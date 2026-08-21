extends Node

const SHARED_CITIZEN_TILE := Vector2i(3, 3)
const SHARED_HOUSE_TILE := Vector2i(6, 6)
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_equal_version_city_isolation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-task runtime isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-task runtime isolation test passed.")
	get_tree().quit(0)


func _test_equal_version_city_isolation() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Task Runtime Isolation Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Task Runtime Isolation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Task Runtime City A", polity_id, Vector2i(1, 1))
	var city_b := _create_city("Task Runtime City B", polity_id, Vector2i(8, 8))
	if city_a.is_empty() or city_b.is_empty():
		_expect(false, "The fixture must create two Cities.")
		return

	var city_a_id := int(city_a["id"])
	var city_b_id := int(city_b["id"])
	var state_a := _seed_city(city_a_id, culture_id, 95_101)
	var state_b := _seed_city(city_b_id, culture_id, 95_202)
	if state_a.is_empty() or state_b.is_empty():
		return

	var task_state_a: CityCitizenTaskRuntimeState = state_a["task_state"]
	var task_state_b: CityCitizenTaskRuntimeState = state_b["task_state"]
	task_state_a.citizen_task_version = 7
	task_state_b.citizen_task_version = 7

	_expect(
		int(state_a["citizen_id"]) == 1
		and int(state_b["citizen_id"]) == 1
		and int(state_a["house_id"]) == 1
		and int(state_b["house_id"]) == 1
		and task_state_a.active_task_ids == [1]
		and task_state_b.active_task_ids == [1]
		and task_state_a.citizen_task_version == task_state_b.citizen_task_version,
		"Both Cities must independently reuse citizen, house, task IDs and equal versions."
	)
	_expect(
		not is_same(task_state_a, task_state_b)
		and not is_same(task_state_a.active_task_ids, task_state_b.active_task_ids)
		and not is_same(task_state_a.active_task_id_lookup, task_state_b.active_task_id_lookup),
		"Equal task IDs and versions must retain distinct runtime owners."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and _bind_fixture_city(city_a_id)
		and _current_task_matches_house(
			state_a["city_state"],
			int(state_a["house_id"])
		),
		"Explicit City A task lookup must ignore presentation selection B."
	)
	_expect(
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task_for_city_state(
			state_a["city_state"],
			1
		)
		and task_state_a.active_task_ids.is_empty()
		and task_state_b.active_task_ids == [1]
		and _task_matches_house(
			state_b["task_snapshot"],
			int(state_b["house_id"])
		),
		"Clearing A's equal local task must not clear B's task."
	)
	_expect(
		_bind_fixture_city(city_b_id)
		and _current_task_matches_house(
			state_b["city_state"],
			int(state_b["house_id"])
		)
		and task_state_b.active_task_ids == [1],
		"Binding B must recover its exact task runtime."
	)
	_expect(
		_bind_fixture_city(city_a_id)
		and CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
			state_a["city_state"],
			1
		).get(
			"kind", CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
		) == CityCitizens.CITY_CITIZEN_TASK_KIND_NONE,
		"A -> B -> A must preserve A's independent cleared state."
	)

	var validation_a := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_a_id), true, false
	)
	var validation_b := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_b_id), true, false
	)
	_expect(
		int(validation_a.get("citizen_task_runtime_state_instance_id", -1))
		== int(task_state_a.get_instance_id())
		and int(validation_b.get("citizen_task_runtime_state_instance_id", -1))
		== int(task_state_b.get_instance_id())
		and int(validation_a.get("citizen_task_runtime_state_instance_id", -1))
		!= int(validation_b.get("citizen_task_runtime_state_instance_id", -1)),
		"Validator caches must distinguish equal-version task owners."
	)


func _seed_city(
	city_id: int,
	culture_id: int,
	seed_value: int
) -> Dictionary:
	_expect(
		WorldPoliticalState.set_active_settlement(city_id)
		and _bind_fixture_city(city_id),
		"The seeded City must select presentation and bind its citizen owner."
	)
	var city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	if not city_state is CitySettlementSimulationState:
		return {}
	var city_world := _make_world(12, 12, seed_value)
	WorldData.store_city_world_for_state(city_state, city_world, seed_value)
	city_state.city_runtime_data.merge({
		"name": "Task Runtime Isolation City",
		"primary_culture_id": culture_id,
		"founded": true,
		"can_build": true,
	}, true)
	var house := CityObjectSystem.register_completed_city_object_for_city_state(
		city_state,
		{
		"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
		"top_left": SHARED_HOUSE_TILE,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_HOUSE
		),
		"object_owner": "player",
		"city_world": city_world,
		}
	)
	var house_id := int(house.get("id", -1))
	var citizen := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		city_state,
		"",
		SHARED_CITIZEN_TILE,
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	var citizen_id := int(citizen.get("id", -1))
	if citizen_id != 1 or house_id != 1:
		_expect(false, "Each City must create local citizen 1 and house 1.")
		return {}
	var task := {
		"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
		"source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE,
		"priority": 50,
		"target_object_id": house_id,
	}
	_expect(
		CityAssignmentSystem.assign_city_citizen_home_for_city_state(
			city_state,
			citizen_id,
			house_id
		)
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task_for_city_state(
			city_state,
			citizen_id,
			task
		),
		"Each City must assign its own valid local Return Home task."
	)
	return {
		"city_state": city_state,
		"citizen_id": citizen_id,
		"house_id": house_id,
		"task_state": city_state.citizen_task_runtime_state,
		"task_snapshot": (
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
				city_state,
				citizen_id
			)
		),
	}


func _current_task_matches_house(
	city_state: CitySettlementSimulationState,
	house_id: int
) -> bool:
	return _task_matches_house(
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
			city_state,
			1
		),
		house_id
	)


func _task_matches_house(task: Dictionary, house_id: int) -> bool:
	return (
		str(task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME
		and str(task.get("source", ""))
		== CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		and int(task.get("target_object_id", -1)) == house_id
	)


func _bind_fixture_city(city_id: int) -> bool:
	var city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	if not city_state is CitySettlementSimulationState:
		return false
	return true


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
	push_error("City citizen-task runtime isolation test: " + message)
