extends Node

const PresentationScript = preload(
	"res://scripts/citizens/rendering/CityCitizenMovementPresentation.gd"
)

var failure_count: int = 0
var presentation_city_state: CitySettlementSimulationState


func _ready() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture(
		"Movement Presentation Unit Culture"
	)
	var initial_city_state = _create_active_city_fixture(
		"Movement Presentation Unit City",
		int(culture.get("id", -1))
	)
	if not initial_city_state is CitySettlementSimulationState:
		_expect(
			false,
			"Movement presentation tests require an explicit City state."
		)
		get_tree().quit(1)
		return
	presentation_city_state = initial_city_state
	_configure_clock()
	_test_late_cardinal_observer_starts_at_current_segment()
	_test_late_diagonal_observer_starts_at_current_progress()
	_test_committed_trace_preserves_mixed_corners()
	_test_completed_route_remains_visualized()
	_test_zero_progress_route_waits_without_snapping()
	_test_immediate_partial_repath_returns_to_origin()
	_test_partial_completion_does_not_backtrack()
	_test_repath_after_old_corner_keeps_that_corner_first()
	_test_completed_replacement_route_returns_to_repath_origin()
	_test_visual_event_buffer_is_tick_scoped_and_take_once()
	_test_completed_road_doubles_visual_travel_speed()

	if failure_count > 0:
		push_error(
			"Movement presentation tests failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Movement presentation tests passed.")
	get_tree().quit(0)


func _configure_clock() -> void:
	SimulationClock.simulation_active = true
	SimulationClock.simulation_paused = false
	SimulationClock.speed_multiplier = 1.0
	SimulationClock.minutes_per_tick = 2
	SimulationClock.real_seconds_per_tick = 0.8333333333


func _test_late_cardinal_observer_starts_at_current_segment() -> void:
	var presentation := _make_presentation()
	var citizen := _make_moving_citizen(
		1,
		Vector2i(2, 1),
		[
			Vector2i(1, 1),
			Vector2i(2, 1),
			Vector2i(3, 1),
		],
		2,
		0
	)
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup = {1: true}
	presentation._synchronize_citizen_position(citizen, true)

	_expect_vector_close(
		presentation.get_visual_tile_position(citizen),
		Vector2(2.0, 1.0),
		"A late cardinal observer must not replay completed route tiles."
	)

	presentation.update(1.0 / 60.0)
	_expect_vector_close(
		presentation.get_visual_tile_position(citizen),
		Vector2(2.0, 1.0),
		"A late cardinal observer must remain at current segment progress."
	)


func _test_late_diagonal_observer_starts_at_current_progress() -> void:
	var presentation := _make_presentation()
	var citizen := _make_moving_citizen(
		2,
		Vector2i(1, 1),
		[
			Vector2i(1, 1),
			Vector2i(2, 2),
			Vector2i(3, 2),
		],
		1,
		10_000
	)
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup = {2: true}
	presentation._synchronize_citizen_position(citizen, true)

	_expect_vector_close(
		presentation.get_visual_tile_position(citizen),
		Vector2(1.70711356, 1.70711356),
		"A late diagonal observer must begin at current partial progress."
	)

	presentation.update(1.0 / 60.0)
	_expect_vector_close(
		presentation.get_visual_tile_position(citizen),
		Vector2(1.70711356, 1.70711356),
		"A late diagonal observer must not replay the route origin."
	)


func _test_committed_trace_preserves_mixed_corners() -> void:
	var presentation := _make_presentation()
	var movement_path := [
		Vector2i(0, 0),
		Vector2i(1, 1),
		Vector2i(2, 1),
		Vector2i(3, 2),
	]
	var before := _make_moving_citizen(
		3,
		Vector2i(0, 0),
		movement_path,
		1,
		0
	)
	var after := _make_moving_citizen(
		3,
		Vector2i(2, 1),
		movement_path,
		3,
		5_858
	)
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup = {3: true}

	var changed: bool = presentation.synchronize_committed_tick([
		{
			"citizen_id": 3,
			"before": before,
			"after": after,
			"traversed_tiles": [
				Vector2i(0, 0),
				Vector2i(1, 1),
				Vector2i(2, 1),
			],
		}
	])
	_expect(changed, "Committed movement trace must report a visual change.")
	_expect_vector_close(
		presentation.get_visual_tile_position(after),
		Vector2(0.0, 0.0),
		"Committed trace must retain its pre-tick visual origin."
	)

	var transition: Dictionary = (
		presentation.transition_by_citizen_id.get(3, {})
	)
	var waypoints: Array = transition.get("waypoints", [])
	_expect(
		waypoints.size() == 3,
		"Mixed trace must retain two consumed corners and the partial endpoint."
	)

	if waypoints.size() == 3:
		_expect_vector_close(
			waypoints[0],
			Vector2(1.0, 1.0),
			"Mixed trace lost its diagonal corner."
		)
		_expect_vector_close(
			waypoints[1],
			Vector2(2.0, 1.0),
			"Mixed trace lost its cardinal corner."
		)
		_expect(
			waypoints[2].x > 2.0
			and waypoints[2].y > 1.0,
			"Mixed trace lost its partial diagonal endpoint."
		)


