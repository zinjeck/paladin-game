extends RefCounted
class_name CityObjectSystem

const CITY_TOPOLOGY_MUTATION_FAILURE_NONE := "none"
const CITY_TOPOLOGY_MUTATION_FAILURE_INVALID_REQUEST := "invalid_request"
const CITY_TOPOLOGY_MUTATION_FAILURE_TILE_BLOCKED := "tile_blocked"
const CITY_TOPOLOGY_MUTATION_FAILURE_FOOTPRINT_OCCUPIED := "footprint_occupied"
const _DEFERRED_FOUNDATION_SURFACE_CLEAR_FIELD := (
	"_deferred_foundation_surface_clear"
)
const _DEFERRED_FOUNDATION_REGISTRATION_BASELINE_FIELD := (
	"_deferred_foundation_registration_baseline"
)
const _CITY_OBJECT_ASSIGNMENT_MUTABLE_FIELDS := [
	"resident_capacity",
	"resident_ids",
	"assigned_worker_ids",
]
const _CITY_OBJECT_WORKPLACE_MUTABLE_FIELDS := [
	"worker_capacity",
	"staffing_mode",
	"desired_worker_count",
	"production_progress_work_units",
	"production_status",
	"productive_worker_count",
	"site_productivity_basis_points",
]
const _CITY_OBJECT_STORAGE_MUTABLE_FIELDS := [
	"stored_resources",
]

# File responsibility: Authoritative completed-city-object behavior/API for
# one explicitly supplied CITY settlement. CityObjectState remains the data-only
# owner of the registry, ID index, footprint occupancy, next local ID, and version.




static func get_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> CityObjectState:
	if city_state == null:
		return null

	return city_state.object_state




static func _make_variant_read_only_recursive(value) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value

		for raw_key in dictionary.keys():
			_make_variant_read_only_recursive(dictionary[raw_key])

		if not dictionary.is_read_only():
			dictionary.make_read_only()
		return

	if value is Array:
		var array: Array = value

		for item in array:
			_make_variant_read_only_recursive(item)

		if not array.is_read_only():
			array.make_read_only()


static func _make_read_only_city_object_record(
	city_object: Dictionary
) -> Dictionary:
	if city_object.is_empty():
		return {}

	var detached_record := city_object.duplicate(true)
	_make_variant_read_only_recursive(detached_record)
	return detached_record


static func _ensure_city_object_record_is_read_only(
	object_state: CityObjectState,
	object_index: int
) -> Dictionary:
	if (
		object_state == null
		or object_index < 0
		or object_index >= object_state.objects.size()
	):
		return {}

	var raw_city_object = object_state.objects[object_index]

	if not raw_city_object is Dictionary:
		return {}

	var city_object: Dictionary = raw_city_object

	# Bootstrap and adopted states may predate the read-only boundary. Normalize
	# only their records and preserve the settlement-owned outer Array identity.
	if not city_object.is_read_only():
		city_object = _make_read_only_city_object_record(city_object)
		object_state.objects[object_index] = city_object

	return city_object


static func _ensure_city_object_records_are_read_only(
	object_state: CityObjectState
) -> void:
	if object_state == null:
		return

	for object_index in range(object_state.objects.size()):
		_ensure_city_object_record_is_read_only(object_state, object_index)




static func get_city_objects_for_city_state(
	city_state: CitySettlementSimulationState
) -> Array:
	var object_state := get_state_for_city_state(city_state)

	if object_state == null:
		return []

	_ensure_city_object_records_are_read_only(object_state)
	return object_state.objects.duplicate()


static func get_city_object_snapshot_for_city_state(
	city_state: CitySettlementSimulationState
) -> Array:
	return get_city_objects_for_city_state(city_state).duplicate(true)






static func get_city_object_by_id_for_city_state(
	city_state: CitySettlementSimulationState,
	object_id: int
) -> Dictionary:
	var object_index := get_city_object_index_by_id_for_city_state(
		city_state,
		object_id
	)

	if object_index < 0:
		return {}

	var object_state := get_state_for_city_state(city_state)
	return _ensure_city_object_record_is_read_only(
		object_state,
		object_index
	)


static func get_city_object_by_id_snapshot_for_city_state(
	city_state: CitySettlementSimulationState,
	object_id: int
) -> Dictionary:
	return get_city_object_by_id_for_city_state(
		city_state,
		object_id
	).duplicate(true)




static func _get_city_object_changed_fields(
	existing: Dictionary,
	proposed: Dictionary
) -> Array[String]:
	var field_lookup: Dictionary = {}
	var changed_fields: Array[String] = []

	for raw_field in existing.keys():
		if typeof(raw_field) != TYPE_STRING:
			return [""]
		field_lookup[str(raw_field)] = true

	for raw_field in proposed.keys():
		if typeof(raw_field) != TYPE_STRING:
			return [""]
		field_lookup[str(raw_field)] = true

	for raw_field in field_lookup.keys():
		var field_name := str(raw_field)
		var existing_has_field := existing.has(field_name)
		var proposed_has_field := proposed.has(field_name)

		if (
			existing_has_field != proposed_has_field
			or (
				existing_has_field
				and existing[field_name] != proposed[field_name]
			)
		):
			changed_fields.append(field_name)

	changed_fields.sort()
	return changed_fields


static func _get_city_object_mutation_domain(field_name: String) -> String:
	if _CITY_OBJECT_ASSIGNMENT_MUTABLE_FIELDS.has(field_name):
		return "assignment"
	if _CITY_OBJECT_WORKPLACE_MUTABLE_FIELDS.has(field_name):
		return "workplace"
	if _CITY_OBJECT_STORAGE_MUTABLE_FIELDS.has(field_name):
		return "storage"
	return ""


