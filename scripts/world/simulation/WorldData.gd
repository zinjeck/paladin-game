extends RefCounted
class_name WorldData

# File responsibility: world/city grid data plus world/founding/session metadata and global visual-session coordination.
# Settlement-local simulation state and behavior belong to focused city systems.

const CultureDataScript = preload(
	"res://scripts/world/simulation/CultureData.gd"
)
const CityResourceCatalogScript = preload(
	"res://scripts/city/data/CityResourceCatalog.gd"
)
const MapTextureCacheStateScript = preload(
	"res://scripts/map/visuals/MapTextureCacheState.gd"
)
const MapCameraSessionStateScript = preload(
	"res://scripts/map/MapCameraSessionState.gd"
)

const TERRAIN_WATER := "water"
const TERRAIN_LAND := "land"
const TERRAIN_MOUNTAIN := "mountain"

const BIOME_OCEAN := "ocean"
const BIOME_MOUNTAIN := "mountain"
const BIOME_HILLS := "hills"
const BIOME_DESERT := "desert"
const BIOME_PLAIN := "plain"
const BIOME_FOREST := "forest"
const BIOME_TUNDRA:= "tundra"
const BIOME_TAIGA := "taiga"
const BIOME_JUNGLE := "jungle"
const BIOME_RIVER := "river"

const RESOURCE_NONE := CityResourceCatalogScript.RESOURCE_NONE
const RESOURCE_IRON := CityResourceCatalogScript.RESOURCE_IRON
const RESOURCE_COAL := CityResourceCatalogScript.RESOURCE_COAL
const RESOURCE_GOLD := CityResourceCatalogScript.RESOURCE_GOLD
const RESOURCE_FISH := CityResourceCatalogScript.RESOURCE_FISH
const RESOURCE_MEAT := CityResourceCatalogScript.RESOURCE_MEAT
const RESOURCE_LUMBER := CityResourceCatalogScript.RESOURCE_LUMBER
const RESOURCE_STONE := CityResourceCatalogScript.RESOURCE_STONE

const CITY_SURFACE_FEATURE_NONE := "none"
const CITY_SURFACE_FEATURE_TREE := "tree"
const CITY_SURFACE_FEATURE_ROCK := "rock"

var width: int
var height: int
var seed: int
var tiles := []
var tile_data_version: int = 0
var city_surface_feature_change_version: int = 0
var pending_city_surface_feature_changes: Array[Dictionary] = []
# City generation records its initial natural-feature positions while it is
# already traversing the map. The renderer may consume these immutable lists
# instead of immediately rescanning every tile. Any later tile-data version
# invalidates them automatically.
var prepared_city_tree_tiles: Array[Vector2i] = []
var prepared_city_rock_tiles: Array[Vector2i] = []
var prepared_city_feature_tile_data_version: int = -1

static var city_start_world_seed: int = 0
static var city_start_region_center: Vector2i = Vector2i(-1, -1)
static var city_start_region_top_left: Vector2i = Vector2i(-1, -1)
static var city_start_region_size: int = 0
static var city_start_tiles: Array = []
static var city_return_world_scene_path: String = ""
static var save_locked: bool = false
static var player_city_foundation_top_left: Vector2i = Vector2i(-1, -1)
static var player_city_foundation_size: Vector2i = Vector2i.ZERO
static var official_world = null
static var player_city_founded: bool = false
static var debug_mode_enabled: bool = false

const INVALID_CULTURE_ID: int = CultureDataScript.INVALID_CULTURE_ID
const MAX_FOUNDING_NAME_LENGTH: int = 40
static var cultures: Array = []
static var culture_index_by_id: Dictionary = {}
static var next_culture_id: int = 1
static var official_city_name: String = ""
static var official_founding_culture_id: int = INVALID_CULTURE_ID


static var official_selected_region_center: Vector2i = Vector2i(-1, -1)
static var official_selected_region_top_left: Vector2i = Vector2i(-1, -1)
static var official_region_size: int = 0

static var official_world_scene_path: String = ""
static var official_city_scene_path: String = ""


#region World Grid and Tile State

