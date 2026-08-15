extends Node

const TEST_WORLD_SIZE := Vector2i(32, 32)

var failure_count: int = 0


func _ready() -> void:
	_test_bidirectional_repair_capacity_and_idempotence()
	_test_atomic_mutation_and_removed_building_reassignment()
	_test_automatic_staffing_capacity_and_task_cleanup()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City assignment system test failed: " + str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City assignment system test passed.")
	get_tree().quit(0)


func _test_bidirectional_repair_capacity_and_idempotence() -> void:
	var fixture := _make_assignment_fixture(99_101)
	if fixture.is_empty():
		return

	var house_a_id := int(fixture.get("house_a_id", -1))
	var house_b_id := int(fixture.get("house_b_id", -1))
	var fishery_a_id := int(fixture.get("fishery_a_id", -1))
	var fishery_b_id := int(fixture.get("fishery_b_id", -1))
	var citizen_ids: Array = fixture.get("citizen_ids", [])
	if citizen_ids.size() != 3:
		return

	var citizen_one_id := int(citizen_ids[0])
	var citizen_two_id := int(citizen_ids[1])
	var citizen_three_id := int(citizen_ids[2])

	# Corrupt both sides deliberately. Citizen-side links are canonical intent;
	# object projections contain duplicates, stale IDs, and mismatches.
	_set_citizen_relationship_fixture(
		citizen_one_id,
		house_a_id,
		fishery_a_id,
		true
	)
	_set_citizen_relationship_fixture(
		citizen_two_id,
		house_a_id,
		fishery_a_id,
		true
	)
	_set_citizen_relationship_fixture(
		citizen_three_id,
		9_999,
		9_999,
		false
	)
	CityCitizenSpatialSystem.rebuild_city_citizen_spatial_index()
	_set_object_relationship_fixture(
		house_a_id,
		"resident_ids",
		[citizen_two_id, citizen_one_id, citizen_one_id, 9_999]
	)
	_set_object_relationship_fixture(
		house_b_id,
		"resident_ids",
		[citizen_three_id]
	)
	_set_object_relationship_fixture(
		fishery_a_id,
		"assigned_worker_ids",
		[citizen_two_id, citizen_one_id, 9_999]
	)
	_set_object_relationship_fixture(
		fishery_b_id,
		"assigned_worker_ids",
		[citizen_three_id]
	)

	var assignment_state := CityAssignmentSystem.get_current_state()
	var version_before_repair := assignment_state.assignment_version
	var repaired_record_count := (
		CityAssignmentSystem.ensure_city_citizen_assignment_state()
	)
	var citizen_one := CityCitizenRegistrySystem.get_city_citizen_by_id(
		citizen_one_id
	)
	var citizen_two := CityCitizenRegistrySystem.get_city_citizen_by_id(
		citizen_two_id
	)
	var citizen_three := CityCitizenRegistrySystem.get_city_citizen_by_id(
		citizen_three_id
	)

	_expect(
		repaired_record_count > 0
		and assignment_state.assignment_version == version_before_repair + 1,
		"One repair pass must publish exactly one assignment invalidation."
	)
	_expect(
		int(citizen_one.get("home_object_id", -1)) == house_a_id
		and int(citizen_one.get("job_object_id", -1)) == fishery_a_id
		and int(citizen_two.get("home_object_id", -1)) == -1
		and int(citizen_two.get("job_object_id", -1)) == -1
		and int(citizen_three.get("home_object_id", -1)) == -1
		and int(citizen_three.get("job_object_id", -1)) == -1,
		"Capacity overflow, dead citizens, and dangling targets must clear deterministically."
	)
	_expect(
		CityAssignmentSystem.get_city_object_resident_ids(
			CityObjectSystem.get_city_object_by_id(house_a_id)
		) == [citizen_one_id]
		and CityAssignmentSystem.get_city_object_resident_ids(
			CityObjectSystem.get_city_object_by_id(house_b_id)
		).is_empty()
		and CityEmploymentSystem.get_city_object_worker_ids(
			CityObjectSystem.get_city_object_by_id(fishery_a_id)
		) == [citizen_one_id]
		and CityEmploymentSystem.get_city_object_worker_ids(
			CityObjectSystem.get_city_object_by_id(fishery_b_id)
		).is_empty(),
		"Object-side resident and worker projections must rebuild from valid citizen links."
	)

	var version_before_no_op := assignment_state.assignment_version
	_expect(
		CityAssignmentSystem.ensure_city_citizen_assignment_state() == 0
		and assignment_state.assignment_version == version_before_no_op,
		"A clean relationship graph must make repair idempotent."
	)


