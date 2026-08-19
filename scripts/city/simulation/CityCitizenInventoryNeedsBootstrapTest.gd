extends Node

const CityCitizenStateValidatorScript := preload(
	"res://scripts/city/simulation/validators/CityCitizenStateValidator.gd"
)
const CityObjectStateValidatorScript := preload(
	"res://scripts/city/simulation/validators/CityObjectStateValidator.gd"
)

const TEST_CITY_NAME := "Inventory Needs Bootstrap"
const TEST_CULTURE_NAME := "Inventory Needs Culture"

var failure_count: int = 0
var validator_city_id: int = -1
var validator_city_state: CitySettlementSimulationState
var validator_settlement_context: SettlementSimulationContext


func _ready() -> void:
	_test_real_founding_records_and_clean_ensures()
	_test_lossless_legacy_repair_and_identity()
	_test_headless_simulation_bootstrap_and_canonical_setters()
	_test_malformed_carried_state_quarantine()
	_test_validator_rejects_uninterpretable_embedded_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen inventory/needs bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen inventory/needs bootstrap test passed.")
	get_tree().quit(0)


func _test_real_founding_records_and_clean_ensures() -> void:
	WorldData.reset_runtime_session_state()
	var founding_world := _make_world(8, 8, 98_901)

	if not _lock_founding_world(founding_world, "real founding"):
		return

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Real founding must establish an instance-owned capital before Keep placement."
	)
	var capital_state = WorldPoliticalState.get_active_city_simulation_state()

	if not capital_state is CitySettlementSimulationState:
		_expect(false, "Real founding must expose a City simulation state.")
		return

	var city_world := _make_world(20, 20, 98_902)
	WorldData.store_city_world_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		city_world, 98_902)
	var keep := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		"top_left": Vector2i(6, 6),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		),
		"object_owner": "player",
		"city_world": city_world,
	})

	_expect(not keep.is_empty(), "Real founding must place a City Keep.")

	if keep.is_empty():
		return

	WorldData.found_player_city({
		"city_world_seed": 98_902,
		"city_map_size": Vector2i(city_world.width, city_world.height),
		"foundation_top_left": keep.get("top_left", Vector2i(-1, -1)),
		"foundation_size": keep.get("size", Vector2i.ZERO),
	})

	var registry_state := CityCitizenRegistrySystem.get_current_state()
	var registry_array: Array = registry_state.citizens
	var registry_version_before := registry_state.citizen_version
	var complete_records := true

	for citizen_index in range(registry_array.size()):
		var raw_citizen = registry_array[citizen_index]

		if not raw_citizen is Dictionary:
			complete_records = false
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if (
			citizen_id != citizen_index + 1
			or not CityCitizens.has_complete_city_citizen_need_state(citizen)
			or not CityCitizens.has_complete_city_citizen_haul_cargo_state(
				citizen
			)
			or CityCitizenInventorySystem.get_city_citizen_carry_capacity(
				citizen_id
			) != CityCitizens.DEFAULT_CITIZEN_CARRY_CAPACITY
			or not CityCitizenInventorySystem.get_city_citizen_inventory(
				citizen_id
			).is_empty()
			or CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(
				citizen_id
			) != 0
			or CitizenNeedsSystem.get_city_citizen_hunger(citizen_id)
			!= CityCitizens.DEFAULT_CITIZEN_HUNGER
			or CitizenNeedsSystem.get_city_citizen_happiness(citizen_id)
			!= CityCitizens.DEFAULT_CITIZEN_HAPPINESS
			or int(citizen.get("hunger_decay_remainder", -1)) != 0
		):
			complete_records = false

	_expect(
		WorldData.has_player_city()
		and registry_array.size() == CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		and registry_version_before == CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		and complete_records,
		"Founding must create eight complete default inventory, cargo, and need records."
	)

	var inventory_migrated := (
		CityCitizenInventorySystem.ensure_city_citizen_inventory_state()
	)
	var needs_migrated := CitizenNeedsSystem.ensure_city_citizen_need_state()

	_expect(
		inventory_migrated == 0
		and needs_migrated == 0
		and registry_state.citizen_version == registry_version_before
		and is_same(registry_state.citizens, registry_array),
		"Clean founding records must make both ensure paths idempotent without publication."
	)


