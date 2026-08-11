# File responsibility: Validate construction, ground-pile, work-order, and haul-reservation state.
extends RefCounted

const CityWorkSystemScript := preload(
	"res://scripts/city/simulation/systems/CityWorkSystem.gd"
)


#region Construction and Ground Piles
static func _validate_city_construction_state(
	errors: Array[String],
	object_lookup: Dictionary
) -> Dictionary:
	var site_lookup: Dictionary = {}
	var expected_tile_lookup: Dictionary = {}
	var maximum_site_id := 0
	var valid_phases := [
		CityConstructionSystem.CITY_CONSTRUCTION_PHASE_CLEARING,
		CityConstructionSystem.CITY_CONSTRUCTION_PHASE_GATHERING,
		CityConstructionSystem.CITY_CONSTRUCTION_PHASE_LABOR,
	]
	var valid_target_kinds := [
		CityConstructionSystem.CITY_CONSTRUCTION_TARGET_NEW,
		CityConstructionSystem.CITY_CONSTRUCTION_TARGET_MODIFICATION,
	]

	for site_index in range(CityConstructionSystem.get_current_state().construction_sites.size()):
		var raw_site = CityConstructionSystem.get_current_state().construction_sites[site_index]

		if not raw_site is Dictionary:
			errors.append(
				"city_construction_sites["
				+ str(site_index)
				+ "] is not a Dictionary."
			)
			continue

		var site: Dictionary = raw_site
		var site_id := int(site.get("id", -1))
		var object_type := str(site.get("object_type", ""))
		var phase := str(site.get("phase", ""))
		var target_kind := str(site.get("target_kind", ""))
		var target_object_id := int(
			site.get("target_object_id", -1)
		)
		var raw_footprint = site.get("footprint_tiles", [])
		var raw_recipe = site.get("material_recipe", {})
		var raw_work_positions = site.get("work_positions", [])

		if site_id <= 0 or site_lookup.has(site_id):
			errors.append(
				"Construction site at index "
				+ str(site_index)
				+ " has an invalid or duplicate ID "
				+ str(site_id)
				+ "."
			)
			continue

		site_lookup[site_id] = site_index
		maximum_site_id = maxi(maximum_site_id, site_id)

		if (
			int(
				CityConstructionSystem.get_current_state().construction_site_index_by_id.get(
					site_id,
					-1
				)
			)
			!= site_index
		):
			errors.append(
				"Construction site index lookup disagrees for ID "
				+ str(site_id)
				+ "."
			)

		if not CityConstructionSystem.city_object_type_uses_construction(object_type):
			errors.append(
				"Construction site "
				+ str(site_id)
				+ " has non-constructible target '"
				+ object_type
				+ "'."
			)

		if target_kind not in valid_target_kinds:
			errors.append(
				"Construction site "
				+ str(site_id)
				+ " has invalid target kind '"
				+ target_kind
				+ "'."
			)
		elif target_kind == CityConstructionSystem.CITY_CONSTRUCTION_TARGET_NEW:
			if target_object_id != -1:
				errors.append(
					"New construction site "
					+ str(site_id)
					+ " unexpectedly targets object "
					+ str(target_object_id)
					+ "."
				)
		else:
			var target_object := CityObjectSystem.get_city_object_by_id(
				target_object_id
			)

			if (
				not object_lookup.has(target_object_id)
				or target_object.is_empty()
				or str(target_object.get("type", "")) != object_type
			):
				errors.append(
					"Modification site "
					+ str(site_id)
					+ " targets a missing or incompatible object."
				)

		if phase not in valid_phases:
			errors.append(
				"Construction site "
				+ str(site_id)
				+ " has invalid phase '"
				+ phase
				+ "'."
			)

		if not raw_footprint is Array or raw_footprint.is_empty():
			errors.append(
				"Construction site "
				+ str(site_id)
				+ " has no valid footprint."
			)
		else:
			var local_tile_lookup: Dictionary = {}

			for raw_tile in raw_footprint:
				if not raw_tile is Vector2i:
					errors.append(
						"Construction site "
						+ str(site_id)
						+ " has a non-Vector2i footprint tile."
					)
					continue

				var tile_position: Vector2i = raw_tile

				if local_tile_lookup.has(tile_position):
					errors.append(
						"Construction site "
						+ str(site_id)
						+ " repeats footprint tile "
						+ str(tile_position)
						+ "."
					)
					continue

				local_tile_lookup[tile_position] = true

				if expected_tile_lookup.has(tile_position):
					errors.append(
						"Construction sites "
						+ str(expected_tile_lookup[tile_position])
						+ " and "
						+ str(site_id)
						+ " overlap at "
						+ str(tile_position)
						+ "."
					)
				else:
					expected_tile_lookup[tile_position] = site_id

				if (
					WorldPoliticalState.get_current_city_world() != null
					and not WorldPoliticalState.get_current_city_world().is_in_bounds(
						tile_position.x,
						tile_position.y
					)
				):
					errors.append(
						"Construction site "
						+ str(site_id)
						+ " is out of bounds at "
						+ str(tile_position)
						+ "."
					)

				if CityObjectSystem.has_city_object_at_tile(tile_position):
					var completed_object_id := int(
						CityObjectSystem.get_city_object_id_at_tile(
							tile_position
						)
					)

					if (
						object_lookup.has(completed_object_id)
						and not (
							target_kind
							== CityConstructionSystem.CITY_CONSTRUCTION_TARGET_MODIFICATION
							and completed_object_id
							== target_object_id
						)
					):
						errors.append(
							"Construction site "
							+ str(site_id)
							+ " overlaps completed object "
							+ str(completed_object_id)
							+ "."
						)

		if not raw_recipe is Dictionary:
			errors.append(
				"Construction site "
				+ str(site_id)
				+ " has a non-Dictionary material recipe."
			)
		else:
			for raw_resource in raw_recipe.keys():
				if (
					typeof(raw_resource) != TYPE_STRING
					or not CityResourceCatalog.is_city_resource_type(
						str(raw_resource)
					)
					or typeof(raw_recipe[raw_resource]) != TYPE_INT
					or int(raw_recipe[raw_resource]) <= 0
				):
					errors.append(
						"Construction site "
						+ str(site_id)
						+ " has an invalid recipe entry."
					)

		var required_labor := int(
			site.get("required_labor_minutes", 0)
		)
		var completed_labor := int(
			site.get("completed_labor_minutes", -1)
		)

		if (
			required_labor <= 0
			or completed_labor < 0
			or completed_labor > required_labor
		):
			errors.append(
				"Construction site "
				+ str(site_id)
				+ " has invalid labor progress."
			)

		if not raw_work_positions is Array or raw_work_positions.is_empty():
			errors.append(
				"Construction site "
				+ str(site_id)
				+ " has no work positions."
			)

	if (
		CityConstructionSystem.get_current_state().construction_site_index_by_id.size()
		!= site_lookup.size()
	):
		errors.append(
			"Construction site registry and ID lookup have different sizes."
		)

	if CityConstructionSystem.get_current_state().construction_site_id_by_tile != expected_tile_lookup:
		errors.append(
			"Construction site footprint lookup does not match site state."
		)

	if CityConstructionSystem.get_current_state().next_construction_site_id <= maximum_site_id:
		errors.append(
			"next_city_construction_site_id must exceed every site ID."
		)

	return site_lookup




