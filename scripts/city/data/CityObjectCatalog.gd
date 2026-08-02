extends RefCounted
class_name CityObjectCatalog

const CityResourceCatalogScript = preload(
	"res://scripts/city/data/CityResourceCatalog.gd"
)

# City object identity and immutable definition policy live here. WorldData
# remains the public facade for callers and owns all mutable object state.
const CITY_OBJECT_CITY_CENTER := "city_center"
const CITY_OBJECT_HOUSE := "house"
const CITY_OBJECT_STOCKPILE := "stockpile"
const CITY_OBJECT_FISHING_GROUNDS := "fishing_grounds"
const CITY_OBJECT_PLACEHOLDER_BUILDING := "placeholder_building"
const CITY_OBJECT_ROAD := "road"
const CITY_OBJECT_PLACEMENT_EFFECT_NONE := "none"
const CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY := "found_city"
const CITY_OBJECT_SHAPE_RECTANGLE := "rectangle"
const CITY_OBJECT_SHAPE_TILE_AREA := "tile_area"

const WORKPLACE_KIND_NONE := "none"
const WORKPLACE_KIND_GATHERING := "gathering"

const WORKPLACE_ANCHOR_MODE_FOOTPRINT_CENTER := "footprint_center"
const WORKPLACE_ANCHOR_MODE_EXPLICIT_POINT := "explicit_point"
const WORKPLACE_ANCHOR_MODE_EXPLICIT_TILE := "explicit_tile"

const WORKPLACE_RESOURCE_SOURCE_MODE_NONE := "none"
const WORKPLACE_RESOURCE_SOURCE_MODE_RADIUS := "radius"
const WORKPLACE_RESOURCE_SOURCE_MODE_FOOTPRINT_REACH := "footprint_reach"
const WORKPLACE_RESOURCE_SOURCE_MODE_LINKED_TILES := "linked_tiles"
const WORKPLACE_RESOURCE_SOURCE_MODE_LINKED_OBJECTS := "linked_objects"
const WORKPLACE_RESOURCE_SOURCE_MODE_STORED_INPUTS := "stored_inputs"
const WORKPLACE_RESOURCE_SOURCE_MODE_EXPLICIT_WORK_POINTS := (
	"explicit_work_points"
)

const WORKPLACE_WORK_LOCATION_MODE_NONE := "none"
const WORKPLACE_WORK_LOCATION_MODE_RESOURCE_SOURCE_TILES := (
	"resource_source_tiles"
)
const WORKPLACE_WORK_LOCATION_MODE_LINKED_TILES := "linked_tiles"
const WORKPLACE_WORK_LOCATION_MODE_WORKSTATIONS := "workstations"
const WORKPLACE_WORK_LOCATION_MODE_EXPLICIT_POINTS := "explicit_points"
const WORKPLACE_WORK_LOCATION_MODE_FOOTPRINT := "footprint"
const WORKPLACE_WORK_LOCATION_ZONE_SOURCE_RESOURCE_SOURCE := (
	"resource_source"
)
const WORKPLACE_WORK_LOCATION_TILE_REQUIREMENT_WALKABLE := "walkable"
const WORKPLACE_WORK_LOCATION_ADJACENCY_NONE := "none"
const WORKPLACE_WORK_LOCATION_ADJACENCY_CARDINAL_TERRAIN := (
	"cardinal_terrain"
)

const WORKPLACE_MOVEMENT_MODE_NONE := "none"
const WORKPLACE_MOVEMENT_MODE_MOVE_BETWEEN_WORK_POINTS := (
	"move_between_work_points"
)
const WORKPLACE_MOVEMENT_MODE_STATION_BASED := "station_based"
const WORKPLACE_MOVEMENT_MODE_REMAIN_AT_STATION := "remain_at_station"
const WORKPLACE_MOVEMENT_MODE_LINKED_TILE_TASKS := "linked_tile_tasks"

const WORKPLACE_BREAK_LOCATION_MODE_NONE := "none"
const WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT := "footprint"
const WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT_RADIUS := "footprint_radius"
const WORKPLACE_BREAK_LOCATION_MODE_LINKED_AREA := "linked_area"
const WORKPLACE_BREAK_LOCATION_MODE_EXPLICIT_TILES := "explicit_tiles"
const WORKPLACE_BREAK_LOCATION_MODE_WORK_AREA := "work_area"
const WORKPLACE_BREAK_LOCATION_MODE_INTERIOR := "interior"

