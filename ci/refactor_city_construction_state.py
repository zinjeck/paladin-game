#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# 1) Add the settlement-owned construction state container.
write(
    "scripts/city/simulation/CityConstructionState.gd",
    '''extends RefCounted
class_name CityConstructionState

# Settlement-owned mutable construction registry state for one CITY.
#
# This object owns only construction-site collections, indexes, counters, and
# the focused construction change version. Construction rules and behavior stay
# in the existing construction APIs for this ownership-only pass.
#
# Keep this class a small state container rather than a second simulation brain.

var construction_sites: Array = []
var construction_site_index_by_id: Dictionary = {}
var construction_site_id_by_tile: Dictionary = {}
var next_construction_site_id: int = 1
var construction_version: int = 0
'''
)

# 2) Move construction ownership out of the settlement root workspace copy.
path = "scripts/city/simulation/CitySettlementSimulationState.gd"
text = read(path)
text = replace_once(
    text,
    '''var construction_sites: Array = []
var construction_site_index_by_id: Dictionary = {}
var construction_site_id_by_tile: Dictionary = {}
var next_construction_site_id: int = 1

# Physically extracted settlement-local subsystems. Their state is selected by
# settlement identity rather than copied through the legacy WorldData workspace.
var work_state: CityWorkState = CityWorkState.new()
var logistics_state: CityLogisticsState = CityLogisticsState.new()
''',
    '''# Physically extracted settlement-local subsystems. Their state is selected by
# settlement identity rather than copied through the legacy WorldData workspace.
var work_state: CityWorkState = CityWorkState.new()
var logistics_state: CityLogisticsState = CityLogisticsState.new()
var construction_state: CityConstructionState = CityConstructionState.new()
''',
    "CitySettlementSimulationState subsystem fields",
)
text = replace_once(
    text,
    "var construction_version: int = 0\n",
    "",
    "CitySettlementSimulationState construction version",
)
text = replace_once(
    text,
    '''\tconstruction_sites = WorldData.city_construction_sites
\tconstruction_site_index_by_id = WorldData.city_construction_site_index_by_id
\tconstruction_site_id_by_tile = WorldData.city_construction_site_id_by_tile
\tnext_construction_site_id = WorldData.next_city_construction_site_id

''',
    "",
    "CitySettlementSimulationState construction capture",
)
text = replace_once(
    text,
    "\tconstruction_version = WorldData.city_construction_version\n",
    "",
    "CitySettlementSimulationState construction-version capture",
)
text = replace_once(
    text,
    '''\tWorldData.city_construction_sites = construction_sites
\tWorldData.city_construction_site_index_by_id = construction_site_index_by_id
\tWorldData.city_construction_site_id_by_tile = construction_site_id_by_tile
\tWorldData.next_city_construction_site_id = next_construction_site_id

''',
    "",
    "CitySettlementSimulationState construction apply",
)
text = replace_once(
    text,
    "\tWorldData.city_construction_version = construction_version\n",
    "",
    "CitySettlementSimulationState construction-version apply",
)
text = replace_once(
    text,
    '''\treturn (
\t\tWorldData.city_objects == objects
\t\tand WorldData.city_citizens == citizens
\t\tand WorldData.city_construction_sites == construction_sites
\t)
''',
    '''\treturn (
\t\tWorldData.city_objects == objects
\t\tand WorldData.city_citizens == citizens
\t)
''',
    "CitySettlementSimulationState workspace binding check",
)
write(path, text)

