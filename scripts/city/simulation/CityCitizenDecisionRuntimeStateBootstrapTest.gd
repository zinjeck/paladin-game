extends Node

const CityCitizenDecisionRuntimeStateScript = preload(
	"res://scripts/city/simulation/CityCitizenDecisionRuntimeState.gd"
)

const TEST_CITY_NAME := "Decision Bootstrap"
const TEST_CULTURE_NAME := "Decision Runtime Culture"

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_pre_context_state_adoption()
	_test_city_and_session_reset()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-decision runtime bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-decision runtime bootstrap test passed.")
	get_tree().quit(0)


func _test_state_defaults() -> void:
	var state_a := CityCitizenDecisionRuntimeStateScript.new()
	var state_b := CityCitizenDecisionRuntimeStateScript.new()
	_expect(
		_state_has_clean_defaults(state_a),
		"A new decision-runtime owner must have exact clean defaults."
	)
	_expect(
		not is_same(state_a, state_b)
		and not is_same(state_a.pending_decision_ids, state_b.pending_decision_ids)
		and not is_same(
			state_a.pending_decision_id_lookup,
			state_b.pending_decision_id_lookup
		)
		and not is_same(
			state_a.idle_anchor_tile_by_citizen_id,
			state_b.idle_anchor_tile_by_citizen_id
		)
		and not is_same(
			state_a.next_idle_decision_minute_by_citizen_id,
			state_b.next_idle_decision_minute_by_citizen_id
		)
		and not is_same(
			state_a.idle_choice_sequence_by_citizen_id,
			state_b.idle_choice_sequence_by_citizen_id
		),
		"Separate owners must never share mutable decision-runtime collections."
	)


func _test_pre_context_state_adoption() -> void:
	WorldData.reset_runtime_session_state()
	var world := _make_world(8, 8, 93_001)
	if not _lock_founding_world(world):
		return

	var bootstrap_state := CitizenDecisionSystem.get_current_state()
	var pending_ids: Array[int] = [9, 4]
	var pending_lookup: Dictionary = {9: true, 4: true}
	var anchors: Dictionary = {4: Vector2i(3, 2)}
	var deadlines: Dictionary = {4: 777}
	var sequences: Dictionary = {4: 6}
	bootstrap_state.pending_decision_ids = pending_ids
	bootstrap_state.pending_decision_id_lookup = pending_lookup
	bootstrap_state.runtime_initialized = true
	bootstrap_state.work_shift_was_active = true
	bootstrap_state.observed_assignment_version = 11
	bootstrap_state.recovery_scan_cursor = 2
	bootstrap_state.idle_scan_cursor = 3
	bootstrap_state.idle_anchor_tile_by_citizen_id = anchors
	bootstrap_state.next_idle_decision_minute_by_citizen_id = deadlines
	bootstrap_state.idle_choice_sequence_by_citizen_id = sequences
	bootstrap_state.autonomous_haul_scan_cursor = 4
	bootstrap_state.critical_food_scan_cursor = 5
	bootstrap_state.normal_food_scan_cursor = 6

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish a City settlement context."
	)
	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	var context = WorldPoliticalState.get_active_settlement_context()
	_expect(
		capital_state is CitySettlementSimulationState
		and is_same(
			capital_state.citizen_decision_runtime_state,
			bootstrap_state
		)
		and is_same(bootstrap_state.pending_decision_ids, pending_ids)
		and is_same(bootstrap_state.pending_decision_id_lookup, pending_lookup)
		and is_same(bootstrap_state.idle_anchor_tile_by_citizen_id, anchors)
		and is_same(
			bootstrap_state.next_idle_decision_minute_by_citizen_id,
			deadlines
		)
		and is_same(
			bootstrap_state.idle_choice_sequence_by_citizen_id,
			sequences
		),
		"The founding City must adopt the exact pre-context decision owner."
	)
	_expect(
		context != null
		and is_same(
			context.get_city_citizen_decision_runtime_state(),
			bootstrap_state
		)
		and is_same(CitizenDecisionSystem.get_current_state(), bootstrap_state)
		and _state_has_seeded_values(bootstrap_state),
		"Context and the focused scheduler must resolve one exact owner."
	)
	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data()
		and is_same(CitizenDecisionSystem.get_current_state(), bootstrap_state),
		"Repeated foundation synchronization must retain decision runtime."
	)


func _test_city_and_session_reset() -> void:
	var state := CitizenDecisionSystem.get_current_state()
	var pending_ids := state.pending_decision_ids
	var pending_lookup := state.pending_decision_id_lookup
	var anchors := state.idle_anchor_tile_by_citizen_id
	var deadlines := state.next_idle_decision_minute_by_citizen_id
	var sequences := state.idle_choice_sequence_by_citizen_id
	CitizenDecisionSystem.reset_runtime_state()
	_expect(
		is_same(CitizenDecisionSystem.get_current_state(), state)
		and is_same(state.pending_decision_ids, pending_ids)
		and is_same(state.pending_decision_id_lookup, pending_lookup)
		and is_same(state.idle_anchor_tile_by_citizen_id, anchors)
		and is_same(state.next_idle_decision_minute_by_citizen_id, deadlines)
		and is_same(state.idle_choice_sequence_by_citizen_id, sequences)
		and _state_has_clean_defaults(state),
		"A city reset must clear the exact active decision owner in place."
	)

	WorldData.reset_runtime_session_state()
	var fresh_state := CitizenDecisionSystem.get_current_state()
	_expect(
		not is_same(fresh_state, state)
		and _state_has_clean_defaults(fresh_state),
		"A session reset must replace decision runtime with fresh defaults."
	)


func _state_has_seeded_values(state: CityCitizenDecisionRuntimeStateScript) -> bool:
	return (
		state.pending_decision_ids == [9, 4]
		and state.pending_decision_id_lookup == {9: true, 4: true}
		and state.runtime_initialized
		and state.work_shift_was_active
		and state.observed_assignment_version == 11
		and state.recovery_scan_cursor == 2
		and state.idle_scan_cursor == 3
		and state.idle_anchor_tile_by_citizen_id == {4: Vector2i(3, 2)}
		and state.next_idle_decision_minute_by_citizen_id == {4: 777}
		and state.idle_choice_sequence_by_citizen_id == {4: 6}
		and state.autonomous_haul_scan_cursor == 4
		and state.critical_food_scan_cursor == 5
		and state.normal_food_scan_cursor == 6
	)


func _state_has_clean_defaults(state: CityCitizenDecisionRuntimeStateScript) -> bool:
	return (
		state.pending_decision_ids.is_empty()
		and state.pending_decision_id_lookup.is_empty()
		and not state.runtime_initialized
		and not state.work_shift_was_active
		and state.observed_assignment_version == -1
		and state.recovery_scan_cursor == 0
		and state.idle_scan_cursor == 0
		and state.idle_anchor_tile_by_citizen_id.is_empty()
		and state.next_idle_decision_minute_by_citizen_id.is_empty()
		and state.idle_choice_sequence_by_citizen_id.is_empty()
		and state.autonomous_haul_scan_cursor == 0
		and state.critical_food_scan_cursor == 0
		and state.normal_food_scan_cursor == 0
	)


func _lock_founding_world(world: WorldData) -> bool:
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(1, 1),
		"region_center": Vector2i(2, 2),
		"region_size": 3,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": TEST_CITY_NAME,
		"culture_name": TEST_CULTURE_NAME,
	})
	_expect(locked, "The founding fixture must lock its world.")
	return locked


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
	push_error("City citizen-decision runtime bootstrap test: " + message)
