extends RefCounted
class_name CityCitizenInventorySystem

# Authoritative mutation and query boundary for resources physically carried by
# citizens. Personal inventory, carry capacity, and haul cargo remain embedded
# in each citizen record; this system deliberately does not create a second
# settlement-wide inventory ledger.


static func ensure_city_citizen_inventory_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _ensure_city_citizen_inventory_state(
		city_state.citizen_registry_state
	)


static func _ensure_city_citizen_inventory_state(
	registry_state: CityCitizenRegistryState
) -> int:
	var migrated_count := 0

	for citizen_index in range(registry_state.citizens.size()):
		var raw_citizen = registry_state.citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_was_migrated := false
		var raw_carry_capacity = citizen.get("carry_capacity")
		var carried_state_is_interpretable := (
			_record_carried_state_is_interpretable(citizen)
		)

		if carried_state_is_interpretable:
			var minimum_lossless_capacity := (
				_get_record_total_carried_amount(citizen)
			)

			if typeof(raw_carry_capacity) != TYPE_INT:
				citizen["carry_capacity"] = maxi(
					CityCitizens.DEFAULT_CITIZEN_CARRY_CAPACITY,
					minimum_lossless_capacity
				)
				citizen_was_migrated = true
			elif int(raw_carry_capacity) < minimum_lossless_capacity:
				citizen["carry_capacity"] = minimum_lossless_capacity
				citizen_was_migrated = true

		var raw_inventory = citizen.get("inventory")

		if not citizen.has("inventory"):
			citizen["inventory"] = {}
			citizen_was_migrated = true
		elif not raw_inventory is Dictionary:
			# A present wrong-type value may encode legacy data that cannot be
			# interpreted losslessly. Leave it intact for validation.
			pass
		else:
			var normalized_inventory := (
				CityCitizens.make_sparse_city_citizen_inventory(raw_inventory)
			)

			# Normalize harmless legacy zeros while leaving ambiguous malformed
			# quantities intact for validation. Bootstrap must never choose what
			# physical resources to discard.
			if (
				raw_inventory != normalized_inventory
				and _manifest_normalization_preserves_physical_amount(
					raw_inventory,
					normalized_inventory
				)
			):
				citizen["inventory"] = normalized_inventory
				citizen_was_migrated = true

		var raw_cargo = citizen.get("haul_cargo")

		if not citizen.has("haul_cargo"):
			citizen["haul_cargo"] = (
				CityCitizens.make_city_citizen_haul_cargo()
			)
			citizen_was_migrated = true
		elif not raw_cargo is Dictionary:
			# As with inventory, never erase an uninterpretable present value.
			pass
		else:
			var normalized_cargo := (
				CityCitizens.make_city_citizen_haul_cargo(raw_cargo)
			)

			if (
				raw_cargo != normalized_cargo
				and _cargo_normalization_preserves_physical_amount(
					raw_cargo,
					normalized_cargo
				)
			):
				citizen["haul_cargo"] = normalized_cargo
				citizen_was_migrated = true

		if not citizen_was_migrated:
			continue

		registry_state.citizens[citizen_index] = citizen
		migrated_count += 1

	if migrated_count > 0:
		registry_state.citizen_version += 1

	return migrated_count


static func _resolve_registry_state(
	registry_state: CityCitizenRegistryState
) -> CityCitizenRegistryState:
	return registry_state


static func _get_city_citizen_index_by_id(
	registry_state: CityCitizenRegistryState,
	citizen_id: int
) -> int:
	if citizen_id < 0 or not registry_state.citizen_index_by_id.has(citizen_id):
		return -1

	var citizen_index := int(registry_state.citizen_index_by_id[citizen_id])
	if citizen_index < 0 or citizen_index >= registry_state.citizens.size():
		push_error(
			"Stale city citizen index for citizen ID " + str(citizen_id)
		)
		registry_state.citizen_index_by_id.erase(citizen_id)
		return -1

	var raw_citizen = registry_state.citizens[citizen_index]
	if not raw_citizen is Dictionary:
		push_error(
			"City citizen index points to non-Dictionary data for citizen ID "
			+ str(citizen_id)
		)
		registry_state.citizen_index_by_id.erase(citizen_id)
		return -1

	if int((raw_citizen as Dictionary).get("id", -1)) != citizen_id:
		push_error(
			"City citizen index mismatch for requested ID " + str(citizen_id)
		)
		registry_state.citizen_index_by_id.erase(citizen_id)
		return -1

	return citizen_index


