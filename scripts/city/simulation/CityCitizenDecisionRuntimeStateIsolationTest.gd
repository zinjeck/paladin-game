extends Node

const CityCitizenDecisionRuntimeStateScript = preload(
	"res://scripts/city/simulation/CityCitizenDecisionRuntimeState.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_city_isolation_and_future_ordering()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-decision runtime isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-decision runtime isolation test passed.")
	get_tree().quit(0)


func _test_city_isolation_and_future_ordering() -> void:
	var fixture := _make_two_city_fixture()
	if fixture.is_empty():
		return
	var city_a_id := int(fixture["city_a_id"])
	var city_b_id := int(fixture["city_b_id"])

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id),
		"City A must become active."
	)
	var state_a := CitizenDecisionSystem.get_current_state()
	_seed_state(state_a, 10)
	var identity_a := _capture_identity(state_a)
	var values_a := _capture_values(state_a)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"City B must become active."
	)
	var state_b := CitizenDecisionSystem.get_current_state()
	_seed_state(state_b, 20)
	var identity_b := _capture_identity(state_b)
	var values_b := _capture_values(state_b)

	_expect(
		not is_same(state_a, state_b)
		and not is_same(
			state_a.pending_decision_ids,
			state_b.pending_decision_ids
		)
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
		"Every City must own distinct decision runtime and collections."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and is_same(CitizenDecisionSystem.get_current_state(), state_a)
		and _matches_identity(state_a, identity_a)
		and _matches_values(state_a, values_a),
		"A -> B -> A must restore City A exactly."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and is_same(CitizenDecisionSystem.get_current_state(), state_b)
		and _matches_identity(state_b, identity_b)
		and _matches_values(state_b, values_b),
		"Returning to City B must restore its exact scheduler state."
	)

	# Execute the public scheduler boundary in B. With no B citizens it takes the
	# deterministic empty-city reset path; City A must remain byte-for-byte stable.
	CitizenDecisionSystem.run_tick(1, 1)
	_expect(
		_state_has_clean_defaults(state_b),
		"Running City B must mutate only City B's scheduler owner."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and _matches_identity(state_a, identity_a)
		and _matches_values(state_a, values_a),
		"Running City B must not mutate any City A decision runtime."
	)

	# Drive the real pending-queue and scan-order seams in A.
	CitizenDecisionSystem._queue_citizen_id(77)
	CitizenDecisionSystem._queue_citizen_id(77)
	var first_a_scan := CitizenDecisionSystem._take_food_scan_start_index(
		false,
		50
	)
	var a_values_after_step := _capture_values(state_a)
	_expect(
		state_a.pending_decision_ids == [10, 11, 77]
		and state_a.pending_decision_id_lookup.has(77)
		and first_a_scan == 21
		and state_a.normal_food_scan_cursor == 22,
		"City A must retain exact queue order and advance its own scan cursor."
	)

	# Merely making B visible/active must not reset or advance A. B's next scan is
	# independent; A then continues with the exact next index it had before.
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"City B must become visible for the ordering check."
	)
	state_b.normal_food_scan_cursor = 4
	var first_b_scan := CitizenDecisionSystem._take_food_scan_start_index(false, 5)
	_expect(
		first_b_scan == 4 and state_b.normal_food_scan_cursor == 0,
		"City B must advance its own independent future ordering."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and _matches_identity(state_a, identity_a)
		and _matches_values(state_a, a_values_after_step),
		"A visible-city round trip alone must not alter City A's future order."
	)
	var second_a_scan := CitizenDecisionSystem._take_food_scan_start_index(
		false,
		50
	)
	_expect(
		second_a_scan == 22 and state_a.normal_food_scan_cursor == 23,
		"City A must resume at the exact next scheduled scan index."
	)

	var city_b_root = WorldPoliticalState.get_city_simulation_state(city_b_id)
	var context := SettlementSimulationContext.new({
		"settlement_id": city_b_id,
		"polity_id": int(fixture["polity_id"]),
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"backend_kind": SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE,
		"local_state": city_b_root,
	})
	_expect(
		is_same(
			context.get_city_citizen_decision_runtime_state(),
			state_b
		),
		"Settlement context must expose City B's exact decision owner."
	)