func setup(new_width: int, new_height: int, new_seed: int):
	width = new_width
	height = new_height
	seed = new_seed
	tiles.clear()
	tile_data_version = 0
	city_surface_feature_change_version = 0
	pending_city_surface_feature_changes.clear()
	_invalidate_prepared_city_feature_tiles()

	for y in range(height):
		var row := []
		for x in range(width):
			row.append(make_default_tile())

		tiles.append(row)

func make_default_tile() -> Dictionary:
	return {
		"fertility": -1.0,
		"elevation": 0.0,
		"temperature": 0.0,
		"precipitation": 0.0,
		"terrain": TERRAIN_WATER,
		"biome": BIOME_OCEAN,
		"resource": RESOURCE_NONE,
		"is_land": false
	}

func get_tile(x: int, y: int) -> Dictionary:
	return get_tile_for_internal_read(x, y).duplicate(true)


func get_tile_for_internal_read(x: int, y: int) -> Dictionary:
	if not is_in_bounds(x, y):
		return make_default_tile()

	return tiles[y][x]

func is_in_bounds(x: int, y: int) -> bool:
	if x < 0 or y < 0:
		return false

	if x >= width or y >= height:
		return false

	return true

func set_tile(x: int, y: int, data: Dictionary) -> bool:
	if not is_in_bounds(x, y):
		return false

	var replacement_tile := data.duplicate(true)

	if tiles[y][x] == replacement_tile:
		return false

	tiles[y][x] = replacement_tile
	mark_tile_data_changed()
	return true


func set_tile_terrain(
	tile_position: Vector2i,
	terrain: String
) -> bool:
	if (
		not is_in_bounds(tile_position.x, tile_position.y)
		or terrain not in [
			TERRAIN_WATER,
			TERRAIN_LAND,
			TERRAIN_MOUNTAIN,
		]
	):
		return false

	var current_tile: Dictionary = tiles[tile_position.y][tile_position.x]
	var is_land := terrain != TERRAIN_WATER

	if (
		str(current_tile.get("terrain", "")) == terrain
		and bool(current_tile.get("is_land", false)) == is_land
	):
		return false

	var replacement_tile := current_tile.duplicate(true)
	replacement_tile["terrain"] = terrain
	replacement_tile["is_land"] = is_land
	return set_tile(tile_position.x, tile_position.y, replacement_tile)


func set_tile_resource_value(
	tile_position: Vector2i,
	resource: String
) -> bool:
	if (
		not is_in_bounds(tile_position.x, tile_position.y)
		or (
			resource != RESOURCE_NONE
			and not CityResourceCatalogScript.is_city_resource_type(resource)
		)
	):
		return false

	var current_tile: Dictionary = tiles[tile_position.y][tile_position.x]

	if str(current_tile.get("resource", RESOURCE_NONE)) == resource:
		return false

	var replacement_tile := current_tile.duplicate(true)
	replacement_tile["resource"] = resource
	return set_tile(tile_position.x, tile_position.y, replacement_tile)


func set_tile_surface_feature(
	tile_position: Vector2i,
	surface_feature: String
) -> bool:
	if (
		not is_in_bounds(tile_position.x, tile_position.y)
		or (
			surface_feature != CITY_SURFACE_FEATURE_NONE
			and not is_city_surface_feature(surface_feature)
		)
	):
		return false

	var current_tile: Dictionary = tiles[tile_position.y][tile_position.x]
	var previous_feature := get_city_surface_feature(current_tile)

	if previous_feature == surface_feature:
		return false

	var replacement_tile := current_tile.duplicate(true)

	if surface_feature == CITY_SURFACE_FEATURE_NONE:
		replacement_tile.erase("surface_feature")
	else:
		replacement_tile["surface_feature"] = surface_feature

	tiles[tile_position.y][tile_position.x] = replacement_tile
	mark_city_surface_feature_changed(
		tile_position,
		previous_feature,
		surface_feature
	)
	return true