# 3) Make WorldPoliticalState own the pre-context construction state and expose
# the current City's state to the compatibility workspace.
path = "scripts/world/simulation/WorldPoliticalState.gd"
text = read(path)
text = replace_once(
    text,
    '''const CityLogisticsStateScript = preload(
\t"res://scripts/city/simulation/CityLogisticsState.gd"
)
''',
    '''const CityLogisticsStateScript = preload(
\t"res://scripts/city/simulation/CityLogisticsState.gd"
)
const CityConstructionStateScript = preload(
\t"res://scripts/city/simulation/CityConstructionState.gd"
)
''',
    "WorldPoliticalState construction preload",
)
text = replace_once(
    text,
    '''var _unbound_city_work_state = CityWorkStateScript.new()
var _unbound_city_logistics_state = CityLogisticsStateScript.new()
''',
    '''var _unbound_city_work_state = CityWorkStateScript.new()
var _unbound_city_logistics_state = CityLogisticsStateScript.new()
var _unbound_city_construction_state = CityConstructionStateScript.new()
''',
    "WorldPoliticalState unbound state",
)
text = replace_once(
    text,
    '''\t_unbound_city_work_state = CityWorkStateScript.new()
\t_unbound_city_logistics_state = CityLogisticsStateScript.new()
''',
    '''\t_unbound_city_work_state = CityWorkStateScript.new()
\t_unbound_city_logistics_state = CityLogisticsStateScript.new()
\t_unbound_city_construction_state = CityConstructionStateScript.new()
''',
    "WorldPoliticalState reset unbound state",
)
text = replace_once(
    text,
    '''\tvar unbound_work_state_to_adopt = _unbound_city_work_state
\tvar unbound_logistics_state_to_adopt = _unbound_city_logistics_state
''',
    '''\tvar unbound_work_state_to_adopt = _unbound_city_work_state
\tvar unbound_logistics_state_to_adopt = _unbound_city_logistics_state
\tvar unbound_construction_state_to_adopt = _unbound_city_construction_state
''',
    "WorldPoliticalState foundation adoption snapshot",
)
text = replace_once(
    text,
    '''\tif should_adopt_unbound_work_state:
\t\tcapital_state.work_state = unbound_work_state_to_adopt
\t\tcapital_state.logistics_state = unbound_logistics_state_to_adopt
\tcapital_state.capture_from_world_data()
''',
    '''\tif should_adopt_unbound_work_state:
\t\tcapital_state.work_state = unbound_work_state_to_adopt
\t\tcapital_state.logistics_state = unbound_logistics_state_to_adopt
\t\tcapital_state.construction_state = unbound_construction_state_to_adopt
\tcapital_state.capture_from_world_data()
''',
    "WorldPoliticalState foundation adoption assignment",
)
text = replace_once(
    text,
    '''func get_current_city_logistics_state() -> CityLogisticsState:
\tvar active_city_state = get_active_city_simulation_state()
\tif (
\t\tactive_city_state != null
\t\tand active_city_state.logistics_state is CityLogisticsState
\t):
\t\treturn active_city_state.logistics_state
\treturn _unbound_city_logistics_state


# WorldData still owns the legacy city-session reset entry point while local
''',
    '''func get_current_city_logistics_state() -> CityLogisticsState:
\tvar active_city_state = get_active_city_simulation_state()
\tif (
\t\tactive_city_state != null
\t\tand active_city_state.logistics_state is CityLogisticsState
\t):
\t\treturn active_city_state.logistics_state
\treturn _unbound_city_logistics_state


func get_current_city_construction_state() -> CityConstructionState:
\tvar active_city_state = get_active_city_simulation_state()
\tif (
\t\tactive_city_state != null
\t\tand active_city_state.construction_state is CityConstructionState
\t):
\t\treturn active_city_state.construction_state
\treturn _unbound_city_construction_state


# WorldData still owns the legacy city-session reset entry point while local
''',
    "WorldPoliticalState construction getter",
)
write(path, text)

