extends RefCounted
class_name DevCityLauncher

const DEV_WORLD_SEED: int = 123456789
const DEV_REGION_SIZE: int = 9
const DEV_REGION_OCEAN_RATIO_LIMIT: float = 0.90


static func launch_dev_city(
	tree: SceneTree,
	city_scene_path: String,
	main_menu_scene_path: String = "res://scenes/MainMenu.tscn"
) -> void:
	if tree == null:
		push_error("DevCityLauncher needs a valid SceneTree.")
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

	var region_center := region_top_left + Vector2i(
		int(DEV_REGION_SIZE / 2),
		int(DEV_REGION_SIZE / 2)
	)

	WorldData.lock_world_save(
		dev_world,
		region_top_left,
		region_center,
		DEV_REGION_SIZE,
		main_menu_scene_path,
		city_scene_path
	)

	print("Launching dev city.")
	print("Dev world seed: ", dev_world.seed)
	print("Dev region top-left: ", region_top_left)
	print("Dev region center: ", region_center)

	var error: Error = tree.change_scene_to_file(city_scene_path)

	if error != OK:
		push_error("Could not load dev city scene: " + city_scene_path)


static func reset_dev_city_state() -> void:
	WorldData.reset_runtime_session_state()


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


static func is_dev_region_valid(
	world: WorldData,
	region_top_left: Vector2i,
	region_size: int
) -> bool:
	if region_top_left.x < 0 or region_top_left.y < 0:
		return false

	if region_top_left.x + region_size > world.width:
		return false

	if region_top_left.y + region_size > world.height:
		return false

	var ocean_tiles := 0
	var total_tiles := region_size * region_size

	for y_offset in range(region_size):
		for x_offset in range(region_size):
			var tile_x := region_top_left.x + x_offset
			var tile_y := region_top_left.y + y_offset
			var tile: Dictionary = world.tiles[tile_y][tile_x]

			if str(tile.get("biome", "")) == WorldData.BIOME_OCEAN:
				ocean_tiles += 1

	var ocean_ratio := float(ocean_tiles) / float(total_tiles)

	return ocean_ratio <= DEV_REGION_OCEAN_RATIO_LIMIT