const WORKPLACE_OVERFLOW_MODE_NONE := "none"
const WORKPLACE_OVERFLOW_MODE_FOOTPRINT_RADIUS := "footprint_radius"
const WORKPLACE_OVERFLOW_MODE_EXPLICIT_TILES := "explicit_tiles"
const WORKPLACE_OVERFLOW_MODE_LINKED_AREA := "linked_area"

const PRODUCTIVITY_BASIS_POINTS_SCALE := 10_000
const DEFAULT_WORKPLACE_SITE_PRODUCTIVITY_BASIS_POINTS := (
	PRODUCTIVITY_BASIS_POINTS_SCALE
)

const WORKPLACE_PRODUCTION_STATUS_INACTIVE := "inactive"
const WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS := "idle_no_workers"
const WORKPLACE_PRODUCTION_STATUS_WORKING := "working"
const WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL := (
	"blocked_output_full"
)
const WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT := (
	"blocked_missing_input"
)
const WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE := (
	"blocked_no_resource_source"
)
const CITY_WORKPLACE_PRODUCTION_STATE_KEYS := [
	"object_id",
	"progress_work_units",
	"production_status",
	"productive_worker_count",
	"site_productivity_basis_points",
]

const CONTAINER_TYPE_NONE := "none"
const CONTAINER_TYPE_PUBLIC_CITY_STORAGE := "public_city_storage"
const CONTAINER_TYPE_PRIVATE_HOME_STORAGE := "private_home_storage"
const CONTAINER_TYPE_WORKPLACE_STORAGE := "workplace_storage"
const CONTAINER_TYPE_PERSONAL_INVENTORY := "personal_inventory"
const CONTAINER_TYPE_GROUND_PILE := "ground_pile"

const CONTAINER_ACCESS_COUNTS_TOWARD_CITY_OWNED_TOTALS := (
	"counts_toward_city_owned_totals"
)
const CONTAINER_ACCESS_PUBLICLY_USABLE := "publicly_usable"
const CONTAINER_ACCESS_HAUL_DEPOSIT_PURPOSES := "haul_deposit_purposes"
const CONTAINER_ACCESS_HAUL_WITHDRAWAL_PURPOSES := (
	"haul_withdrawal_purposes"
)
const CONTAINER_ACCESS_DIRECT_WITHDRAWAL_PURPOSES := (
	"direct_withdrawal_purposes"
)

const CONTAINER_HAUL_PURPOSE_NONE := "none"
const CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE := "public_storage"
const CONTAINER_HAUL_PURPOSE_HOME_DELIVERY := "home_delivery"
const CONTAINER_HAUL_PURPOSE_WORKPLACE_OUTPUT := "workplace_output"
const CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP := "ground_pile_cleanup"
const CONTAINER_HAUL_PURPOSE_CONSTRUCTION := "construction"
const CONTAINER_HAUL_PURPOSE_HOUSEHOLD_FOOD_SOURCE := (
	"household_food_source"
)
const CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE := "none"
const CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD := "personal_food"

const PUBLIC_CITY_STORAGE_TIER_NONE: int = -1
const PUBLIC_CITY_STORAGE_TIER_STOCKPILE: int = 0
const PUBLIC_CITY_STORAGE_TIER_CITY_KEEP: int = 1

const CITY_OBJECT_INTERIOR_ACCESS_NONE := "none"
const CITY_OBJECT_INTERIOR_ACCESS_RESIDENTS := "residents"
const CITY_OBJECT_INTERIOR_ACCESS_ASSIGNED_WORKERS := "assigned_workers"
const CITY_OBJECT_INTERIOR_ACCESS_TASK_TARGET := "task_target"
const CITY_OBJECT_INTERIOR_ACCESS_PUBLIC := "public"

const CITY_OBJECT_ENTRY_MODE_ANY_BOUNDARY := "any_boundary"
const CITY_OBJECT_ENTRY_MODE_EXPLICIT_TILES := "explicit_tiles"

const TERRAIN_WATER := "water"

static var _city_object_definitions: Dictionary = {}
static var _storage_resource_lookup_by_object_type: Dictionary = {}


