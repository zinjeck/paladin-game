extends RefCounted
class_name CityResourceContainerSystem

# File responsibility: Generic sparse resource-container primitives plus
# completed-city-object storage policy, capacity, and authoritative mutation.
# This system answers questions about one container at a time; settlement-wide
# totals and cache/version reads belong to CityResourceAccountingSystem.


static func make_empty_resource_container(
	_resource_list: Array = []
) -> Dictionary:
	return {}


static func make_sparse_resource_container(
	raw_container
) -> Dictionary:
	var sparse_container: Dictionary = {}

	if not raw_container is Dictionary:
		return sparse_container

	for raw_resource in raw_container.keys():
		var raw_amount = raw_container[raw_resource]

		if typeof(raw_amount) != TYPE_INT:
			continue

		var amount: int = raw_amount

		if amount <= 0:
			continue

		sparse_container[str(raw_resource)] = amount

	return sparse_container


static func get_resource_container_resource_amount(
	raw_container,
	resource: String
) -> int:
	if not raw_container is Dictionary:
		return 0

	var raw_amount = raw_container.get(resource, 0)

	if typeof(raw_amount) != TYPE_INT:
		return 0

	return maxi(int(raw_amount), 0)


static func get_resource_container_total_amount(
	raw_container
) -> int:
	var total_amount := 0

	if not raw_container is Dictionary:
		return total_amount

	for raw_amount in raw_container.values():
		if typeof(raw_amount) != TYPE_INT:
			continue

		total_amount += maxi(int(raw_amount), 0)

	return total_amount


static func get_resource_container_present_resources(
	raw_container
) -> Array[String]:
	var present_resources: Array[String] = []

	if not raw_container is Dictionary:
		return present_resources

	for resource in CityResourceCatalog.get_city_resource_types():
		if get_resource_container_resource_amount(raw_container, resource) > 0:
			present_resources.append(resource)

	var extra_resources: Array[String] = []

	for raw_resource in raw_container.keys():
		var resource := str(raw_resource)
		var raw_amount = raw_container[raw_resource]

		if present_resources.has(resource):
			continue

		if typeof(raw_amount) != TYPE_INT:
			continue

		if int(raw_amount) <= 0:
			continue

		extra_resources.append(resource)

	extra_resources.sort()
	present_resources.append_array(extra_resources)
	return present_resources


static func get_food_nutrition_in_resource_container(
	raw_container
) -> int:
	var total_nutrition := 0

	for resource in CityResourceCatalog.get_city_food_resource_types():
		total_nutrition += (
			get_resource_container_resource_amount(
				raw_container,
				resource
			)
			* CityResourceCatalog.get_city_food_hunger_restore(resource)
		)

	return total_nutrition


static func make_empty_city_object_storage_for_type(
	object_type: String
) -> Dictionary:
	var definition := CityObjectCatalog.get_city_object_definition(object_type)

	if definition.is_empty():
		return {}

	var storage_resources: Array = definition.get("storage_resources", [])

	if storage_resources.is_empty():
		return {}

	return make_empty_resource_container(storage_resources)


static func _get_city_object_definition_from_object(
	city_object: Dictionary
) -> Dictionary:
	if city_object.is_empty():
		return {}

	return CityObjectCatalog.get_city_object_definition(
		str(city_object.get("type", ""))
	)


static func get_city_object_container_type(
	city_object: Dictionary
) -> String:
	var definition := _get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return CityObjectCatalog.CONTAINER_TYPE_NONE

	return str(
		definition.get(
			"container_type",
			CityObjectCatalog.CONTAINER_TYPE_NONE
		)
	)


static func get_city_object_container_access_policy(
	city_object: Dictionary
) -> Dictionary:
	return CityObjectCatalog._get_city_object_definition_dictionary(
		city_object,
		"container_access_policy"
	)


static func _get_container_policy_purposes(
	city_object: Dictionary,
	policy_key: String
) -> Array[String]:
	var purposes: Array[String] = []
	var policy := get_city_object_container_access_policy(city_object)
	var raw_purposes = policy.get(policy_key, [])

	if not raw_purposes is Array:
		return purposes

	for raw_purpose in raw_purposes:
		var purpose := str(raw_purpose)

		if purpose.is_empty() or purposes.has(purpose):
			continue

		purposes.append(purpose)

	return purposes


