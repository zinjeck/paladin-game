# File responsibility: Validate city foundations, occupancy, assignments, inventories, containers, and workplace state.
extends RefCounted

#region Foundation Occupancy and Containers
static func _validate_city_foundation_state(
	errors: Array[String],
	warnings: Array[String],
	object_lookup: Dictionary
) -> void:
	var city_center_count := 0

	for object_id in object_lookup.keys():
		var object_index := int(
			object_lookup[object_id]
		)

		var city_object: Dictionary = (
			CityObjectSystem.get_city_objects()[object_index]
		)

		if (
			str(city_object.get("type", ""))
			== CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		):
			city_center_count += 1

	if not WorldData.player_city_founded:
		if not CityCitizenRegistrySystem.get_current_state().citizens.is_empty():
			errors.append(
				"Citizens exist before the player city is founded."
			)

		if city_center_count > 0:
			errors.append(
				"A City Keep exists while player_city_founded is false."
			)

		return

	if city_center_count != 1:
		errors.append(
			"Founded city must have exactly one City Keep, but "
				+ str(city_center_count)
				+ " exist."
		)

	if CityCitizenRegistrySystem.get_current_state().citizens.is_empty():
		warnings.append(
			"The city is founded but currently has no citizens."
		)


static func _validate_city_occupancy(
	errors: Array[String],
	object_lookup: Dictionary
) -> void:
	var expected_occupancy: Dictionary = {}
	var occupied_tiles := CityObjectSystem.get_city_occupied_tiles_snapshot()

	for object_id in object_lookup.keys():
		var object_index := int(
			object_lookup[object_id]
		)

		var city_object: Dictionary = (
			CityObjectSystem.get_city_objects()[object_index]
		)

		var footprint_tiles := (
			CityObjectSystem.get_city_object_footprint_tiles(
				city_object
			)
		)

		if footprint_tiles.is_empty():
			errors.append(
				"City object "
					+ str(object_id)
					+ " has an empty footprint."
			)

			continue

		for raw_tile_position in footprint_tiles:
			if not raw_tile_position is Vector2i:
				errors.append(
					"City object "
						+ str(object_id)
						+ " has a non-Vector2i footprint entry."
				)

				continue

			var tile_position: Vector2i = (
				raw_tile_position
			)

			if expected_occupancy.has(tile_position):
				errors.append(
					"Tile "
						+ str(tile_position)
						+ " belongs to footprints of both object "
						+ str(expected_occupancy[tile_position])
						+ " and object "
						+ str(object_id)
						+ "."
				)
			else:
				expected_occupancy[tile_position] = object_id

			if not occupied_tiles.has(tile_position):
				errors.append(
					"Object "
						+ str(object_id)
						+ " footprint tile "
						+ str(tile_position)
						+ " is missing from city_occupied_tiles."
				)

				continue

			var occupied_object_id := int(
				occupied_tiles[tile_position]
			)

			if occupied_object_id != int(object_id):
				errors.append(
					"Tile "
						+ str(tile_position)
						+ " belongs to object "
						+ str(object_id)
						+ " by footprint, but occupancy points to "
						+ str(occupied_object_id)
						+ "."
				)

	for raw_tile_position in occupied_tiles.keys():
		if not raw_tile_position is Vector2i:
			errors.append(
				"city_occupied_tiles contains a non-Vector2i key."
			)

			continue

		var tile_position: Vector2i = raw_tile_position
		var object_id := int(occupied_tiles[tile_position])

		if not object_lookup.has(object_id):
			errors.append(
				"Occupied tile "
					+ str(tile_position)
					+ " points to missing object ID "
					+ str(object_id)
					+ "."
			)

		if not expected_occupancy.has(tile_position):
			errors.append(
				"Occupied tile "
					+ str(tile_position)
					+ " is not present in its object's footprint."
			)


