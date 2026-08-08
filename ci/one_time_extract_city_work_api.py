from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
WORLD_DATA = ROOT / "scripts/world/simulation/WorldData.gd"
WORK_SYSTEM = ROOT / "scripts/city/simulation/systems/CityWorkSystem.gd"
SETTLEMENT_STATE = ROOT / "scripts/city/simulation/CitySettlementSimulationState.gd"
POLITICAL_STATE = ROOT / "scripts/world/simulation/WorldPoliticalState.gd"
AUDIT = ROOT / "ci/audit_gdscript.py"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def regex_replace_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one regex match, found {count}")
    return updated


world = WORLD_DATA.read_text(encoding="utf-8")
work = WORK_SYSTEM.read_text(encoding="utf-8")
settlement = SETTLEMENT_STATE.read_text(encoding="utf-8")
political = POLITICAL_STATE.read_text(encoding="utf-8")
audit = AUDIT.read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# WorldData: remove the remaining city-work compatibility surface.
# ---------------------------------------------------------------------------
world = regex_replace_once(
    world,
    r"\n# Player designations are authoritative city simulation state\..*?\n# One atomic reservation",
    "\n# One atomic reservation",
    "remove WorldData work collection proxies",
)
world = regex_replace_once(
    world,
    r"\nstatic var city_player_command_version: int:.*?\nstatic var city_haul_reservation_version: int = 0",
    "\nstatic var city_haul_reservation_version: int = 0",
    "remove WorldData work version proxies",
)
world = regex_replace_once(
    world,
    r"\nconst CITY_PLAYER_COMMAND_TYPE_NONE := \"none\".*?const CITY_PLAYER_COMMAND_BLOCKED_RETRY_DELAY_MINUTES: int = 30\n",
    "\n",
    "remove WorldData player-command constants",
)
world = replace_once(
    world,
    "const CITY_CONSTRUCTION_TASK_PRIORITY: int = (\n\tCITY_PLAYER_COMMAND_TASK_PRIORITY\n)",
    "const CITY_CONSTRUCTION_TASK_PRIORITY: int = 1000",
    "decouple construction priority from removed work constant",
)
world = regex_replace_once(
    world,
    r"\n#region Player Command and Work Order State Primitives\n.*?\n#endregion\n\n#region Food Resource Accounting Primitives",
    "\n#region Food Resource Accounting Primitives",
    "remove WorldData work primitive API region",
)
world = replace_once(
    world,
    "\tWorldData.reset_city_work_order_state()\n\tWorldData.reset_city_player_command_state()",
    "\tWorldPoliticalState.reset_extracted_city_state()",
    "route extracted-state reset through ownership registry",
)

# ---------------------------------------------------------------------------
# WorldPoliticalState: provide the generic reset seam for extracted local data.
# ---------------------------------------------------------------------------
political = replace_once(
    political,
    "func get_current_city_work_state():\n\tvar active_city_state = get_active_city_simulation_state()\n\tif (\n\t\tactive_city_state != null\n\t\tand active_city_state.work_state is CityWorkState\n\t):\n\t\treturn active_city_state.work_state\n\treturn _unbound_city_work_state\n\n\nfunc get_polity_snapshot()",
    "func get_current_city_work_state():\n\tvar active_city_state = get_active_city_simulation_state()\n\tif (\n\t\tactive_city_state != null\n\t\tand active_city_state.work_state is CityWorkState\n\t):\n\t\treturn active_city_state.work_state\n\treturn _unbound_city_work_state\n\n\n# WorldData still owns the legacy city-session reset entry point while local\n# subsystems are extracted. Keep that entry point generic: it asks the local\n# ownership registry to reset extracted state without knowing its internals.\nfunc reset_extracted_city_state() -> void:\n\tget_current_city_work_state().reset_all()\n\n\nfunc get_polity_snapshot()",
    "add generic extracted-state reset seam",
)

# ---------------------------------------------------------------------------
# CityWorkSystem: own work constants and all work-state APIs.
# ---------------------------------------------------------------------------
work = replace_once(
    work,
    "# File responsibility: Player-command and work-order operations, scheduling, job generation, assignment, and diagnostics. Authoritative collections remain in WorldData.\n# Navigation regions are organizational only; they do not define runtime ownership.",
    "# File responsibility: Player-command and work-order state access, mutation, scheduling, job generation, assignment, and diagnostics for the active CITY settlement.\n# CityWorkState owns the data; this system owns the behavior. WorldData is not a work-state owner or API surface.",
    "update CityWorkSystem responsibility",
)