func _test_completed_route_remains_visualized() -> void:
	var presentation := _make_presentation()
	var before := _make_moving_citizen(
		4,
		Vector2i(0, 0),
		[
			Vector2i(0, 0),
			Vector2i(1, 0),
		],
		1,
		0
	)
	var after := _make_idle_citizen(4, Vector2i(1, 0))
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup.clear()

	presentation.synchronize_committed_tick([
		{
			"citizen_id": 4,
			"before": before,
			"after": after,
			"traversed_tiles": [
				Vector2i(0, 0),
				Vector2i(1, 0),
			],
		}
	])
	_expect(
		presentation.transition_by_citizen_id.has(4),
		"A route completed before rendering must retain its visual transition."
	)
	_expect_vector_close(
		presentation.get_visual_tile_position(after),
		Vector2(0.0, 0.0),
		"Completed route must animate from its actual start."
	)


func _test_zero_progress_route_waits_without_snapping() -> void:
	var presentation := _make_presentation()
	var starting_citizen := _make_moving_citizen(
		5,
		Vector2i(1, 1),
		[
			Vector2i(1, 1),
			Vector2i(2, 2),
		],
		1,
		0
	)
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup = {5: true}
	presentation._synchronize_citizen_position(starting_citizen, true)
	presentation.update(1.0 / 60.0)

	_expect_vector_close(
		presentation.get_visual_tile_position(starting_citizen),
		Vector2(1.0, 1.0),
		"A zero-progress route must remain at its authoritative origin."
	)


func _test_immediate_partial_repath_returns_to_origin() -> void:
	var presentation := _make_presentation()
	var before := _make_moving_citizen(
		6,
		Vector2i(0, 0),
		[Vector2i(0, 0), Vector2i(1, 0)],
		1,
		5_000
	)
	var after := _make_moving_citizen(
		6,
		Vector2i(0, 0),
		[Vector2i(0, 0), Vector2i(0, 1)],
		1,
		5_000
	)
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup = {6: true}

	presentation.synchronize_committed_tick([{
		"citizen_id": 6,
		"before": before,
		"after": after,
		"traversed_tiles": [Vector2i(0, 0)],
	}])
	var transition: Dictionary = (
		presentation.transition_by_citizen_id.get(6, {})
	)
	var waypoints: Array = transition.get("waypoints", [])
	_expect(
		waypoints.size() == 2,
		"Immediate partial repath must return to origin before turning."
	)

	if waypoints.size() == 2:
		_expect_vector_close(
			waypoints[0],
			Vector2(0.0, 0.0),
			"Immediate partial repath skipped its authoritative origin."
		)


func _test_partial_completion_does_not_backtrack() -> void:
	var presentation := _make_presentation()
	var before := _make_moving_citizen(
		7,
		Vector2i(0, 0),
		[Vector2i(0, 0), Vector2i(1, 0)],
		1,
		5_000
	)
	var after := _make_idle_citizen(7, Vector2i(1, 0))
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup.clear()

	presentation.synchronize_committed_tick([{
		"citizen_id": 7,
		"before": before,
		"after": after,
		"traversed_tiles": [Vector2i(0, 0), Vector2i(1, 0)],
	}])
	var transition: Dictionary = (
		presentation.transition_by_citizen_id.get(7, {})
	)
	var waypoints: Array = transition.get("waypoints", [])
	_expect(
		waypoints.size() == 1,
		"Partial route completion must not backtrack to its origin."
	)

	if waypoints.size() == 1:
		_expect_vector_close(
			waypoints[0],
			Vector2(1.0, 0.0),
			"Partial completion must continue directly to its destination."
		)


