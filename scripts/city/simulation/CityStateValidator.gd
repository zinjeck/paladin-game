# File responsibility: Coordinate read-only invariant validation for one explicit settlement simulation target.
# Domain-specific validation lives in the dedicated validators preloaded below.
extends RefCounted

const CityLogisticsStateValidator := preload("res://scripts/city/simulation/validators/CityLogisticsStateValidator.gd")
const CityCitizenStateValidator := preload("res://scripts/city/simulation/validators/CityCitizenStateValidator.gd")
const CityObjectStateValidator := preload("res://scripts/city/simulation/validators/CityObjectStateValidator.gd")

const MAX_REPORTED_PROBLEMS: int = 24
const MAX_CACHED_SETTLEMENTS: int = 8

# Validation is read-only. Cache entries retain authoritative-owner identity references,
# version/fingerprint stamps, and detached result dictionaries. Settlement ID selects
# a bounded slot, while exact state/world/domain-owner identities prevent same-ID or
# equal-version cross-settlement reuse.
static var _cache_by_settlement_id: Dictionary = {}
static var _cache_recency: Array[int] = []


#region Explicit Validation Entry Points
static func validate_for_settlement(
	settlement_context: SettlementSimulationContext,
	force_rebuild: bool = false,
	report_problems: bool = true
) -> Dictionary:
	var validation_target := _make_validation_target(settlement_context)
	if validation_target.is_empty():
		var invalid_result := _make_invalid_target_result(
			settlement_context,
			"CityStateValidator requires a registered city settlement context."
		)
		if report_problems:
			_report_validation_problems(invalid_result)
		return invalid_result

	return _validate_target(
		validation_target,
		force_rebuild,
		report_problems
	)


static func validate_for_city_state(
	settlement_id: int,
	city_state: CitySettlementSimulationState,
	force_rebuild: bool = false,
	report_problems: bool = true,
	settlement_context: SettlementSimulationContext = null
) -> Dictionary:
	var validation_target := _make_validation_target_for_city_state(
		settlement_id,
		city_state,
		settlement_context
	)
	if validation_target.is_empty():
		var invalid_result := _make_invalid_target_result(
			settlement_context,
			"CityStateValidator requires an explicit valid settlement ID and city state."
		)
		if report_problems:
			_report_validation_problems(invalid_result)
		return invalid_result

	return _validate_target(
		validation_target,
		force_rebuild,
		report_problems
	)


static func get_summary_text_for_settlement(
	settlement_context: SettlementSimulationContext
) -> String:
	return _format_summary_text(
		validate_for_settlement(settlement_context, false, true)
	)


static func get_summary_text_for_city_state(
	settlement_id: int,
	city_state: CitySettlementSimulationState,
	settlement_context: SettlementSimulationContext = null
) -> String:
	return _format_summary_text(
		validate_for_city_state(
			settlement_id,
			city_state,
			false,
			true,
			settlement_context
		)
	)


static func clear_cache_for_settlement(settlement_id: int) -> void:
	_cache_by_settlement_id.erase(settlement_id)
	_cache_recency.erase(settlement_id)


static func clear_all_validation_caches() -> void:
	_cache_by_settlement_id.clear()
	_cache_recency.clear()


static func _make_validation_target(
	settlement_context: SettlementSimulationContext
) -> Dictionary:
	if (
		settlement_context == null
		or not settlement_context.supports_city_simulation()
		or not WorldPoliticalState.is_registered_settlement_context(
			settlement_context
		)
	):
		return {}

	var city_state: CitySettlementSimulationState = (
		settlement_context.get_city_simulation_state()
	)
	return _make_validation_target_for_city_state(
		settlement_context.settlement_id,
		city_state,
		settlement_context
	)


static func _make_validation_target_for_city_state(
	settlement_id: int,
	city_state: CitySettlementSimulationState,
	settlement_context: SettlementSimulationContext
) -> Dictionary:
	if settlement_id <= 0 or city_state == null:
		return {}
	if (
		settlement_context != null
		and (
			settlement_context.settlement_id != settlement_id
			or not settlement_context.supports_city_simulation()
			or not WorldPoliticalState.is_registered_settlement_context(
				settlement_context
			)
			or not is_same(
				settlement_context.get_city_simulation_state(),
				city_state
			)
		)
	):
		return {}

	return {
		"settlement_context": settlement_context,
		"settlement_id": settlement_id,
		"city_state": city_state,
	}


