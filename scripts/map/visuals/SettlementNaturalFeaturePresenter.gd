extends Node2D
class_name SettlementNaturalFeaturePresenter

# Retained natural-feature presentation for one explicitly bound settlement
# source. The presenter owns every generated resource, tile index, and canvas
# node in this slice; it never discovers a settlement or mutates its WorldData.

const CityWorldGeneratorScript = preload(
	"res://scripts/city/generation/CityWorldGenerator.gd"
)
const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)

const MAX_CACHED_SETTLEMENTS: int = 8
const TREE_CANOPY_TILE_SCALE: float = 1.30
const TREE_MIN_SCALE_VARIATION: float = 0.92
const TREE_MAX_SCALE_VARIATION: float = 1.08
const TREE_DARK_COLOR := Color(0.12, 0.43, 0.16, 1.0)
const TREE_LIGHT_COLOR := Color(0.30, 0.66, 0.28, 1.0)
const TAIGA_TREE_DARK_COLOR := Color(0.12, 0.29, 0.24, 1.0)
const TAIGA_TREE_LIGHT_COLOR := Color(0.29, 0.47, 0.36, 1.0)
const JUNGLE_TREE_DARK_COLOR := Color(0.055, 0.27, 0.10, 1.0)
const JUNGLE_TREE_LIGHT_COLOR := Color(0.16, 0.49, 0.18, 1.0)
const ROCK_MARKER_TILE_SCALE: float = 0.28
const ROCK_MAX_CENTER_OFFSET_TILES: float = 0.30
const TREE_ROTATION_SALT: int = 401
const TREE_SCALE_SALT: int = 409
const TREE_COLOR_SALT: int = 419
const ROCK_OFFSET_X_SALT: int = 431
const ROCK_OFFSET_Y_SALT: int = 433

# Immutable GPU inputs and exact-source presentation caches are shared only to
# avoid rebuilding retained resources when a settlement view is revisited.
static var shared_feature_resources: Dictionary = {}
static var cache_by_settlement_id: Dictionary = {}
static var cache_recency: Array[int] = []

var presentation_binding: SettlementPresentationBindingScript
var source_world: WorldData
var source_world_instance_id: int = 0
var settlement_id: int = SettlementData.INVALID_SETTLEMENT_ID
var settlement_seed: int = 0
var binding_generation: int = 0
var highest_accepted_binding_generation: int = 0
var tile_size: int = 0
var view_mode: int = MapVisuals.ViewMode.BIOME
var cache_reused_on_entry: bool = false

var white_texture: ImageTexture
var tree_mesh: ArrayMesh
var rock_mesh: ArrayMesh
var tree_multimesh: MultiMesh
var rock_multimesh: MultiMesh
var tree_multimesh_instance: MultiMeshInstance2D
var rock_multimesh_instance: MultiMeshInstance2D
var tree_index_by_tile: Dictionary = {}
var tree_tile_by_index: Array[Vector2i] = []
var rock_index_by_tile: Dictionary = {}
var rock_tile_by_index: Array[Vector2i] = []


func can_bind_settlement_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	var target_world := _get_binding_world(binding)
	var target_seed := _get_binding_seed(binding)
	if (
		target_world == null
		or target_world.width <= 0
		or target_world.height <= 0
		or binding.settlement_id <= 0
		or target_seed <= 0
		or binding.generation <= 0
	):
		return false

	if binding.generation > highest_accepted_binding_generation:
		return true

	# Repeating the exact current bind is harmless. Equal-generation source
	# replacement and every older generation are rejected transactionally.
	return is_bound_to_settlement_presentation(binding)


func bind_settlement_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	if not can_bind_settlement_presentation(binding):
		return false

	if is_bound_to_settlement_presentation(binding):
		return true

	var target_world := _get_binding_world(binding)
	var target_seed := _get_binding_seed(binding)
	var same_source := _matches_source_identity(
		target_world,
		binding.settlement_id,
		target_seed
	)
	presentation_binding = binding
	source_world = target_world
	source_world_instance_id = int(target_world.get_instance_id())
	settlement_id = binding.settlement_id
	settlement_seed = target_seed
	binding_generation = binding.generation
	highest_accepted_binding_generation = binding.generation
	cache_reused_on_entry = false
	if not same_source:
		_clear_retained_feature_state()
	return true