func _test_repath_after_old_corner_keeps_that_corner_first() -> void:
	var presentation := _make_presentation()
	var before := _make_moving_citizen(
		8,
		Vector2i(0, 0),
		[
			Vector2i(0, 0),
			Vector2i(1, 0),
			Vector2i(2, 0),
		],
		1,
		5_000
	)
	var after := _make_moving_citizen(
		8,
		Vector2i(1, 0),
		[Vector2i(1, 0), Vector2i(1, 1)],
		1,
		5_000
	)
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup = {8: true}

	presentation.synchronize_committed_tick([{
		"citizen_id": 8,
		"before": before,
		"after": after,
		"traversed_tiles": [Vector2i(0, 0), Vector2i(1, 0)],
	}])
	var transition: Dictionary = (
		presentation.transition_by_citizen_id.get(8, {})
	)
	var waypoints: Array = transition.get("waypoints", [])
	_expect(
		waypoints.size() == 2,
		"Repath after an old corner must retain the corner and new endpoint."
	)

	if waypoints.size() == 2:
		_expect_vector_close(
			waypoints[0],
			Vector2(1.0, 0.0),
			"Repath after an old corner must not return to route origin."
		)


func _test_completed_replacement_route_returns_to_repath_origin() -> void:
	var presentation := _make_presentation()
	var before := _make_moving_citizen(
		9,
		Vector2i(0, 0),
		[Vector2i(0, 0), Vector2i(1, 0)],
		1,
		5_000
	)
	var after := _make_idle_citizen(9, Vector2i(0, 1))
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup.clear()

	presentation.synchronize_committed_tick([{
		"citizen_id": 9,
		"before": before,
		"after": after,
		"traversed_tiles": [Vector2i(0, 0), Vector2i(0, 1)],
	}])
	var transition: Dictionary = (
		presentation.transition_by_citizen_id.get(9, {})
	)
	var waypoints: Array = transition.get("waypoints", [])
	_expect(
		waypoints.size() == 2,
		"A completed replacement route must retain its repath origin."
	)

	if waypoints.size() == 2:
		_expect_vector_close(
			waypoints[0],
			Vector2(0.0, 0.0),
			"Completed replacement route skipped its repath origin."
		)
		_expect_vector_close(
			waypoints[1],
			Vector2(0.0, 1.0),
			"Completed replacement route lost its destination."
		)


func _test_visual_event_buffer_is_tick_scoped_and_take_once() -> void:
	CityCitizenMovementRuntimeSystem.clear_city_citizen_movement_visual_events()
	CityCitizenMovementRuntimeSystem.begin_city_citizen_movement_visual_tick(40)
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_events.append({"marker": 1})
	_expect(
		CityCitizenMovementRuntimeSystem.take_city_citizen_movement_visual_events(39).is_empty(),
		"A stale tick must not expose movement visual events."
	)

	CityCitizenMovementRuntimeSystem.begin_city_citizen_movement_visual_tick(41)
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_events.append({"marker": 2})
	var events := (
		CityCitizenMovementRuntimeSystem.take_city_citizen_movement_visual_events(41)
	)
	_expect(
		events.size() == 1
		and int(events[0].get("marker", -1)) == 2,
		"The matching tick must transfer its movement visual events."
	)
	_expect(
		CityCitizenMovementRuntimeSystem.take_city_citizen_movement_visual_events(41).is_empty(),
		"Movement visual events must be consumable only once."
	)
	CityCitizenMovementRuntimeSystem.clear_city_citizen_movement_visual_events()


