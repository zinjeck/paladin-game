extends Node

# Focused characterization for the presentation invalidation seam. The tracker
# may retain exact owner references and numeric versions, but polling it must be
# stale-generation-safe and must never mutate authoritative gameplay state.

const CITY_A_SEED: int = 311_001
const CITY_B_SEED: int = 311_002
const TrackerScript := preload(
	"res://scripts/city/rendering/CityPresentationInvalidationTracker.gd"
)
const ALL_CHANGE_FLAGS: Array[String] = [
	"city_objects_changed",
	"city_containers_changed",
	"public_storage_changed",
	"city_citizens_changed",
	"city_citizen_registry_changed",
	"city_citizen_spatial_changed",
	"city_citizen_movement_changed",
	"city_citizen_movement_runtime_changed",
	"city_citizen_task_changed",
	"city_citizen_task_runtime_changed",
	"city_ground_piles_changed",
	"city_player_commands_changed",
	"city_haul_reservations_changed",
	"city_construction_changed",
	"city_assignments_changed",
	"city_workplaces_changed",
	"city_tile_data_changed",
	"city_surface_features_changed",
]

var failure_count: int = 0
var culture_id: int = CultureData.INVALID_CULTURE_ID
var polity_id: int = PolityData.INVALID_POLITY_ID
var city_a_id: int = SettlementData.INVALID_SETTLEMENT_ID
var city_a_context: SettlementSimulationContext
var city_a_state: CitySettlementSimulationState
var city_b_id: int = SettlementData.INVALID_SETTLEMENT_ID
var city_b_context: SettlementSimulationContext
var city_b_state: CitySettlementSimulationState


func _ready() -> void:
	_test_binding_generation_transaction()
	_test_all_version_and_owner_invalidation_paths()
	_cleanup()

	if failure_count > 0:
		push_error(
			"City presentation invalidation tracker test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City presentation invalidation tracker test passed.")
	get_tree().quit(0)


func _test_binding_generation_transaction() -> void:
	if not _create_two_city_fixture():
		_expect(false, "The binding transaction fixture must be created.")
		return

	var binding := CityPresentationBinding.new()
	_expect(
		not binding.rebind(null, 1) and not binding.is_valid(),
		"An invalid initial binding must be rejected without partial identity."
	)
	_expect(
		binding.rebind(city_a_context, 1),
		"A valid registered binding generation must be accepted."
	)
	var context_before := binding.settlement_context
	var state_before := binding.city_state
	var world_before := binding.city_world
	var settlement_before := binding.settlement_id
	var seed_before := binding.city_seed
	_expect(
		not binding.rebind(city_b_context, 1)
		and is_same(binding.settlement_context, context_before)
		and is_same(binding.city_state, state_before)
		and is_same(binding.city_world, world_before)
		and binding.settlement_id == settlement_before
		and binding.city_seed == seed_before
		and binding.generation == 1,
		"A stale/equal generation must leave the previous valid binding transactional and retryable."
	)
	_expect(
		not binding.rebind(city_b_context, 2)
		and binding.matches_context(city_a_context)
		and binding.accepts_generation(1)
		and not binding.accepts_generation(2)
		and binding.highest_accepted_generation == 1,
		(
			"A binding token must be immutable after its first valid bind; a "
			+ "newer settlement requires a fresh token."
		)
	)
	binding.reset()
	_expect(
		not binding.is_valid()
		and not binding.rebind(city_a_context, 1)
		and not binding.rebind(city_b_context, 2)
		and binding.highest_accepted_generation == 1,
		(
			"Binding reset must clear references, preserve the generation "
			+ "high-water mark, and never make the identity token reusable."
		)
	)
	var replacement_binding := CityPresentationBinding.new()
	_expect(
		replacement_binding.rebind(city_b_context, 2)
		and replacement_binding.matches_context(city_b_context),
		"A fresh token must carry the strictly newer settlement generation."
	)
	_cleanup()