func _test_lossless_legacy_repair_and_identity() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Legacy Inventory Needs Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Legacy Inventory Needs Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var city := _create_city(
		"Legacy Inventory Needs City",
		int(polity.get("id", -1)),
		Vector2i(3, 3)
	)

	_expect(
		not city.is_empty()
		and WorldPoliticalState.set_active_settlement(int(city.get("id", -1))),
		"Legacy repair must run inside an instance-owned City."
	)

	if city.is_empty():
		return

	WorldPoliticalState.set_current_city_world(_make_world(16, 16, 98_903))
	WorldPoliticalState.set_current_city_seed(98_903)
	var created := CityCitizenRegistrySystem.add_city_citizen(
		"",
		Vector2i(5, 5),
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	var citizen_id := int(created.get("id", -1))

	_expect(citizen_id == 1, "Legacy repair must create local citizen ID 1.")

	if citizen_id <= 0:
		return

	var registry_state := CityCitizenRegistrySystem.get_current_state()
	var citizen: Dictionary = registry_state.citizens[0]
	var record_identity: Dictionary = citizen
	var current_task_identity: Dictionary = citizen.get("current_task", {})
	var current_haul_identity: Dictionary = citizen.get("current_haul", {})
	var movement_path_identity: Array = citizen.get("movement_path", [])
	var inventory_identity: Dictionary = {
		CityResourceCatalog.RESOURCE_FISH: 8,
	}

	citizen.erase("carry_capacity")
	citizen["inventory"] = inventory_identity
	citizen["haul_cargo"] = {
		"resource_type": CityResourceCatalog.RESOURCE_STONE,
		"amount": 5,
	}
	citizen["hunger"] = 150
	citizen["hunger_decay_remainder"] = 99_999
	citizen["happiness"] = -20
	registry_state.citizens[0] = citizen

	var version_before_repair := registry_state.citizen_version
	var inventory_migrated := (
		CityCitizenInventorySystem.ensure_city_citizen_inventory_state()
	)
	var version_after_inventory := registry_state.citizen_version
	var repaired_after_inventory: Dictionary = registry_state.citizens[0]
	var repaired_cargo_identity: Dictionary = repaired_after_inventory.get(
		"haul_cargo",
		{}
	)

	_expect(
		inventory_migrated == 1
		and version_after_inventory == version_before_repair + 1
		and is_same(repaired_after_inventory, record_identity)
		and is_same(
			repaired_after_inventory.get("current_task", {}),
			current_task_identity
		)
		and is_same(
			repaired_after_inventory.get("current_haul", {}),
			current_haul_identity
		)
		and is_same(
			repaired_after_inventory.get("movement_path", []),
			movement_path_identity
		)
		and is_same(
			repaired_after_inventory.get("inventory", {}),
			inventory_identity
		),
		"Inventory repair must publish once while preserving the citizen and unrelated nested identities."
	)
	_expect(
		CityCitizenInventorySystem.get_city_citizen_carry_capacity(citizen_id)
		== 13
		and CityCitizenInventorySystem.get_city_citizen_inventory_resource_amount(
			citizen_id,
			CityResourceCatalog.RESOURCE_FISH
		) == 8
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			CityResourceCatalog.RESOURCE_STONE
		) == 5
		and CityCitizenInventorySystem.get_city_citizen_total_carried_amount(
			citizen_id
		) == 13,
		"Supported legacy normalization must preserve every physical unit and expand missing capacity losslessly."
	)

	var needs_migrated := CitizenNeedsSystem.ensure_city_citizen_need_state()
	var repaired_after_needs: Dictionary = registry_state.citizens[0]

	_expect(
		needs_migrated == 1
		and registry_state.citizen_version == version_after_inventory + 1
		and CitizenNeedsSystem.get_city_citizen_hunger(citizen_id)
		== CityCitizens.MAX_CITIZEN_HUNGER
		and int(repaired_after_needs.get("hunger_decay_remainder", -1))
		== CityCitizens.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES - 1
		and CitizenNeedsSystem.get_city_citizen_happiness(citizen_id) == 0,
		"Need repair must clamp all malformed scalar fields and publish exactly once."
	)
	_expect(
		is_same(repaired_after_needs, record_identity)
		and is_same(
			repaired_after_needs.get("current_task", {}),
			current_task_identity
		)
		and is_same(
			repaired_after_needs.get("current_haul", {}),
			current_haul_identity
		)
		and is_same(
			repaired_after_needs.get("movement_path", []),
			movement_path_identity
		)
		and is_same(
			repaired_after_needs.get("inventory", {}),
			inventory_identity
		)
		and is_same(
			repaired_after_needs.get("haul_cargo", {}),
			repaired_cargo_identity
		),
		"Need repair must preserve all unrelated nested inventory, cargo, task, and movement identities."
	)

	var version_before_repeat := registry_state.citizen_version
	_expect(
		CityCitizenInventorySystem.ensure_city_citizen_inventory_state() == 0
		and CitizenNeedsSystem.ensure_city_citizen_need_state() == 0
		and registry_state.citizen_version == version_before_repeat
		and CityCitizenInventorySystem.get_city_citizen_total_carried_amount(
			citizen_id
		) == 13,
		"Repeated clean ensures must be no-ops and retain every physical resource."
	)