func remove_tile_surface_feature(
	tile_position: Vector2i,
	expected_feature: String = ""
) -> bool:
	if not is_in_bounds(tile_position.x, tile_position.y):
		return false

	var current_feature := get_city_surface_feature(
		tiles[tile_position.y][tile_position.x]
	)

	if (
		current_feature == CITY_SURFACE_FEATURE_NONE
		or (
			not expected_feature.is_empty()
			and current_feature != expected_feature
		)
	):
		return false

	return set_tile_surface_feature(
		tile_position,
		CITY_SURFACE_FEATURE_NONE
	)


func mark_tile_data_changed() -> void:
	tile_data_version += 1
	_invalidate_prepared_city_feature_tiles()


func _invalidate_prepared_city_feature_tiles() -> void:
	prepared_city_tree_tiles.clear()
	prepared_city_rock_tiles.clear()
	prepared_city_feature_tile_data_version = -1


func mark_city_surface_feature_changed(
	tile_position: Vector2i,
	previous_feature: String,
	current_feature: String
) -> void:
	if previous_feature == current_feature:
		return

	_invalidate_prepared_city_feature_tiles()
	pending_city_surface_feature_changes.append({
		"tile_position": tile_position,
		"previous_feature": previous_feature,
		"current_feature": current_feature,
	})
	city_surface_feature_change_version += 1


func consume_city_surface_feature_changes() -> Array[Dictionary]:
	var changes: Array[Dictionary] = []

	for change in pending_city_surface_feature_changes:
		changes.append(change.duplicate(true))

	pending_city_surface_feature_changes.clear()
	return changes


#endregion

#region Session Save and City Foundation State


static func normalize_official_city_name(city_name: String) -> String:
	return city_name.strip_edges()


static func is_valid_founding_name(name: String) -> bool:
	var normalized_name := name.strip_edges()

	return (
		not normalized_name.is_empty()
		and normalized_name.length() <= MAX_FOUNDING_NAME_LENGTH
	)


static func get_culture_index_by_id(culture_id: int) -> int:
	if culture_id <= 0 or not culture_index_by_id.has(culture_id):
		return -1

	var culture_index := int(culture_index_by_id[culture_id])

	if culture_index < 0 or culture_index >= cultures.size():
		return -1

	var raw_culture = cultures[culture_index]

	if not raw_culture is Dictionary:
		return -1

	var culture: Dictionary = raw_culture

	if (
		int(culture.get("id", INVALID_CULTURE_ID)) != culture_id
		or not CultureDataScript.is_valid_culture_record(culture)
	):
		return -1

	return culture_index


static func has_culture_id(culture_id: int) -> bool:
	return get_culture_index_by_id(culture_id) >= 0


static func is_valid_culture_id(culture_id: int) -> bool:
	return has_culture_id(culture_id)


static func get_culture_by_id(culture_id: int) -> Dictionary:
	var culture_index := get_culture_index_by_id(culture_id)

	if culture_index < 0:
		return {}

	return cultures[culture_index].duplicate(true)


static func get_culture_name_by_id(culture_id: int) -> String:
	var culture := get_culture_by_id(culture_id)

	if culture.is_empty():
		return ""

	return str(culture.get("name", ""))


static func get_culture_snapshot() -> Array:
	var culture_snapshot: Array = []

	for raw_culture in cultures:
		if not raw_culture is Dictionary:
			continue

		culture_snapshot.append(raw_culture.duplicate(true))

	return culture_snapshot


static func create_culture(culture_name: String) -> Dictionary:
	var culture := CultureDataScript.make_culture({
		"id": next_culture_id,
		"name": culture_name,
	})

	if culture.is_empty():
		return {}

	var culture_id := int(culture["id"])

	if culture_index_by_id.has(culture_id):
		push_error(
			"Cannot create culture because ID "
			+ str(culture_id)
			+ " is already registered."
		)
		return {}

	cultures.append(culture)
	culture_index_by_id[culture_id] = cultures.size() - 1
	next_culture_id += 1

	return culture.duplicate(true)


static func reset_founding_identity_state() -> void:
	official_city_name = ""
	official_founding_culture_id = INVALID_CULTURE_ID
	cultures.clear()
	culture_index_by_id.clear()
	next_culture_id = 1


