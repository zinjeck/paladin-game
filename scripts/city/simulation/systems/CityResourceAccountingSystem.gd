extends RefCounted
class_name CityResourceAccountingSystem

# File responsibility: Settlement-level resource/container accounting behavior
# for one active CITY. Physical quantities remain authoritative in completed
# object containers, citizen inventories/cargo, logistics ground piles, and
# construction sites; this system only derives aggregate answers and governs
# the settlement-owned cache/change versions in CityResourceAccountingState.


static func get_current_state() -> CityResourceAccountingState:
	return WorldPoliticalState.get_current_city_resource_accounting_state()


static func get_city_container_version() -> int:
	return get_current_state().container_version


static func get_city_public_storage_version() -> int:
	return get_current_state().public_storage_version


static func mark_city_container_changed(
	city_object: Dictionary
) -> void:
	var state := get_current_state()
	state.container_version += 1

	if (
		CityResourceContainerSystem
		.city_object_counts_as_public_city_storage(city_object)
	):
		state.public_storage_version += 1


static func reset_city_resource_accounting_state() -> void:
	var state := get_current_state()
	state.owned_resource_amount_cache.clear()
	state.owned_resource_amount_cache_container_version = -1

	# A city reset removes every completed-object container, including every
	# public Stockpile/Keep. Preserve the historical single publication for
	# that aggregate removal rather than publishing once per deleted object.
	state.container_version += 1
	state.public_storage_version += 1


static func get_total_public_city_resource_amount(
	resource: String
) -> int:
	var total := 0

	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			not CityResourceContainerSystem
			.city_object_counts_as_public_city_storage(city_object)
		):
			continue

		total += (
			CityResourceContainerSystem
			.get_city_object_stored_resource_amount(city_object, resource)
		)

	return total


static func get_total_public_city_resource_storage_capacity(
	resource: String
) -> int:
	var total_capacity := 0

	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			not CityResourceContainerSystem
			.city_object_counts_as_public_city_storage(city_object)
			or not CityResourceContainerSystem.can_city_object_store_resource(
				city_object,
				resource
			)
		):
			continue

		total_capacity += (
			CityResourceContainerSystem
			.get_city_object_stored_resource_amount(city_object, resource)
			+ CityResourceContainerSystem.get_city_object_storage_free_space(
				city_object
			)
		)

	return total_capacity


static func get_total_stored_city_resource_amount(
	resource: String
) -> int:
	var total_amount := 0

	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			not CityResourceContainerSystem
			.city_object_counts_toward_city_storage_totals(city_object)
		):
			continue

		total_amount += (
			CityResourceContainerSystem
			.get_city_object_stored_resource_amount(city_object, resource)
		)

	return total_amount


static func get_total_physical_city_resource_amount(
	resource: String
) -> int:
	if not CityResourceCatalog.is_city_resource_type(resource):
		return 0

	var total_amount := (
		CityLogisticsSystem.get_total_city_ground_pile_resource_amount(
			resource
		)
	)

	# Conservation includes every completed-object container, including private
	# homes and storage that is intentionally absent from the secured-city total.
	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		total_amount += (
			CityResourceContainerSystem.get_city_object_stored_resource_amount(
				raw_city_object,
				resource
			)
		)

	# Personal inventory and in-transit cargo are still physical even though
	# neither is secured settlement property while a living citizen carries it.
	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		total_amount += (
			CityCitizenInventorySystem
			.get_city_citizen_record_carried_resource_amount(
				citizen,
				resource
			)
		)

	return total_amount


static func get_total_owned_city_resource_amount(
	resource: String
) -> int:
	return maxi(
		int(
			get_total_owned_city_resource_amounts().get(
				resource,
				0
			)
		),
		0
	)


static func get_total_owned_city_resource_amounts() -> Dictionary:
	var state := get_current_state()

	if (
		state.owned_resource_amount_cache_container_version
		== state.container_version
	):
		return state.owned_resource_amount_cache

	var totals: Dictionary = {}

	for resource in CityResourceCatalog.get_city_resource_types():
		totals[resource] = 0

	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			not CityResourceContainerSystem
			.city_object_counts_toward_city_storage_totals(city_object)
		):
			continue

		var raw_stored_resources = city_object.get("stored_resources", {})

		if not raw_stored_resources is Dictionary:
			continue

		for raw_resource in raw_stored_resources.keys():
			var resource := str(raw_resource)

			if (
				not CityResourceContainerSystem.can_city_object_store_resource(
					city_object,
					resource
				)
			):
				continue

			totals[resource] = (
				int(totals.get(resource, 0))
				+ CityResourceContainerSystem.get_resource_container_resource_amount(
					raw_stored_resources,
					resource
				)
			)

	state.owned_resource_amount_cache = totals
	state.owned_resource_amount_cache_container_version = (
		state.container_version
	)
	return state.owned_resource_amount_cache


static func get_total_city_resource_storage_capacity(
	resource: String
) -> int:
	var total_capacity := 0

	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			not CityResourceContainerSystem
			.city_object_counts_toward_city_storage_totals(city_object)
			or not CityResourceContainerSystem.can_city_object_store_resource(
				city_object,
				resource
			)
		):
			continue

		total_capacity += (
			CityResourceContainerSystem
			.get_city_object_stored_resource_amount(city_object, resource)
			+ CityResourceContainerSystem.get_city_object_storage_free_space(
				city_object
			)
		)

	return total_capacity
