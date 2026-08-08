extends Node

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityWorkSystemScript = preload(
	"res://scripts/city/simulation/systems/CityWorkSystem.gd"
)
const CitizenDecisionSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenDecisionSystem.gd"
)
const CitizenMovementSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenMovementSystem.gd"
)
const CitizenTaskSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenTaskSystem.gd"
)
const CitizenHaulingSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenHaulingSystem.gd"
)
const CityCitizenStateValidatorScript = preload(
	"res://scripts/city/simulation/validators/CityCitizenStateValidator.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 24)
const TEST_WORLD_SEED: int = 41_207
const AUTONOMOUS_CLEANUP_PRIORITY: int = 90

var failure_count: int = 0
var test_primary_culture_id: int = -1


func _ready() -> void:
	_test_normal_order_preempts_before_pickup()
	_test_normal_order_waits_for_picked_up_cargo_delivery()
	_test_critical_hunger_interrupts_cargo_safely()
	_test_construction_labor_releases_at_atomic_boundary()
	_test_world_founding_identity_commit_boundaries()
	_test_culture_identity_validation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"Unified boundary tests failed: " + str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Unified boundary tests passed.")
	get_tree().quit(0)


func _test_normal_order_preempts_before_pickup() -> void:
	print("Boundary test: pre-pickup Normal preemption")
	var city_world := _reset_fixture()
	var citizen := _add_citizen(Vector2i(5, 5))
	var citizen_id := int(citizen.get("id", -1))
	var stockpile := _add_stockpile(city_world, Vector2i(10, 4))
	var source_id := _add_ground_resource(
		Vector2i(7, 5),
		WorldData.RESOURCE_LUMBER,
		2
	)
	var haul_request := _make_cleanup_haul_request(
		city_world,
		citizen,
		source_id
	)

	_expect(
		not stockpile.is_empty()
		and source_id > 0
		and not haul_request.is_empty()
		and WorldData.assign_city_citizen_task(citizen_id, haul_request),
		"The pre-pickup fixture must assign a real autonomous haul."
	)

	var reservation_id := WorldData.get_city_haul_reservation_id_for_citizen(
		citizen_id
	)
	_expect(
		reservation_id > 0
		and WorldData.get_city_citizen_haul_cargo_amount(citizen_id) == 0,
		"The autonomous haul must begin reserved but before pickup."
	)

	var command_id := _add_natural_command(
		city_world,
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
		Vector2i(4, 5)
	)
	CitizenDecisionSystemScript.run_tick(1, 2)
	var assigned_task := WorldData.get_city_citizen_current_task(citizen_id)

	_expect(
		str(assigned_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
		and int(assigned_task.get("target_object_id", -1)) == command_id,
		"A Normal tree order must replace the autonomous haul before pickup."
	)
	_expect(
		WorldData.get_city_haul_reservation(reservation_id).is_empty(),
		"Pre-pickup interruption must release the old haul reservation."
	)
	_expect(
		WorldData.get_city_ground_pile_resource_amount(
			WorldData.get_city_ground_pile_by_id(source_id),
			WorldData.RESOURCE_LUMBER
		) == 2
		and WorldData.get_city_citizen_haul_cargo_amount(citizen_id) == 0,
		"Pre-pickup interruption must leave the physical source untouched."
	)

	# Run the actual command executor through its visible performing boundary.
	CitizenTaskSystemScript.run_tick(2, 2)
	var performing_task := WorldData.get_city_citizen_current_task(citizen_id)
	_expect(
		str(performing_task.get("phase", ""))
		== WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING,
		"The commanded tree must enter its real performing phase."
	)
	SimulationClock.absolute_world_minutes += (
		CityWorkSystem.CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES
	)
	CitizenTaskSystemScript.run_tick(3, 2)
	_expect(
		CityWorkSystem.get_city_player_command_by_id(command_id).is_empty()
		and WorldData.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == 6,
		"The representative tree command must complete and create its yield."
	)


func _test_normal_order_waits_for_picked_up_cargo_delivery() -> void:
	print("Boundary test: post-pickup delivery boundary")
	var city_world := _reset_fixture()
	var citizen := _add_citizen(Vector2i(5, 5))
	var citizen_id := int(citizen.get("id", -1))
	var stockpile := _add_stockpile(city_world, Vector2i(10, 4))
	var stockpile_id := int(stockpile.get("id", -1))
	var source_id := _add_ground_resource(
		Vector2i(5, 5),
		WorldData.RESOURCE_STONE,
		2
	)
	var haul_request := _make_cleanup_haul_request(
		city_world,
		citizen,
		source_id
	)

	_expect(
		not haul_request.is_empty()
		and WorldData.assign_city_citizen_task(citizen_id, haul_request),
		"The after-pickup fixture must assign a real autonomous haul."
	)
	CitizenTaskSystemScript.run_tick(1, 2)
	CitizenTaskSystemScript.run_tick(2, 2)

	var haul_after_pickup := WorldData.get_city_citizen_current_haul(citizen_id)
	_expect(
		WorldData.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_STONE
		) == 2
		and str(haul_after_pickup.get("phase", "")) in [
			WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION,
			WorldData.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION,
			WorldData.CITY_CITIZEN_HAUL_PHASE_DEPOSITING,
		],
		"The real pickup executor must move both stone units into cargo."
	)

	var command_id := _add_natural_command(
		city_world,
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK,
		Vector2i(4, 5)
	)
	var physical_before_order := (
		WorldData.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_STONE
		)
	)
	CitizenDecisionSystemScript.run_tick(3, 2)
	var task_after_order := WorldData.get_city_citizen_current_task(citizen_id)

	_expect(
		str(task_after_order.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_HAUL
		and WorldData.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_STONE
		) == 2,
		"A Normal rock order must wait while already-picked-up cargo is delivered."
	)
	_expect(
		WorldData.get_total_city_ground_pile_resource_amount(
			WorldData.RESOURCE_STONE
		) == 0
		and WorldData.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_STONE
		) == physical_before_order,
		"Issuing the Normal order after pickup must not spill or lose cargo."
	)

	var assigned_command_after_delivery := false

	for tick_index in range(4, 28):
		SimulationClock.absolute_world_minutes += 2
		CitizenDecisionSystemScript.run_tick(tick_index, 2)
		CitizenMovementSystemScript.run_tick(tick_index, 2)
		CitizenTaskSystemScript.run_tick(tick_index, 2)

		var current_task := WorldData.get_city_citizen_current_task(citizen_id)

		if (
			str(current_task.get("kind", ""))
			== WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
			and int(current_task.get("target_object_id", -1)) == command_id
		):
			assigned_command_after_delivery = true
			break

	_expect(
		WorldData.get_city_object_stored_resource_amount(
			WorldData.get_city_object_by_id(stockpile_id),
			WorldData.RESOURCE_STONE
		) == 2
		and WorldData.get_city_citizen_haul_cargo_amount(citizen_id) == 0,
		"Picked-up cargo must reach its reserved destination before preemption."
	)
	_expect(
		assigned_command_after_delivery,
		"The waiting Normal rock order must be assigned after delivery."
	)
	_expect(
		WorldData.get_total_city_ground_pile_resource_amount(
			WorldData.RESOURCE_STONE
		) == 0,
		"The completed delivery must not leave an ordinary-command cargo spill."
	)