static func _make_invalid_target_result(
	settlement_context,
	error_text: String
) -> Dictionary:
	var settlement_id: int = (
		int(settlement_context.settlement_id)
		if settlement_context is SettlementSimulationContext
		else SettlementData.INVALID_SETTLEMENT_ID
	)
	return {
		"valid": false,
		"errors": [error_text],
		"warnings": [],
		"settlement_id": settlement_id,
		"city_state_instance_id": -1,
		"city_world_instance_id": -1,
		"duration_usec": 0,
		"cache_hit": false,
	}
#endregion


#region Target Validation and Cache
static func _validate_target(
	validation_target: Dictionary,
	force_rebuild: bool,
	report_problems: bool
) -> Dictionary:
	if not force_rebuild:
		var cached_result := _get_cached_result(validation_target)
		if not cached_result.is_empty():
			cached_result["cache_hit"] = true
			return cached_result

	var validation_start_usec := Time.get_ticks_usec()
	var city_state: CitySettlementSimulationState = validation_target["city_state"]
	var errors: Array[String] = []
	var warnings: Array[String] = []

	var object_lookup := _validate_city_object_index(validation_target, errors)
	var citizen_lookup := _validate_city_citizen_index(validation_target, errors)
	var construction_site_lookup := (
		CityLogisticsStateValidator._validate_city_construction_state(
			validation_target,
			errors,
			object_lookup
		)
	)
	var ground_pile_lookup := (
		CityLogisticsStateValidator._validate_city_ground_pile_state(
			validation_target,
			errors,
			construction_site_lookup
		)
	)

	CityObjectStateValidator._validate_city_foundation_state(
		validation_target,
		errors,
		warnings,
		object_lookup
	)
	CityObjectStateValidator._validate_city_occupancy(
		validation_target,
		errors,
		object_lookup
	)
	CityCitizenStateValidator._validate_city_citizen_spatial_state(
		validation_target,
		errors,
		citizen_lookup
	)
	CityCitizenStateValidator._validate_city_citizen_demographics(
		validation_target,
		errors,
		citizen_lookup
	)
	CityCitizenStateValidator._validate_city_citizen_culture_state(
		validation_target,
		errors,
		citizen_lookup
	)
	CityCitizenStateValidator._validate_city_citizen_need_state(
		validation_target,
		errors,
		citizen_lookup
	)
	var checked_work_order_count := (
		CityLogisticsStateValidator._validate_city_work_orders(
			validation_target,
			errors,
			citizen_lookup,
			construction_site_lookup
		)
	)
	CityCitizenStateValidator._validate_city_citizen_task_state(
		validation_target,
		errors,
		citizen_lookup,
		object_lookup
	)
	var checked_haul_reservation_count := (
		CityLogisticsStateValidator._validate_city_haul_reservations(
			validation_target,
			errors,
			citizen_lookup,
			ground_pile_lookup
		)
	)
	CityCitizenStateValidator._validate_city_citizen_movement_state(
		validation_target,
		errors,
		citizen_lookup
	)
	var checked_container_count := (
		CityObjectStateValidator._validate_city_containers(
			validation_target,
			errors,
			object_lookup
		)
	)
	CityObjectStateValidator._validate_city_assignments(
		validation_target,
		errors,
		object_lookup,
		citizen_lookup
	)
	CityObjectStateValidator._validate_city_workplace_production(
		validation_target,
		{
			"errors": errors,
			"warnings": warnings,
			"object_lookup": object_lookup,
			"citizen_lookup": citizen_lookup,
		}
	)
	var checked_inventory_count := (
		CityObjectStateValidator._validate_citizen_inventories(
			validation_target,
			errors,
			warnings,
			citizen_lookup
		)
	)

	var validation_duration_usec := (
		Time.get_ticks_usec() - validation_start_usec
	)
	var result := _make_validation_result(
		validation_target,
		errors,
		warnings,
		object_lookup,
		citizen_lookup,
		construction_site_lookup,
		ground_pile_lookup,
		checked_container_count,
		checked_inventory_count,
		checked_haul_reservation_count,
		checked_work_order_count,
		validation_duration_usec
	)
	_store_cached_result(validation_target, result)

	if report_problems:
		_report_validation_problems(result)
	return result.duplicate(true)