work_constants = '''const CITY_PLAYER_COMMAND_TYPE_NONE := "none"
const CITY_PLAYER_COMMAND_TYPE_CHOP_TREE := "chop_tree"
const CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK := "collect_rock"
const CITY_PLAYER_COMMAND_STATUS_PENDING := "pending"
const CITY_PLAYER_COMMAND_STATUS_CLAIMED := "claimed"
const CITY_PLAYER_COMMAND_STATUS_BLOCKED := "blocked"
const CITY_PLAYER_COMMAND_TASK_PRIORITY: int = 1000
# At the default clock rate, six world minutes is three simulation ticks,
# or roughly 2.5 real seconds at normal speed.
const CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES: int = 6
const CITY_PLAYER_COMMAND_RESOURCE_YIELD: int = 4
const CITY_PLAYER_COMMAND_BLOCKED_RETRY_DELAY_MINUTES: int = 30
'''
work = replace_once(
    work,
    '''const CityNavigationSystemScript = preload(
\t"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)

# Parent work orders''',
    '''const CityNavigationSystemScript = preload(
\t"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)

''' + work_constants + '''
# Parent work orders''',
    "insert CityWorkSystem command constants",
)

work_api = r'''static func get_current_work_state() -> CityWorkState:
	return WorldPoliticalState.get_current_city_work_state()


static func _work_state() -> CityWorkState:
	return get_current_work_state()


static func get_city_player_command_types() -> Array[String]:
	return [
		CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
		CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK,
	]


static func is_valid_city_player_command_type(command_type: String) -> bool:
	return get_city_player_command_types().has(command_type)


static func get_city_player_command_surface_feature(command_type: String) -> String:
	match command_type:
		CITY_PLAYER_COMMAND_TYPE_CHOP_TREE:
			return WorldData.CITY_SURFACE_FEATURE_TREE
		CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK:
			return WorldData.CITY_SURFACE_FEATURE_ROCK
	return WorldData.CITY_SURFACE_FEATURE_NONE


static func mark_city_player_commands_changed() -> void:
	_work_state().mark_player_commands_changed()


static func mark_city_work_orders_changed() -> void:
	_work_state().mark_work_orders_changed()


static func reset_city_work_order_state() -> void:
	_work_state().reset_work_orders()


static func reset_city_player_command_state() -> void:
	_work_state().reset_player_commands()


static func get_city_player_command_index_by_id(command_id: int) -> int:
	return _work_state().get_player_command_index_by_id(command_id)


static func get_city_player_command_by_id(command_id: int) -> Dictionary:
	return _work_state().get_player_command_by_id(command_id)


static func is_city_player_command_target_valid(command: Dictionary) -> bool:
	var city_world: WorldData = WorldData.official_city_world
	var command_type := str(
		command.get("type", CITY_PLAYER_COMMAND_TYPE_NONE)
	)
	var raw_tile_position = command.get(
		"tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	if (
		city_world == null
		or not is_valid_city_player_command_type(command_type)
		or not raw_tile_position is Vector2i
	):
		return false

	var tile_position: Vector2i = raw_tile_position
	if not city_world.is_in_bounds(tile_position.x, tile_position.y):
		return false

	return (
		WorldData.get_city_surface_feature(
			city_world.get_tile(tile_position.x, tile_position.y)
		)
		== get_city_player_command_surface_feature(command_type)
	)


static func release_city_player_command_claim(
	command_id: int,
	citizen_id: int,
	blocked_retry_minute: int = -1
) -> bool:
	var work_state := _work_state()
	var command_index := work_state.get_player_command_index_by_id(command_id)
	if command_index < 0:
		return false

	var command: Dictionary = work_state.player_commands[command_index]
	if int(command.get("claimed_citizen_id", -1)) != citizen_id:
		return false

	command["claimed_citizen_id"] = -1
	if blocked_retry_minute >= 0:
		command["status"] = CITY_PLAYER_COMMAND_STATUS_BLOCKED
		command["next_retry_world_minute"] = blocked_retry_minute
	else:
		command["status"] = CITY_PLAYER_COMMAND_STATUS_PENDING
		command["next_retry_world_minute"] = -1

	work_state.player_commands[command_index] = command
	work_state.mark_player_commands_changed()
	return true


'''
work = replace_once(
    work,
    "#region Player Command and Work Order Operations\n",
    work_api + "#region Player Command and Work Order Operations\n",
    "insert CityWorkSystem work-state API",
)

