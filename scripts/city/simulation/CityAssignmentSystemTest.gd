extends Node

const CityStateValidator := preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)
const TEST_WORLD_SIZE := Vector2i(32, 32)

var failure_count: int = 0


func _ready() -> void:
	_test_bidirectional_repair_capacity_and_idempotence()
	_test_atomic_mutation_and_removed_building_reassignment()
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

	var validation := CityStateValidator.validate(true, false)
	_expect(
		bool(validation.get("valid", false)),
		"The repaired relationship graph must satisfy the full city validator."
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

	var validation := CityStateValidator.validate(true, false)
	_expect(
		bool(validation.get("valid", false)),
		"Atomic mutation, cleanup, and reassignment must leave valid city state."
	)


func _make_assignment_fixture(seed: int) -> Dictionary:
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game()
	var culture := WorldData.create_culture("Assignment Test Culture")
	var culture_id := int(culture.get("id", -1))
	var city_world := _make_world(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, seed)
	WorldData.store_city_world_save(city_world, seed)

	var house_a := _register_object(
		WorldData.CITY_OBJECT_HOUSE,
		Vector2i(3, 3),
		city_world
	)
	var house_b := _register_object(
		WorldData.CITY_OBJECT_HOUSE,
		Vector2i(10, 3),
		city_world
	)
	var fishery_a := _register_object(
		WorldData.CITY_OBJECT_FISHING_GROUNDS,
		Vector2i(3, 12),
		city_world
	)
	var fishery_b := _register_object(
		WorldData.CITY_OBJECT_FISHING_GROUNDS,
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
		var citizen := WorldData.add_city_citizen(
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


func _register_object(
	object_type: String,
	top_left: Vector2i,
	city_world: WorldData
) -> Dictionary:
	return CityObjectSystem.register_completed_city_object({
		"object_type": object_type,
		"top_left": top_left,
		"size_tiles": WorldData.get_city_object_size_for_type(object_type),
		"object_owner": "player",
		"city_world": city_world,
	})


func _set_object_capacity(
	object_id: int,
	field_name: String,
	capacity: int
) -> void:
	var object_index := CityObjectSystem.get_city_object_index_by_id(object_id)
	if object_index < 0:
		return
	var raw_city_object = CityObjectSystem.get_city_objects()[object_index]
	if not raw_city_object is Dictionary:
		return
	var city_object: Dictionary = raw_city_object.duplicate(false)
	city_object[field_name] = capacity
	CityObjectSystem.write_city_object_at_index(object_index, city_object)


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


func _set_object_relationship_fixture(
	object_id: int,
	field_name: String,
	assignment_ids: Array
) -> void:
	var object_index := CityObjectSystem.get_city_object_index_by_id(object_id)
	if object_index < 0:
		return
	var raw_city_object = CityObjectSystem.get_city_objects()[object_index]
	if not raw_city_object is Dictionary:
		return
	var city_object: Dictionary = raw_city_object.duplicate(false)
	city_object[field_name] = assignment_ids.duplicate()
	CityObjectSystem.write_city_object_at_index(object_index, city_object)


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