func is_bound_to_settlement_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	var target_world := _get_binding_world(binding)
	var target_seed := _get_binding_seed(binding)
	return (
		presentation_binding != null
		and binding != null
		and presentation_binding.matches_binding(binding)
		and source_world != null
		and target_world != null
		and is_same(source_world, target_world)
		and source_world_instance_id == int(target_world.get_instance_id())
		and settlement_id == binding.settlement_id
		and settlement_seed == target_seed
		and binding_generation == binding.generation
		and binding_generation > 0
	)


func accepts_generation(target_generation: int) -> bool:
	return (
		presentation_binding != null
		and presentation_binding.is_valid()
		and source_world != null
		and target_generation > 0
		and target_generation == binding_generation
		and source_world_instance_id == int(source_world.get_instance_id())
	)


func reset_presentation(target_generation: int) -> bool:
	if not accepts_generation(target_generation):
		return false
	_clear_retained_feature_state()
	presentation_binding = null
	source_world = null
	source_world_instance_id = 0
	settlement_id = SettlementData.INVALID_SETTLEMENT_ID
	settlement_seed = 0
	binding_generation = 0
	tile_size = 0
	cache_reused_on_entry = false
	return true


func _get_binding_world(
	binding: SettlementPresentationBindingScript
) -> WorldData:
	if (
		binding == null
		or not binding.is_valid()
		or not binding.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_SETTLEMENT_WORLD
		)
	):
		return null
	var raw_world = binding.get_backend_capability(
		SettlementPresentationBindingScript.CAPABILITY_SETTLEMENT_WORLD
	)
	return raw_world if raw_world is WorldData else null


func _get_binding_seed(binding: SettlementPresentationBindingScript) -> int:
	if (
		binding == null
		or not binding.is_valid()
		or not binding.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_DETERMINISTIC_SEED
		)
	):
		return 0
	return int(binding.get_backend_capability(
		SettlementPresentationBindingScript.CAPABILITY_DETERMINISTIC_SEED
	))


func _matches_source_identity(
	target_world: WorldData,
	target_settlement_id: int,
	target_seed: int
) -> bool:
	return (
		source_world != null
		and target_world != null
		and is_same(source_world, target_world)
		and source_world_instance_id == int(target_world.get_instance_id())
		and settlement_id == target_settlement_id
		and settlement_seed == target_seed
	)


func initialize_presentation(
	target_generation: int,
	target_tile_size: int,
	target_view_mode: int,
	prepared_payload: Dictionary = {}
) -> bool:
	if not accepts_generation(target_generation) or target_tile_size <= 0:
		return false
	tile_size = target_tile_size
	view_mode = target_view_mode
	_ensure_shared_feature_resources()
	_create_feature_instances()
	cache_reused_on_entry = try_load_cache(target_generation)
	if not cache_reused_on_entry:
		return rebuild(target_generation, prepared_payload)
	return true


func try_load_cache(target_generation: int) -> bool:
	if not accepts_generation(target_generation) or tile_size <= 0:
		return false
	var raw_entry = cache_by_settlement_id.get(settlement_id)
	if not raw_entry is Dictionary:
		return false
	var cache_entry: Dictionary = raw_entry
	var source_ref = cache_entry.get("source_ref")
	var cached_world = (
		source_ref.get_ref()
		if source_ref is WeakRef
		else null
	)
	if (
		cached_world == null
		or not is_same(cached_world, source_world)
		or int(cache_entry.get("source_world_instance_id", 0))
		!= source_world_instance_id
		or int(cache_entry.get("tile_data_version", -1))
		!= source_world.tile_data_version
		or int(cache_entry.get("surface_feature_change_version", -1))
		!= source_world.city_surface_feature_change_version
		or int(cache_entry.get("settlement_seed", 0)) != settlement_seed
		or int(cache_entry.get("tile_size", 0)) != tile_size
		or not cache_entry.get("tree_multimesh") is MultiMesh
		or not cache_entry.get("rock_multimesh") is MultiMesh
		or not cache_entry.get("tree_index_by_tile") is Dictionary
		or not cache_entry.get("tree_tile_by_index") is Array
		or not cache_entry.get("rock_index_by_tile") is Dictionary
		or not cache_entry.get("rock_tile_by_index") is Array
	):
		return false

	tree_multimesh = cache_entry["tree_multimesh"]
	rock_multimesh = cache_entry["rock_multimesh"]
	tree_index_by_tile = cache_entry["tree_index_by_tile"].duplicate(false)
	rock_index_by_tile = cache_entry["rock_index_by_tile"].duplicate(false)
	tree_tile_by_index.clear()
	tree_tile_by_index.assign(cache_entry["tree_tile_by_index"])
	rock_tile_by_index.clear()
	rock_tile_by_index.assign(cache_entry["rock_tile_by_index"])
	_touch_cache_recency(settlement_id)
	_refresh_feature_instances()
	return true