func _test_atomic_mutation_and_removed_building_reassignment() -> void:
	var fixture := _make_assignment_fixture(99_102)
	if fixture.is_empty():
		return

	var house_a_id := int(fixture.get("house_a_id", -1))
	var house_b_id := int(fixture.get("house_b_id", -1))
	var fishery_a_id := int(fixture.get("fishery_a_id", -1))
	var fishery_b_id := int(fixture.get("fishery_b_id", -1))
	var citizen_ids: Array = fixture.get("citizen_ids", [])
	if citizen_ids.size() != 3:
		return

	var citizen_one_id := int(citizen_ids[0])
	var citizen_two_id := int(citizen_ids[1])
	var assignment_state := CityAssignmentSystem.get_current_state()
	var version_before_assignments := assignment_state.assignment_version

	_expect(
		CityAssignmentSystem.assign_city_citizen_home(
			citizen_one_id,
			house_a_id
		)
		and CityAssignmentSystem.assign_city_citizen_job(
			citizen_one_id,
			fishery_a_id
		)
		and CityAssignmentSystem.assign_city_citizen_home(
			citizen_two_id,
			house_b_id
		)
		and CityAssignmentSystem.assign_city_citizen_job(
			citizen_two_id,
			fishery_b_id
		),
		"Focused APIs must establish both housing and employment relationships."
	)
	_expect(
		assignment_state.assignment_version == version_before_assignments + 4,
		"Four real atomic relationship mutations must publish four versions."
	)

	var version_before_rejected_capacity := assignment_state.assignment_version
	_expect(
		not CityAssignmentSystem.assign_city_citizen_home(
			citizen_two_id,
			house_a_id
		)
		and not CityAssignmentSystem.assign_city_citizen_job(
			citizen_two_id,
			fishery_a_id
		)
		and assignment_state.assignment_version
		== version_before_rejected_capacity,
		"Rejected full-capacity moves must leave both sides and version untouched."
	)

	_remove_completed_objects([house_a_id, fishery_a_id])
	var version_before_cleanup := assignment_state.assignment_version
	CityEmploymentSystem.run_tick(1, 1)
	var citizen_one := CityCitizenRegistrySystem.get_city_citizen_by_id(
		citizen_one_id
	)
	var surviving_house := CityObjectSystem.get_city_object_by_id(house_b_id)
	var surviving_fishery := CityObjectSystem.get_city_object_by_id(fishery_b_id)

	_expect(
		assignment_state.assignment_version > version_before_cleanup
		and int(citizen_one.get("home_object_id", -1)) == house_b_id
		and int(citizen_one.get("job_object_id", -1)) == fishery_b_id
		and CityAssignmentSystem.get_city_object_resident_ids(
			surviving_house
		).has(citizen_one_id)
		and CityEmploymentSystem.get_city_object_worker_ids(
			surviving_fishery
		).has(citizen_one_id),
		"Removed buildings must clear dangling links and reassign to remaining capacity."
	)

	var version_before_removals := assignment_state.assignment_version
	_expect(
		CityAssignmentSystem.remove_city_citizen_home(citizen_one_id)
		and CityAssignmentSystem.remove_city_citizen_job(citizen_one_id)
		and assignment_state.assignment_version == version_before_removals + 2,
		"Focused removals must each publish one assignment invalidation."
	)
	_expect(
		int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_one_id).get(
				"home_object_id",
				0
			)
		) == -1
		and int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_one_id).get(
				"job_object_id",
				0
			)
		) == -1
		and not CityAssignmentSystem.get_city_object_resident_ids(
			surviving_house
		).has(citizen_one_id)
		and not CityEmploymentSystem.get_city_object_worker_ids(
			surviving_fishery
		).has(citizen_one_id),
		"Focused removal must clear citizen and object sides together."
	)
	_expect(
		CityAssignmentSystem.ensure_city_citizen_assignment_state() == 0,
		"The final focused relationship graph must already be internally consistent."
	)


