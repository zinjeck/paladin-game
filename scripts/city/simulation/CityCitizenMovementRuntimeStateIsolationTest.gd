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
	var city_a := _prepare_active_city_movement({
		"city_id": city_a_id,
		"culture_id": culture_id,
		"seed": 94_101,
		"destination": CITY_A_DESTINATION,
	})
	var city_b := _prepare_active_city_movement({
		"city_id": city_b_id,
		"culture_id": culture_id,
		"seed": 94_202,
		"destination": CITY_B_DESTINATION,
	})
	if city_a.is_empty() or city_b.is_empty():
		return

	var state_a: CityCitizenMovementRuntimeState = city_a["movement_state"]
	var state_b: CityCitizenMovementRuntimeState = city_b["movement_state"]
	var mover_ids_a: Array[int] = city_a["mover_ids"]
	var mover_ids_b: Array[int] = city_b["mover_ids"]
	var mover_lookup_a: Dictionary = city_a["mover_lookup"]
	var mover_lookup_b: Dictionary = city_b["mover_lookup"]
	var events_a: Array = city_a["visual_events"]
	var events_b: Array = city_b["visual_events"]

	_expect(
		int(city_a["citizen_id"]) == 1
		and int(city_b["citizen_id"]) == 1
		and state_a.citizen_movement_version == 2
		and state_b.citizen_movement_version
		== state_a.citizen_movement_version
		and state_a.citizen_movement_visual_tick_index
		== SHARED_VISUAL_TICK
		and state_b.citizen_movement_visual_tick_index
		== SHARED_VISUAL_TICK
		and mover_ids_a == [1]
		and mover_ids_b == [1]
		and bool(mover_lookup_a.get(1, false))
		and bool(mover_lookup_b.get(1, false)),
		"Both Cities must independently reuse ID, coordinate, version, and tick."
	)
	_expect(
		not is_same(state_a, state_b)
		and not is_same(mover_ids_a, mover_ids_b)
		and not is_same(mover_lookup_a, mover_lookup_b)
		and not is_same(events_a, events_b)
		and events_a.size() == 1
		and events_b.size() == 1
		and _event_step_target(events_a) == CITY_A_DESTINATION
		and _event_step_target(events_b) == CITY_B_DESTINATION,
		"Equal local identities must retain distinct owners and visual traces."
	)

	_test_renderer_identity_invalidation(city_b_id, state_b)
	_test_validator_identity_invalidation(city_b_id, state_b)
	_test_event_consumption_and_unequal_state({
		"city_a_id": city_a_id,
		"city_b_id": city_b_id,
		"state_a": state_a,
		"state_b": state_b,
		"events_a": events_a,
		"events_b": events_b,
	})

	var city_a_root = WorldPoliticalState.get_city_simulation_state(city_a_id)
	var city_b_root = WorldPoliticalState.get_city_simulation_state(city_b_id)
	_expect(
		city_a_root is CitySettlementSimulationState
		and city_b_root is CitySettlementSimulationState
		and is_same(city_a_root.citizen_movement_runtime_state, state_a)
		and is_same(city_b_root.citizen_movement_runtime_state, state_b)
		and not is_same(
			city_a_root.citizen_movement_runtime_state,
			city_b_root.citizen_movement_runtime_state
		),
		"Each City root must retain one distinct movement-runtime owner."
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
			active_context.get_city_citizen_movement_runtime_state(),
			state_b
		),
		"The active settlement context must resolve City B's exact owner."
	)


