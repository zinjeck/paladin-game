extends RefCounted
class_name CityWorkplaceZoneOverlayCache

const TEXTURE_TARGET_PIXELS_PER_TILE: int = 8
const TEXTURE_MAXIMUM_DIMENSION: int = 1024
const TEXTURE_BORDER_PIXELS: int = 1
const PREVIEW_MAGENTA_FILL_COLOR: Color = (
	Color(1.0, 0.0, 1.0, 0.44)
)
const PREVIEW_MAGENTA_BORDER_COLOR: Color = (
	Color(1.0, 0.0, 1.0, 0.72)
)
const PREVIEW_RED_FILL_COLOR: Color = (
	Color(1.0, 0.0, 0.0, 0.40)
)
const PREVIEW_RED_BORDER_COLOR: Color = (
	Color(1.0, 0.0, 0.0, 0.72)
)
const SELECTED_RESOURCE_COLOR: Color = (
	Color(1.0, 0.0, 1.0, 0.42)
)
const SELECTED_BORDER_COLOR: Color = (
	Color(1.0, 0.0, 1.0, 0.72)
)

var _preview_cache: Dictionary = {}
var _selected_cache: Dictionary = {}


func invalidate_all() -> void:
	_invalidate_cache(_preview_cache)
	_invalidate_cache(_selected_cache)


func prepare(
	city_object: Dictionary,
	preview_mode: bool,
	city_world: WorldData,
	city_tile_size: int
) -> Dictionary:
	return _get_cached(
		city_object,
		preview_mode,
		city_world,
		city_tile_size,
		true
	)


func has_cached_zone(
	city_object: Dictionary,
	preview_mode: bool,
	city_world: WorldData
) -> bool:
	var render_cache := _get_cached(
		city_object,
		preview_mode,
		city_world,
		0,
		false
	)

	return bool(render_cache.get("has_zone", false))


func draw_cached(
	city_object: Dictionary,
	preview_mode: bool,
	city_world: WorldData,
	draw_target: CanvasItem
) -> bool:
	var render_cache := _get_cached(
		city_object,
		preview_mode,
		city_world,
		0,
		false
	)

	if not bool(render_cache.get("has_zone", false)):
		return false

	_draw_render_cache(
		render_cache,
		draw_target
	)

	# Preserve the renderer contract: true means this object has a prepared
	# environmental zone, even if an invalid texture cannot be drawn.
	return true


func _draw_render_cache(
	render_cache: Dictionary,
	draw_target: CanvasItem
) -> void:
	var raw_texture = render_cache.get(
		"texture",
		null
	)

	if not raw_texture is Texture2D:
		return

	var overlay_texture := raw_texture as Texture2D
	var world_rect: Rect2 = render_cache.get(
		"world_rect",
		Rect2()
	)

	if (
		world_rect.size.x <= 0.0
		or world_rect.size.y <= 0.0
	):
		return

	draw_target.draw_texture_rect(
		overlay_texture,
		world_rect,
		false
	)


func _invalidate_cache(render_cache: Dictionary) -> void:
	if render_cache.is_empty():
		return

	# Tile-data versions never use negative values.
	# This forces one rebuild while preserving allocated resources.
	render_cache["tile_data_version"] = -2


func _get_cached(
	city_object: Dictionary,
	preview_mode: bool,
	city_world: WorldData,
	city_tile_size: int,
	allow_rebuild: bool
) -> Dictionary:
	var object_id := int(
		city_object.get("id", -1)
	)
	var object_type := str(
		city_object.get("type", "")
	)
	var top_left: Vector2i = city_object.get(
		"top_left",
		Vector2i(-1, -1)
	)
	var size_tiles: Vector2i = city_object.get(
		"size",
		Vector2i.ZERO
	)
	var footprint_tiles := (
		WorldData.get_city_object_footprint_tiles(
			city_object
		)
	)
	var footprint_hash_value := int(
		hash(footprint_tiles)
	)
	var tile_data_version := -1

	if city_world != null:
		tile_data_version = (
			city_world.tile_data_version
		)

	var active_cache := (
		_preview_cache
		if preview_mode
		else _selected_cache
	)

	if _cache_matches(
		active_cache,
		preview_mode,
		object_id,
		object_type,
		top_left,
		size_tiles,
		footprint_hash_value,
		tile_data_version
	):
		return active_cache

	# Rendering is permitted to read only an already-prepared cache.
	# Texture generation happens before draw callbacks.
	if not allow_rebuild:
		return {}

	var reusable_texture: ImageTexture = null
	var reusable_image: Image = null
	var raw_reusable_texture = active_cache.get(
		"texture",
		null
	)
	var raw_reusable_image = active_cache.get(
		"image",
		null
	)

	if raw_reusable_texture is ImageTexture:
		reusable_texture = raw_reusable_texture

	if raw_reusable_image is Image:
		reusable_image = raw_reusable_image

	var new_cache := {
		"preview_mode": preview_mode,
		"object_id": object_id,
		"object_type": object_type,
		"top_left": top_left,
		"size": size_tiles,
		"footprint_hash": footprint_hash_value,
		"tile_data_version": tile_data_version,
		"has_zone": false,
		"texture": reusable_texture,
		"image": reusable_image,
		"world_rect": Rect2()
	}
	var source_evaluation := (
		WorkplaceProductionSystem
		.get_resource_source_evaluation(
			city_object,
			city_world
		)
	)

	if bool(
		source_evaluation.get(
			"uses_environmental_source",
			false
		)
	):
		var texture_data := _build_texture(
			source_evaluation,
			preview_mode,
			city_tile_size,
			reusable_texture,
			reusable_image
		)

		if not texture_data.is_empty():
			new_cache["has_zone"] = true
			new_cache["texture"] = texture_data.get(
				"texture",
				null
			)
			new_cache["image"] = texture_data.get(
				"image",
				null
			)
			new_cache["world_rect"] = texture_data.get(
				"world_rect",
				Rect2()
			)

	if preview_mode:
		_preview_cache = new_cache
	else:
		_selected_cache = new_cache

	return new_cache


