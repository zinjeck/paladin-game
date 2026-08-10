extends Node

const SHARED_TILE := Vector2i(5, 5)

var failure_count: int = 0


func _ready() -> void:
	_test_equal_version_city_isolation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen inventory/needs isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen inventory/needs isolation test passed.")
	get_tree().quit(0)


func _test_equal_version_city_isolation() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Inventory Needs Isolation Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Inventory Needs Isolation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city(
		"Inventory Needs City A",
		polity_id,
		Vector2i(1, 1)
	)
	var city_b := _create_city(
		"Inventory Needs City B",
		polity_id,
		Vector2i(8, 8)
	)

	_expect(
		not city_a.is_empty() and not city_b.is_empty(),
		"The isolation fixture must create two instance-owned Cities."
	)

	if city_a.is_empty() or city_b.is_empty():
		return

	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))
	var state_a := _exercise_city({
		"city_id": city_a_id,
		"culture_id": culture_id,
		"world_seed": 98_911,
		"sex": CityCitizens.CITY_CITIZEN_SEX_MALE,
		"inventory_resource": CityResourceCatalog.RESOURCE_FISH,
		"cargo_resource": CityResourceCatalog.RESOURCE_STONE,
		"carry_capacity": 11,
		"hunger": 60,
		"hunger_remainder": 7,
		"happiness": 40,
	})
	var state_b := _exercise_city({
		"city_id": city_b_id,
		"culture_id": culture_id,
		"world_seed": 98_912,
		"sex": CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		"inventory_resource": CityResourceCatalog.RESOURCE_MEAT,
		"cargo_resource": CityResourceCatalog.RESOURCE_LUMBER,
		"carry_capacity": 12,
		"hunger": 45,
		"hunger_remainder": 11,
		"happiness": 55,
	})

	if state_a.is_empty() or state_b.is_empty():
		return

	_expect(
		int(state_a.get("citizen_id", -1)) == 1
		and int(state_b.get("citizen_id", -1)) == 1
		and int(state_a.get("version", -1))
		== int(state_b.get("version", -2)),
		"Both Cities must independently reuse citizen ID 1 and equal versions."
	)
	_expect(
		not is_same(state_a.get("registry_state"), state_b.get("registry_state"))
		and not is_same(
			state_a.get("citizens_array"),
			state_b.get("citizens_array")
		)
		and not is_same(
			state_a.get("citizen_record"),
			state_b.get("citizen_record")
		)
		and not is_same(
			state_a.get("inventory_identity"),
			state_b.get("inventory_identity")
		)
		and not is_same(
			state_a.get("cargo_identity"),
			state_b.get("cargo_identity")
		),
		"Equal local IDs and versions must not alias registry, record, inventory, or cargo state."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and _active_city_matches(state_a),
		"B -> A must restore City A's exact inventory, cargo, and needs."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and _active_city_matches(state_b),
		"A -> B must restore City B's exact inventory, cargo, and needs."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and _active_city_matches(state_a),
		"A -> B -> A must preserve City A despite equal IDs and versions."
	)


