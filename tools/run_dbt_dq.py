#!/usr/bin/env python3
"""Minimal orchestration for running dbt tests and recording DQ failures.

This utility is intended to be triggered from the `dpc-dbt-tests` ECS task
or a Lambda function that has permissions to execute commands inside the
container and to call the Redshift Data API.  It runs ``dbt test --store-failures``
for the configured project, parses the resulting ``run_results.json`` and
``manifest.json`` artifacts, and writes failed test summaries into
``dq.results_yyyymm``.  Optionally a Slack webhook can be notified with the
aggregated outcome.

The implementation focuses on the "minimal" scope described in
``plans/minimal_task_06_data_quality.md`` and ``docs/08_data_quality.md``.
It assumes that each dbt test that should be tracked as a DQ rule defines
metadata in the model YAML, for example::

    tests:
      - unique:
          meta:
            dq_rule_id: PK_DUPLICATE_Y1
            dq_severity: CRITICAL
            dq_note: "様式1 主キー重複"
            dq_facility_column: facility_cd
            dq_sample_key_columns: [data_id]

When ``dq_facility_column`` is present the failure table produced by dbt is
queried via the Redshift Data API so that counts and sample keys can be
grouped per facility.  If it is omitted, a default facility code supplied via
``--default-facility-cd`` is used instead.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import logging
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections import defaultdict
from typing import Any, Dict, Iterable, Iterator, List, Optional

import boto3

LOGGER = logging.getLogger(__name__)


@dataclasses.dataclass
class RuleConfig:
    """Metadata parsed from dbt's manifest for a failing test."""

    rule_id: str
    severity: str
    note: str
    facility_column: Optional[str]
    sample_key_columns: List[str]


@dataclasses.dataclass
class DQResult:
    """Single row that will be inserted into dq.results_yyyymm."""

    facility_cd: str
    yyyymm: str
    rule_id: str
    severity: str
    cnt: int
    sample_keys: Optional[str]
    note: str


class RedshiftDataAPI:
    """Helper for running statements through the Redshift Data API."""

    def __init__(
        self,
        workgroup_name: str,
        database: str,
        db_user: Optional[str] = None,
        secret_arn: Optional[str] = None,
        poll_interval: float = 1.0,
    ) -> None:
        self._client = boto3.client("redshift-data")
        self._workgroup_name = workgroup_name
        self._database = database
        self._db_user = db_user
        self._secret_arn = secret_arn
        self._poll_interval = poll_interval

    def execute(  # noqa: D401 - short description inherited
        self,
        sql: str,
        parameters: Optional[List[Dict[str, Any]]] = None,
        with_results: bool = False,
    ) -> List[Dict[str, Any]]:
        """Execute ``sql`` and optionally return the resulting rows."""

        kwargs = {
            "Database": self._database,
            "Sql": sql,
            "WorkgroupName": self._workgroup_name,
        }
        if self._db_user:
            kwargs["DbUser"] = self._db_user
        if self._secret_arn:
            kwargs["SecretArn"] = self._secret_arn
        if parameters:
            kwargs["Parameters"] = parameters

        LOGGER.debug("Executing SQL: %s", sql)
        response = self._client.execute_statement(**kwargs)
        statement_id = response["Id"]
        status = self._wait_for_statement(statement_id)
        if status != "FINISHED":
            raise RuntimeError(f"Statement {statement_id} failed with status {status}")

        if not with_results:
            return []

        return list(self._yield_rows(statement_id))

    def _wait_for_statement(self, statement_id: str) -> str:
        while True:
            desc = self._client.describe_statement(Id=statement_id)
            status = desc["Status"]
            if status in {"FINISHED", "FAILED", "ABORTED"}:
                LOGGER.debug("Statement %s completed with status %s", statement_id, status)
                return status
            LOGGER.debug("Statement %s running...", statement_id)
            time.sleep(self._poll_interval)

    def _yield_rows(self, statement_id: str) -> Iterator[Dict[str, Any]]:
        next_token: Optional[str] = None
        column_names: Optional[List[str]] = None
        while True:
            kwargs = {"Id": statement_id}
            if next_token:
                kwargs["NextToken"] = next_token
            result = self._client.get_statement_result(**kwargs)
            if column_names is None:
                column_names = [meta["name"] for meta in result["ColumnMetadata"]]
            for record in result.get("Records", []):
                yield {
                    column_names[idx]: self._convert_value(value)
                    for idx, value in enumerate(record)
                }
            next_token = result.get("NextToken")
            if not next_token:
                break

    @staticmethod
    def _convert_value(value: Dict[str, Any]) -> Any:
        if "stringValue" in value:
            return value["stringValue"]
        if "longValue" in value:
            return value["longValue"]
        if "doubleValue" in value:
            return value["doubleValue"]
        if "booleanValue" in value:
            return value["booleanValue"]
        return None