static func _validate_city_containers(
	errors: Array[String],
	object_lookup: Dictionary
) -> int:
	var checked_container_count := 0

	for object_id in object_lookup.keys():
		var object_index := int(
			object_lookup[object_id]
		)

		var city_object: Dictionary = (
			CityObjectSystem.get_city_objects()[object_index]
		)

		var allowed_resources := (
			CityResourceContainerSystem.get_city_object_storage_resources(
				city_object
			)
		)

		var raw_stored_resources = city_object.get(
			"stored_resources",
			{}
		)

		if allowed_resources.is_empty():
			if (
				raw_stored_resources is Dictionary
				and not raw_stored_resources.is_empty()
			):
				errors.append(
					"Object "
						+ str(object_id)
						+ " stores resources despite having no allowed storage resources."
				)
			elif not raw_stored_resources is Dictionary:
				errors.append(
					"Object "
						+ str(object_id)
						+ " has non-Dictionary stored_resources."
				)

			continue

		checked_container_count += 1

		if not raw_stored_resources is Dictionary:
			errors.append(
				"Container object "
					+ str(object_id)
					+ " has non-Dictionary stored_resources."
			)

			continue

		var stored_resources: Dictionary = (
			raw_stored_resources
		)

		for resource in allowed_resources:
			var capacity := (
				CityResourceContainerSystem
				.get_city_object_storage_capacity_for_resource(
					city_object,
					resource
				)
			)

			if capacity <= 0:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " allows "
						+ resource
						+ " but has capacity "
						+ str(capacity)
						+ "."
				)

		for raw_resource in stored_resources.keys():
			if typeof(raw_resource) != TYPE_STRING:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " has a non-String storage resource key."
				)

				continue

			var resource: String = raw_resource

			if not allowed_resources.has(resource):
				errors.append(
					"Container object "
						+ str(object_id)
						+ " stores unsupported resource '"
						+ resource
						+ "'."
				)

				continue

			var raw_amount = stored_resources[raw_resource]

			if typeof(raw_amount) != TYPE_INT:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " stores non-integer amount for "
						+ resource
						+ "."
				)

				continue

			var amount: int = raw_amount

			if amount <= 0:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " has non-positive "
						+ resource
						+ " amount "
						+ str(amount)
						+ "; empty resources must be omitted."
				)

			var capacity := (
				CityResourceContainerSystem
				.get_city_object_storage_capacity_for_resource(
					city_object,
					resource
				)
			)

			if capacity >= 0 and amount > capacity:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " stores "
						+ str(amount)
						+ " "
						+ resource
						+ " but capacity is "
						+ str(capacity)
						+ "."
				)
		var total_stored_amount := (
			CityResourceContainerSystem.get_city_object_storage_used_capacity(
				city_object
			)
		)
		var total_capacity := (
			CityResourceContainerSystem.get_city_object_storage_capacity(
				city_object
			)
		)

		if total_stored_amount > total_capacity:
			errors.append(
				"Container object "
					+ str(object_id)
					+ " stores "
					+ str(total_stored_amount)
					+ " total units but capacity is "
					+ str(total_capacity)
					+ "."
			)
	return checked_container_count




#endregion

#region Assignments and Inventories
static func _validate_city_assignments(
	errors: Array[String],
	object_lookup: Dictionary,
	citizen_lookup: Dictionary
) -> void:
	var resident_membership: Dictionary = {}
	var worker_membership: Dictionary = {}

	for object_id in object_lookup.keys():
		var object_index := int(
			object_lookup[object_id]
		)

		var city_object: Dictionary = (
			CityObjectSystem.get_city_objects()[object_index]
		)

		var resident_capacity := (
			CityObjectCatalog.get_city_object_resident_capacity(
				city_object
			)
		)

		if resident_capacity > 0:
			if not city_object.has("resident_ids"):
				errors.append(
					"Housing object "
						+ str(object_id)
						+ " is missing resident_ids."
				)
			else:
				_validate_resident_list({
					"errors": errors,
					"city_object": city_object,
					"object_id": int(object_id),
					"resident_capacity": resident_capacity,
					"citizen_lookup": citizen_lookup,
					"resident_membership": resident_membership,
				})
		elif (
			city_object.has("resident_ids")
			and city_object.get("resident_ids", []) is Array
			and not city_object.get(
				"resident_ids",
				[]
			).is_empty()
		):
			errors.append(
				"Non-housing object "
					+ str(object_id)
					+ " contains residents."
			)

		if CityObjectCatalog.city_object_is_workplace(
			city_object
		):
			var worker_capacity := (
				CityObjectCatalog.get_city_object_worker_capacity(
					city_object
				)
			)

			if not city_object.has("assigned_worker_ids"):
				errors.append(
					"Workplace "
						+ str(object_id)
						+ " is missing assigned_worker_ids."
				)
			else:
				_validate_worker_list({
					"errors": errors,
					"city_object": city_object,
					"object_id": int(object_id),
					"worker_capacity": worker_capacity,
					"citizen_lookup": citizen_lookup,
					"worker_membership": worker_membership,
				})
		elif (
			city_object.has("assigned_worker_ids")
			and city_object.get(
				"assigned_worker_ids",
				[]
			) is Array
			and not city_object.get(
				"assigned_worker_ids",
				[]
			).is_empty()
		):
			errors.append(
				"Non-workplace object "
					+ str(object_id)
					+ " contains assigned workers."
			)

	for citizen_id in citizen_lookup.keys():
		var citizen_index := int(
			citizen_lookup[citizen_id]
		)

		var citizen: Dictionary = (
			CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]
		)

		var is_alive := bool(
			citizen.get("alive", true)
		)

		var home_object_id := int(
			citizen.get("home_object_id", -1)
		)

		var job_object_id := int(
			citizen.get("job_object_id", -1)
		)

		if not is_alive:
			if home_object_id >= 0:
				errors.append(
					"Dead citizen "
						+ str(citizen_id)
						+ " remains assigned to home "
						+ str(home_object_id)
						+ "."
				)

			if job_object_id >= 0:
				errors.append(
					"Dead citizen "
						+ str(citizen_id)
						+ " remains assigned to workplace "
						+ str(job_object_id)
						+ "."
				)

		if home_object_id >= 0:
			if not object_lookup.has(home_object_id):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to missing home object "
						+ str(home_object_id)
						+ "."
				)
			else:
				var home_index := int(
					object_lookup[home_object_id]
				)

				var home_object: Dictionary = (
					CityObjectSystem.get_city_objects()[home_index]
				)

				if (
					WorldData
					.get_city_object_resident_capacity(
						home_object
					)
					<= 0
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " points to non-housing object "
							+ str(home_object_id)
							+ " as a home."
					)

			if not resident_membership.has(citizen_id):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to home "
						+ str(home_object_id)
						+ " but is absent from that resident list."
				)
			elif (
				int(resident_membership[citizen_id])
				!= home_object_id
			):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to home "
						+ str(home_object_id)
						+ " but appears in House "
						+ str(resident_membership[citizen_id])
						+ "."
				)
		elif resident_membership.has(citizen_id):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has no home ID but appears in House "
					+ str(resident_membership[citizen_id])
					+ "."
			)

		if job_object_id >= 0:
			if not object_lookup.has(job_object_id):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to missing workplace "
						+ str(job_object_id)
						+ "."
				)
			else:
				var workplace_index := int(
					object_lookup[job_object_id]
				)

				var workplace: Dictionary = (
					CityObjectSystem.get_city_objects()[
						workplace_index
					]
				)

				if not CityObjectCatalog.city_object_is_workplace(
					workplace
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " points to non-workplace object "
							+ str(job_object_id)
							+ " as a job."
					)

			if not worker_membership.has(citizen_id):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to workplace "
						+ str(job_object_id)
						+ " but is absent from its worker list."
				)
			elif (
				int(worker_membership[citizen_id])
				!= job_object_id
			):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to workplace "
						+ str(job_object_id)
						+ " but appears in workplace "
						+ str(worker_membership[citizen_id])
						+ "."
				)
		elif worker_membership.has(citizen_id):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has no job ID but appears in workplace "
					+ str(worker_membership[citizen_id])
					+ "."
			)