# 4) Convert WorldData construction storage into compatibility properties.
path = "scripts/world/simulation/WorldData.gd"
text = read(path)
text = replace_once(
    text,
    '''# Construction sites reserve placement footprints without becoming operational
# city objects. Their physical materials remain authoritative ground piles.
static var city_construction_sites: Array = []
static var city_construction_site_index_by_id: Dictionary = {}
static var city_construction_site_id_by_tile: Dictionary = {}
static var next_city_construction_site_id: int = 1
''',
    '''# Construction registry ownership is settlement-local. These compatibility
# properties preserve the historical WorldData API during the ownership-only
# pass while resolving to the active City's CityConstructionState.
static var city_construction_sites: Array:
\tget:
\t\treturn WorldPoliticalState.get_current_city_construction_state().construction_sites
\tset(value):
\t\tWorldPoliticalState.get_current_city_construction_state().construction_sites = value
static var city_construction_site_index_by_id: Dictionary:
\tget:
\t\treturn WorldPoliticalState.get_current_city_construction_state().construction_site_index_by_id
\tset(value):
\t\tWorldPoliticalState.get_current_city_construction_state().construction_site_index_by_id = value
static var city_construction_site_id_by_tile: Dictionary:
\tget:
\t\treturn WorldPoliticalState.get_current_city_construction_state().construction_site_id_by_tile
\tset(value):
\t\tWorldPoliticalState.get_current_city_construction_state().construction_site_id_by_tile = value
static var next_city_construction_site_id: int:
\tget:
\t\treturn WorldPoliticalState.get_current_city_construction_state().next_construction_site_id
\tset(value):
\t\tWorldPoliticalState.get_current_city_construction_state().next_construction_site_id = value
''',
    "WorldData construction registry storage",
)
text = replace_once(
    text,
    "static var city_construction_version: int = 0\n",
    '''static var city_construction_version: int:
\tget:
\t\treturn WorldPoliticalState.get_current_city_construction_state().construction_version
\tset(value):
\t\tWorldPoliticalState.get_current_city_construction_state().construction_version = value
''',
    "WorldData construction version storage",
)
write(path, text)

# 5) Add focused bootstrap coverage.
write(
    "scripts/city/simulation/CityConstructionStateBootstrapTest.gd",
    '''extends Node

const TEST_CITY_NAME := "Construction Bootstrap City"
const TEST_CULTURE_NAME := "Construction Bootstrap Culture"

var failure_count: int = 0


func _ready() -> void:
\t_run_bootstrap_test()
\tWorldPoliticalState.reset_state()
\tWorldData.reset_runtime_session_state()

\tif failure_count > 0:
\t\tpush_error(
\t\t\t"City construction-state bootstrap test failed: "
\t\t\t+ str(failure_count)
\t\t)
\t\tget_tree().quit(1)
\t\treturn

\tprint("City construction-state bootstrap test passed.")
\tget_tree().quit(0)


func _run_bootstrap_test() -> void:
\tWorldPoliticalState.reset_state()
\tWorldData.reset_runtime_session_state()

\tvar world := _make_world(8, 8, 85_021)
\tvar locked := WorldData.lock_world_save({
\t\t"source_world": world,
\t\t"region_top_left": Vector2i(1, 1),
\t\t"region_center": Vector2i(2, 2),
\t\t"region_size": 3,
\t\t"world_scene_path": "res://scenes/GameSession.tscn",
\t\t"city_scene_path": "res://scenes/CityScreen.tscn",
\t\t"city_name": TEST_CITY_NAME,
\t\t"culture_name": TEST_CULTURE_NAME,
\t})
\t_expect(locked, "Fixture must lock a founding world.")
\tif not locked:
\t\treturn

\tWorldData.city_construction_sites = [
\t\t{
\t\t\t"id": 17,
\t\t\t"test_owner": "bootstrap",
\t\t},
\t]
\tWorldData.city_construction_site_index_by_id = {17: 0}
\tWorldData.city_construction_site_id_by_tile = {Vector2i(3, 3): 17}
\tWorldData.next_city_construction_site_id = 18
\tWorldData.city_construction_version = 5

\tvar bootstrap_state = WorldPoliticalState.get_current_city_construction_state()
\t_expect(
\t\tbootstrap_state is CityConstructionState,
\t\t"Pre-context construction must live in the unbound CityConstructionState."
\t)

\t_expect(
\t\tWorldPoliticalState.synchronize_foundation_with_world_data(),
\t\t"Founding must establish a city settlement context."
\t)

\tvar capital_state = WorldPoliticalState.get_active_city_simulation_state()
\t_expect(
\t\tcapital_state is CitySettlementSimulationState,
\t\t"Founding capital must own city simulation state."
\t)
\tif capital_state == null:
\t\treturn

\t_expect(
\t\tcapital_state.construction_state == bootstrap_state,
\t\t"Founding City must adopt the exact pre-context construction-state object."
\t)
\t_expect(
\t\tstr(capital_state.construction_state.construction_sites[0].get("test_owner", ""))
\t\t== "bootstrap"
\t\tand capital_state.construction_state.next_construction_site_id == 18
\t\tand capital_state.construction_state.construction_version == 5,
\t\t"Bootstrap construction state must survive context establishment."
\t)
\t_expect(
\t\tWorldData.city_construction_sites == capital_state.construction_state.construction_sites
\t\tand WorldData.next_city_construction_site_id == 18
\t\tand WorldData.city_construction_version == 5,
\t\t"WorldData compatibility properties must resolve to the active City's construction state."
\t)


func _make_world(width: int, height: int, seed: int) -> WorldData:
\tvar world := WorldData.new()
\tworld.setup(width, height, seed)

\tfor y in range(height):
\t\tfor x in range(width):
\t\t\tworld.tiles[y][x] = {
\t\t\t\t"fertility": 50.0,
\t\t\t\t"elevation": 0.2,
\t\t\t\t"temperature": 0.5,
\t\t\t\t"precipitation": 0.5,
\t\t\t\t"terrain": WorldData.TERRAIN_LAND,
\t\t\t\t"biome": WorldData.BIOME_PLAIN,
\t\t\t\t"resource": WorldData.RESOURCE_NONE,
\t\t\t\t"is_land": true,
\t\t\t}

\tworld.mark_tile_data_changed()
\treturn world


func _expect(condition: bool, message: String) -> void:
\tif condition:
\t\treturn

\tfailure_count += 1
\tpush_error("City construction-state bootstrap test: " + message)
'''
)
write(
    "scripts/city/simulation/CityConstructionStateBootstrapTest.tscn",
    '''[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/city/simulation/CityConstructionStateBootstrapTest.gd" id="1_bootstrap"]

[node name="CityConstructionStateBootstrapTest" type="Node"]
script = ExtResource("1_bootstrap")
'''
)