static func ensure_city_object_definitions_ready() -> void:
	if _city_object_definitions.is_empty():
		setup_city_object_definitions()


static func setup_city_object_definitions() -> void:
	_city_object_definitions.clear()
	_storage_resource_lookup_by_object_type.clear()

	_city_object_definitions[CITY_OBJECT_CITY_CENTER] = (
		make_city_object_definition({
			"type": CITY_OBJECT_CITY_CENTER,
			"display_name": "City Keep",
			"container_type": CONTAINER_TYPE_PUBLIC_CITY_STORAGE,
			"counts_as_public_city_storage": true,
			"container_access_policy": {
				CONTAINER_ACCESS_COUNTS_TOWARD_CITY_OWNED_TOTALS: true,
				CONTAINER_ACCESS_PUBLICLY_USABLE: true,
				CONTAINER_ACCESS_HAUL_DEPOSIT_PURPOSES: [
					CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE,
				],
				CONTAINER_ACCESS_HAUL_WITHDRAWAL_PURPOSES: [
					CONTAINER_HAUL_PURPOSE_HOME_DELIVERY,
					CONTAINER_HAUL_PURPOSE_HOUSEHOLD_FOOD_SOURCE,
					CONTAINER_HAUL_PURPOSE_CONSTRUCTION,
				],
				CONTAINER_ACCESS_DIRECT_WITHDRAWAL_PURPOSES: [
					CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD,
				],
			},
			"storage_resources": (
				CityResourceCatalogScript.get_city_resource_types()
			),
			"storage_capacity": 50,
			"supports_citizen_interior": true,
			"citizen_interior_access_mode": (
				CITY_OBJECT_INTERIOR_ACCESS_TASK_TARGET
			),
			"citizen_entry_policy": {
				"mode": CITY_OBJECT_ENTRY_MODE_ANY_BOUNDARY,
			},
			"size": Vector2i(3, 7),
			"button_slot": 1,
			"requires_city": false,
			"requires_no_city": true,
			"repeat_after_place": false,
			"placement_effect": CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY,
			"frame_color": Color(0.32, 0.30, 0.24, 0.95),
			"fill_color": Color(0.86, 0.84, 0.76, 0.55),
			"frame_thickness": 0.35,
		})
	)

	_city_object_definitions[CITY_OBJECT_HOUSE] = (
		make_city_object_definition({
			"type": CITY_OBJECT_HOUSE,
			"display_name": "House",
			"container_type": CONTAINER_TYPE_PRIVATE_HOME_STORAGE,
			"container_access_policy": {
				CONTAINER_ACCESS_COUNTS_TOWARD_CITY_OWNED_TOTALS: false,
				CONTAINER_ACCESS_PUBLICLY_USABLE: false,
				CONTAINER_ACCESS_HAUL_DEPOSIT_PURPOSES: [
					CONTAINER_HAUL_PURPOSE_HOME_DELIVERY,
				],
				CONTAINER_ACCESS_HAUL_WITHDRAWAL_PURPOSES: [],
				CONTAINER_ACCESS_DIRECT_WITHDRAWAL_PURPOSES: [
					CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD,
				],
			},
			"supports_citizen_interior": true,
			"citizen_interior_access_mode": (
				CITY_OBJECT_INTERIOR_ACCESS_RESIDENTS
			),
			"citizen_entry_policy": {
				"mode": CITY_OBJECT_ENTRY_MODE_ANY_BOUNDARY,
			},
			"resident_capacity": 4,
			"storage_resources": (
				CityResourceCatalogScript.get_city_resource_types()
			),
			"storage_capacity": 50,
			"size": Vector2i(3, 3),
			"button_slot": 3,
			"requires_city": true,
			"requires_no_city": false,
			"repeat_after_place": true,
			"placement_effect": CITY_OBJECT_PLACEMENT_EFFECT_NONE,
			"construction_enabled": true,
			"construction_materials": {
				CityResourceCatalogScript.RESOURCE_LUMBER: 8,
				CityResourceCatalogScript.RESOURCE_STONE: 4,
			},
			"construction_labor_minutes": 135,
			"construction_max_workers": 4,
			"frame_color": Color(0.32, 0.30, 0.24, 0.95),
			"fill_color": Color(0.86, 0.84, 0.76, 0.55),
			"frame_thickness": 0.30,
		})
	)

	_city_object_definitions[CITY_OBJECT_STOCKPILE] = (
		make_city_object_definition({
			"type": CITY_OBJECT_STOCKPILE,
			"display_name": "Stockpile",
			"container_type": CONTAINER_TYPE_PUBLIC_CITY_STORAGE,
			"counts_as_public_city_storage": true,
			"container_access_policy": {
				CONTAINER_ACCESS_COUNTS_TOWARD_CITY_OWNED_TOTALS: true,
				CONTAINER_ACCESS_PUBLICLY_USABLE: true,
				CONTAINER_ACCESS_HAUL_DEPOSIT_PURPOSES: [
					CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE,
				],
				CONTAINER_ACCESS_HAUL_WITHDRAWAL_PURPOSES: [
					CONTAINER_HAUL_PURPOSE_HOME_DELIVERY,
					CONTAINER_HAUL_PURPOSE_HOUSEHOLD_FOOD_SOURCE,
					CONTAINER_HAUL_PURPOSE_CONSTRUCTION,
				],
				CONTAINER_ACCESS_DIRECT_WITHDRAWAL_PURPOSES: [
					CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD,
				],
			},
			"size": Vector2i(2, 2),
			"button_slot": 4,
			"requires_city": true,
			"requires_no_city": false,
			"repeat_after_place": true,
			"placement_effect": CITY_OBJECT_PLACEMENT_EFFECT_NONE,
			"construction_enabled": true,
			"construction_materials": {
				CityResourceCatalogScript.RESOURCE_LUMBER: 6,
				CityResourceCatalogScript.RESOURCE_STONE: 2,
			},
			"construction_labor_minutes": 90,
			"construction_max_workers": 4,
			"frame_color": Color(0.46, 0.30, 0.12, 0.95),
			"fill_color": Color(0.82, 0.64, 0.32, 0.55),
			"frame_thickness": 0.30,
			"storage_resources": (
				CityResourceCatalogScript.get_city_resource_types()
			),
			"storage_capacity": 200,
		})
	)

	_city_object_definitions[CITY_OBJECT_FISHING_GROUNDS] = (
		make_city_object_definition({
			"type": CITY_OBJECT_FISHING_GROUNDS,
			"display_name": "Fishing Grounds",
			"container_type": CONTAINER_TYPE_WORKPLACE_STORAGE,
			"counts_as_public_city_storage": false,
			"container_access_policy": {
				CONTAINER_ACCESS_COUNTS_TOWARD_CITY_OWNED_TOTALS: true,
				CONTAINER_ACCESS_PUBLICLY_USABLE: false,
				CONTAINER_ACCESS_HAUL_DEPOSIT_PURPOSES: [],
				CONTAINER_ACCESS_HAUL_WITHDRAWAL_PURPOSES: [
					CONTAINER_HAUL_PURPOSE_WORKPLACE_OUTPUT,
					CONTAINER_HAUL_PURPOSE_HOUSEHOLD_FOOD_SOURCE,
				],
				CONTAINER_ACCESS_DIRECT_WITHDRAWAL_PURPOSES: [
					CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD,
				],
			},
			"shape_mode": CITY_OBJECT_SHAPE_RECTANGLE,
			"size": Vector2i(3, 3),
			"button_slot": 5,
			"requires_city": true,
			"requires_no_city": false,
			"repeat_after_place": true,
			"placement_effect": CITY_OBJECT_PLACEMENT_EFFECT_NONE,
			"construction_enabled": true,
			"construction_materials": {
				CityResourceCatalogScript.RESOURCE_LUMBER: 10,
				CityResourceCatalogScript.RESOURCE_STONE: 4,
			},
			"construction_labor_minutes": 180,
			"construction_max_workers": 4,
			"frame_color": Color(0.06, 0.34, 0.40, 0.95),
			"fill_color": Color(0.18, 0.62, 0.70, 0.48),
			"frame_thickness": 0.30,
			"is_workplace": true,
			"workplace_kind": WORKPLACE_KIND_GATHERING,
			"worker_capacity": 4,
			"output_resource": CityResourceCatalogScript.RESOURCE_FISH,
			# Fish restores one citizen-day of hunger. Three worker-hours per
			# fish lets four fully productive workers make 12 fish during the
			# current nine-hour shift, matching the 33% food-labor target.
			"production_recipe": {
				"inputs": {},
				"outputs": {
					CityResourceCatalogScript.RESOURCE_FISH: 1,
				},
				"work_units_per_batch": 180_000,
			},
			"resource_source_policy": {
				"mode": WORKPLACE_RESOURCE_SOURCE_MODE_FOOTPRINT_REACH,
				"resource_type": CityResourceCatalogScript.RESOURCE_FISH,
				"reach_tiles": 8,
				"source_density_for_full_productivity_basis_points": 1_000,
			},
			"work_location_policy": {
				"mode": WORKPLACE_WORK_LOCATION_MODE_RESOURCE_SOURCE_TILES,
				"zone_source": (
					WORKPLACE_WORK_LOCATION_ZONE_SOURCE_RESOURCE_SOURCE
				),
				"standing_tile_requirement": (
					WORKPLACE_WORK_LOCATION_TILE_REQUIREMENT_WALKABLE
				),
				"adjacency_mode": (
					WORKPLACE_WORK_LOCATION_ADJACENCY_CARDINAL_TERRAIN
				),
				"adjacent_terrain": TERRAIN_WATER,
			},
			"work_movement_policy": {
				"mode": WORKPLACE_MOVEMENT_MODE_MOVE_BETWEEN_WORK_POINTS,
				"dwell_min_minutes": 120,
				"dwell_max_minutes": 360,
				"maximum_relocations_per_task": 1,
				"minimum_relocation_distance": 4,
				"avoid_previous_target": true,
			},
			"break_location_policy": {
				"mode": WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT_RADIUS,
				"radius_tiles": 3,
			},
			"overflow_policy": {
				"mode": WORKPLACE_OVERFLOW_MODE_FOOTPRINT_RADIUS,
				"radius_tiles": 2,
			},
			"storage_capacity": 50,
		})
	)

	_city_object_definitions[CITY_OBJECT_ROAD] = (
		make_city_object_definition({
			"type": CITY_OBJECT_ROAD,
			"display_name": "Road",
			"shape_mode": CITY_OBJECT_SHAPE_TILE_AREA,
			"size": Vector2i.ONE,
			"requires_city": true,
			"requires_no_city": false,
			"repeat_after_place": true,
			"placement_effect": CITY_OBJECT_PLACEMENT_EFFECT_NONE,
			"construction_enabled": true,
			# Roads are labor-only infrastructure. Each painted tile becomes its
			# own construction site, so this is the complete per-tile recipe.
			"construction_materials": {},
			"construction_materials_per_tile": false,
			"construction_labor_minutes": 8,
			"construction_labor_per_tile": false,
			"construction_max_workers": 1,
			"frame_color": Color(0.29, 0.11, 0.045, 1.0),
			"fill_color": Color(0.56, 0.25, 0.10, 0.96),
			"frame_thickness": 0.08,
		})
	)

	for raw_object_type in _city_object_definitions.keys():
		var object_type := str(raw_object_type)
		var definition: Dictionary = _city_object_definitions[
			raw_object_type
		]
		var storage_resource_lookup: Dictionary = {}
		var raw_storage_resources = definition.get(
			"storage_resources",
			[]
		)

		if raw_storage_resources is Array:
			for raw_resource in raw_storage_resources:
				storage_resource_lookup[str(raw_resource)] = true

		_storage_resource_lookup_by_object_type[object_type] = (
			storage_resource_lookup
		)


