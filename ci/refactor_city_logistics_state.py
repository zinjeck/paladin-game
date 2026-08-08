#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# WorldData: keep the legacy API surface, but make logistics fields accessors
# onto the active settlement-owned CityLogisticsState.
# ---------------------------------------------------------------------------
world_path = ROOT / "scripts/world/simulation/WorldData.gd"
world = world_path.read_text(encoding="utf-8")

world = replace_once(
    world,
    """static var city_ground_piles: Array = []\nstatic var city_ground_pile_index_by_id: Dictionary = {}\nstatic var next_city_ground_pile_id: int = 1\n\n# One atomic reservation binds a citizen to source goods and matching shared\n# capacity at one destination. Aggregate lookups keep availability checks O(1)\n# while the full records remain available for validation and debug inspection.\nstatic var city_haul_reservations: Dictionary = {}\nstatic var city_haul_reservation_id_by_citizen_id: Dictionary = {}\nstatic var city_haul_source_reserved_amount_by_key: Dictionary = {}\nstatic var city_haul_destination_reserved_amount_by_key: Dictionary = {}\nstatic var next_city_haul_reservation_id: int = 1\n""",
    """# Physical logistics storage is settlement-owned. These temporary accessors\n# preserve the historical WorldData API while callers are migrated in the next\n# pass; switching the active settlement changes which CityLogisticsState they\n# resolve to instead of copying logistics registries through WorldData.\nstatic var city_ground_piles: Array:\n\tget:\n\t\treturn WorldPoliticalState.get_current_city_logistics_state().ground_piles\n\tset(value):\n\t\tWorldPoliticalState.get_current_city_logistics_state().ground_piles = value\nstatic var city_ground_pile_index_by_id: Dictionary:\n\tget:\n\t\treturn WorldPoliticalState.get_current_city_logistics_state().ground_pile_index_by_id\n\tset(value):\n\t\tWorldPoliticalState.get_current_city_logistics_state().ground_pile_index_by_id = value\nstatic var next_city_ground_pile_id: int:\n\tget:\n\t\treturn WorldPoliticalState.get_current_city_logistics_state().next_ground_pile_id\n\tset(value):\n\t\tWorldPoliticalState.get_current_city_logistics_state().next_ground_pile_id = value\n\n# One atomic reservation binds a citizen to source goods and matching shared\n# capacity at one destination. Aggregate lookups keep availability checks O(1)\n# while the full records remain available for validation and debug inspection.\nstatic var city_haul_reservations: Dictionary:\n\tget:\n\t\treturn WorldPoliticalState.get_current_city_logistics_state().haul_reservations\n\tset(value):\n\t\tWorldPoliticalState.get_current_city_logistics_state().haul_reservations = value\nstatic var city_haul_reservation_id_by_citizen_id: Dictionary:\n\tget:\n\t\treturn WorldPoliticalState.get_current_city_logistics_state().haul_reservation_id_by_citizen_id\n\tset(value):\n\t\tWorldPoliticalState.get_current_city_logistics_state().haul_reservation_id_by_citizen_id = value\nstatic var city_haul_source_reserved_amount_by_key: Dictionary:\n\tget:\n\t\treturn WorldPoliticalState.get_current_city_logistics_state().haul_source_reserved_amount_by_key\n\tset(value):\n\t\tWorldPoliticalState.get_current_city_logistics_state().haul_source_reserved_amount_by_key = value\nstatic var city_haul_destination_reserved_amount_by_key: Dictionary:\n\tget:\n\t\treturn WorldPoliticalState.get_current_city_logistics_state().haul_destination_reserved_amount_by_key\n\tset(value):\n\t\tWorldPoliticalState.get_current_city_logistics_state().haul_destination_reserved_amount_by_key = value\nstatic var next_city_haul_reservation_id: int:\n\tget:\n\t\treturn WorldPoliticalState.get_current_city_logistics_state().next_haul_reservation_id\n\tset(value):\n\t\tWorldPoliticalState.get_current_city_logistics_state().next_haul_reservation_id = value\n""",
    "WorldData logistics registry declarations",
)

