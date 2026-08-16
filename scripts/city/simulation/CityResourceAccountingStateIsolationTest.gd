extends Node

const SHARED_STOCKPILE_TOP_LEFT := Vector2i(4, 4)
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_equal_version_city_isolation()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City resource-accounting isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City resource-accounting isolation test passed.")
	get_tree().quit(0)


func _test_equal_version_city_isolation() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Accounting Isolation Culture")
	var polity := WorldPoliticalState.create_polity({
		"name": "Accounting Isolation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": int(culture.get("id", -1)),
	})
	var city_a := _create_city(
		"Accounting City A",
		int(polity.get("id", -1)),
		Vector2i(1, 1)
	)
	var city_b := _create_city(
		"Accounting City B",
		int(polity.get("id", -1)),
		Vector2i(8, 8)
	)
	_expect(
		not city_a.is_empty() and not city_b.is_empty(),
		"Fixture must create two instance-owned Cities."
	)
	if city_a.is_empty() or city_b.is_empty():
		return

	var city_a_id := int(city_a["id"])
	var city_b_id := int(city_b["id"])
	var culture_id := int(culture.get("id", -1))
	var city_a_state = WorldPoliticalState.get_city_simulation_state(city_a_id)
	var city_b_state = WorldPoliticalState.get_city_simulation_state(city_b_id)
	_seed_city_runtime_data(
		city_a_state,
		city_a_id,
		"Accounting City A",
		culture_id
	)
	_seed_city_runtime_data(
		city_b_state,
		city_b_id,
		"Accounting City B",
		culture_id
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id),
		"City A must become active."
	)
	var world_a := _make_world(24, 20, 95_101)
	WorldPoliticalState.set_current_city_world(world_a)
	WorldPoliticalState.set_current_city_seed(95_101)
	var keep_a := _register_keep(world_a)
	_mark_city_founded(city_a_state, keep_a)
	var stockpile_a := _register_stockpile(world_a)
	var stockpile_a_id := int(stockpile_a.get("id", -1))
	_expect(
		stockpile_a_id == 2
		and CityResourceContainerSystem.add_resource_to_city_object_storage(
			stockpile_a_id,
			WorldData.RESOURCE_FISH,
			7
		) == 7,
		"City A must create local Stockpile 2 with seven fish."
	)
	var city_a_total := CityResourceAccountingSystem.get_total_owned_city_resource_amount(
		WorldData.RESOURCE_FISH
	)
	var state_a := (
		CityResourceAccountingSystem.get_current_state()
	)
	var cache_a: Dictionary = state_a.owned_resource_amount_cache
	var state_a_container_version := state_a.container_version
	var state_a_public_version := state_a.public_storage_version
	var state_a_cache_version := (
		state_a.owned_resource_amount_cache_container_version
	)

	_expect(
		city_a_total == 7
		and state_a_container_version == 3
		and state_a_public_version == 3
		and state_a_cache_version == state_a_container_version
		and int(cache_a.get(WorldData.RESOURCE_FISH, 0)) == 7,
		"City A accounting must cache its physical Stockpile total."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"City B must become active."
	)
	var world_b := _make_world(24, 20, 95_202)
	WorldPoliticalState.set_current_city_world(world_b)
	WorldPoliticalState.set_current_city_seed(95_202)
	var keep_b := _register_keep(world_b)
	_mark_city_founded(city_b_state, keep_b)
	var stockpile_b := _register_stockpile(world_b)
	var stockpile_b_id := int(stockpile_b.get("id", -1))
	_expect(
		stockpile_b_id == 2
		and CityResourceContainerSystem.add_resource_to_city_object_storage(
			stockpile_b_id,
			WorldData.RESOURCE_FISH,
			31
		) == 31,
		"City B must independently create local Stockpile 2 with 31 fish."
	)
	var city_b_total := CityResourceAccountingSystem.get_total_owned_city_resource_amount(
		WorldData.RESOURCE_FISH
	)
	var state_b := (
		CityResourceAccountingSystem.get_current_state()
	)
	var cache_b: Dictionary = state_b.owned_resource_amount_cache

	_expect(
		city_b_total == 31
		and state_b.container_version == state_a_container_version
		and state_b.public_storage_version == state_a_public_version
		and state_b.owned_resource_amount_cache_container_version
		== state_b.container_version,
		"The two Cities must deliberately reach equal numeric accounting versions."
	)
	_expect(
		not is_same(state_b, state_a)
		and not is_same(cache_b, cache_a)
		and int(cache_b.get(WorldData.RESOURCE_FISH, 0)) == 31
		and int(cache_a.get(WorldData.RESOURCE_FISH, 0)) == 7
		and state_a.container_version == state_a_container_version
		and state_a.public_storage_version == state_a_public_version
		and state_a.owned_resource_amount_cache_container_version
		== state_a_cache_version,
		"City B mutations must not touch City A accounting state or cache identity."
	)
	_expect(
		stockpile_a_id == stockpile_b_id
		and stockpile_a.get("top_left") == SHARED_STOCKPILE_TOP_LEFT
		and stockpile_b.get("top_left") == SHARED_STOCKPILE_TOP_LEFT,
		"Separate Cities may reuse the same local object ID and coordinates."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and is_same(
			CityResourceAccountingSystem.get_current_state(),
			state_a
		)
		and is_same(CityResourceAccountingSystem.get_current_state().owned_resource_amount_cache, cache_a)
		and CityResourceAccountingSystem.get_total_owned_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 7,
		"A -> B -> A must restore City A's exact accounting owner and total."
	)

	var renderer := _make_resource_renderer(city_a_id, state_a)
	var fish_index := renderer.get_city_resource_order().find(WorldData.RESOURCE_FISH)
	_expect(
		fish_index >= 0
		and renderer.resource_amount_labels[fish_index].text == "7",
		"The resource bar must initially render City A's owned fish total."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"Renderer fixture must switch back to City B."
	)
	var change_flags: Dictionary = {}
	renderer._collect_world_data_change_flags(change_flags)
	renderer._apply_city_change_refreshes(change_flags, false)
	_expect(
		bool(change_flags.get("city_containers_changed", false))
		and bool(change_flags.get("public_storage_changed", false))
		and is_same(
			renderer.observed_city_resource_accounting_state,
			state_b
		)
		and renderer.resource_amount_labels[fish_index].text == "31",
		"Equal versions must still refresh renderer accounting by state identity."
	)

	var fishery_b := CityObjectSystem.register_completed_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(12, 4),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		),
		"object_owner": "player",
		"city_world": world_b,
	})
	var fishery_b_id := int(fishery_b.get("id", -1))
	var fishery_registration_flags: Dictionary = {}
	renderer._collect_world_data_change_flags(
		fishery_registration_flags
	)
	renderer._apply_city_change_refreshes(
		fishery_registration_flags,
		false
	)
	_expect(
		fishery_b_id > 0
		and bool(
			fishery_registration_flags.get(
				"city_containers_changed",
				false
			)
		)
		and not bool(
			fishery_registration_flags.get(
				"public_storage_changed",
				false
			)
		)
		and is_same(
			renderer.observed_city_resource_accounting_state,
			state_b
		)
		and renderer.resource_amount_labels[fish_index].text == "31",
		"Registering empty private workplace storage must establish the same-city renderer baseline."
	)

	var container_before_fishery_mutation := state_b.container_version
	var public_before_fishery_mutation := state_b.public_storage_version
	_expect(
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			fishery_b_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1,
		"The same-city renderer fixture must produce one Fishery fish."
	)
	var fishery_change_flags: Dictionary = {}
	renderer._collect_world_data_change_flags(fishery_change_flags)
	renderer._apply_city_change_refreshes(fishery_change_flags, false)
	_expect(
		state_b.container_version == container_before_fishery_mutation + 1
		and state_b.public_storage_version == public_before_fishery_mutation
		and bool(
			fishery_change_flags.get(
				"city_containers_changed",
				false
			)
		)
		and not bool(
			fishery_change_flags.get(
				"public_storage_changed",
				false
			)
		)
		and is_same(
			renderer.observed_city_resource_accounting_state,
			state_b
		)
		and renderer.resource_amount_labels[fish_index].text == "32",
		"A Fishery mutation must refresh same-city owned UI through only the container version."
	)

	var container_before_stockpile_mutation := state_b.container_version
	var public_before_stockpile_mutation := state_b.public_storage_version
	_expect(
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			stockpile_b_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1,
		"The same-city renderer fixture must add one public Stockpile fish."
	)
	var stockpile_change_flags: Dictionary = {}
	renderer._collect_world_data_change_flags(stockpile_change_flags)
	renderer._apply_city_change_refreshes(stockpile_change_flags, false)
	_expect(
		state_b.container_version == container_before_stockpile_mutation + 1
		and state_b.public_storage_version == public_before_stockpile_mutation + 1
		and bool(
			stockpile_change_flags.get(
				"city_containers_changed",
				false
			)
		)
		and bool(
			stockpile_change_flags.get(
				"public_storage_changed",
				false
			)
		)
		and is_same(
			renderer.observed_city_resource_accounting_state,
			state_b
		)
		and renderer.resource_amount_labels[fish_index].text == "33",
		"A Stockpile mutation must refresh same-city owned UI through container and public versions."
	)
	cache_b = state_b.owned_resource_amount_cache
	_assert_validator_and_final_city_isolation({
		"renderer": renderer,
		"city_a_id": city_a_id,
		"city_b_id": city_b_id,
		"state_b": state_b,
		"cache_a": cache_a,
		"cache_b": cache_b,
		"state_a_cache_version": state_a_cache_version,
		"state_a_container_version": state_a_container_version,
		"state_a_public_version": state_a_public_version,
	})