func _test_critical_hunger_interrupts_cargo_safely() -> void:
	print("Boundary test: critical-hunger interruption")
	var city_world := _reset_fixture()
	var citizen := _add_citizen(Vector2i(5, 5))
	var citizen_id := int(citizen.get("id", -1))
	_add_stockpile(city_world, Vector2i(10, 4))
	var fishery_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_FISHING_GROUNDS
	)
	var fishery := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(12, 9),
		"size_tiles": fishery_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery_id := int(fishery.get("id", -1))
	_expect(
		WorldData.add_resource_to_city_object_storage(
			fishery_id,
			WorldData.RESOURCE_FISH,
			2
		) == 2,
		"The critical-hunger fixture must expose reachable workplace fish."
	)
	# Placing a workplace may immediately employ an eligible idle citizen. This
	# boundary specifically begins from autonomous logistics, so release that
	# assignment before creating the real haul task.
	if int(
		WorldData.get_city_citizen_by_id(citizen_id).get(
			"job_object_id",
			-1
		)
	) > 0:
		WorldData.remove_city_citizen_job(citizen_id)

	var source_id := _add_ground_resource(
		Vector2i(5, 5),
		WorldData.RESOURCE_LUMBER,
		2
	)
	var haul_request := _make_cleanup_haul_request(
		city_world,
		citizen,
		source_id
	)
	var haul_assigned := WorldData.assign_city_citizen_task(
		citizen_id,
		haul_request
	)
	_expect(
		not haul_request.is_empty() and haul_assigned,
		"The critical-hunger fixture must begin with a real haul."
	)
	CitizenTaskSystemScript.run_tick(1, 2)
	CitizenTaskSystemScript.run_tick(2, 2)
	_expect(
		WorldData.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_LUMBER
		) == 2,
		"Critical interruption coverage requires already-picked-up cargo."
	)

	var reservation_id := WorldData.get_city_haul_reservation_id_for_citizen(
		citizen_id
	)
	var physical_before_interrupt := (
		WorldData.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		)
	)
	WorldData.set_city_citizen_hunger_state(citizen_id, 20, 0)
	CitizenDecisionSystemScript.run_tick(3, 2)
	var food_task := WorldData.get_city_citizen_current_task(citizen_id)

	_expect(
		str(food_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		and int(food_task.get("target_object_id", -1)) == fishery_id,
		"Critical hunger must replace an in-flight haul with workplace-food acquisition."
	)
	_expect(
		WorldData.get_city_citizen_haul_cargo_amount(citizen_id) == 0
		and WorldData.get_city_haul_reservation(reservation_id).is_empty(),
		"Critical interruption must release cargo state and its old reservation."
	)
	_expect(
		WorldData.get_total_city_ground_pile_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == 2
		and WorldData.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == physical_before_interrupt,
		"Critical interruption may spill exceptionally, but must do so atomically without loss."
	)


func _test_construction_labor_releases_at_atomic_boundary() -> void:
	print("Boundary test: construction labor atomic boundary")
	var city_world := _reset_fixture()
	var house_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_HOUSE
	)
	var house_site := CityConstructionSystemScript.create_rectangular_site({
		"object_type": WorldData.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(10, 8),
		"size_tiles": house_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var site_id := int(house_site.get("id", -1))
	_expect(site_id > 0, "The boundary fixture must create a House site.")

	if site_id <= 0:
		return

	_expect(
		CityConstructionSystem.add_resource_to_city_construction_site(
			site_id,
			WorldData.RESOURCE_LUMBER,
			8
		) == 8
		and CityConstructionSystem.add_resource_to_city_construction_site(
			site_id,
			WorldData.RESOURCE_STONE,
			4
		) == 4,
		"The House site must receive its complete physical material recipe."
	)
	CityConstructionSystemScript.refresh_city_construction_site(site_id)
	house_site = WorldData.get_city_construction_site_by_id(site_id)
	_expect(
		str(house_site.get("phase", ""))
		== WorldData.CITY_CONSTRUCTION_PHASE_LABOR,
		"A fully supplied clear House must enter labor."
	)

	var work_positions := (
		WorldData.get_city_construction_site_work_positions(house_site)
	)
	_expect(
		not work_positions.is_empty(),
		"The House site must expose at least one labor position."
	)

	if work_positions.is_empty():
		return

	var citizen := _add_citizen(work_positions[0])
	var citizen_id := int(citizen.get("id", -1))
	_add_natural_command(
		city_world,
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
		Vector2i(25, 18)
	)
	CitizenDecisionSystemScript.run_tick(1, 2)
	var assigned_task := WorldData.get_city_citizen_current_task(citizen_id)
	_expect(
		str(assigned_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
		and int(assigned_task.get("target_object_id", -1)) == site_id,
		"The unified scheduler must assign the nearby construction labor job."
	)

	CitizenTaskSystemScript.run_tick(2, 2)
	var performing_task := WorldData.get_city_citizen_current_task(citizen_id)
	var boundary_minute := int(
		performing_task.get(
			"next_action_world_minute",
			WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)
	_expect(
		str(performing_task.get("phase", ""))
		== WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
		and boundary_minute
		== SimulationClock.absolute_world_minutes
		+ WorldData.CITY_CONSTRUCTION_LABOR_ATOMIC_MINUTES,
		"Construction labor must publish its exact 30-minute atomic boundary."
	)

	SimulationClock.absolute_world_minutes = boundary_minute - 1
	CitizenTaskSystemScript.run_tick(3, 29)
	var before_boundary_task := WorldData.get_city_citizen_current_task(
		citizen_id
	)
	_expect(
		str(before_boundary_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
		and int(
			WorldData.get_city_construction_site_by_id(site_id).get(
				"completed_labor_minutes",
				-1
			)
		)
		== 29,
		"Labor must remain committed one minute before its atomic boundary."
	)

	SimulationClock.absolute_world_minutes = boundary_minute
	CitizenTaskSystemScript.run_tick(4, 1)
	var released_task := WorldData.get_city_citizen_current_task(citizen_id)
	_expect(
		str(released_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_NONE
		and int(
			WorldData.get_city_construction_site_by_id(site_id).get(
				"completed_labor_minutes",
				-1
			)
		)
		== 30,
		"Labor must release exactly at the boundary after preserving progress."
	)

	CityWorkSystemScript.synchronize_player_work_board()
	var next_job := CityWorkSystemScript.get_best_player_job_for_citizen(
		citizen_id
	)
	_expect(
		not next_job.is_empty(),
		"A released laborer must be immediately eligible to re-query the scheduler."
	)
	CitizenDecisionSystemScript.run_tick(5, 2)
	var reassigned_task := WorldData.get_city_citizen_current_task(citizen_id)
	_expect(
		str(reassigned_task.get("source", ""))
		== WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
		and int(reassigned_task.get("work_order_id", -1)) > 0
		and not str(reassigned_task.get("job_id", "")).is_empty(),
		"The next decision pass must assign a real unified-board job after the boundary."
	)


func _test_culture_identity_validation() -> void:
	print("Boundary test: citizen culture identity")
	_reset_fixture()

	for founder_index in range(WorldData.STARTING_CITY_POPULATION):
		var founder := _add_citizen(
			Vector2i(3 + founder_index, 4)
		)
		_expect(
			not founder.is_empty(),
			"The culture fixture must create every founding citizen."
		)

	var alternate_culture := WorldData.create_culture(
		"Boundary Alternate Culture"
	)
	var alternate_culture_id := int(
		alternate_culture.get("id", -1)
	)
	var citizen := WorldData.add_city_citizen(
		"",
		Vector2i(5, 5),
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		alternate_culture_id
	)

	_expect(
		alternate_culture_id > 0
		and alternate_culture_id != test_primary_culture_id
		and not citizen.is_empty(),
		"The culture fixture must create a citizen from a valid alternate culture."
	)

	if citizen.is_empty():
		return

	var errors: Array[String] = []
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		errors,
		WorldData.city_citizen_index_by_id
	)
	_expect(
		errors.is_empty(),
		"A citizen may validly differ from the city's primary culture."
	)

	citizen.erase("culture_id")
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		errors,
		WorldData.city_citizen_index_by_id
	)
	_expect(
		_culture_errors_contain(errors, "missing culture_id"),
		"Culture validation must reject a missing citizen culture_id."
	)

	citizen["culture_id"] = "not an integer"
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		errors,
		WorldData.city_citizen_index_by_id
	)
	_expect(
		_culture_errors_contain(errors, "non-integer culture_id"),
		"Culture validation must reject a non-integer citizen culture_id."
	)

	citizen["culture_id"] = 0
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		errors,
		WorldData.city_citizen_index_by_id
	)
	_expect(
		_culture_errors_contain(errors, "nonpositive culture_id"),
		"Culture validation must reject a nonpositive citizen culture_id."
	)

	var nonexistent_culture_id := 1_000_000

	while WorldData.has_culture_id(nonexistent_culture_id):
		nonexistent_culture_id += 1

	citizen["culture_id"] = nonexistent_culture_id
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		errors,
		WorldData.city_citizen_index_by_id
	)
	_expect(
		_culture_errors_contain(errors, "references nonexistent culture"),
		"Culture validation must reject an unresolved citizen culture_id."
	)

	citizen["culture_id"] = alternate_culture_id
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		errors,
		WorldData.city_citizen_index_by_id
	)
	_expect(
		errors.is_empty(),
		"Restoring the alternate culture must restore valid culture state."
	)

	var founding_citizen := WorldData.get_city_citizen_by_id(1)
	founding_citizen["culture_id"] = alternate_culture_id
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		errors,
		WorldData.city_citizen_index_by_id
	)
	_expect(
		_culture_errors_contain(
			errors,
			"does not reference the city's primary culture"
		),
		"A later alternate-culture citizen must not disable founder-culture validation."
	)
	founding_citizen["culture_id"] = test_primary_culture_id