world = replace_once(
    world,
    """static var city_workplace_version: int = 0\nstatic var city_ground_pile_version: int = 0\nstatic var city_haul_reservation_version: int = 0\nstatic var city_construction_version: int = 0\n""",
    """static var city_workplace_version: int = 0\nstatic var city_ground_pile_version: int:\n\tget:\n\t\treturn WorldPoliticalState.get_current_city_logistics_state().ground_pile_version\n\tset(value):\n\t\tWorldPoliticalState.get_current_city_logistics_state().ground_pile_version = value\nstatic var city_haul_reservation_version: int:\n\tget:\n\t\treturn WorldPoliticalState.get_current_city_logistics_state().haul_reservation_version\n\tset(value):\n\t\tWorldPoliticalState.get_current_city_logistics_state().haul_reservation_version = value\nstatic var city_construction_version: int = 0\n""",
    "WorldData logistics versions",
)
world_path.write_text(world, encoding="utf-8")


# ---------------------------------------------------------------------------
# WorldPoliticalState: own a pre-context logistics state and adopt it exactly
# once into the founding city, mirroring the proven work-state bootstrap seam.
# ---------------------------------------------------------------------------
political_path = ROOT / "scripts/world/simulation/WorldPoliticalState.gd"
political = political_path.read_text(encoding="utf-8")

political = replace_once(
    political,
    """const CityWorkStateScript = preload(\n\t\"res://scripts/city/simulation/CityWorkState.gd\"\n)\n""",
    """const CityWorkStateScript = preload(\n\t\"res://scripts/city/simulation/CityWorkState.gd\"\n)\nconst CityLogisticsStateScript = preload(\n\t\"res://scripts/city/simulation/CityLogisticsState.gd\"\n)\n""",
    "WorldPoliticalState logistics preload",
)

political = replace_once(
    political,
    """var _foundation_world_fingerprint: String = \"\"\nvar _unbound_city_work_state = CityWorkStateScript.new()\n""",
    """var _foundation_world_fingerprint: String = \"\"\nvar _unbound_city_work_state = CityWorkStateScript.new()\nvar _unbound_city_logistics_state = CityLogisticsStateScript.new()\n""",
    "WorldPoliticalState unbound logistics state",
)

political = replace_once(
    political,
    """\t_foundation_world_fingerprint = \"\"\n\t_unbound_city_work_state = CityWorkStateScript.new()\n""",
    """\t_foundation_world_fingerprint = \"\"\n\t_unbound_city_work_state = CityWorkStateScript.new()\n\t_unbound_city_logistics_state = CityLogisticsStateScript.new()\n""",
    "WorldPoliticalState reset unbound logistics state",
)

political = replace_once(
    political,
    """\tvar should_adopt_unbound_work_state := not _has_live_foundation_registry()\n\tvar unbound_work_state_to_adopt = _unbound_city_work_state\n\n\treset_state()\n""",
    """\tvar should_adopt_unbound_work_state := not _has_live_foundation_registry()\n\tvar unbound_work_state_to_adopt = _unbound_city_work_state\n\tvar unbound_logistics_state_to_adopt = _unbound_city_logistics_state\n\n\treset_state()\n""",
    "WorldPoliticalState preserve unbound logistics state",
)

political = replace_once(
    political,
    """\tif should_adopt_unbound_work_state:\n\t\tcapital_state.work_state = unbound_work_state_to_adopt\n\tcapital_state.capture_from_world_data()\n""",
    """\tif should_adopt_unbound_work_state:\n\t\tcapital_state.work_state = unbound_work_state_to_adopt\n\t\tcapital_state.logistics_state = unbound_logistics_state_to_adopt\n\tcapital_state.capture_from_world_data()\n""",
    "WorldPoliticalState adopt founding logistics state",
)

