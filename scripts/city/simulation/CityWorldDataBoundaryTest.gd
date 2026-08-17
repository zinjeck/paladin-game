extends Node

var failure_count: int = 0

func _ready() -> void:
	WorldData.reset_runtime_session_state()
	_test_catalog_boundary()
	_test_tile_owner_mutation_boundary()
	_test_catalog_recursive_readonly_boundary()
	_test_environmental_resource_cache_invalidation()
	_test_registry_boundary()
	WorldData.reset_runtime_session_state()
	if failure_count > 0:
		push_error("WorldData boundary test failed: " + str(failure_count))
		get_tree().quit(1)
		return
	print("WorldData final boundary test passed.")
	get_tree().quit(0)

func _test_catalog_boundary() -> void:
	var house := CityObjectCatalog.get_city_object_definition(CityObjectCatalog.CITY_OBJECT_HOUSE)
	_expect(not house.is_empty(), "CityObjectCatalog must own object definitions.")
	_expect(CityObjectCatalog.get_city_object_size_for_type(CityObjectCatalog.CITY_OBJECT_HOUSE) == Vector2i(3, 3), "Object metadata must resolve outside WorldData.")
	_expect(CityObjectCatalog.get_city_object_resident_capacity({"type": CityObjectCatalog.CITY_OBJECT_HOUSE}) == 4, "Housing policy must resolve through CityObjectCatalog.")