func _cache_matches(
	render_cache: Dictionary,
	preview_mode: bool,
	object_id: int,
	object_type: String,
	top_left: Vector2i,
	size_tiles: Vector2i,
	footprint_hash_value: int,
	tile_data_version: int
) -> bool:
	if render_cache.is_empty():
		return false

	return (
		bool(render_cache.get("preview_mode", false))
		== preview_mode
		and int(render_cache.get("object_id", -2))
		== object_id
		and str(render_cache.get("object_type", ""))
		== object_type
		and render_cache.get(
			"top_left",
			Vector2i(-2, -2)
		)
		== top_left
		and render_cache.get(
			"size",
			Vector2i.ZERO
		)
		== size_tiles
		and int(render_cache.get("footprint_hash", -1))
		== footprint_hash_value
		and int(render_cache.get("tile_data_version", -2))
		== tile_data_version
	)


func _build_texture(
	source_evaluation: Dictionary,
	preview_mode: bool,
	city_tile_size: int,
	reusable_texture: ImageTexture,
	reusable_image: Image
) -> Dictionary:
	var zone_tiles: Array = source_evaluation.get(
		"zone_tiles",
		[]
	)

	if zone_tiles.is_empty():
		return {}

	var has_bounds := false
	var minimum_tile := Vector2i.ZERO
	var maximum_tile := Vector2i.ZERO

	for raw_zone_tile in zone_tiles:
		if not raw_zone_tile is Vector2i:
			continue

		var zone_tile: Vector2i = raw_zone_tile

		if not has_bounds:
			minimum_tile = zone_tile
			maximum_tile = zone_tile
			has_bounds = true
			continue

		minimum_tile.x = mini(
			minimum_tile.x,
			zone_tile.x
		)
		minimum_tile.y = mini(
			minimum_tile.y,
			zone_tile.y
		)
		maximum_tile.x = maxi(
			maximum_tile.x,
			zone_tile.x
		)
		maximum_tile.y = maxi(
			maximum_tile.y,
			zone_tile.y
		)

	if not has_bounds:
		return {}

	var width_tiles := (
		maximum_tile.x - minimum_tile.x + 1
	)
	var height_tiles := (
		maximum_tile.y - minimum_tile.y + 1
	)
	var maximum_dimension_tiles := maxi(
		width_tiles,
		height_tiles
	)
	var pixels_per_tile := clampi(
		int(
			floor(
				float(
					TEXTURE_MAXIMUM_DIMENSION
				)
				/ float(maximum_dimension_tiles)
			)
		),
		1,
		TEXTURE_TARGET_PIXELS_PER_TILE
	)
	var image_width := width_tiles * pixels_per_tile
	var image_height := height_tiles * pixels_per_tile
	var overlay_image: Image = reusable_image

	if (
		overlay_image == null
		or overlay_image.get_width() != image_width
		or overlay_image.get_height() != image_height
		or (
			overlay_image.get_format()
			!= Image.FORMAT_RGBA8
		)
	):
		overlay_image = Image.create(
			image_width,
			image_height,
			false,
			Image.FORMAT_RGBA8
		)

	overlay_image.fill(
		Color(0.0, 0.0, 0.0, 0.0)
	)

	var resource_tile_lookup: Dictionary = (
		source_evaluation.get(
			"resource_tile_lookup",
			{}
		)
	)

	if preview_mode:
		for raw_zone_tile in zone_tiles:
			if not raw_zone_tile is Vector2i:
				continue

			var zone_tile: Vector2i = raw_zone_tile

			_paint_preview_tile(
				overlay_image,
				zone_tile,
				minimum_tile,
				pixels_per_tile,
				resource_tile_lookup.has(zone_tile)
			)
	else:
		var resource_tiles: Array = source_evaluation.get(
			"resource_tiles",
			[]
		)

		for raw_resource_tile in resource_tiles:
			if not raw_resource_tile is Vector2i:
				continue

			var resource_tile: Vector2i = (
				raw_resource_tile
			)
			var resource_rect := _get_tile_rect(
				resource_tile,
				minimum_tile,
				pixels_per_tile
			)

			overlay_image.fill_rect(
				resource_rect,
				SELECTED_RESOURCE_COLOR
			)

		var zone_tile_lookup: Dictionary = (
			source_evaluation.get(
				"zone_tile_lookup",
				{}
			)
		)

		for raw_zone_tile in zone_tiles:
			if not raw_zone_tile is Vector2i:
				continue

			var zone_tile: Vector2i = raw_zone_tile
			var tile_rect := _get_tile_rect(
				zone_tile,
				minimum_tile,
				pixels_per_tile
			)

			_paint_border(
				overlay_image,
				tile_rect,
				SELECTED_BORDER_COLOR,
				not zone_tile_lookup.has(
					zone_tile + Vector2i(0, -1)
				),
				not zone_tile_lookup.has(
					zone_tile + Vector2i(0, 1)
				),
				not zone_tile_lookup.has(
					zone_tile + Vector2i(-1, 0)
				),
				not zone_tile_lookup.has(
					zone_tile + Vector2i(1, 0)
				)
			)

	var overlay_texture: ImageTexture = (
		reusable_texture
	)

	if overlay_texture == null:
		overlay_texture = ImageTexture.create_from_image(
			overlay_image
		)
	elif (
		overlay_texture.get_width() == image_width
		and overlay_texture.get_height() == image_height
		and (
			overlay_texture.get_format()
			== Image.FORMAT_RGBA8
		)
	):
		# Fast path: same GPU allocation, new pixel contents.
		overlay_texture.update(
			overlay_image
		)
	else:
		# This should occur mainly when a zone becomes clipped
		# against a map edge and changes dimensions.
		overlay_texture.set_image(
			overlay_image
		)

	var world_rect := Rect2(
		Vector2(
			float(minimum_tile.x * city_tile_size),
			float(minimum_tile.y * city_tile_size)
		),
		Vector2(
			float(width_tiles * city_tile_size),
			float(height_tiles * city_tile_size)
		)
	)

	return {
		"texture": overlay_texture,
		"image": overlay_image,
		"world_rect": world_rect
	}