func _make_resource_renderer(
	settlement_id: int,
	state: CityResourceAccountingState
) -> CityRenderer:
	var renderer := CityRenderer.new()
	var renderer_context = WorldPoliticalState.get_settlement_context(
		settlement_id
	)
	_expect(
		renderer.configure_initial_city_presentation(renderer_context),
		"Resource UI coverage requires an explicit renderer settlement binding."
	)
	renderer.observed_city_resource_accounting_state = state
	renderer.observed_city_container_version = state.container_version
	renderer.observed_city_public_storage_version = state.public_storage_version

	for _resource in renderer.get_city_resource_order():
		var amount_label := Label.new()
		renderer.add_child(amount_label)
		renderer.resource_amount_labels.append(amount_label)

	renderer.update_resource_bar_values()
	return renderer


func _assert_validator_and_final_city_isolation(
	values: Dictionary
) -> void:
	var renderer: CityRenderer = values["renderer"]
	var city_a_id: int = values["city_a_id"]
	var city_b_id: int = values["city_b_id"]
	var state_b: CityResourceAccountingState = values["state_b"]
	var cache_a: Dictionary = values["cache_a"]
	var cache_b: Dictionary = values["cache_b"]
	var state_a_cache_version: int = values["state_a_cache_version"]
	var state_a_container_version: int = values["state_a_container_version"]
	var state_a_public_version: int = values["state_a_public_version"]
	var first_validation := CityStateValidatorScript.validate(true, false)
	var replacement_state := CityResourceAccountingState.new()
	replacement_state.owned_resource_amount_cache = cache_b.duplicate(true)
	replacement_state.owned_resource_amount_cache_container_version = (
		state_b.owned_resource_amount_cache_container_version
	)
	replacement_state.container_version = state_b.container_version
	replacement_state.public_storage_version = state_b.public_storage_version
	var city_b_root = WorldPoliticalState.get_city_simulation_state(city_b_id)
	city_b_root.resource_accounting_state = replacement_state
	var second_validation := CityStateValidatorScript.validate(false, false)
	_expect(
		int(first_validation.get(
			"resource_accounting_state_instance_id",
			-1
		)) == int(state_b.get_instance_id())
		and int(second_validation.get(
			"resource_accounting_state_instance_id",
			-1
		)) == int(replacement_state.get_instance_id())
		and int(first_validation.get(
			"resource_accounting_state_instance_id",
			-1
		)) != int(second_validation.get(
			"resource_accounting_state_instance_id",
			-1
		)),
		"Validator caching must include accounting-state identity."
	)
	city_b_root.resource_accounting_state = state_b
	CityStateValidatorScript.validate(true, false)
	renderer.free()

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and is_same(
			CityResourceAccountingSystem.get_current_state().owned_resource_amount_cache,
			cache_a
		)
		and CityResourceAccountingSystem
		.get_current_state().owned_resource_amount_cache_container_version
		== state_a_cache_version
		and CityResourceAccountingSystem.get_city_container_version()
		== state_a_container_version
		and CityResourceAccountingSystem.get_city_public_storage_version()
		== state_a_public_version
		and CityResourceAccountingSystem.get_total_owned_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 7,
		"City A accounting must remain exact after rendering and validation checks."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and is_same(
			CityResourceAccountingSystem.get_current_state().owned_resource_amount_cache,
			cache_b
		)
		and CityResourceAccountingSystem.get_city_container_version()
		== state_b.container_version
		and CityResourceAccountingSystem.get_city_public_storage_version()
		== state_b.public_storage_version
		and CityResourceAccountingSystem.get_total_owned_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 33,
		"City B accounting must remain exact after the final A -> B switch."
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