static func _validate_resident_list(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var city_object: Dictionary = values.get("city_object", {})
	var object_id := int(values.get("object_id", -1))
	var resident_capacity := int(values.get("resident_capacity", 0))
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	var resident_membership: Dictionary = values.get(
		"resident_membership",
		{}
	)
	var raw_resident_ids = city_object.get(
		"resident_ids",
		[]
	)

	if not raw_resident_ids is Array:
		errors.append(
			"Housing object "
				+ str(object_id)
				+ " has non-Array resident_ids."
		)

		return

	var resident_ids: Array = raw_resident_ids

	if resident_ids.size() > resident_capacity:
		errors.append(
			"Housing object "
				+ str(object_id)
				+ " has "
				+ str(resident_ids.size())
				+ " residents but capacity is "
				+ str(resident_capacity)
				+ "."
		)

	var local_residents: Dictionary = {}

	for raw_citizen_id in resident_ids:
		if typeof(raw_citizen_id) != TYPE_INT:
			errors.append(
				"Housing object "
					+ str(object_id)
					+ " contains a non-integer resident ID."
			)

			continue

		var citizen_id: int = raw_citizen_id

		if local_residents.has(citizen_id):
			errors.append(
				"Housing object "
					+ str(object_id)
					+ " lists citizen "
					+ str(citizen_id)
					+ " more than once."
			)

			continue

		local_residents[citizen_id] = true

		if resident_membership.has(citizen_id):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " appears in both House "
					+ str(resident_membership[citizen_id])
					+ " and House "
					+ str(object_id)
					+ "."
			)
		else:
			resident_membership[citizen_id] = object_id

		if not citizen_lookup.has(citizen_id):
			errors.append(
				"Housing object "
					+ str(object_id)
					+ " lists missing citizen "
					+ str(citizen_id)
					+ "."
			)

			continue

		var citizen_index := int(
			citizen_lookup[citizen_id]
		)

		var citizen: Dictionary = (
			CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]
		)

		if not bool(citizen.get("alive", true)):
			errors.append(
				"Housing object "
					+ str(object_id)
					+ " lists dead citizen "
					+ str(citizen_id)
					+ "."
			)

		if (
			int(citizen.get("home_object_id", -1))
			!= object_id
		):
			errors.append(
				"Housing object "
					+ str(object_id)
					+ " lists citizen "
					+ str(citizen_id)
					+ ", but the citizen points to home "
					+ str(
						citizen.get(
							"home_object_id",
							-1
						)
					)
					+ "."
			)