func store_cache(target_generation: int) -> bool:
	if (
		not accepts_generation(target_generation)
		or tile_size <= 0
		or tree_multimesh == null
		or rock_multimesh == null
	):
		return false

	cache_by_settlement_id[settlement_id] = {
		"source_ref": weakref(source_world),
		"source_world_instance_id": source_world_instance_id,
		"tile_data_version": source_world.tile_data_version,
		"surface_feature_change_version": (
			source_world.city_surface_feature_change_version
		),
		"settlement_seed": settlement_seed,
		"tile_size": tile_size,
		"tree_multimesh": tree_multimesh,
		"rock_multimesh": rock_multimesh,
		"tree_index_by_tile": tree_index_by_tile.duplicate(false),
		"tree_tile_by_index": tree_tile_by_index.duplicate(),
		"rock_index_by_tile": rock_index_by_tile.duplicate(false),
		"rock_tile_by_index": rock_tile_by_index.duplicate(),
	}
	_touch_cache_recency(settlement_id)
	_prune_cache()
	return true


func rebuild(
	target_generation: int,
	prepared_payload: Dictionary = {}
) -> bool:
	if not accepts_generation(target_generation) or tile_size <= 0:
		return false
	tree_index_by_tile.clear()
	tree_tile_by_index.clear()
	rock_index_by_tile.clear()
	rock_tile_by_index.clear()

	var tree_tiles: Array[Vector2i] = []
	var rock_tiles: Array[Vector2i] = []
	var prepared_tree_tiles = prepared_payload.get(
		"natural_feature_tree_tiles",
		prepared_payload.get("tree_tiles")
	)
	var prepared_rock_tiles = prepared_payload.get(
		"natural_feature_rock_tiles",
		prepared_payload.get("rock_tiles")
	)
	var prepared_world = prepared_payload.get(
		"source_world",
		prepared_payload.get("city_world")
	)
	var prepared_feature_tile_data_version = prepared_payload.get(
		"feature_tile_data_version"
	)
	var prepared_surface_feature_change_version = prepared_payload.get(
		"surface_feature_change_version",
		prepared_payload.get("city_surface_feature_change_version")
	)
	var can_use_prepared_feature_tiles := (
		prepared_world is WorldData
		and is_same(prepared_world, source_world)
		and typeof(prepared_feature_tile_data_version) == TYPE_INT
		and int(prepared_feature_tile_data_version)
		== source_world.tile_data_version
		and typeof(prepared_surface_feature_change_version) == TYPE_INT
		and int(prepared_surface_feature_change_version)
		== source_world.city_surface_feature_change_version
	)

	if (
		can_use_prepared_feature_tiles
		and prepared_tree_tiles is Array
		and prepared_rock_tiles is Array
	):
		for raw_tile in prepared_tree_tiles:
			if raw_tile is Vector2i:
				tree_tiles.append(raw_tile)
		for raw_tile in prepared_rock_tiles:
			if raw_tile is Vector2i:
				rock_tiles.append(raw_tile)
	elif (
		source_world.prepared_city_feature_tile_data_version
		== source_world.tile_data_version
	):
		tree_tiles.assign(source_world.prepared_city_tree_tiles)
		rock_tiles.assign(source_world.prepared_city_rock_tiles)
	else:
		for y in range(source_world.height):
			var row: Array = source_world.tiles[y]
			for x in range(source_world.width):
				match WorldData.get_city_surface_feature(row[x]):
					WorldData.CITY_SURFACE_FEATURE_TREE:
						tree_tiles.append(Vector2i(x, y))
					WorldData.CITY_SURFACE_FEATURE_ROCK:
						rock_tiles.append(Vector2i(x, y))

	tree_multimesh = _create_feature_multimesh(
		tree_mesh,
		tree_tiles.size()
	)
	rock_multimesh = _create_feature_multimesh(
		rock_mesh,
		rock_tiles.size()
	)
	_populate_tree_multimesh(tree_tiles)
	_populate_rock_multimesh(rock_tiles)
	_refresh_feature_instances()
	return store_cache(target_generation)