def run_dbt_tests(args: argparse.Namespace) -> int:
    command = ["dbt", "test", "--store-failures"]
    if args.project_dir:
        command.extend(["--project-dir", str(args.project_dir)])
    if args.profiles_dir:
        command.extend(["--profiles-dir", str(args.profiles_dir)])
    if args.target:
        command.extend(["--target", args.target])
    if args.select:
        command.extend(["--select", args.select])
    if args.exclude:
        command.extend(["--exclude", args.exclude])

    LOGGER.info("Running dbt command: %s", " ".join(command))
    process = subprocess.run(command, cwd=args.project_dir, capture_output=True, text=True)
    LOGGER.debug("dbt stdout:\n%s", process.stdout)
    LOGGER.debug("dbt stderr:\n%s", process.stderr)
    if process.returncode not in {0, 1}:
        raise RuntimeError(f"dbt command failed with exit code {process.returncode}")
    return process.returncode


def load_artifact(path: pathlib.Path) -> Dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"Artifact not found: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def extract_rule_config(node: Dict[str, Any]) -> RuleConfig:
    meta = node.get("meta", {})
    rule_id = meta.get("dq_rule_id", node.get("name", node.get("unique_id", "UNKNOWN_RULE")))
    severity = meta.get("dq_severity")
    if severity is None:
        severity = node.get("config", {}).get("severity", "error")
        severity = "CRITICAL" if severity.lower() == "error" else "WARNING"
    note = meta.get("dq_note", node.get("description", ""))
    facility_column = meta.get("dq_facility_column")
    sample_key_columns_raw = meta.get("dq_sample_key_columns", [])
    if isinstance(sample_key_columns_raw, str):
        sample_key_columns = [sample_key_columns_raw]
    else:
        sample_key_columns = list(sample_key_columns_raw)
    return RuleConfig(
        rule_id=rule_id,
        severity=severity,
        note=note,
        facility_column=facility_column,
        sample_key_columns=sample_key_columns,
    )


def gather_failed_results(
    run_results: Dict[str, Any],
    manifest: Dict[str, Any],
    yyyymm: str,
    redshift: RedshiftDataAPI,
    max_sample_keys: int,
    default_facility_cd: str,
) -> List[DQResult]:
    dq_rows: List[DQResult] = []
    for result in run_results.get("results", []):
        status = result.get("status")
        if status == "pass":
            continue
        unique_id = result.get("unique_id")
        node = manifest.get("nodes", {}).get(unique_id)
        if not node:
            LOGGER.warning("Manifest node not found for %s", unique_id)
            continue
        rule_config = extract_rule_config(node)
        failure_relation = _extract_failure_relation(result)
        LOGGER.info("Processing failure %s (%s)", unique_id, failure_relation or "no relation")
        if failure_relation and rule_config.facility_column:
            dq_rows.extend(
                _hydrate_rows_from_relation(
                    redshift=redshift,
                    relation=failure_relation,
                    config=rule_config,
                    yyyymm=yyyymm,
                    max_sample_keys=max_sample_keys,
                )
            )
        else:
            cnt = int(result.get("failures", 0))
            sample_keys = None
            if failure_relation and rule_config.sample_key_columns:
                rows = redshift.execute(
                    sql=_build_sample_query(failure_relation, rule_config.sample_key_columns, max_sample_keys),
                    with_results=True,
                )
                samples = [
                    "-".join(str(row.get(col, "")) for col in rule_config.sample_key_columns)
                    for row in rows
                ]
                if samples:
                    sample_keys = ",".join(samples)
            dq_rows.append(
                DQResult(
                    facility_cd=default_facility_cd,
                    yyyymm=yyyymm,
                    rule_id=rule_config.rule_id,
                    severity=rule_config.severity,
                    cnt=cnt,
                    sample_keys=sample_keys,
                    note=rule_config.note,
                )
            )
    return dq_rows