func _test_all_version_and_owner_invalidation_paths() -> void:
	if not _create_two_city_fixture():
		_expect(false, "The invalidation tracker fixture must be created.")
		return

	var binding_a := CityPresentationBinding.new()
	var binding_b := CityPresentationBinding.new()
	_expect(
		binding_a.rebind(city_a_context, 1)
		and binding_b.rebind(city_b_context, 2),
		"Both cities must expose valid monotonic presentation bindings."
	)
	if not binding_a.is_valid() or not binding_b.is_valid():
		return

	var tracker := TrackerScript.new()
	_expect(
		tracker.can_rebind_city_presentation(binding_a)
		and not tracker.is_bound_to_city_presentation(binding_a),
		"Tracker rebind preflight must be non-mutating for one valid newer binding."
	)
	_expect(
		tracker.rebind_city_presentation(binding_a)
		and tracker.is_bound_to_city_presentation(binding_a)
		and not tracker.can_rebind_city_presentation(binding_a)
		and tracker.can_rebind_city_presentation(binding_b)
		and tracker.accepts_generation(1)
		and tracker.capture_current_versions(1),
		"Tracker A must accept and capture one exact binding generation."
	)
	var no_change_flags: Dictionary = tracker.create_change_flags()
	var a_before_no_change_poll := _capture_gameplay_snapshot(city_a_state)
	_expect(
		tracker.collect_city_state_change_flags(1, no_change_flags)
		and tracker.collect_city_world_version_change_flags(1, no_change_flags)
		and _all_change_flags_are_false(no_change_flags)
		and _capture_gameplay_snapshot(city_a_state)
		== a_before_no_change_poll,
		"A no-change poll must be pure and produce no invalidation."
	)

	var version_cases: Array[Dictionary] = [
		{"name": "object", "expected": ["city_objects_changed"]},
		{"name": "container", "expected": ["city_containers_changed"]},
		{"name": "public_storage", "expected": ["public_storage_changed"]},
		{"name": "citizen", "expected": ["city_citizens_changed"]},
		{"name": "spatial", "expected": ["city_citizen_spatial_changed"]},
		{"name": "movement", "expected": ["city_citizen_movement_changed"]},
		{"name": "task", "expected": ["city_citizen_task_changed"]},
		{"name": "ground_pile", "expected": ["city_ground_piles_changed"]},
		{"name": "player_command", "expected": ["city_player_commands_changed"]},
		{"name": "haul_reservation", "expected": ["city_haul_reservations_changed"]},
		{"name": "construction", "expected": ["city_construction_changed"]},
		{"name": "assignment", "expected": ["city_assignments_changed"]},
		{"name": "workplace", "expected": ["city_workplaces_changed"]},
	]
	for version_case in version_cases:
		_increment_version(city_a_state, str(version_case["name"]))
		var before_poll := _capture_gameplay_snapshot(city_a_state)
		var flags: Dictionary = tracker.create_change_flags()
		var expected_flags: Array = version_case["expected"]
		_expect(
			tracker.collect_city_state_change_flags(1, flags),
			"The current generation must collect "
			+ str(version_case["name"])
			+ " invalidation."
		)
		_expect_exact_change_flags(
			flags,
			expected_flags,
			str(version_case["name"]) + " version"
		)
		_expect(
			_capture_gameplay_snapshot(city_a_state) == before_poll,
			"Polling " + str(version_case["name"]) + " must be read-only."
		)
		_expect(
			tracker.capture_current_versions(1),
			"Each accepted version must become the next exact baseline."
		)

	city_a_state.city_world.tile_data_version += 1
	var before_tile_poll := _capture_gameplay_snapshot(city_a_state)
	var tile_flags: Dictionary = tracker.create_change_flags()
	_expect(
		tracker.collect_city_world_version_change_flags(1, tile_flags),
		"Tile-data invalidation must accept the current generation."
	)
	_expect_exact_change_flags(
		tile_flags,
		["city_tile_data_changed"],
		"tile-data version"
	)
	_expect(
		_capture_gameplay_snapshot(city_a_state) == before_tile_poll
		and tracker.capture_current_versions(1),
		"Tile-data polling must not mutate the world or gameplay owners."
	)

	city_a_state.city_world.city_surface_feature_change_version += 1
	var before_surface_poll := _capture_gameplay_snapshot(city_a_state)
	var surface_flags: Dictionary = tracker.create_change_flags()
	_expect(
		tracker.collect_city_world_version_change_flags(1, surface_flags),
		"Surface-feature invalidation must accept the current generation."
	)
	_expect_exact_change_flags(
		surface_flags,
		["city_surface_features_changed"],
		"surface-feature version"
	)
	_expect(
		_capture_gameplay_snapshot(city_a_state) == before_surface_poll
		and tracker.capture_current_versions(1),
		"Surface-feature polling must not consume or mutate world events."
	)

	_replace_all_observed_owners_at_equal_versions(city_a_state)
	var before_owner_poll := _capture_gameplay_snapshot(city_a_state)
	var owner_flags: Dictionary = tracker.create_change_flags()
	_expect(
		tracker.collect_city_state_change_flags(1, owner_flags),
		"Equal-version owner replacement must be observed for the current generation."
	)
	_expect_exact_change_flags(
		owner_flags,
		[
			"city_objects_changed",
			"city_containers_changed",
			"public_storage_changed",
			"city_citizens_changed",
			"city_citizen_registry_changed",
			"city_citizen_spatial_changed",
			"city_citizen_movement_changed",
			"city_citizen_movement_runtime_changed",
			"city_citizen_task_changed",
			"city_citizen_task_runtime_changed",
			"city_ground_piles_changed",
			"city_player_commands_changed",
			"city_haul_reservations_changed",
			"city_construction_changed",
			"city_assignments_changed",
			"city_workplaces_changed",
		],
		"equal-version exact-owner replacement"
	)
	_expect(
		_capture_gameplay_snapshot(city_a_state) == before_owner_poll,
		"Exact-owner collision detection must remain read-only."
	)

	var city_b_before := _capture_gameplay_snapshot(city_b_state)
	var city_b_identities := _capture_gameplay_identities(city_b_state)
	_expect(
		tracker.rebind_city_presentation(binding_b)
		and tracker.capture_current_versions(2),
		"Tracker must rebind atomically to the strictly newer B generation."
	)
	city_a_state.object_state.object_version += 1
	var b_flags_after_a_mutation: Dictionary = tracker.create_change_flags()
	_expect(
		tracker.collect_city_state_change_flags(2, b_flags_after_a_mutation)
		and _all_change_flags_are_false(b_flags_after_a_mutation)
		and _capture_gameplay_snapshot(city_b_state) == city_b_before
		and _gameplay_identities_match(city_b_state, city_b_identities),
		"After rebinding B, an A-only mutation must neither invalidate nor mutate B."
	)

	var stale_flags: Dictionary = tracker.create_change_flags()
	_expect(
		not tracker.collect_city_state_change_flags(1, stale_flags)
		and not tracker.collect_city_world_version_change_flags(1, stale_flags)
		and _all_change_flags_are_false(stale_flags)
		and tracker.is_bound_to_city_presentation(binding_b),
		"Stale generation polling must fail without flags or binding mutation."
	)
	tracker.reset()
	_expect(
		not tracker.accepts_generation(2)
		and not tracker.rebind_city_presentation(binding_a),
		"Reset must clear observations while preserving the generation high-water mark."
	)
	var binding_a_three := CityPresentationBinding.new()
	_expect(
		binding_a_three.rebind(city_a_context, 3)
		and tracker.rebind_city_presentation(binding_a_three)
		and tracker.capture_current_versions(3),
		"A fresh newer generation must remain retryable after reset."
	)


