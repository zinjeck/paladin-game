extends RefCounted
class_name CityWorldGenerator

var city_world: WorldData
var city_seed: int = 0

var detail_noise := FastNoiseLite.new()
var fertility_noise := FastNoiseLite.new()
var resource_noise := FastNoiseLite.new()
var biome_warp_noise := FastNoiseLite.new()
var coast_noise := FastNoiseLite.new()
var biome_edge_noise := FastNoiseLite.new()


static func calculate_city_seed() -> int:
	var center: Vector2i = WorldData.city_start_region_center

	var seed_value: int = int(WorldData.city_start_world_seed)
	seed_value += int(center.x * 73856093)
	seed_value += int(center.y * 19349663)
	seed_value += int(WorldData.city_start_region_size * 83492791)

	return seed_value


func generate_city_world(
	local_tiles_per_world_tile: int,
	requested_city_seed: int
) -> WorldData:
	var region_size: int = WorldData.city_start_region_size
	var city_width: int = region_size * local_tiles_per_world_tile
	var city_height: int = region_size * local_tiles_per_world_tile

	city_seed = requested_city_seed
	setup_city_noise()

	city_world = WorldData.new()
	city_world.setup(city_width, city_height, city_seed)

	for y in range(city_world.height):
		var row: Array = city_world.tiles[y]

		for x in range(city_world.width):
			var tile: Dictionary = row[x]
			var profile: Dictionary = get_city_source_profile(x, y, region_size)

			copy_city_profile_into_tile(tile, profile, x, y)

			row[x] = tile

	city_world.mark_tile_data_changed()

	return city_world


func get_city_source_profile(city_x: int, city_y: int, region_size: int) -> Dictionary:
	var source_fx: float = ((float(city_x) + 0.5) / float(city_world.width)) * float(region_size) - 0.5
	var source_fy: float = ((float(city_y) + 0.5) / float(city_world.height)) * float(region_size) - 0.5

	var warp_strength := 0.62

	source_fx += biome_warp_noise.get_noise_2d(city_x, city_y) * warp_strength
	source_fy += biome_warp_noise.get_noise_2d(city_x + 9173, city_y - 4289) * warp_strength

	source_fx = clamp(source_fx, 0.0, float(region_size - 1))
	source_fy = clamp(source_fy, 0.0, float(region_size - 1))

	var x0: int = int(floor(source_fx))
	var y0: int = int(floor(source_fy))
	var x1: int = min(x0 + 1, region_size - 1)
	var y1: int = min(y0 + 1, region_size - 1)

	var tx: float = source_fx - float(x0)
	var ty: float = source_fy - float(y0)

	var w00: float = (1.0 - tx) * (1.0 - ty)
	var w10: float = tx * (1.0 - ty)
	var w01: float = (1.0 - tx) * ty
	var w11: float = tx * ty

	var profile := {
		"elevation": 0.0,
		"temperature": 0.0,
		"precipitation": 0.0,
		"fertility": 0.0,
		"fertility_weight": 0.0,
		"water_weight": 0.0,
		"ocean_weight": 0.0,
		"river_weight": 0.0,
		"mountain_weight": 0.0,
		"biome_weights": {},
		"resource_weights": {}
	}

	accumulate_city_source_sample(profile, WorldData.city_start_tiles[y0][x0], w00)
	accumulate_city_source_sample(profile, WorldData.city_start_tiles[y0][x1], w10)
	accumulate_city_source_sample(profile, WorldData.city_start_tiles[y1][x0], w01)
	accumulate_city_source_sample(profile, WorldData.city_start_tiles[y1][x1], w11)

	if float(profile["fertility_weight"]) > 0.0:
		profile["fertility"] = float(profile["fertility"]) / float(profile["fertility_weight"])
	else:
		profile["fertility"] = -1.0

	return profile


