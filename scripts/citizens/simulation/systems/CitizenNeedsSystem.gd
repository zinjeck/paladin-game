extends RefCounted
class_name CitizenNeedsSystem

# Needs remain independent of the citizen's current activity. Hunger can fall
# and food can be eaten while a citizen works, walks, rests, or hauls. Physical
# food is always removed from personal inventory one whole item at a time.
#
# Immediate food allocation is also deliberately one whole item at a time.
# Citizens reassess after each item instead of filling a private pocket toward
# 100 while equally or more hungry citizens are still waiting for shared food.


static func ensure_city_citizen_need_state() -> int:
	return _ensure_city_citizen_need_state(
		CityCitizenUnboundCompatibility.get_city_state().citizen_registry_state
	)


static func ensure_city_citizen_need_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _ensure_city_citizen_need_state(
		city_state.citizen_registry_state
	)


static func _ensure_city_citizen_need_state(
	registry_state: CityCitizenRegistryState
) -> int:
	var migrated_count := 0

	for citizen_index in range(registry_state.citizens.size()):
		var raw_citizen = registry_state.citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if (
			CityCitizens.has_complete_city_citizen_need_state(citizen)
			and int(citizen.get("hunger", -1)) >= 0
			and int(citizen.get("hunger", -1))
			<= CityCitizens.MAX_CITIZEN_HUNGER
			and int(citizen.get("hunger_decay_remainder", -1)) >= 0
			and int(citizen.get("hunger_decay_remainder", -1))
			< CityCitizens.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES
			and int(citizen.get("happiness", -1)) >= 0
			and int(citizen.get("happiness", -1)) <= 100
		):
			continue

		# Normalize only the scalar need fields. Preserving the citizen Dictionary
		# also preserves the identity of unrelated task, movement, and inventory
		# records held by focused runtime systems.
		CityCitizens.normalize_city_citizen_need_state(citizen)
		registry_state.citizens[citizen_index] = citizen
		migrated_count += 1

	if migrated_count > 0:
		registry_state.citizen_version += 1

	return migrated_count


static func _get_city_citizen_by_id(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> Dictionary:
	if city_state == null:
		return CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	return CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
		city_state,
		citizen_id
	)


static func _get_city_citizen_index_by_id(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	if city_state == null:
		return CityCitizenRegistrySystem.get_city_citizen_index_by_id(citizen_id)
	return CityCitizenRegistrySystem.get_city_citizen_index_by_id_for_city_state(
		city_state,
		citizen_id
	)


static func _get_registry_state(
	city_state: CitySettlementSimulationState
) -> CityCitizenRegistryState:
	if city_state == null:
		return CityCitizenUnboundCompatibility.get_city_state().citizen_registry_state
	return city_state.citizen_registry_state


static func _mark_city_citizens_changed(
	city_state: CitySettlementSimulationState
) -> void:
	if city_state == null:
		CityCitizenRegistrySystem.mark_city_citizens_changed()
		return
	city_state.citizen_registry_state.citizen_version += 1


static func get_city_citizen_hunger(citizen_id: int) -> int:
	return _get_city_citizen_hunger(CityCitizenUnboundCompatibility.get_city_state(), citizen_id)


static func get_city_citizen_hunger_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return _get_city_citizen_hunger(city_state, citizen_id)


static func _get_city_citizen_hunger(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	var citizen := _get_city_citizen_by_id(city_state, citizen_id)

	if citizen.is_empty():
		return 0

	return clampi(
		int(citizen.get("hunger", CityCitizens.DEFAULT_CITIZEN_HUNGER)),
		0,
		CityCitizens.MAX_CITIZEN_HUNGER
	)


static func set_city_citizen_hunger_state(
	citizen_id: int,
	hunger: int,
	hunger_decay_remainder: int
) -> bool:
	return _set_city_citizen_hunger_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		citizen_id,
		hunger,
		hunger_decay_remainder
	)


static func set_city_citizen_hunger_state_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	hunger: int,
	hunger_decay_remainder: int
) -> bool:
	return _set_city_citizen_hunger_state(
		city_state,
		citizen_id,
		hunger,
		hunger_decay_remainder
	)