func _test_completed_road_doubles_visual_travel_speed() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture(
		"Movement Presentation Test Culture"
	)
	var culture_id := int(culture.get("id", -1))
	var city_state = _create_active_city_fixture(
		"Movement Presentation Test City",
		culture_id
	)
	_expect(
		city_state is CitySettlementSimulationState,
		"The visual-speed fixture must own an active City simulation state."
	)
	if not city_state is CitySettlementSimulationState:
		return
	city_state.city_runtime_data.clear()
	city_state.city_runtime_data.merge({
		"name": "Movement Presentation Test City",
		"primary_culture_id": culture_id,
		"founded": true,
		"can_build": true,
	}, true)

	var city_world := WorldData.new()
	city_world.setup(4, 3, 91_733)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.get_tile_for_internal_read(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true

	WorldData.store_city_world_save(city_world, 91_733)
	_expect(
		not CityObjectSystem.add_city_road_object(
			[Vector2i(1, 0)],
			"player",
			city_world
		).is_empty(),
		"The visual-speed fixture must create one completed road tile."
	)

	var road_presentation := _make_presentation(city_state)
	var normal_presentation := _make_presentation(city_state)
	var road_before := _make_moving_citizen(
		20,
		Vector2i(0, 0),
		[Vector2i(0, 0), Vector2i(1, 0)],
		1,
		0
	)
	var road_after := _make_idle_citizen(20, Vector2i(1, 0))
	var normal_before := _make_moving_citizen(
		21,
		Vector2i(0, 1),
		[Vector2i(0, 1), Vector2i(1, 1)],
		1,
		0
	)
	var normal_after := _make_idle_citizen(21, Vector2i(1, 1))
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup.clear()

	road_presentation.synchronize_committed_tick([{
		"citizen_id": 20,
		"before": road_before,
		"after": road_after,
		"traversed_tiles": [Vector2i(0, 0), Vector2i(1, 0)],
	}])
	normal_presentation.synchronize_committed_tick([{
		"citizen_id": 21,
		"before": normal_before,
		"after": normal_after,
		"traversed_tiles": [Vector2i(0, 1), Vector2i(1, 1)],
	}])

	# At the configured clock rate this provides exactly 5,000 movement-cost
	# units: one full road tile or half of one ordinary tile.
	var comparison_delta := (
		1.0
		/ (
			float(SimulationClock.minutes_per_tick)
			/ SimulationClock.real_seconds_per_tick
		)
	)
	road_presentation.update(comparison_delta)
	normal_presentation.update(comparison_delta)
	_expect_vector_close(
		road_presentation.get_visual_tile_position(road_after),
		Vector2(1.0, 0.0),
		"A citizen entering a completed road must visually traverse the tile at double speed."
	)
	_expect_vector_close(
		normal_presentation.get_visual_tile_position(normal_after),
		Vector2(0.5, 1.0),
		"The same movement budget must cover only half an ordinary tile."
	)


func _make_presentation(
	city_state: CitySettlementSimulationState = null
) -> CityCitizenMovementPresentation:
	var resolved_state: CitySettlementSimulationState = city_state
	if resolved_state == null:
		resolved_state = presentation_city_state
	var presentation: CityCitizenMovementPresentation = (
		PresentationScript.new()
	)
	presentation.initialize(resolved_state)
	return presentation


func _create_active_city_fixture(
	city_name: String,
	culture_id: int
) -> CitySettlementSimulationState:
	if culture_id <= 0:
		return null
	var polity := WorldPoliticalState.create_polity({
		"name": city_name + " Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city := WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": Vector2i.ZERO,
		"world_region_center": Vector2i.ZERO,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	var city_id := int(city.get("id", -1))
	if city_id <= 0 or not WorldPoliticalState.set_active_settlement(city_id):
		return null
	return WorldPoliticalState.get_city_simulation_state(city_id)


func _make_moving_citizen(
	citizen_id: int,
	tile_position: Vector2i,
	movement_path: Array,
	path_index: int,
	progress: int
) -> Dictionary:
	return {
		"id": citizen_id,
		"alive": true,
		"city_tile_position": tile_position,
		"movement_state": CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING,
		"movement_path": movement_path.duplicate(),
		"movement_path_index": path_index,
		"movement_progress_basis_points": progress,
		"movement_speed_basis_points_per_minute": 5_000,
	}


func _make_idle_citizen(
	citizen_id: int,
	tile_position: Vector2i
) -> Dictionary:
	return {
		"id": citizen_id,
		"alive": true,
		"city_tile_position": tile_position,
		"movement_state": CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE,
		"movement_path": [],
		"movement_path_index": 0,
		"movement_progress_basis_points": 0,
		"movement_speed_basis_points_per_minute": 5_000,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)


func _expect_vector_close(
	actual: Vector2,
	expected: Vector2,
	message: String
) -> void:
	_expect(actual.distance_to(expected) <= 0.0001, message)