static func _validate_city_ground_pile_state(
	errors: Array[String],
	construction_site_lookup: Dictionary
) -> Dictionary:
	var ground_pile_lookup: Dictionary = {}
	var nonfull_pile_id_by_resource_tile: Dictionary = {}
	var maximum_ground_pile_id := 0

	for pile_index in range(CityLogisticsSystem.get_current_state().ground_piles.size()):
		var raw_ground_pile = CityLogisticsSystem.get_current_state().ground_piles[pile_index]

		if not raw_ground_pile is Dictionary:
			errors.append(
				"city_ground_piles["
				+ str(pile_index)
				+ "] is not a Dictionary."
			)
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var ground_pile_id := int(ground_pile.get("id", -1))
		var raw_tile_position = ground_pile.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var resource := str(
			ground_pile.get("resource_type", WorldData.RESOURCE_NONE)
		)
		var raw_amount = ground_pile.get("amount")
		var construction_site_id := (
			CityLogisticsSystem.get_city_ground_pile_construction_site_id(
				ground_pile
			)
		)

		if ground_pile_id <= 0:
			errors.append(
				"Ground pile at index "
				+ str(pile_index)
				+ " has invalid ID "
				+ str(ground_pile_id)
				+ "."
			)
			continue

		if ground_pile_lookup.has(ground_pile_id):
			errors.append(
				"Duplicate ground pile ID "
				+ str(ground_pile_id)
				+ "."
			)
			continue

		ground_pile_lookup[ground_pile_id] = pile_index
		maximum_ground_pile_id = maxi(
			maximum_ground_pile_id,
			ground_pile_id
		)

		if not raw_tile_position is Vector2i:
			errors.append(
				"Ground pile "
				+ str(ground_pile_id)
				+ " has a non-Vector2i tile."
			)
		else:
			var tile_position: Vector2i = raw_tile_position

			if (
				WorldPoliticalState.get_current_city_world() != null
				and not CityLogisticsSystem.can_city_ground_pile_exist_at_tile(
					WorldPoliticalState.get_current_city_world(),
					tile_position
				)
			):
				errors.append(
					"Ground pile "
					+ str(ground_pile_id)
					+ " occupies invalid tile "
					+ str(tile_position)
					+ "."
				)

		if not CityResourceCatalog.is_city_resource_type(resource):
			errors.append(
				"Ground pile "
				+ str(ground_pile_id)
				+ " has invalid resource '"
				+ resource
				+ "'."
			)

		if construction_site_id > 0:
			var construction_site := (
				CityConstructionSystem.get_city_construction_site_by_id(
					construction_site_id
				)
			)

			if (
				not construction_site_lookup.has(construction_site_id)
				or construction_site.is_empty()
			):
				errors.append(
					"Ground pile "
					+ str(ground_pile_id)
					+ " belongs to missing construction site "
					+ str(construction_site_id)
					+ "."
				)
			elif (
				raw_tile_position is Vector2i
				and not construction_site.get(
					"footprint_tiles",
					[]
				).has(raw_tile_position)
			):
				errors.append(
					"Ground pile "
					+ str(ground_pile_id)
					+ " is outside its construction footprint."
				)

		if typeof(raw_amount) != TYPE_INT or int(raw_amount) <= 0:
			errors.append(
				"Ground pile "
				+ str(ground_pile_id)
				+ " has invalid amount "
				+ str(raw_amount)
				+ "."
			)
		elif int(raw_amount) > CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY:
			errors.append(
				"Ground pile "
				+ str(ground_pile_id)
				+ " exceeds capacity "
				+ str(CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY)
				+ "."
			)
		elif (
			raw_tile_position is Vector2i
			and CityResourceCatalog.is_city_resource_type(resource)
			and int(raw_amount) < CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY
		):
			var tile_position: Vector2i = raw_tile_position
			var nearby_nonfull_pile_id := -1
			var merge_radius := (
				CityLogisticsSystem.CITY_GROUND_PILE_MERGE_RADIUS_TILES
			)
			var merge_radius_squared := merge_radius * merge_radius

			for offset_y in range(-merge_radius, merge_radius + 1):
				for offset_x in range(-merge_radius, merge_radius + 1):
					if (
						offset_x * offset_x + offset_y * offset_y
						> merge_radius_squared
					):
						continue

					var nearby_tile := (
						tile_position
						+ Vector2i(offset_x, offset_y)
					)
					var nearby_key := (
						resource
						+ ":"
						+ str(construction_site_id)
						+ ":"
						+ str(nearby_tile)
					)

					if nonfull_pile_id_by_resource_tile.has(
						nearby_key
					):
						nearby_nonfull_pile_id = int(
							nonfull_pile_id_by_resource_tile[
								nearby_key
							]
						)
						break

				if nearby_nonfull_pile_id > 0:
					break

			if nearby_nonfull_pile_id > 0:
				errors.append(
					"Non-full ground piles "
					+ str(nearby_nonfull_pile_id)
					+ " and "
					+ str(ground_pile_id)
					+ " should have coalesced within radius "
					+ str(merge_radius)
					+ " for "
					+ resource
					+ "."
				)

			var pile_key := (
				resource
				+ ":"
				+ str(construction_site_id)
				+ ":"
				+ str(tile_position)
			)
			nonfull_pile_id_by_resource_tile[pile_key] = (
				ground_pile_id
			)


		if int(
			CityLogisticsSystem.get_current_state().ground_pile_index_by_id.get(
				ground_pile_id,
				-1
			)
		) != pile_index:
			errors.append(
				"Ground pile index lookup disagrees for ID "
				+ str(ground_pile_id)
				+ "."
			)

	if (
		CityLogisticsSystem.get_current_state().ground_pile_index_by_id.size()
		!= ground_pile_lookup.size()
	):
		errors.append(
			"Ground pile registry array and ID lookup have different sizes."
		)

	if CityLogisticsSystem.get_current_state().next_ground_pile_id <= maximum_ground_pile_id:
		errors.append(
			"next_city_ground_pile_id must be greater than every existing pile ID."
		)

	return ground_pile_lookup




#endregion