static func _patch_city_object_fields_at_index(
	object_state: CityObjectState,
	object_index: int,
	object_id: int,
	field_values: Dictionary,
	fields_to_erase: Array,
	allowed_fields: Array
) -> bool:
	if object_state == null or object_id <= 0:
		return false

	var existing := _ensure_city_object_record_is_read_only(
		object_state,
		object_index
	)

	if (
		existing.is_empty()
		or int(existing.get("id", -1)) != object_id
		or int(object_state.object_index_by_id.get(object_id, -1))
		!= object_index
	):
		return false

	var erased_field_lookup: Dictionary = {}

	for raw_field in fields_to_erase:
		if typeof(raw_field) != TYPE_STRING:
			return false

		var field_name := str(raw_field)

		if (
			not allowed_fields.has(field_name)
			or erased_field_lookup.has(field_name)
			or field_values.has(field_name)
		):
			return false

		erased_field_lookup[field_name] = true

	for raw_field in field_values.keys():
		if (
			typeof(raw_field) != TYPE_STRING
			or not allowed_fields.has(str(raw_field))
		):
			return false

	if field_values.is_empty() and erased_field_lookup.is_empty():
		return false

	var updated := existing.duplicate(true)

	for raw_field in erased_field_lookup.keys():
		updated.erase(str(raw_field))

	for raw_field in field_values.keys():
		updated[str(raw_field)] = field_values[raw_field]

	if updated == existing:
		return false

	object_state.objects[object_index] = (
		_make_read_only_city_object_record(updated)
	)
	return true




static func patch_city_object_assignment_fields_for_city_state(
	city_state: CitySettlementSimulationState,
	object_id: int,
	field_values: Dictionary,
	fields_to_erase: Array = []
) -> bool:
	return _patch_city_object_fields_at_index(
		get_state_for_city_state(city_state),
		get_city_object_index_by_id_for_city_state(city_state, object_id),
		object_id,
		field_values,
		fields_to_erase,
		_CITY_OBJECT_ASSIGNMENT_MUTABLE_FIELDS
	)




static func patch_city_object_workplace_fields_for_city_state(
	city_state: CitySettlementSimulationState,
	object_id: int,
	field_values: Dictionary,
	fields_to_erase: Array = []
) -> bool:
	return _patch_city_object_fields_at_index(
		get_state_for_city_state(city_state),
		get_city_object_index_by_id_for_city_state(city_state, object_id),
		object_id,
		field_values,
		fields_to_erase,
		_CITY_OBJECT_WORKPLACE_MUTABLE_FIELDS
	)




static func patch_city_object_storage_fields_for_city_state(
	city_state: CitySettlementSimulationState,
	object_id: int,
	field_values: Dictionary,
	fields_to_erase: Array = []
) -> bool:
	return _patch_city_object_fields_at_index(
		get_state_for_city_state(city_state),
		get_city_object_index_by_id_for_city_state(city_state, object_id),
		object_id,
		field_values,
		fields_to_erase,
		_CITY_OBJECT_STORAGE_MUTABLE_FIELDS
	)




static func write_city_object_at_index_for_city_state(
	city_state: CitySettlementSimulationState,
	object_index: int,
	city_object: Dictionary
) -> bool:
	var object_state := get_state_for_city_state(city_state)

	if (
		object_state == null
		or city_object.is_empty()
		or object_index < 0
		or object_index >= object_state.objects.size()
	):
		return false

	var existing := _ensure_city_object_record_is_read_only(
		object_state,
		object_index
	)
	var object_id := int(city_object.get("id", -1))

	if (
		existing.is_empty()
		or object_id <= 0
		or int(existing.get("id", -1)) != object_id
		or int(object_state.object_index_by_id.get(object_id, -1))
		!= object_index
	):
		return false

	return _write_compatible_city_object_record(
		object_state,
		object_index,
		existing,
		city_object
	)


static func _write_compatible_city_object_record(
	object_state: CityObjectState,
	object_index: int,
	existing: Dictionary,
	proposed: Dictionary
) -> bool:
	var changed_fields := _get_city_object_changed_fields(existing, proposed)

	if changed_fields.is_empty():
		return true

	var mutation_domain := ""
	var allowed_fields: Array = []
	var field_values: Dictionary = {}
	var fields_to_erase: Array = []

	for field_name in changed_fields:
		var field_domain := _get_city_object_mutation_domain(field_name)

		if field_domain.is_empty():
			return false
		if mutation_domain.is_empty():
			mutation_domain = field_domain
		elif mutation_domain != field_domain:
			return false

		if proposed.has(field_name):
			field_values[field_name] = proposed[field_name]
		else:
			fields_to_erase.append(field_name)

	match mutation_domain:
		"assignment":
			allowed_fields = _CITY_OBJECT_ASSIGNMENT_MUTABLE_FIELDS
		"workplace":
			allowed_fields = _CITY_OBJECT_WORKPLACE_MUTABLE_FIELDS
		"storage":
			allowed_fields = _CITY_OBJECT_STORAGE_MUTABLE_FIELDS
		_:
			return false

	return _patch_city_object_fields_at_index(
		object_state,
		object_index,
		int(existing.get("id", -1)),
		field_values,
		fields_to_erase,
		allowed_fields
	)










static func get_city_object_version_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	var object_state := get_state_for_city_state(city_state)
	return object_state.object_version if object_state != null else 0


static func _get_city_object_debug_fingerprint_for_state(
	object_state: CityObjectState
) -> int:
	if object_state == null:
		return 0

	_ensure_city_object_records_are_read_only(object_state)
	return hash([
		object_state.objects,
		object_state.object_index_by_id,
		object_state.occupied_tiles,
		object_state.next_object_id,
	])




static func get_city_object_debug_fingerprint_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _get_city_object_debug_fingerprint_for_state(
		get_state_for_city_state(city_state)
	)




static func mark_city_objects_changed_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	var object_state := get_state_for_city_state(city_state)

	if object_state != null:
		object_state.object_version += 1




