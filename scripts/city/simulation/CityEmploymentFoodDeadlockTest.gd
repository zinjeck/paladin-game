extends Node

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityEmploymentSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CityEmploymentSystem.gd"
)
const CityWorkSystemScript = preload(
	"res://scripts/city/simulation/systems/CityWorkSystem.gd"
)
const CitizenDecisionSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenDecisionSystem.gd"
)
const CitizenTaskSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenTaskSystem.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 24)
const TEST_WORLD_SEED: int = 84_221

var failure_count: int = 0
var test_culture_id: int = -1


func _ready() -> void:
	_test_hunger_waits_for_real_food_opportunity()
	_test_starving_food_workers_keep_survival_schedule()
	_test_starving_worker_recovers_and_returns_to_work()
	_test_starving_residents_keep_return_home_schedule()
	_test_off_shift_home_queue_survives_unassignable_haul_work()
	_test_persistent_workplace_staffing_policy()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"Employment and food deadlock tests failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Employment and food deadlock tests passed.")
	get_tree().quit(0)


func _test_hunger_waits_for_real_food_opportunity() -> void:
	var city_world := _reset_fixture()
	var normal_citizen := _add_citizen(Vector2i(3, 4))
	var critical_citizen := _add_citizen(Vector2i(3, 6))
	var normal_id := int(normal_citizen.get("id", -1))
	var critical_id := int(critical_citizen.get("id", -1))

	CitizenNeedsSystem.set_city_citizen_hunger_state(normal_id, 60, 0)
	CitizenNeedsSystem.set_city_citizen_hunger_state(critical_id, 0, 0)

	var road_sites := CityConstructionSystemScript.create_road_sites(
		[Vector2i(9, 4), Vector2i(9, 6)],
		"player",
		city_world
	)
	_expect(
		road_sites.size() == 2,
		"The hunger deadlock fixture must create two independent road sites."
	)

	CityWorkSystemScript.synchronize_player_work_board()
	CitizenDecisionSystemScript._process_player_commands()

	_expect(
		_task_kind(normal_id) == CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
		and _task_kind(critical_id)
		== CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION,
		"Hungry citizens without obtainable food must remain eligible for road and construction work."
	)

	CitizenTaskSystemScript.run_tick(1, 2)
	_expect(
		_task_kind(normal_id) == CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION,
		"Normal hunger must not speculatively release work before a food source exists."
	)

	var stockpile := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_STOCKPILE,
		"top_left": Vector2i(4, 10),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_STOCKPILE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var stockpile_id := int(stockpile.get("id", -1))
	_expect(stockpile_id > 0, "The food fixture must create public storage.")

	CityResourceContainerSystem.add_resource_to_city_object_storage(
		stockpile_id,
		WorldData.RESOURCE_FISH,
		1
	)
	CitizenDecisionSystemScript._process_food_needs(true)

	_expect(
		_task_kind(critical_id) == CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		and _task_kind(normal_id)
		== CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION,
		"One available fish must interrupt the critical citizen only after the source is matched and reserved."
	)

	CityResourceContainerSystem.add_resource_to_city_object_storage(
		stockpile_id,
		WorldData.RESOURCE_FISH,
		1
	)
	CitizenDecisionSystemScript._process_food_needs(false)

	_expect(
		_task_kind(normal_id) == CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD,
		"Normal hunger must yield construction at a safe boundary as soon as a real food opportunity exists."
	)


func _test_starving_food_workers_keep_survival_schedule() -> void:
	var city_world := _reset_fixture()
	SimulationClock.start_new_game(1, 8, 0)
	var citizen_ids: Array[int] = []

	for index in range(4):
		var citizen := _add_citizen(Vector2i(3, 3 + index * 2))
		var citizen_id := int(citizen.get("id", -1))
		citizen_ids.append(citizen_id)
		CitizenNeedsSystem.set_city_citizen_hunger_state(citizen_id, 0, 0)

	var fishery := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(15, 8),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery_id := int(fishery.get("id", -1))
	_expect(fishery_id > 0, "The starvation fixture must create a Fishery.")

	CityEmploymentSystemScript.run_tick(1, 2)
	fishery = CityObjectSystem.get_city_object_by_id(fishery_id)
	_expect(
		CityEmploymentSystem.get_city_object_worker_count(fishery) == 4,
		"The starvation fixture must assign all four Fishery workers."
	)

	for citizen_id in citizen_ids:
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
		_expect(
			int(citizen.get("job_object_id", -1)) == fishery_id,
			"Every starvation fixture citizen must remain assigned to the Fishery."
		)
		var work_request := (
			CitizenDecisionSystemScript._get_assigned_work_task_request(citizen)
		)
		_expect(
			str(work_request.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_WORK,
			"A starving assigned food worker must still receive scheduled Work when no food exists."
		)
		_expect(
			CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, work_request),
			"The starvation fixture must assign each generated Work request."
		)

	var stockpile := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_STOCKPILE,
		"top_left": Vector2i(8, 12),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_STOCKPILE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var stockpile_id := int(stockpile.get("id", -1))
	_expect(stockpile_id > 0, "The starvation fixture must create public storage.")
	CityResourceContainerSystem.add_resource_to_city_object_storage(
		stockpile_id,
		WorldData.RESOURCE_FISH,
		1
	)

	CitizenDecisionSystemScript._process_food_needs(true)

	var acquiring_food_count := 0
	var continuing_work_count := 0

	for citizen_id in citizen_ids:
		match _task_kind(citizen_id):
			CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD:
				acquiring_food_count += 1
			CityCitizens.CITY_CITIZEN_TASK_KIND_WORK:
				continuing_work_count += 1

	_expect(
		acquiring_food_count == 1 and continuing_work_count == 3,
		"One real fish must interrupt one critical scheduled worker while the other three continue producing."
	)