static func _make_validation_result(
	validation_target: Dictionary,
	errors: Array[String],
	warnings: Array[String],
	object_lookup: Dictionary,
	citizen_lookup: Dictionary,
	construction_site_lookup: Dictionary,
	ground_pile_lookup: Dictionary,
	checked_container_count: int,
	checked_inventory_count: int,
	checked_haul_reservation_count: int,
	checked_work_order_count: int,
	validation_duration_usec: int
) -> Dictionary:
	var settlement_context = validation_target.get("settlement_context")
	var settlement_id: int = int(validation_target["settlement_id"])
	var city_state: CitySettlementSimulationState = validation_target["city_state"]
	var world_instance_id := (
		int(city_state.city_world.get_instance_id())
		if city_state.city_world is WorldData
		else -1
	)
	var result := {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"settlement_id": settlement_id,
		"settlement_context_instance_id": (
			int(settlement_context.get_instance_id())
			if settlement_context is SettlementSimulationContext
			else -1
		),
		"city_state_instance_id": int(city_state.get_instance_id()),
		"city_world_instance_id": world_instance_id,
		"object_state_instance_id": int(
			city_state.object_state.get_instance_id()
		),
		"resource_accounting_state_instance_id": int(
			city_state.resource_accounting_state.get_instance_id()
		),
		"citizen_registry_state_instance_id": int(
			city_state.citizen_registry_state.get_instance_id()
		),
		"assignment_state_instance_id": int(
			city_state.assignment_state.get_instance_id()
		),
		"workplace_state_instance_id": int(
			city_state.workplace_state.get_instance_id()
		),
		"citizen_spatial_state_instance_id": int(
			city_state.citizen_spatial_state.get_instance_id()
		),
		"citizen_movement_runtime_state_instance_id": int(
			city_state.citizen_movement_runtime_state.get_instance_id()
		),
		"citizen_task_runtime_state_instance_id": int(
			city_state.citizen_task_runtime_state.get_instance_id()
		),
		"work_state_instance_id": int(
			city_state.work_state.get_instance_id()
		),
		"logistics_state_instance_id": int(
			city_state.logistics_state.get_instance_id()
		),
		"construction_state_instance_id": int(
			city_state.construction_state.get_instance_id()
		),
		"navigation_state_instance_id": int(
			city_state.navigation_state.get_instance_id()
		),
		"checked_objects": object_lookup.size(),
		"checked_citizens": citizen_lookup.size(),
		"checked_occupied_tiles": city_state.object_state.occupied_tiles.size(),
		"checked_containers": checked_container_count,
		"checked_inventories": checked_inventory_count,
		"checked_ground_piles": ground_pile_lookup.size(),
		"checked_haul_reservations": checked_haul_reservation_count,
		"checked_work_orders": checked_work_order_count,
		"checked_construction_sites": construction_site_lookup.size(),
		"duration_usec": validation_duration_usec,
		"cache_hit": false,
	}
	result.merge(_make_cache_stamp(city_state), true)
	return result


static func _get_cached_result(
	validation_target: Dictionary
) -> Dictionary:
	var settlement_id: int = int(validation_target["settlement_id"])
	var raw_entry = _cache_by_settlement_id.get(settlement_id, {})
	if not raw_entry is Dictionary:
		return {}
	var entry: Dictionary = raw_entry
	if not _validation_cache_matches_target(entry, validation_target):
		return {}
	_touch_cache_entry(settlement_id)
	var raw_result = entry.get("result", {})
	if not raw_result is Dictionary:
		return {}
	var cached_result: Dictionary = (raw_result as Dictionary).duplicate(true)
	var settlement_context = validation_target.get("settlement_context")
	cached_result["settlement_context_instance_id"] = (
		int(settlement_context.get_instance_id())
		if settlement_context is SettlementSimulationContext
		else -1
	)
	return cached_result


