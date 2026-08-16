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
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 24)
const TEST_WORLD_SEED: int = 41_207
const AUTONOMOUS_CLEANUP_PRIORITY: int = 90

var failure_count: int = 0
var test_primary_culture_id: int = -1
var test_city_state: CitySettlementSimulationState


func _ready() -> void:
	_test_normal_order_preempts_before_pickup()
	_test_normal_order_waits_for_picked_up_cargo_delivery()
	_test_chained_pickup_respects_near_full_destination()
	_test_public_storage_keep_fallback()
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
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, haul_request),
		"The pre-pickup fixture must assign a real autonomous haul."
	)

	var reservation_id := CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
		citizen_id
	)
	_expect(
		reservation_id > 0
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0,
		"The autonomous haul must begin reserved but before pickup."
	)

	var command_id := _add_natural_command(
		city_world,
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
		Vector2i(4, 5)
	)
	CitizenDecisionSystemScript.run_tick(1, 2)
	var assigned_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)

	_expect(
		str(assigned_task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
		and int(assigned_task.get("target_object_id", -1)) == command_id,
		"A Normal tree order must replace the autonomous haul before pickup."
	)
	_expect(
		CityLogisticsSystem.get_city_haul_reservation(reservation_id).is_empty(),
		"Pre-pickup interruption must release the old haul reservation."
	)
	_expect(
		CityLogisticsSystem.get_city_ground_pile_resource_amount(
			CityLogisticsSystem.get_city_ground_pile_by_id(source_id),
			WorldData.RESOURCE_LUMBER
		) == 2
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0,
		"Pre-pickup interruption must leave the physical source untouched."
	)

	# Run the actual command executor through its visible performing boundary.
	CitizenTaskSystemScript.run_tick(2, 2)
	var performing_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	_expect(
		str(performing_task.get("phase", ""))
		== CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING,
		"The commanded tree must enter its real performing phase."
	)
	SimulationClock.absolute_world_minutes += (
		CityWorkSystem.CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES
	)
	CitizenTaskSystemScript.run_tick(3, 2)
	_expect(
		CityWorkSystem.get_city_player_command_by_id(command_id).is_empty()
		and CityResourceAccountingSystem.get_total_physical_city_resource_amount(
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
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, haul_request),
		"The after-pickup fixture must assign a real autonomous haul."
	)
	CitizenTaskSystemScript.run_tick(1, 2)
	CitizenTaskSystemScript.run_tick(2, 2)

	var haul_after_pickup := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)
	_expect(
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_STONE
		) == 2
		and str(haul_after_pickup.get("phase", "")) in [
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION,
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION,
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_DEPOSITING,
		],
		"The real pickup executor must move both stone units into cargo."
	)

	var command_id := _add_natural_command(
		city_world,
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK,
		Vector2i(4, 5)
	)
	var physical_before_order := (
		CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_STONE
		)
	)
	CitizenDecisionSystemScript.run_tick(3, 2)
	var task_after_order := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)

	_expect(
		str(task_after_order.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_STONE
		) == 2,
		"A Normal rock order must wait while already-picked-up cargo is delivered."
	)
	_expect(
		CityLogisticsSystem.get_total_city_ground_pile_resource_amount(
			WorldData.RESOURCE_STONE
		) == 0
		and CityResourceAccountingSystem.get_total_physical_city_resource_amount(
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

		var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)

		if (
			str(current_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
			and int(current_task.get("target_object_id", -1)) == command_id
		):
			assigned_command_after_delivery = true
			break

	_expect(
		CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id(stockpile_id),
			WorldData.RESOURCE_STONE
		) == 2
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0,
		"Picked-up cargo must reach its reserved destination before preemption."
	)
	_expect(
		assigned_command_after_delivery,
		"The waiting Normal rock order must be assigned after delivery."
	)
	_expect(
		CityLogisticsSystem.get_total_city_ground_pile_resource_amount(
			WorldData.RESOURCE_STONE
		) == 0,
		"The completed delivery must not leave an ordinary-command cargo spill."
	)


func _test_chained_pickup_respects_near_full_destination() -> void:
	print("Boundary test: chained pickup destination capacity")
	var city_world := _reset_fixture()
	var citizen := _add_citizen(Vector2i(5, 5))
	var citizen_id := int(citizen.get("id", -1))
	var keep := _add_keep(city_world, Vector2i(20, 10))
	var stockpile := _add_stockpile(city_world, Vector2i(10, 4))
	var stockpile_id := int(stockpile.get("id", -1))
	var stockpile_capacity := CityResourceContainerSystem.get_city_object_storage_capacity(
		stockpile
	)
	var stored_amount := CityResourceContainerSystem.add_resource_to_city_object_storage(
		stockpile_id,
		WorldData.RESOURCE_LUMBER,
		stockpile_capacity - 4
	)
	var first_source_id := _add_ground_resource(
		Vector2i(5, 5),
		WorldData.RESOURCE_LUMBER,
		2
	)
	var second_source_id := _add_ground_resource(
		Vector2i(8, 5),
		WorldData.RESOURCE_LUMBER,
		8
	)
	var haul_request := _make_cleanup_haul_request(
		city_world,
		citizen,
		first_source_id
	)

	_expect(
		not keep.is_empty()
		and stockpile_id > 0
		and stored_amount == stockpile_capacity - 4
		and first_source_id > 0
		and second_source_id > 0
		and not haul_request.is_empty()
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, haul_request),
		"The chained-pickup fixture must assign a near-full storage haul."
	)

	CitizenTaskSystemScript.run_tick(1, 2)
	CitizenTaskSystemScript.run_tick(2, 2)

	var reservation_id := (
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
			citizen_id
		)
	)
	var reservation := CityLogisticsSystem.get_city_haul_reservation(
		reservation_id
	)
	var destination_reserved_amount := int(
		reservation.get("destination_reserved_amount", 0)
	)
	var source_reserved_amount := int(
		reservation.get("source_reserved_amount", 0)
	)
	var destination_free_space := CityResourceContainerSystem.get_city_object_storage_free_space(
		CityObjectSystem.get_city_object_by_id(stockpile_id)
	)
	var validation_result := _validate_fixture_city(true, false)
	var has_shared_capacity_error := false

	for raw_error in validation_result.get("errors", []):
		if (
			"Destination reservations exceed shared free capacity"
			in str(raw_error)
		):
			has_shared_capacity_error = true
			break

	_expect(
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_LUMBER
		) == 2
		and int(reservation.get("source", {}).get("id", -1))
		== second_source_id,
		"The first pickup must enter cargo and chain to the second pile."
	)
	_expect(
		source_reserved_amount == 2
		and destination_reserved_amount == 4
		and destination_reserved_amount <= destination_free_space,
		"A chained pickup may reserve only the destination space left after its loaded cargo."
	)
	_expect(
		not has_shared_capacity_error,
		"Chained pickup reservations must keep shared container capacity valid."
	)

	var container_version_before_deposit := (
		CityResourceAccountingSystem.get_city_container_version()
	)
	var public_version_before_deposit := (
		CityResourceAccountingSystem.get_city_public_storage_version()
	)
	var physical_lumber_before_deposit := (
		CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		)
	)
	var unreserved_accepted := (
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_LUMBER,
			1
		)
	)
	var wrong_reservation_accepted := (
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_LUMBER,
			1,
			reservation_id + 10_000
		)
	)

	_expect(
		unreserved_accepted == 0
		and wrong_reservation_accepted == 0,
		"Reserved near-full capacity must reject unreserved and wrong-reservation deposits."
	)
	_expect(
		CityResourceAccountingSystem.get_city_container_version()
		== container_version_before_deposit
		and CityResourceAccountingSystem.get_city_public_storage_version()
		== public_version_before_deposit,
		"Rejected deposits must not publish container or public-storage changes."
	)

	var haul_completed := false

	for tick_index in range(3, 48):
		SimulationClock.absolute_world_minutes += 2
		CitizenMovementSystemScript.run_tick(tick_index, 2)
		CitizenTaskSystemScript.run_tick(tick_index, 2)

		if (
			CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0
			and CityLogisticsSystem
			.get_city_haul_reservation(reservation_id).is_empty()
			and CityResourceContainerSystem
			.get_city_object_storage_free_space(
				CityObjectSystem.get_city_object_by_id(stockpile_id)
			) == 0
		):
			haul_completed = true
			break

	var final_stockpile := CityObjectSystem.get_city_object_by_id(
		stockpile_id
	)
	var final_validation := _validate_fixture_city(true, true)

	_expect(
		haul_completed
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			final_stockpile,
			WorldData.RESOURCE_LUMBER
		) == stockpile_capacity
		and CityResourceContainerSystem.get_city_object_storage_free_space(
			final_stockpile
		) == 0,
		"The reserved haul must complete by filling the Stockpile exactly to capacity."
	)
	_expect(
		CityLogisticsSystem.get_city_ground_pile_resource_amount(
			CityLogisticsSystem.get_city_ground_pile_by_id(second_source_id),
			WorldData.RESOURCE_LUMBER
		) == 6,
		"The chained source must retain the six units that could not fit."
	)
	_expect(
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0
		and CityLogisticsSystem
		.get_city_haul_reservation(reservation_id).is_empty(),
		"Completed delivery must clear both citizen cargo and its reservation."
	)
	_expect(
		bool(final_validation.get("valid", false))
		and final_validation.get("errors", []).is_empty(),
		"The completed near-full haul must leave the unified city state valid."
	)
	_expect(
		CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == physical_lumber_before_deposit,
		"The chained pickup and reserved deposit must conserve physical lumber."
	)
	_expect(
		CityResourceAccountingSystem.get_city_container_version()
		== container_version_before_deposit + 1
		and CityResourceAccountingSystem.get_city_public_storage_version()
		== public_version_before_deposit + 1,
		"Only the real Stockpile deposit may advance container and public-storage versions."
	)


