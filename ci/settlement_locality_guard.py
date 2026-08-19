#!/usr/bin/env python3

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = ROOT / "scripts"
BASELINE_SHA = "f4dfa02f906ca924f403256ebdac60904673f45a"

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


@dataclass(frozen=True)
class LegacyMetadata:
    reason: str
    remove_in: str


def make_key(path: str, scope: str, token: str) -> str:
    return f"{path}::{scope}::{token}"


def strip_comments_and_strings(text: str) -> str:
    """Remove comments and string contents while preserving line structure."""
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


def git_text(*args: str) -> str:
    completed = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return completed.stdout


def baseline_script_paths() -> list[str]:
    listing = git_text("ls-tree", "-r", "--name-only", BASELINE_SHA, "scripts")
    return sorted(
        path
        for path in listing.splitlines()
        if path.endswith(".gd") and not path.endswith("Test.gd")
    )


def read_baseline_file(path: str) -> str:
    return git_text("show", f"{BASELINE_SHA}:{path}")


def inventory(hits: list[Hit]) -> tuple[dict[str, int], dict[str, Hit]]:
    counts: dict[str, int] = {}
    first_hits: dict[str, Hit] = {}
    for hit in hits:
        counts[hit.key] = counts.get(hit.key, 0) + 1
        first_hits.setdefault(hit.key, hit)
    return counts, first_hits


def legacy_metadata(hit: Hit) -> LegacyMetadata | None:
    path = hit.path
    if path == "scripts/city/rendering/CityRenderer.gd":
        return LegacyMetadata(
            "CityRenderer still contains active/current-city presentation and bootstrap compatibility paths.",
            "PR 4",
        )
    if path.startswith("scripts/city/simulation/validators/") or path == "scripts/city/simulation/CityStateValidator.gd":
        return LegacyMetadata(
            "Validator code still resolves the globally current city and must be made target-local.",
            "PR 5",
        )
    if path.startswith("scripts/ui/city/") or path.startswith("scripts/citizens/rendering/"):
        return LegacyMetadata(
            "Renderer-owned UI/debug/presentation helper still discovers current settlement state.",
            "PR 6",
        )
    if path.startswith("scripts/citizens/simulation/"):
        return LegacyMetadata(
            "Citizen-domain compatibility API still resolves current settlement state.",
            "PR 7",
        )
    if path.startswith("scripts/city/simulation/systems/"):
        return LegacyMetadata(
            "City-system compatibility API still resolves current settlement state.",
            "PR 8",
        )
    if path in (
        "scripts/world/simulation/WorldData.gd",
        "scripts/session/GameSession.gd",
    ):
        return LegacyMetadata(
            "World/session bridge still exposes active-city resolution while explicit target APIs are being closed.",
            "PR 8",
        )
    if path == "scripts/world/simulation/WorldPoliticalState.gd":
        return LegacyMetadata(
            "Current/unbound city compatibility remains in the political/session registry until final retirement.",
            "PR 9",
        )
    return None