func _test_headless_simulation_bootstrap_and_canonical_setters() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Headless Inventory Needs Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Headless Inventory Needs Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city(
		"Headless Inventory Needs City A",
		polity_id,
		Vector2i(4, 4)
	)
	var city_a_id := int(city_a.get("id", -1))

	_expect(
		city_a_id > 0
		and WorldPoliticalState.set_active_settlement(city_a_id),
		"Headless bootstrap must create and activate an instance-owned City."
	)

	if city_a_id <= 0:
		return

	WorldPoliticalState.set_current_city_world(_make_world(16, 16, 98_904))
	WorldPoliticalState.set_current_city_seed(98_904)
	validator_city_id = city_a_id
	validator_city_state = WorldPoliticalState.get_city_simulation_state(city_a_id)
	validator_settlement_context = (
		WorldPoliticalState.get_settlement_context(city_a_id)
	)
	var created := CityCitizenRegistrySystem.add_city_citizen(
		"",
		Vector2i(5, 5),
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	var citizen_id := int(created.get("id", -1))
	var registry_state := CityCitizenRegistrySystem.get_current_state()
	var citizen: Dictionary = registry_state.citizens[0]
	var record_identity: Dictionary = citizen

	for field in [
		"carry_capacity",
		"inventory",
		"haul_cargo",
		"hunger",
		"hunger_decay_remainder",
		"happiness",
	]:
		citizen.erase(field)

	registry_state.citizens[0] = citizen
	var version_before_adoption := registry_state.citizen_version

	var settlement_context := SettlementSimulationContext.new({
		"settlement_id": city_a_id,
		"polity_id": polity_id,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
		"local_state": WorldPoliticalState.get_city_simulation_state(city_a_id),
	})
	SimulationCoordinator.run_settlement_simulation_systems(
		settlement_context,
		1,
		1
	)

	registry_state = CityCitizenRegistrySystem.get_current_state()
	var adopted: Dictionary = registry_state.citizens[0]
	_expect(
		is_same(adopted, record_identity)
		and registry_state.citizen_version == version_before_adoption + 2
		and CityCitizenInventorySystem.get_city_citizen_carry_capacity(citizen_id)
		== CityCitizens.DEFAULT_CITIZEN_CARRY_CAPACITY
		and CityCitizenInventorySystem.get_city_citizen_inventory(citizen_id).is_empty()
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id)
		== 0
		and CitizenNeedsSystem.get_city_citizen_hunger(citizen_id)
		== CityCitizens.DEFAULT_CITIZEN_HUNGER
		and int(adopted.get("hunger_decay_remainder", -1)) == 0
		and CitizenNeedsSystem.get_city_citizen_happiness(citizen_id)
		== CityCitizens.DEFAULT_CITIZEN_HAPPINESS,
		"Renderer-free simulation bootstrap must repair both embedded owners in place and publish once per owner."
	)

	for field in [
		"carry_capacity",
		"inventory",
		"haul_cargo",
		"hunger",
		"hunger_decay_remainder",
		"happiness",
	]:
		adopted.erase(field)

	registry_state.citizens[0] = adopted
	var version_before_setters := registry_state.citizen_version
	_expect(
		CityCitizenInventorySystem.set_city_citizen_carry_capacity(
			citizen_id,
			CityCitizens.DEFAULT_CITIZEN_CARRY_CAPACITY
		)
		and CityCitizenInventorySystem.set_city_citizen_inventory_resource_amount(
			citizen_id,
			CityResourceCatalog.RESOURCE_FISH,
			0
		) == 0
		and CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources(
			citizen_id,
			{}
		) == 0
		and CitizenNeedsSystem.set_city_citizen_hunger_state(
			citizen_id,
			CityCitizens.DEFAULT_CITIZEN_HUNGER,
			0
		)
		and CitizenNeedsSystem.set_city_citizen_happiness(
			citizen_id,
			CityCitizens.DEFAULT_CITIZEN_HAPPINESS
		)
		and registry_state.citizen_version == version_before_setters + 5,
		"Default-valued setters must materialize missing canonical fields and publish each real repair."
	)