func _increment_version(
	city_state: CitySettlementSimulationState,
	version_name: String
) -> void:
	match version_name:
		"object":
			city_state.object_state.object_version += 1
		"container":
			city_state.resource_accounting_state.container_version += 1
		"public_storage":
			city_state.resource_accounting_state.public_storage_version += 1
		"citizen":
			city_state.citizen_registry_state.citizen_version += 1
		"spatial":
			city_state.citizen_spatial_state.citizen_spatial_version += 1
		"movement":
			city_state.citizen_movement_runtime_state.citizen_movement_version += 1
		"task":
			city_state.citizen_task_runtime_state.citizen_task_version += 1
		"ground_pile":
			city_state.logistics_state.ground_pile_version += 1
		"player_command":
			city_state.work_state.player_command_version += 1
		"haul_reservation":
			city_state.logistics_state.haul_reservation_version += 1
		"construction":
			city_state.construction_state.construction_version += 1
		"assignment":
			city_state.assignment_state.assignment_version += 1
		"workplace":
			city_state.workplace_state.workplace_version += 1


func _replace_all_observed_owners_at_equal_versions(
	city_state: CitySettlementSimulationState
) -> void:
	var object_state := CityObjectState.new()
	object_state.object_version = city_state.object_state.object_version
	city_state.object_state = object_state

	var resource_state := CityResourceAccountingState.new()
	resource_state.container_version = (
		city_state.resource_accounting_state.container_version
	)
	resource_state.public_storage_version = (
		city_state.resource_accounting_state.public_storage_version
	)
	city_state.resource_accounting_state = resource_state

	var registry_state := CityCitizenRegistryState.new()
	registry_state.citizen_version = (
		city_state.citizen_registry_state.citizen_version
	)
	city_state.citizen_registry_state = registry_state

	var spatial_state := CityCitizenSpatialState.new()
	spatial_state.citizen_spatial_version = (
		city_state.citizen_spatial_state.citizen_spatial_version
	)
	city_state.citizen_spatial_state = spatial_state

	var movement_state := CityCitizenMovementRuntimeState.new()
	movement_state.citizen_movement_version = (
		city_state.citizen_movement_runtime_state.citizen_movement_version
	)
	city_state.citizen_movement_runtime_state = movement_state

	var task_state := CityCitizenTaskRuntimeState.new()
	task_state.citizen_task_version = (
		city_state.citizen_task_runtime_state.citizen_task_version
	)
	city_state.citizen_task_runtime_state = task_state

	var logistics_state := CityLogisticsState.new()
	logistics_state.ground_pile_version = (
		city_state.logistics_state.ground_pile_version
	)
	logistics_state.haul_reservation_version = (
		city_state.logistics_state.haul_reservation_version
	)
	city_state.logistics_state = logistics_state

	var work_state := CityWorkState.new()
	work_state.player_command_version = (
		city_state.work_state.player_command_version
	)
	city_state.work_state = work_state

	var construction_state := CityConstructionState.new()
	construction_state.construction_version = (
		city_state.construction_state.construction_version
	)
	city_state.construction_state = construction_state

	var assignment_state := CityAssignmentState.new()
	assignment_state.assignment_version = (
		city_state.assignment_state.assignment_version
	)
	city_state.assignment_state = assignment_state

	var workplace_state := CityWorkplaceState.new()
	workplace_state.workplace_version = (
		city_state.workplace_state.workplace_version
	)
	city_state.workplace_state = workplace_state