#region Work Orders
static func _validate_city_work_orders(
	errors: Array[String],
	citizen_lookup: Dictionary,
	construction_site_lookup: Dictionary
) -> int:
	var expected_source_lookup: Dictionary = {}
	var maximum_order_id := 0
	var required_order_fields: Array[String] = [
		"id",
		"source_key",
		"order_type",
		"source_id",
		"creation_sequence",
		"created_world_minute",
		"priority_rank",
		"state",
		"phase",
		"jobs",
		"active_worker_count",
		"active_citizen_ids",
		"useful_parallel_capacity",
		"blocked_reason",
		"last_progress_world_minute",
		"last_attention_world_minute",
		"progress_signature",
	]

	for raw_order_id in CityWorkSystem.get_current_work_state().work_orders.keys():
		maximum_order_id = _validate_city_work_order_entry({
			"errors": errors,
			"citizen_lookup": citizen_lookup,
			"construction_site_lookup": construction_site_lookup,
			"expected_source_lookup": expected_source_lookup,
			"required_order_fields": required_order_fields,
			"maximum_order_id": maximum_order_id,
			"raw_order_id": raw_order_id,
		})

	for raw_source_key in CityWorkSystem.get_current_work_state().work_order_id_by_source_key.keys():
		var raw_lookup_order_id = (
			CityWorkSystem.get_current_work_state().work_order_id_by_source_key.get(raw_source_key)
		)

		if (
			typeof(raw_source_key) != TYPE_STRING
			or typeof(raw_lookup_order_id) != TYPE_INT
		):
			errors.append(
				"Work-order source lookup contains an invalid key or ID."
			)

	if CityWorkSystem.get_current_work_state().work_order_id_by_source_key != expected_source_lookup:
		errors.append(
			"Work-order source lookup is not a bijection with the registry."
		)

	if CityWorkSystem.get_current_work_state().next_work_order_id <= maximum_order_id:
		errors.append(
			"next_city_work_order_id must exceed every work-order ID."
		)

	return CityWorkSystem.get_current_work_state().work_orders.size()




static func _validate_city_work_order_entry(
	values: Dictionary
) -> int:
	var errors: Array[String] = values.get("errors", [])
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	var construction_site_lookup: Dictionary = values.get(
		"construction_site_lookup",
		{}
	)
	var expected_source_lookup: Dictionary = values.get(
		"expected_source_lookup",
		{}
	)
	var required_order_fields: Array[String] = values.get(
		"required_order_fields",
		[]
	)
	var maximum_order_id := int(values.get("maximum_order_id", 0))
	var raw_order_id = values.get("raw_order_id")
	if typeof(raw_order_id) != TYPE_INT:
		errors.append(
			"Work-order registry contains a non-integer key."
		)
		return maximum_order_id

	var order_id: int = raw_order_id
	maximum_order_id = maxi(maximum_order_id, order_id)
	var raw_order = CityWorkSystem.get_current_work_state().work_orders.get(order_id, {})

	if not raw_order is Dictionary:
		errors.append(
			"Work order "
			+ str(order_id)
			+ " is not a Dictionary."
		)
		return maximum_order_id

	var order: Dictionary = raw_order
	var missing_field := false

	for field_name in required_order_fields:
		if order.has(field_name):
			continue

		errors.append(
			"Work order "
			+ str(order_id)
			+ " is missing '"
			+ field_name
			+ "'."
		)
		missing_field = true

	if missing_field:
		return maximum_order_id

	var raw_stored_id = order.get("id")
	var raw_source_key = order.get("source_key")
	var raw_order_type = order.get("order_type")
	var raw_source_id = order.get("source_id")
	var raw_creation_sequence = order.get("creation_sequence")
	var raw_created_minute = order.get("created_world_minute")
	var raw_priority_rank = order.get("priority_rank")
	var raw_state = order.get("state")
	var raw_phase = order.get("phase")
	var raw_jobs = order.get("jobs")
	var raw_active_worker_count = order.get("active_worker_count")
	var raw_active_citizen_ids = order.get("active_citizen_ids")
	var raw_useful_capacity = order.get("useful_parallel_capacity")
	var raw_blocked_reason = order.get("blocked_reason")
	var raw_last_progress_minute = order.get(
		"last_progress_world_minute"
	)
	var raw_last_attention_minute = order.get(
		"last_attention_world_minute"
	)
	var raw_progress_signature = order.get("progress_signature")
	var order_types_are_valid := true

	for integer_field in [
		raw_stored_id,
		raw_source_id,
		raw_creation_sequence,
		raw_created_minute,
		raw_priority_rank,
		raw_active_worker_count,
		raw_useful_capacity,
		raw_last_progress_minute,
		raw_last_attention_minute,
	]:
		if typeof(integer_field) != TYPE_INT:
			order_types_are_valid = false
			break

	if not order_types_are_valid:
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has a non-integer identifier, priority, count, or minute."
		)

	if (
		typeof(raw_source_key) != TYPE_STRING
		or typeof(raw_order_type) != TYPE_STRING
		or typeof(raw_state) != TYPE_STRING
		or typeof(raw_phase) != TYPE_STRING
		or typeof(raw_blocked_reason) != TYPE_STRING
		or typeof(raw_progress_signature) != TYPE_STRING
	):
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has a non-string source, type, state, reason, or signature."
		)
		order_types_are_valid = false

	if not raw_jobs is Array:
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has a non-Array jobs field."
		)
		order_types_are_valid = false

	if not raw_active_citizen_ids is Array:
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has a non-Array active-citizen field."
		)
		order_types_are_valid = false

	if not order_types_are_valid:
		return maximum_order_id

	var stored_id: int = raw_stored_id
	var source_key: String = raw_source_key
	var order_type: String = raw_order_type
	var source_id: int = raw_source_id
	var creation_sequence: int = raw_creation_sequence
	var created_minute: int = raw_created_minute
	var priority_rank: int = raw_priority_rank
	var state: String = raw_state
	var phase: String = raw_phase
	var jobs: Array = raw_jobs
	var active_worker_count: int = raw_active_worker_count
	var active_citizen_ids: Array = raw_active_citizen_ids
	var useful_capacity: int = raw_useful_capacity
	var blocked_reason: String = raw_blocked_reason
	var last_progress_minute: int = raw_last_progress_minute
	var last_attention_minute: int = raw_last_attention_minute

	var order_context := {
		"errors": errors,
		"citizen_lookup": citizen_lookup,
		"construction_site_lookup": construction_site_lookup,
		"expected_source_lookup": expected_source_lookup,
		"order_id": order_id,
		"stored_id": stored_id,
		"source_key": source_key,
		"order_type": order_type,
		"source_id": source_id,
		"creation_sequence": creation_sequence,
		"created_minute": created_minute,
		"priority_rank": priority_rank,
		"state": state,
		"phase": phase,
		"active_worker_count": active_worker_count,
		"active_citizen_ids": active_citizen_ids,
		"useful_capacity": useful_capacity,
		"blocked_reason": blocked_reason,
		"last_progress_minute": last_progress_minute,
		"last_attention_minute": last_attention_minute,
	}
	_validate_city_work_order_identity(order_context)
	_validate_city_work_order_source_state(order_context)
	_validate_city_work_order_runtime_state(order_context)
	_validate_city_work_order_active_citizens(order_context)

	_validate_city_work_order_jobs({
		"errors": errors,
		"order_id": order_id,
		"jobs": jobs,
		"citizen_lookup": citizen_lookup,
		"order_active_citizen_ids": active_citizen_ids,
	})


	return maximum_order_id