func _test_renderer_identity_invalidation(
	city_id: int,
	original_state: CityCitizenMovementRuntimeState
) -> void:
	var registry_state := (
		WorldPoliticalState.get_current_city_citizen_registry_state()
	)
	var spatial_state := (
		WorldPoliticalState.get_current_city_citizen_spatial_state()
	)
	var renderer := CityRenderer.new()
	renderer.observed_city_citizen_registry_state = registry_state
	renderer.observed_city_citizen_version = registry_state.citizen_version
	renderer.observed_city_citizen_spatial_state = spatial_state
	renderer.observed_city_citizen_spatial_version = (
		spatial_state.citizen_spatial_version
	)
	renderer.observed_city_citizen_movement_runtime_state = original_state
	renderer.observed_city_citizen_movement_version = (
		original_state.citizen_movement_version
	)
	renderer.synchronized_city_citizen_movement_version = (
		original_state.citizen_movement_version
	)
	renderer.city_citizen_movement_presentation.movement_snapshot_by_citizen_id = {
		1: {"marker": "old-owner"},
	}
	renderer.city_citizen_movement_presentation.visual_position_by_citizen_id = {
		1: Vector2(99.0, 99.0),
	}
	renderer.city_citizen_movement_presentation.transition_by_citizen_id = {
		1: {"marker": "old-owner"},
	}
	renderer.city_citizen_movement_presentation.tracked_mover_id_lookup = {
		1: true,
	}

	var replacement_state := _clone_movement_state(original_state)
	var city_root = WorldPoliticalState.get_city_simulation_state(city_id)
	city_root.citizen_movement_runtime_state = replacement_state
	var change_flags: Dictionary = {}
	renderer._collect_world_data_change_flags(change_flags)
	_expect(
		bool(change_flags.get("city_citizen_movement_changed", false))
		and bool(
			change_flags.get(
				"city_citizen_movement_runtime_changed",
				false
			)
		)
		and not bool(change_flags.get("city_citizens_changed", false))
		and not bool(
			change_flags.get("city_citizen_spatial_changed", false)
		)
		and is_same(
			renderer.observed_city_citizen_movement_runtime_state,
			replacement_state
		)
		and renderer.observed_city_citizen_movement_version
		== original_state.citizen_movement_version,
		"Renderer refresh must include movement-owner identity at equal versions."
	)
	renderer._synchronize_city_citizen_movement(change_flags)
	var current_snapshot: Dictionary = (
		renderer
		.city_citizen_movement_presentation
		.movement_snapshot_by_citizen_id.get(1, {})
	)
	_expect(
		not current_snapshot.has("marker")
		and renderer
		.city_citizen_movement_presentation
		.visual_position_by_citizen_id.get(1, Vector2.ZERO)
		!= Vector2(99.0, 99.0)
		and renderer
		.city_citizen_movement_presentation
		.transition_by_citizen_id.is_empty()
		and renderer
		.city_citizen_movement_presentation
		.tracked_mover_id_lookup.has(1)
		and renderer.synchronized_city_citizen_movement_version
		== replacement_state.citizen_movement_version,
		"Owner replacement must discard stale cosmetic state before retracking."
	)
	city_root.citizen_movement_runtime_state = original_state
	renderer.free()


func _test_validator_identity_invalidation(
	city_id: int,
	original_state: CityCitizenMovementRuntimeState
) -> void:
	var first_validation := CityStateValidatorScript.validate(true, false)
	var replacement_state := _clone_movement_state(original_state)
	replacement_state.active_mover_id_lookup.clear()
	var city_root = WorldPoliticalState.get_city_simulation_state(city_id)
	city_root.citizen_movement_runtime_state = replacement_state
	var second_validation := CityStateValidatorScript.validate(false, false)
	_expect(
		int(first_validation.get(
			"citizen_movement_runtime_state_instance_id",
			-1
		)) == int(original_state.get_instance_id())
		and int(second_validation.get(
			"citizen_movement_runtime_state_instance_id",
			-1
		)) == int(replacement_state.get_instance_id())
		and _contains_error_fragment(
			second_validation.get("errors", []),
			"Active-mover lookup is missing citizen 1"
		),
		"Validator cache must inspect an equal-version movement-owner replacement."
	)
	city_root.citizen_movement_runtime_state = original_state
	CityStateValidatorScript.validate(true, false)


func _test_event_consumption_and_unequal_state(values: Dictionary) -> void:
	var city_a_id := int(values["city_a_id"])
	var city_b_id := int(values["city_b_id"])
	var state_a: CityCitizenMovementRuntimeState = values["state_a"]
	var state_b: CityCitizenMovementRuntimeState = values["state_b"]
	var events_a: Array = values["events_a"]
	var events_b: Array = values["events_b"]
	var version_b_before_take := state_b.citizen_movement_version
	var taken_b := WorldData.take_city_citizen_movement_visual_events(
		SHARED_VISUAL_TICK
	)
	_expect(
		is_same(taken_b, events_b)
		and not is_same(state_b.citizen_movement_visual_events, events_b)
		and state_b.citizen_movement_visual_events.is_empty()
		and state_b.citizen_movement_visual_tick_index == -1
		and state_b.citizen_movement_version == version_b_before_take
		and WorldData.take_city_citizen_movement_visual_events(
			SHARED_VISUAL_TICK
		).is_empty(),
		"Matching take must transfer City B's buffer once without invalidating."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and is_same(
			WorldPoliticalState
			.get_current_city_citizen_movement_runtime_state(),
			state_a
		)
		and is_same(
			WorldData.city_citizen_movement_visual_events,
			events_a
		)
		and WorldData.city_citizen_movement_visual_tick_index
		== SHARED_VISUAL_TICK
		and WorldData.city_citizen_movement_version == 2,
		"Consuming City B's equal tick must leave City A untouched."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and WorldData.cancel_city_citizen_movement(1),
		"City B's mover must cancel through the real movement API."
	)
	WorldData.begin_city_citizen_movement_visual_tick(802)
	WorldData.city_citizen_movement_visual_events.append({"marker": "B-late"})
	var late_events_b: Array = WorldData.city_citizen_movement_visual_events
	_expect(
		state_b.citizen_movement_version == 3
		and state_b.active_mover_ids.is_empty()
		and state_b.active_mover_id_lookup.is_empty()
		and state_b.citizen_movement_visual_tick_index == 802,
		"City B must diverge to its own later version and visual tick."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and state_a.citizen_movement_version == 2
		and state_a.active_mover_ids == [1]
		and is_same(state_a.citizen_movement_visual_events, events_a)
		and state_a.citizen_movement_visual_tick_index
		== SHARED_VISUAL_TICK,
		"City A must retain its earlier version, mover, event buffer, and tick."
	)
	var taken_a := WorldData.take_city_citizen_movement_visual_events(
		SHARED_VISUAL_TICK
	)
	_expect(
		is_same(taken_a, events_a)
		and state_a.citizen_movement_version == 2,
		"Taking City A's buffer must transfer only City A's exact events."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and is_same(
			WorldData.city_citizen_movement_visual_events,
			late_events_b
		)
		and WorldData.city_citizen_movement_visual_tick_index == 802
		and WorldData.city_citizen_movement_version == 3
		and WorldData.take_city_citizen_movement_visual_events(801).is_empty()
		and state_b.citizen_movement_visual_events.is_empty()
		and state_b.citizen_movement_visual_tick_index == -1
		and state_b.citizen_movement_version == 3,
		"A stale take must clear only City B's active buffer without invalidating."
	)