static func _validate_worker_list(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var city_object: Dictionary = values.get("city_object", {})
	var object_id := int(values.get("object_id", -1))
	var worker_capacity := int(values.get("worker_capacity", 0))
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	var worker_membership: Dictionary = values.get(
		"worker_membership",
		{}
	)
	var raw_worker_ids = city_object.get(
		"assigned_worker_ids",
		[]
	)

	if not raw_worker_ids is Array:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has non-Array assigned_worker_ids."
		)

		return

	var worker_ids: Array = raw_worker_ids

	if worker_ids.size() > worker_capacity:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has "
				+ str(worker_ids.size())
				+ " workers but capacity is "
				+ str(worker_capacity)
				+ "."
		)

	var local_workers: Dictionary = {}

	for raw_citizen_id in worker_ids:
		if typeof(raw_citizen_id) != TYPE_INT:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " contains a non-integer worker ID."
			)

			continue

		var citizen_id: int = raw_citizen_id

		if local_workers.has(citizen_id):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " lists citizen "
					+ str(citizen_id)
					+ " more than once."
			)

			continue

		local_workers[citizen_id] = true

		if worker_membership.has(citizen_id):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " appears in both workplace "
					+ str(worker_membership[citizen_id])
					+ " and workplace "
					+ str(object_id)
					+ "."
			)
		else:
			worker_membership[citizen_id] = object_id

		if not citizen_lookup.has(citizen_id):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " lists missing citizen "
					+ str(citizen_id)
					+ "."
			)

			continue

		var citizen_index := int(
			citizen_lookup[citizen_id]
		)

		var citizen: Dictionary = (
			CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]
		)

		if not bool(citizen.get("alive", true)):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " lists dead citizen "
					+ str(citizen_id)
					+ "."
			)

		if (
			int(citizen.get("job_object_id", -1))
			!= object_id
		):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " lists citizen "
					+ str(citizen_id)
					+ ", but the citizen points to job "
					+ str(
						citizen.get(
							"job_object_id",
							-1
						)
					)
					+ "."
			)


static func _validate_citizen_inventories(
	errors: Array[String],
	warnings: Array[String],
	citizen_lookup: Dictionary
) -> int:
	var checked_inventory_count := 0
	var valid_resources := (
		CityResourceCatalog.get_city_resource_types()
	)

	for citizen_id in citizen_lookup.keys():
		var citizen_index := int(
			citizen_lookup[citizen_id]
		)

		var citizen: Dictionary = (
			CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]
		)

		var raw_carry_capacity = citizen.get("carry_capacity")
		var carry_capacity := 0

		if (
			not citizen.has("carry_capacity")
			or typeof(raw_carry_capacity) != TYPE_INT
		):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has missing or non-integer carry capacity."
			)
		elif int(raw_carry_capacity) < 0:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has negative carry capacity "
					+ str(raw_carry_capacity)
					+ "."
			)
		else:
			carry_capacity = int(raw_carry_capacity)

		var raw_inventory = citizen.get("inventory")

		if not citizen.has("inventory") or not raw_inventory is Dictionary:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has non-Dictionary inventory."
			)

			continue

		checked_inventory_count += 1

		var inventory: Dictionary = raw_inventory
		var total_inventory_amount := 0

		for raw_resource in inventory.keys():
			if typeof(raw_resource) != TYPE_STRING:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " has a non-String inventory resource key."
				)

				continue

			var resource: String = raw_resource
			var raw_amount = inventory[raw_resource]

			if typeof(raw_amount) != TYPE_INT:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " has non-integer inventory amount for "
						+ resource
						+ "."
				)

				continue

			var amount: int = raw_amount

			if amount <= 0:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " has non-positive inventory amount for "
						+ resource
						+ "; empty resources must be omitted."
				)

			total_inventory_amount += maxi(amount, 0)

			if not valid_resources.has(resource):
				warnings.append(
					"Citizen "
						+ str(citizen_id)
						+ " carries unknown resource '"
						+ resource
						+ "'."
				)

		var haul_cargo_amount := 0

		if not CityCitizens.has_complete_city_citizen_haul_state(
			citizen
		):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has incomplete haul state."
			)
		else:
			var raw_haul_cargo = citizen.get("haul_cargo", {})

			if not raw_haul_cargo is Dictionary:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " has non-Dictionary haul cargo."
				)
			else:
				var haul_cargo: Dictionary = raw_haul_cargo
				var raw_cargo_resource = haul_cargo.get(
					"resource_type"
				)
				var raw_cargo_amount = haul_cargo.get("amount")
				var raw_cargo_resources = haul_cargo.get("resources")
				var manifest_total := 0
				var manifest_resources: Dictionary = {}

				if typeof(raw_cargo_resource) != TYPE_STRING:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " has non-string haul cargo primary resource."
					)

				if typeof(raw_cargo_amount) != TYPE_INT:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " has non-integer haul cargo amount."
					)
				else:
					haul_cargo_amount = maxi(
						int(raw_cargo_amount),
						0
					)

					if int(raw_cargo_amount) < 0:
						errors.append(
							"Citizen "
								+ str(citizen_id)
								+ " has negative haul cargo."
						)

				if not raw_cargo_resources is Dictionary:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " has non-Dictionary haul cargo resources."
					)
				else:
					for raw_manifest_resource in raw_cargo_resources.keys():
						if typeof(raw_manifest_resource) != TYPE_STRING:
							errors.append(
								"Citizen "
									+ str(citizen_id)
									+ " has a non-string haul cargo resource key."
							)
							continue

						var manifest_resource: String = raw_manifest_resource
						var raw_manifest_amount = raw_cargo_resources.get(
							raw_manifest_resource,
							0
						)

						if (
							typeof(raw_manifest_amount) != TYPE_INT
							or int(raw_manifest_amount) <= 0
							or not valid_resources.has(manifest_resource)
						):
							errors.append(
								"Citizen "
									+ str(citizen_id)
									+ " has invalid haul cargo entry '"
									+ manifest_resource
									+ "'."
							)
							continue

						var manifest_amount: int = raw_manifest_amount
						manifest_resources[manifest_resource] = manifest_amount
						manifest_total += manifest_amount

				if manifest_total != haul_cargo_amount:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul cargo manifest totals "
							+ str(manifest_total)
							+ " but stored amount is "
							+ str(haul_cargo_amount)
							+ "."
					)

				if typeof(raw_cargo_resource) == TYPE_STRING:
					var cargo_resource: String = raw_cargo_resource

					if (
						haul_cargo_amount <= 0
						and cargo_resource != WorldData.RESOURCE_NONE
					):
						errors.append(
							"Citizen "
								+ str(citizen_id)
								+ " has empty haul cargo with primary resource '"
								+ cargo_resource
								+ "'."
						)

					if (
						haul_cargo_amount > 0
						and not manifest_resources.has(cargo_resource)
					):
						errors.append(
							"Citizen "
								+ str(citizen_id)
								+ " haul cargo primary resource is absent from its manifest."
						)

		var total_carried_amount := (
			total_inventory_amount + haul_cargo_amount
		)

		if total_carried_amount > carry_capacity:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " carries "
					+ str(total_carried_amount)
					+ " items but capacity is "
					+ str(carry_capacity)
					+ "."
			)

	return checked_inventory_count