func _test_starving_worker_recovers_and_returns_to_work() -> void:
	var city_world := _reset_fixture()
	WorldData.player_city_founded = true
	SimulationClock.start_new_game(1, 8, 0)
	var fishery := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(15, 8),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery_id := int(fishery.get("id", -1))
	var access_tiles := CityNavigationSystem.get_city_object_access_tiles(
		city_world,
		fishery
	)
	_expect(
		fishery_id > 0 and not access_tiles.is_empty(),
		"The starvation-recovery fixture must create an accessible Fishery."
	)

	if fishery_id <= 0 or access_tiles.is_empty():
		return

	var citizen := _add_citizen(access_tiles[0])
	var citizen_id := int(citizen.get("id", -1))
	CityEmploymentSystemScript.run_tick(1, 2)
	CitizenDecisionSystemScript.run_tick(1, 2)
	citizen = CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	_expect(
		int(citizen.get("job_object_id", -1)) == fishery_id
		and _task_kind(citizen_id) == CityCitizens.CITY_CITIZEN_TASK_KIND_WORK,
		"An employed Fishery worker must begin scheduled Work during the shift."
	)

	_expect(
		CitizenNeedsSystem.set_city_citizen_hunger_state(citizen_id, 0, 0),
		"The starvation-recovery fixture must make the worker critically hungry."
	)
	_expect(
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			fishery_id,
			WorldData.RESOURCE_FISH,
			4
		) == 4,
		"The starvation-recovery fixture must expose four whole workplace fish."
	)

	for meal_index in range(4):
		var decision_tick := meal_index + 2
		CitizenDecisionSystemScript.run_tick(decision_tick, 2)
		_expect(
			_task_kind(citizen_id)
			== CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD,
			"A real accessible fish must interrupt Work and allocate exactly one meal."
		)

		CitizenTaskSystemScript.run_tick(decision_tick, 2)
		_expect(
			CitizenNeedsSystem.get_city_citizen_hunger(citizen_id)
			== (meal_index + 1) * 20
			and CityCitizenInventorySystem.get_city_citizen_inventory_resource_amount(
				citizen_id,
				WorldData.RESOURCE_FISH
			) == 0,
			"Each Acquire Food task must consume one whole fish without pocketing a reserve."
		)

	_expect(
		CitizenNeedsSystem.get_city_citizen_hunger(citizen_id) == 80
		and _task_kind(citizen_id) == CityCitizens.CITY_CITIZEN_TASK_KIND_NONE,
		"Four whole fish must recover starvation to 80 and complete the food task."
	)
	_expect(
		CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id(fishery_id),
			WorldData.RESOURCE_FISH
		) == 0,
		"Starvation recovery must consume exactly the four physical source fish."
	)

	CitizenDecisionSystemScript.run_tick(6, 2)
	citizen = CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	_expect(
		_task_kind(citizen_id) == CityCitizens.CITY_CITIZEN_TASK_KIND_WORK
		and int(citizen.get("job_object_id", -1)) == fishery_id,
		"The next in-shift decision must return the recovered worker to Work without losing the job."
	)
	CitizenTaskSystemScript.run_tick(7, 2)
	_expect(
		_task_kind(citizen_id) == CityCitizens.CITY_CITIZEN_TASK_KIND_WORK,
		"Resumed scheduled Work must execute a task step instead of being a transient assignment."
	)

	_expect(
		CityCitizenInventorySystem.set_city_citizen_haul_cargo(
			citizen_id,
			WorldData.RESOURCE_STONE,
			1
		) == 1
		and CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		)
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_STONE
		) == 1,
		"Clearing non-haul Work while cargo exists must preserve the physical cargo."
	)

	citizen = CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var resumed_work_request := (
		CitizenDecisionSystemScript._get_assigned_work_task_request(citizen)
	)
	_expect(
		not resumed_work_request.is_empty()
		and not CityCitizenTaskRuntimeSystem.assign_city_citizen_task(
			citizen_id,
			resumed_work_request
		)
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_STONE
		) == 1,
		"Rejecting non-haul reassignment while cargo exists must not erase the cargo."
	)