func _exercise_city(values: Dictionary) -> Dictionary:
	var city_id := int(values.get("city_id", -1))
	var culture_id := int(values.get("culture_id", -1))
	var world_seed := int(values.get("world_seed", 0))
	var inventory_resource := str(values.get("inventory_resource", ""))
	var cargo_resource := str(values.get("cargo_resource", ""))
	var carry_capacity := int(values.get("carry_capacity", 0))
	var hunger := int(values.get("hunger", 0))
	var hunger_remainder := int(values.get("hunger_remainder", 0))
	var happiness := int(values.get("happiness", 0))

	_expect(
		WorldPoliticalState.set_active_settlement(city_id),
		"The City under test must become active."
	)

	if WorldPoliticalState.active_settlement_id != city_id:
		return {}

	WorldData.official_city_world = _make_world(16, 16, world_seed)
	WorldData.official_city_seed = world_seed
	var citizen := WorldData.add_city_citizen(
		"",
		SHARED_TILE,
		str(values.get("sex", "")),
		culture_id
	)
	var citizen_id := int(citizen.get("id", -1))

	_expect(citizen_id == 1, "Each City must begin with local citizen ID 1.")

	if citizen_id <= 0:
		return {}

	var registry_state := CityCitizenRegistrySystem.get_current_state()
	var version_after_creation := registry_state.citizen_version

	_expect(
		CityCitizenInventorySystem.set_city_citizen_carry_capacity(
			citizen_id,
			carry_capacity
		)
		and CityCitizenInventorySystem.set_city_citizen_inventory_resource_amount(
			citizen_id,
			inventory_resource,
			2
		) == 2
		and CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources(
			citizen_id,
			{cargo_resource: 3}
		) == 3
		and CitizenNeedsSystem.set_city_citizen_hunger_state(
			citizen_id,
			hunger,
			hunger_remainder
		)
		and CitizenNeedsSystem.set_city_citizen_happiness(
			citizen_id,
			happiness
		),
		"Each City must accept independent capacity, inventory, cargo, hunger, and happiness mutations."
	)
	_expect(
		registry_state.citizen_version == version_after_creation + 5,
		"Five real record mutations must publish exactly five citizen versions."
	)

	var version_before_clipping := registry_state.citizen_version
	var clipped_inventory_amount := (
		CityCitizenInventorySystem.set_city_citizen_inventory_resource_amount(
			citizen_id,
			inventory_resource,
			99
		)
	)

	_expect(
		clipped_inventory_amount == carry_capacity - 3
		and CityCitizenInventorySystem.get_city_citizen_total_carried_amount(
			citizen_id
		) == carry_capacity
		and CityCitizenInventorySystem.get_city_citizen_inventory_free_space(
			citizen_id
		) == 0
		and registry_state.citizen_version == version_before_clipping + 1,
		"Personal inventory must clip against the three-unit cargo share and publish once."
	)

	var version_before_no_ops := registry_state.citizen_version
	var no_op_cargo := {cargo_resource: 3}

	_expect(
		CityCitizenInventorySystem.set_city_citizen_inventory_resource_amount(
			citizen_id,
			inventory_resource,
			carry_capacity - 3
		) == carry_capacity - 3
		and CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources(
			citizen_id,
			no_op_cargo
		) == 3
		and CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources(
			citizen_id,
			{"not_a_city_resource": 3}
		) == 3
		and CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources(
			citizen_id,
			{cargo_resource: "3"}
		) == 3
		and CitizenNeedsSystem.set_city_citizen_hunger_state(
			citizen_id,
			hunger,
			hunger_remainder
		)
		and CitizenNeedsSystem.set_city_citizen_happiness(
			citizen_id,
			happiness
		)
		and CityCitizenInventorySystem.set_city_citizen_carry_capacity(
			citizen_id,
			carry_capacity
		)
		and not CityCitizenInventorySystem.set_city_citizen_carry_capacity(
			citizen_id,
			carry_capacity - 1
		)
		and registry_state.citizen_version == version_before_no_ops,
		"Idempotent writes and invalid or over-capacity replacements must not publish."
	)

	var inventory_copy := (
		CityCitizenInventorySystem.get_city_citizen_inventory(citizen_id)
	)
	var cargo_copy := CityCitizenInventorySystem.get_city_citizen_haul_cargo(
		citizen_id
	)
	var cargo_resources_copy: Dictionary = cargo_copy.get("resources", {})
	inventory_copy[inventory_resource] = 999
	cargo_resources_copy[cargo_resource] = 999
	cargo_copy["amount"] = 999

	_expect(
		CityCitizenInventorySystem.get_city_citizen_inventory_resource_amount(
			citizen_id,
			inventory_resource
		) == carry_capacity - 3
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			cargo_resource
		) == 3
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(
			citizen_id
		) == 3,
		"Inventory and cargo query results must be non-aliasing copies."
	)

	var authoritative_record: Dictionary = registry_state.citizens[0]
	return {
		"citizen_id": citizen_id,
		"registry_state": registry_state,
		"citizens_array": registry_state.citizens,
		"citizen_record": authoritative_record,
		"inventory_identity": authoritative_record.get("inventory", {}),
		"cargo_identity": authoritative_record.get("haul_cargo", {}),
		"version": registry_state.citizen_version,
		"inventory_resource": inventory_resource,
		"cargo_resource": cargo_resource,
		"hunger": hunger,
		"hunger_remainder": hunger_remainder,
		"happiness": happiness,
		"carry_capacity": carry_capacity,
	}


func _active_city_matches(expected: Dictionary) -> bool:
	var citizen_id := int(expected.get("citizen_id", -1))
	var inventory_resource := str(expected.get("inventory_resource", ""))
	var cargo_resource := str(expected.get("cargo_resource", ""))
	var carry_capacity := int(expected.get("carry_capacity", 0))
	var registry_state := CityCitizenRegistrySystem.get_current_state()

	return (
		is_same(registry_state, expected.get("registry_state"))
		and is_same(registry_state.citizens, expected.get("citizens_array"))
		and is_same(registry_state.citizens[0], expected.get("citizen_record"))
		and is_same(
			registry_state.citizens[0].get("inventory", {}),
			expected.get("inventory_identity")
		)
		and is_same(
			registry_state.citizens[0].get("haul_cargo", {}),
			expected.get("cargo_identity")
		)
		and registry_state.citizen_version == int(expected.get("version", -1))
		and CityCitizenInventorySystem.get_city_citizen_inventory_resource_amount(
			citizen_id,
			inventory_resource
		) == carry_capacity - 3
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			cargo_resource
		) == 3
		and CityCitizenInventorySystem.get_city_citizen_total_carried_amount(
			citizen_id
		) == carry_capacity
		and CityCitizenInventorySystem.get_city_citizen_carry_capacity(citizen_id)
		== carry_capacity
		and CitizenNeedsSystem.get_city_citizen_hunger(citizen_id)
		== int(expected.get("hunger", -1))
		and int(registry_state.citizens[0].get("hunger_decay_remainder", -1))
		== int(expected.get("hunger_remainder", -1))
		and CitizenNeedsSystem.get_city_citizen_happiness(citizen_id)
		== int(expected.get("happiness", -1))
	)


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
	push_error("City citizen inventory/needs isolation test: " + message)
