extends Node

const SHARED_CITIZEN_TILE := Vector2i(3, 3)
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
	var fixture := _make_two_city_fixture()
	if fixture.is_empty():
		return

	var city_a_id := int(fixture["city_a_id"])
	var city_b_id := int(fixture["city_b_id"])
	var culture_id := int(fixture["culture_id"])
	var city_a := _prepare_active_city_task(
		city_a_id,
		culture_id,
		91_101
	)
	var city_b := _prepare_active_city_task(
		city_b_id,
		culture_id,
		91_202
	)
	if city_a.is_empty() or city_b.is_empty():
		return

	var state_a: CityCitizenTaskRuntimeState = city_a["task_state"]
	var state_b: CityCitizenTaskRuntimeState = city_b["task_state"]
	var task_ids_a: Array[int] = city_a["task_ids"]
	var task_ids_b: Array[int] = city_b["task_ids"]
	var task_lookup_a: Dictionary = city_a["task_lookup"]
	var task_lookup_b: Dictionary = city_b["task_lookup"]

	_expect(
		int(city_a["citizen_id"]) == 1
		and int(city_b["citizen_id"]) == 1
		and state_a.citizen_task_version == 1
		and state_b.citizen_task_version == state_a.citizen_task_version
		and task_ids_a == [1]
		and task_ids_b == [1]
		and _lookup_matches_ids(task_lookup_a, [1])
		and _lookup_matches_ids(task_lookup_b, [1]),
		"Both Cities must independently reuse citizen ID and task version."
	)
	_expect(
		not is_same(state_a, state_b)
		and not is_same(task_ids_a, task_ids_b)
		and not is_same(task_lookup_a, task_lookup_b),
		"Equal local values must retain distinct task owners and collections."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and is_same(
			CityCitizenTaskRuntimeSystem.get_current_state(),
			state_a
		)
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids, task_ids_a)
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup, task_lookup_a)
		and CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version == 1,
		"A -> B -> A must restore City A's exact task owner."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and is_same(
			CityCitizenTaskRuntimeSystem.get_current_state(),
			state_b
		)
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids, task_ids_b)
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup, task_lookup_b)
		and CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version == 1,
		"A -> B -> A -> B must leave City B unchanged."
	)

	_test_renderer_identity_invalidation(city_b_id, state_b)
	_test_validator_identity_invalidation(city_b_id, state_b)
	_test_reservation_invalidation_is_local({
		"city_a_id": city_a_id,
		"city_b_id": city_b_id,
		"state_a": state_a,
		"state_b": state_b,
	})

	var city_a_root = WorldPoliticalState.get_city_simulation_state(city_a_id)
	var city_b_root = WorldPoliticalState.get_city_simulation_state(city_b_id)
	_expect(
		city_a_root is CitySettlementSimulationState
		and city_b_root is CitySettlementSimulationState
		and is_same(city_a_root.citizen_task_runtime_state, state_a)
		and is_same(city_b_root.citizen_task_runtime_state, state_b)
		and not is_same(
			city_a_root.citizen_task_runtime_state,
			city_b_root.citizen_task_runtime_state
		),
		"Each City root must retain one distinct task-runtime owner."
	)
	var active_context := SettlementSimulationContext.new({
		"settlement_id": city_b_id,
		"polity_id": 1,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
		"local_state": city_b_root,
	})
	_expect(
		active_context != null
		and is_same(
			active_context.get_city_citizen_task_runtime_state(),
			state_b
		),
		"The active settlement context must resolve City B's exact owner."
	)


func _test_renderer_identity_invalidation(
	city_id: int,
	original_state: CityCitizenTaskRuntimeState
) -> void:
	var renderer := CityRenderer.new()
	var registry_state := (
		CityCitizenRegistrySystem.get_current_state()
	)
	var spatial_state := (
		CityCitizenSpatialSystem.get_current_state()
	)
	var movement_state := (
		CityCitizenMovementRuntimeSystem.get_current_state()
	)
	renderer.observed_city_citizen_registry_state = registry_state
	renderer.observed_city_citizen_version = registry_state.citizen_version
	renderer.observed_city_citizen_spatial_state = spatial_state
	renderer.observed_city_citizen_spatial_version = (
		spatial_state.citizen_spatial_version
	)
	renderer.observed_city_citizen_movement_runtime_state = movement_state
	renderer.observed_city_citizen_movement_version = (
		movement_state.citizen_movement_version
	)
	renderer.observed_city_citizen_task_runtime_state = original_state
	renderer.observed_city_citizen_task_version = (
		original_state.citizen_task_version
	)
	var no_change_flags: Dictionary = {}
	renderer._collect_world_data_change_flags(no_change_flags)
	_expect(
		not bool(no_change_flags.get("city_citizen_task_changed", false))
		and not bool(
			no_change_flags.get("city_citizen_task_runtime_changed", false)
		),
		"An unchanged owner and version must not invalidate task presentation."
	)

	var replacement_state := _clone_task_state(original_state)
	var city_root = WorldPoliticalState.get_city_simulation_state(city_id)
	city_root.citizen_task_runtime_state = replacement_state
	var change_flags: Dictionary = {}
	renderer._collect_world_data_change_flags(change_flags)
	_expect(
		bool(change_flags.get("city_citizen_task_changed", false))
		and bool(
			change_flags.get("city_citizen_task_runtime_changed", false)
		)
		and is_same(
			renderer.observed_city_citizen_task_runtime_state,
			replacement_state
		)
		and renderer.observed_city_citizen_task_version
		== original_state.citizen_task_version,
		"Renderer refresh must include task-owner identity at equal versions."
	)
	city_root.citizen_task_runtime_state = original_state
	renderer.free()


