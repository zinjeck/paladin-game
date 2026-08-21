#!/usr/bin/env python3

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

from settlement_locality_guard import strip_comments_and_strings


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = ROOT / "scripts"

# Pass 9 retires these names from definitions and callers alike. Comments and
# strings are stripped before scanning so documentation cannot hide a live
# compatibility surface or create a false positive.
FORBIDDEN_COMPATIBILITY_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "CityCitizenUnboundCompatibility",
        re.compile(r"\bCityCitizenUnboundCompatibility\b"),
    ),
    ("_unbound_city_*", re.compile(r"\b_unbound_city_[A-Za-z0-9_]*\b")),
    ("get_current_city_*", re.compile(r"\bget_current_city_[A-Za-z0-9_]*\b")),
    ("set_current_city_*", re.compile(r"\bset_current_city_[A-Za-z0-9_]*\b")),
    (
        "replace_current_city_*",
        re.compile(r"\breplace_current_city_[A-Za-z0-9_]*\b"),
    ),
    # Camera persistence is presentation/session state and intentionally keeps
    # the descriptive `store_current_city_camera_state` name.  The retired
    # gameplay backend exposed only this exact world-storage entry point.
    ("store_current_city_world", re.compile(r"\bstore_current_city_world\b")),
    ("clear_current_city_*", re.compile(r"\bclear_current_city_[A-Za-z0-9_]*\b")),
    (
        "active gameplay context accessor",
        re.compile(
            r"\b(?:get_active_city_simulation_state|get_active_settlement_context|"
            r"get_player_capital_city_simulation_state)\b"
        ),
    ),
    (
        "no-target system state accessor",
        re.compile(r"\b(?:get_current_state|get_current_work_state)\b"),
    ),
    (
        "legacy fixture binding",
        re.compile(r"\b(?:bind_legacy_fixture_state|clear_legacy_fixture_state)\b"),
    ),
)

# Presentation selection is intentionally process-wide, but only the political
# registry and GameSession may publish/read it in production. Tests may select B
# while explicitly operating on A to prove locality; they are checked above for
# gameplay-owner discovery rather than forbidden from presenting a settlement.
ACTIVE_SELECTION_PRODUCTION_OWNERS = {
    "scripts/world/simulation/WorldPoliticalState.gd",
    "scripts/session/GameSession.gd",
}
ACTIVE_SELECTION_PATTERN = re.compile(
    r"\bWorldPoliticalState\s*\.\s*(?:active_settlement_id|"
    r"get_active_settlement|get_presented_settlement_id|set_active_settlement)\b"
)
ACTIVE_ID_GAMEPLAY_RESOLUTION_PATTERN = re.compile(
    r"\b(?:get_city_simulation_state|get_settlement_context)\s*\(\s*"
    r"active_settlement_id\b"
)

# Every remaining mutable production static has an explicit architectural
# classification. The guard fails closed: a new static var must either become
# instance-owned/const or be added here with a reviewable ownership reason.
STATIC_CLASSIFICATIONS: dict[str, dict[str, str]] = {
    "scripts/session/GameSession.gd": {
        "_next_session_starts_in_city": "legitimate global world/session state",
    },
    "scripts/map/MapCameraSessionState.gd": {
        "has_world_camera_state": "legitimate global world/session state",
        "world_camera_position": "legitimate global world/session state",
        "world_camera_zoom": "legitimate global world/session state",
        "city_camera_state_by_settlement_id": "settlement-keyed presentation/session state",
        "city_camera_recency": "settlement-keyed presentation/session state",
    },
    "scripts/map/visuals/MapTextureCacheState.gd": {
        "world_mode_textures": "exact-source-keyed non-authoritative cache",
        "world_source_ref": "exact-source-keyed non-authoritative cache",
        "world_source_instance_id": "exact-source-keyed non-authoritative cache",
        "world_seed": "exact-source-keyed non-authoritative cache",
        "world_size": "exact-source-keyed non-authoritative cache",
        "world_tile_data_version": "exact-source-keyed non-authoritative cache",
        "world_visual_version": "exact-source-keyed non-authoritative cache",
        "city_mode_textures": "exact-source-keyed non-authoritative cache",
        "city_source_ref": "exact-source-keyed non-authoritative cache",
        "city_source_instance_id": "exact-source-keyed non-authoritative cache",
        "city_seed": "exact-source-keyed non-authoritative cache",
        "city_size": "exact-source-keyed non-authoritative cache",
        "city_tile_data_version": "exact-source-keyed non-authoritative cache",
        "city_visual_version": "exact-source-keyed non-authoritative cache",
    },
    "scripts/world/simulation/WorldData.gd": {
        "city_start_world_seed": "legitimate global world/session state",
        "city_start_region_center": "legitimate global world/session state",
        "city_start_region_top_left": "legitimate global world/session state",
        "city_start_region_size": "legitimate global world/session state",
        "city_start_tiles": "legitimate global world/session state",
        "city_return_world_scene_path": "legitimate global world/session state",
        "save_locked": "legitimate global world/session state",
        "player_city_foundation_top_left": "legitimate global world/session state",
        "player_city_foundation_size": "legitimate global world/session state",
        "official_world": "legitimate global world/session state",
        "player_city_founded": "legitimate global world/session state",
        "debug_mode_enabled": "legitimate global world/session state",
        "cultures": "legitimate global world/session state",
        "culture_index_by_id": "legitimate global world/session state",
        "next_culture_id": "legitimate global world/session state",
        "official_city_name": "legitimate global world/session state",
        "official_founding_culture_id": "legitimate global world/session state",
        "official_selected_region_center": "legitimate global world/session state",
        "official_selected_region_top_left": "legitimate global world/session state",
        "official_region_size": "legitimate global world/session state",
        "official_world_scene_path": "legitimate global world/session state",
        "official_city_scene_path": "legitimate global world/session state",
    },
    "scripts/city/simulation/CityStateValidator.gd": {
        "_cache_by_settlement_id": "exact-source-keyed non-authoritative cache",
        "_cache_recency": "exact-source-keyed non-authoritative cache",
    },
    "scripts/map/visuals/SettlementNaturalFeaturePresenter.gd": {
        "shared_feature_resources": "immutable configuration",
        "cache_by_settlement_id": "exact-source-keyed non-authoritative cache",
        "cache_recency": "settlement-keyed presentation/session state",
    },
    "scripts/ui/debug/DebugPanel.gd": {
        "_debug_enable_sequence": "legitimate global world/session state",
    },
    "scripts/city/data/CityObjectCatalog.gd": {
        "_city_object_definitions": "immutable configuration",
        "_storage_resource_lookup_by_object_type": "immutable configuration",
    },
    "scripts/city/data/CityResourceCatalog.gd": {
        "_city_resource_types": "immutable configuration",
        "_city_food_resource_types": "immutable configuration",
        "_city_resource_type_lookup": "immutable configuration",
    },
    "scripts/city/simulation/systems/WorkplaceProductionSystem.gd": {
        "_resource_source_evaluation_cache": "exact-source-keyed non-authoritative cache",
        "_preview_resource_source_evaluation_cache": "exact-source-keyed non-authoritative cache",
    },
}