static func _rebuild_city_object_index_for_state(
	state: CityObjectState
) -> void:
	state.object_index_by_id.clear()

	for object_index in range(state.objects.size()):
		var raw_city_object = state.objects[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object
		var object_id := int(city_object.get("id", -1))

		if object_id <= 0:
			continue

		if state.object_index_by_id.has(object_id):
			push_error(
				"Duplicate city object ID while rebuilding index: "
				+ str(object_id)
			)
			continue

		state.object_index_by_id[object_id] = object_index




static func rebuild_city_object_occupancy_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	var state := get_state_for_city_state(city_state)

	if state == null:
		return

	if _rebuild_city_object_occupancy_for_state(state):
		mark_city_objects_changed_for_city_state(city_state)


static func _rebuild_city_object_occupancy_for_state(
	state: CityObjectState
) -> bool:
	var previous_occupancy := state.occupied_tiles.duplicate()
	state.occupied_tiles.clear()

	for raw_city_object in state.objects:
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object
		var object_id := int(city_object.get("id", -1))

		if object_id <= 0:
			continue

		for raw_tile in get_city_object_footprint_tiles(city_object):
			if not raw_tile is Vector2i:
				continue

			var tile_position: Vector2i = raw_tile
			var occupying_id := int(state.occupied_tiles.get(tile_position, -1))

			if occupying_id > 0 and occupying_id != object_id:
				push_error(
					"Conflicting city-object occupancy at "
					+ str(tile_position)
					+ " for object IDs "
					+ str(occupying_id)
					+ " and "
					+ str(object_id)
				)
				continue

			state.occupied_tiles[tile_position] = object_id

	return state.occupied_tiles != previous_occupancy




static func rebuild_city_object_registry_indexes_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	var state := get_state_for_city_state(city_state)

	if state == null:
		return

	_rebuild_city_object_index_for_state(state)
	rebuild_city_object_occupancy_for_city_state(city_state)










static func get_city_object_index_by_id_for_city_state(
	city_state: CitySettlementSimulationState,
	object_id: int
) -> int:
	var object_state := get_state_for_city_state(city_state)

	if object_state == null or object_id <= 0:
		return -1

	var object_index := int(
		object_state.object_index_by_id.get(object_id, -1)
	)

	if object_index >= 0 and object_index < object_state.objects.size():
		var raw_indexed = object_state.objects[object_index]

		if (
			raw_indexed is Dictionary
			and int(raw_indexed.get("id", -1)) == object_id
		):
			return object_index

	var authoritative_index := -1

	for candidate_index in range(object_state.objects.size()):
		var raw_candidate = object_state.objects[candidate_index]

		if (
			raw_candidate is Dictionary
			and int(raw_candidate.get("id", -1)) == object_id
		):
			authoritative_index = candidate_index
			break

	if authoritative_index < 0:
		object_state.object_index_by_id.erase(object_id)
		return -1

	object_state.object_index_by_id[object_id] = authoritative_index
	return authoritative_index




static func get_city_object_id_at_tile_for_city_state(
	city_state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> int:
	var object_state := get_state_for_city_state(city_state)

	if object_state == null:
		return -1

	return maxi(int(object_state.occupied_tiles.get(tile_position, -1)), -1)




static func has_city_object_at_tile_for_city_state(
	city_state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> bool:
	return get_city_object_id_at_tile_for_city_state(
		city_state,
		tile_position
	) > 0




static func get_city_object_at_tile_for_city_state(
	city_state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> Dictionary:
	var object_id := get_city_object_id_at_tile_for_city_state(
		city_state,
		tile_position
	)

	if object_id <= 0:
		return {}

	return get_city_object_by_id_for_city_state(city_state, object_id)




static func make_rectangle_city_object_footprint_tiles(
	top_left: Vector2i,
	size_tiles: Vector2i
) -> Array:
	var footprint_tiles := []

	if size_tiles.x <= 0 or size_tiles.y <= 0:
		return footprint_tiles

	for y in range(top_left.y, top_left.y + size_tiles.y):
		for x in range(top_left.x, top_left.x + size_tiles.x):
			footprint_tiles.append(Vector2i(x, y))

	return footprint_tiles


static func get_city_object_footprint_tiles(city_object: Dictionary) -> Array:
	var footprint_tiles := []

	if city_object.is_empty():
		return footprint_tiles

	if city_object.has("footprint_tiles"):
		var raw_footprint_tiles = city_object.get("footprint_tiles", [])

		if raw_footprint_tiles is Array:
			for tile_position in raw_footprint_tiles:
				if tile_position is Vector2i:
					footprint_tiles.append(tile_position)

			return footprint_tiles

	if city_object.has("tiles"):
		var raw_tiles = city_object.get("tiles", [])

		if raw_tiles is Array:
			for tile_position in raw_tiles:
				if tile_position is Vector2i:
					footprint_tiles.append(tile_position)

			return footprint_tiles

	if city_object.has("top_left") and city_object.has("size"):
		var top_left: Vector2i = city_object.get(
			"top_left",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)
		return make_rectangle_city_object_footprint_tiles(top_left, size_tiles)

	return footprint_tiles






static func city_object_type_preserves_citizen_walkability(
	object_type: String
) -> bool:
	return object_type == CityObjectCatalog.CITY_OBJECT_ROAD




static func get_city_object_topology_blocking_citizen_ids_for_city_state(
	city_state: CitySettlementSimulationState,
	object_type: String,
	footprint_tiles: Array
) -> Array[int]:
	if city_state == null or city_object_type_preserves_citizen_walkability(
		object_type
	):
		return []

	return CityCitizenSpatialSystem.get_living_city_citizen_ids_in_tiles_for_city_state(
		city_state,
		footprint_tiles
	)






static func can_place_city_object_for_city_state(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	top_left: Vector2i,
	size_tiles: Vector2i,
	object_type: String = ""
) -> bool:
	return _can_place_city_object(
		city_state,
		CityConstructionSystem.get_state_for_city_state(city_state),
		city_world,
		top_left,
		size_tiles,
		object_type
	)


static func _can_place_city_object(
	city_state: CitySettlementSimulationState,
	construction_state: CityConstructionState,
	city_world: WorldData,
	top_left: Vector2i,
	size_tiles: Vector2i,
	object_type: String
) -> bool:
	if city_world == null:
		return false

	if city_state == null or not is_same(city_world, city_state.city_world):
		return false

	if size_tiles.x <= 0 or size_tiles.y <= 0:
		return false

	if top_left.x < 0 or top_left.y < 0:
		return false

	if (
		top_left.x + size_tiles.x > city_world.width
		or top_left.y + size_tiles.y > city_world.height
	):
		return false

	if construction_state == null:
		return false

	for y in range(top_left.y, top_left.y + size_tiles.y):
		for x in range(top_left.x, top_left.x + size_tiles.x):
			var tile_position := Vector2i(x, y)

			var has_object: bool = (
				has_city_object_at_tile_for_city_state(
					city_state,
					tile_position
				)
			)
			if has_object:
				return false

			if construction_state.construction_site_id_by_tile.has(
				tile_position
			):
				return false

			var has_ground_pile: bool = (
				CityLogisticsSystem.has_city_ground_pile_at_tile_for_city_state(
						city_state,
						tile_position
					)
			)
			if has_ground_pile:
				return false

			var has_citizen: bool = (
				CityCitizenSpatialSystem.has_living_city_citizen_at_tile_for_city_state(
						city_state,
						tile_position
					)
			)
			if has_citizen:
				return false

			var tile: Dictionary = city_world.get_tile_for_internal_read(x, y)

			if str(tile.get("terrain", "")) in [
				CityObjectCatalog.TERRAIN_WATER,
				WorldData.TERRAIN_MOUNTAIN,
			]:
				return false

	if (
		object_type == CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		and not _city_object_placement_has_walkable_access_tile(
			city_state,
			city_world,
			top_left,
			size_tiles
		)
	):
		return false

	return true




static func city_object_placement_has_walkable_access_tile_for_city_state(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	top_left: Vector2i,
	size_tiles: Vector2i
) -> bool:
	return _city_object_placement_has_walkable_access_tile(
		city_state,
		city_world,
		top_left,
		size_tiles
	)


static func _city_object_placement_has_walkable_access_tile(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	top_left: Vector2i,
	size_tiles: Vector2i
) -> bool:
	if city_world == null:
		return false

	if city_state == null or not is_same(city_world, city_state.city_world):
		return false

	var footprint_lookup: Dictionary = {}

	for y in range(top_left.y, top_left.y + size_tiles.y):
		for x in range(top_left.x, top_left.x + size_tiles.x):
			footprint_lookup[Vector2i(x, y)] = true

	for raw_footprint_tile in footprint_lookup:
		if not raw_footprint_tile is Vector2i:
			continue

		var footprint_tile: Vector2i = raw_footprint_tile

		for offset in CityNavigationSystem.CITY_CARDINAL_TILE_OFFSETS:
			var candidate_tile: Vector2i = footprint_tile + Vector2i(offset)

			if footprint_lookup.has(candidate_tile):
				continue

			var is_walkable: bool = (
				CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
						city_state,
						city_world,
						candidate_tile
					)
			)
			if is_walkable:
				return true

	return false


static func city_object_supports_citizen_interior(
	city_object: Dictionary
) -> bool:
	var definition := CityObjectCatalog.get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return false

	return bool(definition.get("supports_citizen_interior", false))


static func get_city_object_citizen_interior_access_mode(
	city_object: Dictionary
) -> String:
	var definition := CityObjectCatalog.get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return CityObjectCatalog.CITY_OBJECT_INTERIOR_ACCESS_NONE

	return str(
		definition.get(
			"citizen_interior_access_mode",
			CityObjectCatalog.CITY_OBJECT_INTERIOR_ACCESS_NONE
		)
	)


static func get_city_object_citizen_entry_policy(
	city_object: Dictionary
) -> Dictionary:
	return CityObjectCatalog._get_city_object_definition_dictionary(
		city_object,
		"citizen_entry_policy"
	)


static func get_city_object_citizen_entry_tiles(
	city_object: Dictionary
) -> Array[Vector2i]:
	var entry_tiles: Array[Vector2i] = []
	var raw_entry_tiles = city_object.get("citizen_entry_tiles", [])

	if not raw_entry_tiles is Array:
		return entry_tiles

	for raw_entry_tile in raw_entry_tiles:
		if raw_entry_tile is Vector2i:
			entry_tiles.append(raw_entry_tile)

	entry_tiles.sort_custom(_sort_city_tiles_y_then_x)
	return entry_tiles


static func city_object_boundary_tile_allows_entry(
	city_object: Dictionary,
	boundary_tile: Vector2i
) -> bool:
	if not city_object_supports_citizen_interior(city_object):
		return true

	var entry_policy := get_city_object_citizen_entry_policy(city_object)
	var entry_mode := str(
		entry_policy.get(
			"mode",
			CityObjectCatalog.CITY_OBJECT_ENTRY_MODE_ANY_BOUNDARY
		)
	)

	match entry_mode:
		CityObjectCatalog.CITY_OBJECT_ENTRY_MODE_ANY_BOUNDARY:
			return get_city_object_footprint_tiles(city_object).has(boundary_tile)

		CityObjectCatalog.CITY_OBJECT_ENTRY_MODE_EXPLICIT_TILES:
			return get_city_object_citizen_entry_tiles(city_object).has(boundary_tile)

	return false




static func is_completed_city_road_tile_for_city_state(
	city_state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> bool:
	var city_object := get_city_object_at_tile_for_city_state(
		city_state,
		tile_position
	)

	return (
		not city_object.is_empty()
		and str(city_object.get("type", ""))
		== CityObjectCatalog.CITY_OBJECT_ROAD
	)








static func register_completed_city_object_for_city_state(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> Dictionary:
	return _register_completed_city_object_for_city_state(city_state, values)


static func place_immediate_settlement_object_for_context(
	settlement_context: SettlementSimulationContext,
	values: Dictionary
) -> Dictionary:
	# Presentation code submits a registered settlement context and placement
	# values to this single authoritative transaction.  It never owns object,
	# foundation, rollback, or player-capital mirror mutation itself.
	if (
		settlement_context == null
		or not WorldPoliticalState.is_registered_settlement_context(
			settlement_context
		)
		or not settlement_context.supports_detailed_simulation()
	):
		return {}

	var detailed_state = settlement_context.get_detailed_simulation_state()
	if not detailed_state is CitySettlementSimulationState:
		return {}
	var city_state: CitySettlementSimulationState = detailed_state
	if city_state.city_world == null:
		return {}

	var requested_world = values.get(
		"settlement_world",
		values.get("city_world", city_state.city_world)
	)
	if (
		not requested_world is WorldData
		or not is_same(requested_world, city_state.city_world)
	):
		return {}

	var object_type := str(values.get("object_type", ""))
	var definition := CityObjectCatalog.get_city_object_definition(object_type)
	if definition.is_empty():
		return {}

	var placement_effect := str(definition.get(
		"placement_effect",
		CityObjectCatalog.CITY_OBJECT_PLACEMENT_EFFECT_NONE
	))
	var is_foundation := (
		placement_effect
		== CityObjectCatalog.CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY
	)
	var registration_values := values.duplicate(true)
	registration_values.erase("settlement_world")
	registration_values.erase("settlement_seed")
	registration_values["city_world"] = city_state.city_world
	if is_foundation:
		registration_values["defer_surface_feature_clear"] = true

	var city_object := register_completed_city_object_for_city_state(
		city_state,
		registration_values
	)
	if city_object.is_empty():
		return {}
	var object_id := int(city_object.get("id", -1))

	if (
		is_foundation
		and not _commit_immediate_settlement_foundation(
			settlement_context,
			city_state,
			city_object,
			values
		)
	):
		if not rollback_completed_city_object_for_city_state(
			city_state,
			object_id
		):
			push_error(
				"Could not roll back failed immediate settlement-object placement."
			)
		return {}

	if (
		is_foundation
		and not finalize_deferred_city_foundation_surface_features_for_city_state(
			city_state,
			object_id
		)
	):
		push_error(
			"Settlement foundation committed, but its deferred surface features "
			+ "could not be cleared."
		)

	return get_city_object_by_id_for_city_state(city_state, object_id)


static func _commit_immediate_settlement_foundation(
	settlement_context: SettlementSimulationContext,
	city_state: CitySettlementSimulationState,
	city_object: Dictionary,
	values: Dictionary
) -> bool:
	if (
		settlement_context == null
		or city_state == null
		or city_object.is_empty()
		or not is_same(
			settlement_context.get_detailed_simulation_state(),
			city_state
		)
		or not is_same(city_state.city_world, values.get(
			"settlement_world",
			values.get("city_world", city_state.city_world)
		))
	):
		return false
	if city_state.is_city_founded():
		return true

	var seed_value = values.get(
		"settlement_seed",
		values.get("city_world_seed", city_state.city_seed)
	)
	if not seed_value is int:
		return false

	var top_left: Vector2i = city_object.get(
		"top_left",
		Vector2i(-1, -1)
	)
	var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)
	if not WorldPoliticalState.found_city_settlement(
		settlement_context.settlement_id,
		{
			"city_world_seed": int(seed_value),
			"city_map_size": Vector2i(
				city_state.city_world.width,
				city_state.city_world.height
			),
			"foundation_top_left": top_left,
			"foundation_size": size_tiles,
			"can_build": true,
		}
	):
		return false

	if settlement_context.is_player_polity and settlement_context.is_capital:
		return WorldData.synchronize_player_city_mirrors_for_settlement(
			settlement_context,
			city_state
		)

	return true


static func add_city_object_for_city_state(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> Dictionary:
	return register_completed_city_object_for_city_state(city_state, values)


static func add_city_road_object_for_city_state(
	city_state: CitySettlementSimulationState,
	tile_positions: Array,
	object_owner: String = "player",
	city_world: WorldData = null,
	allowed_construction_site_id: int = -1
) -> Dictionary:
	if city_state == null:
		return {}

	return register_completed_city_object_for_city_state(city_state, {
		"object_type": CityObjectCatalog.CITY_OBJECT_ROAD,
		"footprint_tiles": tile_positions,
		"object_owner": object_owner,
		"city_world": city_world if city_world != null else city_state.city_world,
		"allowed_construction_site_id": allowed_construction_site_id,
	})


static func register_completed_city_object_from_construction_site_for_city_state(
	city_state: CitySettlementSimulationState,
	construction_site_id: int,
	values: Dictionary
) -> Dictionary:
	if not _registration_matches_authoritative_construction_site(
		city_state,
		construction_site_id,
		values
	):
		return {}

	return _register_completed_city_object_for_city_state(
		city_state,
		values,
		construction_site_id
	)


static func register_recovered_city_foundation_object_for_city_state(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> Dictionary:
	if not _is_valid_city_foundation_recovery(city_state, values):
		return {}

	var recovered_object := _register_completed_city_object_for_city_state(
		city_state,
		values,
		-1,
		true
	)
	if recovered_object.is_empty():
		return {}

	city_state.city_runtime_data["foundation_object_id"] = int(
		recovered_object.get("id", -1)
	)
	return recovered_object


static func _register_completed_city_object_for_city_state(
	city_state: CitySettlementSimulationState,
	values: Dictionary,
	preauthorized_construction_site_id: int = -1,
	allow_foundation_recovery: bool = false
) -> Dictionary:
	if city_state == null or city_state.city_world == null:
		return {}

	var object_type := str(values.get("object_type", ""))
	var definition := CityObjectCatalog.get_city_object_definition(object_type)

	if (
		definition.is_empty()
		or (
				not allow_foundation_recovery
				and preauthorized_construction_site_id <= 0
			and not can_use_city_object_definition_for_city_state(
				city_state,
				object_type
			)
		)
		or not _can_defer_foundation_surface_feature_clear(
			city_state,
			definition,
			values
		)
	):
		return {}

	var registration_values := values.duplicate()
	registration_values.erase("allowed_construction_site_id")
	if preauthorized_construction_site_id > 0:
		registration_values["allowed_construction_site_id"] = (
			preauthorized_construction_site_id
		)
	values = registration_values

	var shape_mode := str(
		definition.get(
			"shape_mode",
			CityObjectCatalog.CITY_OBJECT_SHAPE_RECTANGLE
		)
	)
	var footprint_tiles: Array = []
	var city_object: Dictionary = {}

	if shape_mode == CityObjectCatalog.CITY_OBJECT_SHAPE_TILE_AREA:
		var raw_tiles = values.get("footprint_tiles", [])

		if not raw_tiles is Array:
			return {}

		for raw_tile in raw_tiles:
			if raw_tile is Vector2i and not footprint_tiles.has(raw_tile):
				footprint_tiles.append(raw_tile)

		if footprint_tiles.size() != 1:
			return {}

		city_object = {
			"type": object_type,
			"tiles": footprint_tiles.duplicate(),
			"owner": str(values.get("object_owner", "player")),
		}
	else:
		var top_left: Vector2i = values.get(
			"top_left",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var size_tiles: Vector2i = values.get("size_tiles", Vector2i.ZERO)
		footprint_tiles = make_rectangle_city_object_footprint_tiles(
			top_left,
			size_tiles
		)

		if footprint_tiles.is_empty():
			return {}

		city_object = {
			"type": object_type,
			"top_left": top_left,
			"size": size_tiles,
			"owner": str(values.get("object_owner", "player")),
			"shape_mode": shape_mode,
			"footprint_tiles": footprint_tiles.duplicate(),
		}

		var resident_capacity := int(definition.get("resident_capacity", 0))
		if resident_capacity > 0:
			city_object["resident_capacity"] = resident_capacity
			city_object["resident_ids"] = []

		if bool(definition.get("is_workplace", false)):
			city_object["is_workplace"] = true
			city_object["workplace_kind"] = str(
				definition.get(
					"workplace_kind",
					CityObjectCatalog.WORKPLACE_KIND_NONE
				)
			)
			city_object["worker_capacity"] = int(
				definition.get("worker_capacity", 0)
			)
			city_object["assigned_worker_ids"] = []
			city_object["output_resource"] = str(
				definition.get("output_resource", WorldData.RESOURCE_NONE)
			)
			var production_recipe = definition.get("production_recipe", {})
			if production_recipe is Dictionary and not production_recipe.is_empty():
				city_object["production_progress_work_units"] = 0
				city_object["production_status"] = (
					CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS
				)
				city_object["productive_worker_count"] = 0
				city_object["site_productivity_basis_points"] = (
					CityObjectCatalog.DEFAULT_WORKPLACE_SITE_PRODUCTIVITY_BASIS_POINTS
				)

		var raw_allowed_storage_resources = definition.get("storage_resources", [])
		if (
			raw_allowed_storage_resources is Array
			and not raw_allowed_storage_resources.is_empty()
		):
			city_object["stored_resources"] = (
				CityResourceContainerSystem.make_empty_city_object_storage_for_type(
					object_type
				)
			)

	if bool(values.get("defer_surface_feature_clear", false)):
		city_object[_DEFERRED_FOUNDATION_SURFACE_CLEAR_FIELD] = true
		city_object[_DEFERRED_FOUNDATION_REGISTRATION_BASELINE_FIELD] = (
			_make_deferred_foundation_registration_baseline(city_state)
		)

	var allowed_construction_site_id := int(
		values.get("allowed_construction_site_id", -1)
	)
	var allowed_occupied_object_id := int(
		values.get("allowed_occupied_object_id", -1)
	)
	var footprint_lookup: Dictionary = {}

	for raw_tile in footprint_tiles:
		if not raw_tile is Vector2i or footprint_lookup.has(raw_tile):
			return {}

		var tile_position: Vector2i = raw_tile
		if not city_state.city_world.is_in_bounds(tile_position.x, tile_position.y):
			return {}

		var tile: Dictionary = (
			city_state.city_world.get_tile_for_internal_read(
				tile_position.x,
				tile_position.y
			)
		)
		if (
			str(tile.get("terrain", CityObjectCatalog.TERRAIN_WATER)) in [
				CityObjectCatalog.TERRAIN_WATER,
				WorldData.TERRAIN_MOUNTAIN,
			]
			or not bool(tile.get("is_land", false))
		):
			return {}

		var occupied_object_id := get_city_object_id_at_tile_for_city_state(
			city_state,
			tile_position
		)
		if occupied_object_id > 0 and occupied_object_id != allowed_occupied_object_id:
			return {}

		var construction_site_id := int(
			city_state.construction_state.construction_site_id_by_tile.get(
				tile_position,
				-1
			)
		)
		if (
			construction_site_id > 0
			and construction_site_id != allowed_construction_site_id
		):
			return {}

		for raw_ground_pile in city_state.logistics_state.ground_piles:
			if (
				raw_ground_pile is Dictionary
				and int(raw_ground_pile.get("amount", 0)) > 0
				and raw_ground_pile.get(
					"tile_position",
					CityCitizens.INVALID_CITY_TILE_POSITION
				) == tile_position
			):
				return {}

		footprint_lookup[tile_position] = true

	if not get_city_object_topology_blocking_citizen_ids_for_city_state(
		city_state,
		object_type,
		footprint_tiles
	).is_empty():
		return {}

	var object_state := city_state.object_state
	var object_id := object_state.next_object_id

	if object_id <= 0 or get_city_object_index_by_id_for_city_state(
		city_state,
		object_id
	) >= 0:
		return {}

	city_object["id"] = object_id
	var stored_city_object := _make_read_only_city_object_record(city_object)
	object_state.next_object_id += 1
	object_state.objects.append(stored_city_object)
	var object_index := object_state.objects.size() - 1
	object_state.object_index_by_id[object_id] = object_index

	for tile_position in footprint_tiles:
		object_state.occupied_tiles[tile_position] = object_id

	if not bool(values.get("defer_surface_feature_clear", false)):
		WorldData.clear_city_surface_features_at_tiles(
			city_state.city_world,
			footprint_tiles
		)
	object_state.object_version += 1

	if CityObjectCatalog.city_object_is_workplace(stored_city_object):
		city_state.workplace_state.workplace_version += 1

	if stored_city_object.has("stored_resources"):
		CityResourceAccountingSystem.mark_city_container_changed_for_city_state(
			city_state,
			stored_city_object
		)

	if object_type == CityObjectCatalog.CITY_OBJECT_HOUSE:
		CityAssignmentSystem.assign_homeless_citizens_to_available_housing_for_city_state(
			city_state
		)

	return get_city_object_by_id_for_city_state(city_state, object_id)


static func finalize_deferred_city_foundation_surface_features_for_city_state(
	city_state: CitySettlementSimulationState,
	expected_object_id: int
) -> bool:
	var city_object := get_city_object_by_id_for_city_state(
		city_state,
		expected_object_id
	)

	if (
		city_state == null
		or city_state.city_world == null
		or not bool(
			city_object.get(
				_DEFERRED_FOUNDATION_SURFACE_CLEAR_FIELD,
				false
			)
		)
		or not _city_object_is_immediate_foundation(city_object)
	):
		return false

	var footprint_tiles := get_city_object_footprint_tiles(city_object)
	if footprint_tiles.is_empty():
		return false

	WorldData.clear_city_surface_features_at_tiles(
		city_state.city_world,
		footprint_tiles
	)
	var object_index := get_city_object_index_by_id_for_city_state(
		city_state,
		expected_object_id
	)
	return _patch_city_object_fields_at_index(
		get_state_for_city_state(city_state),
		object_index,
		expected_object_id,
		{},
		[
			_DEFERRED_FOUNDATION_SURFACE_CLEAR_FIELD,
			_DEFERRED_FOUNDATION_REGISTRATION_BASELINE_FIELD,
		],
		[
			_DEFERRED_FOUNDATION_SURFACE_CLEAR_FIELD,
			_DEFERRED_FOUNDATION_REGISTRATION_BASELINE_FIELD,
		]
	)


static func rollback_completed_city_object_for_city_state(
	city_state: CitySettlementSimulationState,
	expected_object_id: int
) -> bool:
	var object_state := get_state_for_city_state(city_state)

	if (
		object_state == null
		or expected_object_id <= 0
		or object_state.next_object_id != expected_object_id + 1
		or object_state.objects.is_empty()
	):
		return false

	var object_index := get_city_object_index_by_id_for_city_state(
		city_state,
		expected_object_id
	)
	if object_index != object_state.objects.size() - 1:
		return false

	var raw_city_object = object_state.objects[object_index]
	if not raw_city_object is Dictionary:
		return false
	var city_object: Dictionary = raw_city_object
	var raw_registration_baseline = city_object.get(
		_DEFERRED_FOUNDATION_REGISTRATION_BASELINE_FIELD,
		{}
	)
	if (
		int(city_object.get("id", -1)) != expected_object_id
		or not bool(
			city_object.get(
				_DEFERRED_FOUNDATION_SURFACE_CLEAR_FIELD,
				false
			)
		)
		or not _city_object_is_immediate_foundation(city_object)
		or not raw_registration_baseline is Dictionary
		or not _is_valid_deferred_foundation_registration_baseline(
			raw_registration_baseline
		)
	):
		return false
	var registration_baseline: Dictionary = raw_registration_baseline

	var footprint_tiles := get_city_object_footprint_tiles(city_object)
	var footprint_lookup: Dictionary = {}
	if footprint_tiles.is_empty():
		return false
	for raw_tile in footprint_tiles:
		if (
			not raw_tile is Vector2i
			or footprint_lookup.has(raw_tile)
			or int(object_state.occupied_tiles.get(raw_tile, -1))
			!= expected_object_id
		):
			return false
		footprint_lookup[raw_tile] = true
	for raw_tile in object_state.occupied_tiles.keys():
		if (
			int(object_state.occupied_tiles.get(raw_tile, -1))
			== expected_object_id
			and not footprint_lookup.has(raw_tile)
		):
			return false

	for raw_tile in footprint_tiles:
		object_state.occupied_tiles.erase(raw_tile)
	object_state.object_index_by_id.erase(expected_object_id)
	object_state.objects.remove_at(object_index)
	object_state.next_object_id = expected_object_id
	object_state.object_version = int(
		registration_baseline["object_version"]
	)
	city_state.workplace_state.workplace_version = int(
		registration_baseline["workplace_version"]
	)
	return (
		CityResourceAccountingSystem.restore_city_resource_accounting_snapshot_for_city_state(
			city_state,
			registration_baseline
		)
	)
















static func reset_city_object_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	var state := get_state_for_city_state(city_state)

	if state == null:
		return

	state.objects.clear()
	state.object_index_by_id.clear()
	state.occupied_tiles.clear()
	state.next_object_id = 1

	mark_city_objects_changed_for_city_state(city_state)


static func _sort_city_tiles_y_then_x(
	tile_a: Vector2i,
	tile_b: Vector2i
) -> bool:
	if tile_a.y == tile_b.y:
		return tile_a.x < tile_b.x

	return tile_a.y < tile_b.y



static func can_use_city_object_definition_for_city_state(
	city_state: CitySettlementSimulationState,
	object_type: String
) -> bool:
	if city_state == null:
		return false

	var definition := CityObjectCatalog.get_city_object_definition(object_type)

	if definition.is_empty():
		return false

	if (
		bool(definition.get("requires_city", false))
		and not city_state.can_build_city_objects()
	):
		return false

	if (
		bool(definition.get("requires_no_city", false))
		and city_state.is_city_founded()
	):
		return false

	return true


static func _can_defer_foundation_surface_feature_clear(
	city_state: CitySettlementSimulationState,
	definition: Dictionary,
	values: Dictionary
) -> bool:
	if not bool(values.get("defer_surface_feature_clear", false)):
		return true

	return (
		city_state != null
		and not city_state.is_city_founded()
		and str(definition.get("type", ""))
		== CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		and bool(definition.get("requires_no_city", false))
		and not bool(definition.get("construction_enabled", false))
		and str(definition.get("placement_effect", ""))
		== CityObjectCatalog.CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY
	)


static func _make_deferred_foundation_registration_baseline(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	if city_state == null:
		return {}

	var accounting_state := city_state.resource_accounting_state
	return {
		"object_version": city_state.object_state.object_version,
		"workplace_version": city_state.workplace_state.workplace_version,
		"container_version": accounting_state.container_version,
		"public_storage_version": accounting_state.public_storage_version,
		"owned_resource_amount_cache": (
			accounting_state.owned_resource_amount_cache.duplicate(true)
		),
		"owned_resource_amount_cache_container_version": (
			accounting_state.owned_resource_amount_cache_container_version
		),
	}


static func _is_valid_deferred_foundation_registration_baseline(
	baseline: Dictionary
) -> bool:
	for key in [
		"object_version",
		"workplace_version",
		"container_version",
		"public_storage_version",
		"owned_resource_amount_cache_container_version",
	]:
		if not baseline.get(key) is int:
			return false
	return baseline.get("owned_resource_amount_cache") is Dictionary


static func _city_object_is_immediate_foundation(
	city_object: Dictionary
) -> bool:
	var object_type := str(city_object.get("type", ""))
	var definition := CityObjectCatalog.get_city_object_definition(object_type)
	return (
		object_type == CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		and not definition.is_empty()
		and bool(definition.get("requires_no_city", false))
		and not bool(definition.get("construction_enabled", false))
		and str(definition.get("placement_effect", ""))
		== CityObjectCatalog.CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY
	)


static func _is_valid_city_foundation_recovery(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> bool:
	if (
		city_state == null
		or city_state.city_world == null
		or not city_state.has_city_foundation_footprint()
		or str(values.get("object_type", ""))
		!= CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		or values.get("city_world", city_state.city_world) != city_state.city_world
	):
		return false

	var expected_object_id := int(
		city_state.city_runtime_data.get("foundation_object_id", -1)
	)
	if (
		expected_object_id <= 0
		or not get_city_object_by_id_for_city_state(
			city_state,
			expected_object_id
		).is_empty()
	):
		return false

	for raw_city_object in city_state.object_state.objects:
		if (
			raw_city_object is Dictionary
			and str(raw_city_object.get("type", ""))
			== CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		):
			return false

	var expected_top_left = city_state.city_runtime_data.get(
		"foundation_top_left",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var expected_size = city_state.city_runtime_data.get(
		"foundation_size",
		Vector2i.ZERO
	)
	var expected_owner := str(
		city_state.city_runtime_data.get(
			"foundation_object_owner",
			""
		)
	)
	return (
		expected_top_left is Vector2i
		and expected_size is Vector2i
		and not expected_owner.is_empty()
		and values.get("top_left") == expected_top_left
		and values.get("size_tiles") == expected_size
		and str(values.get("object_owner", "")) == expected_owner
		and not bool(values.get("defer_surface_feature_clear", false))
	)


static func _registration_matches_authoritative_construction_site(
	city_state: CitySettlementSimulationState,
	construction_site_id: int,
	values: Dictionary
) -> bool:
	if (
		city_state == null
		or city_state.city_world == null
		or construction_site_id <= 0
		or values.get("city_world", city_state.city_world) != city_state.city_world
	):
		return false

	var site := (
		CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
			city_state,
			construction_site_id
		)
	)
	if (
		site.is_empty()
		or int(site.get("id", -1)) != construction_site_id
		or str(site.get("target_kind", ""))
		!= CityConstructionSystem.CITY_CONSTRUCTION_TARGET_NEW
		or str(site.get("finalization_state", ""))
		!= CityConstructionSystem.CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE
		or str(site.get("object_type", ""))
		!= str(values.get("object_type", ""))
		or str(site.get("owner", "player"))
		!= str(values.get("object_owner", "player"))
		or site.get("top_left") != values.get("top_left")
		or site.get("size") != values.get("size_tiles")
		or not _city_tile_arrays_match_exactly(
			site.get("footprint_tiles", []),
			values.get("footprint_tiles", [])
		)
	):
		return false

	return true


static func _city_tile_arrays_match_exactly(
	raw_tiles_a,
	raw_tiles_b
) -> bool:
	if not raw_tiles_a is Array or not raw_tiles_b is Array:
		return false
	if raw_tiles_a.size() != raw_tiles_b.size() or raw_tiles_a.is_empty():
		return false

	var tile_lookup: Dictionary = {}
	for raw_tile in raw_tiles_a:
		if not raw_tile is Vector2i or tile_lookup.has(raw_tile):
			return false
		tile_lookup[raw_tile] = true
	for raw_tile in raw_tiles_b:
		if not raw_tile is Vector2i or not tile_lookup.erase(raw_tile):
			return false
	return tile_lookup.is_empty()

#endregion

#region World Grid and Tile State
