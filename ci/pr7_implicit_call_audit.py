#!/usr/bin/env python3
"""Report legacy no-target citizen API calls that still have explicit variants."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SYSTEMS_DIR = ROOT / "scripts/citizens/simulation/systems"

SYSTEM_FILES = {
    path.stem: path
    for path in SYSTEMS_DIR.glob("*.gd")
}
FUNC_RE = re.compile(r"^static func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.MULTILINE)


def collect_legacy_pairs() -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}
    for system_name, path in SYSTEM_FILES.items():
        names = set(FUNC_RE.findall(path.read_text(encoding="utf-8")))
        legacy = {
            name
            for name in names
            if not name.endswith("_for_city_state")
            and f"{name}_for_city_state" in names
        }
        if legacy:
            result[system_name] = legacy
    return result


def main() -> int:
    pairs = collect_legacy_pairs()
    findings: list[tuple[str, int, str, str]] = []
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        relative = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        for system_name, legacy_names in pairs.items():
            if path == SYSTEM_FILES.get(system_name):
                continue
            for name in sorted(legacy_names):
                pattern = re.compile(
                    rf"\b{re.escape(system_name)}\s*\.\s*{re.escape(name)}\s*\("
                )
                for match in pattern.finditer(text):
                    line = text.count("\n", 0, match.start()) + 1
                    scope = "test" if path.name.endswith("Test.gd") else "production"
                    findings.append((scope, line, relative, f"{system_name}.{name}"))

    for scope, line, relative, call in findings:
        print(f"{scope}\t{relative}:{line}\t{call}")
    production_count = sum(1 for finding in findings if finding[0] == "production")
    test_count = len(findings) - production_count
    print(
        f"SUMMARY production={production_count} test={test_count} total={len(findings)}"
    )
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