static func _store_cached_result(
	validation_target: Dictionary,
	result: Dictionary
) -> void:
	var settlement_id: int = int(validation_target["settlement_id"])
	var city_state: CitySettlementSimulationState = validation_target["city_state"]
	_cache_by_settlement_id[settlement_id] = {
		"city_state": city_state,
		"city_world": city_state.city_world,
		"object_state": city_state.object_state,
		"resource_accounting_state": city_state.resource_accounting_state,
		"citizen_registry_state": city_state.citizen_registry_state,
		"assignment_state": city_state.assignment_state,
		"workplace_state": city_state.workplace_state,
		"citizen_spatial_state": city_state.citizen_spatial_state,
		"citizen_movement_runtime_state": city_state.citizen_movement_runtime_state,
		"citizen_task_runtime_state": city_state.citizen_task_runtime_state,
		"work_state": city_state.work_state,
		"logistics_state": city_state.logistics_state,
		"construction_state": city_state.construction_state,
		"navigation_state": city_state.navigation_state,
		"stamp": _make_cache_stamp(city_state),
		"result": result.duplicate(true),
	}
	_touch_cache_entry(settlement_id)
	while _cache_recency.size() > MAX_CACHED_SETTLEMENTS:
		var evicted_settlement_id: int = int(_cache_recency.pop_front())
		_cache_by_settlement_id.erase(evicted_settlement_id)


static func _touch_cache_entry(settlement_id: int) -> void:
	_cache_recency.erase(settlement_id)
	_cache_recency.append(settlement_id)


static func _validation_cache_matches_target(
	entry: Dictionary,
	validation_target: Dictionary
) -> bool:
	var city_state: CitySettlementSimulationState = validation_target["city_state"]
	if (
		not is_same(entry.get("city_state"), city_state)
		or not is_same(entry.get("city_world"), city_state.city_world)
		or not is_same(entry.get("object_state"), city_state.object_state)
		or not is_same(
			entry.get("resource_accounting_state"),
			city_state.resource_accounting_state
		)
		or not is_same(
			entry.get("citizen_registry_state"),
			city_state.citizen_registry_state
		)
		or not is_same(entry.get("assignment_state"), city_state.assignment_state)
		or not is_same(entry.get("workplace_state"), city_state.workplace_state)
		or not is_same(
			entry.get("citizen_spatial_state"),
			city_state.citizen_spatial_state
		)
		or not is_same(
			entry.get("citizen_movement_runtime_state"),
			city_state.citizen_movement_runtime_state
		)
		or not is_same(
			entry.get("citizen_task_runtime_state"),
			city_state.citizen_task_runtime_state
		)
		or not is_same(entry.get("work_state"), city_state.work_state)
		or not is_same(entry.get("logistics_state"), city_state.logistics_state)
		or not is_same(entry.get("construction_state"), city_state.construction_state)
		or not is_same(entry.get("navigation_state"), city_state.navigation_state)
	):
		return false
	return entry.get("stamp", {}) == _make_cache_stamp(city_state)