func _test_public_storage_keep_fallback() -> void:
	print("Boundary test: public storage Keep fallback")
	var city_world := _reset_fixture()
	var citizen := _add_citizen(Vector2i(5, 5))
	var citizen_id := int(citizen.get("id", -1))
	var keep := _add_keep(city_world, Vector2i(20, 10))
	var keep_id := int(keep.get("id", -1))
	var stockpile := _add_stockpile(city_world, Vector2i(10, 4))
	var stockpile_id := int(stockpile.get("id", -1))
	var fallback_amount := 3
	var source_id := _add_ground_resource(
		Vector2i(5, 5),
		WorldData.RESOURCE_LUMBER,
		fallback_amount
	)
	var versions_before_stockpile_probe := {
		"container": CityResourceAccountingSystem.get_city_container_version(),
		"public": CityResourceAccountingSystem.get_city_public_storage_version(),
	}
	var stockpile_probe_request := _make_cleanup_haul_request(
		city_world,
		citizen,
		source_id
	)
	var stockpile_probe_assigned := (
		not stockpile_probe_request.is_empty()
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task(
			citizen_id,
			stockpile_probe_request
		)
	)
	var stockpile_probe_reservation_id := (
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
			citizen_id
		)
	)
	var stockpile_probe_reservation := (
		CityLogisticsSystem.get_city_haul_reservation(
			stockpile_probe_reservation_id
		)
	)

	_expect(
		keep_id > 0
		and stockpile_id > 0
		and source_id > 0
		and stockpile_probe_assigned
		and int(
			stockpile_probe_reservation
			.get("destination", {}).get("id", -1)
		) == stockpile_id,
		"Cleanup hauling must prefer a Stockpile while it has unreserved space."
	)
	_expect(
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
		)
		and CityLogisticsSystem.get_city_haul_reservation(
			stockpile_probe_reservation_id
		).is_empty()
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0
		and CityResourceAccountingSystem.get_city_container_version()
		== int(versions_before_stockpile_probe["container"])
		and CityResourceAccountingSystem.get_city_public_storage_version()
		== int(versions_before_stockpile_probe["public"]),
		"Routing and canceling the Stockpile probe must release state without publishing storage changes."
	)

	var stockpile_capacity := (
		CityResourceContainerSystem.get_city_object_storage_capacity(
			stockpile
		)
	)
	var accepted_filler := (
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_COAL,
			stockpile_capacity
		)
	)
	var container_version_before_keep_delivery := (
		CityResourceAccountingSystem.get_city_container_version()
	)
	var public_version_before_keep_delivery := (
		CityResourceAccountingSystem.get_city_public_storage_version()
	)
	var physical_lumber_before_keep_delivery := (
		CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		)
	)

	citizen = CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var keep_request := _make_cleanup_haul_request(
		city_world,
		citizen,
		source_id
	)
	var keep_haul_assigned := (
		accepted_filler == stockpile_capacity
		and CityResourceContainerSystem.get_city_object_storage_free_space(
			CityObjectSystem.get_city_object_by_id(stockpile_id)
		) == 0
		and not keep_request.is_empty()
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, keep_request)
	)
	var keep_reservation_id := (
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
			citizen_id
		)
	)
	var keep_reservation := CityLogisticsSystem.get_city_haul_reservation(
		keep_reservation_id
	)

	_expect(
		keep_haul_assigned
		and int(keep_reservation.get("destination", {}).get("id", -1))
		== keep_id
		and int(keep_reservation.get("destination_reserved_amount", 0))
		== fallback_amount,
		"A full Stockpile must route a fresh cleanup haul to the City Keep."
	)
	_expect(
		CityResourceAccountingSystem.get_city_container_version()
		== container_version_before_keep_delivery
		and CityResourceAccountingSystem.get_city_public_storage_version()
		== public_version_before_keep_delivery,
		"Fallback matching and reservation must not publish a storage mutation."
	)

	var keep_delivery_completed := false

	for tick_index in range(1, 64):
		SimulationClock.absolute_world_minutes += 2
		CitizenMovementSystemScript.run_tick(tick_index, 2)
		CitizenTaskSystemScript.run_tick(tick_index, 2)

		if (
			CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0
			and CityLogisticsSystem
			.get_city_haul_reservation(keep_reservation_id).is_empty()
			and CityResourceContainerSystem
			.get_city_object_stored_resource_amount(
				CityObjectSystem.get_city_object_by_id(keep_id),
				WorldData.RESOURCE_LUMBER
			) == fallback_amount
		):
			keep_delivery_completed = true
			break

	var final_keep := CityObjectSystem.get_city_object_by_id(keep_id)
	var final_validation := _validate_fixture_city(true, true)

	_expect(
		keep_delivery_completed
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			final_keep,
			WorldData.RESOURCE_LUMBER
		) == fallback_amount,
		"The fallback haul must deliver the exact cleanup amount to the Keep."
	)
	_expect(
		CityLogisticsSystem.get_city_ground_pile_by_id(source_id).is_empty()
		and CityLogisticsSystem.get_total_city_ground_pile_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == 0,
		"The completed Keep fallback must empty the cleanup pile."
	)
	_expect(
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0
		and CityLogisticsSystem
		.get_city_haul_reservation(keep_reservation_id).is_empty(),
		"The completed Keep fallback must clear cargo and its reservation."
	)
	_expect(
		bool(final_validation.get("valid", false))
		and final_validation.get("errors", []).is_empty(),
		"The Keep fallback must leave the unified city state valid."
	)
	_expect(
		CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == physical_lumber_before_keep_delivery,
		"The Keep fallback must conserve physical lumber."
	)
	_expect(
		CityResourceAccountingSystem.get_city_container_version()
		== container_version_before_keep_delivery + 1
		and CityResourceAccountingSystem.get_city_public_storage_version()
		== public_version_before_keep_delivery + 1,
		"Only the real Keep deposit may advance container and public-storage versions during fallback."
	)