static func get_official_city_name() -> String:
	return official_city_name


static func get_official_founding_culture_id() -> int:
	return official_founding_culture_id


static func get_official_founding_culture() -> Dictionary:
	return get_culture_by_id(official_founding_culture_id)


static func get_official_founding_culture_name() -> String:
	return get_culture_name_by_id(official_founding_culture_id)


static func has_official_founding_identity() -> bool:
	return (
		is_valid_founding_name(official_city_name)
		and official_city_name
		== normalize_official_city_name(official_city_name)
		and has_culture_id(official_founding_culture_id)
	)


static func _make_city_start_region_tiles(
	source_world: WorldData,
	region_top_left: Vector2i,
	region_size: int
) -> Array:
	if source_world == null or region_size <= 0:
		return []

	var region_bottom_right := (
		region_top_left
		+ Vector2i(region_size - 1, region_size - 1)
	)

	if (
		not source_world.is_in_bounds(
			region_top_left.x,
			region_top_left.y
		)
		or not source_world.is_in_bounds(
			region_bottom_right.x,
			region_bottom_right.y
		)
	):
		return []

	var region_tiles: Array = []

	for y_offset in range(region_size):
		var row: Array = []

		for x_offset in range(region_size):
			var tile_x: int = region_top_left.x + x_offset
			var tile_y: int = region_top_left.y + y_offset
			var source_tile := (
				source_world.get_tile_for_internal_read(
					tile_x,
					tile_y
				).duplicate(true)
			)

			source_tile["source_world_x"] = tile_x
			source_tile["source_world_y"] = tile_y
			row.append(source_tile)

		region_tiles.append(row)

	return region_tiles


static func store_city_start_region(
	source_world: WorldData,
	region_top_left: Vector2i,
	region_center: Vector2i,
	region_size: int
) -> bool:
	var region_tiles := _make_city_start_region_tiles(
		source_world,
		region_top_left,
		region_size
	)

	if region_tiles.is_empty():
		return false

	city_start_world_seed = source_world.seed
	city_start_region_center = region_center
	city_start_region_top_left = region_top_left
	city_start_region_size = region_size
	city_start_tiles = region_tiles
	return true


static func has_city_start_region() -> bool:
	if city_start_region_size <= 0:
		return false

	if city_start_tiles.size() != city_start_region_size:
		return false

	return true