static func make_city_object_definition(values: Dictionary) -> Dictionary:
	var object_type: String = str(values.get("type", ""))
	var storage_resources: Array[String] = []
	var raw_storage_resources = values.get("storage_resources", [])

	if raw_storage_resources is Array:
		for resource in raw_storage_resources:
			storage_resources.append(str(resource))
	if object_type.is_empty():
		push_error("City object definition is missing a type.")
		return {}

	var container_type: String = str(
		values.get("container_type", CONTAINER_TYPE_NONE)
	)
	var production_recipe := _copy_dictionary_field(
		values,
		"production_recipe"
	)
	var construction_materials := _normalize_construction_materials(
		_copy_dictionary_field(values, "construction_materials")
	)

	# Workplace storage is an output buffer. Its compatibility is derived from
	# recipe outputs so multi-output recipes cannot leave a stale list behind.
	if container_type == CONTAINER_TYPE_WORKPLACE_STORAGE:
		storage_resources = _get_recipe_output_resource_types(
			production_recipe
		)

	var counts_as_public_city_storage := bool(values.get(
		"counts_as_public_city_storage",
		container_type == CONTAINER_TYPE_PUBLIC_CITY_STORAGE
	))
	var shape_mode: String = str(
		values.get("shape_mode", CITY_OBJECT_SHAPE_RECTANGLE)
	)
	var is_workplace := bool(values.get("is_workplace", false))

	return {
		"type": object_type,
		"display_name": str(
			values.get("display_name", object_type.capitalize())
		),
		"size": values.get("size", Vector2i.ONE),
		"button_slot": int(values.get("button_slot", 0)),
		"requires_city": bool(values.get("requires_city", false)),
		"requires_no_city": bool(values.get("requires_no_city", false)),
		"repeat_after_place": bool(values.get("repeat_after_place", false)),
		"placement_effect": str(
			values.get(
				"placement_effect",
				CITY_OBJECT_PLACEMENT_EFFECT_NONE
			)
		),
		"construction_enabled": bool(
			values.get("construction_enabled", false)
		),
		"construction_materials": construction_materials,
		"construction_materials_per_tile": bool(
			values.get("construction_materials_per_tile", false)
		),
		"construction_labor_minutes": maxi(
			int(values.get("construction_labor_minutes", 0)),
			0
		),
		"construction_labor_per_tile": bool(
			values.get("construction_labor_per_tile", false)
		),
		"construction_max_workers": maxi(
			int(values.get("construction_max_workers", 1)),
			1
		),
		"frame_color": values.get(
			"frame_color",
			Color(0.32, 0.30, 0.24, 0.95)
		),
		"fill_color": values.get(
			"fill_color",
			Color(0.86, 0.84, 0.76, 0.55)
		),
		"frame_thickness": float(values.get("frame_thickness", 0.30)),
		"container_type": container_type,
		"counts_as_public_city_storage": counts_as_public_city_storage,
		"container_access_policy": _copy_dictionary_field(
			values,
			"container_access_policy"
		),
		"shape_mode": shape_mode,
		"storage_resources": storage_resources,
		"storage_capacity": int(values.get("storage_capacity", 0)),
		"resident_capacity": int(values.get("resident_capacity", 0)),
		"supports_citizen_interior": bool(
			values.get("supports_citizen_interior", false)
		),
		"citizen_interior_access_mode": str(
			values.get(
				"citizen_interior_access_mode",
				CITY_OBJECT_INTERIOR_ACCESS_NONE
			)
		),
		"citizen_entry_policy": _copy_dictionary_field(
			values,
			"citizen_entry_policy"
		),
		"is_workplace": is_workplace,
		"workplace_kind": str(
			values.get("workplace_kind", WORKPLACE_KIND_NONE)
		),
		"worker_capacity": int(values.get("worker_capacity", 0)),
		"output_resource": str(
			values.get(
				"output_resource",
				CityResourceCatalogScript.RESOURCE_NONE
			)
		),
		"production_recipe": production_recipe,
		"resource_source_policy": _copy_dictionary_field(
			values,
			"resource_source_policy"
		),
		"work_location_policy": _copy_dictionary_field(
			values,
			"work_location_policy"
		),
		"work_movement_policy": _copy_dictionary_field(
			values,
			"work_movement_policy"
		),
		"break_location_policy": _copy_dictionary_field(
			values,
			"break_location_policy"
		),
		"overflow_policy": _copy_dictionary_field(
			values,
			"overflow_policy"
		),
	}