static func _set_city_citizen_hunger_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	hunger: int,
	hunger_decay_remainder: int
) -> bool:
	var citizen_index := _get_city_citizen_index_by_id(
		city_state,
		citizen_id
	)

	if citizen_index < 0:
		return false

	var registry_state := _get_registry_state(city_state)
	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var safe_hunger := clampi(
		hunger,
		0,
		CityCitizens.MAX_CITIZEN_HUNGER
	)
	var safe_remainder := clampi(
		hunger_decay_remainder,
		0,
		CityCitizens.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES - 1
	)

	if (
		citizen.has("hunger")
		and typeof(citizen.get("hunger")) == TYPE_INT
		and int(citizen.get("hunger")) == safe_hunger
		and citizen.has("hunger_decay_remainder")
		and typeof(citizen.get("hunger_decay_remainder")) == TYPE_INT
		and int(citizen.get("hunger_decay_remainder")) == safe_remainder
	):
		return true

	citizen["hunger"] = safe_hunger
	citizen["hunger_decay_remainder"] = safe_remainder
	registry_state.citizens[citizen_index] = citizen
	_mark_city_citizens_changed(city_state)
	return true


static func get_city_citizen_happiness(citizen_id: int) -> int:
	return _get_city_citizen_happiness(CityCitizenUnboundCompatibility.get_city_state(), citizen_id)


static func get_city_citizen_happiness_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return _get_city_citizen_happiness(city_state, citizen_id)


static func _get_city_citizen_happiness(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	var citizen := _get_city_citizen_by_id(city_state, citizen_id)

	if citizen.is_empty():
		return 0

	return clampi(
		int(citizen.get("happiness", CityCitizens.DEFAULT_CITIZEN_HAPPINESS)),
		0,
		100
	)


static func set_city_citizen_happiness(
	citizen_id: int,
	happiness: int
) -> bool:
	return _set_city_citizen_happiness(CityCitizenUnboundCompatibility.get_city_state(), citizen_id, happiness)


static func set_city_citizen_happiness_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	happiness: int
) -> bool:
	return _set_city_citizen_happiness(city_state, citizen_id, happiness)


static func _set_city_citizen_happiness(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	happiness: int
) -> bool:
	var citizen_index := _get_city_citizen_index_by_id(
		city_state,
		citizen_id
	)

	if citizen_index < 0:
		return false

	var registry_state := _get_registry_state(city_state)
	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var safe_happiness := clampi(happiness, 0, 100)

	if (
		citizen.has("happiness")
		and typeof(citizen.get("happiness")) == TYPE_INT
		and int(citizen.get("happiness")) == safe_happiness
	):
		return true

	citizen["happiness"] = safe_happiness
	registry_state.citizens[citizen_index] = citizen
	_mark_city_citizens_changed(city_state)
	return true


static func _city_citizen_can_directly_withdraw_food(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	city_object: Dictionary,
	resource: String
) -> bool:
	var withdrawal_purpose := (
		CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
	)
	var citizen := _get_city_citizen_by_id(city_state, citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or city_object.is_empty()
		or not CityResourceContainerSystem.can_city_object_store_resource(
			city_object,
			resource
		)
		or not CityResourceContainerSystem.city_object_allows_direct_resource_withdrawal(
			city_object,
			withdrawal_purpose
		)
	):
		return false

	if (
		withdrawal_purpose
		== CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
		and CityResourceCatalog.get_city_food_hunger_restore(resource) <= 0
	):
		return false

	match CityResourceContainerSystem.get_city_object_container_type(city_object):
		CityObjectCatalog.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return (
				int(citizen.get("home_object_id", -1))
				== int(city_object.get("id", -1))
				and (
					CityAssignmentSystem.get_city_object_resident_ids(city_object)
					if city_state == null
					else CityAssignmentSystem.get_city_object_resident_ids_for_city_state(
						city_state,
						city_object
					)
				).has(citizen_id)
			)

		CityObjectCatalog.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return (
				CityResourceContainerSystem
				.city_object_container_is_publicly_usable(city_object)
			)

		CityObjectCatalog.CONTAINER_TYPE_WORKPLACE_STORAGE:
			return (
				withdrawal_purpose
				== CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
				and CityObjectCatalog.city_object_is_workplace(city_object)
				and CityObjectCatalog.get_city_object_output_resources(city_object).has(
					resource
				)
			)

	return false