func _test_critical_hunger_interrupts_cargo_safely() -> void:
	print("Boundary test: critical-hunger interruption")
	var city_world := _reset_fixture()
	var citizen := _add_citizen(Vector2i(5, 5))
	var citizen_id := int(citizen.get("id", -1))
	_add_stockpile(city_world, Vector2i(10, 4))
	var fishery_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
	)
	var fishery := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(12, 9),
		"size_tiles": fishery_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery_id := int(fishery.get("id", -1))
	_expect(
		CityResourceContainerSystem.add_resource_to_city_object_storage(
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
		CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id).get(
			"job_object_id",
			-1
		)
	) > 0:
		CityAssignmentSystem.remove_city_citizen_job(citizen_id)

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
	var haul_assigned := CityCitizenTaskRuntimeSystem.assign_city_citizen_task(
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
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_LUMBER
		) == 2,
		"Critical interruption coverage requires already-picked-up cargo."
	)

	var reservation_id := CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
		citizen_id
	)
	var physical_before_interrupt := (
		CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		)
	)
	CitizenNeedsSystem.set_city_citizen_hunger_state(citizen_id, 20, 0)
	CitizenDecisionSystemScript.run_tick(3, 2)
	var food_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)

	_expect(
		str(food_task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		and int(food_task.get("target_object_id", -1)) == fishery_id,
		"Critical hunger must replace an in-flight haul with workplace-food acquisition."
	)
	_expect(
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0
		and CityLogisticsSystem.get_city_haul_reservation(reservation_id).is_empty(),
		"Critical interruption must release cargo state and its old reservation."
	)
	_expect(
		CityLogisticsSystem.get_total_city_ground_pile_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == 2
		and CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == physical_before_interrupt,
		"Critical interruption may spill exceptionally, but must do so atomically without loss."
	)


func _test_construction_labor_releases_at_atomic_boundary() -> void:
	print("Boundary test: construction labor atomic boundary")
	var city_world := _reset_fixture()
	var house_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_HOUSE
	)
	var house_site := CityConstructionSystemScript.create_rectangular_site({
		"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
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
	house_site = CityConstructionSystem.get_city_construction_site_by_id(site_id)
	_expect(
		str(house_site.get("phase", ""))
		== CityConstructionSystem.CITY_CONSTRUCTION_PHASE_LABOR,
		"A fully supplied clear House must enter labor."
	)

	var work_positions := (
		CityConstructionSystem.get_city_construction_site_work_positions(house_site)
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
	var assigned_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	_expect(
		str(assigned_task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
		and int(assigned_task.get("target_object_id", -1)) == site_id,
		"The unified scheduler must assign the nearby construction labor job."
	)

	CitizenTaskSystemScript.run_tick(2, 2)
	var performing_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	var boundary_minute := int(
		performing_task.get(
			"next_action_world_minute",
			CityCitizens.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)
	_expect(
		str(performing_task.get("phase", ""))
		== CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		and boundary_minute
		== SimulationClock.absolute_world_minutes
		+ CityConstructionSystem.CITY_CONSTRUCTION_LABOR_ATOMIC_MINUTES,
		"Construction labor must publish its exact 30-minute atomic boundary."
	)

	SimulationClock.absolute_world_minutes = boundary_minute - 1
	CitizenTaskSystemScript.run_tick(3, 29)
	var before_boundary_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
		citizen_id
	)
	_expect(
		str(before_boundary_task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
		and int(
			CityConstructionSystem.get_city_construction_site_by_id(site_id).get(
				"completed_labor_minutes",
				-1
			)
		)
		== 29,
		"Labor must remain committed one minute before its atomic boundary."
	)

	SimulationClock.absolute_world_minutes = boundary_minute
	CitizenTaskSystemScript.run_tick(4, 1)
	var released_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	_expect(
		str(released_task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
		and int(
			CityConstructionSystem.get_city_construction_site_by_id(site_id).get(
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
	var reassigned_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	_expect(
		str(reassigned_task.get("source", ""))
		== CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		and int(reassigned_task.get("work_order_id", -1)) > 0
		and not str(reassigned_task.get("job_id", "")).is_empty(),
		"The next decision pass must assign a real unified-board job after the boundary."
	)


func _test_culture_identity_validation() -> void:
	print("Boundary test: citizen culture identity")
	_reset_fixture()
	var validation_target := _get_fixture_validation_target()

	for founder_index in range(CityCitizenRegistrySystem.STARTING_CITY_POPULATION):
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
	var citizen := CityCitizenRegistrySystem.add_city_citizen(
		"",
		Vector2i(5, 5),
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
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
		validation_target,
		errors,
		CityCitizenRegistrySystem.get_current_state().citizen_index_by_id
	)
	_expect(
		errors.is_empty(),
		"A citizen may validly differ from the city's primary culture."
	)

	citizen.erase("culture_id")
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		validation_target,
		errors,
		CityCitizenRegistrySystem.get_current_state().citizen_index_by_id
	)
	_expect(
		_culture_errors_contain(errors, "missing culture_id"),
		"Culture validation must reject a missing citizen culture_id."
	)

	citizen["culture_id"] = "not an integer"
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		validation_target,
		errors,
		CityCitizenRegistrySystem.get_current_state().citizen_index_by_id
	)
	_expect(
		_culture_errors_contain(errors, "non-integer culture_id"),
		"Culture validation must reject a non-integer citizen culture_id."
	)

	citizen["culture_id"] = 0
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		validation_target,
		errors,
		CityCitizenRegistrySystem.get_current_state().citizen_index_by_id
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
		validation_target,
		errors,
		CityCitizenRegistrySystem.get_current_state().citizen_index_by_id
	)
	_expect(
		_culture_errors_contain(errors, "references nonexistent culture"),
		"Culture validation must reject an unresolved citizen culture_id."
	)

	citizen["culture_id"] = alternate_culture_id
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		validation_target,
		errors,
		CityCitizenRegistrySystem.get_current_state().citizen_index_by_id
	)
	_expect(
		errors.is_empty(),
		"Restoring the alternate culture must restore valid culture state."
	)

	var founding_citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(1)
	founding_citizen["culture_id"] = alternate_culture_id
	errors.clear()
	CityCitizenStateValidatorScript._validate_city_citizen_culture_state(
		validation_target,
		errors,
		CityCitizenRegistrySystem.get_current_state().citizen_index_by_id
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
			var tile := city_world.get_tile_for_internal_read(x, y)
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
	WorldPoliticalState.replace_current_city_runtime_data({
		"id": 1,
		"name": "Boundary Test City",
		"primary_culture_id": test_primary_culture_id,
		"city_world_seed": TEST_WORLD_SEED,
		"city_map_size": TEST_WORLD_SIZE,
		"can_build": true,
		"founded": true,
	})
	test_city_state = WorldPoliticalState.get_current_city_simulation_state()
	return city_world


func _validate_fixture_city(
	force_rebuild: bool,
	report_problems: bool
) -> Dictionary:
	return CityStateValidatorScript.validate_for_city_state(
		1,
		test_city_state,
		force_rebuild,
		report_problems
	)


func _get_fixture_validation_target() -> Dictionary:
	return {
		"settlement_context": null,
		"settlement_id": 1,
		"city_state": test_city_state,
	}


func _add_citizen(tile_position: Vector2i) -> Dictionary:
	return CityCitizenRegistrySystem.add_city_citizen(
		"",
		tile_position,
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		test_primary_culture_id
	)


func _add_keep(
	city_world: WorldData,
	top_left: Vector2i
) -> Dictionary:
	var city_state = WorldPoliticalState.get_current_city_simulation_state()
	if not city_state is CitySettlementSimulationState:
		return {}

	var runtime_data: Dictionary = city_state.city_runtime_data
	var was_founded := bool(runtime_data.get("founded", false))
	var could_build := bool(runtime_data.get("can_build", false))
	runtime_data["founded"] = false
	runtime_data["can_build"] = false
	var keep := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		"top_left": top_left,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	runtime_data["founded"] = was_founded
	runtime_data["can_build"] = could_build
	if not keep.is_empty() and was_founded:
		runtime_data["foundation_top_left"] = top_left
		runtime_data["foundation_size"] = keep.get("size", Vector2i.ZERO)
		runtime_data["foundation_object_id"] = int(keep.get("id", -1))
		runtime_data["foundation_object_owner"] = str(
			keep.get("owner", "player")
		)
	return keep


func _add_stockpile(
	city_world: WorldData,
	top_left: Vector2i
) -> Dictionary:
	return CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_STOCKPILE,
		"top_left": top_left,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
						CityObjectCatalog.CITY_OBJECT_STOCKPILE
					),
		"object_owner": "player",
		"city_world": city_world,
	})


func _add_ground_resource(
	tile_position: Vector2i,
	resource: String,
	amount: int
) -> int:
	var add_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
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
	var source := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(source_id)
	return CitizenHaulingSystemScript.make_public_storage_haul_task_request({
		"city_world": city_world,
		"citizen": citizen,
		"source": source,
		"requester": source,
		"resource_type": str(
			CityLogisticsSystem.get_city_ground_pile_by_id(source_id).get(
				"resource_type",
				WorldData.RESOURCE_NONE
			)
		),
		"requested_amount": CityCitizens.DEFAULT_CITIZEN_CARRY_CAPACITY,
		"reason": CityCitizens.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP,
		"source_access_purpose": (
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
		),
		"destination_access_purpose": (
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
		),
		"task_source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_AUTONOMY,
		"task_priority": AUTONOMOUS_CLEANUP_PRIORITY,
	})


func _add_natural_command(
	city_world: WorldData,
	command_type: String,
	tile_position: Vector2i
) -> int:
	city_world.set_tile_surface_feature(
		tile_position,
		CityWorkSystem.get_city_player_command_surface_feature(command_type)
	)
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