static func _validate_city_work_order_identity(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var expected_source_lookup: Dictionary = values.get(
		"expected_source_lookup",
		{}
	)
	var order_id := int(values.get("order_id", -1))
	var stored_id := int(values.get("stored_id", -1))
	var source_key := str(values.get("source_key", ""))
	var order_type := str(values.get("order_type", ""))
	var source_id := int(values.get("source_id", -1))
	var creation_sequence := int(values.get("creation_sequence", -1))

	if order_id <= 0 or stored_id != order_id:
		errors.append(
			"Work-order key/ID mismatch for "
			+ str(order_id)
			+ "."
		)

	if creation_sequence <= 0 or creation_sequence != order_id:
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has an invalid deterministic creation sequence."
		)

	if source_id <= 0 or source_key.is_empty():
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has an invalid source identity."
		)
		return

	var expected_source_key := order_type + ":" + str(source_id)

	if source_key != expected_source_key:
		errors.append(
			"Work order "
			+ str(order_id)
			+ " source key does not match its type and source ID."
		)

	if expected_source_lookup.has(source_key):
		errors.append(
			"Multiple work orders use source key '"
			+ source_key
			+ "'."
		)
	else:
		expected_source_lookup[source_key] = order_id


static func _validate_city_work_order_source_state(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var construction_site_lookup: Dictionary = values.get(
		"construction_site_lookup",
		{}
	)
	var order_id := int(values.get("order_id", -1))
	var order_type := str(values.get("order_type", ""))
	var source_id := int(values.get("source_id", -1))
	var phase := str(values.get("phase", ""))

	if order_type not in [
		CityWorkSystemScript.ORDER_TYPE_COMMAND_GROUP,
		CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE,
	]:
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has invalid type '"
			+ order_type
			+ "'."
		)
	elif not _city_work_order_source_exists(
		order_type,
		source_id,
		construction_site_lookup
	):
		errors.append(
			"Work order "
			+ str(order_id)
			+ " references a missing or incompatible source record."
		)
	elif (
		order_type == CityWorkSystemScript.ORDER_TYPE_COMMAND_GROUP
		and phase != CityWorkSystemScript.ORDER_PHASE_COMMANDS
	):
		errors.append(
			"Command-group work order "
			+ str(order_id)
			+ " has invalid phase '"
			+ phase
			+ "'."
		)
	elif order_type == CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE:
		var source_site := CityConstructionSystem.get_city_construction_site_by_id(
			source_id
		)

		if (
			not source_site.is_empty()
			and phase != str(source_site.get("phase", ""))
		):
			errors.append(
				"Construction work order "
				+ str(order_id)
				+ " phase disagrees with its site."
			)


static func _validate_city_work_order_runtime_state(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	var order_id := int(values.get("order_id", -1))
	var created_minute := int(values.get("created_minute", -1))
	var priority_rank := int(values.get("priority_rank", -1))
	var state := str(values.get("state", ""))
	var active_worker_count := int(values.get("active_worker_count", -1))
	var useful_capacity := int(values.get("useful_capacity", -1))
	var blocked_reason := str(values.get("blocked_reason", ""))
	var last_progress_minute := int(values.get("last_progress_minute", -1))
	var last_attention_minute := int(
		values.get("last_attention_minute", -1)
	)

	if (
		priority_rank < CityWorkSystemScript.PRIORITY_LOW
		or priority_rank > CityWorkSystemScript.PRIORITY_URGENT
	):
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has an out-of-range priority."
		)

	if state not in [
		CityWorkSystemScript.ORDER_STATE_ACTIVE,
		CityWorkSystemScript.ORDER_STATE_BLOCKED,
		CityWorkSystemScript.ORDER_STATE_CANCELLED,
	]:
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has invalid state '"
			+ state
			+ "'."
		)
	elif (
		(state == CityWorkSystemScript.ORDER_STATE_ACTIVE)
		!= blocked_reason.is_empty()
	):
		errors.append(
			"Work order "
			+ str(order_id)
			+ " state and blocked reason disagree."
		)

	if (
		created_minute < 0
		or last_progress_minute < created_minute
		or last_attention_minute < created_minute
	):
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has invalid progress or attention chronology."
		)

	if (
		active_worker_count < 0
		or active_worker_count > citizen_lookup.size()
		or useful_capacity <= 0
	):
		errors.append(
			"Work order "
			+ str(order_id)
			+ " has invalid worker accounting."
		)