func _seed_state(state: CityCitizenDecisionRuntimeStateScript, base: int) -> void:
	state.pending_decision_ids.append_array([base, base + 1])
	state.pending_decision_id_lookup[base] = true
	state.pending_decision_id_lookup[base + 1] = true
	state.runtime_initialized = true
	state.work_shift_was_active = base == 10
	state.observed_assignment_version = base + 2
	state.recovery_scan_cursor = base + 3
	state.idle_scan_cursor = base + 4
	state.idle_anchor_tile_by_citizen_id[base] = Vector2i(base, base + 1)
	state.next_idle_decision_minute_by_citizen_id[base] = base + 5
	state.idle_choice_sequence_by_citizen_id[base] = base + 6
	state.autonomous_haul_scan_cursor = base + 7
	state.critical_food_scan_cursor = base + 8
	state.normal_food_scan_cursor = base + 11


func _capture_identity(state: CityCitizenDecisionRuntimeStateScript) -> Dictionary:
	return {
		"pending_ids": state.pending_decision_ids,
		"pending_lookup": state.pending_decision_id_lookup,
		"anchors": state.idle_anchor_tile_by_citizen_id,
		"deadlines": state.next_idle_decision_minute_by_citizen_id,
		"sequences": state.idle_choice_sequence_by_citizen_id,
	}


func _capture_values(state: CityCitizenDecisionRuntimeStateScript) -> Dictionary:
	return {
		"pending_ids": state.pending_decision_ids.duplicate(),
		"pending_lookup": state.pending_decision_id_lookup.duplicate(true),
		"runtime_initialized": state.runtime_initialized,
		"work_shift_was_active": state.work_shift_was_active,
		"observed_assignment_version": state.observed_assignment_version,
		"recovery_scan_cursor": state.recovery_scan_cursor,
		"idle_scan_cursor": state.idle_scan_cursor,
		"anchors": state.idle_anchor_tile_by_citizen_id.duplicate(true),
		"deadlines": state.next_idle_decision_minute_by_citizen_id.duplicate(true),
		"sequences": state.idle_choice_sequence_by_citizen_id.duplicate(true),
		"autonomous_haul_scan_cursor": state.autonomous_haul_scan_cursor,
		"critical_food_scan_cursor": state.critical_food_scan_cursor,
		"normal_food_scan_cursor": state.normal_food_scan_cursor,
	}


func _matches_identity(
	state: CityCitizenDecisionRuntimeStateScript,
	identity: Dictionary
) -> bool:
	return (
		is_same(state.pending_decision_ids, identity["pending_ids"])
		and is_same(state.pending_decision_id_lookup, identity["pending_lookup"])
		and is_same(state.idle_anchor_tile_by_citizen_id, identity["anchors"])
		and is_same(
			state.next_idle_decision_minute_by_citizen_id,
			identity["deadlines"]
		)
		and is_same(
			state.idle_choice_sequence_by_citizen_id,
			identity["sequences"]
		)
	)


func _matches_values(
	state: CityCitizenDecisionRuntimeStateScript,
	values: Dictionary
) -> bool:
	return (
		state.pending_decision_ids == values["pending_ids"]
		and state.pending_decision_id_lookup == values["pending_lookup"]
		and state.runtime_initialized == values["runtime_initialized"]
		and state.work_shift_was_active == values["work_shift_was_active"]
		and state.observed_assignment_version
		== values["observed_assignment_version"]
		and state.recovery_scan_cursor == values["recovery_scan_cursor"]
		and state.idle_scan_cursor == values["idle_scan_cursor"]
		and state.idle_anchor_tile_by_citizen_id == values["anchors"]
		and state.next_idle_decision_minute_by_citizen_id == values["deadlines"]
		and state.idle_choice_sequence_by_citizen_id == values["sequences"]
		and state.autonomous_haul_scan_cursor
		== values["autonomous_haul_scan_cursor"]
		and state.critical_food_scan_cursor == values["critical_food_scan_cursor"]
		and state.normal_food_scan_cursor == values["normal_food_scan_cursor"]
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


func _make_two_city_fixture() -> Dictionary:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Decision Runtime Isolation Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Decision Runtime Isolation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Decision City A", polity_id, Vector2i(1, 1))
	var city_b := _create_city("Decision City B", polity_id, Vector2i(2, 2))
	if culture_id <= 0 or city_a.is_empty() or city_b.is_empty():
		_expect(false, "The two-City fixture must be created.")
		return {}
	return {
		"polity_id": polity_id,
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


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City citizen-decision runtime isolation test: " + message)