func _test_world_founding_identity_commit_boundaries() -> void:
	print("Boundary test: world founding identity commit")
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game()

	var source_world := WorldData.new()
	source_world.setup(16, 16, TEST_WORLD_SEED)
	var region_top_left := Vector2i(2, 2)
	var region_center := Vector2i(6, 6)
	var lock_values := {
		"source_world": source_world,
		"region_top_left": region_top_left,
		"region_center": region_center,
		"region_size": 9,
		"world_scene_path": "res://scenes/WorldScene.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": "  Boundary Founding City  ",
		"culture_name": "  Boundary Founding Culture  ",
	}
	_expect(
		not WorldData.has_active_world_save()
		and WorldData.get_culture_snapshot().is_empty()
		and WorldData.get_official_city_name().is_empty()
		and WorldData.get_official_founding_culture_id()
		== WorldData.INVALID_CULTURE_ID
		and not WorldData.has_city_start_region(),
		"A fresh runtime must begin without authoritative founding state."
	)

	_expect(
		WorldData.lock_world_save(lock_values),
		"A complete world and founding identity must lock successfully."
	)
	var founding_culture_id := (
		WorldData.get_official_founding_culture_id()
	)
	_expect(
		WorldData.get_official_city_name() == "Boundary Founding City"
		and WorldData.get_official_founding_culture_name()
		== "Boundary Founding Culture"
		and WorldData.get_culture_snapshot().size() == 1
		and founding_culture_id > 0
		and WorldData.has_city_start_region(),
		"A successful lock must atomically store trimmed identity and one culture."
	)

	_expect(
		WorldData.lock_world_save(lock_values)
		and WorldData.get_culture_snapshot().size() == 1
		and WorldData.get_official_founding_culture_id()
		== founding_culture_id,
		"An identical relock must be idempotent and create no second culture."
	)

	var conflicting_lock_values: Dictionary = lock_values.duplicate(true)
	conflicting_lock_values["city_name"] = "Conflicting City"
	_expect(
		not WorldData.lock_world_save(conflicting_lock_values)
		and WorldData.get_official_city_name() == "Boundary Founding City"
		and WorldData.get_culture_snapshot().size() == 1
		and WorldData.get_official_founding_culture_id()
		== founding_culture_id,
		"A conflicting relock must fail without changing committed identity."
	)

	WorldData.reset_player_city_state()
	WorldData.reset_city_session_state()
	_expect(
		WorldData.has_active_world_save()
		and WorldData.has_official_founding_identity()
		and WorldData.get_culture_snapshot().size() == 1,
		"City-state resets must preserve the locked world's founding identity."
	)

	WorldData.reset_runtime_session_state()
	_expect(
		not WorldData.has_active_world_save()
		and not WorldData.has_official_founding_identity()
		and WorldData.get_culture_snapshot().is_empty()
		and WorldData.next_culture_id == 1
		and not WorldData.has_city_start_region(),
		"A full runtime reset must clear founding identity and culture records."
	)