static func _normalize_construction_materials(
	raw_materials: Dictionary
) -> Dictionary:
	var materials: Dictionary = {}

	for resource in CityResourceCatalogScript.get_city_resource_types():
		var amount := maxi(int(raw_materials.get(resource, 0)), 0)

		if amount > 0:
			materials[resource] = amount

	return materials


static func _get_recipe_output_resource_types(
	production_recipe: Dictionary
) -> Array[String]:
	var output_resources: Array[String] = []
	var raw_outputs = production_recipe.get("outputs", {})

	if not raw_outputs is Dictionary:
		return output_resources

	for known_resource in (
		CityResourceCatalogScript.get_city_resource_types()
	):
		if raw_outputs.has(known_resource):
			output_resources.append(known_resource)

	var extra_resources: Array[String] = []

	for raw_resource in raw_outputs.keys():
		var resource := str(raw_resource)

		if output_resources.has(resource):
			continue

		extra_resources.append(resource)

	extra_resources.sort()
	output_resources.append_array(extra_resources)
	return output_resources


static func _copy_dictionary_field(
	values: Dictionary,
	field_name: String
) -> Dictionary:
	var raw_value = values.get(field_name, {})

	if not raw_value is Dictionary:
		return {}

	return raw_value.duplicate(true)


static func get_city_object_definitions() -> Dictionary:
	ensure_city_object_definitions_ready()
	return _city_object_definitions