static func _get_city_citizen_direct_food_withdrawal_target_tiles(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	city_object: Dictionary
) -> Array:
	var target_tiles: Array = []
	var citizen := _get_city_citizen_by_id(city_state, citizen_id)
	var withdrawal_purpose := (
		CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
	)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or city_object.is_empty()
		or not CityResourceContainerSystem.city_object_allows_direct_resource_withdrawal(
			city_object,
			withdrawal_purpose
		)
	):
		return target_tiles

	match CityResourceContainerSystem.get_city_object_container_type(city_object):
		CityObjectCatalog.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			if (
				int(citizen.get("home_object_id", -1))
				== int(city_object.get("id", -1))
				and (
					CityAssignmentSystem.get_city_object_resident_ids(city_object)
					if city_state == null
					else CityAssignmentSystem.get_city_object_resident_ids_for_city_state(
						city_state,
						city_object
					)
				).has(citizen_id)
			):
				return CityObjectSystem.get_city_object_footprint_tiles(
					city_object
				)

		CityObjectCatalog.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			if (
				CityResourceContainerSystem
				.city_object_container_is_publicly_usable(city_object)
			):
				return (
					CityNavigationSystem.get_city_object_access_tiles(
						CityCitizenUnboundCompatibility.get_city_state().city_world,
						city_object
					)
					if city_state == null
					else CityNavigationSystem.get_city_object_access_tiles_for_city_state(
						city_state,
						city_state.city_world,
						city_object
					)
				)

		CityObjectCatalog.CONTAINER_TYPE_WORKPLACE_STORAGE:
			if (
				withdrawal_purpose
				== CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
				and CityObjectCatalog.city_object_is_workplace(city_object)
			):
				return (
					CityNavigationSystem.get_city_object_access_tiles(
						CityCitizenUnboundCompatibility.get_city_state().city_world,
						city_object
					)
					if city_state == null
					else CityNavigationSystem.get_city_object_access_tiles_for_city_state(
						city_state,
						city_state.city_world,
						city_object
					)
				)

	return target_tiles


static func city_citizen_can_withdraw_food_from_endpoint(
	citizen_id: int,
	endpoint: Dictionary,
	resource: String
) -> bool:
	return _city_citizen_can_withdraw_food_from_endpoint(
		CityCitizenUnboundCompatibility.get_city_state(),
		citizen_id,
		endpoint,
		resource
	)


static func city_citizen_can_withdraw_food_from_endpoint_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	endpoint: Dictionary,
	resource: String
) -> bool:
	return _city_citizen_can_withdraw_food_from_endpoint(
		city_state,
		citizen_id,
		endpoint,
		resource
	)


static func _city_citizen_can_withdraw_food_from_endpoint(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	endpoint: Dictionary,
	resource: String
) -> bool:
	if CityResourceCatalog.get_city_food_hunger_restore(resource) <= 0:
		return false

	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	match endpoint_kind:
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			return _city_citizen_can_directly_withdraw_food(
				city_state,
				citizen_id,
				(
					CityObjectSystem.get_city_object_by_id(endpoint_id)
					if city_state == null
					else CityObjectSystem.get_city_object_by_id_for_city_state(
						city_state,
						endpoint_id
					)
				),
				resource
			)

		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			var citizen := _get_city_citizen_by_id(
				city_state,
				citizen_id
			)
			var ground_pile := (
				CityLogisticsSystem.get_city_ground_pile_by_id(endpoint_id)
				if city_state == null
				else CityLogisticsSystem.get_city_ground_pile_by_id_for_city_state(
					city_state,
					endpoint_id
				)
			)
			return (
				not citizen.is_empty()
				and bool(citizen.get("alive", false))
				and not ground_pile.is_empty()
				and not CityLogisticsSystem.city_ground_pile_is_construction_reserved(
					ground_pile
				)
				and CityLogisticsSystem.get_city_ground_pile_resource_amount(
					ground_pile,
					resource
				) > 0
			)

	return false


static func get_city_citizen_food_endpoint_target_tiles(
	citizen_id: int,
	endpoint: Dictionary
) -> Array:
	return _get_city_citizen_food_endpoint_target_tiles(
		CityCitizenUnboundCompatibility.get_city_state(),
		citizen_id,
		endpoint
	)


static func get_city_citizen_food_endpoint_target_tiles_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	endpoint: Dictionary
) -> Array:
	return _get_city_citizen_food_endpoint_target_tiles(
		city_state,
		citizen_id,
		endpoint
	)


