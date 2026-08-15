#!/usr/bin/env python3

from __future__ import annotations

import io
import re
import tokenize
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = ROOT / "scripts"

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

# Ratchet entries describe only legacy production call sites present when this
# guard was introduced. Every key is exact: file + function/property scope +
# forbidden token. Later localization PRs must delete entries as those call
# sites disappear. New production references fail by default.
#
# key: "scripts/path/File.gd::scope_name::forbidden token"
# value: {"max_count": N, "reason": "...", "remove_in": "PR N"}
LEGACY_ALLOWLIST: dict[str, dict[str, object]] = {}

FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")


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
    """Remove comments/string contents while preserving line structure."""
    out: list[str] = []
    in_string = False
    quote = ""
    escaped = False
    i = 0
    while i < len(text):
        ch = text[i]
        if in_string:
            out.append("\n" if ch == "\n" else " ")
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                in_string = False
                quote = ""
            i += 1
            continue
        if ch in ('"', "'"):
            in_string = True
            quote = ch
            out.append(" ")
            i += 1
            continue
        if ch == "#":
            while i < len(text) and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        out.append(ch)
        i += 1
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


def run_self_tests() -> list[str]:
    failures: list[str] = []
    ordinary = (
        "func legacy_reader() -> void:\n"
        "\tvar state = WorldPoliticalState.get_active_city_simulation_state()\n"
    )
    ordinary_hits = scan_text("synthetic.gd", ordinary)
    if len(ordinary_hits) != 1:
        failures.append("synthetic forbidden reference was not detected exactly once")

    allowed_key = make_key(
        "synthetic.gd",
        "legacy_reader",
        "WorldPoliticalState.get_active_city_simulation_state(",
    )
    local_allowlist = {
        allowed_key: {
            "max_count": 1,
            "reason": "self-test legacy path",
            "remove_in": "self-test",
        }
    }
    if ordinary_hits and ordinary_hits[0].key not in local_allowlist:
        failures.append("exact allowlist key did not accept synthetic legacy reference")
    if ordinary_hits and ordinary_hits[0].key in {}:
        failures.append("removed allowlist entry unexpectedly accepted a remaining reference")

    explicit = (
        "func run_tick_for_city_state(city_state) -> void:\n"
        "\tvar state = WorldPoliticalState.get_active_city_simulation_state()\n"
    )
    explicit_hits = scan_text("explicit.gd", explicit)
    if len(explicit_hits) != 1 or not is_explicit_target_scope(explicit_hits[0].scope):
        failures.append("explicit-target reference did not trigger the hard locality rule")

    inert = (
        "func harmless() -> void:\n"
        "\t# WorldPoliticalState.active_settlement_id\n"
        "\tvar example = \"WorldPoliticalState.get_current_city_world()\"\n"
    )
    if scan_text("inert.gd", inert):
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
    for path in production_scripts():
        relative = path.relative_to(ROOT).as_posix()
        hits.extend(scan_text(relative, path.read_text(encoding="utf-8")))

    counts: dict[str, int] = {}
    first_hit_by_key: dict[str, Hit] = {}
    for hit in hits:
        counts[hit.key] = counts.get(hit.key, 0) + 1
        first_hit_by_key.setdefault(hit.key, hit)

    errors: list[str] = []
    used_allowlist: set[str] = set()
    for key in sorted(counts):
        hit = first_hit_by_key[key]
        actual_count = counts[key]
        if is_explicit_target_scope(hit.scope):
            errors.append(
                f"{hit.path}:{hit.line}: explicit-target function {hit.scope} "
                f"uses implicit settlement authority via {hit.token}; "
                "explicit-target paths can never be allowlisted"
            )
            continue
        entry = LEGACY_ALLOWLIST.get(key)
        if entry is None:
            errors.append(
                f"{hit.path}:{hit.line}: unallowlisted implicit settlement authority "
                f"in {hit.scope} via {hit.token}; key={key!r}; count={actual_count}"
            )
            continue
        expected_count = int(entry.get("max_count", 0))
        if actual_count != expected_count:
            errors.append(
                f"{key}: allowlist count drifted; expected={expected_count} "
                f"actual={actual_count}. Shrink the ratchet when legacy paths disappear."
            )
            continue
        if not str(entry.get("reason", "")).strip() or not str(entry.get("remove_in", "")).strip():
            errors.append(f"{key}: allowlist entry must document reason and removal PR")
            continue
        used_allowlist.add(key)

    for key in sorted(LEGACY_ALLOWLIST):
        if key not in used_allowlist and key not in counts:
            errors.append(
                f"{key}: stale allowlist entry has no remaining source reference; remove it"
            )

    print(
        f"Settlement locality guard scanned {len(production_scripts())} production "
        f"GDScript files and found {len(hits)} tracked implicit-resolution references."
    )
    if errors:
        print(f"Settlement locality violations: {len(errors)}")
        for error in errors:
            print(f"  ERROR: {error}")
        return 1

    print(
        f"Settlement locality guard passed with {len(LEGACY_ALLOWLIST)} exact legacy "
        "allowlist scopes."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