static func _make_cache_stamp(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	var city_world = city_state.city_world
	return {
		"city_seed": city_state.city_seed,
		"city_runtime_fingerprint": int(hash(city_state.city_runtime_data)),
		"city_world_width": city_world.width if city_world is WorldData else -1,
		"city_world_height": city_world.height if city_world is WorldData else -1,
		"city_world_tile_data_version": (
			city_world.tile_data_version if city_world is WorldData else -1
		),
		"city_world_surface_feature_version": (
			city_world.city_surface_feature_change_version
			if city_world is WorldData
			else -1
		),
		"object_version": city_state.object_state.object_version,
		"object_debug_fingerprint": (
			CityObjectSystem.get_city_object_debug_fingerprint_for_city_state(
				city_state
			)
		),
		"container_version": city_state.resource_accounting_state.container_version,
		"public_storage_version": (
			city_state.resource_accounting_state.public_storage_version
		),
		"citizen_version": city_state.citizen_registry_state.citizen_version,
		"citizen_spatial_version": (
			city_state.citizen_spatial_state.citizen_spatial_version
		),
		"citizen_movement_version": (
			city_state.citizen_movement_runtime_state.citizen_movement_version
		),
		"citizen_task_version": (
			city_state.citizen_task_runtime_state.citizen_task_version
		),
		"assignment_version": city_state.assignment_state.assignment_version,
		"workplace_version": city_state.workplace_state.workplace_version,
		"ground_pile_version": city_state.logistics_state.ground_pile_version,
		"haul_reservation_version": (
			city_state.logistics_state.haul_reservation_version
		),
		"player_command_version": city_state.work_state.player_command_version,
		"work_order_version": city_state.work_state.work_order_version,
		"construction_version": city_state.construction_state.construction_version,
	}
#endregion


#region Summary Formatting
static func _format_summary_text(result: Dictionary) -> String:
	var error_count := int(result.get("errors", []).size())
	var warning_count := int(result.get("warnings", []).size())
	var status_text := "VALID"
	if error_count > 0:
		status_text = "INVALID"
	elif warning_count > 0:
		status_text = "VALID WITH WARNINGS"
	var duration_msec := float(result.get("duration_usec", 0)) / 1000.0

	return (
		"City State: " + status_text
		+ " | Settlement: " + str(result.get("settlement_id", -1))
		+ " | Errors: " + str(error_count)
		+ " | Warnings: " + str(warning_count)
		+ "\n"
		+ "Checked: "
		+ str(result.get("checked_objects", 0))
		+ " objects | "
		+ str(result.get("checked_citizens", 0))
		+ " citizens | "
		+ str(result.get("checked_occupied_tiles", 0))
		+ " occupied tiles"
		+ "\n"
		+ "Logistics: "
		+ str(result.get("checked_ground_piles", 0))
		+ " ground piles | "
		+ str(result.get("checked_haul_reservations", 0))
		+ " reservations | "
		+ str(result.get("checked_work_orders", 0))
		+ " work orders | "
		+ str(result.get("checked_construction_sites", 0))
		+ " construction sites"
		+ "\n"
		+ "Validation Cost: "
		+ "%.3f ms" % duration_msec
	)
#endregion


#region Entity Index Validation
static func _validate_city_object_index(
	validation_target: Dictionary,
	errors: Array[String]
) -> Dictionary:
	var city_state: CitySettlementSimulationState = validation_target["city_state"]
	var object_state: CityObjectState = city_state.object_state
	var object_lookup: Dictionary = {}
	var maximum_object_id := 0
	var city_objects: Array = object_state.objects
	var object_index_by_id: Dictionary = object_state.object_index_by_id

	for object_index in range(city_objects.size()):
		var raw_city_object = city_objects[object_index]

		if not raw_city_object is Dictionary:
			errors.append(
				"city_objects["
				+ str(object_index)
				+ "] is not a Dictionary."
			)

			continue

		var city_object: Dictionary = raw_city_object
		var object_id := int(
			city_object.get("id", -1)
		)

		if object_id <= 0:
			errors.append(
				"City object at array index "
				+ str(object_index)
				+ " has invalid ID "
				+ str(object_id)
				+ "."
			)

			continue

		if object_lookup.has(object_id):
			errors.append(
				"Duplicate city object ID "
				+ str(object_id)
				+ " exists at array indexes "
				+ str(object_lookup[object_id])
				+ " and "
				+ str(object_index)
				+ "."
			)

			continue

		object_lookup[object_id] = object_index
		maximum_object_id = maxi(
			maximum_object_id,
			object_id
		)

		var object_type := str(
			city_object.get("type", "")
		)

		if object_type.is_empty():
			errors.append(
				"City object "
				+ str(object_id)
				+ " has no object type."
			)
		elif (
			object_type != CityObjectCatalog.CITY_OBJECT_ROAD
			and CityObjectCatalog.get_city_object_definition(
				object_type
			).is_empty()
		):
			errors.append(
				"City object "
				+ str(object_id)
				+ " uses unknown type '"
				+ object_type
				+ "'."
			)

		if not object_index_by_id.has(
			object_id
		):
			errors.append(
				"City object index is missing object ID "
				+ str(object_id)
				+ "."
			)
		else:
			var indexed_array_position := int(
				object_index_by_id[
					object_id
				]
			)

			if indexed_array_position != object_index:
				errors.append(
					"City object index maps object ID "
					+ str(object_id)
					+ " to array index "
					+ str(indexed_array_position)
					+ ", but the object is actually at "
					+ str(object_index)
					+ "."
				)

	for raw_object_id in object_index_by_id.keys():
		if typeof(raw_object_id) != TYPE_INT:
			errors.append(
				"City object index contains non-integer key "
				+ str(raw_object_id)
				+ "."
			)

			continue

		var object_id: int = raw_object_id

		if not object_lookup.has(object_id):
			errors.append(
				"City object index contains orphan object ID "
				+ str(object_id)
				+ "."
			)

	if (
		object_index_by_id.size()
		!= object_lookup.size()
	):
		errors.append(
			"City object index contains "
				+ str(
					object_index_by_id.size()
				)
				+ " entries, but "
				+ str(object_lookup.size())
				+ " valid objects exist."
		)

	if (
		not object_lookup.is_empty()
		and object_state.next_object_id
		<= maximum_object_id
	):
		errors.append(
			"next_city_object_id is "
				+ str(object_state.next_object_id)
				+ ", but existing object ID "
				+ str(maximum_object_id)
				+ " is equal or greater."
		)

	return object_lookup


static func _validate_city_citizen_index(
	validation_target: Dictionary,
	errors: Array[String]
) -> Dictionary:
	var city_state: CitySettlementSimulationState = validation_target["city_state"]
	var citizen_state: CityCitizenRegistryState = city_state.citizen_registry_state
	var citizen_lookup: Dictionary = {}
	var maximum_citizen_id := 0

	for citizen_index in range(
		citizen_state.citizens.size()
	):
		var raw_citizen = citizen_state.citizens[
			citizen_index
		]

		if not raw_citizen is Dictionary:
			errors.append(
				"city_citizens["
				+ str(citizen_index)
				+ "] is not a Dictionary."
			)

			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(
			citizen.get("id", -1)
		)

		if citizen_id <= 0:
			errors.append(
				"Citizen at array index "
				+ str(citizen_index)
				+ " has invalid ID "
				+ str(citizen_id)
				+ "."
			)

			continue

		if citizen_lookup.has(citizen_id):
			errors.append(
				"Duplicate citizen ID "
				+ str(citizen_id)
				+ " exists at array indexes "
				+ str(citizen_lookup[citizen_id])
				+ " and "
				+ str(citizen_index)
				+ "."
			)

			continue

		citizen_lookup[citizen_id] = citizen_index
		maximum_citizen_id = maxi(
			maximum_citizen_id,
			citizen_id
		)

		if not citizen_state.citizen_index_by_id.has(
			citizen_id
		):
			errors.append(
				"Citizen index is missing citizen ID "
				+ str(citizen_id)
				+ "."
			)
		else:
			var indexed_array_position := int(
				citizen_state.citizen_index_by_id[
					citizen_id
				]
			)

			if indexed_array_position != citizen_index:
				errors.append(
					"Citizen index maps citizen ID "
					+ str(citizen_id)
					+ " to array index "
					+ str(indexed_array_position)
					+ ", but the citizen is actually at "
					+ str(citizen_index)
					+ "."
				)

	for raw_citizen_id in (
		citizen_state.citizen_index_by_id.keys()
	):
		if typeof(raw_citizen_id) != TYPE_INT:
			errors.append(
				"Citizen index contains non-integer key "
				+ str(raw_citizen_id)
				+ "."
			)

			continue

		var citizen_id: int = raw_citizen_id

		if not citizen_lookup.has(citizen_id):
			errors.append(
				"Citizen index contains orphan citizen ID "
				+ str(citizen_id)
				+ "."
			)

	if (
		citizen_state.citizen_index_by_id.size()
		!= citizen_lookup.size()
	):
		errors.append(
			"Citizen index contains "
				+ str(
					citizen_state.citizen_index_by_id.size()
				)
				+ " entries, but "
				+ str(citizen_lookup.size())
				+ " valid citizens exist."
		)

	if (
		not citizen_lookup.is_empty()
		and citizen_state.next_citizen_id
		<= maximum_citizen_id
	):
		errors.append(
			"next_city_citizen_id is "
				+ str(citizen_state.next_citizen_id)
				+ ", but existing citizen ID "
				+ str(maximum_citizen_id)
				+ " is equal or greater."
		)

	return citizen_lookup



#endregion

#region Validation Reporting
static func _report_validation_problems(
	result: Dictionary
) -> void:
	var errors: Array = result.get("errors", [])
	var warnings: Array = result.get(
		"warnings",
		[]
	)

	var reported_problem_count := 0

	for error_text in errors:
		if (
			reported_problem_count
			>= MAX_REPORTED_PROBLEMS
		):
			break

		push_error(
			"CITY STATE INVARIANT: "
			+ str(error_text)
		)

		reported_problem_count += 1

	for warning_text in warnings:
		if (
			reported_problem_count
			>= MAX_REPORTED_PROBLEMS
		):
			break

		push_warning(
			"CITY STATE WARNING: "
			+ str(warning_text)
		)

		reported_problem_count += 1

	var total_problem_count := (
		errors.size()
		+ warnings.size()
	)

	if total_problem_count > reported_problem_count:
		push_warning(
			"City validation found "
				+ str(
					total_problem_count
					- reported_problem_count
				)
				+ " additional problems that were not printed."
		)

#endregion
