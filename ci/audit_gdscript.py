#!/usr/bin/env python3
"""Repository-wide structural audit for Paladin's Godot source.

Godot remains the source of truth for parsing. This script adds fast checks that
are easy to miss in runtime smoke tests and emits maintainability metrics for
all scripts on every pull request.
"""

from __future__ import annotations

import collections
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOG_DIR = ROOT / "ci-logs"
LOG_DIR.mkdir(exist_ok=True)
REPORT_PATH = LOG_DIR / "static-audit.json"

FUNC_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.MULTILINE)
CLASS_RE = re.compile(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", re.MULTILINE)
RESOURCE_RE = re.compile(r'(["\'])res://([^"\']+)\1')
REGION_RE = re.compile(r"^\s*#region\b", re.MULTILINE)
ENDREGION_RE = re.compile(r"^\s*#endregion\b", re.MULTILINE)
FUNC_LINE_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")


@dataclass(frozen=True)
class FunctionMetric:
    path: str
    name: str
    start_line: int
    line_count: int


def script_paths() -> list[Path]:
    return sorted(ROOT.glob("scripts/**/*.gd"))


def function_metrics(path: Path, text: str) -> list[FunctionMetric]:
    lines = text.splitlines()
    starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = FUNC_LINE_RE.match(line)
        if match:
            starts.append((index, match.group(1)))

    metrics: list[FunctionMetric] = []
    for position, (start, name) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        metrics.append(
            FunctionMetric(
                path=str(path.relative_to(ROOT)),
                name=name,
                start_line=start + 1,
                line_count=max(end - start, 1),
            )
        )
    return metrics


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    class_owners: dict[str, list[str]] = collections.defaultdict(list)
    all_metrics: list[FunctionMetric] = []
    total_lines = 0
    total_functions = 0

    scripts = script_paths()
    if not scripts:
        errors.append("No GDScript files were found under scripts/.")

    for path in scripts:
        relative = str(path.relative_to(ROOT))
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        total_lines += len(lines)

        functions = FUNC_RE.findall(text)
        total_functions += len(functions)
        duplicates = sorted(
            name for name, count in collections.Counter(functions).items() if count > 1
        )
        if duplicates:
            errors.append(f"{relative}: duplicate functions: {', '.join(duplicates)}")

        classes = CLASS_RE.findall(text)
        if len(classes) > 1:
            errors.append(f"{relative}: declares multiple class_name values: {classes}")
        for class_name in classes:
            class_owners[class_name].append(relative)

        region_count = len(REGION_RE.findall(text))
        endregion_count = len(ENDREGION_RE.findall(text))
        if region_count != endregion_count:
            errors.append(
                f"{relative}: #region/#endregion mismatch "
                f"({region_count} vs {endregion_count})"
            )

        for _, resource_path in RESOURCE_RE.findall(text):
            resolved = ROOT / resource_path
            if not resolved.exists():
                errors.append(f"{relative}: missing resource path res://{resource_path}")

        metrics = function_metrics(path, text)
        all_metrics.extend(metrics)
        for metric in metrics:
            if metric.line_count >= 300:
                warnings.append(
                    f"{metric.path}:{metric.start_line} {metric.name} is "
                    f"{metric.line_count} lines"
                )

    for class_name, owners in sorted(class_owners.items()):
        if len(owners) > 1:
            errors.append(f"class_name {class_name} is declared by: {', '.join(owners)}")

    # Validate scene/script resource paths as well as script-local preloads.
    for pattern in ("**/*.tscn", "**/*.tres", "project.godot"):
        paths = [ROOT / "project.godot"] if pattern == "project.godot" else ROOT.glob(pattern)
        for path in paths:
            if not path.is_file() or ".godot" in path.parts:
                continue
            relative = str(path.relative_to(ROOT))
            text = path.read_text(encoding="utf-8")
            for _, resource_path in RESOURCE_RE.findall(text):
                if not (ROOT / resource_path).exists():
                    errors.append(f"{relative}: missing resource path res://{resource_path}")

    largest_files = []
    for path in scripts:
        count = len(path.read_text(encoding="utf-8").splitlines())
        largest_files.append((count, str(path.relative_to(ROOT))))
    largest_files.sort(reverse=True)

    report = {
        "script_count": len(scripts),
        "total_script_lines": total_lines,
        "function_count": total_functions,
        "class_name_count": len(class_owners),
        "error_count": len(errors),
        "warning_count": len(warnings),
        "errors": errors,
        "warnings": warnings,
        "largest_files": [
            {"path": path, "line_count": count} for count, path in largest_files[:15]
        ],
        "largest_functions": [
            {
                "path": metric.path,
                "name": metric.name,
                "start_line": metric.start_line,
                "line_count": metric.line_count,
            }
            for metric in sorted(all_metrics, key=lambda item: item.line_count, reverse=True)[:25]
        ],
    }
    REPORT_PATH.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(
        f"Audited {len(scripts)} scripts, {total_lines:,} lines, "
        f"and {total_functions:,} functions."
    )
    if warnings:
        print(f"Maintainability warnings: {len(warnings)}")
        for warning in warnings[:20]:
            print(f"  WARNING: {warning}")
    if errors:
        print(f"Structural errors: {len(errors)}", file=sys.stderr)
        for error in errors:
            print(f"  ERROR: {error}", file=sys.stderr)
        return 1

    print("Static GDScript and resource audit passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