def _extract_failure_relation(result: Dict[str, Any]) -> Optional[str]:
    adapter_response = result.get("adapter_response") or {}
    relation = adapter_response.get("table") or adapter_response.get("name")
    if relation:
        return relation
    failures = result.get("failures", 0)
    if failures:
        LOGGER.warning("No failure relation found for result %s", result.get("unique_id"))
    return None


def _hydrate_rows_from_relation(
    redshift: RedshiftDataAPI,
    relation: str,
    config: RuleConfig,
    yyyymm: str,
    max_sample_keys: int,
) -> List[DQResult]:
    columns = [config.facility_column]
    columns.extend(col for col in config.sample_key_columns if col not in columns)
    sql = f"SELECT {', '.join(columns)} FROM {relation}"
    rows = redshift.execute(sql=sql, with_results=True)
    grouped: Dict[str, Dict[str, Any]] = defaultdict(lambda: {"cnt": 0, "samples": []})
    for row in rows:
        facility = str(row.get(config.facility_column) or "UNKNOWN")
        grouped_entry = grouped[facility]
        grouped_entry["cnt"] += 1
        if config.sample_key_columns and len(grouped_entry["samples"]) < max_sample_keys:
            sample = "-".join(
                str(row.get(col, "")) for col in config.sample_key_columns
            )
            if sample:
                grouped_entry["samples"].append(sample)

    results: List[DQResult] = []
    for facility, payload in grouped.items():
        sample_keys = payload["samples"][:max_sample_keys]
        results.append(
            DQResult(
                facility_cd=facility,
                yyyymm=yyyymm,
                rule_id=config.rule_id,
                severity=config.severity,
                cnt=payload["cnt"],
                sample_keys=",".join(sample_keys) if sample_keys else None,
                note=config.note,
            )
        )
    return results


def _build_sample_query(relation: str, sample_columns: List[str], max_sample_keys: int) -> str:
    select_cols = ", ".join(sample_columns)
    return f"SELECT {select_cols} FROM {relation} LIMIT {max_sample_keys}"


def persist_results(
    redshift: RedshiftDataAPI,
    results: Iterable[DQResult],
    table: str,
) -> None:
    grouped: Dict[str, List[DQResult]] = defaultdict(list)
    for row in results:
        grouped[row.facility_cd].append(row)

    for facility, facility_rows in grouped.items():
        LOGGER.info("Persisting %d rows for facility %s", len(facility_rows), facility)
        redshift.execute(
            sql=f"DELETE FROM {table} WHERE facility_cd = :facility AND yyyymm = :yyyymm",
            parameters=[
                {"name": "facility", "value": {"stringValue": facility}},
                {"name": "yyyymm", "value": {"stringValue": facility_rows[0].yyyymm}},
            ],
        )
        for row in facility_rows:
            params = [
                {"name": "facility_cd", "value": {"stringValue": row.facility_cd}},
                {"name": "yyyymm", "value": {"stringValue": row.yyyymm}},
                {"name": "rule_id", "value": {"stringValue": row.rule_id}},
                {"name": "severity", "value": {"stringValue": row.severity}},
                {"name": "cnt", "value": {"longValue": row.cnt}},
                {
                    "name": "sample_keys",
                    "value": {"stringValue": row.sample_keys} if row.sample_keys else {"isNull": True},
                },
                {"name": "note", "value": {"stringValue": row.note}},
            ]
            redshift.execute(
                sql=(
                    f"INSERT INTO {table} (facility_cd, yyyymm, rule_id, severity, cnt, sample_keys, note) "
                    "VALUES (:facility_cd, :yyyymm, :rule_id, :severity, :cnt, :sample_keys, :note)"
                ),
                parameters=params,
            )


