extends Node

const TEST_CITY_NAME := "Asterfall"
const TEST_CULTURE_NAME := "Valen"
const TEST_CPU_CULTURE_NAME := "Maren"
const TEST_REGION_TOP_LEFT := Vector2i(2, 2)
const TEST_REGION_CENTER := Vector2i(3, 3)
const TEST_REGION_SIZE: int = 3

var failure_count: int = 0


func _ready() -> void:
	_run_framework_test()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"World political framework test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("World political framework test passed.")
	get_tree().quit(0)


func _run_framework_test() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	var world := _make_world(8, 8, 44_017)
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": TEST_REGION_TOP_LEFT,
		"region_center": TEST_REGION_CENTER,
		"region_size": TEST_REGION_SIZE,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": TEST_CITY_NAME,
		"culture_name": TEST_CULTURE_NAME,
	})
	_expect(locked, "The founding fixture must lock its world state.")
	if not locked:
		return

	var synchronized := (
		WorldPoliticalState.synchronize_foundation_with_world_data()
	)
	_expect(
		synchronized,
		"A locked founding world must create a political framework."
	)
	if not synchronized:
		return

	var polity_snapshot := WorldPoliticalState.get_polity_snapshot()
	var settlement_snapshot := WorldPoliticalState.get_settlement_snapshot()
	_expect(
		polity_snapshot.size() == 1,
		"Founding must create exactly one player polity."
	)
	_expect(
		settlement_snapshot.size() == 1,
		"Founding must create exactly one capital settlement."
	)
	if polity_snapshot.is_empty() or settlement_snapshot.is_empty():
		return

	var player_polity: Dictionary = polity_snapshot[0]
	var capital: Dictionary = settlement_snapshot[0]
	var player_polity_id := int(player_polity["id"])
	var capital_id := int(capital["id"])

	_expect(
		WorldPoliticalState.player_polity_id == player_polity_id,
		"The founding polity must become the player polity."
	)
	_expect(
		str(player_polity["polity_type"])
		== PolityData.POLITY_TYPE_CHIEFDOM,
		"The player must begin as a chiefdom."
	)
	_expect(
		int(player_polity["primary_culture_id"])
		== WorldData.get_official_founding_culture_id(),
		"The founding culture must become the polity primary culture."
	)
	_expect(
		(player_polity["accepted_culture_ids"] as Array).is_empty(),
		"The founding polity must not invent accepted cultures."
	)
	_expect(
		int(player_polity["ruler_citizen_id"])
		== PolityData.INVALID_CITIZEN_ID,
		"The framework must reserve ruler identity without inventing a ruler yet."
	)
	_expect(
		int(player_polity["capital_settlement_id"]) == capital_id
		and (player_polity["settlement_ids"] as Array).has(capital_id),
		"The founding settlement must be linked as the polity capital."
	)

	_expect(
		str(capital["name"]) == TEST_CITY_NAME
		and str(capital["settlement_type"])
		== SettlementData.SETTLEMENT_TYPE_CITY,
		"The first settlement must retain its name and city-class simulation type."
	)
	_expect(
		int(capital["polity_id"]) == player_polity_id,
		"The capital must point back to its owning polity."
	)
	_expect(
		capital["world_region_top_left"] == TEST_REGION_TOP_LEFT
		and capital["world_region_center"] == TEST_REGION_CENTER
		and int(capital["world_region_size"]) == TEST_REGION_SIZE,
		"The settlement identity must retain its world-map footprint."
	)
	_expect(
		int(capital["parent_city_id"])
		== SettlementData.INVALID_SETTLEMENT_ID,
		"A city must not invent a parent city."
	)
	_expect(
		WorldPoliticalState.active_settlement_id == capital_id
		and WorldPoliticalState.is_settlement_capital(capital_id),
		"The founding capital must become the active settlement."
	)

	var capital_context = WorldPoliticalState.get_active_settlement_context()
	_expect(
		capital_context != null
		and capital_context.is_valid()
		and capital_context.settlement_id == capital_id
		and capital_context.polity_id == player_polity_id
		and capital_context.is_capital
		and capital_context.supports_city_simulation(),
		"The existing city simulation must run through the founding settlement context."
	)

	_test_village_hierarchy(player_polity_id, capital_id)
	_test_generic_second_polity(capital_id)