#endregion

#region Workplace Production
static func _validate_city_workplace_production(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var warnings: Array[String] = values.get("warnings", [])
	var object_lookup: Dictionary = values.get("object_lookup", {})
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	for object_id in object_lookup.keys():
		var object_index := int(object_lookup[object_id])
		var city_object: Dictionary = CityObjectSystem.get_city_objects()[object_index]

		if not CityObjectCatalog.city_object_is_workplace(city_object):
			continue

		var definition := CityObjectCatalog.get_city_object_definition_from_object(
			city_object
		)

		if definition.is_empty():
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has no valid city-object definition."
			)
			continue

		var raw_production_recipe = (
			_get_required_workplace_definition_dictionary({
				"errors": errors,
				"definition": definition,
				"object_id": int(object_id),
				"field_name": "production_recipe",
			})
		)

		if raw_production_recipe is Dictionary:
			var production_recipe: Dictionary = raw_production_recipe

			if not production_recipe.is_empty():
				var work_units_per_batch := _validate_workplace_recipe({
					"errors": errors,
					"city_object": city_object,
					"object_id": int(object_id),
					"recipe": production_recipe,
				})

				_validate_workplace_runtime_production_state({
					"errors": errors,
					"warnings": warnings,
					"city_object": city_object,
					"object_id": int(object_id),
					"citizen_lookup": citizen_lookup,
					"work_units_per_batch": work_units_per_batch,
				})

		var raw_resource_source_policy = (
			_get_required_workplace_definition_dictionary({
				"errors": errors,
				"definition": definition,
				"object_id": int(object_id),
				"field_name": "resource_source_policy",
			})
		)

		if raw_resource_source_policy is Dictionary:
			_validate_workplace_resource_source_policy(
				errors,
				int(object_id),
				raw_resource_source_policy
			)

		var raw_work_location_policy = (
			_get_required_workplace_definition_dictionary({
				"errors": errors,
				"definition": definition,
				"object_id": int(object_id),
				"field_name": "work_location_policy",
			})
		)

		if raw_work_location_policy is Dictionary:
			_validate_workplace_work_location_policy(
				errors,
				int(object_id),
				raw_work_location_policy
			)

		var raw_work_movement_policy = (
			_get_required_workplace_definition_dictionary({
				"errors": errors,
				"definition": definition,
				"object_id": int(object_id),
				"field_name": "work_movement_policy",
			})
		)

		if raw_work_movement_policy is Dictionary:
			_validate_workplace_movement_policy(
				errors,
				int(object_id),
				raw_work_movement_policy
			)

		var raw_break_location_policy = (
			_get_required_workplace_definition_dictionary({
				"errors": errors,
				"definition": definition,
				"object_id": int(object_id),
				"field_name": "break_location_policy",
			})
		)

		if raw_break_location_policy is Dictionary:
			_validate_workplace_break_location_policy(
				errors,
				int(object_id),
				raw_break_location_policy
			)

		var raw_overflow_policy = (
			_get_required_workplace_definition_dictionary({
				"errors": errors,
				"definition": definition,
				"object_id": int(object_id),
				"field_name": "overflow_policy",
			})
		)

		if raw_overflow_policy is Dictionary:
			_validate_workplace_overflow_policy(
				errors,
				int(object_id),
				raw_overflow_policy
			)


static func _get_required_workplace_definition_dictionary(
	values: Dictionary
) -> Variant:
	var errors: Array[String] = values.get("errors", [])
	var definition: Dictionary = values.get("definition", {})
	var object_id := int(values.get("object_id", -1))
	var field_name := str(values.get("field_name", ""))
	if not definition.has(field_name):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " definition is missing "
				+ field_name
				+ "."
		)
		return null

	var raw_value = definition[field_name]

	if not raw_value is Dictionary:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " definition has non-Dictionary "
				+ field_name
				+ "."
		)
		return null

	return raw_value