static func _validate_city_work_order_active_citizens(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	var order_id := int(values.get("order_id", -1))
	var active_worker_count := int(values.get("active_worker_count", -1))
	var active_citizen_ids: Array = values.get("active_citizen_ids", [])
	var previous_active_citizen_id := 0

	for raw_active_citizen_id in active_citizen_ids:
		if typeof(raw_active_citizen_id) != TYPE_INT:
			errors.append(
				"Work order "
				+ str(order_id)
				+ " has a non-integer active citizen ID."
			)
			continue

		var active_citizen_id: int = raw_active_citizen_id

		if (
			active_citizen_id <= previous_active_citizen_id
			or not citizen_lookup.has(active_citizen_id)
		):
			errors.append(
				"Work order "
				+ str(order_id)
				+ " has invalid, duplicate, or unsorted active citizens."
			)

		previous_active_citizen_id = active_citizen_id

	if active_worker_count != active_citizen_ids.size():
		errors.append(
			"Work order "
			+ str(order_id)
			+ " active worker count disagrees with its citizen IDs."
		)

static func _city_work_order_source_exists(
	order_type: String,
	source_id: int,
	construction_site_lookup: Dictionary
) -> bool:
	if order_type == CityWorkSystemScript.ORDER_TYPE_COMMAND_GROUP:
		for raw_command in CityWorkSystem.get_current_work_state().player_commands:
			if (
				raw_command is Dictionary
				and int(raw_command.get("group_id", -1)) == source_id
				and int(raw_command.get("construction_site_id", -1)) <= 0
			):
				return true

		return false

	if order_type == CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE:
		return construction_site_lookup.has(source_id)

	return false


static func _validate_city_work_order_jobs(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var order_id := int(values.get("order_id", -1))
	var jobs: Array = values.get("jobs", [])
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	var order_active_citizen_ids: Array = values.get(
		"order_active_citizen_ids",
		[]
	)
	var job_ids: Dictionary = {}

	for job_index in range(jobs.size()):
		var raw_job = jobs[job_index]

		if not raw_job is Dictionary:
			errors.append(
				"Work order "
				+ str(order_id)
				+ " has a non-Dictionary job at index "
				+ str(job_index)
				+ "."
			)
			continue

		var job: Dictionary = raw_job
		var raw_job_id = job.get("id")
		var raw_job_kind = job.get("kind")
		var raw_job_state = job.get("state")
		var raw_actionable = job.get("actionable")
		var raw_blocked_reason = job.get("blocked_reason")
		var raw_claimed_citizen_id = job.get("claimed_citizen_id")
		var raw_active_citizen_ids = job.get("active_citizen_ids")

		if (
			typeof(raw_job_id) != TYPE_STRING
			or str(raw_job_id).is_empty()
			or typeof(raw_job_kind) != TYPE_STRING
			or str(raw_job_kind).is_empty()
			or typeof(raw_job_state) != TYPE_STRING
			or typeof(raw_actionable) != TYPE_BOOL
			or typeof(raw_blocked_reason) != TYPE_STRING
			or typeof(raw_claimed_citizen_id) != TYPE_INT
			or not raw_active_citizen_ids is Array
		):
			errors.append(
				"Work order "
				+ str(order_id)
				+ " has malformed job data at index "
				+ str(job_index)
				+ "."
			)
			continue

		var job_id: String = raw_job_id
		var job_kind: String = raw_job_kind
		var job_state: String = raw_job_state
		var actionable: bool = raw_actionable
		var blocked_reason: String = raw_blocked_reason
		var claimed_citizen_id: int = raw_claimed_citizen_id
		var active_citizen_ids: Array = raw_active_citizen_ids

		if job_ids.has(job_id):
			errors.append(
				"Work order "
				+ str(order_id)
				+ " contains duplicate job ID '"
				+ job_id
				+ "'."
			)
		else:
			job_ids[job_id] = true

		if (
			claimed_citizen_id == 0
			or claimed_citizen_id < -1
			or (
				claimed_citizen_id > 0
				and not citizen_lookup.has(claimed_citizen_id)
			)
		):
			errors.append(
				"Work order "
				+ str(order_id)
				+ " job '"
				+ job_id
				+ " has an invalid citizen claim."
			)

		var previous_active_citizen_id := 0

		for raw_active_citizen_id in active_citizen_ids:
			if typeof(raw_active_citizen_id) != TYPE_INT:
				errors.append(
					"Work order "
					+ str(order_id)
					+ " job '"
					+ job_id
					+ "' has a non-integer active citizen ID."
				)
				continue

			var active_citizen_id: int = raw_active_citizen_id

			if (
				active_citizen_id <= previous_active_citizen_id
				or not citizen_lookup.has(active_citizen_id)
				or not order_active_citizen_ids.has(active_citizen_id)
			):
				errors.append(
					"Work order "
					+ str(order_id)
					+ " job '"
					+ job_id
					+ "' has invalid, duplicate, or unsorted active citizens."
				)

			previous_active_citizen_id = active_citizen_id

		var expected_job_state := CityWorkSystemScript.JOB_STATE_BLOCKED

		if not active_citizen_ids.is_empty():
			expected_job_state = CityWorkSystemScript.JOB_STATE_ACTIVE
		elif actionable:
			expected_job_state = CityWorkSystemScript.JOB_STATE_ACTIONABLE

		if (
			job_state not in [
				CityWorkSystemScript.JOB_STATE_ACTIONABLE,
				CityWorkSystemScript.JOB_STATE_ACTIVE,
				CityWorkSystemScript.JOB_STATE_BLOCKED,
			]
			or job_state != expected_job_state
		):
			errors.append(
				"Work order "
				+ str(order_id)
				+ " job '"
				+ job_id
				+ "' has inconsistent runtime state."
			)

		if (
			(job_state in [
				CityWorkSystemScript.JOB_STATE_ACTIONABLE,
				CityWorkSystemScript.JOB_STATE_ACTIVE,
			]) != blocked_reason.is_empty()
		):
			errors.append(
				"Work order "
				+ str(order_id)
				+ " job '"
				+ job_id
				+ "' state and blocked reason disagree."
			)

		if (
			active_citizen_ids.is_empty()
			and claimed_citizen_id > 0
		) or (
			not active_citizen_ids.is_empty()
			and claimed_citizen_id != int(active_citizen_ids[0])
		):
			errors.append(
				"Work order "
				+ str(order_id)
				+ " job '"
				+ job_id
				+ " claim disagrees with its active citizens."
			)

		for reservation_field in [
			"source_reserved_amount",
			"destination_reserved_amount",
		]:
			var field_is_required := job_kind in [
				CityWorkSystemScript.JOB_KIND_CLEARING_RELOCATION,
				CityWorkSystemScript.JOB_KIND_CONSTRUCTION_DELIVERY,
			]

			if not job.has(reservation_field):
				if field_is_required:
					errors.append(
						"Work order "
						+ str(order_id)
						+ " job '"
						+ job_id
						+ "' lacks reservation diagnostics."
					)

				continue

			var raw_reserved_amount = job.get(reservation_field)

			if (
				typeof(raw_reserved_amount) != TYPE_INT
				or int(raw_reserved_amount) < 0
			):
				errors.append(
					"Work order "
					+ str(order_id)
					+ " job '"
					+ job_id
					+ "' has invalid reservation diagnostics."
				)




#endregion

#region Haul Reservations
static func _validate_city_haul_reservations(
	errors: Array[String],
	citizen_lookup: Dictionary,
	ground_pile_lookup: Dictionary
) -> int:
	var expected_citizen_lookup: Dictionary = {}
	var expected_source_amount_by_key: Dictionary = {}
	var expected_destination_amount_by_key: Dictionary = {}
	var source_endpoint_by_key: Dictionary = {}
	var source_resource_by_key: Dictionary = {}
	var destination_endpoint_by_key: Dictionary = {}
	var maximum_reservation_id := 0

	for raw_reservation_id in CityLogisticsSystem.get_current_state().haul_reservations.keys():
		maximum_reservation_id = _validate_city_haul_reservation_entry({
			"errors": errors,
			"citizen_lookup": citizen_lookup,
			"ground_pile_lookup": ground_pile_lookup,
			"expected_citizen_lookup": expected_citizen_lookup,
			"expected_source_amount_by_key": expected_source_amount_by_key,
			"expected_destination_amount_by_key": (
				expected_destination_amount_by_key
			),
			"source_endpoint_by_key": source_endpoint_by_key,
			"source_resource_by_key": source_resource_by_key,
			"destination_endpoint_by_key": destination_endpoint_by_key,
			"maximum_reservation_id": maximum_reservation_id,
			"raw_reservation_id": raw_reservation_id,
		})

	for source_key in expected_source_amount_by_key.keys():
		var source: Dictionary = source_endpoint_by_key[source_key]
		var resource: String = source_resource_by_key[source_key]
		var reserved_amount := int(
			expected_source_amount_by_key[source_key]
		)

		if (
			reserved_amount
			> CityLogisticsSystem.get_city_haul_endpoint_resource_amount(
				source,
				resource
			)
		):
			errors.append(
				"Source reservations exceed physical "
				+ resource
				+ " at "
				+ str(source)
				+ "."
			)

	for destination_key in expected_destination_amount_by_key.keys():
		var destination: Dictionary = (
			destination_endpoint_by_key[destination_key]
		)
		var destination_kind := str(
			destination.get(
				"kind",
				CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		var city_object := CityObjectSystem.get_city_object_by_id(
			int(destination.get("id", -1))
		)
		var reserved_amount := int(
			expected_destination_amount_by_key[destination_key]
		)

		if (
			destination_kind
			== WorldData
			.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
		):
			var site_id := int(destination.get("id", -1))
			var remaining_capacity := 0

			for resource in CityResourceCatalog.get_city_resource_types():
				remaining_capacity += (
					CityConstructionSystem.get_city_construction_site_remaining_resource_amount(
						site_id,
						resource
					)
				)

			if reserved_amount > remaining_capacity:
				errors.append(
					"Destination reservations exceed remaining construction "
					+ "requirements at "
					+ str(destination)
					+ "."
				)
		elif (
			destination_kind
			== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE
			and reserved_amount
			> CityLogisticsSystem.CITY_GROUND_DROP_RESERVATION_CAPACITY
		):
			errors.append(
				"Destination reservations exceed ground-drop capacity at "
				+ str(destination)
				+ "."
			)
		elif (
			not city_object.is_empty()
			and reserved_amount
			> CityResourceContainerSystem.get_city_object_storage_free_space(city_object)
		):
			errors.append(
				"Destination reservations exceed shared free capacity at "
				+ str(destination)
				+ "."
			)

	if (
		CityLogisticsSystem.get_current_state().haul_reservation_id_by_citizen_id
		!= expected_citizen_lookup
	):
		errors.append(
			"Haul reservation citizen lookup does not match the ledger."
		)

	if (
		CityLogisticsSystem.get_current_state().haul_source_reserved_amount_by_key
		!= expected_source_amount_by_key
	):
		errors.append(
			"Haul source reservation aggregate does not match the ledger."
		)

	if (
		CityLogisticsSystem.get_current_state().haul_destination_reserved_amount_by_key
		!= expected_destination_amount_by_key
	):
		errors.append(
			"Haul destination reservation aggregate does not match the ledger."
		)

	if CityLogisticsSystem.get_current_state().next_haul_reservation_id <= maximum_reservation_id:
		errors.append(
			"next_city_haul_reservation_id must exceed every reservation ID."
		)

	return CityLogisticsSystem.get_current_state().haul_reservations.size()




static func _validate_city_haul_reservation_entry(
	values: Dictionary
) -> int:
	var errors: Array[String] = values.get("errors", [])
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	var ground_pile_lookup: Dictionary = values.get("ground_pile_lookup", {})
	var expected_citizen_lookup: Dictionary = values.get(
		"expected_citizen_lookup",
		{}
	)
	var expected_source_amount_by_key: Dictionary = values.get(
		"expected_source_amount_by_key",
		{}
	)
	var expected_destination_amount_by_key: Dictionary = values.get(
		"expected_destination_amount_by_key",
		{}
	)
	var source_endpoint_by_key: Dictionary = values.get(
		"source_endpoint_by_key",
		{}
	)
	var source_resource_by_key: Dictionary = values.get(
		"source_resource_by_key",
		{}
	)
	var destination_endpoint_by_key: Dictionary = values.get(
		"destination_endpoint_by_key",
		{}
	)
	var maximum_reservation_id := int(
		values.get("maximum_reservation_id", 0)
	)
	var raw_reservation_id = values.get("raw_reservation_id")
	if typeof(raw_reservation_id) != TYPE_INT:
		errors.append(
			"Haul reservation ledger contains a non-integer key."
		)
		return maximum_reservation_id

	var reservation_id: int = raw_reservation_id
	var raw_reservation = CityLogisticsSystem.get_current_state().haul_reservations[
		reservation_id
	]

	if not raw_reservation is Dictionary:
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " is not a Dictionary."
		)
		return maximum_reservation_id

	var reservation: Dictionary = raw_reservation
	var stored_reservation_id := int(
		reservation.get("id", -1)
	)
	var citizen_id := int(reservation.get("citizen_id", -1))
	var resource := str(
		reservation.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var raw_source = reservation.get("source", {})
	var raw_destination = reservation.get("destination", {})
	var raw_source_reserved_amount = reservation.get(
		"source_reserved_amount",
		0
	)
	var raw_destination_reserved_amount = reservation.get(
		"destination_reserved_amount",
		0
	)
	var raw_destination_reserved_resources = reservation.get(
		"destination_reserved_resources",
		{}
	)
	var source_reserved_amount := maxi(
		int(raw_source_reserved_amount),
		0
	)
	var destination_reserved_amount := maxi(
		int(raw_destination_reserved_amount),
		0
	)
	var destination_manifest_result := (
		_build_destination_reserved_resource_manifest({
			"errors": errors,
			"reservation_id": reservation_id,
			"raw_manifest": raw_destination_reserved_resources,
		})
	)
	var destination_reserved_resources: Dictionary = (
		destination_manifest_result.get("resources", {})
	)
	var destination_manifest_total := int(
		destination_manifest_result.get("total", 0)
	)

	if destination_manifest_total != destination_reserved_amount:
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " destination manifest totals "
			+ str(destination_manifest_total)
			+ " but reserved amount is "
			+ str(destination_reserved_amount)
			+ "."
		)

	maximum_reservation_id = maxi(
		maximum_reservation_id,
		reservation_id
	)

	if reservation_id <= 0 or stored_reservation_id != reservation_id:
		errors.append(
			"Haul reservation key/ID mismatch for "
			+ str(reservation_id)
			+ "."
		)

	if (
		typeof(raw_source_reserved_amount) != TYPE_INT
		or int(raw_source_reserved_amount) < 0
	):
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " has invalid source reserved amount."
		)

	if (
		typeof(raw_destination_reserved_amount) != TYPE_INT
		or int(raw_destination_reserved_amount) < 0
	):
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " has invalid destination reserved amount."
		)

	if not citizen_lookup.has(citizen_id):
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " references missing citizen "
			+ str(citizen_id)
			+ "."
		)
		return maximum_reservation_id

	if expected_citizen_lookup.has(citizen_id):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " owns multiple haul reservations."
		)
	else:
		expected_citizen_lookup[citizen_id] = reservation_id

	if not CityResourceCatalog.is_city_resource_type(resource):
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " has invalid resource '"
			+ resource
			+ "'."
		)

	if not raw_source is Dictionary or not raw_destination is Dictionary:
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " has invalid endpoint data."
		)
		return maximum_reservation_id

	var source: Dictionary = raw_source
	var destination: Dictionary = raw_destination
	var source_is_valid := (
		CityCitizens.is_valid_city_citizen_haul_endpoint(source)
		and _city_haul_endpoint_schema_is_valid(source)
		and str(source.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE
	)
	var destination_is_valid := (
		CityCitizens.is_valid_city_citizen_haul_endpoint(
			destination,
			destination_reserved_amount <= 0
		)
		and _city_haul_endpoint_schema_is_valid(
			destination,
			destination_reserved_amount <= 0
		)
	)

	if not source_is_valid:
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " has invalid source endpoint."
		)

	if not destination_is_valid:
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " has invalid destination endpoint."
		)

	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
		citizen_id
	)
	var current_haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(
		citizen_id
	)
	var cargo_amount := CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(
		citizen_id
	)
	var cargo_resources := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources(
			citizen_id
		)
	)
	_validate_city_haul_reservation_citizen_state({
		"errors": errors,
		"reservation_id": reservation_id,
		"citizen_id": citizen_id,
		"resource": resource,
		"source": source,
		"source_reserved_amount": source_reserved_amount,
		"destination_reserved_amount": destination_reserved_amount,
		"destination_reserved_resources": destination_reserved_resources,
		"citizen": citizen,
		"current_task": current_task,
		"current_haul": current_haul,
		"cargo_amount": cargo_amount,
		"cargo_resources": cargo_resources,
	})

	var endpoint_context := {
		"errors": errors,
		"ground_pile_lookup": ground_pile_lookup,
		"expected_source_amount_by_key": expected_source_amount_by_key,
		"expected_destination_amount_by_key": (
			expected_destination_amount_by_key
		),
		"source_endpoint_by_key": source_endpoint_by_key,
		"source_resource_by_key": source_resource_by_key,
		"destination_endpoint_by_key": destination_endpoint_by_key,
		"reservation_id": reservation_id,
		"reservation": reservation,
		"citizen_id": citizen_id,
		"resource": resource,
		"source": source,
		"destination": destination,
		"source_reserved_amount": source_reserved_amount,
		"destination_reserved_amount": destination_reserved_amount,
		"destination_reserved_resources": destination_reserved_resources,
		"current_haul": current_haul,
	}
	_validate_city_haul_reservation_source(endpoint_context)
	_validate_city_haul_reservation_destination(endpoint_context)

	return maximum_reservation_id