func _test_validator_identity_invalidation(
	city_id: int,
	original_state: CityCitizenTaskRuntimeState
) -> void:
	var first_validation := CityStateValidatorScript.validate(true, false)
	var replacement_state := _clone_task_state(original_state)
	replacement_state.active_task_id_lookup.clear()
	var city_root = WorldPoliticalState.get_city_simulation_state(city_id)
	city_root.citizen_task_runtime_state = replacement_state
	var second_validation := CityStateValidatorScript.validate(false, false)
	_expect(
		int(first_validation.get(
			"citizen_task_runtime_state_instance_id",
			-1
		)) == int(original_state.get_instance_id())
		and int(second_validation.get(
			"citizen_task_runtime_state_instance_id",
			-1
		)) == int(replacement_state.get_instance_id())
		and _contains_error_fragment(
			second_validation.get("errors", []),
			"Active task lookup is missing citizen ID 1"
		),
		"Validator cache must inspect an equal-version task-owner replacement."
	)
	city_root.citizen_task_runtime_state = original_state
	CityStateValidatorScript.validate(true, false)


func _test_reservation_invalidation_is_local(values: Dictionary) -> void:
	var city_a_id := int(values["city_a_id"])
	var city_b_id := int(values["city_b_id"])
	var state_a: CityCitizenTaskRuntimeState = values["state_a"]
	var state_b: CityCitizenTaskRuntimeState = values["state_b"]
	var version_a := state_a.citizen_task_version
	var version_b := state_b.citizen_task_version
	CityLogisticsSystem.reset_city_haul_reservation_state()
	_expect(
		state_a.citizen_task_version == version_a
		and state_b.citizen_task_version == version_b + 1,
		"Reservation invalidation must update only the active City's task owner."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version == version_a
		and WorldPoliticalState.set_active_settlement(city_b_id)
		and CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version == version_b + 1,
		"Switching must preserve the cross-domain invalidation in City B only."
	)


func _prepare_active_city_task(
	city_id: int,
	culture_id: int,
	seed_value: int
) -> Dictionary:
	_expect(
		WorldPoliticalState.set_active_settlement(city_id),
		"The fixture City must become active."
	)
	var city_world := _make_world(18, 18, seed_value)
	WorldPoliticalState.set_current_city_world(city_world)
	WorldPoliticalState.set_current_city_seed(seed_value)
	var city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	_expect(
		city_state is CitySettlementSimulationState,
		"The task fixture must expose its settlement-owned City state."
	)
	if not city_state is CitySettlementSimulationState:
		return {}
	var settlement := WorldPoliticalState.get_settlement(city_id)
	city_state.city_runtime_data.clear()
	city_state.city_runtime_data.merge({
		"name": str(settlement.get("name", "Task City")),
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}, true)
	var keep_top_left := Vector2i(0, 10)
	var keep := CityObjectSystem.register_completed_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		"top_left": keep_top_left,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	_expect(
		not keep.is_empty(),
		"The task fixture must register its Keep while still unfounded."
	)
	if keep.is_empty():
		return {}
	city_state.city_runtime_data.merge({
		"founded": true,
		"can_build": true,
		"foundation_top_left": keep_top_left,
		"foundation_size": keep.get("size", Vector2i.ZERO),
		"foundation_object_id": int(keep.get("id", -1)),
		"foundation_object_owner": str(keep.get("owner", "")),
	}, true)
	var house := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(8, 8),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_HOUSE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var house_id := int(house.get("id", -1))
	var citizen := CityCitizenRegistrySystem.add_city_citizen(
		"",
		SHARED_CITIZEN_TILE,
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	var citizen_id := int(citizen.get("id", -1))
	_expect(
		house_id > 0
		and citizen_id == 1
		and CityAssignmentSystem.assign_city_citizen_home(citizen_id, house_id)
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, {
			"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
			"source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE,
			"priority": 50,
			"target_object_id": house_id,
		}),
		"Each City must create one real active Return Home task."
	)
	var task_state := (
		CityCitizenTaskRuntimeSystem.get_current_state()
	)
	return {
		"citizen_id": citizen_id,
		"task_state": task_state,
		"task_ids": task_state.active_task_ids,
		"task_lookup": task_state.active_task_id_lookup,
	}


func _make_two_city_fixture() -> Dictionary:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Task Runtime Isolation Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Task Runtime Isolation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Task City A", polity_id, Vector2i(1, 1))
	var city_b := _create_city("Task City B", polity_id, Vector2i(2, 2))
	if culture_id <= 0 or city_a.is_empty() or city_b.is_empty():
		_expect(false, "The two-City fixture must be created.")
		return {}
	return {
		"culture_id": culture_id,
		"city_a_id": int(city_a["id"]),
		"city_b_id": int(city_b["id"]),
	}


func _create_city(
	city_name: String,
	polity_id: int,
	region_center: Vector2i
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


func _clone_task_state(
	source: CityCitizenTaskRuntimeState
) -> CityCitizenTaskRuntimeState:
	var clone := CityCitizenTaskRuntimeState.new()
	clone.active_task_ids.append_array(source.active_task_ids)
	clone.active_task_id_lookup.merge(source.active_task_id_lookup)
	clone.citizen_task_version = source.citizen_task_version
	return clone


func _lookup_matches_ids(lookup: Dictionary, expected_ids: Array) -> bool:
	if lookup.size() != expected_ids.size():
		return false
	for raw_id in expected_ids:
		var citizen_id := int(raw_id)
		if not lookup.has(citizen_id) or not bool(lookup[citizen_id]):
			return false
	return true


func _contains_error_fragment(errors: Array, fragment: String) -> bool:
	for raw_error in errors:
		if str(raw_error).contains(fragment):
			return true
	return false


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
