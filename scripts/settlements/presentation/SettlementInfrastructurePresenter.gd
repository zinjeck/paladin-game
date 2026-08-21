extends RefCounted
class_name SettlementInfrastructurePresenter

const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)

# Draws completed objects and roads, construction blueprints, and loose
# resource piles for one explicit settlement presentation. This component owns
# no gameplay data and never discovers an active settlement; every snapshot is
# read directly from the exact state carried by its accepted binding.

const CityRenderLayerScript = preload(
	"res://scripts/city/rendering/CityRenderLayer.gd"
)

const GROUND_PILE_MARKER_TILE_SCALE: float = 0.16
const CONSTRUCTION_CLEARING_COLOR := Color(1.0, 0.48, 0.08, 0.9)
const CONSTRUCTION_GATHERING_COLOR := Color(0.12, 0.78, 1.0, 0.9)
const CONSTRUCTION_LABOR_COLOR := Color(0.25, 1.0, 0.48, 0.9)
const CONSTRUCTION_BLUEPRINT_FILL := Color(0.2, 0.65, 1.0, 0.18)
const CONSTRUCTION_UNKNOWN_PHASE_COLOR := Color(1.0, 1.0, 1.0, 0.58)

var presentation_binding: SettlementPresentationBindingScript
var highest_accepted_binding_generation: int = 0
var local_tile_size: int = 1


func can_bind_settlement_presentation(
	binding: SettlementPresentationBindingScript,
	tile_size: int
) -> bool:
	if (
		binding == null
		or not binding.is_valid()
		or not binding.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
		)
		or tile_size <= 0
	):
		return false
	if binding.generation > highest_accepted_binding_generation:
		return true

	# Equal generations are idempotent only for the exact current binding.
	return (
		binding.generation == highest_accepted_binding_generation
		and tile_size == local_tile_size
		and is_bound_to_settlement_presentation(binding)
	)


func bind_settlement_presentation(
	binding: SettlementPresentationBindingScript,
	tile_size: int
) -> bool:
	if not can_bind_settlement_presentation(binding, tile_size):
		return false
	if (
		is_bound_to_settlement_presentation(binding)
		and tile_size == local_tile_size
	):
		return true

	presentation_binding = binding
	local_tile_size = tile_size
	highest_accepted_binding_generation = binding.generation
	return true


func is_bound_to_settlement_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	return (
		binding != null
		and presentation_binding != null
		and presentation_binding.matches_binding(binding)
		and binding.generation == highest_accepted_binding_generation
		and local_tile_size > 0
	)


func reset_presentation() -> void:
	presentation_binding = null
	local_tile_size = 1
	# The generation high-water mark intentionally survives presentation reset.


func draw_completed_infrastructure(draw_target: CanvasItem) -> void:
	var state := _get_bound_state()
	if draw_target == null or state == null:
		return

	var completed_objects := (
		CityObjectSystem.get_city_objects_for_city_state(state)
	)
	_draw_completed_objects(draw_target, completed_objects)
	_draw_completed_roads(draw_target, completed_objects)
	_draw_construction_sites(draw_target, state)


func draw_ground_piles(draw_target: CanvasItem) -> void:
	var state := _get_bound_state()
	if draw_target == null or state == null:
		return

	var ground_piles := (
		CityLogisticsSystem.get_city_ground_pile_snapshot_for_city_state(state)
	)
	var pile_count_by_tile: Dictionary = {}
	for raw_ground_pile in ground_piles:
		if not raw_ground_pile is Dictionary:
			continue
		var raw_tile_position = raw_ground_pile.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		if not raw_tile_position is Vector2i:
			continue
		pile_count_by_tile[raw_tile_position] = (
			int(pile_count_by_tile.get(raw_tile_position, 0)) + 1
		)

	var next_slot_by_tile: Dictionary = {}
	var multiple_pile_offsets := [
		Vector2(-0.075, -0.075),
		Vector2(0.075, -0.075),
		Vector2(-0.075, 0.075),
		Vector2(0.075, 0.075),
	]
	for raw_ground_pile in ground_piles:
		if not raw_ground_pile is Dictionary:
			continue
		var ground_pile: Dictionary = raw_ground_pile
		var raw_tile_position = ground_pile.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var resource := str(
			ground_pile.get("resource_type", WorldData.RESOURCE_NONE)
		)
		if (
			not raw_tile_position is Vector2i
			or not CityResourceCatalog.is_city_resource_type(resource)
		):
			continue

		var tile_position: Vector2i = raw_tile_position
		var pile_count := int(pile_count_by_tile.get(tile_position, 1))
		var slot_index := int(next_slot_by_tile.get(tile_position, 0))
		next_slot_by_tile[tile_position] = slot_index + 1
		var marker_scale := GROUND_PILE_MARKER_TILE_SCALE
		var center_offset := Vector2.ZERO
		if pile_count > 1:
			marker_scale = 0.11
			center_offset = multiple_pile_offsets[
				posmod(slot_index, multiple_pile_offsets.size())
			]

		var tile_center := Vector2(
			(float(tile_position.x) + 0.5) * float(local_tile_size),
			(float(tile_position.y) + 0.5) * float(local_tile_size)
		)
		tile_center += center_offset * float(local_tile_size)
		var marker_side := float(local_tile_size) * marker_scale
		var marker_rect := Rect2(
			tile_center - Vector2.ONE * marker_side * 0.5,
			Vector2.ONE * marker_side
		)
		draw_target.draw_rect(
			marker_rect,
			MapVisuals.get_resource_color(resource),
			true
		)