static func _get_city_citizen_food_endpoint_target_tiles(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	endpoint: Dictionary
) -> Array:
	match str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	):
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			return _get_city_citizen_direct_food_withdrawal_target_tiles(
				city_state,
				citizen_id,
				(
					CityObjectSystem.get_city_object_by_id(
						int(endpoint.get("id", -1))
					)
					if city_state == null
					else CityObjectSystem.get_city_object_by_id_for_city_state(
						city_state,
						int(endpoint.get("id", -1))
					)
				)
			)

		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			var ground_pile := (
				CityLogisticsSystem.get_city_ground_pile_by_id(
					int(endpoint.get("id", -1))
				)
				if city_state == null
				else CityLogisticsSystem.get_city_ground_pile_by_id_for_city_state(
					city_state,
					int(endpoint.get("id", -1))
				)
			)
			var raw_tile = ground_pile.get(
				"tile_position",
				CityCitizens.INVALID_CITY_TILE_POSITION
			)

			if (
				not CityLogisticsSystem.city_ground_pile_is_construction_reserved(
					ground_pile
				)
				and raw_tile is Vector2i
				and (
					CityNavigationSystem.is_city_tile_walkable_for_citizen(
						CityCitizenUnboundCompatibility.get_city_state().city_world,
						raw_tile,
						citizen_id
					)
					if city_state == null
					else CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
						city_state,
						city_state.city_world,
						raw_tile,
						citizen_id
					)
				)
			):
				return [raw_tile]

	return []


static func get_city_food_endpoint_unreserved_amount(
	citizen_id: int,
	endpoint: Dictionary,
	resource: String,
	excluding_citizen_id: int = -1
) -> int:
	return _get_city_food_endpoint_unreserved_amount(
		CityCitizenUnboundCompatibility.get_city_state(),
		citizen_id,
		endpoint,
		resource,
		excluding_citizen_id
	)


static func get_city_food_endpoint_unreserved_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	endpoint: Dictionary,
	resource: String,
	excluding_citizen_id: int = -1
) -> int:
	return _get_city_food_endpoint_unreserved_amount(
		city_state,
		citizen_id,
		endpoint,
		resource,
		excluding_citizen_id
	)


static func _get_city_food_endpoint_unreserved_amount(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	endpoint: Dictionary,
	resource: String,
	excluding_citizen_id: int
) -> int:
	if not _city_citizen_can_withdraw_food_from_endpoint(
		city_state,
		citizen_id,
		endpoint,
		resource
	):
		return 0

	return (
		CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
			endpoint,
			resource,
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID,
			excluding_citizen_id
		)
		if city_state == null
		else CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount_for_city_state(
			city_state,
			endpoint,
			resource,
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID,
			excluding_citizen_id
		)
	)


static func transfer_city_food_endpoint_to_citizen_inventory(
	citizen_id: int,
	endpoint: Dictionary,
	resource: String,
	requested_amount: int
) -> int:
	return _transfer_city_food_endpoint_to_citizen_inventory(
		CityCitizenUnboundCompatibility.get_city_state(),
		citizen_id,
		endpoint,
		resource,
		requested_amount
	)


static func transfer_city_food_endpoint_to_citizen_inventory_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	endpoint: Dictionary,
	resource: String,
	requested_amount: int
) -> int:
	return _transfer_city_food_endpoint_to_citizen_inventory(
		city_state,
		citizen_id,
		endpoint,
		resource,
		requested_amount
	)