political = replace_once(
    political,
    """func get_current_city_work_state() -> CityWorkState:\n\tvar active_city_state = get_active_city_simulation_state()\n\tif (\n\t\tactive_city_state != null\n\t\tand active_city_state.work_state is CityWorkState\n\t):\n\t\treturn active_city_state.work_state\n\treturn _unbound_city_work_state\n\n\n# WorldData still owns the legacy city-session reset entry point while local\n""",
    """func get_current_city_work_state() -> CityWorkState:\n\tvar active_city_state = get_active_city_simulation_state()\n\tif (\n\t\tactive_city_state != null\n\t\tand active_city_state.work_state is CityWorkState\n\t):\n\t\treturn active_city_state.work_state\n\treturn _unbound_city_work_state\n\n\nfunc get_current_city_logistics_state() -> CityLogisticsState:\n\tvar active_city_state = get_active_city_simulation_state()\n\tif (\n\t\tactive_city_state != null\n\t\tand active_city_state.logistics_state is CityLogisticsState\n\t):\n\t\treturn active_city_state.logistics_state\n\treturn _unbound_city_logistics_state\n\n\n# WorldData still owns the legacy city-session reset entry point while local\n""",
    "WorldPoliticalState logistics resolver",
)
political_path.write_text(political, encoding="utf-8")


# ---------------------------------------------------------------------------
# Isolation regression: prove two cities own distinct logistics objects and
# that the legacy WorldData fields transparently resolve to the active city.
# ---------------------------------------------------------------------------
isolation_path = ROOT / "scripts/city/simulation/CitySettlementStateIsolationTest.gd"
isolation = isolation_path.read_text(encoding="utf-8")

isolation = replace_once(
    isolation,
    """\t_expect(\n\t\tplayer_state.work_state is CityWorkState,\n\t\t\"Every city state must own a dedicated work-state subsystem.\"\n\t)\n\n\t# Give the player city unmistakable local state. WorldData remains a\n""",
    """\t_expect(\n\t\tplayer_state.work_state is CityWorkState,\n\t\t\"Every city state must own a dedicated work-state subsystem.\"\n\t)\n\t_expect(\n\t\tplayer_state.logistics_state is CityLogisticsState,\n\t\t\"Every city state must own a dedicated logistics-state subsystem.\"\n\t)\n\n\t# Give the player city unmistakable local state. WorldData remains a\n""",
    "Isolation player logistics state assertion",
)

isolation = replace_once(
    isolation,
    """\tCityWorkSystem.get_current_work_state().next_work_order_id = 72\n\tCityWorkSystem.get_current_work_state().work_order_version = 8\n\n\tvar cpu_culture := WorldData.create_culture(CPU_CULTURE_NAME)\n""",
    """\tCityWorkSystem.get_current_work_state().next_work_order_id = 72\n\tCityWorkSystem.get_current_work_state().work_order_version = 8\n\tWorldData.city_ground_piles = [\n\t\t{\"id\": 81, \"test_owner\": \"player\"},\n\t]\n\tWorldData.city_ground_pile_index_by_id = {81: 0}\n\tWorldData.next_city_ground_pile_id = 82\n\tWorldData.city_ground_pile_version = 10\n\tWorldData.city_haul_reservations = {\n\t\t91: {\"id\": 91, \"citizen_id\": 1, \"test_owner\": \"player\"},\n\t}\n\tWorldData.city_haul_reservation_id_by_citizen_id = {1: 91}\n\tWorldData.city_haul_source_reserved_amount_by_key = {\"player:source\": 3}\n\tWorldData.city_haul_destination_reserved_amount_by_key = {\"player:destination\": 3}\n\tWorldData.next_city_haul_reservation_id = 92\n\tWorldData.city_haul_reservation_version = 11\n\n\tvar cpu_culture := WorldData.create_culture(CPU_CULTURE_NAME)\n""",
    "Isolation player logistics fixture",
)

