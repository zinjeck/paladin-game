extends Node

const SHARED_CITIZEN_TILE := Vector2i(5, 5)
const CITY_A_DESTINATION := Vector2i(6, 5)
const CITY_B_DESTINATION := Vector2i(5, 6)
const SHARED_VISUAL_TICK := 701
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_equal_and_unequal_city_isolation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-movement runtime isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-movement runtime isolation test passed.")
	get_tree().quit(0)


func _test_equal_and_unequal_city_isolation() -> void:
	var fixture := _make_two_city_fixture()
	if fixture.is_empty():
		return
	var city_a_id := int(fixture["city_a_id"])
	var city_b_id := int(fixture["city_b_id"])
	var culture_id := int(fixture["culture_id"])
	var city_a := _seed_city(city_a_id, culture_id, 94_101, CITY_A_DESTINATION, "A")
	var city_b := _seed_city(city_b_id, culture_id, 94_202, CITY_B_DESTINATION, "B")
	if city_a.is_empty() or city_b.is_empty():
		return

	var state_a: CityCitizenMovementRuntimeState = city_a["movement_state"]
	var state_b: CityCitizenMovementRuntimeState = city_b["movement_state"]
	state_a.citizen_movement_version = 2
	state_b.citizen_movement_version = 2

	_expect(
		int(city_a["citizen_id"]) == 1
		and int(city_b["citizen_id"]) == 1
		and state_a.active_mover_ids == [1]
		and state_b.active_mover_ids == [1]
		and state_a.citizen_movement_version == state_b.citizen_movement_version
		and state_a.citizen_movement_visual_tick_index == SHARED_VISUAL_TICK
		and state_b.citizen_movement_visual_tick_index == SHARED_VISUAL_TICK,
		"Both Cities must independently reuse citizen ID, movement version, and visual tick."
	)
	_expect(
		not is_same(state_a, state_b)
		and not is_same(state_a.active_mover_ids, state_b.active_mover_ids)
		and not is_same(state_a.active_mover_id_lookup, state_b.active_mover_id_lookup)
		and not is_same(state_a.citizen_movement_visual_events, state_b.citizen_movement_visual_events),
		"Equal movement IDs and versions must retain distinct runtime owners."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and _bind_fixture_city(city_a_id)
		and is_same(
			city_a["city_state"].citizen_movement_runtime_state,
			state_a
		),
		"Explicit City A movement binding must ignore presentation selection B."
	)
	var taken_a := (
		CityCitizenMovementRuntimeSystem.take_city_citizen_movement_visual_events_for_city_state(
			city_a["city_state"],
			SHARED_VISUAL_TICK
		)
	)
	_expect(
		taken_a.size() == 1
		and str(taken_a[0].get("marker", "")) == "A"
		and state_a.citizen_movement_visual_events.is_empty()
		and state_b.citizen_movement_visual_events.size() == 1
		and str(state_b.citizen_movement_visual_events[0].get("marker", "")) == "B",
		"Taking A's equal-tick visual buffer must not consume B's buffer."
	)
	_expect(
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
			city_a["city_state"],
			1
		)
		and state_a.active_mover_ids.is_empty()
		and state_b.active_mover_ids == [1],
		"Cancelling A's equal local mover must not cancel B's mover."
	)
	_expect(
		_bind_fixture_city(city_b_id)
		and is_same(
			city_b["city_state"].citizen_movement_runtime_state,
			state_b
		)
		and state_b.active_mover_ids == [1],
		"A -> B must restore B's exact movement runtime."
	)
	_expect(
		_bind_fixture_city(city_a_id)
		and state_a.active_mover_ids.is_empty()
		and state_a.citizen_movement_visual_events.is_empty(),
		"A -> B -> A must preserve A's independent consumed/cancelled state."
	)

	var validation_a := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_a_id), true, false
	)
	var validation_b := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_b_id), true, false
	)
	_expect(
		int(validation_a.get("citizen_movement_runtime_state_instance_id", -1))
		== int(state_a.get_instance_id())
		and int(validation_b.get("citizen_movement_runtime_state_instance_id", -1))
		== int(state_b.get_instance_id())
		and int(validation_a.get("citizen_movement_runtime_state_instance_id", -1))
		!= int(validation_b.get("citizen_movement_runtime_state_instance_id", -1)),
		"Validator caches must distinguish equal-version movement owners."
	)


func _seed_city(
	city_id: int,
	culture_id: int,
	seed_value: int,
	destination: Vector2i,
	marker: String
) -> Dictionary:
	_expect(
		WorldPoliticalState.set_active_settlement(city_id)
		and _bind_fixture_city(city_id),
		"The seeded City must select presentation and bind its citizen owner."
	)
	var city_world := _make_world(12, 12, seed_value)
	var city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	if not city_state is CitySettlementSimulationState:
		_expect(false, "Each City must expose an explicit movement owner.")
		return {}
	WorldData.store_city_world_for_state(city_state, city_world, seed_value)
	var citizen := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		city_state,
		"",
		SHARED_CITIZEN_TILE,
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	var citizen_id := int(citizen.get("id", -1))
	if citizen_id != 1:
		_expect(false, "Each City must create local citizen 1.")
		return {}
	_expect(
		CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
			city_state,
			citizen_id,
			[SHARED_CITIZEN_TILE, destination]
		),
		"Each City must assign its own local movement order."
	)
	var movement_state: CityCitizenMovementRuntimeState = city_state.citizen_movement_runtime_state
	movement_state.citizen_movement_visual_events = [{
		"marker": marker,
		"citizen_id": citizen_id,
		"step_target": destination,
	}]
	movement_state.citizen_movement_visual_tick_index = SHARED_VISUAL_TICK
	return {
		"city_state": city_state,
		"citizen_id": citizen_id,
		"movement_state": movement_state,
	}


func _bind_fixture_city(city_id: int) -> bool:
	var city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	if not city_state is CitySettlementSimulationState:
		return false
	return true


func _make_two_city_fixture() -> Dictionary:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Movement Runtime Isolation Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Movement Runtime Isolation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Movement Runtime City A", polity_id, Vector2i(1, 1))
	var city_b := _create_city("Movement Runtime City B", polity_id, Vector2i(8, 8))
	if culture_id <= 0 or city_a.is_empty() or city_b.is_empty():
		_expect(false, "The two-City movement fixture must be created.")
		return {}
	return {
		"culture_id": culture_id,
		"city_a_id": int(city_a["id"]),
		"city_b_id": int(city_b["id"]),
	}


func _create_city(city_name: String, polity_id: int, region_center: Vector2i) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE,
	})


func _make_world(width: int, height: int, seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed_value)
	for y in range(height):
		for x in range(width):
			world.tiles[y][x] = {
				"fertility": 50.0,
				"elevation": 0.2,
				"temperature": 0.5,
				"precipitation": 0.5,
				"terrain": WorldData.TERRAIN_LAND,
				"biome": WorldData.BIOME_PLAIN,
				"resource": WorldData.RESOURCE_NONE,
				"is_land": true,
			}
	world.mark_tile_data_changed()
	return world


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City citizen-movement runtime isolation test: " + message)