func _test_tile_owner_mutation_boundary() -> void:
	var world := WorldData.new()
	world.setup(6, 6, 98_801)
	var tile_position := Vector2i(2, 2)
	var caller_tile := world.make_default_tile()
	caller_tile.merge({
		"terrain": WorldData.TERRAIN_LAND,
		"biome": WorldData.BIOME_PLAIN,
		"is_land": true,
		"mutation_probe": {"value": 7},
	}, true)
	var version_before_set := world.tile_data_version

	_expect(
		world.set_tile(tile_position.x, tile_position.y, caller_tile)
		and world.tile_data_version == version_before_set + 1,
		"An effective tile replacement must publish exactly one broad tile version."
	)
	caller_tile["terrain"] = WorldData.TERRAIN_WATER
	caller_tile["is_land"] = false
	var caller_probe: Dictionary = caller_tile["mutation_probe"]
	caller_probe["value"] = 99
	var stored_tile := world.get_tile(tile_position.x, tile_position.y)
	var stored_probe: Dictionary = stored_tile.get("mutation_probe", {})
	_expect(
		str(stored_tile.get("terrain", "")) == WorldData.TERRAIN_LAND
		and bool(stored_tile.get("is_land", false))
		and int(stored_probe.get("value", -1)) == 7,
		"set_tile must detach both the caller Dictionary and its nested values."
	)
	stored_tile["terrain"] = WorldData.TERRAIN_WATER
	stored_probe["value"] = 123
	stored_tile = world.get_tile(tile_position.x, tile_position.y)
	stored_probe = stored_tile.get("mutation_probe", {})
	_expect(
		str(stored_tile.get("terrain", "")) == WorldData.TERRAIN_LAND
		and int(stored_probe.get("value", -1)) == 7,
		"get_tile must return a recursively detached public snapshot."
	)

	var stable_version := world.tile_data_version
	_expect(
		not world.set_tile(
			tile_position.x,
			tile_position.y,
			stored_tile.duplicate(true)
		)
		and world.tile_data_version == stable_version,
		"An equal replacement must be an exact no-op."
	)
	_expect(
		not world.set_tile(-1, -1, caller_tile)
		and world.tile_data_version == stable_version,
		"An out-of-bounds replacement must not publish a version."
	)

	var terrain_version := world.tile_data_version
	_expect(
		world.set_tile_terrain(tile_position, WorldData.TERRAIN_MOUNTAIN)
		and world.tile_data_version == terrain_version + 1
		and str(
			world.get_tile(tile_position.x, tile_position.y).get(
				"terrain",
				""
			)
		) == WorldData.TERRAIN_MOUNTAIN,
		"Terrain mutation must route through the tile owner and version once."
	)
	terrain_version = world.tile_data_version
	_expect(
		not world.set_tile_terrain(tile_position, WorldData.TERRAIN_MOUNTAIN)
		and not world.set_tile_terrain(tile_position, "invalid_terrain")
		and world.tile_data_version == terrain_version,
		"No-op and invalid terrain mutations must not publish versions."
	)

	var resource_version := world.tile_data_version
	_expect(
		world.set_tile_resource_value(tile_position, WorldData.RESOURCE_FISH)
		and world.tile_data_version == resource_version + 1
		and str(
			world.get_tile(tile_position.x, tile_position.y).get(
				"resource",
				WorldData.RESOURCE_NONE
			)
		) == WorldData.RESOURCE_FISH,
		"Resource mutation must route through the tile owner and version once."
	)
	resource_version = world.tile_data_version
	_expect(
		not world.set_tile_resource_value(tile_position, WorldData.RESOURCE_FISH)
		and not world.set_tile_resource_value(tile_position, "invalid_resource")
		and world.tile_data_version == resource_version,
		"No-op and invalid resource mutations must not publish versions."
	)

	world.prepared_city_tree_tiles.assign([tile_position])
	world.prepared_city_rock_tiles.assign([Vector2i(3, 3)])
	world.prepared_city_feature_tile_data_version = world.tile_data_version
	var broad_version_before_feature := world.tile_data_version
	var feature_version_before := world.city_surface_feature_change_version
	_expect(
		world.set_tile_surface_feature(
			tile_position,
			WorldData.CITY_SURFACE_FEATURE_TREE
		)
		and world.tile_data_version == broad_version_before_feature
		and world.city_surface_feature_change_version
		== feature_version_before + 1
		and world.prepared_city_tree_tiles.is_empty()
		and world.prepared_city_rock_tiles.is_empty()
		and world.prepared_city_feature_tile_data_version == -1,
		"A surface-feature change must publish only focused invalidation and retire stale prepared lists."
	)
	feature_version_before = world.city_surface_feature_change_version
	_expect(
		not world.set_tile_surface_feature(
			tile_position,
			WorldData.CITY_SURFACE_FEATURE_TREE
		)
		and not world.remove_tile_surface_feature(
			tile_position,
			WorldData.CITY_SURFACE_FEATURE_ROCK
		)
		and world.city_surface_feature_change_version
		== feature_version_before,
		"No-op and compare-mismatched surface mutations must not publish versions."
	)
	_expect(
		world.remove_tile_surface_feature(
			tile_position,
			WorldData.CITY_SURFACE_FEATURE_TREE
		)
		and world.tile_data_version == broad_version_before_feature
		and world.city_surface_feature_change_version
		== feature_version_before + 1,
		"A matching surface removal must publish exactly one focused version."
	)
	var feature_changes := world.consume_city_surface_feature_changes()
	_expect(
		feature_changes.size() == 2
		and feature_changes[0].get("tile_position") == tile_position
		and str(feature_changes[0].get("previous_feature", ""))
		== WorldData.CITY_SURFACE_FEATURE_NONE
		and str(feature_changes[0].get("current_feature", ""))
		== WorldData.CITY_SURFACE_FEATURE_TREE
		and str(feature_changes[1].get("previous_feature", ""))
		== WorldData.CITY_SURFACE_FEATURE_TREE
		and str(feature_changes[1].get("current_feature", ""))
		== WorldData.CITY_SURFACE_FEATURE_NONE,
		"Surface publication must preserve the exact ordered previous/current transitions."
	)


