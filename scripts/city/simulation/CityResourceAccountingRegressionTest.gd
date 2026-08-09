extends Node

const TEST_WORLD_SIZE := Vector2i(40, 30)

var failure_count: int = 0


func _ready() -> void:
	_test_container_accounting_and_cache_invalidation()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City resource-accounting regression test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City resource-accounting regression test passed.")
	get_tree().quit(0)


func _test_container_accounting_and_cache_invalidation() -> void:
	var city_world := _reset_fixture(96_101)
	var keep := _register_container(
		WorldData.CITY_OBJECT_CITY_CENTER,
		Vector2i(2, 2),
		city_world
	)
	var stockpile := _register_container(
		WorldData.CITY_OBJECT_STOCKPILE,
		Vector2i(8, 2),
		city_world
	)
	var house := _register_container(
		WorldData.CITY_OBJECT_HOUSE,
		Vector2i(13, 2),
		city_world
	)
	var fishery := _register_container(
		WorldData.CITY_OBJECT_FISHING_GROUNDS,
		Vector2i(19, 2),
		city_world
	)
	_expect(
		not keep.is_empty()
		and not stockpile.is_empty()
		and not house.is_empty()
		and not fishery.is_empty(),
		"Fixture must register all four current container types."
	)
	if (
		keep.is_empty()
		or stockpile.is_empty()
		or house.is_empty()
		or fishery.is_empty()
	):
		return

	var keep_id := int(keep["id"])
	var stockpile_id := int(stockpile["id"])
	var house_id := int(house["id"])
	var fishery_id := int(fishery["id"])
	_expect(
		WorldData.add_resource_to_city_object_storage(
			keep_id,
			WorldData.RESOURCE_FISH,
			3
		) == 3
		and WorldData.add_resource_to_city_object_storage(
			keep_id,
			WorldData.RESOURCE_LUMBER,
			17
		) == 17
		and WorldData.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_FISH,
			5
		) == 5
		and WorldData.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_STONE,
			25
		) == 25
		and WorldData.add_resource_to_city_object_storage(
			house_id,
			WorldData.RESOURCE_FISH,
			7
		) == 7
		and WorldData.add_resource_to_city_object_storage(
			house_id,
			WorldData.RESOURCE_MEAT,
			8
		) == 8
		and WorldData.add_resource_to_city_object_storage(
			fishery_id,
			WorldData.RESOURCE_FISH,
			11
		) == 11,
		"Each physical container must accept its accounting fixture resources."
	)

	keep = CityObjectSystem.get_city_object_by_id(keep_id)
	stockpile = CityObjectSystem.get_city_object_by_id(stockpile_id)
	house = CityObjectSystem.get_city_object_by_id(house_id)
	fishery = CityObjectSystem.get_city_object_by_id(fishery_id)
	_expect(
		WorldData.city_object_counts_as_public_city_storage(keep)
		and WorldData.city_object_counts_as_public_city_storage(stockpile)
		and not WorldData.city_object_counts_as_public_city_storage(house)
		and not WorldData.city_object_counts_as_public_city_storage(fishery)
		and WorldData.get_city_object_public_storage_tier(keep)
		== WorldData.PUBLIC_CITY_STORAGE_TIER_CITY_KEEP
		and WorldData.get_city_object_public_storage_tier(stockpile)
		== WorldData.PUBLIC_CITY_STORAGE_TIER_STOCKPILE
		and WorldData.get_city_object_public_storage_tier(house)
		== WorldData.PUBLIC_CITY_STORAGE_TIER_NONE
		and WorldData.get_city_object_public_storage_tier(fishery)
		== WorldData.PUBLIC_CITY_STORAGE_TIER_NONE,
		"Public/private container classification must remain unchanged."
	)
	_expect(
		WorldData.city_object_counts_toward_city_storage_totals(keep)
		and WorldData.city_object_counts_toward_city_storage_totals(stockpile)
		and not WorldData.city_object_counts_toward_city_storage_totals(house)
		and WorldData.city_object_counts_toward_city_storage_totals(fishery),
		"Owned totals must include public and workplace output, but not pantries."
	)

	var owned_totals := WorldData.get_total_owned_city_resource_amounts()
	var accounting_state := (
		WorldPoliticalState.get_current_city_resource_accounting_state()
	)
	_expect(
		WorldData.get_total_public_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 8
		and WorldData.get_total_stored_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 19
		and int(owned_totals.get(WorldData.RESOURCE_FISH, 0)) == 19
		and WorldData.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 26,
		"Public, owned/UI, and total physical fish must preserve distinct scopes."
	)
	_expect(
		is_same(
			WorldData.city_owned_resource_amount_cache,
			accounting_state.owned_resource_amount_cache
		)
		and is_same(
			owned_totals,
			accounting_state.owned_resource_amount_cache
		)
		and accounting_state.owned_resource_amount_cache_container_version
		== accounting_state.container_version,
		"The active state must own the exact valid aggregate cache."
	)

	_expect(
		WorldData.get_city_object_storage_used_capacity(keep) == 20
		and WorldData.get_city_object_storage_free_space(keep) == 30
		and WorldData.get_city_object_storage_used_capacity(stockpile) == 30
		and WorldData.get_city_object_storage_free_space(stockpile) == 170
		and WorldData.get_city_object_storage_used_capacity(house) == 15
		and WorldData.get_city_object_storage_free_space(house) == 35
		and WorldData.get_city_object_storage_used_capacity(fishery) == 11
		and WorldData.get_city_object_storage_free_space(fishery) == 39,
		"Used and free capacity must be derived from physical container contents."
	)
	_expect(
		WorldData.get_total_public_city_resource_storage_capacity(
			WorldData.RESOURCE_FISH
		) == 208
		and WorldData.get_total_city_resource_storage_capacity(
			WorldData.RESOURCE_FISH
		) == 258
		and WorldData.get_city_object_storage_capacity_for_resource(
			fishery,
			WorldData.RESOURCE_LUMBER
		) == 0,
		"Public and owned capacity must preserve policy and resource compatibility."
	)

	var renderer := CityRenderer.new()
	var resource_order := renderer.get_city_resource_order()
	for _resource in resource_order:
		var amount_label := Label.new()
		renderer.add_child(amount_label)
		renderer.resource_amount_labels.append(amount_label)
	renderer.update_resource_bar_values()
	var fish_index := resource_order.find(WorldData.RESOURCE_FISH)
	_expect(
		fish_index >= 0
		and renderer.resource_amount_labels[fish_index].text == "19",
		"The resource bar must render the authoritative owned fish total."
	)
	renderer.free()

	_test_cache_invalidation_and_capacity_edges(
		accounting_state,
		house_id,
		fishery_id,
		stockpile_id,
		stockpile
	)


