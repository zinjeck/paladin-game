extends RefCounted
class_name DevCityLauncher

const DEV_WORLD_SEED: int = 223456789
const DEV_REGION_SIZE: int = 9
const DEV_REGION_OCEAN_RATIO_LIMIT: float = 0.90
const DEV_CITY_NAME := "Dev City"
const DEV_CULTURE_NAME := "Dev Culture"


static func launch_dev_city(
	tree: SceneTree,
	game_session_scene_path: String,
	city_scene_path: String = "res://scenes/CityScreen.tscn"
) -> void:
	if tree == null:
		push_error("DevCityLauncher needs a valid SceneTree.")
		return

	if game_session_scene_path.is_empty():
		push_error("Dev city GameSession scene path is empty.")
		return

	if city_scene_path.is_empty():
		push_error("Dev city scene path is empty.")
		return

	reset_dev_city_state()

	var generator := WorldGenerator.new()
	var dev_world := generator.generate_world(DEV_WORLD_SEED)

	var region_top_left := find_good_dev_region(dev_world, DEV_REGION_SIZE)

	if region_top_left == Vector2i(-1, -1):
		push_error("Could not find a valid dev city region.")
		return

	SimulationCoordinator.reset_performance_statistics()

	var region_center := region_top_left + Vector2i(
		int(DEV_REGION_SIZE / 2),
		int(DEV_REGION_SIZE / 2)
	)

	var world_lock_succeeded := WorldData.lock_world_save({
		"source_world": dev_world,
		"region_top_left": region_top_left,
		"region_center": region_center,
		"region_size": DEV_REGION_SIZE,
		"world_scene_path": game_session_scene_path,
		"city_scene_path": city_scene_path,
		"city_name": DEV_CITY_NAME,
		"culture_name": DEV_CULTURE_NAME,
	})

	if not world_lock_succeeded:
		push_error("Could not lock the dev world and founding identity.")
		return

	# Dev City now uses the same persistent session and city-preparation path as
	# ordinary play. The one-shot request is consumed by the next GameSession.
	GameSession.request_next_session_city_entry()

	print("Launching dev city through GameSession.")
	print("Dev world seed: ", dev_world.seed)
	print("Dev region top-left: ", region_top_left)
	print("Dev region center: ", region_center)
	print("Dev city name: ", DEV_CITY_NAME)
	print("Dev culture name: ", DEV_CULTURE_NAME)

	var error: Error = tree.change_scene_to_file(game_session_scene_path)

	if error != OK:
		GameSession.cancel_next_session_city_entry()
		push_error(
			"Could not load dev GameSession scene: "
			+ game_session_scene_path
		)


static func reset_dev_city_state() -> void:
	GameSession.cancel_next_session_city_entry()
	WorldData.reset_runtime_session_state()
	SimulationClock.reset_clock_state()
	SimulationClock.set_simulation_paused(true)


static func find_good_dev_region(world: WorldData, region_size: int) -> Vector2i:
	if world == null:
		return Vector2i(-1, -1)

	var center := Vector2i(
		int(world.width / 2),
		int(world.height / 2)
	)

	var half_size := int(region_size / 2)
	var ocean_prefix_sum := build_ocean_prefix_sum(world)

	var best_region := Vector2i(-1, -1)
	var best_distance_squared := INF

	for y in range(half_size, world.height - half_size):
		for x in range(half_size, world.width - half_size):
			var region_top_left := Vector2i(x - half_size, y - half_size)

			if not is_dev_region_valid_with_prefix(ocean_prefix_sum, region_top_left, region_size):
				continue

			var dx := float(x - center.x)
			var dy := float(y - center.y)
			var distance_squared := dx * dx + dy * dy

			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_region = region_top_left

	return best_region


static func build_ocean_prefix_sum(world: WorldData) -> Array:
	var prefix := []

	for y in range(world.height + 1):
		var row := []

		for x in range(world.width + 1):
			row.append(0)

		prefix.append(row)

	for y in range(world.height):
		var source_row: Array = world.tiles[y]
		var prefix_row: Array = prefix[y + 1]
		var previous_prefix_row: Array = prefix[y]
		var row_total := 0

		for x in range(world.width):
			var tile: Dictionary = source_row[x]

			if str(tile.get("biome", "")) == WorldData.BIOME_OCEAN:
				row_total += 1

			prefix_row[x + 1] = int(previous_prefix_row[x + 1]) + row_total

	return prefix


static func is_dev_region_valid_with_prefix(
	ocean_prefix_sum: Array,
	region_top_left: Vector2i,
	region_size: int
) -> bool:
	var x0 := region_top_left.x
	var y0 := region_top_left.y
	var x1 := x0 + region_size
	var y1 := y0 + region_size

	var ocean_tiles: int = (
		int(ocean_prefix_sum[y1][x1])
		- int(ocean_prefix_sum[y0][x1])
		- int(ocean_prefix_sum[y1][x0])
		+ int(ocean_prefix_sum[y0][x0])
	)

	var total_tiles := region_size * region_size
	var ocean_ratio := float(ocean_tiles) / float(total_tiles)

	return ocean_ratio <= DEV_REGION_OCEAN_RATIO_LIMIT
