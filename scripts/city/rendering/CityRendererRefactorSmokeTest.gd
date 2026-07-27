extends Node

const CITY_SCENE := preload("res://scenes/CityScreen.tscn")
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)
const CityWorldGeneratorScript = preload(
	"res://scripts/city/generation/CityWorldGenerator.gd"
)

var failure_count: int = 0
var background_draw_count: int = 0
var citizen_draw_count: int = 0
var interaction_draw_count: int = 0


func _ready() -> void:
	await _run_smoke_test()

	if failure_count > 0:
		push_error(
			"City renderer refactor smoke test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City renderer refactor smoke test passed.")
	get_tree().quit(0)


func _run_smoke_test() -> void:
	_prepare_dev_city_region()

	var renderer := CITY_SCENE.instantiate() as CityRenderer
	_expect(renderer != null, "City scene must instantiate a CityRenderer.")

	if renderer == null:
		return

	add_child(renderer)
	SimulationClock.set_simulation_paused(true)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(renderer.city_world != null, "City world must be generated.")
	_expect(
		renderer.city_background_render_layer != null,
		"Background render layer must exist."
	)
	_expect(
		renderer.city_citizen_render_layer != null,
		"Citizen render layer must exist."
	)
	_expect(
		renderer.city_interaction_render_layer != null,
		"Interaction render layer must exist."
	)

	_test_city_natural_features(renderer)
	await _test_focused_layer_invalidation(renderer)
	_test_resource_catalog_and_bulk_totals()
	_place_and_validate_city_fixture(renderer)

	renderer.queue_all_city_render_layers_redraw()
	await get_tree().process_frame
	await get_tree().process_frame

	var validation := CityStateValidatorScript.validate(true, false)
	_expect(
		bool(validation.get("valid", false)),
		"City state validator must remain valid after the fixture."
	)

	if not bool(validation.get("valid", false)):
		for error in validation.get("errors", []):
			push_error(str(error))

	renderer.queue_free()
	await get_tree().process_frame
	WorldData.reset_runtime_session_state()

	# Let any canceled texture-cache coroutine resume and release its in-flight
	# WorldData/Image references before this short-lived test process exits.
	for _frame_index in range(4):
		await get_tree().process_frame


func _test_focused_layer_invalidation(
	renderer: CityRenderer
) -> void:
	renderer.city_background_render_layer.draw.connect(
		_on_background_layer_draw
	)
	renderer.city_citizen_render_layer.draw.connect(
		_on_citizen_layer_draw
	)
	renderer.city_interaction_render_layer.draw.connect(
		_on_interaction_layer_draw
	)

	renderer.queue_all_city_render_layers_redraw()
	await get_tree().process_frame
	await get_tree().process_frame

	# Isolate the explicit invalidation from hover/version work performed by the
	# renderer's regular process loop.
	renderer.set_process(false)
	var background_before := background_draw_count
	var citizen_before := citizen_draw_count
	var interaction_before := interaction_draw_count

	renderer.queue_city_citizen_layer_redraw()
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(
		citizen_draw_count > citizen_before,
		"Citizen-only invalidation must redraw the citizen layer."
	)
	_expect(
		background_draw_count == background_before,
		"Citizen-only invalidation must not redraw the static city."
	)
	_expect(
		interaction_draw_count == interaction_before,
		"Citizen-only invalidation must not redraw interaction overlays."
	)
	renderer.set_process(true)


func _on_background_layer_draw() -> void:
	background_draw_count += 1


func _on_citizen_layer_draw() -> void:
	citizen_draw_count += 1


func _on_interaction_layer_draw() -> void:
	interaction_draw_count += 1