static func get_city_object_definition(object_type: String) -> Dictionary:
	ensure_city_object_definitions_ready()

	if _city_object_definitions.has(object_type):
		return _city_object_definitions[object_type]

	return {}


static func can_city_object_type_store_resource(
	object_type: String,
	resource: String
) -> bool:
	ensure_city_object_definitions_ready()

	var raw_lookup = _storage_resource_lookup_by_object_type.get(
		object_type,
		{}
	)

	if not raw_lookup is Dictionary:
		return false

	return raw_lookup.has(resource)


# Definition dictionaries are shared immutable catalog data.
static func _get_city_object_definition_dictionary(
	city_object: Dictionary,
	definition_field: String
) -> Dictionary:
	if city_object.is_empty():
		return {}

	var definition := get_city_object_definition(
		str(city_object.get("type", ""))
	)

	if definition.is_empty():
		return {}

	var raw_value = definition.get(definition_field, {})

	if not raw_value is Dictionary:
		return {}

	var definition_dictionary: Dictionary = raw_value
	return definition_dictionary


static func get_city_object_production_recipe(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"production_recipe"
	)


static func get_city_object_construction_materials(
	object_type: String
) -> Dictionary:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return {}

	var raw_materials = definition.get("construction_materials", {})

	if not raw_materials is Dictionary:
		return {}

	return raw_materials.duplicate(true)