func _test_automatic_staffing_capacity_and_task_cleanup() -> void:
	var fixture := _make_assignment_fixture(99_103)
	if fixture.is_empty():
		return

	var house_a_id := int(fixture.get("house_a_id", -1))
	var fishery_a_id := int(fixture.get("fishery_a_id", -1))
	var fishery_b_id := int(fixture.get("fishery_b_id", -1))
	var citizen_ids: Array = fixture.get("citizen_ids", []).duplicate()
	if citizen_ids.size() != 3:
		return

	var return_home_citizen_id := int(citizen_ids[1])
	var work_citizen_id := int(citizen_ids[2])
	_expect(
		CityAssignmentSystem.assign_city_citizen_home(
			return_home_citizen_id,
			house_a_id
		)
		and _assign_task_and_movement(
			return_home_citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
			house_a_id
		)
		and CityAssignmentSystem.assign_city_citizen_job(
			work_citizen_id,
			fishery_a_id
		)
		and _assign_task_and_movement(
			work_citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_KIND_WORK,
			fishery_a_id
		),
		"The repair-order fixture must seed active Return Home and Work movement."
	)

	_set_citizen_relationship_fixture(
		return_home_citizen_id,
		0,
		-1,
		true
	)
	_set_citizen_relationship_fixture(
		work_citizen_id,
		-1,
		0,
		true
	)
	CityAssignmentSystem.ensure_city_citizen_assignment_state()
	var repaired_home_citizen := (
		CityCitizenRegistrySystem.get_city_citizen_by_id(
			return_home_citizen_id
		)
	)
	var repaired_work_citizen := (
		CityCitizenRegistrySystem.get_city_citizen_by_id(work_citizen_id)
	)
	var active_mover_ids := (
		CityCitizenMovementRuntimeSystem.get_city_active_mover_ids_snapshot()
	)
	_expect(
		int(repaired_home_citizen.get("home_object_id", 0)) == -1
		and _task_kind(return_home_citizen_id)
		== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
		and str(repaired_home_citizen.get("movement_state", ""))
		== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		and not active_mover_ids.has(return_home_citizen_id)
		and int(repaired_work_citizen.get("job_object_id", 0)) == -1
		and _task_kind(work_citizen_id)
		== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
		and str(repaired_work_citizen.get("movement_state", ""))
		== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		and not active_mover_ids.has(work_citizen_id),
		"Assignment repair must commit cleared links before retiring their tasks and movement."
	)

	var normalized_dead_citizen_id := int(citizen_ids[0])
	_expect(
		CityAssignmentSystem.assign_city_citizen_job(
			normalized_dead_citizen_id,
			fishery_a_id
		)
		and _assign_task_and_movement(
			normalized_dead_citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_KIND_WORK,
			fishery_a_id
		),
		"The dead-state repair fixture must seed stale Work movement."
	)
	_set_citizen_relationship_fixture(
		normalized_dead_citizen_id,
		-1,
		-1,
		false
	)
	CityAssignmentSystem.ensure_city_citizen_assignment_state()
	var normalized_dead_citizen := (
		CityCitizenRegistrySystem.get_city_citizen_by_id(
			normalized_dead_citizen_id
		)
	)
	_expect(
		_task_kind(normalized_dead_citizen_id)
		== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
		and str(normalized_dead_citizen.get("movement_state", ""))
		== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE,
		"A dead citizen with already-normalized links must not retain stale Work movement."
	)
	_set_citizen_relationship_fixture(
		normalized_dead_citizen_id,
		-1,
		-1,
		true
	)

	var first_citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(
		int(citizen_ids[0])
	)
	var culture_id := int(first_citizen.get("culture_id", -1))
	var fourth_citizen := CityCitizenRegistrySystem.add_city_citizen(
		"",
		Vector2i(23, 20),
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	var fourth_citizen_id := int(fourth_citizen.get("id", -1))
	if fourth_citizen_id > 0:
		citizen_ids.append(fourth_citizen_id)
	citizen_ids.sort()
	_expect(
		citizen_ids.size() == 4,
		"The automatic staffing fixture must own four eligible citizens."
	)
	if citizen_ids.size() != 4:
		return

	_set_object_capacity(fishery_a_id, "worker_capacity", 4)
	_set_object_capacity(fishery_b_id, "worker_capacity", 0)
	CityEmploymentSystem.run_tick(1, 1)
	var fishery_a := CityObjectSystem.get_city_object_by_id(fishery_a_id)
	_expect(
		CityEmploymentSystem.get_workplace_staffing_mode(fishery_a)
		== CityEmploymentSystem.STAFFING_MODE_AUTOMATIC
		and CityEmploymentSystem.get_workplace_desired_worker_count(fishery_a) == 4
		and CityEmploymentSystem.get_city_object_worker_ids(fishery_a)
		== citizen_ids,
		"Automatic staffing must fill a four-worker Fishery deterministically."
	)

	_set_object_capacity(fishery_a_id, "worker_capacity", 2)
	CityEmploymentSystem.run_tick(2, 1)
	fishery_a = CityObjectSystem.get_city_object_by_id(fishery_a_id)
	var retained_worker_ids: Array = [citizen_ids[0], citizen_ids[1]]
	_expect(
		CityEmploymentSystem.get_workplace_desired_worker_count(fishery_a) == 2
		and CityEmploymentSystem.get_city_object_worker_ids(fishery_a)
		== retained_worker_ids
		and int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(
				int(citizen_ids[2])
			).get("job_object_id", 0)
		) == -1
		and int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(
				int(citizen_ids[3])
			).get("job_object_id", 0)
		) == -1,
		"Capacity downscale must retain the lowest IDs and clear every surplus job."
	)

	_set_object_capacity(fishery_a_id, "worker_capacity", 4)
	CityEmploymentSystem.run_tick(3, 1)
	fishery_a = CityObjectSystem.get_city_object_by_id(fishery_a_id)
	_expect(
		CityEmploymentSystem.get_workplace_desired_worker_count(fishery_a) == 4
		and CityEmploymentSystem.get_city_object_worker_ids(fishery_a)
		== citizen_ids,
		"Capacity upscale must restore the full automatic target and refill vacancies."
	)

	_set_object_capacity(fishery_b_id, "worker_capacity", 1)
	CityAssignmentSystem.ensure_city_citizen_assignment_state()
	CityEmploymentSystem.ensure_workplace_staffing_state()
	var reassigned_citizen_id := int(citizen_ids[0])
	_expect(
		_assign_task_and_movement(
			reassigned_citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_KIND_WORK,
			fishery_a_id
		)
		and CityAssignmentSystem.assign_city_citizen_job(
			reassigned_citizen_id,
			fishery_b_id
		),
		"An employed citizen must support an explicit A to B workplace reassignment."
	)
	var reassigned_citizen := (
		CityCitizenRegistrySystem.get_city_citizen_by_id(reassigned_citizen_id)
	)
	_expect(
		int(reassigned_citizen.get("job_object_id", -1)) == fishery_b_id
		and _task_kind(reassigned_citizen_id)
		== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
		and str(reassigned_citizen.get("movement_state", ""))
		== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		and not CityCitizenMovementRuntimeSystem.get_city_active_mover_ids_snapshot().has(
			reassigned_citizen_id
		),
		"A to B job reassignment must retire the old workplace task and movement."
	)

	var workplace_before_rejected_manual := (
		CityObjectSystem.get_city_object_by_id(fishery_a_id).duplicate(true)
	)
	var assignment_version_before_rejected_manual := (
		CityAssignmentSystem.get_city_assignment_version()
	)
	var workplace_version_before_rejected_manual := (
		CityEmploymentSystem.get_city_workplace_version()
	)
	_expect(
		not CityEmploymentSystem.set_workplace_staffing_mode(
			fishery_a_id,
			CityEmploymentSystem.STAFFING_MODE_MANUAL
		)
		and not CityEmploymentSystem.assign_citizen_to_workplace(
			reassigned_citizen_id,
			fishery_a_id,
			true
		)
		and CityObjectSystem.get_city_object_by_id(fishery_a_id)
		== workplace_before_rejected_manual
		and CityAssignmentSystem.get_city_assignment_version()
		== assignment_version_before_rejected_manual
		and CityEmploymentSystem.get_city_workplace_version()
		== workplace_version_before_rejected_manual,
		"Legacy manual requests must reject without changing policy, jobs, or versions."
	)