def notify_slack(webhook_url: str, results: Iterable[DQResult]) -> None:
    summary: Dict[str, Dict[str, int]] = defaultdict(lambda: {"CRITICAL": 0, "WARNING": 0})
    details: Dict[str, List[DQResult]] = defaultdict(list)
    for row in results:
        key = f"{row.facility_cd}-{row.yyyymm}"
        summary[key][row.severity] += row.cnt
        details[key].append(row)

    lines = []
    for key in sorted(summary.keys()):
        facility, yyyymm = key.split("-")
        sev_counts = summary[key]
        lines.append(
            f"施設 {facility} / {yyyymm}: CRITICAL={sev_counts['CRITICAL']} WARNING={sev_counts['WARNING']}"
        )
        for row in details[key]:
            sample_note = f" samples={row.sample_keys}" if row.sample_keys else ""
            lines.append(f" • {row.rule_id} ({row.severity}) cnt={row.cnt}{sample_note}")

    payload = {
        "text": "DQ test failures detected\n" + "\n".join(lines)
    }
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        webhook_url, data=data, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            LOGGER.info("Slack notification sent with status %s", response.status)
    except urllib.error.URLError as exc:
        LOGGER.error("Failed to send Slack notification: %s", exc)


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yyyymm", required=True, help="Target year-month for dq.results_yyyymm")
    parser.add_argument("--project-dir", type=pathlib.Path, default=pathlib.Path("."))
    parser.add_argument("--profiles-dir", type=pathlib.Path)
    parser.add_argument("--target", help="dbt target name")
    parser.add_argument("--select", help="dbt test selection string")
    parser.add_argument("--exclude", help="dbt test exclusion string")
    parser.add_argument("--target-path", type=pathlib.Path, default=pathlib.Path("target"))
    parser.add_argument("--workgroup-name", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--db-user", help="Database user for the Data API")
    parser.add_argument("--secret-arn", help="Secrets Manager ARN for credentials")
    parser.add_argument("--results-table", default="dq.results_yyyymm")
    parser.add_argument(
        "--default-facility-cd",
        default="000000000",
        help="Fallback facility code when failures do not expose a facility column",
    )
    parser.add_argument(
        "--max-sample-keys",
        type=int,
        default=5,
        help="Maximum number of sample keys to persist per facility",
    )
    parser.add_argument("--slack-webhook-url", help="Optional Slack Incoming Webhook URL")
    parser.add_argument(
        "--log-level",
        default=os.environ.get("LOG_LEVEL", "INFO"),
        help="Python logging level",
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=args.log_level, format="%(asctime)s %(levelname)s %(message)s")

    run_dbt_tests(args)

    target_dir = args.project_dir / args.target_path if not args.target_path.is_absolute() else args.target_path
    run_results_path = target_dir / "run_results.json"
    manifest_path = target_dir / "manifest.json"

    run_results = load_artifact(run_results_path)
    manifest = load_artifact(manifest_path)

    redshift = RedshiftDataAPI(
        workgroup_name=args.workgroup_name,
        database=args.database,
        db_user=args.db_user,
        secret_arn=args.secret_arn,
    )

    dq_rows = gather_failed_results(
        run_results=run_results,
        manifest=manifest,
        yyyymm=args.yyyymm,
        redshift=redshift,
        max_sample_keys=args.max_sample_keys,
        default_facility_cd=args.default_facility_cd,
    )

    if not dq_rows:
        LOGGER.info("No DQ failures detected. Nothing to persist.")
        return 0

    persist_results(redshift=redshift, results=dq_rows, table=args.results_table)

    if args.slack_webhook_url:
        notify_slack(args.slack_webhook_url, dq_rows)

    return 0


if __name__ == "__main__":
    sys.exit(main())