static func _transfer_city_food_endpoint_to_citizen_inventory(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	endpoint: Dictionary,
	resource: String,
	requested_amount: int
) -> int:
	if (
		requested_amount <= 0
		or not _city_citizen_can_withdraw_food_from_endpoint(
			city_state,
			citizen_id,
			endpoint,
			resource
		)
	):
		return 0

	var citizen := _get_city_citizen_by_id(city_state, citizen_id)
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_citizen_tile is Vector2i
		or not _get_city_citizen_food_endpoint_target_tiles(
			city_state,
			citizen_id,
			endpoint
		).has(raw_citizen_tile)
	):
		return 0

	var transfer_amount := mini(
		requested_amount,
		mini(
			(
				CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
					endpoint,
					resource,
					CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID,
					citizen_id
				)
				if city_state == null
				else CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount_for_city_state(
					city_state,
					endpoint,
					resource,
					CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID,
					citizen_id
				)
			),
			(
				CityCitizenInventorySystem.get_city_citizen_inventory_free_space(
					citizen_id
				)
				if city_state == null
				else CityCitizenInventorySystem.get_city_citizen_inventory_free_space_for_city_state(
					city_state,
					citizen_id
				)
			)
		)
	)

	if transfer_amount <= 0:
		return 0

	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))
	var removed_amount := 0
	var original_ground_tile := CityCitizens.INVALID_CITY_TILE_POSITION

	if endpoint_kind == CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
		var original_ground_pile := (
			CityLogisticsSystem.get_city_ground_pile_by_id(endpoint_id)
			if city_state == null
			else CityLogisticsSystem.get_city_ground_pile_by_id_for_city_state(
				city_state,
				endpoint_id
			)
		)
		var raw_original_ground_tile = original_ground_pile.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if raw_original_ground_tile is Vector2i:
			original_ground_tile = raw_original_ground_tile

	match endpoint_kind:
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			removed_amount = (
				CityResourceContainerSystem.remove_resource_from_city_object_storage(
					endpoint_id,
					resource,
					transfer_amount
				)
				if city_state == null
				else CityResourceContainerSystem.remove_resource_from_city_object_storage_for_city_state(
					city_state,
					endpoint_id,
					resource,
					transfer_amount
				)
			)

		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			removed_amount = (
				CityLogisticsSystem.remove_resource_from_city_ground_pile(
					endpoint_id,
					resource,
					transfer_amount
				)
				if city_state == null
				else CityLogisticsSystem.remove_resource_from_city_ground_pile_for_city_state(
					city_state,
					endpoint_id,
					resource,
					transfer_amount
				)
			)

	if removed_amount <= 0:
		return 0

	var accepted_amount := (
		CityCitizenInventorySystem.add_resource_to_city_citizen_inventory(
			citizen_id,
			resource,
			removed_amount
		)
		if city_state == null
		else CityCitizenInventorySystem.add_resource_to_city_citizen_inventory_for_city_state(
			city_state,
			citizen_id,
			resource,
			removed_amount
		)
	)

	if accepted_amount == removed_amount:
		return accepted_amount

	if accepted_amount > 0:
		if city_state == null:
			CityCitizenInventorySystem.remove_resource_from_city_citizen_inventory(
				citizen_id,
				resource,
				accepted_amount
			)
		else:
			CityCitizenInventorySystem.remove_resource_from_city_citizen_inventory_for_city_state(
				city_state,
				citizen_id,
				resource,
				accepted_amount
			)

	var rollback_amount := 0

	match endpoint_kind:
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			rollback_amount = (
				CityResourceContainerSystem.add_resource_to_city_object_storage(
					endpoint_id,
					resource,
					removed_amount
				)
				if city_state == null
				else CityResourceContainerSystem.add_resource_to_city_object_storage_for_city_state(
					city_state,
					endpoint_id,
					resource,
					removed_amount
				)
			)

		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			if original_ground_tile != CityCitizens.INVALID_CITY_TILE_POSITION:
				var rollback_result := (
					CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
						"tile_position": original_ground_tile,
						"resource": resource,
						"amount_delta": removed_amount,
					})
					if city_state == null
					else CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(
						city_state,
						{
							"tile_position": original_ground_tile,
							"resource": resource,
							"amount_delta": removed_amount,
						}
					)
				)
				rollback_amount = int(rollback_result.get("added_amount", 0))

	if rollback_amount != removed_amount:
		push_error(
			"Atomic food-endpoint transfer rollback failed for "
			+ resource
			+ "."
		)

	return 0


static func run_tick(
	_tick_index: int,
	minutes_advanced: int
) -> void:
	_run_tick(CityCitizenUnboundCompatibility.get_city_state(), _tick_index, minutes_advanced)


static func run_tick_for_city_state(
	city_state: CitySettlementSimulationState,
	_tick_index: int,
	minutes_advanced: int
) -> void:
	_run_tick(city_state, _tick_index, minutes_advanced)


static func _run_tick(
	city_state: CitySettlementSimulationState,
	_tick_index: int,
	minutes_advanced: int
) -> void:
	var resolved_city_state = (
		CityCitizenUnboundCompatibility.get_city_state()
		if city_state == null
		else city_state
	)
	var city_world = (
		resolved_city_state.city_world
		if resolved_city_state != null
		else null
	)
	var registry_state := _get_registry_state(city_state)
	if (
		minutes_advanced <= 0
		or city_world == null
		or resolved_city_state == null
		or not resolved_city_state.is_city_founded()
		or registry_state.citizens.is_empty()
	):
		return

	if city_state == null:
		ensure_city_citizen_need_state()
	else:
		ensure_city_citizen_need_state_for_city_state(city_state)
	var citizen_ids: Array[int] = []

	for raw_citizen in registry_state.citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if citizen_id > 0 and bool(citizen.get("alive", false)):
			citizen_ids.append(citizen_id)

	for citizen_id in citizen_ids:
		_advance_citizen_hunger(city_state, citizen_id, minutes_advanced)
		_take_personal_food_at_current_legal_source(city_state, citizen_id)
		_eat_personal_food_if_hungry(city_state, citizen_id)