func _make_assignment_fixture(seed: int) -> Dictionary:
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game()
	var culture := WorldData.create_culture("Assignment Test Culture")
	var culture_id := int(culture.get("id", -1))
	var city_name := "Assignment Test City " + str(seed)
	var city_state = _create_active_city_fixture(city_name, culture_id)
	_expect(
		city_state is CitySettlementSimulationState,
		"The assignment fixture must own an active City simulation state."
	)
	if not city_state is CitySettlementSimulationState:
		return {}
	city_state.city_runtime_data.clear()
	city_state.city_runtime_data.merge({
		"name": city_name,
		"primary_culture_id": culture_id,
		"founded": true,
		"can_build": true,
	}, true)
	var city_world := _make_world(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, seed)
	WorldData.store_city_world_save(city_world, seed)

	var house_a := _register_object(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		Vector2i(3, 3),
		city_world
	)
	var house_b := _register_object(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		Vector2i(10, 3),
		city_world
	)
	var fishery_a := _register_object(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		Vector2i(3, 12),
		city_world
	)
	var fishery_b := _register_object(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		Vector2i(12, 12),
		city_world
	)

	_expect(
		culture_id > 0
		and not house_a.is_empty()
		and not house_b.is_empty()
		and not fishery_a.is_empty()
		and not fishery_b.is_empty(),
		"The fixture must create culture, housing, and workplaces."
	)
	if (
		culture_id <= 0
		or house_a.is_empty()
		or house_b.is_empty()
		or fishery_a.is_empty()
		or fishery_b.is_empty()
	):
		return {}

	_set_object_capacity(int(house_a.get("id", -1)), "resident_capacity", 1)
	_set_object_capacity(int(house_b.get("id", -1)), "resident_capacity", 3)
	_set_object_capacity(int(fishery_a.get("id", -1)), "worker_capacity", 1)
	_set_object_capacity(int(fishery_b.get("id", -1)), "worker_capacity", 3)

	var citizen_ids: Array[int] = []
	for citizen_index in range(3):
		var citizen := CityCitizenRegistrySystem.add_city_citizen(
			"",
			Vector2i(20 + citizen_index, 20),
			CityCitizens.CITY_CITIZEN_SEX_MALE,
			culture_id
		)
		var citizen_id := int(citizen.get("id", -1))
		if citizen_id > 0:
			citizen_ids.append(citizen_id)

	_expect(
		citizen_ids.size() == 3,
		"The assignment fixture must create three indexed citizens."
	)
	if citizen_ids.size() != 3:
		return {}

	return {
		"house_a_id": int(house_a.get("id", -1)),
		"house_b_id": int(house_b.get("id", -1)),
		"fishery_a_id": int(fishery_a.get("id", -1)),
		"fishery_b_id": int(fishery_b.get("id", -1)),
		"citizen_ids": citizen_ids,
	}


