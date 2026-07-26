extends Node

const CITY_SCENE := preload("res://scenes/CityScreen.tscn")
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
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
				"source_tiles_for_full_productivity",
				0
			)
		)
		== 10,
		"Fishing Grounds full productivity must remain ten fish tiles."
	)


func _place_and_validate_city_fixture(
	renderer: CityRenderer
) -> void:
	var keep_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_CITY_CENTER
	)
	var keep_top_left := _find_placeable_rectangle(
		renderer.city_world,
		keep_size
	)

	_expect(
		keep_top_left != Vector2i(-1, -1),
		"A placeable City Keep footprint must exist."
	)

	if keep_top_left == Vector2i(-1, -1):
		return

	var keep := WorldData.add_city_object(
		WorldData.CITY_OBJECT_CITY_CENTER,
		keep_top_left,
		keep_size
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
	size_tiles: Vector2i
) -> Vector2i:
	if city_world == null:
		return Vector2i(-1, -1)

	for y in range(city_world.height - size_tiles.y + 1):
		for x in range(city_world.width - size_tiles.x + 1):
			var top_left := Vector2i(x, y)

			if WorldData.can_place_city_object(
				city_world,
				top_left,
				size_tiles
			):
				return top_left

	return Vector2i(-1, -1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