local_replacements = {
    "WorldData.city_player_commands": "_work_state().player_commands",
    "WorldData.city_player_command_index_by_id": "_work_state().player_command_index_by_id",
    "WorldData.city_player_command_id_by_tile": "_work_state().player_command_id_by_tile",
    "WorldData.next_city_player_command_id": "_work_state().next_player_command_id",
    "WorldData.next_city_player_command_group_id": "_work_state().next_player_command_group_id",
    "WorldData.city_player_command_version": "_work_state().player_command_version",
    "WorldData.city_work_orders": "_work_state().work_orders",
    "WorldData.city_work_order_id_by_source_key": "_work_state().work_order_id_by_source_key",
    "WorldData.next_city_work_order_id": "_work_state().next_work_order_id",
    "WorldData.city_work_order_version": "_work_state().work_order_version",
    "WorldData._mark_city_player_commands_changed()": "mark_city_player_commands_changed()",
    "WorldData.mark_city_work_orders_changed()": "mark_city_work_orders_changed()",
    "WorldData.get_city_player_command_index_by_id": "get_city_player_command_index_by_id",
    "WorldData.get_city_player_command_by_id": "get_city_player_command_by_id",
    "WorldData.is_city_player_command_target_valid": "is_city_player_command_target_valid",
    "WorldData.release_city_player_command_claim": "release_city_player_command_claim",
    "WorldData.get_city_player_command_types": "get_city_player_command_types",
    "WorldData.is_valid_city_player_command_type": "is_valid_city_player_command_type",
    "WorldData.get_city_player_command_surface_feature": "get_city_player_command_surface_feature",
}
for old, new in local_replacements.items():
    work = work.replace(old, new)
work = work.replace("WorldData.CITY_PLAYER_COMMAND_", "CITY_PLAYER_COMMAND_")

# ---------------------------------------------------------------------------
# Other city callers: use CityWorkSystem / CityWorkState directly.
# ---------------------------------------------------------------------------
external_replacements = {
    "WorldData.city_player_commands": "CityWorkSystem.get_current_work_state().player_commands",
    "WorldData.city_player_command_index_by_id": "CityWorkSystem.get_current_work_state().player_command_index_by_id",
    "WorldData.city_player_command_id_by_tile": "CityWorkSystem.get_current_work_state().player_command_id_by_tile",
    "WorldData.next_city_player_command_id": "CityWorkSystem.get_current_work_state().next_player_command_id",
    "WorldData.next_city_player_command_group_id": "CityWorkSystem.get_current_work_state().next_player_command_group_id",
    "WorldData.city_player_command_version": "CityWorkSystem.get_current_work_state().player_command_version",
    "WorldData.city_work_orders": "CityWorkSystem.get_current_work_state().work_orders",
    "WorldData.city_work_order_id_by_source_key": "CityWorkSystem.get_current_work_state().work_order_id_by_source_key",
    "WorldData.next_city_work_order_id": "CityWorkSystem.get_current_work_state().next_work_order_id",
    "WorldData.city_work_order_version": "CityWorkSystem.get_current_work_state().work_order_version",
    "WorldData._mark_city_player_commands_changed()": "CityWorkSystem.mark_city_player_commands_changed()",
    "WorldData.mark_city_work_orders_changed()": "CityWorkSystem.mark_city_work_orders_changed()",
    "WorldData.reset_city_work_order_state()": "CityWorkSystem.reset_city_work_order_state()",
    "WorldData.reset_city_player_command_state()": "CityWorkSystem.reset_city_player_command_state()",
    "WorldData.get_city_player_command_index_by_id": "CityWorkSystem.get_city_player_command_index_by_id",
    "WorldData.get_city_player_command_by_id": "CityWorkSystem.get_city_player_command_by_id",
    "WorldData.is_city_player_command_target_valid": "CityWorkSystem.is_city_player_command_target_valid",
    "WorldData.release_city_player_command_claim": "CityWorkSystem.release_city_player_command_claim",
    "WorldData.get_city_player_command_types": "CityWorkSystem.get_city_player_command_types",
    "WorldData.is_valid_city_player_command_type": "CityWorkSystem.is_valid_city_player_command_type",
    "WorldData.get_city_player_command_surface_feature": "CityWorkSystem.get_city_player_command_surface_feature",
}

for path in sorted((ROOT / "scripts").rglob("*.gd")):
    if path in {WORLD_DATA, WORK_SYSTEM}:
        continue
    text = path.read_text(encoding="utf-8")
    original = text
    for old, new in external_replacements.items():
        text = text.replace(old, new)
    text = text.replace("WorldData.CITY_PLAYER_COMMAND_", "CityWorkSystem.CITY_PLAYER_COMMAND_")
    if text != original:
        path.write_text(text, encoding="utf-8")

# Extracted work state is no longer part of the WorldData workspace binding.
settlement = settlement.replace(
    "\t\tand WorldData.city_work_orders == work_state.work_orders\n",
    "",
)
settlement = settlement.replace(
    "\t\tand WorldData.city_player_commands == work_state.player_commands\n",
    "",
)
settlement = settlement.replace(
    "# First physically extracted local subsystem. WorldData's old work fields are\n# compatibility accessors onto this object rather than stored data.",
    "# First physically extracted local subsystem. Its state and APIs live outside\n# WorldData and are resolved through the active settlement context.",
)