func _get_tile_rect(
	tile_position: Vector2i,
	minimum_tile: Vector2i,
	pixels_per_tile: int
) -> Rect2i:
	return Rect2i(
		(tile_position.x - minimum_tile.x)
			* pixels_per_tile,
		(tile_position.y - minimum_tile.y)
			* pixels_per_tile,
		pixels_per_tile,
		pixels_per_tile
	)


func _paint_preview_tile(
	overlay_image: Image,
	tile_position: Vector2i,
	minimum_tile: Vector2i,
	pixels_per_tile: int,
	has_resource: bool
) -> void:
	var tile_rect := _get_tile_rect(
		tile_position,
		minimum_tile,
		pixels_per_tile
	)
	var fill_color := PREVIEW_RED_FILL_COLOR
	var border_color := PREVIEW_RED_BORDER_COLOR

	if has_resource:
		fill_color = PREVIEW_MAGENTA_FILL_COLOR
		border_color = PREVIEW_MAGENTA_BORDER_COLOR

	overlay_image.fill_rect(
		tile_rect,
		fill_color
	)

	_paint_border(
		overlay_image,
		tile_rect,
		border_color,
		true,
		true,
		true,
		true
	)


func _paint_border(
	overlay_image: Image,
	tile_rect: Rect2i,
	border_color: Color,
	draw_top: bool,
	draw_bottom: bool,
	draw_left: bool,
	draw_right: bool
) -> void:
	var border_width := clampi(
		TEXTURE_BORDER_PIXELS,
		1,
		mini(tile_rect.size.x, tile_rect.size.y)
	)

	if draw_top:
		overlay_image.fill_rect(
			Rect2i(
				tile_rect.position,
				Vector2i(
					tile_rect.size.x,
					border_width
				)
			),
			border_color
		)

	if draw_bottom:
		overlay_image.fill_rect(
			Rect2i(
				Vector2i(
					tile_rect.position.x,
					tile_rect.position.y
						+ tile_rect.size.y
						- border_width
				),
				Vector2i(
					tile_rect.size.x,
					border_width
				)
			),
			border_color
		)

	if draw_left:
		overlay_image.fill_rect(
			Rect2i(
				tile_rect.position,
				Vector2i(
					border_width,
					tile_rect.size.y
				)
			),
			border_color
		)

	if draw_right:
		overlay_image.fill_rect(
			Rect2i(
				Vector2i(
					tile_rect.position.x
						+ tile_rect.size.x
						- border_width,
					tile_rect.position.y
				),
				Vector2i(
					border_width,
					tile_rect.size.y
				)
			),
			border_color
		)