func _test_city_natural_features(
	renderer: CityRenderer
) -> void:
	var tree_count := 0
	var rock_count := 0
	var first_tree_tile := Vector2i(-1, -1)
	var first_rock_tile := Vector2i(-1, -1)

	for y in range(renderer.city_world.height):
		var row: Array = renderer.city_world.tiles[y]

		for x in range(renderer.city_world.width):
			var tile: Dictionary = row[x]
			var surface_feature := (
				WorldData.get_city_surface_feature(tile)
			)

			if (
				surface_feature
				== WorldData.CITY_SURFACE_FEATURE_TREE
			):
				tree_count += 1

				if first_tree_tile == Vector2i(-1, -1):
					first_tree_tile = Vector2i(x, y)

				_expect(
					str(tile.get("terrain", ""))
					== WorldData.TERRAIN_LAND,
					"Trees must generate only on walkable land terrain."
				)
				_expect(
					not [
						WorldData.BIOME_MOUNTAIN,
						WorldData.BIOME_OCEAN,
						WorldData.BIOME_RIVER,
					].has(str(tile.get("biome", ""))),
					"Mountains and water biomes must contain no trees."
				)
				continue

			if (
				surface_feature
				== WorldData.CITY_SURFACE_FEATURE_ROCK
			):
				rock_count += 1

				if first_rock_tile == Vector2i(-1, -1):
					first_rock_tile = Vector2i(x, y)

				_expect(
					str(tile.get("terrain", ""))
					== WorldData.TERRAIN_LAND,
					"Rocks must generate only where citizens can reach them."
				)

	_expect(tree_count > 0, "The dev city must generate trees.")
	_expect(
		renderer.city_tree_multimesh != null
		and renderer.city_tree_multimesh.instance_count
		== tree_count,
		"Tree MultiMesh count must match generated tree tiles."
	)
	_expect(
		renderer.city_rock_multimesh != null
		and renderer.city_rock_multimesh.instance_count
		== rock_count,
		"Rock MultiMesh count must match generated rock tiles."
	)

	if first_tree_tile != Vector2i(-1, -1):
		_expect(
			WorldData.is_city_tile_walkable_for_citizen(
				renderer.city_world,
				first_tree_tile
			),
			"Citizens must be able to walk beneath tree canopies."
		)
		_expect(
			not WorldData.can_city_ground_pile_exist_at_tile(
				renderer.city_world,
				first_tree_tile
			),
			"Ground piles must remain excluded from tree tiles."
		)

		var tree_multimesh_before := renderer.city_tree_multimesh
		var tile_data_version_before_harvest := (
			renderer.city_world.tile_data_version
		)
		var tree_tile := renderer.city_world.get_tile(
			first_tree_tile.x,
			first_tree_tile.y
		)
		tree_tile.erase("surface_feature")
		renderer.city_world.mark_city_surface_feature_changed(
			first_tree_tile,
			WorldData.CITY_SURFACE_FEATURE_TREE,
			WorldData.CITY_SURFACE_FEATURE_NONE
		)
		var feature_changes := (
			renderer.city_world.consume_city_surface_feature_changes()
		)

		_expect(
			renderer.apply_city_surface_feature_changes(feature_changes),
			"A harvested tree must update its existing MultiMesh in place."
		)
		_expect(
			renderer.city_tree_multimesh == tree_multimesh_before,
			"Tree harvesting must not rebuild the full tree MultiMesh."
		)
		_expect(
			renderer.city_tree_multimesh.visible_instance_count
			== tree_count - 1,
			"Harvesting one tree must hide exactly one tree instance."
		)
		_expect(
			renderer.city_world.tile_data_version
			== tile_data_version_before_harvest,
			"Harvesting a tree must not invalidate broad tile data."
		)

		# Restore the fixture after the focused incremental-removal check.
		tree_tile["surface_feature"] = WorldData.CITY_SURFACE_FEATURE_TREE
		renderer.rebuild_city_natural_feature_multimeshes()
		renderer.observed_city_surface_feature_change_version = (
			renderer.city_world.city_surface_feature_change_version
		)

	if first_rock_tile != Vector2i(-1, -1):
		_expect(
			WorldData.is_city_tile_walkable_for_citizen(
				renderer.city_world,
				first_rock_tile
			),
			"A rock tile must remain walkable."
		)

	_expect(
		WorldData.get_city_surface_feature_resource_type(
			WorldData.CITY_SURFACE_FEATURE_TREE
		)
		== WorldData.RESOURCE_LUMBER,
		"Trees must map to lumber for future foraging."
	)
	_expect(
		WorldData.get_city_surface_feature_resource_type(
			WorldData.CITY_SURFACE_FEATURE_ROCK
		)
		== WorldData.RESOURCE_STONE,
		"Rocks must map to stone for future foraging."
	)

	var previous_view_mode := renderer.city_view_mode
	renderer.city_view_mode = MapVisuals.ViewMode.RESOURCES
	_expect(
		not renderer.should_draw_city_trees(),
		"Trees must be hidden in Resources map mode."
	)
	renderer.city_view_mode = MapVisuals.ViewMode.BIOME
	_expect(
		renderer.should_draw_city_trees(),
		"Trees must remain visible outside Resources map mode."
	)
	renderer.city_view_mode = previous_view_mode

	_test_city_keep_accepts_tree_covered_access()