func _culture_errors_contain(
	errors: Array[String],
	expected_text: String
) -> bool:
	for error_text in errors:
		if error_text.contains(expected_text):
			return true

	return false


func _reset_fixture() -> WorldData:
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game()
	CitizenDecisionSystemScript.reset_runtime_state()
	var city_world := WorldData.new()
	city_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, TEST_WORLD_SEED)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.get_tile(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["fertility"] = 50.0
			tile.erase("surface_feature")

	city_world.mark_tile_data_changed()
	WorldData.store_city_world_save(city_world, TEST_WORLD_SEED)
	var primary_culture := WorldData.create_culture(
		"Boundary Test Culture"
	)
	test_primary_culture_id = int(primary_culture.get("id", -1))
	WorldData.official_city_name = "Boundary Test City"
	WorldData.official_founding_culture_id = test_primary_culture_id
	WorldData.player_city_founded = true
	WorldData.player_city_data = {
		"id": 1,
		"name": "Boundary Test City",
		"primary_culture_id": test_primary_culture_id,
		"city_world_seed": TEST_WORLD_SEED,
		"city_map_size": TEST_WORLD_SIZE,
		"can_build": true,
		"founded": true,
	}
	return city_world


func _add_citizen(tile_position: Vector2i) -> Dictionary:
	return WorldData.add_city_citizen(
		"",
		tile_position,
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		test_primary_culture_id
	)


func _add_stockpile(
	city_world: WorldData,
	top_left: Vector2i
) -> Dictionary:
	return WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_STOCKPILE,
		"top_left": top_left,
		"size_tiles": WorldData.get_city_object_size_for_type(
						WorldData.CITY_OBJECT_STOCKPILE
					),
		"object_owner": "player",
		"city_world": city_world,
	})