isolation = replace_once(
    isolation,
    """\t_expect(\n\t\tcpu_state.work_state is CityWorkState\n\t\tand cpu_state.work_state != player_state.work_state,\n\t\t\"Two cities must never share the same work-state object.\"\n\t)\n\n\t_expect(\n""",
    """\t_expect(\n\t\tcpu_state.work_state is CityWorkState\n\t\tand cpu_state.work_state != player_state.work_state,\n\t\t\"Two cities must never share the same work-state object.\"\n\t)\n\t_expect(\n\t\tcpu_state.logistics_state is CityLogisticsState\n\t\tand cpu_state.logistics_state != player_state.logistics_state,\n\t\t\"Two cities must never share the same logistics-state object.\"\n\t)\n\n\t_expect(\n""",
    "Isolation distinct logistics state assertion",
)

isolation = replace_once(
    isolation,
    """\t_expect(\n\t\tCityWorkSystem.get_current_work_state().player_commands.is_empty()\n\t\tand CityWorkSystem.get_current_work_state().work_orders.is_empty()\n\t\tand CityWorkSystem.get_current_work_state().next_player_command_id == 1\n\t\tand CityWorkSystem.get_current_work_state().next_work_order_id == 1,\n\t\t\"A fresh city must begin with an independent work-state subsystem.\"\n\t)\n\n\tvar cpu_context = WorldPoliticalState.get_active_settlement_context()\n""",
    """\t_expect(\n\t\tCityWorkSystem.get_current_work_state().player_commands.is_empty()\n\t\tand CityWorkSystem.get_current_work_state().work_orders.is_empty()\n\t\tand CityWorkSystem.get_current_work_state().next_player_command_id == 1\n\t\tand CityWorkSystem.get_current_work_state().next_work_order_id == 1,\n\t\t\"A fresh city must begin with an independent work-state subsystem.\"\n\t)\n\t_expect(\n\t\tWorldData.city_ground_piles.is_empty()\n\t\tand WorldData.city_haul_reservations.is_empty()\n\t\tand WorldData.next_city_ground_pile_id == 1\n\t\tand WorldData.next_city_haul_reservation_id == 1\n\t\tand WorldData.city_ground_pile_version == 0\n\t\tand WorldData.city_haul_reservation_version == 0,\n\t\t\"A fresh city must begin with an independent logistics-state subsystem.\"\n\t)\n\n\tvar cpu_context = WorldPoliticalState.get_active_settlement_context()\n""",
    "Isolation fresh logistics assertion",
)

isolation = replace_once(
    isolation,
    """\tCityWorkSystem.get_current_work_state().next_work_order_id = 22\n\tCityWorkSystem.get_current_work_state().work_order_version = 16\n\n\t_expect(\n\t\tWorldPoliticalState.set_active_settlement(player_city_id),\n""",
    """\tCityWorkSystem.get_current_work_state().next_work_order_id = 22\n\tCityWorkSystem.get_current_work_state().work_order_version = 16\n\tWorldData.city_ground_piles = [\n\t\t{\"id\": 31, \"test_owner\": \"cpu\"},\n\t]\n\tWorldData.city_ground_pile_index_by_id = {31: 0}\n\tWorldData.next_city_ground_pile_id = 32\n\tWorldData.city_ground_pile_version = 18\n\tWorldData.city_haul_reservations = {\n\t\t41: {\"id\": 41, \"citizen_id\": 2, \"test_owner\": \"cpu\"},\n\t}\n\tWorldData.city_haul_reservation_id_by_citizen_id = {2: 41}\n\tWorldData.city_haul_source_reserved_amount_by_key = {\"cpu:source\": 5}\n\tWorldData.city_haul_destination_reserved_amount_by_key = {\"cpu:destination\": 5}\n\tWorldData.next_city_haul_reservation_id = 42\n\tWorldData.city_haul_reservation_version = 19\n\n\t_expect(\n\t\tWorldPoliticalState.set_active_settlement(player_city_id),\n""",
    "Isolation CPU logistics fixture",
)

