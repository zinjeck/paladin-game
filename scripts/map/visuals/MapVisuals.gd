extends RefCounted
class_name MapVisuals

enum ViewMode {
	BIOME,
	ELEVATION,
	TEMPERATURE,
	PRECIPITATION,
	RESOURCES,
	FERTILITY
}

const INVALID_VIEW_MODE: int = -1
const MAP_VISUAL_CACHE_VERSION: int = 2

static func get_all_view_modes() -> Array[int]:
	var modes: Array[int] = [
		ViewMode.BIOME,
		ViewMode.ELEVATION,
		ViewMode.TEMPERATURE,
		ViewMode.PRECIPITATION,
		ViewMode.RESOURCES,
		ViewMode.FERTILITY
	]

	return modes


static func get_view_mode_for_index(index: int) -> int:
	var modes := get_all_view_modes()

	if index < 0 or index >= modes.size():
		return ViewMode.BIOME

	return modes[index]


static func get_view_mode_for_keycode(keycode: int) -> int:
	match keycode:
		KEY_1:
			return ViewMode.BIOME

		KEY_2:
			return ViewMode.ELEVATION

		KEY_3:
			return ViewMode.TEMPERATURE

		KEY_4:
			return ViewMode.PRECIPITATION

		KEY_5:
			return ViewMode.RESOURCES

		KEY_6:
			return ViewMode.FERTILITY

	return INVALID_VIEW_MODE


static func get_view_mode_name(mode: int) -> String:
	match mode:
		ViewMode.BIOME:
			return "Biome"

		ViewMode.ELEVATION:
			return "Elevation"

		ViewMode.TEMPERATURE:
			return "Temperature"

		ViewMode.PRECIPITATION:
			return "Precipitation"

		ViewMode.RESOURCES:
			return "Resources"

		ViewMode.FERTILITY:
			return "Fertility"

	return "Unknown"


static func get_tile_color_for_mode(
	tile: Dictionary,
	mode: int,
	biome_resource_blend: float = 0.0
) -> Color:
	match mode:
		ViewMode.BIOME:
			return get_biome_mode_color(tile, biome_resource_blend)

		ViewMode.ELEVATION:
			return get_elevation_color(tile)

		ViewMode.TEMPERATURE:
			return get_temperature_color(tile)

		ViewMode.PRECIPITATION:
			return get_precipitation_color(tile)

		ViewMode.RESOURCES:
			return get_resource_overlay_color(tile)

		ViewMode.FERTILITY:
			return get_fertility_overlay_color(tile)

	return Color.MAGENTA


static func get_biome_mode_color(tile: Dictionary, resource_blend: float = 0.0) -> Color:
	var base_color := get_biome_color(tile)

	if resource_blend <= 0.0:
		return base_color

	var resource: String = str(tile.get("resource", WorldData.RESOURCE_NONE))

	if (
		resource == WorldData.RESOURCE_NONE
		or resource == WorldData.RESOURCE_FISH
	):
		return base_color

	return base_color.lerp(get_resource_color(resource), resource_blend)

static func get_biome_color(tile: Dictionary) -> Color:
	var biome: String = str(tile.get("biome", ""))

	match biome:
		WorldData.BIOME_OCEAN:
			return Color(0.05, 0.16, 0.36)

		WorldData.BIOME_RIVER:
			return Color(0.08, 0.34, 0.82)

		WorldData.BIOME_MOUNTAIN:
			return Color(0.45, 0.42, 0.38)

		WorldData.BIOME_HILLS:
			return Color(0.46, 0.31, 0.16)

		WorldData.BIOME_DESERT:
			return Color(0.86, 0.72, 0.36)

		WorldData.BIOME_PLAIN:
			return Color(0.36, 0.65, 0.25)

		WorldData.BIOME_FOREST:
			return Color(0.10, 0.42, 0.16)

		WorldData.BIOME_TUNDRA:
			return Color(0.64, 0.72, 0.68)

		WorldData.BIOME_TAIGA:
			return Color(0.20, 0.38, 0.32)

		WorldData.BIOME_JUNGLE:
			return Color(0.02, 0.36, 0.09)

	return Color.MAGENTA


static func get_elevation_color(tile: Dictionary) -> Color:
	var elevation: float = float(tile.get("elevation", 0.0))
	var value: float = clamp((elevation + 1.0) / 2.0, 0.0, 1.0)

	var color := Color(value, value, value)
	var biome: String = str(tile.get("biome", ""))

	if biome == WorldData.BIOME_OCEAN:
		return Color(0.01, 0.03, 0.12).lerp(color, 0.35)

	if biome == WorldData.BIOME_RIVER:
		return Color(0.0, 0.42, 0.92)

	return color


static func get_temperature_color(tile: Dictionary) -> Color:
	var biome: String = str(tile.get("biome", ""))

	if biome == WorldData.BIOME_OCEAN:
		return get_biome_color(tile).darkened(0.50)

	if biome == WorldData.BIOME_RIVER:
		return Color(0.0, 0.45, 0.95)

	var base_color := get_biome_color(tile).darkened(0.48)
	var temperature: float = clamp(float(tile.get("temperature", 0.0)), 0.0, 1.0)

	var temperature_color := Color(
		temperature,
		0.08,
		1.0 - temperature
	)

	return base_color.lerp(temperature_color, 0.82)


static func get_precipitation_color(tile: Dictionary) -> Color:
	var biome: String = str(tile.get("biome", ""))

	if biome == WorldData.BIOME_OCEAN:
		return get_biome_color(tile).darkened(0.38)

	if biome == WorldData.BIOME_RIVER:
		return Color(0.0, 0.75, 1.0)

	var base_color := get_biome_color(tile).darkened(0.50)
	var precipitation: float = clamp(float(tile.get("precipitation", 0.0)), 0.0, 1.0)

	var precipitation_color := Color(
		0.05,
		precipitation,
		1.0 - precipitation * 0.25
	)

	return base_color.lerp(precipitation_color, 0.82)


static func get_resource_overlay_color(tile: Dictionary) -> Color:
	var base_color := get_biome_color(tile)
	var resource: String = str(tile.get("resource", WorldData.RESOURCE_NONE))

	if resource == WorldData.RESOURCE_NONE:
		return base_color.darkened(0.58)

	return get_resource_color(resource)


static func get_fertility_overlay_color(tile: Dictionary) -> Color:
	var biome: String = str(tile.get("biome", ""))

	if biome == WorldData.BIOME_OCEAN:
		return get_biome_color(tile).darkened(0.68)

	if biome == WorldData.BIOME_RIVER:
		return Color(0.0, 0.90, 1.0)

	var base_color := get_biome_color(tile).darkened(0.55)
	var fertility: float = clamp(float(tile.get("fertility", 0.0)), 0.0, 100.0)

	var fertility_color := Color(
		1.0 - fertility / 100.0,
		fertility / 100.0,
		0.06
	)

	return base_color.lerp(fertility_color, 0.82)


static func get_resource_color(resource: String) -> Color:
	if resource == WorldData.RESOURCE_FISH:
		return Color(0.82, 0.42, 0.95)

	if resource == WorldData.RESOURCE_COAL:
		return Color(0.02, 0.02, 0.02)

	if resource == WorldData.RESOURCE_IRON:
		return Color(0.73, 0.64, 0.48)

	if resource == WorldData.RESOURCE_GOLD:
		return Color(0.93, 0.74, 0.22)

	return Color.MAGENTA