func _test_village_hierarchy(
	player_polity_id: int,
	player_capital_id: int
) -> void:
	var village := WorldPoliticalState.create_settlement({
		"name": "Asterfield",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_VILLAGE,
		"polity_id": player_polity_id,
		"world_region_top_left": Vector2i(1, 1),
		"world_region_center": Vector2i(1, 1),
		"world_region_size": 1,
		"parent_city_id": player_capital_id,
	})
	_expect(
		not village.is_empty(),
		"A village must be creatable beneath a same-polity parent city."
	)
	if village.is_empty():
		return

	var village_id := int(village["id"])
	_expect(
		int(village["parent_city_id"]) == player_capital_id,
		"Village identity must retain its parent-city relationship."
	)
	_expect(
		not WorldPoliticalState.set_polity_capital(
			player_polity_id,
			village_id
		),
		"A village must not be assignable as a polity capital."
	)
	_expect(
		WorldPoliticalState.is_settlement_capital(player_capital_id),
		"Rejecting a village capital must preserve the existing city capital."
	)
	_expect(
		WorldPoliticalState.validate_registry_integrity(),
		"Adding a valid child village must preserve registry integrity."
	)


func _test_generic_second_polity(player_capital_id: int) -> void:
	var cpu_culture := WorldData.create_culture(TEST_CPU_CULTURE_NAME)
	_expect(
		not cpu_culture.is_empty(),
		"The isolation fixture must create a second culture."
	)
	if cpu_culture.is_empty():
		return

	var cpu_polity := WorldPoliticalState.create_polity({
		"name": "Maren Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": int(cpu_culture["id"]),
	})
	_expect(
		not cpu_polity.is_empty(),
		"The registry must create an independent second polity."
	)
	if cpu_polity.is_empty():
		return

	var cpu_settlement := WorldPoliticalState.create_settlement({
		"name": "Marenhold",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": int(cpu_polity["id"]),
		"world_region_top_left": Vector2i(5, 5),
		"world_region_center": Vector2i(5, 5),
		"world_region_size": 1,
	})
	_expect(
		not cpu_settlement.is_empty(),
		"The registry must create a settlement for a non-player polity."
	)
	if cpu_settlement.is_empty():
		return

	var cpu_polity_id := int(cpu_polity["id"])
	var cpu_settlement_id := int(cpu_settlement["id"])
	_expect(
		WorldPoliticalState.set_polity_capital(
			cpu_polity_id,
			cpu_settlement_id
		),
		"A non-player polity must support its own capital relationship."
	)
	_expect(
		WorldPoliticalState.get_polity_snapshot().size() == 2
		and WorldPoliticalState.get_settlement_snapshot().size() == 3,
		"Player and CPU political records must coexist in the same registries."
	)
	_expect(
		WorldPoliticalState.validate_registry_integrity(),
		"Adding a second polity must preserve registry cross-reference integrity."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(cpu_settlement_id),
		"Any registered settlement must be selectable as the active identity."
	)
	var cpu_context = WorldPoliticalState.get_active_settlement_context()
	_expect(
		cpu_context != null
		and cpu_context.is_valid()
		and cpu_context.settlement_id == cpu_settlement_id
		and cpu_context.polity_id == cpu_polity_id
		and cpu_context.is_capital,
		"A second polity must receive an independent settlement context."
	)
	_expect(
		cpu_context != null and not cpu_context.supports_city_simulation(),
		"An unbound CPU settlement must never reuse the player's legacy city backend."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(player_capital_id),
		"The player capital must remain independently addressable after CPU setup."
	)
	var restored_context = WorldPoliticalState.get_active_settlement_context()
	_expect(
		restored_context != null
		and restored_context.settlement_id == player_capital_id
		and restored_context.supports_city_simulation(),
		"Returning to the player capital must restore only its bound city backend."
	)


func _make_world(width: int, height: int, seed: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed)

	for y in range(height):
		for x in range(width):
			world.tiles[y][x] = _make_land_tile()

	world.mark_tile_data_changed()
	return world


func _make_land_tile() -> Dictionary:
	return {
		"fertility": 55.0,
		"elevation": 0.2,
		"temperature": 0.5,
		"precipitation": 0.5,
		"terrain": WorldData.TERRAIN_LAND,
		"biome": WorldData.BIOME_PLAIN,
		"resource": WorldData.RESOURCE_NONE,
		"is_land": true,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("World political framework test: " + message)
