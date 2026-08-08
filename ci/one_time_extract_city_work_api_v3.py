from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
WORLD_DATA = ROOT / "scripts/world/simulation/WorldData.gd"
WORK_STATE = ROOT / "scripts/city/simulation/CityWorkState.gd"
WORK_SYSTEM = ROOT / "scripts/city/simulation/systems/CityWorkSystem.gd"
BASE_TRANSFORM = ROOT / "ci/one_time_extract_city_work_api.py"

# Two legacy citizen-task primitives live outside WorldData's work API region.
# Route them through the settlement-owned state before the base extraction
# removes the legacy WorldData work surface.
world = WORLD_DATA.read_text(encoding="utf-8")
lookup_old = "\tvar command := get_city_player_command_by_id(target_object_id)"
lookup_new = (
    "\tvar command := "
    "WorldPoliticalState.get_current_city_work_state()"
    ".get_player_command_by_id(target_object_id)"
)
if world.count(lookup_old) != 1:
    raise RuntimeError(
        "remaining WorldData player-command lookup did not match exactly once"
    )
world = world.replace(lookup_old, lookup_new, 1)

release_old = '''\tif current_task_kind == CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
\t\tWorldData.release_city_player_command_claim(
\t\t\tint(raw_current_task.get("target_object_id", -1)),
\t\t\tcitizen_id
\t\t)'''
release_new = '''\tif current_task_kind == CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
\t\tWorldPoliticalState.get_current_city_work_state().release_player_command_claim(
\t\t\tint(raw_current_task.get("target_object_id", -1)),
\t\t\tcitizen_id
\t\t)'''
if world.count(release_old) != 1:
    raise RuntimeError(
        "remaining WorldData player-command claim release did not match exactly once"
    )
world = world.replace(release_old, release_new, 1)
WORLD_DATA.write_text(world, encoding="utf-8")

# Primitive record mutation belongs with the record owner. Scheduling and
# higher-level command behavior remain in CityWorkSystem.
state = WORK_STATE.read_text(encoding="utf-8")
anchor = '''func get_player_command_snapshot() -> Array:
\treturn player_commands.duplicate(true)
'''
primitive = '''func release_player_command_claim(
\tcommand_id: int,
\tcitizen_id: int,
\tblocked_retry_minute: int = -1
) -> bool:
\tvar command_index := get_player_command_index_by_id(command_id)
\tif command_index < 0:
\t\treturn false

\tvar command: Dictionary = player_commands[command_index]
\tif int(command.get("claimed_citizen_id", -1)) != citizen_id:
\t\treturn false

\tcommand["claimed_citizen_id"] = -1
\tif blocked_retry_minute >= 0:
\t\tcommand["status"] = "blocked"
\t\tcommand["next_retry_world_minute"] = blocked_retry_minute
\telse:
\t\tcommand["status"] = "pending"
\t\tcommand["next_retry_world_minute"] = -1

\tplayer_commands[command_index] = command
\tmark_player_commands_changed()
\treturn true


'''
if state.count(anchor) != 1:
    raise RuntimeError("CityWorkState snapshot anchor did not match exactly once")
state = state.replace(anchor, primitive + anchor, 1)
WORK_STATE.write_text(state, encoding="utf-8")

# Run the main assertion-driven extraction.
code = compile(
    BASE_TRANSFORM.read_text(encoding="utf-8"),
    str(BASE_TRANSFORM),
    "exec",
)
exec(code, {"__file__": str(BASE_TRANSFORM), "__name__": "__main__"})

# Keep CityWorkSystem as the public API while delegating the primitive record
# mutation to CityWorkState so there is only one implementation of claim
# release semantics.
work = WORK_SYSTEM.read_text(encoding="utf-8")
pattern = re.compile(
    r'''static func release_city_player_command_claim\(
\tcommand_id: int,
\tcitizen_id: int,
\tblocked_retry_minute: int = -1
\) -> bool:
.*?\n\treturn true\n\n\n#region Player Command and Work Order Operations''',
    re.DOTALL,
)
replacement = '''static func release_city_player_command_claim(
\tcommand_id: int,
\tcitizen_id: int,
\tblocked_retry_minute: int = -1
) -> bool:
\treturn _work_state().release_player_command_claim(
\t\tcommand_id,
\t\tcitizen_id,
\t\tblocked_retry_minute
\t)


#region Player Command and Work Order Operations'''
work, count = pattern.subn(replacement, work, count=1)
if count != 1:
    raise RuntimeError(
        "CityWorkSystem claim-release delegation did not match exactly once"
    )
WORK_SYSTEM.write_text(work, encoding="utf-8")
print("Removed final WorldData city-work claim coupling.")