func draw_settlement_object_visual(
	draw_target: CanvasItem,
	settlement_object: Dictionary,
	alpha_multiplier: float = 1.0,
	is_valid_preview: bool = true
) -> void:
	if (
		draw_target == null
		or not _has_valid_binding()
		or settlement_object.is_empty()
	):
		return
	var object_type := str(settlement_object.get("type", ""))
	if object_type == CityObjectCatalog.CITY_OBJECT_ROAD:
		return

	var rect := _get_object_world_rect(settlement_object)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var style := (
		CityObjectCatalog.get_city_object_visual_style_for_type(object_type)
	)
	var frame_color: Color = style["frame_color"]
	var fill_color: Color = style["fill_color"]
	var frame_thickness := float(style["frame_thickness"])
	if not is_valid_preview:
		frame_color = Color(1.0, 0.0, 0.0, 0.95)
		fill_color = Color(1.0, 0.05, 0.05, 0.35)

	frame_color = _with_alpha_multiplier(frame_color, alpha_multiplier)
	fill_color = _with_alpha_multiplier(fill_color, alpha_multiplier)
	CityRenderLayerScript.draw_framed_rect({
		"draw_target": draw_target,
		"rect": rect,
		"frame_color": frame_color,
		"fill_color": fill_color,
		"frame_thickness": frame_thickness,
	})


func _draw_completed_objects(
	draw_target: CanvasItem,
	completed_objects: Array
) -> void:
	for settlement_object in completed_objects:
		if not settlement_object is Dictionary:
			continue
		if settlement_object.is_empty():
			continue
		if (
			str(settlement_object.get("type", ""))
			== CityObjectCatalog.CITY_OBJECT_ROAD
		):
			continue
		draw_settlement_object_visual(
			draw_target,
			settlement_object,
			1.0,
			true
		)


func _draw_completed_roads(
	draw_target: CanvasItem,
	completed_objects: Array
) -> void:
	var road_style := (
		CityObjectCatalog.get_city_object_visual_style_for_type(
			CityObjectCatalog.CITY_OBJECT_ROAD
		)
	)
	var road_fill_color: Color = road_style.get(
		"fill_color",
		Color(0.56, 0.25, 0.10, 0.96)
	)
	for settlement_object in completed_objects:
		if not settlement_object is Dictionary:
			continue
		if (
			str(settlement_object.get("type", ""))
			!= CityObjectCatalog.CITY_OBJECT_ROAD
			or not settlement_object.has("tiles")
		):
			continue
		var road_tiles: Array = settlement_object["tiles"]
		for tile_position in road_tiles:
			if not tile_position is Vector2i:
				continue
			draw_target.draw_rect(
				_get_tile_world_rect(tile_position),
				road_fill_color,
				true
			)