static func lock_world_save(values: Dictionary) -> bool:
	var required_keys: Array[String] = [
		"source_world",
		"region_top_left",
		"region_center",
		"region_size",
		"world_scene_path",
		"city_scene_path",
		"city_name",
		"culture_name",
	]

	for key in required_keys:
		if not values.has(key):
			push_error(
				"WorldData.lock_world_save is missing required key: "
				+ key
			)
			return false

	if not values["source_world"] is WorldData:
		push_error(
			"WorldData.lock_world_save source_world must be WorldData."
		)
		return false

	if not values["region_top_left"] is Vector2i:
		push_error(
			"WorldData.lock_world_save region_top_left must be Vector2i."
		)
		return false

	if not values["region_center"] is Vector2i:
		push_error(
			"WorldData.lock_world_save region_center must be Vector2i."
		)
		return false

	if not values["region_size"] is int:
		push_error(
			"WorldData.lock_world_save region_size must be an integer."
		)
		return false

	if not values["world_scene_path"] is String:
		push_error(
			"WorldData.lock_world_save world_scene_path must be a String."
		)
		return false

	if not values["city_scene_path"] is String:
		push_error(
			"WorldData.lock_world_save city_scene_path must be a String."
		)
		return false

	if not values["city_name"] is String:
		push_error(
			"WorldData.lock_world_save city_name must be a String."
		)
		return false

	if not values["culture_name"] is String:
		push_error(
			"WorldData.lock_world_save culture_name must be a String."
		)
		return false

	var source_world: WorldData = values["source_world"]
	var region_top_left: Vector2i = values["region_top_left"]
	var region_center: Vector2i = values["region_center"]
	var region_size: int = values["region_size"]
	var world_scene_path: String = values["world_scene_path"]
	var city_scene_path: String = values["city_scene_path"]
	var raw_city_name: String = values["city_name"]
	var raw_culture_name: String = values["culture_name"]
	var city_name := normalize_official_city_name(raw_city_name)
	var culture_name := CultureDataScript.normalize_culture_name(
		raw_culture_name
	)

	if region_size <= 0:
		push_error("WorldData.lock_world_save region_size must be positive.")
		return false

	var expected_region_center := (
		region_top_left
		+ Vector2i(int(region_size / 2), int(region_size / 2))
	)

	if region_center != expected_region_center:
		push_error(
			"WorldData.lock_world_save region_center is inconsistent "
			+ "with region_top_left and region_size."
		)
		return false

	if world_scene_path.strip_edges().is_empty():
		push_error(
			"WorldData.lock_world_save world_scene_path must not be blank."
		)
		return false

	if city_scene_path.strip_edges().is_empty():
		push_error(
			"WorldData.lock_world_save city_scene_path must not be blank."
		)
		return false

	if not is_valid_founding_name(city_name):
		push_error(
			"WorldData.lock_world_save city_name must contain 1 to "
			+ str(MAX_FOUNDING_NAME_LENGTH)
			+ " visible characters."
		)
		return false

	if not is_valid_founding_name(culture_name):
		push_error(
			"WorldData.lock_world_save culture_name must contain 1 to "
			+ str(MAX_FOUNDING_NAME_LENGTH)
			+ " visible characters."
		)
		return false

	var prepared_region_tiles := _make_city_start_region_tiles(
		source_world,
		region_top_left,
		region_size
	)

	if prepared_region_tiles.is_empty():
		push_error(
			"WorldData.lock_world_save selected region is outside the world."
		)
		return false

	if save_locked:
		return (
			has_active_world_save()
			and official_world == source_world
			and official_selected_region_center == region_center
			and official_selected_region_top_left == region_top_left
			and official_region_size == region_size
			and official_world_scene_path == world_scene_path
			and official_city_scene_path == city_scene_path
			and official_city_name == city_name
			and get_official_founding_culture_name() == culture_name
		)

	var founding_culture := create_culture(culture_name)

	if founding_culture.is_empty():
		return false

	official_world = source_world
	official_selected_region_center = region_center
	official_selected_region_top_left = region_top_left
	official_region_size = region_size
	official_world_scene_path = world_scene_path
	official_city_scene_path = city_scene_path
	official_city_name = city_name
	official_founding_culture_id = int(founding_culture["id"])

	city_start_world_seed = source_world.seed
	city_start_region_center = region_center
	city_start_region_top_left = region_top_left
	city_start_region_size = region_size
	city_start_tiles = prepared_region_tiles

	save_locked = true
	return true


static func has_active_world_save() -> bool:
	return save_locked and official_world != null


static func has_active_city_save() -> bool:
	return WorldPoliticalState.get_current_city_world() != null


static func store_city_world_save(city_world: WorldData, city_seed: int) -> void:
	WorkplaceProductionSystem.clear_resource_source_evaluation_cache()
	WorldPoliticalState.store_current_city_world(city_world, city_seed)
	MapTextureCacheStateScript.clear_city_cache()


static func _clear_player_city_mirrors() -> void:
	player_city_founded = false
	player_city_foundation_top_left = Vector2i(-1, -1)
	player_city_foundation_size = Vector2i.ZERO


static func _synchronize_player_city_mirrors_from_capital_state() -> void:
	_apply_player_city_mirrors_from_city_state(
		WorldPoliticalState.get_player_capital_city_simulation_state()
	)


static func _apply_player_city_mirrors_from_city_state(
	capital_state: CitySettlementSimulationState
) -> void:
	if capital_state == null or not capital_state.is_city_founded():
		_clear_player_city_mirrors()
		return

	player_city_founded = true
	if not capital_state.has_city_foundation_footprint():
		player_city_foundation_top_left = Vector2i(-1, -1)
		player_city_foundation_size = Vector2i.ZERO
		return

	player_city_foundation_top_left = capital_state.city_runtime_data.get(
		"foundation_top_left",
		Vector2i(-1, -1)
	)
	player_city_foundation_size = capital_state.city_runtime_data.get(
		"foundation_size",
		Vector2i.ZERO
	)