static func _validate_city_haul_reservation_citizen_state(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var reservation_id := int(values.get("reservation_id", -1))
	var citizen_id := int(values.get("citizen_id", -1))
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var source: Dictionary = values.get("source", {})
	var source_reserved_amount := int(values.get("source_reserved_amount", 0))
	var destination_reserved_amount := int(
		values.get("destination_reserved_amount", 0)
	)
	var destination_reserved_resources: Dictionary = values.get(
		"destination_reserved_resources",
		{}
	)
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var current_haul: Dictionary = values.get("current_haul", {})
	var cargo_amount := int(values.get("cargo_amount", 0))
	var cargo_resources: Dictionary = values.get("cargo_resources", {})
	if not bool(citizen.get("alive", false)):
		errors.append(
			"Dead citizen "
			+ str(citizen_id)
			+ " owns haul reservation "
			+ str(reservation_id)
			+ "."
		)

	if (
		str(current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
	):
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " exists without an active haul task."
		)

	if int(
		current_haul.get(
			"reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	) != reservation_id:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " haul state does not point to reservation "
			+ str(reservation_id)
			+ "."
		)

	if str(
		current_haul.get(
			"resource_type",
			WorldData.RESOURCE_NONE
		)
	) != resource:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " haul resource does not match reservation "
			+ str(reservation_id)
			+ "."
		)

	var raw_current_source = current_haul.get("source", {})

	if (
		not raw_current_source is Dictionary
		or _get_validation_endpoint_key(raw_current_source)
		!= _get_validation_endpoint_key(source)
	):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " haul source does not match reservation "
			+ str(reservation_id)
			+ "."
		)

	if (
		source_reserved_amount <= 0
		and destination_reserved_amount <= 0
		and (
			cargo_amount <= 0
			or str(
				current_haul.get(
					"phase",
					CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE
				)
			) not in [
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_RETARGETING,
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION,
			]
		)
	):
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " reserves neither source goods nor destination capacity."
		)

	var maximum_destination_reservation := (
		cargo_amount + source_reserved_amount
	)

	if destination_reserved_amount > maximum_destination_reservation:
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " reserves more destination space than carried and claimed goods."
		)

	if (
		source_reserved_amount > 0
		and destination_reserved_amount
		!= maximum_destination_reservation
	):
		errors.append(
			"Pickup-chain reservation "
			+ str(reservation_id)
			+ " does not reserve all carried cargo plus its next pickup."
		)

	if (
		source_reserved_amount > 0
		and int(current_haul.get("requested_amount", 0))
		!= source_reserved_amount
	):
		errors.append(
			"Pending pickup reservation "
			+ str(reservation_id)
			+ " disagrees with the haul's requested amount."
		)

	for reserved_resource in destination_reserved_resources.keys():
		var maximum_resource_amount := maxi(
			int(cargo_resources.get(reserved_resource, 0)),
			0
		)

		if str(reserved_resource) == resource:
			maximum_resource_amount += source_reserved_amount

		if (
			int(
				destination_reserved_resources.get(
					reserved_resource,
					0
				)
			)
			> maximum_resource_amount
		):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " over-reserves destination space for "
				+ str(reserved_resource)
				+ "."
			)