static func _validate_workplace_recipe(
	values: Dictionary
) -> int:
	var errors: Array[String] = values.get("errors", [])
	var city_object: Dictionary = values.get("city_object", {})
	var object_id := int(values.get("object_id", -1))
	var recipe: Dictionary = values.get("recipe", {})
	var valid_resources := CityResourceCatalog.get_city_resource_types()
	var raw_inputs = recipe.get("inputs", null)

	if not recipe.has("inputs"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe is missing inputs."
		)
	elif not raw_inputs is Dictionary:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe has non-Dictionary inputs."
		)
	else:
		_validate_workplace_recipe_resources({
			"errors": errors,
			"city_object": city_object,
			"object_id": object_id,
			"resource_amounts": raw_inputs,
			"valid_resources": valid_resources,
			"entry_label": "input",
			"validate_output_storage": false,
		})

	var raw_outputs = recipe.get("outputs", null)

	if not recipe.has("outputs"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe is missing outputs."
		)
	elif not raw_outputs is Dictionary:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe has non-Dictionary outputs."
		)
	else:
		var outputs: Dictionary = raw_outputs

		if outputs.is_empty():
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " production recipe has no outputs."
			)
		else:
			_validate_workplace_recipe_resources({
			"errors": errors,
			"city_object": city_object,
			"object_id": object_id,
			"resource_amounts": outputs,
			"valid_resources": valid_resources,
			"entry_label": "output",
			"validate_output_storage": true,
		})

	if not recipe.has("work_units_per_batch"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe is missing work_units_per_batch."
		)
		return 0

	var raw_work_units_per_batch = recipe["work_units_per_batch"]

	if typeof(raw_work_units_per_batch) != TYPE_INT:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe has non-integer work_units_per_batch."
		)
		return 0

	var work_units_per_batch: int = raw_work_units_per_batch

	if work_units_per_batch <= 0:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe has non-positive work_units_per_batch "
				+ str(work_units_per_batch)
				+ "."
		)
		return 0

	return work_units_per_batch


static func _validate_workplace_recipe_resources(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var city_object: Dictionary = values.get("city_object", {})
	var object_id := int(values.get("object_id", -1))
	var resource_amounts: Dictionary = values.get("resource_amounts", {})
	var valid_resources: Array[String] = values.get("valid_resources", [])
	var entry_label := str(values.get("entry_label", ""))
	var validate_output_storage := bool(
		values.get("validate_output_storage", false)
	)
	for raw_resource in resource_amounts.keys():
		var resource := str(raw_resource)
		var resource_is_known := valid_resources.has(resource)

		if not resource_is_known:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " production recipe has unknown "
					+ entry_label
					+ " resource '"
					+ resource
					+ "'."
			)

		var raw_quantity = resource_amounts[raw_resource]

		if typeof(raw_quantity) != TYPE_INT:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " production recipe has non-integer quantity for "
					+ entry_label
					+ " resource '"
					+ resource
					+ "'."
			)
		elif int(raw_quantity) <= 0:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " production recipe has non-positive quantity for "
					+ entry_label
					+ " resource '"
					+ resource
					+ "'."
			)

		if not validate_output_storage or not resource_is_known:
			continue

		if not CityResourceContainerSystem.can_city_object_store_resource(
			city_object,
			resource
		):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " cannot store recipe output resource '"
					+ resource
					+ "'."
			)
			continue

		var output_capacity := (
			CityResourceContainerSystem.get_city_object_storage_capacity_for_resource(
				city_object,
				resource
			)
		)

		if output_capacity <= 0:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has non-positive storage capacity for recipe output '"
					+ resource
					+ "'."
			)