# 6) Add a focused two-City isolation test instead of inflating the existing
# all-subsystem isolation fixture further.
write(
    "scripts/city/simulation/CityConstructionStateIsolationTest.gd",
    '''extends Node

var failure_count: int = 0


func _ready() -> void:
\t_run_isolation_test()
\tWorldPoliticalState.reset_state()
\tWorldData.reset_runtime_session_state()

\tif failure_count > 0:
\t\tpush_error(
\t\t\t"City construction-state isolation test failed: "
\t\t\t+ str(failure_count)
\t\t)
\t\tget_tree().quit(1)
\t\treturn

\tprint("City construction-state isolation test passed.")
\tget_tree().quit(0)


func _run_isolation_test() -> void:
\tWorldPoliticalState.reset_state()
\tWorldData.reset_runtime_session_state()

\tvar world := _make_world(8, 8, 86_001)
\tvar locked := WorldData.lock_world_save({
\t\t"source_world": world,
\t\t"region_top_left": Vector2i(1, 1),
\t\t"region_center": Vector2i(2, 2),
\t\t"region_size": 3,
\t\t"world_scene_path": "res://scenes/GameSession.tscn",
\t\t"city_scene_path": "res://scenes/CityScreen.tscn",
\t\t"city_name": "Construction Isolation City",
\t\t"culture_name": "Construction Isolation Culture",
\t})
\t_expect(locked, "Fixture must lock the founding world.")
\tif not locked:
\t\treturn
\t_expect(
\t\tWorldPoliticalState.synchronize_foundation_with_world_data(),
\t\t"Founding must establish the player City."
\t)

\tvar player_polity := WorldPoliticalState.get_player_polity()
\tvar player_city_id := int(player_polity.get("capital_settlement_id", -1))
\tvar player_state = WorldPoliticalState.get_city_simulation_state(player_city_id)
\t_expect(
\t\tplayer_state != null
\t\tand player_state.construction_state is CityConstructionState,
\t\t"Player City must own a construction state."
\t)
\tif player_state == null:
\t\treturn

\tWorldData.city_construction_sites = [{"id": 41, "test_owner": "player"}]
\tWorldData.city_construction_site_index_by_id = {41: 0}
\tWorldData.city_construction_site_id_by_tile = {Vector2i(2, 2): 41}
\tWorldData.next_city_construction_site_id = 42
\tWorldData.city_construction_version = 6

\tvar cpu_culture := WorldData.create_culture("Construction CPU Culture")
\tvar cpu_polity := WorldPoliticalState.create_polity({
\t\t"name": "Construction CPU Realm",
\t\t"polity_type": PolityData.POLITY_TYPE_KINGDOM,
\t\t"primary_culture_id": int(cpu_culture.get("id", -1)),
\t})
\tvar cpu_city := WorldPoliticalState.create_settlement({
\t\t"name": "Construction CPU City",
\t\t"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
\t\t"polity_id": int(cpu_polity.get("id", -1)),
\t\t"world_region_top_left": Vector2i(5, 5),
\t\t"world_region_center": Vector2i(5, 5),
\t\t"world_region_size": 1,
\t\t"simulation_backend_kind": SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE,
\t})
\t_expect(not cpu_city.is_empty(), "Fixture must create a second City.")
\tif cpu_city.is_empty():
\t\treturn

\tvar cpu_city_id := int(cpu_city["id"])
\tvar cpu_state = WorldPoliticalState.get_city_simulation_state(cpu_city_id)
\t_expect(
\t\tcpu_state != null
\t\tand cpu_state.construction_state is CityConstructionState
\t\tand cpu_state.construction_state != player_state.construction_state,
\t\t"Two Cities must own distinct construction-state objects."
\t)

\t_expect(
\t\tWorldPoliticalState.set_active_settlement(cpu_city_id),
\t\t"CPU City must become active."
\t)
\t_expect(
\t\tWorldData.city_construction_sites.is_empty()
\t\tand WorldData.city_construction_site_index_by_id.is_empty()
\t\tand WorldData.city_construction_site_id_by_tile.is_empty()
\t\tand WorldData.next_city_construction_site_id == 1
\t\tand WorldData.city_construction_version == 0,
\t\t"Fresh CPU City must start with independent construction state."
\t)

\tWorldData.city_construction_sites = [{"id": 71, "test_owner": "cpu"}]
\tWorldData.city_construction_site_index_by_id = {71: 0}
\tWorldData.city_construction_site_id_by_tile = {Vector2i(6, 6): 71}
\tWorldData.next_city_construction_site_id = 72
\tWorldData.city_construction_version = 9

\t_expect(
\t\tWorldPoliticalState.set_active_settlement(player_city_id),
\t\t"Player City must become active again."
\t)
\t_expect(
\t\tstr(WorldData.city_construction_sites[0].get("test_owner", "")) == "player"
\t\tand WorldData.city_construction_site_index_by_id.has(41)
\t\tand int(WorldData.city_construction_site_id_by_tile.get(Vector2i(2, 2), -1)) == 41
\t\tand WorldData.next_city_construction_site_id == 42
\t\tand WorldData.city_construction_version == 6,
\t\t"Player construction state must survive a settlement switch."
\t)

\t_expect(
\t\tWorldPoliticalState.set_active_settlement(cpu_city_id),
\t\t"CPU City must become active again."
\t)
\t_expect(
\t\tstr(WorldData.city_construction_sites[0].get("test_owner", "")) == "cpu"
\t\tand WorldData.city_construction_site_index_by_id.has(71)
\t\tand int(WorldData.city_construction_site_id_by_tile.get(Vector2i(6, 6), -1)) == 71
\t\tand WorldData.next_city_construction_site_id == 72
\t\tand WorldData.city_construction_version == 9,
\t\t"CPU construction state must survive a settlement switch."
\t)


func _make_world(width: int, height: int, seed: int) -> WorldData:
\tvar world := WorldData.new()
\tworld.setup(width, height, seed)
\tfor y in range(height):
\t\tfor x in range(width):
\t\t\tworld.tiles[y][x] = {
\t\t\t\t"fertility": 50.0,
\t\t\t\t"elevation": 0.2,
\t\t\t\t"temperature": 0.5,
\t\t\t\t"precipitation": 0.5,
\t\t\t\t"terrain": WorldData.TERRAIN_LAND,
\t\t\t\t"biome": WorldData.BIOME_PLAIN,
\t\t\t\t"resource": WorldData.RESOURCE_NONE,
\t\t\t\t"is_land": true,
\t\t\t}
\tworld.mark_tile_data_changed()
\treturn world


func _expect(condition: bool, message: String) -> void:
\tif condition:
\t\treturn
\tfailure_count += 1
\tpush_error("City construction-state isolation test: " + message)
'''
)
write(
    "scripts/city/simulation/CityConstructionStateIsolationTest.tscn",
    '''[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/city/simulation/CityConstructionStateIsolationTest.gd" id="1_isolation"]

[node name="CityConstructionStateIsolationTest" type="Node"]
script = ExtResource("1_isolation")
'''
)