static func _get_city_citizen_by_id(
	registry_state: CityCitizenRegistryState,
	citizen_id: int
) -> Dictionary:
	var citizen_index := _get_city_citizen_index_by_id(
		registry_state,
		citizen_id
	)
	if citizen_index < 0:
		return {}

	var raw_citizen = registry_state.citizens[citizen_index]
	if not raw_citizen is Dictionary:
		return {}
	return raw_citizen


static func get_city_citizen_carry_capacity(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> int:
	registry_state = _resolve_registry_state(registry_state)
	var citizen := _get_city_citizen_by_id(registry_state, citizen_id)

	if citizen.is_empty():
		return 0

	var raw_carry_capacity = citizen.get("carry_capacity")

	if typeof(raw_carry_capacity) != TYPE_INT:
		return 0

	return maxi(int(raw_carry_capacity), 0)


static func get_city_citizen_carry_capacity_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return get_city_citizen_carry_capacity(
		citizen_id,
		city_state.citizen_registry_state
	)


static func set_city_citizen_carry_capacity(
	citizen_id: int,
	carry_capacity: int,
	registry_state: CityCitizenRegistryState
) -> bool:
	registry_state = _resolve_registry_state(registry_state)
	var citizen_index := _get_city_citizen_index_by_id(
		registry_state,
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var safe_capacity := maxi(carry_capacity, 0)
	var citizen: Dictionary = raw_citizen

	if not _record_carried_state_is_interpretable(citizen):
		return false

	if safe_capacity < get_city_citizen_total_carried_amount(
		citizen_id,
		registry_state
	):
		return false

	var raw_carry_capacity = citizen.get("carry_capacity")

	if (
		citizen.has("carry_capacity")
		and typeof(raw_carry_capacity) == TYPE_INT
		and int(raw_carry_capacity) == safe_capacity
	):
		return true

	citizen["carry_capacity"] = safe_capacity
	registry_state.citizens[citizen_index] = citizen
	registry_state.citizen_version += 1
	return true


static func set_city_citizen_carry_capacity_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	carry_capacity: int
) -> bool:
	return set_city_citizen_carry_capacity(
		citizen_id,
		carry_capacity,
		city_state.citizen_registry_state
	)


static func get_city_citizen_inventory(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> Dictionary:
	registry_state = _resolve_registry_state(registry_state)
	var citizen := _get_city_citizen_by_id(registry_state, citizen_id)

	if citizen.is_empty():
		return {}

	return CityCitizens.make_sparse_city_citizen_inventory(
		citizen.get("inventory", {})
	)


static func get_city_citizen_inventory_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> Dictionary:
	return get_city_citizen_inventory(
		citizen_id,
		city_state.citizen_registry_state
	)


static func get_city_citizen_inventory_resource_amount(
	citizen_id: int,
	resource: String,
	registry_state: CityCitizenRegistryState
) -> int:
	if not CityResourceCatalog.is_city_resource_type(resource):
		return 0

	var inventory := get_city_citizen_inventory(citizen_id, registry_state)
	var raw_amount = inventory.get(resource, 0)

	if typeof(raw_amount) != TYPE_INT:
		return 0

	return maxi(int(raw_amount), 0)


static func get_city_citizen_inventory_resource_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	resource: String
) -> int:
	return get_city_citizen_inventory_resource_amount(
		citizen_id,
		resource,
		city_state.citizen_registry_state
	)


static func get_city_citizen_inventory_used_capacity(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> int:
	var total_amount := 0

	for raw_amount in get_city_citizen_inventory(
		citizen_id,
		registry_state
	).values():
		if typeof(raw_amount) == TYPE_INT:
			total_amount += maxi(int(raw_amount), 0)

	return total_amount


static func get_city_citizen_inventory_used_capacity_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return get_city_citizen_inventory_used_capacity(
		citizen_id,
		city_state.citizen_registry_state
	)


static func get_city_citizen_personal_inventory_free_space(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> int:
	registry_state = _resolve_registry_state(registry_state)
	var citizen := _get_city_citizen_by_id(registry_state, citizen_id)

	if (
		citizen.is_empty()
		or not _record_carried_state_is_interpretable(citizen)
	):
		return 0

	return maxi(
		get_city_citizen_carry_capacity(citizen_id, registry_state)
		- get_city_citizen_inventory_used_capacity(citizen_id, registry_state),
		0
	)


static func get_city_citizen_personal_inventory_free_space_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return get_city_citizen_personal_inventory_free_space(
		citizen_id,
		city_state.citizen_registry_state
	)


static func get_city_citizen_inventory_free_space(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> int:
	registry_state = _resolve_registry_state(registry_state)
	var citizen := _get_city_citizen_by_id(registry_state, citizen_id)

	if (
		citizen.is_empty()
		or not _record_carried_state_is_interpretable(citizen)
	):
		return 0

	return maxi(
		get_city_citizen_carry_capacity(citizen_id, registry_state)
		- get_city_citizen_inventory_used_capacity(citizen_id, registry_state)
		- get_city_citizen_haul_cargo_amount(citizen_id, registry_state),
		0
	)


static func get_city_citizen_inventory_free_space_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return get_city_citizen_inventory_free_space(
		citizen_id,
		city_state.citizen_registry_state
	)


static func set_city_citizen_inventory_resource_amount(
	citizen_id: int,
	resource: String,
	amount: int,
	registry_state: CityCitizenRegistryState
) -> int:
	if not CityResourceCatalog.is_city_resource_type(resource):
		return 0

	registry_state = _resolve_registry_state(registry_state)
	var citizen_index := _get_city_citizen_index_by_id(
		registry_state,
		citizen_id
	)

	if citizen_index < 0:
		return 0

	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return 0

	var citizen: Dictionary = raw_citizen
	var raw_inventory = citizen.get("inventory", {})
	var inventory := CityCitizens.make_sparse_city_citizen_inventory(
		raw_inventory
	)
	var old_amount := maxi(int(inventory.get(resource, 0)), 0)

	if not _record_carried_state_is_interpretable(citizen):
		return old_amount

	var total_without_resource := maxi(
		_get_resource_manifest_total(inventory)
		- old_amount,
		0
	)
	var safe_amount := mini(
		maxi(amount, 0),
		maxi(
			get_city_citizen_carry_capacity(citizen_id, registry_state)
			- get_city_citizen_haul_cargo_amount(citizen_id, registry_state)
			- total_without_resource,
			0
		)
	)

	if safe_amount > 0:
		inventory[resource] = safe_amount
	else:
		inventory.erase(resource)

	if (
		citizen.has("inventory")
		and raw_inventory is Dictionary
		and raw_inventory == inventory
	):
		return safe_amount

	citizen["inventory"] = inventory
	registry_state.citizens[citizen_index] = citizen
	registry_state.citizen_version += 1
	return safe_amount


static func set_city_citizen_inventory_resource_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	resource: String,
	amount: int
) -> int:
	return set_city_citizen_inventory_resource_amount(
		citizen_id,
		resource,
		amount,
		city_state.citizen_registry_state
	)


static func add_resource_to_city_citizen_inventory(
	citizen_id: int,
	resource: String,
	amount_delta: int,
	registry_state: CityCitizenRegistryState
) -> int:
	if amount_delta <= 0:
		return 0

	var current_amount := get_city_citizen_inventory_resource_amount(
		citizen_id,
		resource,
		registry_state
	)
	var final_amount := set_city_citizen_inventory_resource_amount(
		citizen_id,
		resource,
		current_amount + amount_delta,
		registry_state
	)
	return maxi(final_amount - current_amount, 0)


static func add_resource_to_city_citizen_inventory_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	resource: String,
	amount_delta: int
) -> int:
	return add_resource_to_city_citizen_inventory(
		citizen_id,
		resource,
		amount_delta,
		city_state.citizen_registry_state
	)


static func remove_resource_from_city_citizen_inventory(
	citizen_id: int,
	resource: String,
	requested_amount: int,
	registry_state: CityCitizenRegistryState
) -> int:
	if requested_amount <= 0:
		return 0

	var current_amount := get_city_citizen_inventory_resource_amount(
		citizen_id,
		resource,
		registry_state
	)
	var amount_to_remove := mini(requested_amount, current_amount)

	if amount_to_remove <= 0:
		return 0

	var final_amount := set_city_citizen_inventory_resource_amount(
		citizen_id,
		resource,
		current_amount - amount_to_remove,
		registry_state
	)
	return maxi(current_amount - final_amount, 0)


static func remove_resource_from_city_citizen_inventory_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	resource: String,
	requested_amount: int
) -> int:
	return remove_resource_from_city_citizen_inventory(
		citizen_id,
		resource,
		requested_amount,
		city_state.citizen_registry_state
	)


static func get_city_citizen_haul_cargo(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> Dictionary:
	registry_state = _resolve_registry_state(registry_state)
	var citizen := _get_city_citizen_by_id(registry_state, citizen_id)

	if citizen.is_empty():
		return CityCitizens.make_city_citizen_haul_cargo()

	var raw_cargo = citizen.get("haul_cargo", {})

	if not raw_cargo is Dictionary:
		return CityCitizens.make_city_citizen_haul_cargo()

	return CityCitizens.make_city_citizen_haul_cargo(raw_cargo)


static func get_city_citizen_haul_cargo_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> Dictionary:
	return get_city_citizen_haul_cargo(
		citizen_id,
		city_state.citizen_registry_state
	)


static func get_city_citizen_haul_cargo_resources(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> Dictionary:
	var raw_resources = get_city_citizen_haul_cargo(
		citizen_id,
		registry_state
	).get(
		"resources",
		{}
	)

	if not raw_resources is Dictionary:
		return {}

	return raw_resources.duplicate(true)


static func get_city_citizen_haul_cargo_resources_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> Dictionary:
	return get_city_citizen_haul_cargo_resources(
		citizen_id,
		city_state.citizen_registry_state
	)


static func get_city_citizen_haul_cargo_resource_amount(
	citizen_id: int,
	resource: String,
	registry_state: CityCitizenRegistryState
) -> int:
	if not CityResourceCatalog.is_city_resource_type(resource):
		return 0

	return maxi(
		int(
			get_city_citizen_haul_cargo_resources(
				citizen_id,
				registry_state
			).get(
				resource,
				0
			)
		),
		0
	)


static func get_city_citizen_haul_cargo_resource_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	resource: String
) -> int:
	return get_city_citizen_haul_cargo_resource_amount(
		citizen_id,
		resource,
		city_state.citizen_registry_state
	)


static func get_city_citizen_haul_cargo_resource(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> String:
	return str(
		get_city_citizen_haul_cargo(citizen_id, registry_state).get(
			"resource_type",
			CityResourceCatalog.RESOURCE_NONE
		)
	)


static func get_city_citizen_haul_cargo_resource_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> String:
	return get_city_citizen_haul_cargo_resource(
		citizen_id,
		city_state.citizen_registry_state
	)


static func get_city_citizen_haul_cargo_amount(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> int:
	return maxi(
		int(
			get_city_citizen_haul_cargo(citizen_id, registry_state).get(
				"amount",
				0
			)
		),
		0
	)


static func get_city_citizen_haul_cargo_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return get_city_citizen_haul_cargo_amount(
		citizen_id,
		city_state.citizen_registry_state
	)


static func get_city_citizen_total_carried_amount(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> int:
	return (
		get_city_citizen_inventory_used_capacity(citizen_id, registry_state)
		+ get_city_citizen_haul_cargo_amount(citizen_id, registry_state)
	)


static func get_city_citizen_total_carried_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return get_city_citizen_total_carried_amount(
		citizen_id,
		city_state.citizen_registry_state
	)


static func get_city_citizen_record_carried_resource_amount(
	citizen: Dictionary,
	resource: String
) -> int:
	if (
		citizen.is_empty()
		or not CityResourceCatalog.is_city_resource_type(resource)
	):
		return 0

	var inventory := CityCitizens.make_sparse_city_citizen_inventory(
		citizen.get("inventory", {})
	)
	var inventory_amount := 0
	var raw_inventory_amount = inventory.get(resource, 0)

	if typeof(raw_inventory_amount) == TYPE_INT:
		inventory_amount = maxi(int(raw_inventory_amount), 0)

	var cargo := CityCitizens.make_city_citizen_haul_cargo()
	var raw_cargo = citizen.get("haul_cargo")

	if raw_cargo is Dictionary:
		cargo = CityCitizens.make_city_citizen_haul_cargo(raw_cargo)

	var raw_cargo_resources = cargo.get("resources", {})
	var cargo_amount := 0

	if raw_cargo_resources is Dictionary:
		var raw_cargo_amount = raw_cargo_resources.get(resource, 0)

		if typeof(raw_cargo_amount) == TYPE_INT:
			cargo_amount = maxi(int(raw_cargo_amount), 0)

	return inventory_amount + cargo_amount


static func get_city_citizen_available_haul_capacity(
	citizen_id: int,
	registry_state: CityCitizenRegistryState
) -> int:
	registry_state = _resolve_registry_state(registry_state)
	var citizen := _get_city_citizen_by_id(registry_state, citizen_id)

	if (
		citizen.is_empty()
		or not _record_carried_state_is_interpretable(citizen)
	):
		return 0

	return maxi(
		get_city_citizen_carry_capacity(citizen_id, registry_state)
		- get_city_citizen_total_carried_amount(citizen_id, registry_state),
		0
	)


static func get_city_citizen_available_haul_capacity_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return get_city_citizen_available_haul_capacity(
		citizen_id,
		city_state.citizen_registry_state
	)


static func set_city_citizen_haul_cargo_resources(
	citizen_id: int,
	requested_resources: Dictionary,
	registry_state: CityCitizenRegistryState
) -> int:
	registry_state = _resolve_registry_state(registry_state)
	var citizen_index := _get_city_citizen_index_by_id(
		registry_state,
		citizen_id
	)

	if citizen_index < 0:
		return 0

	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return 0

	var citizen: Dictionary = raw_citizen
	var existing_cargo_amount := get_city_citizen_haul_cargo_amount(
		citizen_id,
		registry_state
	)

	if not _record_carried_state_is_interpretable(citizen):
		return existing_cargo_amount

	var normalized_resources: Dictionary = {}
	var requested_total := 0

	for raw_resource in requested_resources.keys():
		if typeof(raw_resource) != TYPE_STRING:
			return existing_cargo_amount

		var resource: String = raw_resource
		var raw_amount = requested_resources.get(raw_resource)

		if (
			typeof(raw_amount) != TYPE_INT
			or not CityResourceCatalog.is_city_resource_type(resource)
			or int(raw_amount) <= 0
		):
			return existing_cargo_amount

		var amount: int = raw_amount
		normalized_resources[resource] = amount
		requested_total += amount

	var maximum_cargo_amount := maxi(
		get_city_citizen_carry_capacity(citizen_id, registry_state)
		- get_city_citizen_inventory_used_capacity(citizen_id, registry_state),
		0
	)

	if requested_total > maximum_cargo_amount:
		return existing_cargo_amount

	var final_cargo := CityCitizens.make_city_citizen_haul_cargo({
		"resources": normalized_resources,
	})
	var raw_existing_cargo = citizen.get("haul_cargo", {})

	if (
		citizen.has("haul_cargo")
		and raw_existing_cargo is Dictionary
		and raw_existing_cargo == final_cargo
	):
		return requested_total

	citizen["haul_cargo"] = final_cargo
	registry_state.citizens[citizen_index] = citizen
	registry_state.citizen_version += 1
	return requested_total


static func set_city_citizen_haul_cargo_resources_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	requested_resources: Dictionary
) -> int:
	return set_city_citizen_haul_cargo_resources(
		citizen_id,
		requested_resources,
		city_state.citizen_registry_state
	)


static func change_city_citizen_haul_cargo_resource(
	citizen_id: int,
	resource: String,
	amount_delta: int,
	registry_state: CityCitizenRegistryState
) -> int:
	if not CityResourceCatalog.is_city_resource_type(resource):
		return 0

	var resources := get_city_citizen_haul_cargo_resources(
		citizen_id,
		registry_state
	)
	var old_amount := maxi(int(resources.get(resource, 0)), 0)
	var final_amount := old_amount + amount_delta

	if final_amount > 0:
		resources[resource] = final_amount
	else:
		resources.erase(resource)
		final_amount = 0

	var expected_total := 0

	for raw_amount in resources.values():
		expected_total += maxi(int(raw_amount), 0)

	if set_city_citizen_haul_cargo_resources(
		citizen_id,
		resources,
		registry_state
	) != expected_total:
		return old_amount

	return final_amount


static func change_city_citizen_haul_cargo_resource_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	resource: String,
	amount_delta: int
) -> int:
	return change_city_citizen_haul_cargo_resource(
		citizen_id,
		resource,
		amount_delta,
		city_state.citizen_registry_state
	)


static func set_city_citizen_haul_cargo(
	citizen_id: int,
	resource: String,
	amount: int,
	registry_state: CityCitizenRegistryState
) -> int:
	var requested_amount := maxi(amount, 0)
	var resources: Dictionary = {}

	if requested_amount > 0:
		if not CityResourceCatalog.is_city_resource_type(resource):
			return get_city_citizen_haul_cargo_amount(
				citizen_id,
				registry_state
			)

		resources[resource] = requested_amount

	var final_total := set_city_citizen_haul_cargo_resources(
		citizen_id,
		resources,
		registry_state
	)

	if requested_amount <= 0:
		return 0

	if final_total != requested_amount:
		return get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			resource,
			registry_state
		)

	return requested_amount


static func set_city_citizen_haul_cargo_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	resource: String,
	amount: int
) -> int:
	return set_city_citizen_haul_cargo(
		citizen_id,
		resource,
		amount,
		city_state.citizen_registry_state
	)


static func _get_resource_manifest_total(resources: Dictionary) -> int:
	var total_amount := 0

	for raw_amount in resources.values():
		if typeof(raw_amount) == TYPE_INT:
			total_amount += maxi(int(raw_amount), 0)

	return total_amount


static func _get_record_total_carried_amount(citizen: Dictionary) -> int:
	var inventory := CityCitizens.make_sparse_city_citizen_inventory(
		citizen.get("inventory", {})
	)
	var cargo := CityCitizens.make_city_citizen_haul_cargo()
	var raw_cargo = citizen.get("haul_cargo")

	if raw_cargo is Dictionary:
		cargo = CityCitizens.make_city_citizen_haul_cargo(raw_cargo)

	return (
		_get_resource_manifest_total(inventory)
		+ maxi(int(cargo.get("amount", 0)), 0)
	)


static func _record_carried_state_is_interpretable(
	citizen: Dictionary
) -> bool:
	if citizen.has("inventory"):
		var raw_inventory = citizen.get("inventory")

		if not raw_inventory is Dictionary:
			return false

		var normalized_inventory := (
			CityCitizens.make_sparse_city_citizen_inventory(raw_inventory)
		)

		if not _manifest_normalization_preserves_physical_amount(
			raw_inventory,
			normalized_inventory
		):
			return false

	if citizen.has("haul_cargo"):
		var raw_cargo = citizen.get("haul_cargo")

		if not raw_cargo is Dictionary:
			return false

		var normalized_cargo := (
			CityCitizens.make_city_citizen_haul_cargo(raw_cargo)
		)

		if not _cargo_normalization_preserves_physical_amount(
			raw_cargo,
			normalized_cargo
		):
			return false

	return true


static func _cargo_normalization_preserves_physical_amount(
	raw_cargo: Dictionary,
	normalized_cargo: Dictionary
) -> bool:
	var raw_resources = raw_cargo.get("resources")
	var raw_total := -1

	if raw_resources is Dictionary and not raw_resources.is_empty():
		raw_total = 0

		for raw_resource in raw_resources.keys():
			var raw_amount = raw_resources[raw_resource]

			if (
				typeof(raw_resource) != TYPE_STRING
				or typeof(raw_amount) != TYPE_INT
				or int(raw_amount) <= 0
			):
				return false

			raw_total += int(raw_amount)
	else:
		var raw_amount = raw_cargo.get("amount", 0)
		var raw_resource = raw_cargo.get(
			"resource_type",
			CityResourceCatalog.RESOURCE_NONE
		)

		if (
			typeof(raw_amount) != TYPE_INT
			or typeof(raw_resource) != TYPE_STRING
			or int(raw_amount) < 0
			or (
				int(raw_amount) > 0
				and str(raw_resource) == CityResourceCatalog.RESOURCE_NONE
			)
		):
			return false

		raw_total = int(raw_amount)

	return (
		raw_total
		== maxi(int(normalized_cargo.get("amount", 0)), 0)
	)


static func _manifest_normalization_preserves_physical_amount(
	raw_manifest: Dictionary,
	normalized_manifest: Dictionary
) -> bool:
	var raw_total := 0

	for raw_resource in raw_manifest.keys():
		var raw_amount = raw_manifest[raw_resource]

		if (
			typeof(raw_resource) != TYPE_STRING
			or typeof(raw_amount) != TYPE_INT
			or int(raw_amount) < 0
		):
			return false

		raw_total += int(raw_amount)

	return raw_total == _get_resource_manifest_total(normalized_manifest)