func apply_surface_feature_changes(
	target_generation: int,
	changes: Array[Dictionary]
) -> bool:
	if not accepts_generation(target_generation):
		return false
	for change in changes:
		var raw_tile_position = change.get(
			"tile_position",
			Vector2i(-1, -1)
		)
		var previous_feature := str(change.get(
			"previous_feature",
			WorldData.CITY_SURFACE_FEATURE_NONE
		))
		var current_feature := str(change.get(
			"current_feature",
			WorldData.CITY_SURFACE_FEATURE_NONE
		))
		if (
			not raw_tile_position is Vector2i
			or current_feature != WorldData.CITY_SURFACE_FEATURE_NONE
		):
			return false
		if not _remove_feature_instance(previous_feature, raw_tile_position):
			return false
	return true


func set_view_mode(target_generation: int, target_view_mode: int) -> bool:
	if not accepts_generation(target_generation):
		return false
	view_mode = target_view_mode
	_refresh_feature_instance_visibility()
	return true


func should_draw_trees(target_generation: int) -> bool:
	return (
		accepts_generation(target_generation)
		and view_mode != MapVisuals.ViewMode.RESOURCES
	)


func _clear_retained_feature_state() -> void:
	tree_multimesh = null
	rock_multimesh = null
	tree_index_by_tile.clear()
	tree_tile_by_index.clear()
	rock_index_by_tile.clear()
	rock_tile_by_index.clear()
	_refresh_feature_instances()


func _ensure_shared_feature_resources() -> void:
	if not shared_feature_resources.get("white_texture") is ImageTexture:
		var white_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		white_image.fill(Color.WHITE)
		shared_feature_resources["white_texture"] = (
			ImageTexture.create_from_image(white_image)
		)
	if not shared_feature_resources.get("tree_mesh") is ArrayMesh:
		shared_feature_resources["tree_mesh"] = _create_feature_mesh(
			PackedVector2Array([
				Vector2(-0.18, -0.50),
				Vector2(0.10, -0.35),
				Vector2(0.48, -0.30),
				Vector2(0.24, 0.00),
				Vector2(0.50, 0.43),
				Vector2(0.10, 0.39),
				Vector2(-0.18, 0.50),
				Vector2(-0.30, 0.22),
				Vector2(-0.50, 0.00),
				Vector2(-0.25, -0.17),
			])
		)
	if not shared_feature_resources.get("rock_mesh") is ArrayMesh:
		shared_feature_resources["rock_mesh"] = _create_feature_mesh(
			PackedVector2Array([
				Vector2(-0.5, -0.5),
				Vector2(0.5, -0.5),
				Vector2(0.5, 0.5),
				Vector2(-0.5, 0.5),
			])
		)
	white_texture = shared_feature_resources["white_texture"]
	tree_mesh = shared_feature_resources["tree_mesh"]
	rock_mesh = shared_feature_resources["rock_mesh"]


func _create_feature_instances() -> void:
	if rock_multimesh_instance == null:
		rock_multimesh_instance = MultiMeshInstance2D.new()
		rock_multimesh_instance.name = "SettlementRockMultiMeshInstance"
		rock_multimesh_instance.texture_filter = (
			CanvasItem.TEXTURE_FILTER_NEAREST
		)
		rock_multimesh_instance.z_index = -10
		add_child(rock_multimesh_instance)
	if tree_multimesh_instance == null:
		tree_multimesh_instance = MultiMeshInstance2D.new()
		tree_multimesh_instance.name = "SettlementTreeMultiMeshInstance"
		tree_multimesh_instance.texture_filter = (
			CanvasItem.TEXTURE_FILTER_NEAREST
		)
		tree_multimesh_instance.z_index = 11
		add_child(tree_multimesh_instance)
	_refresh_feature_instances()


func _refresh_feature_instances() -> void:
	if rock_multimesh_instance != null:
		rock_multimesh_instance.multimesh = rock_multimesh
		rock_multimesh_instance.texture = white_texture
	if tree_multimesh_instance != null:
		tree_multimesh_instance.multimesh = tree_multimesh
		tree_multimesh_instance.texture = white_texture
	_refresh_feature_instance_visibility()