static func get_single_food_allocation_nutrition_cap() -> int:
	var allocation_nutrition_cap := 0

	for resource in CityResourceCatalog.get_city_food_resource_types():
		var hunger_restore := CityResourceCatalog.get_city_food_hunger_restore(resource)

		if hunger_restore <= 0:
			continue

		if allocation_nutrition_cap <= 0:
			allocation_nutrition_cap = hunger_restore
		else:
			allocation_nutrition_cap = mini(
				allocation_nutrition_cap,
				hunger_restore
			)

	return allocation_nutrition_cap


static func get_citizen_food_need_nutrition(citizen_id: int) -> int:
	return _get_citizen_food_need_nutrition(CityCitizenUnboundCompatibility.get_city_state(), citizen_id)


static func get_citizen_food_need_nutrition_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return _get_citizen_food_need_nutrition(city_state, citizen_id)


static func _get_citizen_food_need_nutrition(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	var citizen := _get_city_citizen_by_id(city_state, citizen_id)

	if citizen.is_empty() or not bool(citizen.get("alive", false)):
		return 0

	var personal_food_nutrition := (
		CityResourceContainerSystem.get_food_nutrition_in_resource_container(
			(
				CityCitizenInventorySystem.get_city_citizen_inventory(citizen_id)
				if city_state == null
				else CityCitizenInventorySystem.get_city_citizen_inventory_for_city_state(
					city_state,
					citizen_id
				)
			)
		)
	)
	return maxi(
		CityCitizens.CITIZEN_EAT_TARGET_HUNGER
		- _get_city_citizen_hunger(city_state, citizen_id)
		- personal_food_nutrition,
		0
	)


static func get_citizen_next_food_allocation_nutrition(
	citizen_id: int
) -> int:
	return _get_citizen_next_food_allocation_nutrition(CityCitizenUnboundCompatibility.get_city_state(), citizen_id)


static func get_citizen_next_food_allocation_nutrition_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	return _get_citizen_next_food_allocation_nutrition(
		city_state,
		citizen_id
	)


static func _get_citizen_next_food_allocation_nutrition(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	var unmet_nutrition := _get_citizen_food_need_nutrition(
		city_state,
		citizen_id
	)
	var allocation_nutrition_cap := (
		get_single_food_allocation_nutrition_cap()
	)

	if allocation_nutrition_cap <= 0:
		return 0

	return mini(unmet_nutrition, allocation_nutrition_cap)


static func citizen_should_seek_food(citizen_id: int) -> bool:
	return _citizen_should_seek_food(CityCitizenUnboundCompatibility.get_city_state(), citizen_id)


static func citizen_should_seek_food_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	return _citizen_should_seek_food(city_state, citizen_id)


static func _citizen_should_seek_food(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	var hunger := _get_city_citizen_hunger(city_state, citizen_id)
	var available_food_capacity := (
		(
			CityCitizenInventorySystem.get_city_citizen_personal_inventory_free_space(citizen_id)
			if city_state == null
			else CityCitizenInventorySystem.get_city_citizen_personal_inventory_free_space_for_city_state(
				city_state,
				citizen_id
			)
		)
		if hunger <= CityCitizens.CITIZEN_CRITICAL_FOOD_SEEK_TRIGGER_HUNGER
		else (
			CityCitizenInventorySystem.get_city_citizen_inventory_free_space(citizen_id)
			if city_state == null
			else CityCitizenInventorySystem.get_city_citizen_inventory_free_space_for_city_state(
				city_state,
				citizen_id
			)
		)
	)

	return (
		hunger <= CityCitizens.CITIZEN_FOOD_SEEK_TRIGGER_HUNGER
		and _get_citizen_food_need_nutrition(city_state, citizen_id) > 0
		and available_food_capacity > 0
	)


static func citizen_has_critical_food_need(citizen_id: int) -> bool:
	return _citizen_has_critical_food_need(CityCitizenUnboundCompatibility.get_city_state(), citizen_id)


static func citizen_has_critical_food_need_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	return _citizen_has_critical_food_need(city_state, citizen_id)


static func _citizen_has_critical_food_need(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	return (
		_get_city_citizen_hunger(city_state, citizen_id)
		<= CityCitizens.CITIZEN_CRITICAL_FOOD_SEEK_TRIGGER_HUNGER
		and _get_citizen_food_need_nutrition(city_state, citizen_id) > 0
	)


static func eat_personal_food_if_hungry(citizen_id: int) -> void:
	_eat_personal_food_if_hungry(CityCitizenUnboundCompatibility.get_city_state(), citizen_id)


static func eat_personal_food_if_hungry_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> void:
	_eat_personal_food_if_hungry(city_state, citizen_id)


static func _advance_citizen_hunger(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	minutes_advanced: int
) -> void:
	var citizen := _get_city_citizen_by_id(city_state, citizen_id)

	if citizen.is_empty():
		return

	var old_hunger := clampi(
		int(citizen.get("hunger", CityCitizens.DEFAULT_CITIZEN_HUNGER)),
		0,
		CityCitizens.MAX_CITIZEN_HUNGER
	)
	var old_remainder := clampi(
		int(citizen.get("hunger_decay_remainder", 0)),
		0,
		CityCitizens.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES - 1
	)
	var decay_numerator := (
		old_remainder
		+ minutes_advanced * CityCitizens.CITIZEN_HUNGER_LOSS_PER_DAY
	)
	var hunger_lost := floori(
		float(decay_numerator)
		/ float(CityCitizens.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES)
	)
	var next_remainder := decay_numerator % (
		CityCitizens.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES
	)

	_set_city_citizen_hunger_state(
		city_state,
		citizen_id,
		maxi(old_hunger - hunger_lost, 0),
		next_remainder
	)


static func _take_personal_food_at_current_legal_source(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> void:
	var citizen := _get_city_citizen_by_id(city_state, citizen_id)

	if (
		citizen.is_empty()
		or _get_city_citizen_hunger(city_state, citizen_id)
		> CityCitizens.CITIZEN_FOOD_CARRY_TRIGGER_HUNGER
		or (
			CityCitizenInventorySystem.get_city_citizen_inventory_free_space(citizen_id)
			if city_state == null
			else CityCitizenInventorySystem.get_city_citizen_inventory_free_space_for_city_state(
				city_state,
				citizen_id
			)
		) <= 0
		or _get_citizen_next_food_allocation_nutrition(city_state, citizen_id) <= 0
	):
		return

	var source_endpoints := _get_legal_food_source_endpoints_at_citizen(
		city_state,
		citizen
	)

	for raw_source_endpoint in source_endpoints:
		if not raw_source_endpoint is Dictionary:
			continue

		var source_endpoint: Dictionary = raw_source_endpoint

		for resource in CityResourceCatalog.get_city_food_resource_types():
			if CityResourceCatalog.get_city_food_hunger_restore(resource) <= 0:
				continue

			var transferred_units := (
				_transfer_city_food_endpoint_to_citizen_inventory(
					city_state,
					citizen_id,
					source_endpoint,
					resource,
					1
				)
			)

			# One successful transfer is the complete immediate allocation. The
			# eating step runs next, then every hungry citizen competes again using
			# current hunger and the source reservations already owned by others.
			if transferred_units > 0:
				return


static func _get_legal_food_source_endpoints_at_citizen(
	city_state: CitySettlementSimulationState,
	citizen: Dictionary
) -> Array:
	var sources: Array = []
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_citizen_tile is Vector2i:
		return sources

	var citizen_tile: Vector2i = raw_citizen_tile
	var citizen_id := int(citizen.get("id", -1))
	var home_id := int(citizen.get("home_object_id", -1))
	var home := (
		CityObjectSystem.get_city_object_by_id(home_id)
		if city_state == null
		else CityObjectSystem.get_city_object_by_id_for_city_state(
			city_state,
			home_id
		)
	)

	# A resident's own home is always their first legal food source. Other homes
	# never enter this list, even if the citizen is standing beside one.
	if (
		_city_object_is_household_home(home)
		and CityObjectSystem.get_city_object_footprint_tiles(home).has(citizen_tile)
	):
		sources.append(CityLogisticsSystem.make_city_citizen_haul_endpoint(home_id))

	# Deliberate travel is owned by the decision system. At the current tile,
	# however, every legal survival source participates in the same endpoint
	# policy, including workplace output and ordinary food piles.
	for storage_tier in (
		CityResourceContainerSystem.get_public_city_storage_tiers()
		+ [CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_NONE]
	):
		var city_objects := (
			CityObjectSystem.get_city_objects()
			if city_state == null
			else CityObjectSystem.get_city_objects_for_city_state(city_state)
		)
		for raw_city_object in city_objects:
			if not raw_city_object is Dictionary:
				continue

			var city_object: Dictionary = raw_city_object

			if (
				(
					storage_tier != CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_NONE
					and CityResourceContainerSystem.get_city_object_public_storage_tier(city_object)
					!= storage_tier
				)
				or (
					storage_tier == CityObjectCatalog.PUBLIC_CITY_STORAGE_TIER_NONE
					and CityResourceContainerSystem.get_city_object_container_type(city_object)
					!= CityObjectCatalog.CONTAINER_TYPE_WORKPLACE_STORAGE
				)
				or not CityResourceContainerSystem.city_object_allows_direct_resource_withdrawal(
					city_object,
					CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
				)
			):
				continue

			var interaction_tiles := (
				_get_city_citizen_direct_food_withdrawal_target_tiles(
					city_state,
					citizen_id,
					city_object
				)
			)

			if interaction_tiles.has(citizen_tile):
				sources.append(
					CityLogisticsSystem.make_city_citizen_haul_endpoint(
						int(city_object.get("id", -1))
					)
				)

	var ground_pile_snapshot := (
		CityLogisticsSystem.get_city_ground_pile_snapshot()
		if city_state == null
		else CityLogisticsSystem.get_city_ground_pile_snapshot_for_city_state(
			city_state
		)
	)
	for raw_pile in ground_pile_snapshot:
		if not raw_pile is Dictionary:
			continue

		var pile: Dictionary = raw_pile
		var endpoint := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
			int(pile.get("id", -1))
		)

		if (
			pile.get("tile_position", CityCitizens.INVALID_CITY_TILE_POSITION)
			== citizen_tile
			and not CityLogisticsSystem.city_ground_pile_is_construction_reserved(pile)
		):
			sources.append(endpoint)

	return sources


static func _city_object_is_household_home(city_object: Dictionary) -> bool:
	return (
		not city_object.is_empty()
		and CityResourceContainerSystem.get_city_object_container_type(city_object)
		== CityObjectCatalog.CONTAINER_TYPE_PRIVATE_HOME_STORAGE
		and CityObjectCatalog.get_city_object_resident_capacity(city_object) > 0
	)


static func _eat_personal_food_if_hungry(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> void:
	var hunger := _get_city_citizen_hunger(city_state, citizen_id)

	for resource in CityResourceCatalog.get_city_food_resource_types():
		var hunger_restore := CityResourceCatalog.get_city_food_hunger_restore(resource)

		if hunger_restore <= 0:
			continue

		while (
			CityCitizenInventorySystem.get_city_citizen_inventory_resource_amount(
				citizen_id,
				resource
			)
			if city_state == null
			else CityCitizenInventorySystem.get_city_citizen_inventory_resource_amount_for_city_state(
				city_state,
				citizen_id,
				resource
			)
		) > 0:
			# Food remains a whole physical item. Citizens only consume it when
			# every point of nutrition fits, so no restoration is discarded by
			# clamping. A citizen at 90 therefore keeps a 20-point item until 80.
			if (
				hunger + hunger_restore
				> CityCitizens.CITIZEN_EAT_TARGET_HUNGER
			):
				break

			var removed_amount := (
				CityCitizenInventorySystem.remove_resource_from_city_citizen_inventory(
					citizen_id,
					resource,
					1
				)
				if city_state == null
				else CityCitizenInventorySystem.remove_resource_from_city_citizen_inventory_for_city_state(
					city_state,
					citizen_id,
					resource,
					1
				)
			)

			if removed_amount != 1:
				break

			var citizen := _get_city_citizen_by_id(city_state, citizen_id)
			var hunger_remainder := int(
				citizen.get("hunger_decay_remainder", 0)
			)
			var next_hunger := hunger + hunger_restore

			if not _set_city_citizen_hunger_state(
				city_state,
				citizen_id,
				next_hunger,
				hunger_remainder
			):
				if city_state == null:
					CityCitizenInventorySystem.add_resource_to_city_citizen_inventory(
						citizen_id,
						resource,
						1
					)
				else:
					CityCitizenInventorySystem.add_resource_to_city_citizen_inventory_for_city_state(
						city_state,
						citizen_id,
						resource,
						1
					)
				return

			hunger = next_hunger

			if hunger >= CityCitizens.CITIZEN_EAT_TARGET_HUNGER:
				return