def run_self_tests() -> list[str]:
    failures: list[str] = []
    ordinary = (
        "func legacy_reader() -> void:\n"
        "\tvar state = WorldPoliticalState.get_active_city_simulation_state()\n"
    )
    ordinary_hits = scan_text("scripts/session/Synthetic.gd", ordinary)
    if len(ordinary_hits) != 1:
        failures.append("synthetic forbidden reference was not detected exactly once")
    else:
        current_counts, _ = inventory(ordinary_hits)
        baseline_counts = {ordinary_hits[0].key: 1}
        if current_counts[ordinary_hits[0].key] > baseline_counts[ordinary_hits[0].key]:
            failures.append("baseline legacy reference was not accepted")
        if baseline_counts.get("missing", 0) != 0:
            failures.append("missing baseline entry self-test is invalid")

    explicit = (
        "func run_tick_for_city_state(city_state) -> void:\n"
        "\tvar state = WorldPoliticalState.get_active_city_simulation_state()\n"
    )
    explicit_hits = scan_text("scripts/session/Explicit.gd", explicit)
    if len(explicit_hits) != 1 or not is_explicit_target_scope(explicit_hits[0].scope):
        failures.append("explicit-target reference did not trigger the hard locality rule")

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

    try:
        baseline_paths = baseline_script_paths()
    except subprocess.CalledProcessError as error:
        print(
            "Settlement locality guard could not read its immutable baseline commit. "
            "CI must checkout enough history to include " + BASELINE_SHA
        )
        print(error.stderr)
        return 1

    baseline_hits: list[Hit] = []
    for path in baseline_paths:
        baseline_hits.extend(scan_text(path, read_baseline_file(path)))
    baseline_counts, _baseline_first_hits = inventory(baseline_hits)

    current_hits: list[Hit] = []
    current_paths = production_scripts()
    for path in current_paths:
        relative = path.relative_to(ROOT).as_posix()
        current_hits.extend(scan_text(relative, path.read_text(encoding="utf-8")))
    current_counts, current_first_hits = inventory(current_hits)

    errors: list[str] = []
    for key in sorted(current_counts):
        hit = current_first_hits[key]
        actual_count = current_counts[key]
        if is_explicit_target_scope(hit.scope):
            errors.append(
                f"{hit.path}:{hit.line}: explicit-target function {hit.scope} uses "
                f"implicit settlement authority via {hit.token}; explicit-target "
                "paths can never be grandfathered"
            )
            continue

        baseline_count = baseline_counts.get(key, 0)
        if baseline_count == 0:
            errors.append(
                f"{hit.path}:{hit.line}: new implicit settlement authority in "
                f"{hit.scope} via {hit.token}; exact scope was not present in baseline"
            )
            continue
        if actual_count > baseline_count:
            errors.append(
                f"{hit.path}:{hit.line}: implicit settlement authority count grew in "
                f"{hit.scope} via {hit.token}; baseline={baseline_count} current={actual_count}"
            )
            continue

        metadata = legacy_metadata(hit)
        if metadata is None:
            errors.append(
                f"{hit.path}:{hit.line}: legacy locality scope has no documented owner/removal pass"
            )

    remaining_legacy_keys = [
        key for key, count in current_counts.items() if count > 0 and key in baseline_counts
    ]
    removed_keys = [
        key for key, count in baseline_counts.items() if count > 0 and key not in current_counts
    ]

    print(
        f"Settlement locality guard scanned {len(current_paths)} production GDScript files."
    )
    print(
        f"Immutable baseline {BASELINE_SHA[:12]} contains {len(baseline_hits)} tracked "
        f"references across {len(baseline_counts)} exact scopes."
    )
    print(
        f"Current tree contains {len(current_hits)} tracked references across "
        f"{len(current_counts)} exact scopes; {len(removed_keys)} baseline scopes have been removed."
    )

    if errors:
        print(f"Settlement locality violations: {len(errors)}")
        for error in errors:
            print(f"  ERROR: {error}")
        return 1

    by_pass: dict[str, int] = {}
    for key in remaining_legacy_keys:
        hit = current_first_hits[key]
        metadata = legacy_metadata(hit)
        if metadata is not None:
            by_pass[metadata.remove_in] = by_pass.get(metadata.remove_in, 0) + 1
    pass_summary = ", ".join(
        f"{name}={count}" for name, count in sorted(by_pass.items())
    )
    print(
        "Settlement locality guard passed. Remaining grandfathered exact scopes: "
        f"{len(remaining_legacy_keys)} ({pass_summary})."
    )

    # Keep the ratchet inspectable: CI now prints every remaining exact scope,
    # grouped implicitly by the pass recorded in legacy_metadata(). This is a
    # permanent audit surface, not a permissive allowlist or a temporary probe.
    for key in sorted(remaining_legacy_keys):
        hit = current_first_hits[key]
        metadata = legacy_metadata(hit)
        if metadata is None:
            continue
        print(
            f"  REMAINING [{metadata.remove_in}] {hit.path}:{hit.line} "
            f"{hit.scope} via {hit.token}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
