#!/usr/bin/env python3
"""One-shot PR 7 codemod for closing citizen no-target compatibility paths.

The script is deliberately narrow: it changes only citizen production systems
and the structural assertions that describe their state gateway. It refuses to
complete while the settlement-locality guard still finds any PR 7 scope.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPAT = "CityCitizenUnboundCompatibility.get_city_state()"

TARGETS = (
    "scripts/citizens/simulation/systems/CityAssignmentSystem.gd",
    "scripts/citizens/simulation/systems/CityEmploymentSystem.gd",
    "scripts/citizens/simulation/systems/CitizenNeedsSystem.gd",
    "scripts/citizens/simulation/systems/CitizenDecisionSystem.gd",
    "scripts/citizens/simulation/systems/CitizenTaskSystem.gd",
    "scripts/citizens/simulation/systems/CitizenHaulingSystem.gd",
)

CURRENT_RESOLVERS = {
    "get_current_city_simulation_state": "",
    "get_current_city_world": "city_world",
    "get_current_city_seed": "city_seed",
    "get_current_city_runtime_data": "city_runtime_data",
    "get_current_city_object_state": "object_state",
    "get_current_city_resource_accounting_state": "resource_accounting_state",
    "get_current_city_citizen_registry_state": "citizen_registry_state",
    "get_current_city_assignment_state": "assignment_state",
    "get_current_city_workplace_state": "workplace_state",
    "get_current_city_citizen_spatial_state": "citizen_spatial_state",
    "get_current_city_citizen_movement_runtime_state": "citizen_movement_runtime_state",
    "get_current_city_citizen_task_runtime_state": "citizen_task_runtime_state",
    "get_current_city_citizen_decision_runtime_state": "citizen_decision_runtime_state",
    "get_current_city_work_state": "work_state",
    "get_current_city_logistics_state": "logistics_state",
    "get_current_city_construction_state": "construction_state",
    "get_current_city_navigation_state": "navigation_state",
}

CURRENT_STATE_CALLS = {
    "CityCitizenRegistrySystem": "citizen_registry_state",
    "CityAssignmentSystem": "assignment_state",
    "CityEmploymentSystem": "workplace_state",
    "CityCitizenSpatialSystem": "citizen_spatial_state",
    "CityCitizenMovementRuntimeSystem": "citizen_movement_runtime_state",
    "CityCitizenTaskRuntimeSystem": "citizen_task_runtime_state",
    "CitizenDecisionSystem": "citizen_decision_runtime_state",
}

PRIVATE_NULL_FIRST_ARGUMENT = re.compile(
    r"(\b_[A-Za-z_][A-Za-z0-9_]*\(\s*)null(?=\s*[,\)])",
    re.MULTILINE,
)


def replace_current_resolvers(text: str) -> str:
    for resolver, field in CURRENT_RESOLVERS.items():
        replacement = COMPAT if not field else f"{COMPAT}.{field}"
        text = re.sub(
            rf"WorldPoliticalState\s*\.\s*{re.escape(resolver)}\s*\(\s*\)",
            replacement,
            text,
        )

    for system_name, field in CURRENT_STATE_CALLS.items():
        text = re.sub(
            rf"{re.escape(system_name)}\s*\.\s*get_current_state\s*\(\s*\)",
            f"{COMPAT}.{field}",
            text,
        )

    return text


def close_no_target_wrappers(text: str) -> str:
    return PRIVATE_NULL_FIRST_ARGUMENT.sub(
        rf"\1{COMPAT}",
        text,
    )


def update_audit(text: str) -> str:
    old_comment = (
        "# Pass 8 makes the focused citizen systems the only public behavior gateways.\n"
        "# The state classes remain data-only owners, while WorldPoliticalState remains\n"
        "# the one low-level resolver behind each system's typed get_current_state API."
    )
    new_comment = (
        "# Citizen behavior systems retain temporary no-target compatibility only through\n"
        "# CityCitizenUnboundCompatibility. Production settlement paths use explicit owners,\n"
        "# and presentation selection is never a gameplay-state resolver."
    )
    text = text.replace(old_comment, new_comment)

    old_gateway = '''        resolver = str(config["resolver"])
        if not re.search(
            rf"return\\s+WorldPoliticalState\\s*\\.\\s*"
            rf"{re.escape(resolver)}\\s*\\(\\s*\\)",
            system_text,
        ):
            errors.append(
                f"{config['path']}: get_current_state must route through "
                f"WorldPoliticalState.{resolver}()"
            )
'''
    new_gateway = '''        resolver = str(config["resolver"])
        compatibility_property = resolver.removeprefix("get_current_city_")
        compatibility_gateway_patterns = (
            rf"return\\s+_get_compatibility_city_state\\s*\\(\\s*\\)\\s*\\.\\s*"
            rf"{re.escape(compatibility_property)}\\b",
            rf"return\\s+CityCitizenUnboundCompatibility\\s*\\.\\s*"
            rf"get_city_state\\s*\\(\\s*\\)\\s*\\.\\s*"
            rf"{re.escape(compatibility_property)}\\b",
        )
        if not any(
            re.search(pattern, system_text)
            for pattern in compatibility_gateway_patterns
        ):
            errors.append(
                f"{config['path']}: get_current_state must route through the "
                f"unbound compatibility owner .{compatibility_property}"
            )
'''
    if old_gateway not in text:
        raise RuntimeError("Could not locate the citizen state-gateway audit block")
    text = text.replace(old_gateway, new_gateway, 1)

    old_inventory = '''            requires_registry_routing
            and "CityCitizenRegistrySystem.get_current_state()"
            not in system_text
        ):
            errors.append(
                f"{system_relative}: embedded citizen state must route through "
                "CityCitizenRegistrySystem.get_current_state()"
            )
'''
    new_inventory = '''            requires_registry_routing
            and (
                "CityCitizenUnboundCompatibility.get_city_state().citizen_registry_state"
                not in system_text
            )
        ):
            errors.append(
                f"{system_relative}: embedded citizen compatibility must route "
                "through the unbound citizen-registry owner"
            )
'''
    if old_inventory not in text:
        raise RuntimeError("Could not locate the embedded citizen-state audit block")
    text = text.replace(old_inventory, new_inventory, 1)
    return text


def load_locality_guard():
    guard_path = ROOT / "ci/settlement_locality_guard.py"
    spec = importlib.util.spec_from_file_location("settlement_locality_guard", guard_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load settlement locality guard")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def assert_pr7_zero() -> None:
    guard = load_locality_guard()
    remaining = []
    citizens_root = ROOT / "scripts/citizens/simulation"
    for path in sorted(citizens_root.rglob("*.gd")):
        if path.name.endswith("Test.gd"):
            continue
        relative = path.relative_to(ROOT).as_posix()
        for hit in guard.scan_text(relative, path.read_text(encoding="utf-8")):
            remaining.append(f"{hit.path}:{hit.line}:{hit.scope}:{hit.token}")
    if remaining:
        raise RuntimeError(
            "PR 7 locality scopes remain after codemod:\n  "
            + "\n  ".join(remaining)
        )


def main() -> int:
    changed_paths: list[str] = []
    for relative in TARGETS:
        path = ROOT / relative
        original = path.read_text(encoding="utf-8")
        updated = close_no_target_wrappers(replace_current_resolvers(original))
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed_paths.append(relative)

    audit_path = ROOT / "ci/audit_gdscript.py"
    audit_original = audit_path.read_text(encoding="utf-8")
    audit_updated = update_audit(audit_original)
    if audit_updated != audit_original:
        audit_path.write_text(audit_updated, encoding="utf-8")
        changed_paths.append("ci/audit_gdscript.py")

    assert_pr7_zero()
    print("PR 7 codemod completed with zero citizen-domain locality scopes.")
    for relative in changed_paths:
        print(f"  changed: {relative}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