func _test_cache_invalidation_and_capacity_edges(
	accounting_state: CityResourceAccountingState,
	house_id: int,
	fishery_id: int,
	stockpile_id: int,
	stockpile: Dictionary
) -> void:
	var cache_before_private_mutation: Dictionary = (
		accounting_state.owned_resource_amount_cache
	)
	var container_before_private_mutation := accounting_state.container_version
	var public_before_private_mutation := accounting_state.public_storage_version
	_expect(
		WorldData.add_resource_to_city_object_storage(
			house_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1
		and accounting_state.container_version
		== container_before_private_mutation + 1
		and accounting_state.public_storage_version
		== public_before_private_mutation
		and accounting_state.owned_resource_amount_cache_container_version
		== container_before_private_mutation,
		"Private pantry mutation must invalidate owned cache without public versioning."
	)
	_expect(
		WorldData.get_total_owned_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 19
		and not is_same(
			accounting_state.owned_resource_amount_cache,
			cache_before_private_mutation
		)
		and accounting_state.owned_resource_amount_cache_container_version
		== accounting_state.container_version,
		"Recomputing after a pantry change must preserve the excluded owned total."
	)

	var public_before_workplace_mutation := accounting_state.public_storage_version
	var container_before_workplace_mutation := accounting_state.container_version
	_expect(
		WorldData.add_resource_to_city_object_storage(
			fishery_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1
		and accounting_state.container_version
		== container_before_workplace_mutation + 1
		and accounting_state.public_storage_version
		== public_before_workplace_mutation
		and WorldData.get_total_owned_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 20,
		"Workplace output must invalidate owned totals without becoming public storage."
	)

	var container_before_public_mutation := accounting_state.container_version
	var public_before_public_mutation := accounting_state.public_storage_version
	_expect(
		WorldData.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1
		and accounting_state.container_version
		== container_before_public_mutation + 1
		and accounting_state.public_storage_version
		== public_before_public_mutation + 1
		and WorldData.get_total_owned_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 21
		and WorldData.get_total_public_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 9,
		"Stockpile mutation must version both accounting and public availability."
	)

	stockpile = CityObjectSystem.get_city_object_by_id(stockpile_id)
	var current_stockpile_fish := WorldData.get_city_object_stored_resource_amount(
		stockpile,
		WorldData.RESOURCE_FISH
	)
	var container_before_no_op := accounting_state.container_version
	var public_before_no_op := accounting_state.public_storage_version
	_expect(
		WorldData.set_city_object_stored_resource_amount(
			stockpile_id,
			WorldData.RESOURCE_FISH,
			current_stockpile_fish
		) == current_stockpile_fish
		and WorldData.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_NONE,
			1
		) == 0
		and accounting_state.container_version == container_before_no_op
		and accounting_state.public_storage_version == public_before_no_op,
		"No-op and invalid mutations must not advance accounting versions."
	)

	stockpile = CityObjectSystem.get_city_object_by_id(stockpile_id)
	var stockpile_free_space := WorldData.get_city_object_storage_free_space(
		stockpile
	)
	var accepted_gold := WorldData.add_resource_to_city_object_storage(
		stockpile_id,
		WorldData.RESOURCE_GOLD,
		999
	)
	_expect(
		accepted_gold == stockpile_free_space
		and accepted_gold == 169
		and WorldData.get_city_object_storage_used_capacity(
			CityObjectSystem.get_city_object_by_id(stockpile_id)
		) == 200,
		"Over-capacity deposits must accept only the physical free space."
	)
	var container_at_capacity := accounting_state.container_version
	var public_at_capacity := accounting_state.public_storage_version
	_expect(
		WorldData.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_GOLD,
			1
		) == 0
		and accounting_state.container_version == container_at_capacity
		and accounting_state.public_storage_version == public_at_capacity,
		"A full Stockpile must reject deposits without publishing false changes."
	)

	var removed_fish := WorldData.remove_resource_from_city_object_storage(
		stockpile_id,
		WorldData.RESOURCE_FISH,
		999
	)
	_expect(
		removed_fish == current_stockpile_fish
		and accounting_state.container_version == container_at_capacity + 1
		and accounting_state.public_storage_version == public_at_capacity + 1
		and WorldData.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id(stockpile_id),
			WorldData.RESOURCE_FISH
		) == 0,
		"Over-requested removal must remove only the physical stored amount."
	)
	_expect(
		WorldData.get_total_owned_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 15
		and WorldData.get_total_public_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 3
		and accounting_state.owned_resource_amount_cache_container_version
		== accounting_state.container_version,
		"Removal must refresh aggregate totals and restamp the owned cache."
	)


func _register_container(
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


func _reset_fixture(seed: int) -> WorldData:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game()
	var city_world := WorldData.new()
	city_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, seed)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.get_tile(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["fertility"] = 50.0
			tile.erase("surface_feature")

	city_world.mark_tile_data_changed()
	WorldData.store_city_world_save(city_world, seed)
	return city_world


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City resource-accounting regression test: " + message)