# 7) Add a permanent ownership guard. WorldData compatibility properties are
# required for this pass, while backing storage in WorldData/root state is not.
path = "ci/audit_gdscript.py"
text = read(path)
text = replace_once(
    text,
    "WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS = (\n",
    '''WORLD_DATA_CONSTRUCTION_COMPATIBILITY_FIELDS = (
    ("city_construction_sites", "construction_sites"),
    ("city_construction_site_index_by_id", "construction_site_index_by_id"),
    ("city_construction_site_id_by_tile", "construction_site_id_by_tile"),
    ("next_city_construction_site_id", "next_construction_site_id"),
    ("city_construction_version", "construction_version"),
)

WORLD_DATA_FORBIDDEN_CITY_WORK_SYMBOLS = (
''',
    "audit construction compatibility tuple",
)
text = replace_once(
    text,
    '''    report = {
''',
    '''    construction_state_path = ROOT / "scripts/city/simulation/CityConstructionState.gd"
    city_root_state_path = ROOT / "scripts/city/simulation/CitySettlementSimulationState.gd"
    if world_data_path.exists() and construction_state_path.exists() and city_root_state_path.exists():
        world_data_text = world_data_path.read_text(encoding="utf-8")
        construction_state_text = construction_state_path.read_text(encoding="utf-8")
        city_root_state_text = city_root_state_path.read_text(encoding="utf-8")
        for legacy_name, state_name in WORLD_DATA_CONSTRUCTION_COMPATIBILITY_FIELDS:
            direct_storage_pattern = rf"^\\s*static\\s+var\\s+{re.escape(legacy_name)}[^\\n]*="
            if re.search(direct_storage_pattern, world_data_text, re.MULTILINE):
                errors.append(
                    f"scripts/world/simulation/WorldData.gd: construction field {legacy_name} "
                    "must forward to CityConstructionState instead of owning storage"
                )
            expected_getter = (
                f"WorldPoliticalState.get_current_city_construction_state().{state_name}"
            )
            if expected_getter not in world_data_text:
                errors.append(
                    f"scripts/world/simulation/WorldData.gd: construction compatibility field "
                    f"{legacy_name} does not forward to {state_name}"
                )
            if not re.search(rf"^var\\s+{re.escape(state_name)}\\b", construction_state_text, re.MULTILINE):
                errors.append(
                    f"scripts/city/simulation/CityConstructionState.gd: missing {state_name}"
                )
            if re.search(rf"^var\\s+{re.escape(state_name)}\\b", city_root_state_text, re.MULTILINE):
                errors.append(
                    f"scripts/city/simulation/CitySettlementSimulationState.gd: construction storage "
                    f"{state_name} must live in CityConstructionState"
                )
        if "var construction_state: CityConstructionState" not in city_root_state_text:
            errors.append(
                "scripts/city/simulation/CitySettlementSimulationState.gd: missing construction_state owner"
            )

    report = {
''',
    "audit construction ownership checks",
)
write(path, text)

print("Construction-state ownership extraction applied successfully.")