func _register_stockpile(city_world: WorldData) -> Dictionary:
	return CityObjectSystem.register_completed_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_STOCKPILE,
		"top_left": SHARED_STOCKPILE_TOP_LEFT,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_STOCKPILE
		),
		"object_owner": "player",
		"city_world": city_world,
	})


func _register_keep(city_world: WorldData) -> Dictionary:
	return CityObjectSystem.register_completed_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		"top_left": Vector2i.ZERO,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		),
		"object_owner": "player",
		"city_world": city_world,
	})


func _seed_city_runtime_data(
	city_state: CitySettlementSimulationState,
	city_id: int,
	city_name: String,
	culture_id: int
) -> void:
	if city_state == null:
		return

	city_state.city_runtime_data.merge({
		"id": city_id,
		"name": city_name,
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}, true)


func _mark_city_founded(
	city_state: CitySettlementSimulationState,
	keep: Dictionary
) -> void:
	if city_state == null or city_state.city_world == null or keep.is_empty():
		return

	city_state.city_runtime_data.merge({
		"city_world_seed": city_state.city_seed,
		"city_map_size": Vector2i(
			city_state.city_world.width,
			city_state.city_world.height
		),
		"foundation_top_left": keep.get("top_left", Vector2i(-1, -1)),
		"foundation_size": keep.get("size", Vector2i.ZERO),
		"foundation_object_id": int(keep.get("id", -1)),
		"foundation_object_owner": str(keep.get("owner", "")),
		"founded": true,
		"can_build": true,
	}, true)


func _make_world(width: int, height: int, seed: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed)

	for y in range(height):
		for x in range(width):
			var tile := world.get_tile_for_internal_read(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["fertility"] = 50.0
			tile.erase("surface_feature")

	world.mark_tile_data_changed()
	return world


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City resource-accounting isolation test: " + message)