func _expect_exact_change_flags(
	flags: Dictionary,
	expected_true_flags: Array,
	label: String
) -> void:
	var unexpected: Array[String] = []
	for flag_name in ALL_CHANGE_FLAGS:
		if bool(flags.get(flag_name, false)) != expected_true_flags.has(flag_name):
			unexpected.append(flag_name)
	_expect(
		unexpected.is_empty(),
		label + " produced incorrect flags: " + str(unexpected)
	)


func _all_change_flags_are_false(flags: Dictionary) -> bool:
	for flag_name in ALL_CHANGE_FLAGS:
		if bool(flags.get(flag_name, false)):
			return false
	return true


func _create_two_city_fixture() -> bool:
	_cleanup()
	var culture := WorldData.create_culture("Invalidation Tracker Culture")
	culture_id = int(culture.get("id", CultureData.INVALID_CULTURE_ID))
	var polity := WorldPoliticalState.create_polity({
		"name": "Invalidation Tracker Polity",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	polity_id = int(polity.get("id", PolityData.INVALID_POLITY_ID))
	if culture_id <= 0 or polity_id <= 0:
		return false

	var settlement_a := WorldPoliticalState.create_settlement({
		"name": "Invalidation Tracker A",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": Vector2i(1, 1),
		"world_region_center": Vector2i(1, 1),
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	var settlement_b := WorldPoliticalState.create_settlement({
		"name": "Invalidation Tracker B",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": Vector2i(9, 9),
		"world_region_center": Vector2i(9, 9),
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	city_a_id = int(
		settlement_a.get("id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	city_b_id = int(
		settlement_b.get("id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	if city_a_id <= 0 or city_b_id <= 0:
		return false
	WorldPoliticalState.player_polity_id = polity_id
	if not WorldPoliticalState.set_polity_capital(polity_id, city_a_id):
		return false
	if not WorldPoliticalState.store_city_world_for_settlement(
		city_a_id,
		_make_world(CITY_A_SEED),
		CITY_A_SEED
	):
		return false
	if not WorldPoliticalState.store_city_world_for_settlement(
		city_b_id,
		_make_world(CITY_B_SEED),
		CITY_B_SEED
	):
		return false
	city_a_context = WorldPoliticalState.get_settlement_context(city_a_id)
	city_a_state = WorldPoliticalState.get_city_simulation_state(city_a_id)
	city_b_context = WorldPoliticalState.get_settlement_context(city_b_id)
	city_b_state = WorldPoliticalState.get_city_simulation_state(city_b_id)
	return (
		city_a_context != null
		and city_a_state != null
		and city_b_context != null
		and city_b_state != null
	)


func _make_world(seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(4, 4, seed_value)
	for y in range(world.height):
		for x in range(world.width):
			world.tiles[y][x] = {
				"fertility": 50.0,
				"elevation": 0.2,
				"temperature": 0.5,
				"precipitation": 0.5,
				"terrain": WorldData.TERRAIN_LAND,
				"biome": WorldData.BIOME_PLAIN,
				"resource": WorldData.RESOURCE_NONE,
				"is_land": true,
			}
	world.mark_tile_data_changed()
	return world


func _capture_gameplay_snapshot(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	var owners := {}
	for owner_key in _get_gameplay_owner_map(city_state).keys():
		owners[owner_key] = _capture_script_variable_values(
			_get_gameplay_owner_map(city_state)[owner_key]
		)
	var world_values := _capture_script_variable_values(city_state.city_world)
	return {
		"city_seed": city_state.city_seed,
		"runtime": city_state.city_runtime_data.duplicate(true),
		"world": world_values,
		"owners": owners,
	}


func _capture_gameplay_identities(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	var identities := {
		"world": city_state.city_world,
		"runtime": city_state.city_runtime_data,
	}
	identities.merge(_get_gameplay_owner_map(city_state))
	return identities


func _gameplay_identities_match(
	city_state: CitySettlementSimulationState,
	identities: Dictionary
) -> bool:
	if (
		not is_same(city_state.city_world, identities.get("world"))
		or not is_same(city_state.city_runtime_data, identities.get("runtime"))
	):
		return false
	for owner_key in _get_gameplay_owner_map(city_state).keys():
		if not is_same(
			_get_gameplay_owner_map(city_state)[owner_key],
			identities.get(owner_key)
		):
			return false
	return true


func _get_gameplay_owner_map(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"object_state": city_state.object_state,
		"resource_accounting_state": city_state.resource_accounting_state,
		"citizen_registry_state": city_state.citizen_registry_state,
		"assignment_state": city_state.assignment_state,
		"workplace_state": city_state.workplace_state,
		"citizen_spatial_state": city_state.citizen_spatial_state,
		"citizen_movement_runtime_state": (
			city_state.citizen_movement_runtime_state
		),
		"citizen_task_runtime_state": city_state.citizen_task_runtime_state,
		"citizen_decision_runtime_state": (
			city_state.citizen_decision_runtime_state
		),
		"work_state": city_state.work_state,
		"logistics_state": city_state.logistics_state,
		"construction_state": city_state.construction_state,
		"navigation_state": city_state.navigation_state,
	}


func _capture_script_variable_values(owner) -> Dictionary:
	if owner == null or not owner.has_method("get_property_list"):
		return {}
	var values := {}
	for property in owner.get_property_list():
		var usage := int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var property_name := str(property.get("name", ""))
		if property_name.is_empty():
			continue
		var value = owner.get(property_name)
		if value is Dictionary:
			values[property_name] = value.duplicate(true)
		elif value is Array:
			values[property_name] = value.duplicate(true)
		else:
			values[property_name] = value
	return values


func _cleanup() -> void:
	culture_id = CultureData.INVALID_CULTURE_ID
	polity_id = PolityData.INVALID_POLITY_ID
	city_a_id = SettlementData.INVALID_SETTLEMENT_ID
	city_a_context = null
	city_a_state = null
	city_b_id = SettlementData.INVALID_SETTLEMENT_ID
	city_b_context = null
	city_b_state = null
	WorldData.reset_runtime_session_state()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error(message)
