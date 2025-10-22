#!/usr/bin/env python3
"""Utility to generate `_manifest.json` files for DPC raw uploads."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import sys
from typing import Optional

FILE_TYPES = {"y1", "y3", "y4", "ef_in", "ef_out", "d", "h", "k"}
HASH_ALGORITHMS = {"MD5": hashlib.md5, "SHA256": hashlib.sha256}


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a manifest JSON file that follows docs/03_s3_naming.md.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("target", type=pathlib.Path, help="Directory that will contain _manifest.json")
    parser.add_argument("--facility", required=True, help="9 digit facility code")
    parser.add_argument("--yyyymm", required=True, help="Month in YYYYMM format")
    parser.add_argument("--file-type", required=True, choices=sorted(FILE_TYPES))
    parser.add_argument("--records", type=int, help="Number of records in the uploaded file(s)")
    parser.add_argument("--data-file", type=pathlib.Path, help="Source file used to compute hash/records")
    parser.add_argument("--has-header", action="store_true", help="Treat the first line of --data-file as a header when counting records")
    parser.add_argument("--hash-algorithm", choices=sorted(HASH_ALGORITHMS.keys()), default="SHA256")
    parser.add_argument("--hash-value", help="Explicit hash value. Overrides --data-file hash computation")
    parser.add_argument("--notes", help="Optional notes field")
    parser.add_argument(
        "--created-at",
        help="ISO 8601 timestamp. Defaults to current local time",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Allow overwriting an existing _manifest.json",
    )
    return parser.parse_args(argv)


def validate_facility(facility: str) -> None:
    if len(facility) != 9 or not facility.isdigit():
        raise ValueError("Facility code must be a 9 digit string.")


def validate_month(yyyymm: str) -> None:
    if len(yyyymm) != 6 or not yyyymm.isdigit():
        raise ValueError("yyyymm must be a 6 digit string (YYYYMM).")
    dt.datetime.strptime(yyyymm, "%Y%m")


def detect_records(data_file: pathlib.Path, has_header: bool) -> int:
    with data_file.open("r", encoding="utf-8") as fh:
        count = sum(1 for _ in fh)
    if has_header and count > 0:
        count -= 1
    return count


def compute_hash(data_file: pathlib.Path, algorithm: str) -> str:
    hash_func = HASH_ALGORITHMS[algorithm]()
    with data_file.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            hash_func.update(chunk)
    return hash_func.hexdigest()


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)

    try:
        validate_facility(args.facility)
        validate_month(args.yyyymm)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    target_dir: pathlib.Path = args.target
    target_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = target_dir / "_manifest.json"

    if manifest_path.exists() and not args.overwrite:
        print(f"Error: {manifest_path} already exists. Use --overwrite to replace it.", file=sys.stderr)
        return 1

    records = args.records
    if records is None:
        if args.data_file is None:
            print("Error: --records or --data-file must be provided.", file=sys.stderr)
            return 1
        if not args.data_file.exists():
            print(f"Error: data file not found: {args.data_file}", file=sys.stderr)
            return 1
        records = detect_records(args.data_file, args.has_header)

    if records < 0:
        print("Error: records must be non-negative.", file=sys.stderr)
        return 1

    if args.hash_value:
        hash_value = args.hash_value
    else:
        if args.data_file is None:
            print("Error: provide --hash-value or --data-file to compute hash.", file=sys.stderr)
            return 1
        if not args.data_file.exists():
            print(f"Error: data file not found: {args.data_file}", file=sys.stderr)
            return 1
        hash_value = compute_hash(args.data_file, args.hash_algorithm)

    created_at = args.created_at
    if created_at is None:
        created_at = dt.datetime.now(dt.timezone.utc).astimezone().isoformat()

    manifest = {
        "yyyymm": args.yyyymm,
        "file_type": args.file_type,
        "facility_cd": args.facility,
        "records": records,
        "hash": {
            "algorithm": args.hash_algorithm,
            "value": hash_value,
        },
        "created_at": created_at,
    }

    if args.notes:
        manifest["notes"] = args.notes

    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Manifest written to {manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