func _test_catalog_recursive_readonly_boundary() -> void:
	var definitions := CityObjectCatalog.get_city_object_definitions()
	var definition_count := definitions.size()
	var fishery := CityObjectCatalog.get_city_object_definition(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
	)
	var storage_resources = fishery.get("storage_resources", [])
	var recipe := CityObjectCatalog.get_city_object_production_recipe({
		"type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
	})
	var outputs = recipe.get("outputs", {})
	var source_policy := CityObjectCatalog.get_city_object_resource_source_policy({
		"type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
	})

	definitions.erase(CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS)
	_expect(
		definitions.size() == definition_count - 1
		and CityObjectCatalog.get_city_object_definitions().size()
		== definition_count
		and CityObjectCatalog.get_city_object_definitions().has(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		),
		"The mutable outer catalog view must be a shallow isolated copy."
	)
	_expect(
		fishery.is_read_only()
		and storage_resources is Array
		and storage_resources.is_read_only()
		and recipe.is_read_only()
		and outputs is Dictionary
		and outputs.is_read_only()
		and source_policy.is_read_only(),
		"Catalog definitions, nested arrays, recipes, outputs, and policies must be recursively read-only."
	)
	_expect(
		int(outputs.get(WorldData.RESOURCE_FISH, 0)) == 1
		and str(source_policy.get("resource_type", ""))
		== WorldData.RESOURCE_FISH,
		"Read-only catalog views must preserve Fishery production and source policy."
	)

	var materials := CityObjectCatalog.get_city_object_construction_materials(
		CityObjectCatalog.CITY_OBJECT_HOUSE
	)
	var expected_lumber := int(materials.get(WorldData.RESOURCE_LUMBER, 0))
	if not materials.is_read_only():
		materials[WorldData.RESOURCE_LUMBER] = expected_lumber + 1_000
	_expect(
		int(
			CityObjectCatalog.get_city_object_construction_materials(
				CityObjectCatalog.CITY_OBJECT_HOUSE
			).get(WorldData.RESOURCE_LUMBER, 0)
		) == expected_lumber,
		"A detached mutable catalog result must never alias canonical definitions."
	)


func _test_environmental_resource_cache_invalidation() -> void:
	var world := WorldData.new()
	world.setup(12, 12, 98_802)
	var top_left := Vector2i(4, 4)
	var fishery_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
	)
	var fishery := {
		"id": 98_802,
		"type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": top_left,
		"size": fishery_size,
		"footprint_tiles": (
			CityObjectSystem.make_rectangle_city_object_footprint_tiles(
				top_left,
				fishery_size
			)
		),
	}
	WorkplaceProductionSystem.clear_resource_source_evaluation_cache()
	var before := WorkplaceProductionSystem.get_resource_source_evaluation(
		fishery,
		world
	)
	var resource_version := world.tile_data_version
	var resource_tile := Vector2i(1, 4)
	_expect(
		int(before.get("resource_tile_count", -1)) == 0
		and world.set_tile_resource_value(
			resource_tile,
			WorldData.RESOURCE_FISH
		)
		and world.tile_data_version == resource_version + 1,
		"The environmental-source fixture must publish one resource-tile mutation."
	)
	var after := WorkplaceProductionSystem.get_resource_source_evaluation(
		fishery,
		world
	)
	_expect(
		int(after.get("resource_tile_count", -1)) == 1
		and bool(after.get("has_resource", false))
		and after.get("resource_tiles", []).has(resource_tile),
		"A tile resource version change must invalidate the environmental-source cache without manual clearing."
	)
	WorkplaceProductionSystem.clear_resource_source_evaluation_cache()

func _test_registry_boundary() -> void:
	var culture := WorldData.create_culture("Pass 14 Culture")
	_expect(not culture.is_empty(), "World-level culture creation must remain available.")
	var citizen := CityCitizenRegistrySystem.add_city_citizen("", Vector2i(1, 1), CityCitizens.CITY_CITIZEN_SEX_MALE, int(culture.get("id", -1)))
	_expect(not citizen.is_empty(), "Citizen creation must resolve through CityCitizenRegistrySystem.")
	_expect(CityCitizenRegistrySystem.get_city_population_count() == 1, "Citizen registry owner must receive the new citizen.")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("WorldData boundary test: " + message)