func _draw_construction_sites(
	draw_target: CanvasItem,
	state: CitySettlementSimulationState
) -> void:
	var construction_sites := (
		CityConstructionSystem.get_city_construction_site_snapshot_for_city_state(
			state
		)
	)
	for raw_site in construction_sites:
		if not raw_site is Dictionary:
			continue
		var site: Dictionary = raw_site
		var phase_color := _get_construction_phase_color(
			str(site.get("phase", ""))
		)
		var object_type := str(site.get("object_type", ""))
		var footprint_tiles = site.get("footprint_tiles", [])
		if not footprint_tiles is Array:
			continue

		if object_type != CityObjectCatalog.CITY_OBJECT_ROAD:
			draw_settlement_object_visual(
				draw_target,
				{
					"type": object_type,
					"top_left": site.get(
						"top_left",
						CityCitizens.INVALID_CITY_TILE_POSITION
					),
					"size": site.get("size", Vector2i.ZERO),
				},
				0.32,
				true
			)

		var blueprint_fill := CONSTRUCTION_BLUEPRINT_FILL
		if object_type == CityObjectCatalog.CITY_OBJECT_ROAD:
			var road_style := (
				CityObjectCatalog.get_city_object_visual_style_for_type(
					CityObjectCatalog.CITY_OBJECT_ROAD
				)
			)
			var road_fill: Color = road_style.get(
				"fill_color",
				Color(0.56, 0.25, 0.10, 0.96)
			)
			blueprint_fill = Color(
				road_fill.r,
				road_fill.g,
				road_fill.b,
				0.34
			)

		for raw_tile in footprint_tiles:
			if not raw_tile is Vector2i:
				continue
			var tile_rect := _get_tile_world_rect(raw_tile)
			draw_target.draw_rect(tile_rect, blueprint_fill, true)
			CityRenderLayerScript.draw_inner_box_border({
				"draw_target": draw_target,
				"rect": tile_rect,
				"border_color": phase_color,
				"border_width": float(local_tile_size) * 0.06,
			})


func _get_construction_phase_color(phase: String) -> Color:
	match phase:
		CityConstructionSystem.CITY_CONSTRUCTION_PHASE_CLEARING:
			return CONSTRUCTION_CLEARING_COLOR
		CityConstructionSystem.CITY_CONSTRUCTION_PHASE_GATHERING:
			return CONSTRUCTION_GATHERING_COLOR
		CityConstructionSystem.CITY_CONSTRUCTION_PHASE_LABOR:
			return CONSTRUCTION_LABOR_COLOR
	return CONSTRUCTION_UNKNOWN_PHASE_COLOR


func _get_object_world_rect(settlement_object: Dictionary) -> Rect2:
	if settlement_object.has("top_left") and settlement_object.has("size"):
		var top_left: Vector2i = settlement_object["top_left"]
		var size_tiles: Vector2i = settlement_object["size"]
		return Rect2(
			Vector2(top_left * local_tile_size),
			Vector2(size_tiles * local_tile_size)
		)

	var footprint_tiles := (
		CityObjectSystem.get_city_object_footprint_tiles(settlement_object)
	)
	var has_tile := false
	var minimum_tile := Vector2i.ZERO
	var maximum_tile := Vector2i.ZERO
	for raw_tile in footprint_tiles:
		if not raw_tile is Vector2i:
			continue
		var tile_position: Vector2i = raw_tile
		if not has_tile:
			minimum_tile = tile_position
			maximum_tile = tile_position
			has_tile = true
		else:
			minimum_tile.x = mini(minimum_tile.x, tile_position.x)
			minimum_tile.y = mini(minimum_tile.y, tile_position.y)
			maximum_tile.x = maxi(maximum_tile.x, tile_position.x)
			maximum_tile.y = maxi(maximum_tile.y, tile_position.y)
	if not has_tile:
		return Rect2()
	return Rect2(
		Vector2(minimum_tile * local_tile_size),
		Vector2(
			(maximum_tile - minimum_tile + Vector2i.ONE) * local_tile_size
		)
	)


func _get_tile_world_rect(tile_position: Vector2i) -> Rect2:
	return Rect2(
		Vector2(tile_position * local_tile_size),
		Vector2(local_tile_size, local_tile_size)
	)


func _has_valid_binding() -> bool:
	return (
		presentation_binding != null
		and presentation_binding.is_valid()
		and presentation_binding.generation
		== highest_accepted_binding_generation
		and local_tile_size > 0
	)


func _get_bound_state() -> CitySettlementSimulationState:
	if not _has_valid_binding():
		return null
	var capability_state = presentation_binding.get_backend_capability(
		SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
	)
	return (
		capability_state
		if capability_state is CitySettlementSimulationState
		else null
	)


func _with_alpha_multiplier(
	color: Color,
	alpha_multiplier: float
) -> Color:
	return Color(
		color.r,
		color.g,
		color.b,
		color.a * alpha_multiplier
	)