static func city_object_type_uses_construction(
	object_type: String
) -> bool:
	var definition := get_city_object_definition(object_type)

	return (
		not definition.is_empty()
		and bool(definition.get("construction_enabled", false))
	)


static func get_city_object_resource_source_policy(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"resource_source_policy"
	)


static func get_city_object_work_location_policy(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"work_location_policy"
	)


static func get_city_object_work_movement_policy(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"work_movement_policy"
	)


static func get_city_object_break_location_policy(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"break_location_policy"
	)


static func get_city_object_overflow_policy(
	city_object: Dictionary
) -> Dictionary:
	return _get_city_object_definition_dictionary(
		city_object,
		"overflow_policy"
	)


static func get_city_object_production_progress_work_units(
	city_object: Dictionary
) -> int:
	if city_object.is_empty():
		return 0

	return maxi(
		int(
			city_object.get(
				"production_progress_work_units",
				0
			)
		),
		0
	)


static func get_city_object_production_status(
	city_object: Dictionary
) -> String:
	if city_object.is_empty():
		return WORKPLACE_PRODUCTION_STATUS_INACTIVE

	return str(
		city_object.get(
			"production_status",
			WORKPLACE_PRODUCTION_STATUS_INACTIVE
		)
	)


static func get_city_object_productive_worker_count(
	city_object: Dictionary
) -> int:
	if city_object.is_empty():
		return 0

	return maxi(
		int(
			city_object.get(
				"productive_worker_count",
				0
			)
		),
		0
	)


static func get_city_object_site_productivity_basis_points(
	city_object: Dictionary
) -> int:
	if city_object.is_empty():
		return DEFAULT_WORKPLACE_SITE_PRODUCTIVITY_BASIS_POINTS

	return maxi(
		int(
			city_object.get(
				"site_productivity_basis_points",
				DEFAULT_WORKPLACE_SITE_PRODUCTIVITY_BASIS_POINTS
			)
		),
		0
	)


static func is_valid_workplace_anchor_mode(mode: String) -> bool:
	return (
		mode == WORKPLACE_ANCHOR_MODE_FOOTPRINT_CENTER
		or mode == WORKPLACE_ANCHOR_MODE_EXPLICIT_POINT
		or mode == WORKPLACE_ANCHOR_MODE_EXPLICIT_TILE
	)