static func city_object_container_is_publicly_usable(
	city_object: Dictionary
) -> bool:
	var policy := get_city_object_container_access_policy(city_object)
	return bool(
		policy.get(
			CityObjectCatalog.CONTAINER_ACCESS_PUBLICLY_USABLE,
			false
		)
	)


static func city_object_counts_as_public_city_storage(
	city_object: Dictionary
) -> bool:
	return city_object_container_is_publicly_usable(city_object)


static func get_city_object_public_storage_tier(
	city_object: Dictionary
) -> int:
	if not city_object_counts_as_public_city_storage(city_object):
		return CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_NONE

	match str(city_object.get("type", "")):
		CityObjectCatalog.CITY_OBJECT_STOCKPILE:
			return CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_STOCKPILE

		CityObjectCatalog.CITY_OBJECT_CITY_CENTER:
			return CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_CITY_KEEP

	return CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_NONE


static func get_public_city_storage_tiers() -> Array[int]:
	return [
		CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_STOCKPILE,
		CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_CITY_KEEP,
	]


static func city_object_counts_toward_city_storage_totals(
	city_object: Dictionary
) -> bool:
	if city_object.is_empty():
		return false

	var container_type := get_city_object_container_type(city_object)
	var policy := get_city_object_container_access_policy(city_object)

	return (
		container_type != CityObjectCatalog.CONTAINER_TYPE_NONE
		and container_type != CityObjectCatalog.CONTAINER_TYPE_GROUND_PILE
		and bool(
			policy.get(
				CityObjectCatalog
				.CONTAINER_ACCESS_COUNTS_TOWARD_CITY_OWNED_TOTALS,
				false
			)
		)
	)


static func get_city_object_storage_resources(
	city_object: Dictionary
) -> Array[String]:
	var definition := _get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return []

	var result: Array[String] = []
	var storage_resources: Array = definition.get("storage_resources", [])

	for raw_resource in storage_resources:
		result.append(str(raw_resource))

	return result


static func get_city_object_present_storage_resources(
	city_object: Dictionary
) -> Array[String]:
	if city_object.is_empty():
		return []

	return get_resource_container_present_resources(
		city_object.get("stored_resources", {})
	)


static func can_city_object_store_resource(
	city_object: Dictionary,
	resource: String
) -> bool:
	if city_object.is_empty():
		return false

	return CityObjectCatalog.can_city_object_type_store_resource(
		str(city_object.get("type", "")),
		resource
	)


static func city_object_can_provide_haul_resource(
	city_object: Dictionary,
	resource: String,
	withdrawal_purpose: String
) -> bool:
	if withdrawal_purpose == CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE:
		return false

	if not can_city_object_store_resource(city_object, resource):
		return false

	if (
		not _get_container_policy_purposes(
			city_object,
			CityObjectCatalog.CONTAINER_ACCESS_HAUL_WITHDRAWAL_PURPOSES
		).has(withdrawal_purpose)
	):
		return false

	return get_city_object_stored_resource_amount(city_object, resource) > 0


static func city_object_can_accept_haul_resource(
	city_object: Dictionary,
	resource: String,
	deposit_purpose: String,
	require_free_space: bool = true
) -> bool:
	if deposit_purpose == CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE:
		return false

	if not can_city_object_store_resource(city_object, resource):
		return false

	if (
		not _get_container_policy_purposes(
			city_object,
			CityObjectCatalog.CONTAINER_ACCESS_HAUL_DEPOSIT_PURPOSES
		).has(deposit_purpose)
	):
		return false

	return (
		not require_free_space
		or get_city_object_resource_free_space(city_object, resource) > 0
	)


static func city_object_allows_direct_resource_withdrawal(
	city_object: Dictionary,
	withdrawal_purpose: String
) -> bool:
	if (
		withdrawal_purpose
		== CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE
	):
		return false

	return _get_container_policy_purposes(
		city_object,
		CityObjectCatalog.CONTAINER_ACCESS_DIRECT_WITHDRAWAL_PURPOSES
	).has(withdrawal_purpose)


static func get_city_object_storage_capacity(
	city_object: Dictionary
) -> int:
	var definition := _get_city_object_definition_from_object(city_object)

	if definition.is_empty():
		return 0

	return maxi(int(definition.get("storage_capacity", 0)), 0)