isolation = replace_once(
    isolation,
    """\t_expect(\n\t\tstr(CityWorkSystem.get_current_work_state().player_commands[0].get(\"test_owner\", \"\")) == \"player\"\n\t\tand CityWorkSystem.get_current_work_state().next_player_command_id == 42\n\t\tand CityWorkSystem.get_current_work_state().player_command_version == 6\n\t\tand CityWorkSystem.get_current_work_state().work_orders.has(71)\n\t\tand CityWorkSystem.get_current_work_state().next_work_order_id == 72\n\t\tand CityWorkSystem.get_current_work_state().work_order_version == 8,\n\t\t\"Returning to the player city must restore its independent work state.\"\n\t)\n\n\t_expect(\n\t\tWorldPoliticalState.set_active_settlement(cpu_city_id),\n""",
    """\t_expect(\n\t\tstr(CityWorkSystem.get_current_work_state().player_commands[0].get(\"test_owner\", \"\")) == \"player\"\n\t\tand CityWorkSystem.get_current_work_state().next_player_command_id == 42\n\t\tand CityWorkSystem.get_current_work_state().player_command_version == 6\n\t\tand CityWorkSystem.get_current_work_state().work_orders.has(71)\n\t\tand CityWorkSystem.get_current_work_state().next_work_order_id == 72\n\t\tand CityWorkSystem.get_current_work_state().work_order_version == 8,\n\t\t\"Returning to the player city must restore its independent work state.\"\n\t)\n\t_expect(\n\t\tstr(WorldData.city_ground_piles[0].get(\"test_owner\", \"\")) == \"player\"\n\t\tand WorldData.next_city_ground_pile_id == 82\n\t\tand WorldData.city_ground_pile_version == 10\n\t\tand WorldData.city_haul_reservations.has(91)\n\t\tand WorldData.next_city_haul_reservation_id == 92\n\t\tand WorldData.city_haul_reservation_version == 11,\n\t\t\"Returning to the player city must restore its independent logistics state.\"\n\t)\n\n\t_expect(\n\t\tWorldPoliticalState.set_active_settlement(cpu_city_id),\n""",
    "Isolation restore player logistics assertion",
)

isolation = replace_once(
    isolation,
    """\t_expect(\n\t\tstr(CityWorkSystem.get_current_work_state().player_commands[0].get(\"test_owner\", \"\")) == \"cpu\"\n\t\tand CityWorkSystem.get_current_work_state().next_player_command_id == 12\n\t\tand CityWorkSystem.get_current_work_state().player_command_version == 14\n\t\tand CityWorkSystem.get_current_work_state().work_orders.has(21)\n\t\tand CityWorkSystem.get_current_work_state().next_work_order_id == 22\n\t\tand CityWorkSystem.get_current_work_state().work_order_version == 16,\n\t\t\"Reactivating the CPU city must restore its own independent work state.\"\n\t)\n\t_expect(\n\t\tWorldPoliticalState.validate_registry_integrity(),\n""",
    """\t_expect(\n\t\tstr(CityWorkSystem.get_current_work_state().player_commands[0].get(\"test_owner\", \"\")) == \"cpu\"\n\t\tand CityWorkSystem.get_current_work_state().next_player_command_id == 12\n\t\tand CityWorkSystem.get_current_work_state().player_command_version == 14\n\t\tand CityWorkSystem.get_current_work_state().work_orders.has(21)\n\t\tand CityWorkSystem.get_current_work_state().next_work_order_id == 22\n\t\tand CityWorkSystem.get_current_work_state().work_order_version == 16,\n\t\t\"Reactivating the CPU city must restore its own independent work state.\"\n\t)\n\t_expect(\n\t\tstr(WorldData.city_ground_piles[0].get(\"test_owner\", \"\")) == \"cpu\"\n\t\tand WorldData.next_city_ground_pile_id == 32\n\t\tand WorldData.city_ground_pile_version == 18\n\t\tand WorldData.city_haul_reservations.has(41)\n\t\tand WorldData.next_city_haul_reservation_id == 42\n\t\tand WorldData.city_haul_reservation_version == 19,\n\t\t\"Reactivating the CPU city must restore its own independent logistics state.\"\n\t)\n\t_expect(\n\t\tWorldPoliticalState.validate_registry_integrity(),\n""",
    "Isolation restore CPU logistics assertion",
)
isolation_path.write_text(isolation, encoding="utf-8")