static func synchronize_player_city_mirrors_for_settlement(
	settlement_context: SettlementSimulationContext,
	city_state: CitySettlementSimulationState
) -> bool:
	if (
		settlement_context == null
		or city_state == null
		or not settlement_context.is_player_polity
		or not settlement_context.is_capital
		or settlement_context.settlement_id
		!= WorldPoliticalState.get_player_capital_settlement_id()
		or not is_same(
			settlement_context.get_city_simulation_state(),
			city_state
		)
		or not is_same(
			WorldPoliticalState.get_city_simulation_state(
				settlement_context.settlement_id
			),
			city_state
		)
	):
		return false

	_apply_player_city_mirrors_from_city_state(city_state)
	return true


static func found_player_city(values: Dictionary) -> void:
	if has_player_city():
		return

	if not has_active_world_save():
		push_error(
			"Cannot found the player city before the world save is locked."
		)
		return

	if not has_official_founding_identity():
		push_error(
			"Cannot found the player city without a committed city name "
			+ "and founding culture."
		)
		return

	var required_keys: Array[String] = [
		"city_world_seed",
		"city_map_size",
	]

	for key in required_keys:
		if not values.has(key):
			push_error(
				"WorldData.found_player_city is missing required key: "
				+ key
			)
			return

	if not values["city_map_size"] is Vector2i:
		push_error(
			"WorldData.found_player_city city_map_size must be Vector2i."
		)
		return

	var foundation_top_left_value = values.get(
		"foundation_top_left",
		Vector2i(-1, -1)
	)
	var foundation_size_value = values.get(
		"foundation_size",
		Vector2i.ZERO
	)

	if not foundation_top_left_value is Vector2i:
		push_error(
			"WorldData.found_player_city foundation_top_left must be Vector2i."
		)
		return

	if not foundation_size_value is Vector2i:
		push_error(
			"WorldData.found_player_city foundation_size must be Vector2i."
		)
		return

	var city_world_seed := int(values["city_world_seed"])
	var city_map_size: Vector2i = values["city_map_size"]
	var foundation_top_left: Vector2i = foundation_top_left_value
	var foundation_size: Vector2i = foundation_size_value

	if not WorldPoliticalState.synchronize_foundation_with_world_data():
		push_error("Cannot found the player city without its capital settlement.")
		return

	var capital_settlement_id := (
		WorldPoliticalState.get_player_capital_settlement_id()
	)
	if not WorldPoliticalState.found_city_settlement(
		capital_settlement_id,
		{
			"city_world_seed": city_world_seed,
			"city_map_size": city_map_size,
			"foundation_top_left": foundation_top_left,
			"foundation_size": foundation_size,
			"primary_culture_id": get_official_founding_culture_id(),
			"can_build": true,
		}
	):
		push_error("Player-capital foundation failed without committing global state.")
		return

	var capital_state = (
		WorldPoliticalState.get_player_capital_city_simulation_state()
	)
	if capital_state == null:
		push_error("Founded player capital has no city simulation state.")
		return

	_synchronize_player_city_mirrors_from_capital_state()

static func has_player_city_foundation() -> bool:
	_synchronize_player_city_mirrors_from_capital_state()
	var capital_state = (
		WorldPoliticalState.get_player_capital_city_simulation_state()
	)
	return capital_state != null and capital_state.has_city_foundation_footprint()

static func has_player_city() -> bool:
	_synchronize_player_city_mirrors_from_capital_state()
	var capital_state = (
		WorldPoliticalState.get_player_capital_city_simulation_state()
	)
	return capital_state != null and capital_state.is_city_founded()


static func can_build_in_city() -> bool:
	var city_state = WorldPoliticalState.get_active_city_simulation_state()
	return city_state != null and city_state.can_build_city_objects()

#endregion