func _add_ground_resource(
	tile_position: Vector2i,
	resource: String,
	amount: int
) -> int:
	var add_result := WorldData.add_resource_to_city_ground_piles_with_result({
		"tile_position": tile_position,
		"resource": resource,
		"amount_delta": amount,
	})

	for raw_placement in add_result.get("placements", []):
		if raw_placement is Dictionary:
			return int(raw_placement.get("ground_pile_id", -1))

	return -1


func _make_cleanup_haul_request(
	city_world: WorldData,
	citizen: Dictionary,
	source_id: int
) -> Dictionary:
	var source := WorldData.make_city_ground_pile_haul_endpoint(source_id)
	return CitizenHaulingSystemScript.make_public_storage_haul_task_request({
		"city_world": city_world,
		"citizen": citizen,
		"source": source,
		"requester": source,
		"resource_type": str(
			WorldData.get_city_ground_pile_by_id(source_id).get(
				"resource_type",
				WorldData.RESOURCE_NONE
			)
		),
		"requested_amount": WorldData.DEFAULT_CITIZEN_CARRY_CAPACITY,
		"reason": WorldData.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP,
		"source_access_purpose": (
			WorldData.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
		),
		"destination_access_purpose": (
			WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
		),
		"task_source": WorldData.CITY_CITIZEN_TASK_SOURCE_AUTONOMY,
		"task_priority": AUTONOMOUS_CLEANUP_PRIORITY,
	})


func _add_natural_command(
	city_world: WorldData,
	command_type: String,
	tile_position: Vector2i
) -> int:
	city_world.get_tile(tile_position.x, tile_position.y)[
		"surface_feature"
	] = CityWorkSystem.get_city_player_command_surface_feature(command_type)
	var added_count := CityWorkSystem.add_city_player_command_targets(
		command_type,
		[tile_position]
	)

	if added_count != 1:
		return -1

	return int(
		CityWorkSystem.get_city_player_command_at_tile(tile_position).get(
			"id",
			-1
		)
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