func _prepare_active_city_movement(values: Dictionary) -> Dictionary:
	var city_id := int(values.get("city_id", -1))
	var culture_id := int(values.get("culture_id", -1))
	var seed_value := int(values.get("seed", 0))
	var destination: Vector2i = values.get(
		"destination",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_id),
		"The requested isolation City must become active."
	)
	var city_world := _make_world(12, 12, seed_value)
	WorldData.official_city_world = city_world
	WorldData.official_city_seed = seed_value
	var citizen := WorldData.add_city_citizen(
		"",
		SHARED_CITIZEN_TILE,
		WorldData.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	var citizen_id := int(citizen.get("id", -1))
	_expect(
		citizen_id == 1
		and WorldData.assign_city_citizen_movement_order(
			citizen_id,
			[SHARED_CITIZEN_TILE, destination]
		),
		"Each City must create and route its local citizen 1."
	)
	if citizen_id != 1:
		return {}

	CitizenMovementSystem.run_tick(SHARED_VISUAL_TICK, 1)
	var movement_state := (
		WorldPoliticalState
		.get_current_city_citizen_movement_runtime_state()
	)
	return {
		"citizen_id": citizen_id,
		"movement_state": movement_state,
		"mover_ids": movement_state.active_mover_ids,
		"mover_lookup": movement_state.active_mover_id_lookup,
		"visual_events": movement_state.citizen_movement_visual_events,
	}


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
	var city_a := _create_city(
		"Movement Runtime City A",
		polity_id,
		Vector2i(1, 1)
	)
	var city_b := _create_city(
		"Movement Runtime City B",
		polity_id,
		Vector2i(8, 8)
	)
	_expect(
		not city_a.is_empty() and not city_b.is_empty(),
		"The fixture must create two instance-owned Cities."
	)
	if city_a.is_empty() or city_b.is_empty():
		return {}
	return {
		"city_a_id": int(city_a["id"]),
		"city_b_id": int(city_b["id"]),
		"culture_id": culture_id,
	}


func _clone_movement_state(
	source: CityCitizenMovementRuntimeState
) -> CityCitizenMovementRuntimeState:
	var clone := CityCitizenMovementRuntimeState.new()
	clone.active_mover_ids = source.active_mover_ids.duplicate()
	clone.active_mover_id_lookup = source.active_mover_id_lookup.duplicate(true)
	clone.citizen_movement_visual_events = (
		source.citizen_movement_visual_events.duplicate(true)
	)
	clone.citizen_movement_visual_tick_index = (
		source.citizen_movement_visual_tick_index
	)
	clone.citizen_movement_version = source.citizen_movement_version
	return clone


func _event_step_target(events: Array):
	if events.size() != 1 or not events[0] is Dictionary:
		return WorldData.INVALID_CITY_TILE_POSITION
	var after = events[0].get("after", {})
	if not after is Dictionary:
		return WorldData.INVALID_CITY_TILE_POSITION
	return after.get(
		"movement_visual_step_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)


func _contains_error_fragment(raw_errors, fragment: String) -> bool:
	if not raw_errors is Array:
		return false
	for raw_error in raw_errors:
		if fragment in str(raw_error):
			return true
	return false


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