static func _validate_workplace_runtime_production_state(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var warnings: Array[String] = values.get("warnings", [])
	var city_object: Dictionary = values.get("city_object", {})
	var object_id := int(values.get("object_id", -1))
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	var work_units_per_batch := int(values.get("work_units_per_batch", 0))

	if not city_object.has("production_progress_work_units"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " is missing production_progress_work_units."
		)
	else:
		var raw_progress = city_object["production_progress_work_units"]

		if typeof(raw_progress) != TYPE_INT:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has non-integer production_progress_work_units."
			)
		else:
			var progress_work_units: int = raw_progress

			if progress_work_units < 0:
				errors.append(
					"Workplace "
						+ str(object_id)
						+ " has negative production progress "
						+ str(progress_work_units)
						+ "."
				)
			elif (
				work_units_per_batch > 0
				and progress_work_units >= work_units_per_batch
			):
				errors.append(
					"Workplace "
						+ str(object_id)
						+ " has production progress "
						+ str(progress_work_units)
						+ ", but one batch requires "
						+ str(work_units_per_batch)
						+ "."
				)

	if not city_object.has("production_status"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " is missing production_status."
		)
	else:
		var raw_status = city_object["production_status"]

		if typeof(raw_status) != TYPE_STRING:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has non-String production_status."
			)
		elif not CityObjectCatalog.is_valid_city_workplace_production_status(
			raw_status
		):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has unknown production status '"
					+ str(raw_status)
					+ "'."
			)

	if not city_object.has("productive_worker_count"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " is missing productive_worker_count."
		)
	else:
		var raw_productive_worker_count = city_object[
			"productive_worker_count"
		]

		if typeof(raw_productive_worker_count) != TYPE_INT:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has non-integer productive_worker_count."
			)
		else:
			var productive_worker_count: int = (
				raw_productive_worker_count
			)
			var worker_capacity := (
				CityObjectCatalog.get_city_object_worker_capacity(city_object)
			)

			if productive_worker_count < 0:
				errors.append(
					"Workplace "
						+ str(object_id)
						+ " has negative productive_worker_count "
						+ str(productive_worker_count)
						+ "."
				)
			elif productive_worker_count > worker_capacity:
				errors.append(
					"Workplace "
						+ str(object_id)
						+ " has productive_worker_count "
						+ str(productive_worker_count)
						+ " but worker capacity is "
						+ str(worker_capacity)
						+ "."
				)

			var expected_productive_worker_count := (
				_get_expected_productive_worker_count(
					city_object,
					citizen_lookup
				)
			)
			var production_status := str(
				city_object.get("production_status", "")
			)

			# A newly staffed workplace can still be idle until the next tick.
			# Compare the derived count only after production has evaluated it.
			var production_has_evaluated_workers := (
				production_status
				== CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_WORKING
				or production_status
				== CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL
				or production_status
				== CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT
				or production_status
				== CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE
			)

			if (
				production_has_evaluated_workers
				and expected_productive_worker_count >= 0
				and productive_worker_count
				!= expected_productive_worker_count
			):
				warnings.append(
					"Workplace "
						+ str(object_id)
						+ " caches "
						+ str(productive_worker_count)
						+ " productive workers, but current attendance state yields "
						+ str(expected_productive_worker_count)
						+ "."
				)

	if not city_object.has("site_productivity_basis_points"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " is missing site_productivity_basis_points."
		)
	else:
		var raw_site_productivity = city_object[
			"site_productivity_basis_points"
		]

		if typeof(raw_site_productivity) != TYPE_INT:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has non-integer site_productivity_basis_points."
			)
		elif int(raw_site_productivity) < 0:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has negative site_productivity_basis_points "
					+ str(raw_site_productivity)
					+ "."
			)


static func _get_expected_productive_worker_count(
	city_object: Dictionary,
	citizen_lookup: Dictionary
) -> int:
	var raw_worker_ids = city_object.get("assigned_worker_ids", null)

	if not raw_worker_ids is Array:
		return -1

	var workplace_id := int(city_object.get("id", -1))

	if workplace_id <= 0:
		return -1

	var productive_worker_count := 0
	var counted_worker_ids: Dictionary = {}

	for raw_worker_id in raw_worker_ids:
		if typeof(raw_worker_id) != TYPE_INT:
			continue

		var worker_id: int = raw_worker_id

		if worker_id <= 0 or counted_worker_ids.has(worker_id):
			continue

		counted_worker_ids[worker_id] = true

		if not citizen_lookup.has(worker_id):
			continue

		var citizen_index := int(citizen_lookup[worker_id])
		var citizen: Dictionary = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

		if not bool(citizen.get("alive", false)):
			continue

		if int(citizen.get("job_object_id", -1)) != workplace_id:
			continue

		if not CityEmploymentSystem.is_city_citizen_attending_workplace(
			worker_id,
			workplace_id
		):
			continue

		productive_worker_count += 1

	return mini(
		productive_worker_count,
		maxi(
			CityObjectCatalog.get_city_object_worker_capacity(city_object),
			0
		)
	)

static func _validate_workplace_resource_source_policy(
	errors: Array[String],
	object_id: int,
	policy: Dictionary
) -> void:
	var mode := _get_workplace_policy_mode({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "resource_source_policy",
		"policy": policy,
	})

	if mode.is_empty():
		return

	if not CityObjectCatalog.is_valid_workplace_resource_source_mode(mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has unknown resource_source_policy mode '"
				+ mode
				+ "'."
		)
		return

	if (
		mode
		== CityObjectCatalog.WORKPLACE_RESOURCE_SOURCE_MODE_FOOTPRINT_REACH
	):
		_validate_known_workplace_policy_resource({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "resource_source_policy",
		"policy": policy,
		"field_name": "resource_type",
	})

		_validate_positive_workplace_policy_integer({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "resource_source_policy",
		"policy": policy,
		"field_name": "reach_tiles",
	})

		_validate_positive_workplace_policy_integer({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "resource_source_policy",
		"policy": policy,
		"field_name": "source_density_for_full_productivity_basis_points",
	})

		var raw_full_density = policy.get(
			"source_density_for_full_productivity_basis_points",
			0
		)

		if (
			typeof(raw_full_density) == TYPE_INT
			and int(raw_full_density)
			> CityObjectCatalog.PRODUCTIVITY_BASIS_POINTS_SCALE
		):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " resource_source_policy has "
					+ "source_density_for_full_productivity_basis_points "
					+ str(raw_full_density)
					+ ", which exceeds 100% density."
			)
		return

	if mode != CityObjectCatalog.WORKPLACE_RESOURCE_SOURCE_MODE_RADIUS:
		return

	_validate_known_workplace_policy_resource({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "resource_source_policy",
		"policy": policy,
		"field_name": "resource_type",
	})

	_validate_positive_workplace_policy_integer({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "resource_source_policy",
		"policy": policy,
		"field_name": "radius_tiles",
	})

	if not policy.has("anchor_mode"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " resource_source_policy is missing anchor_mode."
		)
		return

	var raw_anchor_mode = policy["anchor_mode"]

	if typeof(raw_anchor_mode) != TYPE_STRING:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " resource_source_policy has non-String anchor_mode."
		)
		return

	var anchor_mode: String = raw_anchor_mode

	if not CityObjectCatalog.is_valid_workplace_anchor_mode(anchor_mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " resource_source_policy has unknown anchor_mode '"
				+ anchor_mode
				+ "'."
		)