func _test_malformed_carried_state_quarantine() -> void:
	var registry_state := CityCitizenRegistrySystem.get_current_state()

	if registry_state.citizens.is_empty():
		_expect(false, "Malformed-state coverage requires the headless citizen fixture.")
		return

	var adopted: Dictionary = registry_state.citizens[0]
	var citizen_id := int(adopted.get("id", -1))
	adopted["inventory"] = "opaque legacy inventory"
	adopted["haul_cargo"] = 17
	registry_state.citizens[0] = adopted
	var version_before_ambiguous_ensure := registry_state.citizen_version
	var ambiguous_migration_count := (
		CityCitizenInventorySystem.ensure_city_citizen_inventory_state()
	)
	var capacity_mutation_succeeded := (
		CityCitizenInventorySystem.set_city_citizen_carry_capacity(
			citizen_id,
			20
		)
	)
	var inventory_mutation_result := (
		CityCitizenInventorySystem.set_city_citizen_inventory_resource_amount(
			citizen_id,
			CityResourceCatalog.RESOURCE_FISH,
			1
		)
	)
	var cargo_mutation_result := (
		CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources(
			citizen_id,
			{CityResourceCatalog.RESOURCE_STONE: 1}
		)
	)
	var pile_result := (
		CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
			"tile_position": Vector2i(5, 5),
			"resource": CityResourceCatalog.RESOURCE_FISH,
			"amount_delta": 1,
		})
	)
	var placements: Array = pile_result.get("placements", [])
	var ground_pile_id := -1

	if not placements.is_empty() and placements[0] is Dictionary:
		ground_pile_id = int(placements[0].get("ground_pile_id", -1))

	var food_endpoint := (
		CityLogisticsSystem.make_city_ground_pile_haul_endpoint(ground_pile_id)
	)
	var logistics_state := CityLogisticsSystem.get_current_state()
	var ground_piles_before_transfer := (
		CityLogisticsSystem.get_city_ground_pile_snapshot()
	)
	var ground_pile_version_before_transfer := (
		logistics_state.ground_pile_version
	)
	var next_ground_pile_id_before_transfer := (
		logistics_state.next_ground_pile_id
	)
	var citizen_version_before_transfer := registry_state.citizen_version
	var endpoint_was_reachable := (
		CitizenNeedsSystem.city_citizen_can_withdraw_food_from_endpoint(
			citizen_id,
			food_endpoint,
			CityResourceCatalog.RESOURCE_FISH
		)
		and CitizenNeedsSystem.get_city_citizen_food_endpoint_target_tiles(
			citizen_id,
			food_endpoint
		).has(Vector2i(5, 5))
		and CitizenNeedsSystem.get_city_food_endpoint_unreserved_amount(
			citizen_id,
			food_endpoint,
			CityResourceCatalog.RESOURCE_FISH
		) == 1
	)
	var rejected_transfer_amount := (
		CitizenNeedsSystem.transfer_city_food_endpoint_to_citizen_inventory(
			citizen_id,
			food_endpoint,
			CityResourceCatalog.RESOURCE_FISH,
			1
		)
	)
	_expect(
		ambiguous_migration_count == 0
		and not capacity_mutation_succeeded
		and inventory_mutation_result == 0
		and cargo_mutation_result == 0
		and CityCitizenInventorySystem.get_city_citizen_personal_inventory_free_space(
			citizen_id
		) == 0
		and CityCitizenInventorySystem.get_city_citizen_inventory_free_space(
			citizen_id
		) == 0
		and CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(
			citizen_id
		) == 0
		and endpoint_was_reachable
		and rejected_transfer_amount == 0
		and registry_state.citizen_version == version_before_ambiguous_ensure
		and registry_state.citizen_version == citizen_version_before_transfer
		and logistics_state.ground_pile_version
		== ground_pile_version_before_transfer
		and logistics_state.next_ground_pile_id
		== next_ground_pile_id_before_transfer
		and CityLogisticsSystem.get_city_ground_pile_snapshot()
		== ground_piles_before_transfer
		and registry_state.citizens[0].get("inventory")
		== "opaque legacy inventory"
		and registry_state.citizens[0].get("haul_cargo") == 17,
		"Opaque carried state must reject mutation and reachable food transfer without publishing or touching its source."
	)

	adopted = registry_state.citizens[0]
	var malformed_capacity := {"opaque": 20}
	var valid_inventory := {CityResourceCatalog.RESOURCE_FISH: 2}
	var malformed_cargo := {
		"resource_type": CityResourceCatalog.RESOURCE_STONE,
		"amount": {"opaque": 5},
		"resources": {
			CityResourceCatalog.RESOURCE_STONE: {"opaque": 5},
		},
	}
	adopted["carry_capacity"] = malformed_capacity
	adopted["inventory"] = valid_inventory
	adopted["haul_cargo"] = malformed_cargo
	registry_state.citizens[0] = adopted
	var version_before_nested_malformed_reads := registry_state.citizen_version
	var nested_migration_count := (
		CityCitizenInventorySystem.ensure_city_citizen_inventory_state()
	)
	var nested_capacity_result := (
		CityCitizenInventorySystem.set_city_citizen_carry_capacity(
			citizen_id,
			20
		)
	)
	var nested_inventory_result := (
		CityCitizenInventorySystem.set_city_citizen_inventory_resource_amount(
			citizen_id,
			CityResourceCatalog.RESOURCE_FISH,
			1
		)
	)
	var nested_cargo_result := (
		CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources(
			citizen_id,
			{CityResourceCatalog.RESOURCE_STONE: 1}
		)
	)
	_expect(
		nested_migration_count == 0
		and not nested_capacity_result
		and nested_inventory_result == 2
		and nested_cargo_result == 0
		and CityCitizenInventorySystem.get_city_citizen_carry_capacity(
			citizen_id
		) == 0
		and CityCitizenInventorySystem.get_city_citizen_total_carried_amount(
			citizen_id
		) == 2
		and CityCitizenInventorySystem.get_city_citizen_inventory_free_space(
			citizen_id
		) == 0
		and registry_state.citizen_version
		== version_before_nested_malformed_reads
		and is_same(
			registry_state.citizens[0].get("carry_capacity"),
			malformed_capacity
		)
		and is_same(
			registry_state.citizens[0].get("inventory"),
			valid_inventory
		)
		and is_same(
			registry_state.citizens[0].get("haul_cargo"),
			malformed_cargo
		),
		"Nested malformed cargo and capacity must remain quarantined through ensure, reads, and mutation attempts."
	)