func _test_starving_residents_keep_return_home_schedule() -> void:
	var city_world := _reset_fixture()
	SimulationClock.start_new_game(1, 18, 0)
	var citizen := _add_citizen(Vector2i(3, 4))
	var citizen_id := int(citizen.get("id", -1))
	CitizenNeedsSystem.set_city_citizen_hunger_state(citizen_id, 0, 0)

	var house := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(20, 12),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_HOUSE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var house_id := int(house.get("id", -1))
	_expect(house_id > 0, "The return-home fixture must create a House.")
	_expect(
		CityAssignmentSystem.assign_city_citizen_home(citizen_id, house_id),
		"The return-home fixture must assign the citizen to the House."
	)

	citizen = CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var home_request := (
		CitizenDecisionSystemScript._get_assigned_home_task_request(citizen)
	)
	_expect(
		str(home_request.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
		"A starving resident without obtainable food must still receive Return Home."
	)
	_expect(
		CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, home_request),
		"The return-home fixture must assign the generated Return Home request."
	)

	var stockpile := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_STOCKPILE,
		"top_left": Vector2i(8, 12),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_STOCKPILE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var stockpile_id := int(stockpile.get("id", -1))
	_expect(
		stockpile_id > 0,
		"The return-home fixture must create public storage."
	)
	CityResourceContainerSystem.add_resource_to_city_object_storage(
		stockpile_id,
		WorldData.RESOURCE_FISH,
		1
	)
	CitizenDecisionSystemScript._process_food_needs(true)

	_expect(
		_task_kind(citizen_id) == CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD,
		"A real reachable meal must interrupt scheduled Return Home for a critical resident."
	)