func _create_active_city_fixture(city_name: String, culture_id: int):
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


func _register_object(
	object_type: String,
	top_left: Vector2i,
	city_world: WorldData
) -> Dictionary:
	return CityObjectSystem.register_completed_city_object({
		"object_type": object_type,
		"top_left": top_left,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(object_type),
		"object_owner": "player",
		"city_world": city_world,
	})


func _set_object_capacity(
	object_id: int,
	field_name: String,
	capacity: int
) -> void:
	match field_name:
		"resident_capacity":
			CityAssignmentSystem.set_city_object_resident_capacity(
				object_id,
				capacity
			)
		"worker_capacity":
			CityEmploymentSystem.set_city_workplace_worker_capacity(
				object_id,
				capacity
			)


func _set_citizen_relationship_fixture(
	citizen_id: int,
	home_object_id: int,
	job_object_id: int,
	alive: bool
) -> void:
	var citizen_index := (
		CityCitizenRegistrySystem.get_city_citizen_index_by_id(citizen_id)
	)
	if citizen_index < 0:
		return
	var raw_citizen = (
		CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]
	)
	if not raw_citizen is Dictionary:
		return
	var citizen: Dictionary = raw_citizen.duplicate(false)
	citizen["home_object_id"] = home_object_id
	citizen["job_object_id"] = job_object_id
	citizen["alive"] = alive
	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen


func _assign_task_and_movement(
	citizen_id: int,
	task_kind: String,
	target_object_id: int
) -> bool:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var raw_tile_position = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	if not raw_tile_position is Vector2i:
		return false
	var tile_position: Vector2i = raw_tile_position
	var movement_destination := tile_position + Vector2i(0, 1)
	var task := {
		"kind": task_kind,
		"source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE,
		"priority": 50,
		"target_object_id": target_object_id,
	}
	return (
		CityCitizenTaskRuntimeSystem.assign_city_citizen_task(
			citizen_id,
			task
		)
		and CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
			citizen_id,
			[tile_position, movement_destination]
		)
	)


func _task_kind(citizen_id: int) -> String:
	return str(
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
			citizen_id
		).get("kind", CityCitizens.CITY_CITIZEN_TASK_KIND_NONE)
	)


func _set_object_relationship_fixture(
	object_id: int,
	field_name: String,
	assignment_ids: Array
) -> void:
	var relationship_patch: Dictionary = {}
	relationship_patch[field_name] = assignment_ids.duplicate()
	CityObjectSystem.patch_city_object_assignment_fields(
		object_id,
		relationship_patch
	)


func _remove_completed_objects(object_ids: Array) -> void:
	var indexes: Array[int] = []
	for raw_object_id in object_ids:
		var object_index := CityObjectSystem.get_city_object_index_by_id(
			int(raw_object_id)
		)
		if object_index >= 0:
			indexes.append(object_index)
	indexes.sort()
	indexes.reverse()
	for object_index in indexes:
		CityObjectSystem.get_current_state().objects.remove_at(object_index)
	CityObjectSystem.rebuild_city_object_index()
	CityObjectSystem.rebuild_city_object_occupancy()
	CityObjectSystem.mark_city_objects_changed()
	CityEmploymentSystem.mark_city_workplaces_changed()


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
	push_error("City assignment system test: " + message)