func _test_city_keep_accepts_tree_covered_access() -> void:
	var keep_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_CITY_CENTER
	)
	var test_world := WorldData.new()
	test_world.setup(
		keep_size.x + 2,
		keep_size.y + 2,
		9091
	)
	var keep_top_left := Vector2i.ONE

	for y in range(test_world.height):
		for x in range(test_world.width):
			var tile: Dictionary = test_world.get_tile(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND

			if (
				x == 0
				or y == 0
				or x == test_world.width - 1
				or y == test_world.height - 1
			):
				tile["surface_feature"] = (
					WorldData.CITY_SURFACE_FEATURE_TREE
				)

	_expect(
		WorldData.can_place_city_object(
			test_world,
			keep_top_left,
			keep_size,
			WorldData.CITY_OBJECT_CITY_CENTER
		),
		"A City Keep must accept tree-covered access tiles."
	)


func _prepare_dev_city_region() -> void:
	DevCityLauncher.reset_dev_city_state()

	var generator := WorldGenerator.new()
	var dev_world := generator.generate_world(
		DevCityLauncher.DEV_WORLD_SEED
	)
	var region_top_left := DevCityLauncher.find_good_dev_region(
		dev_world,
		DevCityLauncher.DEV_REGION_SIZE
	)
	var region_center := region_top_left + Vector2i(
		int(DevCityLauncher.DEV_REGION_SIZE / 2),
		int(DevCityLauncher.DEV_REGION_SIZE / 2)
	)

	_expect(
		region_top_left != Vector2i(-1, -1),
		"Dev city region must be found."
	)

	SimulationClock.start_new_game()
	WorldData.lock_world_save({
		"source_world": dev_world,
		"region_top_left": region_top_left,
		"region_center": region_center,
		"region_size": DevCityLauncher.DEV_REGION_SIZE,
		"world_scene_path": "res://scenes/MainMenu.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
	})


func _test_resource_catalog_and_bulk_totals() -> void:
	var expected_resources: Array[String] = [
		WorldData.RESOURCE_FISH,
		WorldData.RESOURCE_MEAT,
		WorldData.RESOURCE_LUMBER,
		WorldData.RESOURCE_STONE,
		WorldData.RESOURCE_COAL,
		WorldData.RESOURCE_IRON,
		WorldData.RESOURCE_GOLD,
	]

	_expect(
		WorldData.get_city_resource_types() == expected_resources,
		"Resource catalog order must remain stable."
	)
	_expect(
		WorldData.is_city_resource_type(WorldData.RESOURCE_MEAT),
		"Meat must be a valid city resource."
	)
	_expect(
		not WorldData.is_city_resource_type("invalid_resource"),
		"Unknown resource IDs must remain invalid."
	)
	_expect(
		WorldData.get_city_food_hunger_restore(
			WorldData.RESOURCE_MEAT
		)
		== 40,
		"Meat nutrition must remain 40."
	)

	var fishery_definition := WorldData.get_city_object_definition(
		WorldData.CITY_OBJECT_FISHING_GROUNDS
	)
	var fishery_source_policy: Dictionary = (
		fishery_definition.get("resource_source_policy", {})
	)
	_expect(
		int(fishery_source_policy.get("reach_tiles", 0)) == 8,
		"Fishing Grounds reach must remain eight tiles."
	)
	_expect(
		int(
			fishery_source_policy.get(
				"source_density_for_full_productivity_basis_points",
				0
			)
		)
		== 1_000,
		"Fishing Grounds full productivity must require 10% fish density."
	)
	var fishery_recipe: Dictionary = fishery_definition.get(
		"production_recipe",
		{}
	)
	_expect(
		int(fishery_recipe.get("work_units_per_batch", 0)) == 180_000,
		"Fishing Grounds must require three worker-hours per fish."
	)


	var house_definition := WorldData.get_city_object_definition(
		WorldData.CITY_OBJECT_HOUSE
	)
	var house_container_policy: Dictionary = house_definition.get(
		"container_access_policy",
		{}
	)
	_expect(
		not bool(
			house_container_policy.get(
				WorldData.CONTAINER_ACCESS_COUNTS_TOWARD_CITY_OWNED_TOTALS,
				true
			)
		),
		"Private house storage must not count as secured city resources."
	)

	var city_generator := CityWorldGeneratorScript.new()
	for biome in [
		WorldData.BIOME_PLAIN,
		WorldData.BIOME_FOREST,
		WorldData.BIOME_TAIGA,
		WorldData.BIOME_JUNGLE,
		WorldData.BIOME_TUNDRA,
		WorldData.BIOME_DESERT,
	]:
		_expect(
			city_generator.get_sparse_rock_base_spawn_chance(biome) > 0.0,
			"Every non-hill land biome must retain sparse rock generation."
		)


func _place_and_validate_city_fixture(
	renderer: CityRenderer
) -> void:
	var keep_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_CITY_CENTER
	)
	var keep_top_left := _find_placeable_rectangle(
		renderer.city_world,
		keep_size,
		WorldData.CITY_OBJECT_CITY_CENTER
	)

	_expect(
		keep_top_left != Vector2i(-1, -1),
		"A placeable City Keep footprint must exist."
	)

	if keep_top_left == Vector2i(-1, -1):
		return

	var tree_test_tile := keep_top_left
	var rock_test_tile := keep_top_left + Vector2i(1, 0)
	renderer.city_world.get_tile(
		tree_test_tile.x,
		tree_test_tile.y
	)["surface_feature"] = WorldData.CITY_SURFACE_FEATURE_TREE
	renderer.city_world.get_tile(
		rock_test_tile.x,
		rock_test_tile.y
	)["surface_feature"] = WorldData.CITY_SURFACE_FEATURE_ROCK
	renderer.city_world.mark_tile_data_changed()
	var tile_data_version_before_placement := (
		renderer.city_world.tile_data_version
	)

	_expect(
		WorldData.can_place_city_object(
			renderer.city_world,
			keep_top_left,
			keep_size,
			WorldData.CITY_OBJECT_CITY_CENTER
		),
		"Surface features must not invalidate building placement."
	)

	var keep := WorldData.add_city_object(
		WorldData.CITY_OBJECT_CITY_CENTER,
		keep_top_left,
		keep_size,
		"player",
		renderer.city_world
	)

	_expect(
		WorldData.get_city_surface_feature(
			renderer.city_world.get_tile(
				tree_test_tile.x,
				tree_test_tile.y
			)
		)
		== WorldData.CITY_SURFACE_FEATURE_NONE,
		"Placed buildings must remove covered trees."
	)
	_expect(
		WorldData.get_city_surface_feature(
			renderer.city_world.get_tile(
				rock_test_tile.x,
				rock_test_tile.y
			)
		)
		== WorldData.CITY_SURFACE_FEATURE_NONE,
		"Placed buildings must remove covered rocks."
	)
	_expect(
		renderer.city_world.tile_data_version
		== tile_data_version_before_placement + 1,
		"One placement must publish one surface-feature tile change."
	)

	renderer.after_city_center_placed(keep)

	_expect(
		WorldData.get_city_population_count()
		== WorldData.STARTING_CITY_POPULATION,
		"Founding must still create the starting population."
	)

	var keep_id := int(keep.get("id", -1))
	var before_totals := (
		WorldData.get_total_owned_city_resource_amounts()
	)
	_expect(
		int(before_totals.get(WorldData.RESOURCE_FISH, 0))
		== 0,
		"Fixture must begin without fish."
	)

	var accepted_fish := (
		WorldData.add_resource_to_city_object_storage(
			keep_id,
			WorldData.RESOURCE_FISH,
			3
		)
	)
	_expect(accepted_fish == 3, "Keep must accept three fish.")
	_expect(
		WorldData.get_total_owned_city_resource_amount(
			WorldData.RESOURCE_FISH
		)
		== 3,
		"Bulk owned-resource cache must invalidate after storage changes."
	)


	var first_citizen := WorldData.city_citizens[0]
	var first_citizen_id := int(first_citizen.get("id", -1))
	var removed_fish := WorldData.remove_resource_from_city_object_storage(
		keep_id,
		WorldData.RESOURCE_FISH,
		1
	)
	var carried_fish := WorldData.set_city_citizen_haul_cargo(
		first_citizen_id,
		WorldData.RESOURCE_FISH,
		removed_fish
	)
	_expect(removed_fish == 1 and carried_fish == 1, "Fixture haul pickup must succeed.")
	_expect(
		WorldData.get_total_owned_city_resource_amount(
			WorldData.RESOURCE_FISH
		)
		== 2,
		"In-transit citizen cargo must not count as secured city resources."
	)
	_expect(
		WorldData.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_FISH
		)
		== 3,
		"Resource conservation must still include in-transit cargo."
	)
	WorldData.set_city_citizen_haul_cargo(
		first_citizen_id,
		WorldData.RESOURCE_NONE,
		0
	)
	WorldData.add_resource_to_city_object_storage(
		keep_id,
		WorldData.RESOURCE_FISH,
		1
	)

	var mixed_cargo := CityCitizens.make_city_citizen_haul_cargo({
		"resources": {
			WorldData.RESOURCE_LUMBER: 4,
			WorldData.RESOURCE_STONE: 4,
			WorldData.RESOURCE_FISH: 2,
		},
	})
	_expect(
		int(mixed_cargo.get("amount", 0)) == 10,
		"Mixed haul cargo must sum every resource amount."
	)
	var mixed_resources: Dictionary = mixed_cargo.get("resources", {})
	_expect(
		int(mixed_resources.get(WorldData.RESOURCE_LUMBER, 0)) == 4
		and int(mixed_resources.get(WorldData.RESOURCE_STONE, 0)) == 4
		and int(mixed_resources.get(WorldData.RESOURCE_FISH, 0)) == 2,
		"Mixed haul cargo must preserve its 4 + 4 + 2 manifest."
	)
	_expect(
		WorldData.set_city_citizen_haul_cargo_resources(
			first_citizen_id,
			mixed_cargo.get("resources", {})
		) == 10,
		"A citizen with capacity ten must accept a full mixed load."
	)
	_expect(
		WorldData.get_city_citizen_haul_cargo_resource_amount(
			first_citizen_id,
			WorldData.RESOURCE_STONE
		) == 4,
		"Mixed cargo lookup must return the requested resource amount."
	)
	WorldData.set_city_citizen_haul_cargo_resources(
		first_citizen_id,
		{}
	)

	var chained_haul := CityCitizens.make_city_citizen_haul({
		"allow_ground_pile_pickup_chaining": true,
		"pickup_stop_count": 3,
	})
	_expect(
		bool(
			chained_haul.get(
				"allow_ground_pile_pickup_chaining",
				false
			)
		)
		and int(chained_haul.get("pickup_stop_count", 0)) == 3,
		"Haul state must preserve multi-stop ground-pile routing."
	)

	var first_access_tiles := WorldData.get_city_object_access_tiles(
		renderer.city_world,
		keep
	)
	var second_access_tiles := WorldData.get_city_object_access_tiles(
		renderer.city_world,
		keep
	)
	_expect(
		not first_access_tiles.is_empty(),
		"Keep must expose citizen access tiles."
	)
	_expect(
		first_access_tiles == second_access_tiles,
		"Cached access tiles must preserve deterministic results."
	)

	if not first_access_tiles.is_empty():
		first_access_tiles.clear()
		_expect(
			not WorldData.get_city_object_access_tiles(
				renderer.city_world,
				keep
			).is_empty(),
			"Access-tile callers must not mutate the cached array."
		)


func _find_placeable_rectangle(
	city_world: WorldData,
	size_tiles: Vector2i,
	object_type: String = ""
) -> Vector2i:
	if city_world == null:
		return Vector2i(-1, -1)

	for y in range(city_world.height - size_tiles.y + 1):
		for x in range(city_world.width - size_tiles.x + 1):
			var top_left := Vector2i(x, y)

			if WorldData.can_place_city_object(
				city_world,
				top_left,
				size_tiles,
				object_type
			):
				return top_left

	return Vector2i(-1, -1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