ALLOWED_STATIC_CLASSIFICATIONS = {
    "authoritative settlement-local state",
    "settlement-keyed presentation/session state",
    "exact-source-keyed non-authoritative cache",
    "immutable configuration",
    "legitimate global world/session state",
}

STATIC_VAR_RE = re.compile(
    r"^\s*static\s+var\s+([A-Za-z_][A-Za-z0-9_]*)\b",
    re.MULTILINE,
)


def all_scripts() -> list[Path]:
    return sorted(SCRIPTS_ROOT.rglob("*.gd"))


def production_scripts() -> list[Path]:
    return [path for path in all_scripts() if not path.name.endswith("Test.gd")]


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def main() -> int:
    errors: list[str] = []
    compatibility_hits = 0
    scripts = all_scripts()

    for path in scripts:
        path_relative = relative(path)
        sanitized = strip_comments_and_strings(path.read_text(encoding="utf-8"))
        for label, pattern in FORBIDDEN_COMPATIBILITY_PATTERNS:
            for match in pattern.finditer(sanitized):
                compatibility_hits += 1
                errors.append(
                    f"{path_relative}:{line_number(sanitized, match.start())}: "
                    f"retired Pass 9 compatibility surface: {label}"
                )

    for path in production_scripts():
        path_relative = relative(path)
        sanitized = strip_comments_and_strings(path.read_text(encoding="utf-8"))
        if path_relative not in ACTIVE_SELECTION_PRODUCTION_OWNERS:
            for match in ACTIVE_SELECTION_PATTERN.finditer(sanitized):
                errors.append(
                    f"{path_relative}:{line_number(sanitized, match.start())}: "
                    "active settlement selection is presentation/session identity only"
                )
        for match in ACTIVE_ID_GAMEPLAY_RESOLUTION_PATTERN.finditer(sanitized):
            errors.append(
                f"{path_relative}:{line_number(sanitized, match.start())}: "
                "presentation active_settlement_id must not resolve gameplay owners"
            )

    classified_counts: Counter[str] = Counter()
    observed_static_keys: set[tuple[str, str]] = set()
    for path in production_scripts():
        path_relative = relative(path)
        text = path.read_text(encoding="utf-8")
        for match in STATIC_VAR_RE.finditer(text):
            name = match.group(1)
            observed_static_keys.add((path_relative, name))
            classification = STATIC_CLASSIFICATIONS.get(path_relative, {}).get(name)
            if classification is None:
                errors.append(
                    f"{path_relative}:{line_number(text, match.start())}: mutable "
                    f"production static {name} has no Pass 9 ownership classification"
                )
                continue
            if classification not in ALLOWED_STATIC_CLASSIFICATIONS:
                errors.append(
                    f"{path_relative}:{line_number(text, match.start())}: mutable "
                    f"production static {name} has unknown Pass 9 classification "
                    f"{classification!r}"
                )
                continue
            classified_counts[classification] += 1

    for path_relative, names in STATIC_CLASSIFICATIONS.items():
        for name, classification in names.items():
            if classification not in ALLOWED_STATIC_CLASSIFICATIONS:
                errors.append(
                    f"{path_relative}: {name} uses unknown Pass 9 static "
                    f"classification {classification!r}"
                )
            if (path_relative, name) not in observed_static_keys:
                errors.append(
                    f"{path_relative}: stale Pass 9 static classification for {name}"
                )

    print(
        f"Pass 9 zero-unbound guard scanned {len(scripts)} GDScript files; "
        f"compatibility references={compatibility_hits}."
    )
    print(
        "Mutable production static classifications: "
        + ", ".join(
            f"{category}={count}"
            for category, count in sorted(classified_counts.items())
        )
    )

    if errors:
        print(f"Pass 9 zero-unbound violations: {len(errors)}")
        for error in errors:
            print(f"  ERROR: {error}")
        return 1

    print("Pass 9 zero-unbound compatibility guard passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