func _refresh_feature_instance_visibility() -> void:
	if rock_multimesh_instance != null:
		rock_multimesh_instance.visible = (
			rock_multimesh != null
			and rock_multimesh.visible_instance_count > 0
		)
	if tree_multimesh_instance != null:
		tree_multimesh_instance.visible = (
			should_draw_trees(binding_generation)
			and tree_multimesh != null
			and tree_multimesh.visible_instance_count > 0
		)


func _create_feature_mesh(points: PackedVector2Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < 3:
		return mesh
	var triangle_indices := Geometry2D.triangulate_polygon(points)
	if triangle_indices.is_empty():
		push_error("Could not triangulate a settlement natural-feature polygon.")
		return mesh
	var vertices := PackedVector3Array()
	var vertex_colors := PackedColorArray()
	var texture_coordinates := PackedVector2Array()
	for point in points:
		vertices.append(Vector3(point.x, point.y, 0.0))
		vertex_colors.append(Color.WHITE)
		texture_coordinates.append(point + Vector2(0.5, 0.5))
	var surface_arrays: Array = []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = vertices
	surface_arrays[Mesh.ARRAY_COLOR] = vertex_colors
	surface_arrays[Mesh.ARRAY_TEX_UV] = texture_coordinates
	surface_arrays[Mesh.ARRAY_INDEX] = triangle_indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
	return mesh


func _create_feature_multimesh(mesh: Mesh, instance_count: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = maxi(instance_count, 0)
	multimesh.visible_instance_count = maxi(instance_count, 0)
	return multimesh


func _populate_tree_multimesh(tree_tiles: Array[Vector2i]) -> void:
	var buffer := PackedFloat32Array()
	buffer.resize(tree_tiles.size() * 12)
	var tile_size_float := float(tile_size)
	for tree_index in range(tree_tiles.size()):
		var tree_tile := tree_tiles[tree_index]
		var tree_data: Dictionary = source_world.tiles[tree_tile.y][tree_tile.x]
		var tile_center := Vector2(
			(float(tree_tile.x) + 0.5) * tile_size_float,
			(float(tree_tile.y) + 0.5) * tile_size_float
		)
		var rotation_ratio := CityWorldGeneratorScript.get_deterministic_tile_unit_value(
			settlement_seed, tree_tile.x, tree_tile.y, TREE_ROTATION_SALT
		)
		var scale_ratio := CityWorldGeneratorScript.get_deterministic_tile_unit_value(
			settlement_seed, tree_tile.x, tree_tile.y, TREE_SCALE_SALT
		)
		var color_ratio := CityWorldGeneratorScript.get_deterministic_tile_unit_value(
			settlement_seed, tree_tile.x, tree_tile.y, TREE_COLOR_SALT
		)
		var canopy_scale := (
			tile_size_float
			* TREE_CANOPY_TILE_SCALE
			* lerpf(TREE_MIN_SCALE_VARIATION, TREE_MAX_SCALE_VARIATION, scale_ratio)
		)
		_write_multimesh_instance_to_buffer(
			buffer,
			tree_index,
			Transform2D(
				rotation_ratio * TAU,
				Vector2.ONE * canopy_scale,
				0.0,
				tile_center
			),
			_get_tree_canopy_color(tree_data, color_ratio)
		)
		tree_index_by_tile[tree_tile] = tree_index
		tree_tile_by_index.append(tree_tile)
	if tree_multimesh != null and not buffer.is_empty():
		tree_multimesh.buffer = buffer


func _populate_rock_multimesh(rock_tiles: Array[Vector2i]) -> void:
	var buffer := PackedFloat32Array()
	buffer.resize(rock_tiles.size() * 12)
	var tile_size_float := float(tile_size)
	var rock_color := MapVisuals.get_resource_color(WorldData.RESOURCE_STONE)
	for rock_index in range(rock_tiles.size()):
		var rock_tile := rock_tiles[rock_index]
		var tile_center := Vector2(
			(float(rock_tile.x) + 0.5) * tile_size_float,
			(float(rock_tile.y) + 0.5) * tile_size_float
		)
		var offset_x_ratio := CityWorldGeneratorScript.get_deterministic_tile_unit_value(
			settlement_seed, rock_tile.x, rock_tile.y, ROCK_OFFSET_X_SALT
		)
		var offset_y_ratio := CityWorldGeneratorScript.get_deterministic_tile_unit_value(
			settlement_seed, rock_tile.x, rock_tile.y, ROCK_OFFSET_Y_SALT
		)
		var rock_offset := Vector2(
			lerpf(
				-ROCK_MAX_CENTER_OFFSET_TILES,
				ROCK_MAX_CENTER_OFFSET_TILES,
				offset_x_ratio
			),
			lerpf(
				-ROCK_MAX_CENTER_OFFSET_TILES,
				ROCK_MAX_CENTER_OFFSET_TILES,
				offset_y_ratio
			)
		) * tile_size_float
		_write_multimesh_instance_to_buffer(
			buffer,
			rock_index,
			Transform2D(
				0.0,
				Vector2.ONE * tile_size_float * ROCK_MARKER_TILE_SCALE,
				0.0,
				tile_center + rock_offset
			),
			rock_color
		)
		rock_index_by_tile[rock_tile] = rock_index
		rock_tile_by_index.append(rock_tile)
	if rock_multimesh != null and not buffer.is_empty():
		rock_multimesh.buffer = buffer


func _write_multimesh_instance_to_buffer(
	buffer: PackedFloat32Array,
	instance_index: int,
	transform: Transform2D,
	color: Color
) -> void:
	var offset := instance_index * 12
	buffer[offset] = transform.x.x
	buffer[offset + 1] = transform.y.x
	buffer[offset + 2] = 0.0
	buffer[offset + 3] = transform.origin.x
	buffer[offset + 4] = transform.x.y
	buffer[offset + 5] = transform.y.y
	buffer[offset + 6] = 0.0
	buffer[offset + 7] = transform.origin.y
	buffer[offset + 8] = color.r
	buffer[offset + 9] = color.g
	buffer[offset + 10] = color.b
	buffer[offset + 11] = color.a


func _get_tree_canopy_color(tile: Dictionary, color_ratio: float) -> Color:
	var dark_color := TREE_DARK_COLOR
	var light_color := TREE_LIGHT_COLOR
	match str(tile.get("biome", "")):
		WorldData.BIOME_TAIGA:
			dark_color = TAIGA_TREE_DARK_COLOR
			light_color = TAIGA_TREE_LIGHT_COLOR
		WorldData.BIOME_JUNGLE:
			dark_color = JUNGLE_TREE_DARK_COLOR
			light_color = JUNGLE_TREE_LIGHT_COLOR
	return dark_color.lerp(light_color, color_ratio)


func _remove_feature_instance(
	surface_feature: String,
	tile_position: Vector2i
) -> bool:
	var multimesh: MultiMesh
	var index_by_tile: Dictionary
	var tile_by_index: Array[Vector2i]
	match surface_feature:
		WorldData.CITY_SURFACE_FEATURE_TREE:
			multimesh = tree_multimesh
			index_by_tile = tree_index_by_tile
			tile_by_index = tree_tile_by_index
		WorldData.CITY_SURFACE_FEATURE_ROCK:
			multimesh = rock_multimesh
			index_by_tile = rock_index_by_tile
			tile_by_index = rock_tile_by_index
		_:
			return false
	if multimesh == null or not index_by_tile.has(tile_position):
		return false
	var removed_index := int(index_by_tile[tile_position])
	var last_index := tile_by_index.size() - 1
	if removed_index < 0 or removed_index > last_index:
		return false
	if removed_index != last_index:
		var last_tile := tile_by_index[last_index]
		multimesh.set_instance_transform_2d(
			removed_index,
			multimesh.get_instance_transform_2d(last_index)
		)
		multimesh.set_instance_color(
			removed_index,
			multimesh.get_instance_color(last_index)
		)
		index_by_tile[last_tile] = removed_index
		tile_by_index[removed_index] = last_tile
	index_by_tile.erase(tile_position)
	tile_by_index.pop_back()
	multimesh.visible_instance_count = tile_by_index.size()
	_refresh_feature_instance_visibility()
	return true


static func _touch_cache_recency(target_settlement_id: int) -> void:
	cache_recency.erase(target_settlement_id)
	cache_recency.append(target_settlement_id)


static func _prune_cache() -> void:
	while cache_recency.size() > MAX_CACHED_SETTLEMENTS:
		var evicted_settlement_id: int = cache_recency.pop_front()
		cache_by_settlement_id.erase(evicted_settlement_id)