func _test_off_shift_home_queue_survives_unassignable_haul_work() -> void:
	_reset_fixture()
	SimulationClock.start_new_game(1, 18, 0)
	var raw_city_state = WorldPoliticalState.get_current_city_simulation_state()
	_expect(
		raw_city_state is CitySettlementSimulationState,
		"The off-shift haul fixture must own an explicit settlement state."
	)

	if not raw_city_state is CitySettlementSimulationState:
		return

	var city_state: CitySettlementSimulationState = raw_city_state
	var house := CityObjectSystem.register_completed_city_object_for_city_state(
		city_state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
			"top_left": Vector2i(20, 12),
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_HOUSE
			),
			"object_owner": "player",
		}
	)
	var fishery := CityObjectSystem.register_completed_city_object_for_city_state(
		city_state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
			"top_left": Vector2i(15, 8),
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
			),
			"object_owner": "player",
		}
	)
	var stockpile := CityObjectSystem.register_completed_city_object_for_city_state(
		city_state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_STOCKPILE,
			"top_left": Vector2i(8, 12),
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_STOCKPILE
			),
			"object_owner": "player",
		}
	)
	var house_id := int(house.get("id", -1))
	var fishery_id := int(fishery.get("id", -1))
	var stockpile_id := int(stockpile.get("id", -1))
	_expect(
		house_id > 0 and fishery_id > 0 and stockpile_id > 0,
		"The off-shift haul fixture must create local home, job, and storage objects."
	)

	if house_id <= 0 or fishery_id <= 0 or stockpile_id <= 0:
		return

	var citizen_ids: Array[int] = []

	for index in range(2):
		var citizen := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
			city_state,
			"",
			Vector2i(3, 4 + index * 2),
			CityCitizens.CITY_CITIZEN_SEX_FEMALE,
			test_culture_id
		)
		var citizen_id := int(citizen.get("id", -1))
		citizen_ids.append(citizen_id)
		_expect(
			citizen_id > 0
			and CityAssignmentSystem.assign_city_citizen_home_for_city_state(
				city_state,
				citizen_id,
				house_id
			)
			and CityAssignmentSystem.assign_city_citizen_job_for_city_state(
				city_state,
				citizen_id,
				fishery_id
			),
			"Every off-shift fixture resident must have one local home and job."
		)

	var unemployed_hauler_ids: Array[int] = []
	for index in range(2):
		var hauler := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
			city_state,
			"",
			Vector2i(5, 8 + index * 2),
			CityCitizens.CITY_CITIZEN_SEX_MALE,
			test_culture_id
		)
		var hauler_id := int(hauler.get("id", -1))
		unemployed_hauler_ids.append(hauler_id)
		CitizenNeedsSystem.set_city_citizen_hunger_state_for_city_state(
			city_state,
			hauler_id,
			0,
			0
		)

	var pile_result := (
		CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(
			city_state,
			{
				"tile_position": Vector2i(6, 10),
				"resource": WorldData.RESOURCE_STONE,
				"amount_delta": 20,
			}
		)
	)
	_expect(
		int(pile_result.get("added_amount", 0)) == 20,
		"The off-shift fixture must expose real deliverable loose cargo."
	)

	CitizenDecisionSystemScript.run_tick_for_city_state(city_state, 1, 1)
	var current_fishery := CityObjectSystem.get_city_object_by_id_for_city_state(
		city_state,
		fishery_id
	)
	var assigned_worker_ids := (
		CityAssignmentSystem.get_city_object_worker_ids_for_city_state(
			city_state,
			current_fishery
		)
	)

	for citizen_id in citizen_ids:
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			city_state,
			citizen_id
		)
		var current_task := (
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
				city_state,
				citizen_id
			)
		)
		_expect(
			str(current_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
			"Unassignable haul work must not suppress an employed resident's Return Home task."
		)
		_expect(
			int(citizen.get("job_object_id", -1)) == fishery_id
			and assigned_worker_ids.has(citizen_id),
			"Return Home scheduling must preserve each settlement-local employment link."
		)

	# Consume both bounded haul slots on the following tick. Employed residents
	# must still receive Return Home while that bounded logistics pass is full.
	for citizen_id in citizen_ids:
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task_for_city_state(
			city_state,
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		)
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
			city_state,
			citizen_id
		)
	for hauler_id in unemployed_hauler_ids:
		CitizenNeedsSystem.set_city_citizen_hunger_state_for_city_state(
			city_state,
			hauler_id,
			100,
			0
		)
	city_state.citizen_decision_runtime_state.runtime_initialized = false
	CitizenDecisionSystemScript.run_tick_for_city_state(city_state, 2, 1)

	var haul_task_count := 0
	for hauler_id in unemployed_hauler_ids:
		var haul_task := (
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
				city_state,
				hauler_id
			)
		)
		if (
			str(haul_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
		):
			haul_task_count += 1
	_expect(
		haul_task_count == 2,
		"The bounded fixture must consume both autonomous haul assignment slots."
	)
	for citizen_id in citizen_ids:
		var home_task := (
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
				city_state,
				citizen_id
			)
		)
		_expect(
			str(home_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
			"A full autonomous-haul budget must not suppress an employed resident's Return Home task."
		)


func _test_persistent_workplace_staffing_policy() -> void:
	var city_world := _reset_fixture()
	var citizen_ids: Array[int] = []

	for index in range(4):
		var citizen := _add_citizen(Vector2i(3, 3 + index * 2))
		citizen_ids.append(int(citizen.get("id", -1)))

	var blocked_citizen_id := citizen_ids[0]
	_expect(
		CityCitizenInventorySystem.set_city_citizen_haul_cargo(
			blocked_citizen_id,
			WorldData.RESOURCE_STONE,
			1
		) == 1,
		"The staffing fixture must make the first unemployed candidate temporarily unavailable."
	)

	var fishery := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(15, 8),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery_id := int(fishery.get("id", -1))
	_expect(fishery_id > 0, "The staffing fixture must create a Fishery.")

	CityEmploymentSystemScript.run_tick(1, 2)
	fishery = CityObjectSystem.get_city_object_by_id(fishery_id)

	_expect(
		CityEmploymentSystemScript.get_workplace_staffing_mode(fishery)
		== CityEmploymentSystemScript.STAFFING_MODE_AUTOMATIC
		and CityEmploymentSystemScript.get_workplace_desired_worker_count(fishery) == 4,
		"New workplaces must default to automatic staffing with desired workers equal to capacity."
	)
	_expect(
		CityEmploymentSystem.get_city_object_worker_count(fishery) == 3
		and int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(blocked_citizen_id).get(
				"job_object_id",
				-1
			)
		) < 0,
		"A temporarily unavailable first candidate must not block later unemployed citizens from filling the Fishery."
	)

	CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources(blocked_citizen_id, {})
	CityEmploymentSystemScript.run_tick(2, 2)
	fishery = CityObjectSystem.get_city_object_by_id(fishery_id)
	_expect(
		CityEmploymentSystem.get_city_object_worker_count(fishery) == 4
		and int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(blocked_citizen_id).get(
				"job_object_id",
				-1
			)
		) == fishery_id,
		"The persistent vacancy must fill on a later tick when the deferred citizen becomes available."
	)

	var workplace_before_manual_request := fishery.duplicate(true)
	var object_version_before_manual_request := (
		CityObjectSystem.get_city_object_version()
	)
	var workplace_version_before_manual_request := (
		CityEmploymentSystemScript.get_city_workplace_version()
	)
	var citizen_version_before_manual_request := (
		CityCitizenRegistrySystem.get_city_citizen_version()
	)
	var assignment_version_before_manual_request := (
		CityAssignmentSystem.get_city_assignment_version()
	)
	var worker_ids_before_manual_request: Array = (
		CityEmploymentSystem.get_city_object_worker_ids(fishery).duplicate()
	)
	var citizen_job_ids_before_manual_request := {}

	for citizen_id in citizen_ids:
		citizen_job_ids_before_manual_request[citizen_id] = int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id).get(
				"job_object_id",
				-1
			)
		)

	var manual_request_accepted := (
		CityEmploymentSystemScript.set_workplace_staffing_mode(
			fishery_id,
			CityEmploymentSystemScript.STAFFING_MODE_MANUAL
		)
	)
	var assignments_unchanged := (
		CityEmploymentSystem.get_city_object_worker_ids(
			CityObjectSystem.get_city_object_by_id(fishery_id)
		)
		== worker_ids_before_manual_request
	)

	for citizen_id in citizen_ids:
		assignments_unchanged = (
			assignments_unchanged
			and int(
				CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id).get(
					"job_object_id",
					-1
				)
			)
			== int(citizen_job_ids_before_manual_request[citizen_id])
		)

	_expect(
		not manual_request_accepted
		and CityObjectSystem.get_city_object_by_id(fishery_id)
		== workplace_before_manual_request
		and CityObjectSystem.get_city_object_version()
		== object_version_before_manual_request
		and CityEmploymentSystemScript.get_city_workplace_version()
		== workplace_version_before_manual_request
		and CityCitizenRegistrySystem.get_city_citizen_version()
		== citizen_version_before_manual_request
		and CityAssignmentSystem.get_city_assignment_version()
		== assignment_version_before_manual_request
		and assignments_unchanged,
		"Automatic-only staffing must reject manual mode without mutating the workplace, versions, or assignments."
	)

	var removed_worker_id := int(worker_ids_before_manual_request[0])
	_expect(
		CityEmploymentSystemScript.remove_citizen_job(removed_worker_id),
		"The automatic staffing fixture must remove one assigned worker."
	)
	fishery = CityObjectSystem.get_city_object_by_id(fishery_id)
	_expect(
		CityEmploymentSystem.get_city_object_worker_count(fishery) == 3
		and int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(removed_worker_id).get(
				"job_object_id",
				-1
			)
		) < 0,
		"Removing one worker must create a real automatic-staffing vacancy before the next tick."
	)

	CityEmploymentSystemScript.run_tick(3, 2)
	fishery = CityObjectSystem.get_city_object_by_id(fishery_id)
	_expect(
		CityEmploymentSystem.get_city_object_worker_count(fishery) == 4
		and int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(removed_worker_id).get(
				"job_object_id",
				-1
			)
		) == fishery_id,
		"Automatic staffing must refill the removed worker's vacancy on the next tick."
	)


func _reset_fixture() -> WorldData:
	WorldData.reset_runtime_session_state()
	CitizenDecisionSystemScript.reset_runtime_state()
	SimulationClock.start_new_game()
	var city_world := WorldData.new()
	city_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, TEST_WORLD_SEED)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.get_tile_for_internal_read(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["fertility"] = 50.0

	city_world.mark_tile_data_changed()
	WorldData.store_city_world_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		city_world, TEST_WORLD_SEED)
	var culture := WorldData.create_culture("Employment Test Culture")
	test_culture_id = int(culture.get("id", -1))
	WorldPoliticalState.replace_current_city_runtime_data({
		"name": "Employment Test City",
		"primary_culture_id": test_culture_id,
		"founded": true,
		"can_build": true,
	})
	return city_world


func _add_citizen(tile_position: Vector2i) -> Dictionary:
	return CityCitizenRegistrySystem.add_city_citizen(
		"",
		tile_position,
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		test_culture_id
	)


func _task_kind(citizen_id: int) -> String:
	return str(
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id).get(
			"kind",
			CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
		)
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
