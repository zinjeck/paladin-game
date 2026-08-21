#!/usr/bin/env python3

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = ROOT / "scripts"

# Pass 9 closes the baseline-era escape hatches completely. There is no path,
# validator, helper, or exact-scope allowlist: any production hit is an error.
FORBIDDEN_TOKENS = (
    "WorldPoliticalState.active_settlement_id",
    "WorldPoliticalState.get_active_settlement(",
    "WorldPoliticalState.get_active_city_simulation_state(",
    "WorldPoliticalState.get_current_city_",
    ".get_current_state(",
    "CityWorkSystem.get_current_work_state(",
    "WorldData.has_active_city_save(",
    "WorldData.store_city_world_save(",
    "WorldData.reset_player_city_state(",
)

EXPLICIT_SCOPE_MARKERS = (
    "_for_city_state",
    "_for_settlement",
    "_for_context",
)

FUNC_RE = re.compile(
    r"^\s*(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("
)


@dataclass(frozen=True)
class Hit:
    path: str
    scope: str
    token: str
    line: int

    @property
    def key(self) -> str:
        return make_key(self.path, self.scope, self.token)


def make_key(path: str, scope: str, token: str) -> str:
    return f"{path}::{scope}::{token}"


def strip_comments_and_strings(text: str) -> str:
    """Remove comments and string contents while preserving line structure."""
    out: list[str] = []
    in_string = False
    quote = ""
    escaped = False
    index = 0
    while index < len(text):
        character = text[index]
        if in_string:
            out.append("\n" if character == "\n" else " ")
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                in_string = False
                quote = ""
            index += 1
            continue
        if character in ('"', "'"):
            in_string = True
            quote = character
            out.append(" ")
            index += 1
            continue
        if character == "#":
            while index < len(text) and text[index] != "\n":
                out.append(" ")
                index += 1
            continue
        out.append(character)
        index += 1
    return "".join(out)


def function_scope_by_line(text: str) -> list[str]:
    scopes: list[str] = []
    current = "<top-level>"
    for line in text.splitlines():
        match = FUNC_RE.match(line)
        if match:
            current = match.group(1)
        scopes.append(current)
    return scopes


def scan_text(path: str, text: str) -> list[Hit]:
    sanitized = strip_comments_and_strings(text)
    scopes = function_scope_by_line(sanitized)
    hits: list[Hit] = []
    for line_number, line in enumerate(sanitized.splitlines(), start=1):
        scope = scopes[line_number - 1] if scopes else "<top-level>"
        for token in FORBIDDEN_TOKENS:
            start = 0
            while True:
                index = line.find(token, start)
                if index < 0:
                    break
                hits.append(Hit(path, scope, token, line_number))
                start = index + len(token)
    return hits


def is_explicit_target_scope(scope: str) -> bool:
    return any(marker in scope for marker in EXPLICIT_SCOPE_MARKERS)


def production_scripts() -> list[Path]:
    return sorted(
        path
        for path in SCRIPTS_ROOT.rglob("*.gd")
        if not path.name.endswith("Test.gd")
    )


def inventory(hits: list[Hit]) -> tuple[dict[str, int], dict[str, Hit]]:
    counts: dict[str, int] = {}
    first_hits: dict[str, Hit] = {}
    for hit in hits:
        counts[hit.key] = counts.get(hit.key, 0) + 1
        first_hits.setdefault(hit.key, hit)
    return counts, first_hits


def run_self_tests() -> list[str]:
    failures: list[str] = []
    ordinary = (
        "func legacy_reader() -> void:\n"
        "\tvar state = WorldPoliticalState.get_active_city_simulation_state()\n"
    )
    ordinary_hits = scan_text("scripts/session/Synthetic.gd", ordinary)
    if len(ordinary_hits) != 1:
        failures.append("synthetic forbidden reference was not detected exactly once")

    explicit = (
        "func run_tick_for_city_state(city_state) -> void:\n"
        "\tvar state = WorldPoliticalState.get_active_city_simulation_state()\n"
    )
    explicit_hits = scan_text("scripts/session/Explicit.gd", explicit)
    if len(explicit_hits) != 1 or not is_explicit_target_scope(explicit_hits[0].scope):
        failures.append("explicit-target reference was not detected")

    inert = (
        "func harmless() -> void:\n"
        "\t# WorldPoliticalState.active_settlement_id\n"
        "\tvar example = \"WorldPoliticalState.get_current_city_world()\"\n"
    )
    if scan_text("scripts/session/Inert.gd", inert):
        failures.append("comments/string literals created locality false positives")
    return failures


def main() -> int:
    failures = run_self_tests()
    if failures:
        print("Settlement locality guard self-test failures:")
        for failure in failures:
            print(f"  ERROR: {failure}")
        return 1

    hits: list[Hit] = []
    paths = production_scripts()
    for path in paths:
        relative = path.relative_to(ROOT).as_posix()
        hits.extend(scan_text(relative, path.read_text(encoding="utf-8")))

    counts, first_hits = inventory(hits)
    print(
        f"Settlement locality guard scanned {len(paths)} production GDScript files; "
        f"references={len(hits)} across {len(counts)} exact scopes."
    )
    if hits:
        print(f"Settlement locality violations: {len(hits)}")
        for key in sorted(counts):
            hit = first_hits[key]
            print(
                f"  ERROR: {hit.path}:{hit.line}: {hit.scope} uses retired "
                f"implicit settlement authority via {hit.token} "
                f"({counts[key]} occurrence(s))"
            )
        return 1

    print("Settlement locality guard passed with no grandfathered scopes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