func accumulate_city_source_sample(
	profile: Dictionary,
	source_tile: Dictionary,
	weight: float
) -> void:
	if weight <= 0.0:
		return

	var source_biome: String = str(source_tile["biome"])
	var source_resource: String = str(source_tile["resource"])
	var source_terrain: String = str(source_tile["terrain"])

	profile["elevation"] = float(profile["elevation"]) + float(source_tile["elevation"]) * weight
	profile["temperature"] = float(profile["temperature"]) + float(source_tile["temperature"]) * weight
	profile["precipitation"] = float(profile["precipitation"]) + float(source_tile["precipitation"]) * weight

	var source_fertility: float = float(source_tile["fertility"])

	if source_fertility >= 0.0:
		profile["fertility"] = float(profile["fertility"]) + source_fertility * weight
		profile["fertility_weight"] = float(profile["fertility_weight"]) + weight

	add_weight_to_dictionary(profile["biome_weights"], source_biome, weight)
	add_weight_to_dictionary(profile["resource_weights"], source_resource, weight)

	if source_terrain == WorldData.TERRAIN_WATER:
		profile["water_weight"] = float(profile["water_weight"]) + weight

	if source_biome == WorldData.BIOME_OCEAN:
		profile["ocean_weight"] = float(profile["ocean_weight"]) + weight

	if source_biome == WorldData.BIOME_RIVER:
		profile["river_weight"] = float(profile["river_weight"]) + weight

	if source_biome == WorldData.BIOME_MOUNTAIN:
		profile["mountain_weight"] = float(profile["mountain_weight"]) + weight


func add_weight_to_dictionary(weights: Dictionary, key: String, amount: float) -> void:
	if not weights.has(key):
		weights[key] = 0.0

	weights[key] = float(weights[key]) + amount


func copy_city_profile_into_tile(
	tile: Dictionary,
	profile: Dictionary,
	city_x: int,
	city_y: int
) -> void:
	var local_detail: float = detail_noise.get_noise_2d(city_x, city_y) * 0.030
	var local_fertility_detail: float = fertility_noise.get_noise_2d(city_x, city_y) * 7.0

	var water_weight: float = float(profile["water_weight"])
	var ocean_weight: float = float(profile["ocean_weight"])
	var river_weight: float = float(profile["river_weight"])

	var coastline_threshold: float = 0.50 + coast_noise.get_noise_2d(city_x, city_y) * 0.18
	var river_threshold: float = 0.40 + coast_noise.get_noise_2d(city_x + 5000, city_y - 5000) * 0.10

	var becomes_river: bool = river_weight > river_threshold
	var becomes_water: bool = water_weight > coastline_threshold or becomes_river

	tile["elevation"] = float(profile["elevation"]) + local_detail
	tile["temperature"] = float(profile["temperature"])
	tile["precipitation"] = float(profile["precipitation"])

	if becomes_water:
		tile["terrain"] = WorldData.TERRAIN_WATER
		tile["is_land"] = false
		tile["fertility"] = -1.0

		if becomes_river and river_weight >= ocean_weight:
			tile["biome"] = WorldData.BIOME_RIVER
		else:
			tile["biome"] = WorldData.BIOME_OCEAN

	else:
		var land_biome: String = get_dominant_land_biome(
			profile["biome_weights"],
			city_x,
			city_y
		)

		tile["biome"] = land_biome
		tile["is_land"] = true

		if land_biome == WorldData.BIOME_MOUNTAIN:
			tile["terrain"] = WorldData.TERRAIN_MOUNTAIN
		else:
			tile["terrain"] = WorldData.TERRAIN_LAND

		var profile_fertility: float = float(profile["fertility"])

		if profile_fertility >= 0.0:
			tile["fertility"] = clamp(
				profile_fertility + local_fertility_detail,
				0.0,
				100.0
			)
		else:
			tile["fertility"] = 0.0

	tile["resource"] = get_city_resource_from_profile(
		profile,
		city_x,
		city_y,
		str(tile["biome"]),
		str(tile["terrain"])
	)


func get_dominant_land_biome(
	biome_weights: Dictionary,
	city_x: int,
	city_y: int
) -> String:
	var best_biome := WorldData.BIOME_PLAIN
	var best_score := -99999.0

	for biome_key in biome_weights.keys():
		var biome := str(biome_key)

		if biome == WorldData.BIOME_OCEAN:
			continue

		if biome == WorldData.BIOME_RIVER:
			continue

		var score: float = float(biome_weights[biome_key])
		score += get_biome_boundary_bias(biome, city_x, city_y)

		if score > best_score:
			best_score = score
			best_biome = biome

	return best_biome