static func get_city_object_storage_used_capacity(
	city_object: Dictionary
) -> int:
	if city_object.is_empty():
		return 0

	return get_resource_container_total_amount(
		city_object.get("stored_resources", {})
	)


static func get_city_object_storage_free_space(
	city_object: Dictionary
) -> int:
	return maxi(
		get_city_object_storage_capacity(city_object)
		- get_city_object_storage_used_capacity(city_object),
		0
	)


static func get_city_object_unreserved_storage_free_space(
	city_object: Dictionary,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	if city_object.is_empty():
		return 0

	var endpoint := CityLogisticsSystem.make_city_citizen_haul_endpoint(
		int(city_object.get("id", -1))
	)

	return maxi(
		get_city_object_storage_free_space(city_object)
		- CityLogisticsSystem
		.get_city_haul_endpoint_destination_reserved_amount(
			endpoint,
			excluding_reservation_id
		),
		0
	)


static func get_city_object_storage_capacity_for_resource(
	city_object: Dictionary,
	resource: String
) -> int:
	if not can_city_object_store_resource(city_object, resource):
		return 0

	return get_city_object_storage_capacity(city_object)


static func get_city_object_stored_resource_amount(
	city_object: Dictionary,
	resource: String
) -> int:
	if city_object.is_empty():
		return 0

	if not can_city_object_store_resource(city_object, resource):
		return 0

	var stored_resources = city_object.get("stored_resources", {})

	if not stored_resources is Dictionary:
		return 0

	return get_resource_container_resource_amount(stored_resources, resource)


static func get_city_object_resource_free_space(
	city_object: Dictionary,
	resource: String
) -> int:
	if not can_city_object_store_resource(city_object, resource):
		return 0

	return get_city_object_storage_free_space(city_object)


static func set_city_object_stored_resource_amount(
	object_id: int,
	resource: String,
	amount: int,
	reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	var object_index := CityObjectSystem.get_city_object_index_by_id(object_id)

	if object_index < 0:
		return 0

	var raw_city_object = CityObjectSystem.get_city_objects()[object_index]

	if not raw_city_object is Dictionary:
		return 0

	var city_object: Dictionary = raw_city_object

	if not can_city_object_store_resource(city_object, resource):
		return 0

	var raw_stored_resources = city_object.get("stored_resources", {})
	var stored_resources := make_sparse_resource_container(
		raw_stored_resources
	)
	var old_amount := get_resource_container_resource_amount(
		stored_resources,
		resource
	)
	var used_without_resource := maxi(
		get_resource_container_total_amount(stored_resources) - old_amount,
		0
	)
	var endpoint := CityLogisticsSystem.make_city_citizen_haul_endpoint(
		object_id
	)
	var minimum_reserved_amount := (
		CityLogisticsSystem.get_city_haul_endpoint_source_reserved_amount(
			endpoint,
			resource,
			reservation_id
		)
	)
	var maximum_allowed_amount := maxi(
		get_city_object_storage_capacity(city_object)
		- used_without_resource
		- CityLogisticsSystem
		.get_city_haul_endpoint_destination_reserved_amount(
			endpoint,
			reservation_id
		),
		minimum_reserved_amount
	)
	var safe_amount := clampi(
		amount,
		minimum_reserved_amount,
		maximum_allowed_amount
	)

	if safe_amount > 0:
		stored_resources[resource] = safe_amount
	else:
		stored_resources.erase(resource)

	if (
		raw_stored_resources is Dictionary
		and raw_stored_resources == stored_resources
	):
		return safe_amount

	city_object["stored_resources"] = stored_resources

	if not CityObjectSystem.write_city_object_at_index(
		object_index,
		city_object
	):
		return old_amount

	CityResourceAccountingSystem.mark_city_container_changed(city_object)
	return safe_amount


static func add_resource_to_city_object_storage(
	object_id: int,
	resource: String,
	amount_delta: int,
	reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	if amount_delta <= 0:
		return 0

	var object_index := CityObjectSystem.get_city_object_index_by_id(object_id)

	if object_index < 0:
		return 0

	var raw_city_object = CityObjectSystem.get_city_objects()[object_index]

	if not raw_city_object is Dictionary:
		return 0

	var city_object: Dictionary = raw_city_object

	if not can_city_object_store_resource(city_object, resource):
		return 0

	var endpoint := CityLogisticsSystem.make_city_citizen_haul_endpoint(
		object_id
	)
	var free_space := get_city_object_unreserved_storage_free_space(
		city_object,
		reservation_id
	)

	if reservation_id > 0:
		var reservation := CityLogisticsSystem.get_city_haul_reservation(
			reservation_id
		)
		var reserved_resource_amount := (
			CityLogisticsSystem
			.get_city_haul_reservation_destination_resource_amount(
				reservation_id,
				resource
			)
		)

		if (
			reservation.is_empty()
			or not CityLogisticsSystem.city_citizen_haul_endpoints_match(
				reservation.get("destination", {}),
				endpoint
			)
			or reserved_resource_amount <= 0
		):
			return 0

		free_space = mini(free_space, reserved_resource_amount)

	if free_space <= 0:
		return 0

	var accepted_amount := mini(amount_delta, free_space)
	var current_amount := get_city_object_stored_resource_amount(
		city_object,
		resource
	)

	set_city_object_stored_resource_amount(
		object_id,
		resource,
		current_amount + accepted_amount,
		reservation_id
	)

	return accepted_amount


static func add_resource_bundle_to_city_object_storage(
	object_id: int,
	requested_resources: Dictionary
) -> bool:
	if requested_resources.is_empty():
		return false

	var object_index := CityObjectSystem.get_city_object_index_by_id(object_id)

	if object_index < 0:
		return false

	var raw_city_object = CityObjectSystem.get_city_objects()[object_index]

	if not raw_city_object is Dictionary:
		return false

	var city_object: Dictionary = raw_city_object
	var normalized_resources: Dictionary = {}
	var total_requested_amount := 0

	for raw_resource in requested_resources.keys():
		if typeof(raw_resource) != TYPE_STRING:
			return false

		var resource: String = raw_resource
		var raw_amount = requested_resources[raw_resource]

		if typeof(raw_amount) != TYPE_INT:
			return false

		var amount: int = raw_amount

		if amount <= 0 or not can_city_object_store_resource(
			city_object,
			resource
		):
			return false

		normalized_resources[resource] = amount
		total_requested_amount += amount

	if (
		total_requested_amount <= 0
		or total_requested_amount
		> get_city_object_unreserved_storage_free_space(city_object)
	):
		return false

	var stored_resources := make_sparse_resource_container(
		city_object.get("stored_resources", {})
	)

	for raw_resource in normalized_resources.keys():
		var resource: String = raw_resource
		stored_resources[resource] = (
			get_resource_container_resource_amount(stored_resources, resource)
			+ int(normalized_resources[resource])
		)

	city_object["stored_resources"] = stored_resources

	if not CityObjectSystem.write_city_object_at_index(
		object_index,
		city_object
	):
		return false

	CityResourceAccountingSystem.mark_city_container_changed(city_object)
	return true


static func remove_resource_from_city_object_storage(
	object_id: int,
	resource: String,
	requested_amount: int,
	reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	if requested_amount <= 0:
		return 0

	var city_object := CityObjectSystem.get_city_object_by_id(object_id)

	if city_object.is_empty():
		return 0

	var current_amount := get_city_object_stored_resource_amount(
		city_object,
		resource
	)
	var endpoint := CityLogisticsSystem.make_city_citizen_haul_endpoint(
		object_id
	)
	var removable_amount := maxi(
		current_amount
		- CityLogisticsSystem.get_city_haul_endpoint_source_reserved_amount(
			endpoint,
			resource,
			reservation_id
		),
		0
	)

	if reservation_id > 0:
		var reservation := CityLogisticsSystem.get_city_haul_reservation(
			reservation_id
		)

		if (
			reservation.is_empty()
			or not CityLogisticsSystem.city_citizen_haul_endpoints_match(
				reservation.get("source", {}),
				endpoint
			)
			or str(
				reservation.get(
					"resource_type",
					CityResourceCatalog.RESOURCE_NONE
				)
			) != resource
		):
			return 0

		removable_amount = mini(
			removable_amount,
			maxi(int(reservation.get("source_reserved_amount", 0)), 0)
		)

	var amount_to_remove := mini(requested_amount, removable_amount)

	if amount_to_remove <= 0:
		return 0

	var final_amount := set_city_object_stored_resource_amount(
		object_id,
		resource,
		current_amount - amount_to_remove,
		reservation_id
	)

	return maxi(current_amount - final_amount, 0)