static func is_valid_workplace_resource_source_mode(mode: String) -> bool:
	return (
		mode == WORKPLACE_RESOURCE_SOURCE_MODE_NONE
		or mode == WORKPLACE_RESOURCE_SOURCE_MODE_RADIUS
		or mode == WORKPLACE_RESOURCE_SOURCE_MODE_FOOTPRINT_REACH
		or mode == WORKPLACE_RESOURCE_SOURCE_MODE_LINKED_TILES
		or mode == WORKPLACE_RESOURCE_SOURCE_MODE_LINKED_OBJECTS
		or mode == WORKPLACE_RESOURCE_SOURCE_MODE_STORED_INPUTS
		or mode == WORKPLACE_RESOURCE_SOURCE_MODE_EXPLICIT_WORK_POINTS
	)


static func is_valid_workplace_work_location_mode(mode: String) -> bool:
	return (
		mode == WORKPLACE_WORK_LOCATION_MODE_NONE
		or mode == WORKPLACE_WORK_LOCATION_MODE_RESOURCE_SOURCE_TILES
		or mode == WORKPLACE_WORK_LOCATION_MODE_LINKED_TILES
		or mode == WORKPLACE_WORK_LOCATION_MODE_WORKSTATIONS
		or mode == WORKPLACE_WORK_LOCATION_MODE_EXPLICIT_POINTS
		or mode == WORKPLACE_WORK_LOCATION_MODE_FOOTPRINT
	)


static func is_valid_workplace_movement_mode(mode: String) -> bool:
	return (
		mode == WORKPLACE_MOVEMENT_MODE_NONE
		or mode == WORKPLACE_MOVEMENT_MODE_MOVE_BETWEEN_WORK_POINTS
		or mode == WORKPLACE_MOVEMENT_MODE_STATION_BASED
		or mode == WORKPLACE_MOVEMENT_MODE_REMAIN_AT_STATION
		or mode == WORKPLACE_MOVEMENT_MODE_LINKED_TILE_TASKS
	)


static func is_valid_workplace_break_location_mode(mode: String) -> bool:
	return (
		mode == WORKPLACE_BREAK_LOCATION_MODE_NONE
		or mode == WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT
		or mode == WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT_RADIUS
		or mode == WORKPLACE_BREAK_LOCATION_MODE_LINKED_AREA
		or mode == WORKPLACE_BREAK_LOCATION_MODE_EXPLICIT_TILES
		or mode == WORKPLACE_BREAK_LOCATION_MODE_WORK_AREA
		or mode == WORKPLACE_BREAK_LOCATION_MODE_INTERIOR
	)


static func is_valid_workplace_overflow_mode(mode: String) -> bool:
	return (
		mode == WORKPLACE_OVERFLOW_MODE_NONE
		or mode == WORKPLACE_OVERFLOW_MODE_FOOTPRINT_RADIUS
		or mode == WORKPLACE_OVERFLOW_MODE_EXPLICIT_TILES
		or mode == WORKPLACE_OVERFLOW_MODE_LINKED_AREA
	)


static func is_valid_city_workplace_production_status(
	production_status: String
) -> bool:
	return (
		production_status == WORKPLACE_PRODUCTION_STATUS_INACTIVE
		or (
			production_status
			== WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE
		)
		or production_status == WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS
		or production_status == WORKPLACE_PRODUCTION_STATUS_WORKING
		or (
			production_status
			== WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL
		)
		or (
			production_status
			== WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT
		)
	)


static func get_city_object_display_name_for_type(
	object_type: String
) -> String:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return object_type.capitalize()

	return str(definition.get("display_name", object_type.capitalize()))


static func get_city_object_size_for_type(
	object_type: String
) -> Vector2i:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return Vector2i.ONE

	return definition["size"]


static func get_city_object_visual_style_for_type(
	object_type: String
) -> Dictionary:
	var definition := get_city_object_definition(object_type)

	if definition.is_empty():
		return {
			"frame_color": Color(0.32, 0.30, 0.24, 0.95),
			"fill_color": Color(0.86, 0.84, 0.76, 0.55),
			"frame_thickness": 0.30,
		}

	return {
		"frame_color": definition["frame_color"],
		"fill_color": definition["fill_color"],
		"frame_thickness": definition["frame_thickness"],
	}