# ---------------------------------------------------------------------------
# Static guardrail: WorldData may expose compatibility accessors during this
# migration, but must not regain physical logistics storage.
# ---------------------------------------------------------------------------
audit_path = ROOT / "ci/audit_gdscript.py"
audit = audit_path.read_text(encoding="utf-8")

audit = replace_once(
    audit,
    """WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS = (\n""",
    """WORLD_DATA_CITY_LOGISTICS_COMPATIBILITY_FIELDS = {\n    \"city_ground_piles\": \"ground_piles\",\n    \"city_ground_pile_index_by_id\": \"ground_pile_index_by_id\",\n    \"next_city_ground_pile_id\": \"next_ground_pile_id\",\n    \"city_ground_pile_version\": \"ground_pile_version\",\n    \"city_haul_reservations\": \"haul_reservations\",\n    \"city_haul_reservation_id_by_citizen_id\": \"haul_reservation_id_by_citizen_id\",\n    \"city_haul_source_reserved_amount_by_key\": \"haul_source_reserved_amount_by_key\",\n    \"city_haul_destination_reserved_amount_by_key\": \"haul_destination_reserved_amount_by_key\",\n    \"next_city_haul_reservation_id\": \"next_haul_reservation_id\",\n    \"city_haul_reservation_version\": \"haul_reservation_version\",\n}\n\nWORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS = (\n""",
    "Audit logistics compatibility field map",
)

audit = replace_once(
    audit,
    """    world_data_path = ROOT / \"scripts/world/simulation/WorldData.gd\"\n    if world_data_path.exists():\n        world_data_text = world_data_path.read_text(encoding=\"utf-8\")\n        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS:\n""",
    """    world_data_path = ROOT / \"scripts/world/simulation/WorldData.gd\"\n    if world_data_path.exists():\n        world_data_text = world_data_path.read_text(encoding=\"utf-8\")\n        for symbol, state_field in WORLD_DATA_CITY_LOGISTICS_COMPATIBILITY_FIELDS.items():\n            if re.search(\n                rf\"^\\s*static\\s+var\\s+{re.escape(symbol)}\\b[^\\n]*=\",\n                world_data_text,\n                re.MULTILINE,\n            ):\n                errors.append(\n                    \"scripts/world/simulation/WorldData.gd: city logistics storage \"\n                    f\"must not return to WorldData: {symbol}\"\n                )\n            resolver = (\n                \"WorldPoliticalState.get_current_city_logistics_state().\"\n                + state_field\n            )\n            if world_data_text.count(resolver) < 2:\n                errors.append(\n                    \"scripts/world/simulation/WorldData.gd: logistics compatibility \"\n                    f\"field must forward getter/setter to settlement state: {symbol}\"\n                )\n\n        settlement_state_path = (\n            ROOT / \"scripts/city/simulation/CitySettlementSimulationState.gd\"\n        )\n        if settlement_state_path.exists():\n            settlement_state_text = settlement_state_path.read_text(encoding=\"utf-8\")\n            legacy_storage_declarations = (\n                \"var ground_piles:\",\n                \"var ground_pile_index_by_id:\",\n                \"var next_ground_pile_id:\",\n                \"var ground_pile_version:\",\n                \"var haul_reservations:\",\n                \"var haul_reservation_id_by_citizen_id:\",\n                \"var haul_source_reserved_amount_by_key:\",\n                \"var haul_destination_reserved_amount_by_key:\",\n                \"var next_haul_reservation_id:\",\n                \"var haul_reservation_version:\",\n            )\n            for declaration in legacy_storage_declarations:\n                if declaration in settlement_state_text:\n                    errors.append(\n                        \"scripts/city/simulation/CitySettlementSimulationState.gd: \"\n                        \"logistics storage must live in CityLogisticsState, not \"\n                        f\"the settlement root: {declaration}\"\n                    )\n\n        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS:\n""",
    "Audit logistics storage ownership guard",
)
audit_path.write_text(audit, encoding="utf-8")

print("City logistics state extraction transform completed.")