# ---------------------------------------------------------------------------
# Permanent architectural guardrail.
# ---------------------------------------------------------------------------
audit_symbols = '''
WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS = (
    "city_player_commands",
    "city_player_command_index_by_id",
    "city_player_command_id_by_tile",
    "next_city_player_command_id",
    "next_city_player_command_group_id",
    "city_player_command_version",
    "city_work_orders",
    "city_work_order_id_by_source_key",
    "next_city_work_order_id",
    "city_work_order_version",
    "CITY_PLAYER_COMMAND_TYPE_NONE",
    "CITY_PLAYER_COMMAND_TYPE_CHOP_TREE",
    "CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK",
    "CITY_PLAYER_COMMAND_STATUS_PENDING",
    "CITY_PLAYER_COMMAND_STATUS_CLAIMED",
    "CITY_PLAYER_COMMAND_STATUS_BLOCKED",
    "CITY_PLAYER_COMMAND_TASK_PRIORITY",
    "CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES",
    "CITY_PLAYER_COMMAND_RESOURCE_YIELD",
    "CITY_PLAYER_COMMAND_BLOCKED_RETRY_DELAY_MINUTES",
    "get_city_player_command_types",
    "is_valid_city_player_command_type",
    "get_city_player_command_surface_feature",
    "mark_city_player_commands_changed",
    "mark_city_work_orders_changed",
    "reset_city_work_order_state",
    "get_city_player_command_index_by_id",
    "get_city_player_command_by_id",
    "is_city_player_command_target_valid",
    "release_city_player_command_claim",
    "reset_city_player_command_state",
)
'''
audit = replace_once(
    audit,
    "ALLOWED_QUEUE_REDRAW_CALLS = {\n    \"scripts/city/rendering/CityRenderLayer.gd\": 1,\n    \"scripts/ui/city/CityInformationPanel.gd\": 2,\n}\n",
    "ALLOWED_QUEUE_REDRAW_CALLS = {\n    \"scripts/city/rendering/CityRenderLayer.gd\": 1,\n    \"scripts/ui/city/CityInformationPanel.gd\": 2,\n}\n" + audit_symbols,
    "add city-work ownership audit symbol list",
)

audit_guard = '''
    world_data_path = ROOT / "scripts/world/simulation/WorldData.gd"
    if world_data_path.exists():
        world_data_text = world_data_path.read_text(encoding="utf-8")
        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS:
            if symbol in world_data_text:
                errors.append(
                    "scripts/world/simulation/WorldData.gd: extracted city-work "
                    f"symbol must not return to WorldData: {symbol}"
                )

    for path in scripts:
        if path == world_data_path:
            continue
        relative = str(path.relative_to(ROOT))
        text = path.read_text(encoding="utf-8")
        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS:
            legacy_reference = f"WorldData.{symbol}"
            if legacy_reference in text:
                errors.append(
                    f"{relative}: legacy WorldData city-work reference remains: "
                    f"{legacy_reference}"
                )

'''
audit = replace_once(
    audit,
    "    city_renderer_path = ROOT / \"scripts/city/rendering/CityRenderer.gd\"\n",
    audit_guard + "    city_renderer_path = ROOT / \"scripts/city/rendering/CityRenderer.gd\"\n",
    "add city-work ownership audit checks",
)

# Final one-time transform assertions before writing.
for forbidden in (
    "city_player_commands",
    "city_work_orders",
    "CITY_PLAYER_COMMAND_TYPE_NONE",
    "get_city_player_command_by_id",
    "release_city_player_command_claim",
):
    if forbidden in world:
        raise RuntimeError(f"WorldData still contains extracted work symbol: {forbidden}")

for legacy in (
    "WorldData.city_player_commands",
    "WorldData.city_work_orders",
    "WorldData.city_player_command_version",
    "WorldData.city_work_order_version",
    "WorldData.get_city_player_command_by_id",
    "WorldData.release_city_player_command_claim",
    "WorldData.CITY_PLAYER_COMMAND_",
):
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        if path == WORLD_DATA:
            continue
        candidate = work if path == WORK_SYSTEM else path.read_text(encoding="utf-8")
        if legacy in candidate:
            raise RuntimeError(
                f"Legacy work reference {legacy} remains in {path.relative_to(ROOT)}"
            )

WORLD_DATA.write_text(world, encoding="utf-8")
WORK_SYSTEM.write_text(work, encoding="utf-8")
SETTLEMENT_STATE.write_text(settlement, encoding="utf-8")
POLITICAL_STATE.write_text(political, encoding="utf-8")
AUDIT.write_text(audit, encoding="utf-8")
print("Extracted city work APIs and callers from WorldData.")