static func _build_destination_reserved_resource_manifest(
	values: Dictionary
) -> Dictionary:
	var errors: Array[String] = values.get("errors", [])
	var reservation_id := int(values.get("reservation_id", -1))
	var raw_manifest = values.get("raw_manifest", {})
	var resources: Dictionary = {}
	var total := 0

	if not raw_manifest is Dictionary:
		errors.append(
			"Haul reservation "
			+ str(reservation_id)
			+ " has a non-Dictionary destination resource manifest."
		)
		return {
			"resources": resources,
			"total": total,
		}

	for raw_reserved_resource in raw_manifest.keys():
		if typeof(raw_reserved_resource) != TYPE_STRING:
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " has a non-string destination resource key."
			)
			continue

		var reserved_resource: String = raw_reserved_resource
		var raw_reserved_resource_amount = raw_manifest.get(
			raw_reserved_resource,
			0
		)

		if (
			typeof(raw_reserved_resource_amount) != TYPE_INT
			or int(raw_reserved_resource_amount) <= 0
			or not CityResourceCatalog.is_city_resource_type(reserved_resource)
		):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " has invalid destination resource entry '"
				+ reserved_resource
				+ "'."
			)
			continue

		var reserved_resource_amount: int = raw_reserved_resource_amount
		resources[reserved_resource] = reserved_resource_amount
		total += reserved_resource_amount

	return {
		"resources": resources,
		"total": total,
	}


static func _validate_city_haul_reservation_source(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var ground_pile_lookup: Dictionary = values.get("ground_pile_lookup", {})
	var expected_source_amount_by_key: Dictionary = values.get(
		"expected_source_amount_by_key",
		{}
	)
	var source_endpoint_by_key: Dictionary = values.get(
		"source_endpoint_by_key",
		{}
	)
	var source_resource_by_key: Dictionary = values.get(
		"source_resource_by_key",
		{}
	)
	var reservation_id := int(values.get("reservation_id", -1))
	var reservation: Dictionary = values.get("reservation", {})
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var source: Dictionary = values.get("source", {})
	var source_reserved_amount := int(values.get("source_reserved_amount", 0))
	if source_reserved_amount > 0:
		if not _city_haul_endpoint_exists(
			source,
			ground_pile_lookup
		):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " reserves a missing source endpoint."
			)

		if not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
			"endpoint": source,
			"resource": resource,
			"withdrawal_purpose": str(
								reservation.get(
									"source_access_purpose",
									CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
								)
							),
			"require_unreserved_amount": false,
			"excluding_reservation_id": reservation_id,
		}):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " has an incompatible source endpoint or purpose."
			)

		var source_key := _get_validation_source_key(
			source,
			resource
		)
		expected_source_amount_by_key[source_key] = (
			int(expected_source_amount_by_key.get(source_key, 0))
			+ source_reserved_amount
		)
		source_endpoint_by_key[source_key] = source
		source_resource_by_key[source_key] = resource


