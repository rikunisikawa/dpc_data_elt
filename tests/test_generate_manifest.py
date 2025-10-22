"""Tests for tools.generate_manifest utilities."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.generate_manifest import (
    compute_hash,
    detect_records,
    evaluate_target_structure,
    main,
)


def test_evaluate_target_structure_ok(tmp_path: Path) -> None:
    target = tmp_path / "raw" / "yyyymm=2025-04" / "y1"
    target.mkdir(parents=True)

    warnings = evaluate_target_structure(target, "202504", "y1")

    assert warnings == []


def test_evaluate_target_structure_warnings(tmp_path: Path) -> None:
    target = tmp_path / "raw" / "yyyymm=2025-03" / "y3"
    target.mkdir(parents=True)

    warnings = evaluate_target_structure(target, "202504", "y1")

    assert any("file_type" in warning for warning in warnings)
    assert any("Partition" in warning for warning in warnings)


def test_detect_records_with_header(tmp_path: Path) -> None:
    data = tmp_path / "sample.csv"
    data.write_text("col\n1\n2\n", encoding="utf-8")

    assert detect_records(data, has_header=True) == 2
    assert detect_records(data, has_header=False) == 3


def test_compute_hash_sha256(tmp_path: Path) -> None:
    data = tmp_path / "hash.txt"
    data.write_text("hello world\n", encoding="utf-8")

    assert (
        compute_hash(data, "SHA256")
        == "a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447"
    )


def test_main_creates_manifest(tmp_path: Path) -> None:
    target = tmp_path / "raw" / "yyyymm=2025-04" / "y1"
    data = tmp_path / "data.csv"
    data.write_text("col\n1\n", encoding="utf-8")

    exit_code = main(
        [
            str(target),
            "--facility",
            "131000123",
            "--yyyymm",
            "202504",
            "--file-type",
            "y1",
            "--data-file",
            str(data),
            "--has-header",
        ]
    )

    assert exit_code == 0
    manifest_path = target / "_manifest.json"
    assert manifest_path.exists()

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert manifest["yyyymm"] == "202504"
    assert manifest["file_type"] == "y1"
    assert manifest["facility_cd"] == "131000123"
    assert manifest["records"] == 1
    assert manifest["hash"]["algorithm"] == "SHA256"
    assert "value" in manifest["hash"]


def test_main_strict_path_enforces_structure(tmp_path: Path) -> None:
    target = tmp_path / "unexpected"
    data = tmp_path / "data.csv"
    data.write_text("col\n1\n", encoding="utf-8")

    exit_code = main(
        [
            str(target),
            "--facility",
            "131000123",
            "--yyyymm",
            "202504",
            "--file-type",
            "y1",
            "--data-file",
            str(data),
            "--has-header",
            "--strict-path",
        ]
    )

    assert exit_code == 1
    assert not (target / "_manifest.json").exists()

