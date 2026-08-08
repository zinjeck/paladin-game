from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORLD_DATA = ROOT / "scripts/world/simulation/WorldData.gd"
WORK_SYSTEM = ROOT / "scripts/city/simulation/systems/CityWorkSystem.gd"
AUDIT = ROOT / "ci/audit_gdscript.py"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


world = WORLD_DATA.read_text(encoding="utf-8")
work = WORK_SYSTEM.read_text(encoding="utf-8")
audit = AUDIT.read_text(encoding="utf-8")

world = replace_once(
    world,
    "\t\tor not is_city_player_command_target_valid(command)\n",
    "\t\tor not WorldPoliticalState.get_current_city_work_state().is_player_command_target_valid(\n"
    "\t\t\tcommand,\n"
    "\t\t\tofficial_city_world,\n"
    "\t\t\tINVALID_CITY_TILE_POSITION\n"
    "\t\t)\n",
    "route task-preparation command validation to CityWorkState",
)

old_work_validator = '''static func is_city_player_command_target_valid(command: Dictionary) -> bool:
\tvar city_world: WorldData = WorldData.official_city_world
\tvar command_type := str(
\t\tcommand.get("type", CITY_PLAYER_COMMAND_TYPE_NONE)
\t)
\tvar raw_tile_position = command.get(
\t\t"tile_position",
\t\tWorldData.INVALID_CITY_TILE_POSITION
\t)
\tif (
\t\tcity_world == null
\t\tor not is_valid_city_player_command_type(command_type)
\t\tor not raw_tile_position is Vector2i
\t):
\t\treturn false

\tvar tile_position: Vector2i = raw_tile_position
\tif not city_world.is_in_bounds(tile_position.x, tile_position.y):
\t\treturn false

\treturn (
\t\tWorldData.get_city_surface_feature(
\t\t\tcity_world.get_tile(tile_position.x, tile_position.y)
\t\t)
\t\t== get_city_player_command_surface_feature(command_type)
\t)
'''
new_work_validator = '''static func is_city_player_command_target_valid(command: Dictionary) -> bool:
\treturn _work_state().is_player_command_target_valid(
\t\tcommand,
\t\tWorldData.official_city_world,
\t\tWorldData.INVALID_CITY_TILE_POSITION
\t)
'''
work = replace_once(
    work,
    old_work_validator,
    new_work_validator,
    "delegate public command target validation to CityWorkState",
)

old_audit_guard = '''    world_data_path = ROOT / "scripts/world/simulation/WorldData.gd"
    if world_data_path.exists():
        world_data_text = world_data_path.read_text(encoding="utf-8")
        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS:
            if symbol in world_data_text:
                errors.append(
                    "scripts/world/simulation/WorldData.gd: extracted city-work "
                    f"symbol must not return to WorldData: {symbol}"
                )

    for path in scripts:
'''
new_audit_guard = '''    world_data_path = ROOT / "scripts/world/simulation/WorldData.gd"
    if world_data_path.exists():
        world_data_text = world_data_path.read_text(encoding="utf-8")
        for symbol in WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS:
            declaration_patterns = (
                rf"^\\s*static\\s+var\\s+{re.escape(symbol)}\\b",
                rf"^\\s*const\\s+{re.escape(symbol)}\\b",
                rf"^\\s*(?:static\\s+)?func\\s+{re.escape(symbol)}\\s*\\(",
                rf"^\\s*(?:static\\s+)?func\\s+_{re.escape(symbol)}\\s*\\(",
            )
            if any(
                re.search(pattern, world_data_text, re.MULTILINE)
                for pattern in declaration_patterns
            ):
                errors.append(
                    "scripts/world/simulation/WorldData.gd: extracted city-work "
                    f"ownership declaration must not return to WorldData: {symbol}"
                )

    for path in scripts:
'''
audit = replace_once(
    audit,
    old_audit_guard,
    new_audit_guard,
    "narrow WorldData city-work guard to ownership declarations",
)

WORLD_DATA.write_text(world, encoding="utf-8")
WORK_SYSTEM.write_text(work, encoding="utf-8")
AUDIT.write_text(audit, encoding="utf-8")
print("Finalized city work API extraction integration.")