func get_biome_boundary_bias(biome: String, city_x: int, city_y: int) -> float:
	var offset: int = get_biome_noise_offset(biome)
	var noise_value: float = biome_edge_noise.get_noise_2d(
		city_x + offset,
		city_y - offset
	)

	return noise_value * 0.075


func get_biome_noise_offset(biome: String) -> int:
	match biome:
		WorldData.BIOME_MOUNTAIN:
			return 1000

		WorldData.BIOME_HILLS:
			return 2000

		WorldData.BIOME_DESERT:
			return 3000

		WorldData.BIOME_PLAIN:
			return 4000

		WorldData.BIOME_FOREST:
			return 5000

		WorldData.BIOME_TUNDRA:
			return 6000

		WorldData.BIOME_TAIGA:
			return 7000

		WorldData.BIOME_JUNGLE:
			return 8000

	return 9000


func setup_city_noise() -> void:
	detail_noise.seed = city_seed
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.055
	detail_noise.fractal_octaves = 4
	detail_noise.fractal_gain = 0.50
	detail_noise.fractal_lacunarity = 2.0

	fertility_noise.seed = city_seed + 4111
	fertility_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fertility_noise.frequency = 0.075
	fertility_noise.fractal_octaves = 3
	fertility_noise.fractal_gain = 0.55
	fertility_noise.fractal_lacunarity = 2.0

	resource_noise.seed = city_seed + 9221
	resource_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	resource_noise.frequency = 0.105
	resource_noise.fractal_octaves = 3
	resource_noise.fractal_gain = 0.50
	resource_noise.fractal_lacunarity = 2.0

	biome_warp_noise.seed = city_seed + 1771
	biome_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_warp_noise.frequency = 0.026
	biome_warp_noise.fractal_octaves = 3
	biome_warp_noise.fractal_gain = 0.52
	biome_warp_noise.fractal_lacunarity = 2.0

	coast_noise.seed = city_seed + 2887
	coast_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	coast_noise.frequency = 0.060
	coast_noise.fractal_octaves = 4
	coast_noise.fractal_gain = 0.52
	coast_noise.fractal_lacunarity = 2.0

	biome_edge_noise.seed = city_seed + 6397
	biome_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_edge_noise.frequency = 0.050
	biome_edge_noise.fractal_octaves = 3
	biome_edge_noise.fractal_gain = 0.50
	biome_edge_noise.fractal_lacunarity = 2.0


func get_city_resource_from_profile(
	profile: Dictionary,
	city_x: int,
	city_y: int,
	biome: String,
	terrain: String
) -> String:
	var resource_weights: Dictionary = profile["resource_weights"]

	var best_resource := WorldData.RESOURCE_NONE
	var best_weight := 0.0

	for resource_key in resource_weights.keys():
		var resource := str(resource_key)

		if resource == WorldData.RESOURCE_NONE:
			continue

		var weight: float = float(resource_weights[resource_key])

		if weight > best_weight:
			best_weight = weight
			best_resource = resource

	if best_resource == WorldData.RESOURCE_NONE:
		return WorldData.RESOURCE_NONE

	if best_resource == WorldData.RESOURCE_FISH and terrain != WorldData.TERRAIN_WATER:
		return WorldData.RESOURCE_NONE

	if best_resource == WorldData.RESOURCE_GOLD:
		if biome != WorldData.BIOME_HILLS and biome != WorldData.BIOME_MOUNTAIN:
			return WorldData.RESOURCE_NONE

	if best_resource != WorldData.RESOURCE_FISH and terrain == WorldData.TERRAIN_WATER:
		return WorldData.RESOURCE_NONE

	var noise_value: float = (resource_noise.get_noise_2d(city_x, city_y) + 1.0) * 0.5
	var spawn_chance: float = clamp(best_weight * 0.55, 0.025, 0.42)

	if noise_value > 1.0 - spawn_chance:
		return best_resource

	return WorldData.RESOURCE_NONE