#region Resource and Surface Feature Metadata







static func get_city_surface_feature(tile: Dictionary) -> String:
	return str(
		tile.get(
			"surface_feature",
			CITY_SURFACE_FEATURE_NONE
		)
	)


static func is_city_surface_feature(surface_feature: String) -> bool:
	return (
		surface_feature == CITY_SURFACE_FEATURE_TREE
		or surface_feature == CITY_SURFACE_FEATURE_ROCK
	)


static func get_city_surface_feature_resource_type(
	surface_feature: String
) -> String:
	match surface_feature:
		CITY_SURFACE_FEATURE_TREE:
			return RESOURCE_LUMBER

		CITY_SURFACE_FEATURE_ROCK:
			return RESOURCE_STONE

	return RESOURCE_NONE


static func clear_city_surface_features_at_tiles(
	city_world: WorldData,
	raw_tile_positions: Array
) -> int:
	if city_world == null:
		return 0

	var cleared_count := 0
	var visited_tiles: Dictionary = {}

	for raw_tile_position in raw_tile_positions:
		if not raw_tile_position is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile_position

		if visited_tiles.has(tile_position):
			continue

		visited_tiles[tile_position] = true

		if not city_world.is_in_bounds(
			tile_position.x,
			tile_position.y
		):
			continue

		var surface_feature := get_city_surface_feature(
			city_world.get_tile_for_internal_read(
				tile_position.x,
				tile_position.y
			)
		)

		if not is_city_surface_feature(surface_feature):
			continue

		if not city_world.remove_tile_surface_feature(
			tile_position,
			surface_feature
		):
			continue

		cleared_count += 1

	return cleared_count

#endregion

#region Citizen and Haul Endpoint Factories





























































static func reset_player_city_state() -> void:
	_clear_player_city_mirrors()

	# Reset the exact player-capital owner without switching presentation to it.
	# The compatibility subsystem reset entry points resolve the active city and
	# therefore must not be used here while an NPC settlement may be active.
	var player_capital_id := (
		WorldPoliticalState.get_player_capital_settlement_id()
	)
	if player_capital_id <= 0:
		return

	WorldPoliticalState.reset_city_simulation_runtime_state(player_capital_id)
	WorkplaceProductionSystem.clear_resource_source_evaluation_cache()

#endregion

#region City Object Placement and Traversal




static func reset_runtime_session_state(clear_debug: bool = false) -> void:
	reset_world_session_state()
	reset_city_session_state()
	reset_player_city_state()
	clear_visual_texture_caches()

	if clear_debug:
		debug_mode_enabled = false

	# This entry point starts a wholly new runtime session. Clear compatibility
	# state first while the current settlement still resolves, then discard every
	# active and inactive settlement-owned state together.
	WorldPoliticalState.reset_state()

static func reset_world_session_state() -> void:
	save_locked = false
	official_world = null
	official_selected_region_center = Vector2i(-1, -1)
	official_selected_region_top_left = Vector2i(-1, -1)
	official_region_size = 0
	official_world_scene_path = ""
	official_city_scene_path = ""
	city_return_world_scene_path = ""

	reset_founding_identity_state()
	reset_city_start_region_state()
	reset_world_camera_state()
	MapTextureCacheStateScript.clear_world_cache()


static func reset_city_session_state() -> void:
	WorldPoliticalState.clear_current_city_world()

	reset_city_camera_state()
	MapTextureCacheStateScript.clear_city_cache()


static func reset_city_start_region_state() -> void:
	city_start_world_seed = 0
	city_start_region_center = Vector2i(-1, -1)
	city_start_region_top_left = Vector2i(-1, -1)
	city_start_region_size = 0
	city_start_tiles.clear()


static func reset_world_camera_state() -> void:
	MapCameraSessionStateScript.reset_world_camera()


static func reset_city_camera_state() -> void:
	MapCameraSessionStateScript.reset_city_camera()

static func clear_visual_texture_caches() -> void:
	MapTextureCacheStateScript.clear_world_cache()
	MapTextureCacheStateScript.clear_city_cache()

#endregion