static func _validate_workplace_work_location_policy(
	errors: Array[String],
	object_id: int,
	policy: Dictionary
) -> void:
	var mode := _get_workplace_policy_mode({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "work_location_policy",
		"policy": policy,
	})

	if mode.is_empty():
		return

	if not CityObjectCatalog.is_valid_workplace_work_location_mode(mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has unknown work_location_policy mode '"
				+ mode
				+ "'."
		)


static func _validate_workplace_movement_policy(
	errors: Array[String],
	object_id: int,
	policy: Dictionary
) -> void:
	var mode := _get_workplace_policy_mode({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "work_movement_policy",
		"policy": policy,
	})

	if mode.is_empty():
		return

	if not CityObjectCatalog.is_valid_workplace_movement_mode(mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has unknown work_movement_policy mode '"
				+ mode
				+ "'."
		)


static func _validate_workplace_break_location_policy(
	errors: Array[String],
	object_id: int,
	policy: Dictionary
) -> void:
	var mode := _get_workplace_policy_mode({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "break_location_policy",
		"policy": policy,
	})

	if mode.is_empty():
		return

	if not CityObjectCatalog.is_valid_workplace_break_location_mode(mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has unknown break_location_policy mode '"
				+ mode
				+ "'."
		)
		return

	if mode == CityObjectCatalog.WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT_RADIUS:
		_validate_positive_workplace_policy_integer({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "break_location_policy",
		"policy": policy,
		"field_name": "radius_tiles",
	})


static func _validate_workplace_overflow_policy(
	errors: Array[String],
	object_id: int,
	policy: Dictionary
) -> void:
	var mode := _get_workplace_policy_mode({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "overflow_policy",
		"policy": policy,
	})

	if mode.is_empty():
		return

	if not CityObjectCatalog.is_valid_workplace_overflow_mode(mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has unknown overflow_policy mode '"
				+ mode
				+ "'."
		)
		return

	if mode == CityObjectCatalog.WORKPLACE_OVERFLOW_MODE_FOOTPRINT_RADIUS:
		_validate_positive_workplace_policy_integer({
		"errors": errors,
		"object_id": object_id,
		"policy_name": "overflow_policy",
		"policy": policy,
		"field_name": "radius_tiles",
	})


static func _get_workplace_policy_mode(
	values: Dictionary
) -> String:
	var errors: Array[String] = values.get("errors", [])
	var object_id := int(values.get("object_id", -1))
	var policy_name := str(values.get("policy_name", ""))
	var policy: Dictionary = values.get("policy", {})
	if not policy.has("mode"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " is missing mode."
		)
		return ""

	var raw_mode = policy["mode"]

	if typeof(raw_mode) != TYPE_STRING:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " has non-String mode."
		)
		return ""

	return str(raw_mode)


static func _validate_known_workplace_policy_resource(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var object_id := int(values.get("object_id", -1))
	var policy_name := str(values.get("policy_name", ""))
	var policy: Dictionary = values.get("policy", {})
	var field_name := str(values.get("field_name", ""))
	if not policy.has(field_name):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " is missing "
				+ field_name
				+ "."
		)
		return

	var raw_resource = policy[field_name]

	if typeof(raw_resource) != TYPE_STRING:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " has non-String "
				+ field_name
				+ "."
		)
		return

	var resource: String = raw_resource

	if not CityResourceCatalog.is_city_resource_type(resource):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " has unknown "
				+ field_name
				+ " '"
				+ resource
				+ "'."
		)


static func _validate_positive_workplace_policy_integer(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var object_id := int(values.get("object_id", -1))
	var policy_name := str(values.get("policy_name", ""))
	var policy: Dictionary = values.get("policy", {})
	var field_name := str(values.get("field_name", ""))
	if not policy.has(field_name):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " is missing "
				+ field_name
				+ "."
		)
		return

	var raw_value = policy[field_name]

	if typeof(raw_value) != TYPE_INT:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " has non-integer "
				+ field_name
				+ "."
		)
		return

	if int(raw_value) <= 0:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " has non-positive "
				+ field_name
				+ " "
				+ str(raw_value)
				+ "."
		)




#endregion
