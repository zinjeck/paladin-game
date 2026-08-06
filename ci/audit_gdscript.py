#!/usr/bin/env python3
"""Repository-wide structural audit for Paladin's Godot source.

Godot remains the source of truth for parsing. This script adds fast checks that
are easy to miss in runtime smoke tests and emits maintainability metrics for
all scripts on every pull request.
"""

from __future__ import annotations

import collections
import hashlib
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
QUEUE_REDRAW_RE = re.compile(r"\bqueue_redraw\b")
COMMENT_LINE_RE = re.compile(r"^\s*#(?!region\b|endregion\b)(.*)$", re.IGNORECASE)

FORBIDDEN_REPOSITORY_ARTIFACT_SUFFIXES = {
    ".bak",
    ".backup",
    ".log",
    ".old",
    ".orig",
    ".tmp",
    ".zip",
}
SUSPICIOUS_TEXT_FILE_PARTS = (
    "noop",
    "backup",
    "copy",
    "temporary",
    "temp_",
    "_temp",
    "old_",
    "_old",
)
AUDIT_EXCLUDED_DIRECTORIES = {".git", ".godot", "ci-logs"}
MINIMUM_DUPLICATE_FUNCTION_BODY_LINES = 10
MINIMUM_DUPLICATE_COMMENT_LENGTH = 28

ALLOWED_QUEUE_REDRAW_CALLS = {
    "scripts/city/rendering/CityRenderLayer.gd": 1,
    "scripts/ui/city/CityInformationPanel.gd": 2,
}


@dataclass(frozen=True)
class FunctionMetric:
    path: str
    name: str
    start_line: int
    line_count: int


def script_paths() -> list[Path]:
    return sorted(ROOT.glob("scripts/**/*.gd"))


def repository_file_paths() -> list[Path]:
    return sorted(
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and not any(part in AUDIT_EXCLUDED_DIRECTORIES for part in path.parts)
    )


def normalized_function_body_groups(text: str) -> dict[str, list[tuple[str, int]]]:
    lines = text.splitlines()
    starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = FUNC_LINE_RE.match(line)
        if match:
            starts.append((index, match.group(1)))

    groups: dict[str, list[tuple[str, int]]] = collections.defaultdict(list)
    for position, (start, name) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        normalized_lines: list[str] = []
        for line in lines[start + 1 : end]:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            normalized_lines.append(re.sub(r"\s+", " ", stripped))

        if len(normalized_lines) < MINIMUM_DUPLICATE_FUNCTION_BODY_LINES:
            continue

        digest = hashlib.sha256("\n".join(normalized_lines).encode("utf-8")).hexdigest()
        groups[digest].append((name, start + 1))

    return groups


def duplicate_substantial_comments(text: str) -> list[tuple[str, list[int]]]:
    occurrences: dict[str, list[int]] = collections.defaultdict(list)
    for line_number, line in enumerate(text.splitlines(), start=1):
        match = COMMENT_LINE_RE.match(line)
        if not match:
            continue
        normalized = re.sub(r"\s+", " ", match.group(1).strip())
        if len(normalized) >= MINIMUM_DUPLICATE_COMMENT_LENGTH:
            occurrences[normalized].append(line_number)

    return [
        (comment, line_numbers)
        for comment, line_numbers in occurrences.items()
        if len(line_numbers) > 1
    ]


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

    repository_files = repository_file_paths()
    content_hash_owners: dict[str, list[str]] = collections.defaultdict(list)

    for path in repository_files:
        relative = str(path.relative_to(ROOT))
        suffix = path.suffix.lower()
        lower_name = path.name.lower()

        if suffix in FORBIDDEN_REPOSITORY_ARTIFACT_SUFFIXES:
            errors.append(
                f"{relative}: repository artifact with forbidden suffix {suffix}"
            )
        elif suffix == ".txt" and any(
            marker in lower_name for marker in SUSPICIOUS_TEXT_FILE_PARTS
        ):
            errors.append(f"{relative}: suspicious temporary text artifact")

        if path.stat().st_size <= 2_000_000:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            content_hash_owners[digest].append(relative)

    for owners in content_hash_owners.values():
        if len(owners) > 1:
            errors.append(
                "Duplicate repository file contents: " + ", ".join(sorted(owners))
            )

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

        for body_group in normalized_function_body_groups(text).values():
            if len(body_group) <= 1:
                continue
            locations = ", ".join(
                f"{name}@{line_number}" for name, line_number in body_group
            )
            errors.append(
                f"{relative}: duplicate substantial function bodies: {locations}"
            )

        for comment, line_numbers in duplicate_substantial_comments(text):
            errors.append(
                f"{relative}: repeated substantial comment at lines "
                f"{', '.join(str(line) for line in line_numbers)}: {comment}"
            )

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

        redraw_call_count = len(QUEUE_REDRAW_RE.findall(text))
        allowed_redraw_calls = ALLOWED_QUEUE_REDRAW_CALLS.get(relative, 0)
        if redraw_call_count > allowed_redraw_calls:
            errors.append(
                f"{relative}: contains {redraw_call_count} queue_redraw references; "
                f"only {allowed_redraw_calls} are approved"
            )

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

    map_cache_path = ROOT / "scripts/map/cache/MapTextureCache.gd"
    if map_cache_path.exists():
        map_cache_text = map_cache_path.read_text(encoding="utf-8")
        forbidden_staggered_terms = (
            "warmup_running",
            "process_warmup",
            "start_warmup",
            "finish_warmup",
            "_warmup_next_row",
            "_warmup_images",
        )
        for term in forbidden_staggered_terms:
            if term in map_cache_text:
                errors.append(
                    "scripts/map/cache/MapTextureCache.gd: retired staggered "
                    f"map loading term remains: {term}"
                )

    city_renderer_path = ROOT / "scripts/city/rendering/CityRenderer.gd"
    if city_renderer_path.exists():
        city_renderer_text = city_renderer_path.read_text(encoding="utf-8")
        if "change_scene_to_" in city_renderer_text:
            errors.append(
                "scripts/city/rendering/CityRenderer.gd: city/world switching must "
                "use the persistent GameSession, not scene replacement"
            )

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