static func _validate_city_haul_reservation_destination(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var ground_pile_lookup: Dictionary = values.get("ground_pile_lookup", {})
	var expected_destination_amount_by_key: Dictionary = values.get(
		"expected_destination_amount_by_key",
		{}
	)
	var destination_endpoint_by_key: Dictionary = values.get(
		"destination_endpoint_by_key",
		{}
	)
	var reservation_id := int(values.get("reservation_id", -1))
	var reservation: Dictionary = values.get("reservation", {})
	var citizen_id := int(values.get("citizen_id", -1))
	var destination: Dictionary = values.get("destination", {})
	var destination_reserved_amount := int(
		values.get("destination_reserved_amount", 0)
	)
	var destination_reserved_resources: Dictionary = values.get(
		"destination_reserved_resources",
		{}
	)
	var current_haul: Dictionary = values.get("current_haul", {})
	if destination_reserved_amount > 0:
		if not _city_haul_endpoint_exists(
			destination,
			ground_pile_lookup
		):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " reserves missing destination capacity."
			)

		var raw_current_destination = current_haul.get(
			"destination",
			{}
		)

		if (
			not raw_current_destination is Dictionary
			or _get_validation_endpoint_key(raw_current_destination)
			!= _get_validation_endpoint_key(destination)
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " haul destination does not match reservation "
				+ str(reservation_id)
				+ "."
			)

		var destination_object := CityObjectSystem.get_city_object_by_id(
			int(destination.get("id", -1))
		)
		var destination_kind := str(
			destination.get(
				"kind",
				CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)

		var destination_access_purpose := str(
			reservation.get(
				"destination_access_purpose",
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
			)
		)
		var destination_policy_is_valid := true

		for reserved_resource in destination_reserved_resources.keys():
			if not CityLogisticsSystem.city_haul_endpoint_can_accept_resource({
				"endpoint": destination,
				"resource": str(reserved_resource),
				"deposit_purpose": destination_access_purpose,
				"require_unreserved_space": false,
				"excluding_reservation_id": reservation_id,
			}):
				destination_policy_is_valid = false
				break

		if (
			destination_access_purpose
			== CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
			and CityResourceContainerSystem.get_city_object_public_storage_tier(
				destination_object
			)
			== CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_NONE
		):
			destination_policy_is_valid = false
		elif (
			destination_access_purpose
			== CityObjectCatalog.CONTAINER_HAUL_PURPOSE_HOME_DELIVERY
			and not CityResourceMatcher.city_object_is_household_home(
				destination_object
			)
		):
			destination_policy_is_valid = false
		elif (
			destination_kind
			== WorldData
			.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
			and destination_access_purpose
			!= CityObjectCatalog.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
		):
			destination_policy_is_valid = false

		if not destination_policy_is_valid:
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " has an incompatible destination or purpose."
			)

		var destination_key := _get_validation_endpoint_key(
			destination
		)
		expected_destination_amount_by_key[destination_key] = (
			int(
				expected_destination_amount_by_key.get(
					destination_key,
					0
				)
			)
			+ destination_reserved_amount
		)
		destination_endpoint_by_key[destination_key] = destination


static func _city_haul_endpoint_exists(
	endpoint: Dictionary,
	ground_pile_lookup: Dictionary
) -> bool:
	match str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	):
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			return not CityObjectSystem.get_city_object_by_id(
				int(endpoint.get("id", -1))
			).is_empty()

		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			return ground_pile_lookup.has(
				int(endpoint.get("id", -1))
			)

		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE:
			var raw_tile = endpoint.get(
				"tile_position",
				CityCitizens.INVALID_CITY_TILE_POSITION
			)
			return (
				raw_tile is Vector2i
				and WorldPoliticalState.get_current_city_world() != null
				and CityLogisticsSystem.can_city_ground_pile_exist_at_tile(
					WorldPoliticalState.get_current_city_world(),
					raw_tile
				)
			)

		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE:
			return not CityConstructionSystem.get_city_construction_site_by_id(
				int(endpoint.get("id", -1))
			).is_empty()

	return false


static func _city_haul_endpoint_schema_is_valid(
	endpoint: Dictionary,
	allow_none: bool = false
) -> bool:
	for field_name in [
		"kind",
		"id",
		"tile_position",
		"excluded_ground_pile_ids",
	]:
		if not endpoint.has(field_name):
			return false

	var raw_kind = endpoint.get("kind")
	var raw_id = endpoint.get("id")
	var raw_tile = endpoint.get("tile_position")
	var raw_excluded_ids = endpoint.get("excluded_ground_pile_ids")

	if (
		typeof(raw_kind) != TYPE_STRING
		or typeof(raw_id) != TYPE_INT
		or not raw_tile is Vector2i
		or not raw_excluded_ids is Array
	):
		return false

	var endpoint_kind: String = raw_kind
	var endpoint_id: int = raw_id
	var tile: Vector2i = raw_tile
	var previous_excluded_id := 0

	for raw_excluded_id in raw_excluded_ids:
		if (
			typeof(raw_excluded_id) != TYPE_INT
			or int(raw_excluded_id) <= previous_excluded_id
		):
			return false

		previous_excluded_id = int(raw_excluded_id)

	if endpoint_kind == CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE:
		return (
			allow_none
			and endpoint_id == -1
			and tile == CityCitizens.INVALID_CITY_TILE_POSITION
			and raw_excluded_ids.is_empty()
		)

	if (
		endpoint_kind
		== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE
	):
		return (
			endpoint_id == -1
			and tile != CityCitizens.INVALID_CITY_TILE_POSITION
		)

	return (
		endpoint_id > 0
		and tile == CityCitizens.INVALID_CITY_TILE_POSITION
		and raw_excluded_ids.is_empty()
	)


static func _get_validation_endpoint_key(
	endpoint: Dictionary
) -> String:
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)

	if (
		endpoint_kind
		== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE
	):
		var raw_tile = endpoint.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if raw_tile is Vector2i:
			return (
				endpoint_kind
				+ ":"
				+ str(raw_tile.x)
				+ ","
				+ str(raw_tile.y)
			)

	return (
		endpoint_kind
		+ ":"
		+ str(int(endpoint.get("id", -1)))
	)


static func _get_validation_source_key(
	endpoint: Dictionary,
	resource: String
) -> String:
	return _get_validation_endpoint_key(endpoint) + ":" + resource




#endregion