func _test_validator_rejects_uninterpretable_embedded_state() -> void:
	var validation_target := _get_explicit_validation_target()
	var registry_state := validator_city_state.citizen_registry_state

	if registry_state.citizens.is_empty():
		_expect(false, "Validator coverage requires the headless citizen fixture.")
		return

	var citizen: Dictionary = registry_state.citizens[0]
	var citizen_id := int(citizen.get("id", -1))
	var citizen_lookup := {citizen_id: 0}
	citizen["carry_capacity"] = "opaque capacity"
	citizen["inventory"] = {}
	citizen["haul_cargo"] = {
		"resource_type": CityResourceCatalog.RESOURCE_STONE,
		"amount": "opaque amount",
		"resources": {
			CityResourceCatalog.RESOURCE_STONE: {"opaque": 5},
		},
	}
	registry_state.citizens[0] = citizen
	var carrying_errors: Array[String] = []
	var carrying_warnings: Array[String] = []
	CityObjectStateValidatorScript._validate_citizen_inventories(
		validation_target,
		carrying_errors,
		carrying_warnings,
		citizen_lookup
	)
	_expect(
		_errors_contain(carrying_errors, "non-integer carry capacity")
		and _errors_contain(carrying_errors, "non-integer haul cargo amount")
		and _errors_contain(carrying_errors, "invalid haul cargo entry"),
		"Validator must diagnose malformed capacity and nested cargo values."
	)

	citizen["carry_capacity"] = CityCitizens.DEFAULT_CITIZEN_CARRY_CAPACITY
	citizen["inventory"] = "opaque inventory"
	citizen["haul_cargo"] = CityCitizens.make_city_citizen_haul_cargo()
	registry_state.citizens[0] = citizen
	var inventory_errors: Array[String] = []
	var inventory_warnings: Array[String] = []
	CityObjectStateValidatorScript._validate_citizen_inventories(
		validation_target,
		inventory_errors,
		inventory_warnings,
		citizen_lookup
	)
	_expect(
		_errors_contain(inventory_errors, "non-Dictionary inventory"),
		"Validator must reject opaque personal inventory."
	)

	citizen["inventory"] = {}
	citizen["hunger"] = CityCitizens.MAX_CITIZEN_HUNGER + 1
	citizen["hunger_decay_remainder"] = (
		CityCitizens.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES
	)
	citizen["happiness"] = -1
	registry_state.citizens[0] = citizen
	var need_errors: Array[String] = []
	CityCitizenStateValidatorScript._validate_city_citizen_need_state(
		validation_target,
		need_errors,
		citizen_lookup
	)
	_expect(
		_errors_contain(need_errors, "out-of-range hunger state")
		and _errors_contain(need_errors, "invalid hunger-decay remainder")
		and _errors_contain(need_errors, "out-of-range happiness state"),
		"Validator must reject every out-of-range scalar need field."
	)

	citizen.erase("hunger")
	registry_state.citizens[0] = citizen
	var incomplete_need_errors: Array[String] = []
	CityCitizenStateValidatorScript._validate_city_citizen_need_state(
		validation_target,
		incomplete_need_errors,
		citizen_lookup
	)
	_expect(
		_errors_contain(incomplete_need_errors, "incomplete need state"),
		"Validator must reject missing scalar need fields."
	)


func _get_explicit_validation_target() -> Dictionary:
	return {
		"settlement_context": validator_settlement_context,
		"settlement_id": validator_city_id,
		"city_state": validator_city_state,
	}


func _lock_founding_world(world: WorldData, label: String) -> bool:
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(1, 1),
		"region_center": Vector2i(2, 2),
		"region_size": 3,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": TEST_CITY_NAME + " " + label,
		"culture_name": TEST_CULTURE_NAME + " " + label,
	})
	_expect(locked, label + " fixture must lock its founding world.")
	return locked


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


func _errors_contain(errors: Array[String], fragment: String) -> bool:
	for error in errors:
		if error.contains(fragment):
			return true

	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City citizen inventory/needs bootstrap test: " + message)
