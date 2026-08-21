extends Node

const CitySettlementTestFixtureScript = preload(
	"res://scripts/city/simulation/test_support/CitySettlementTestFixture.gd"
)
const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 24)
const TEST_WORLD_SEED := 77_007

var failure_count: int = 0
var test_fixture = null
var test_city_state: CitySettlementSimulationState = null


func _ready() -> void:
	_test_partial_cancellation_releases_materials_and_reservations_once()
	_test_full_cancellation_preserves_radius_capacity_and_local_overflow()
	_test_explicit_release_preserves_active_settlement_and_ordinary_ids()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"Construction cancellation logistics tests failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Construction cancellation logistics tests passed.")
	get_tree().quit(0)


func _test_partial_cancellation_releases_materials_and_reservations_once() -> void:
	var city_world := _reset_fixture()
	var site := _create_material_site(
		Vector2i(12, 10),
		{
			WorldData.RESOURCE_LUMBER: 8,
			WorldData.RESOURCE_STONE: 4,
		}
	)
	var site_id := int(site.get("id", -1))
	_expect(site_id > 0, "The partial-cancellation fixture must create a site.")

	if site_id <= 0:
		return

	_expect(
		CityConstructionSystem.add_resource_to_city_construction_site_for_city_state(
			test_city_state,
			site_id,
			WorldData.RESOURCE_LUMBER,
			3
		) == 3,
		"The partial-cancellation fixture must deliver three lumber."
	)
	var source_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(test_city_state, {
		"tile_position": Vector2i(20, 10),
		"resource": WorldData.RESOURCE_STONE,
		"amount_delta": 7,
	})
	var source_id := _first_ground_pile_id(source_result)
	_expect(source_id > 0, "The reservation fixture must create an ordinary source pile.")

	if source_id <= 0:
		return

	var logistics_state := test_city_state.logistics_state
	var reservation_id := 41
	var source_endpoint := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
		source_id
	)
	var destination_endpoint := (
		CityLogisticsSystem.make_city_construction_site_haul_endpoint(site_id)
	)
	logistics_state.haul_reservations[reservation_id] = {
		"id": reservation_id,
		"citizen_id": 77,
		"resource_type": WorldData.RESOURCE_STONE,
		"source": source_endpoint,
		"destination": destination_endpoint,
		"source_reserved_amount": 3,
		"destination_reserved_amount": 3,
		"destination_reserved_resources": {WorldData.RESOURCE_STONE: 3},
	}
	logistics_state.haul_reservation_id_by_citizen_id[77] = reservation_id
	logistics_state.haul_source_reserved_amount_by_key[
		_haul_source_key(source_endpoint, WorldData.RESOURCE_STONE)
	] = 3
	logistics_state.haul_destination_reserved_amount_by_key[
		_haul_endpoint_key(destination_endpoint)
	] = 3
	logistics_state.next_haul_reservation_id = 42
	logistics_state.haul_reservation_version = 9

	var lumber_before := _physical_total(WorldData.RESOURCE_LUMBER)
	var stone_before := _physical_total(WorldData.RESOURCE_STONE)
	var pile_version_before := logistics_state.ground_pile_version
	var reservation_version_before := logistics_state.haul_reservation_version

	_expect(
		CityConstructionSystemScript.cancel_city_construction_site_for_city_state(
			test_city_state,
			site_id
		),
		"Partial construction cancellation must succeed."
	)
	_expect(
		CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
			test_city_state,
			site_id
		).is_empty(),
		"Cancellation must remove the construction-site record."
	)
	_expect(
		_amount_at_tile(
			Vector2i(12, 10),
			WorldData.RESOURCE_LUMBER,
			false
		) == 3,
		"Delivered lumber must become an ordinary physical pile at the site."
	)
	_expect(
		_amount_at_tile(
			Vector2i(20, 10),
			WorldData.RESOURCE_STONE,
			false
		) == 7,
		"Reservation cleanup must not consume or relocate the source pile."
	)
	_expect(
		logistics_state.haul_reservations.is_empty()
		and logistics_state.haul_reservation_id_by_citizen_id.is_empty()
		and logistics_state.haul_source_reserved_amount_by_key.is_empty()
		and logistics_state.haul_destination_reserved_amount_by_key.is_empty(),
		"Logistics must clear every reservation registry tied to the cancelled site."
	)
	_expect(
		logistics_state.ground_pile_version == pile_version_before + 1
		and logistics_state.haul_reservation_version
		== reservation_version_before + 1,
		"Cancellation must publish pile and reservation changes exactly once."
	)
	_expect(
		_physical_total(WorldData.RESOURCE_LUMBER) == lumber_before
		and _physical_total(WorldData.RESOURCE_STONE) == stone_before,
		"Partial cancellation must conserve every physical resource."
	)
	_assert_ground_pile_integrity()

	var piles_after_first_release := logistics_state.ground_piles.duplicate(true)
	var index_after_first_release := logistics_state.ground_pile_index_by_id.duplicate(true)
	var pile_version_after_first_release := logistics_state.ground_pile_version
	var reservation_version_after_first_release := logistics_state.haul_reservation_version
	_expect(
		not CityConstructionSystemScript.cancel_city_construction_site_for_city_state(
			test_city_state,
			site_id
		)
		and CityLogisticsSystem.release_city_construction_site_materials_for_city_state(
			test_city_state,
			site_id
		) == 0,
		"Repeated cancellation and release must report an exact no-op."
	)
	_expect(
		logistics_state.ground_piles == piles_after_first_release
		and logistics_state.ground_pile_index_by_id == index_after_first_release
		and logistics_state.ground_pile_version == pile_version_after_first_release
		and logistics_state.haul_reservation_version
		== reservation_version_after_first_release,
		"Repeat protection must preserve piles, indices, and versions exactly."
	)


func _test_full_cancellation_preserves_radius_capacity_and_local_overflow() -> void:
	var city_world := _reset_fixture()
	var site_tile := Vector2i(12, 10)
	var site := _create_material_site(
		site_tile,
		{
			WorldData.RESOURCE_LUMBER: 28,
			WorldData.RESOURCE_STONE: 4,
			WorldData.RESOURCE_FISH: 5,
		}
	)
	var site_id := int(site.get("id", -1))
	_expect(site_id > 0, "The full-cancellation fixture must create a site.")

	if site_id <= 0:
		return

	var far_lumber_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(test_city_state, {
		"tile_position": Vector2i(9, 10),
		"resource": WorldData.RESOURCE_LUMBER,
		"amount_delta": CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY,
	})
	var far_lumber_id := _first_ground_pile_id(far_lumber_result)
	var full_lumber_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(test_city_state, {
		"tile_position": Vector2i(10, 10),
		"resource": WorldData.RESOURCE_LUMBER,
		"amount_delta": CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY,
	})
	var full_lumber_id := _first_ground_pile_id(full_lumber_result)
	_expect(
		CityLogisticsSystem.remove_resource_from_city_ground_pile_for_city_state(
			test_city_state,
			far_lumber_id,
			WorldData.RESOURCE_LUMBER,
			3
		) == 3,
		"The radius fixture must leave three free units exactly three tiles away."
	)
	var stone_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(test_city_state, {
		"tile_position": Vector2i(12, 8),
		"resource": WorldData.RESOURCE_STONE,
		"amount_delta": 16,
	})
	var stone_id := _first_ground_pile_id(stone_result)
	var first_fish_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(test_city_state, {
		"tile_position": Vector2i(12, 8),
		"resource": WorldData.RESOURCE_FISH,
		"amount_delta": 18,
	})
	var first_fish_id := _first_ground_pile_id(first_fish_result)
	var second_fish_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(test_city_state, {
		"tile_position": Vector2i(14, 10),
		"resource": WorldData.RESOURCE_FISH,
		"amount_delta": 18,
	})
	var second_fish_id := _first_ground_pile_id(second_fish_result)
	_expect(
		far_lumber_id > 0
		and full_lumber_id > 0
		and stone_id > 0
		and first_fish_id > 0
		and second_fish_id > 0,
		"The radius/capacity fixture must create all ordinary anchor piles."
	)
	_expect(
		CityConstructionSystem.add_resource_to_city_construction_site_for_city_state(
			test_city_state,
			site_id,
			WorldData.RESOURCE_LUMBER,
			28
		) == 28
		and CityConstructionSystem.add_resource_to_city_construction_site_for_city_state(
			test_city_state,
			site_id,
			WorldData.RESOURCE_STONE,
			4
		) == 4
		and CityConstructionSystem.add_resource_to_city_construction_site_for_city_state(
			test_city_state,
			site_id,
			WorldData.RESOURCE_FISH,
			5
		) == 5,
		"The full-cancellation fixture must deliver the entire mixed recipe."
	)

	var lumber_before := _physical_total(WorldData.RESOURCE_LUMBER)
	var stone_before := _physical_total(WorldData.RESOURCE_STONE)
	var fish_before := _physical_total(WorldData.RESOURCE_FISH)
	var logistics_state := test_city_state.logistics_state
	var pile_version_before := logistics_state.ground_pile_version

	_expect(
		CityConstructionSystemScript.cancel_city_construction_site_for_city_state(
			test_city_state,
			site_id
		),
		"Full construction cancellation must succeed."
	)
	_expect(
		_amount_for_pile_id(far_lumber_id) == 17
		and _amount_for_pile_id(full_lumber_id)
		== CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY,
		"Release-local coalescing must not chain material into a pile three tiles away."
	)
	_expect(
		_amount_at_tile(site_tile, WorldData.RESOURCE_LUMBER, false) == 28,
		"A full nearby pile must leave lumber overflow at the released pile's local tile."
	)
	_expect(
		_amount_for_pile_id(stone_id)
		== CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY
		and _amount_at_tile(site_tile, WorldData.RESOURCE_STONE, false) == 0,
		"A compatible pile exactly two tiles away must accept the released stone."
	)
	_expect(
		_amount_for_pile_id(first_fish_id)
		== CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY
		and _amount_for_pile_id(second_fish_id) == 18
		and _amount_at_tile(site_tile, WorldData.RESOURCE_FISH, false) == 3,
		"Release must select one nearby pile and keep additional overflow at the site tile."
	)
	_expect(
		logistics_state.ground_pile_version == pile_version_before + 1,
		"Full release must publish one ground-pile version change."
	)
	_expect(
		_physical_total(WorldData.RESOURCE_LUMBER) == lumber_before
		and _physical_total(WorldData.RESOURCE_STONE) == stone_before
		and _physical_total(WorldData.RESOURCE_FISH) == fish_before,
		"Full mixed-resource cancellation must conserve every physical resource."
	)
	_assert_ground_pile_integrity()


func _test_explicit_release_preserves_active_settlement_and_ordinary_ids() -> void:
	_reset_fixture()
	if test_fixture == null or test_city_state == null:
		return
	_expect(
		WorldPoliticalState.set_active_settlement(test_fixture.settlement_id),
		"The isolation fixture must present its first registered City."
	)
	if WorldPoliticalState.active_settlement_id != test_fixture.settlement_id:
		return
	var active_state := test_city_state
	var target_world := _make_city_world(TEST_WORLD_SEED + 1)
	var target_settlement := WorldPoliticalState.create_settlement({
		"name": "Pass 7 Logistics Target City",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": test_fixture.polity_id,
		"world_region_top_left": Vector2i(2, 0),
		"world_region_center": Vector2i(2, 0),
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	var target_settlement_id := int(
		target_settlement.get("id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	var target_context: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(target_settlement_id)
	)
	var target_ready := (
		target_context != null
		and WorldPoliticalState.is_registered_settlement_context(target_context)
		and WorldPoliticalState.store_city_world_for_settlement(
			target_settlement_id,
			target_world,
			TEST_WORLD_SEED + 1
		)
	)
	_expect(
		target_ready,
		"The explicit release target must be a second registered City."
	)
	if not target_ready:
		return
	var target_state: CitySettlementSimulationState = (
		target_context.get_city_simulation_state()
	)
	target_state.logistics_state.ground_piles = [
		{
			"id": 1,
			"tile_position": Vector2i(7, 5),
			"resource_type": WorldData.RESOURCE_LUMBER,
			"amount": 5,
			"construction_site_id": 91,
		},
		{
			"id": 2,
			"tile_position": Vector2i(5, 5),
			"resource_type": WorldData.RESOURCE_LUMBER,
			"amount": 17,
		},
	]
	target_state.logistics_state.ground_pile_index_by_id = {1: 0, 2: 1}
	target_state.logistics_state.next_ground_pile_id = 3
	var active_piles_before: Array = active_state.logistics_state.ground_piles.duplicate(true)
	var active_index_before: Dictionary = (
		active_state.logistics_state.ground_pile_index_by_id.duplicate(true)
	)
	var active_version_before: int = int(
		active_state.logistics_state.ground_pile_version
	)

	_expect(
		CityLogisticsSystem.release_city_construction_site_materials_for_city_state(
			target_state,
			91
		) == 5,
		"Explicit release must process the supplied settlement state."
	)
	_expect(
		int(
			CityLogisticsSystem.get_city_ground_pile_by_id_for_city_state(
				target_state,
				2
			).get("amount", 0)
		) == CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY
		and int(
			CityLogisticsSystem.get_city_ground_pile_by_id_for_city_state(
				target_state,
				1
			).get("amount", 0)
		) == 2,
		"A lower-ID released pile must fill, not replace, the nearby ordinary pile."
	)
	_expect(
		active_state.logistics_state.ground_piles == active_piles_before
		and active_state.logistics_state.ground_pile_index_by_id == active_index_before
		and active_state.logistics_state.ground_pile_version == active_version_before
		and WorldPoliticalState.active_settlement_id
		== test_fixture.settlement_id,
		"Explicit release must not mutate the visually active settlement."
	)


func _reset_fixture() -> WorldData:
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game()
	var city_world := _make_city_world(TEST_WORLD_SEED)
	test_fixture = CitySettlementTestFixtureScript.create({
		"label": "Pass 7 Logistics",
		"city_world": city_world,
		"city_seed": TEST_WORLD_SEED,
	})
	_expect(test_fixture != null, "The cancellation fixture must be created.")
	if test_fixture == null:
		return null
	test_city_state = test_fixture.city_state
	test_city_state.city_runtime_data.merge({
		"name": "Pass 7 Logistics City",
		"primary_culture_id": test_fixture.culture_id,
		"founded": true,
		"can_build": true,
	}, true)
	return city_world


func _make_city_world(seed_value: int) -> WorldData:
	var city_world := WorldData.new()
	city_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, seed_value)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.get_tile_for_internal_read(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["surface_feature"] = WorldData.CITY_SURFACE_FEATURE_NONE

	city_world.mark_tile_data_changed()
	return city_world


func _create_material_site(
	tile_position: Vector2i,
	material_recipe: Dictionary
) -> Dictionary:
	var site := CityConstructionSystemScript.create_city_construction_site_for_city_state(test_city_state, {
		"target_kind": CityConstructionSystem.CITY_CONSTRUCTION_TARGET_NEW,
		"object_type": CityObjectCatalog.CITY_OBJECT_ROAD,
		"shape_mode": CityObjectCatalog.CITY_OBJECT_SHAPE_TILE_AREA,
		"top_left": tile_position,
		"size": Vector2i.ONE,
		"footprint_tiles": [tile_position],
		"owner": "player",
		"material_recipe": material_recipe,
		"required_labor_minutes": 8,
		"maximum_workers": 1,
		"work_positions": [tile_position],
	})
	var site_id := int(site.get("id", -1))

	if site_id <= 0:
		return {}

	CityConstructionSystemScript.refresh_city_construction_site_for_city_state(
		test_city_state,
		site_id
	)
	return CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
		test_city_state,
		site_id
	)


func _physical_total(resource: String) -> int:
	return CityResourceAccountingSystem.get_total_physical_city_resource_amount_for_city_state(
		test_city_state,
		resource
	)


func _amount_at_tile(
	tile_position: Vector2i,
	resource: String,
	construction_reserved_only: bool
) -> int:
	var amount := 0

	for raw_ground_pile in CityLogisticsSystem.get_city_ground_pile_snapshot_for_city_state(
		test_city_state
	):
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if (
			ground_pile.get("tile_position") == tile_position
			and str(ground_pile.get("resource_type", WorldData.RESOURCE_NONE))
			== resource
			and (
				not construction_reserved_only
				or CityLogisticsSystem.city_ground_pile_is_construction_reserved(
					ground_pile
				)
			)
		):
			amount += maxi(int(ground_pile.get("amount", 0)), 0)

	return amount


func _amount_for_pile_id(ground_pile_id: int) -> int:
	return maxi(
		int(
			CityLogisticsSystem.get_city_ground_pile_by_id_for_city_state(
				test_city_state,
				ground_pile_id
			).get(
				"amount",
				0
			)
		),
		0
	)


func _first_ground_pile_id(add_result: Dictionary) -> int:
	for raw_placement in add_result.get("placements", []):
		if raw_placement is Dictionary:
			return int(raw_placement.get("ground_pile_id", -1))

	return -1


func _haul_endpoint_key(endpoint: Dictionary) -> String:
	return str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	) + ":" + str(int(endpoint.get("id", -1)))


func _haul_source_key(endpoint: Dictionary, resource: String) -> String:
	return _haul_endpoint_key(endpoint) + ":" + resource


func _assert_ground_pile_integrity() -> void:
	var logistics_state := test_city_state.logistics_state
	var observed_ids: Dictionary = {}

	for pile_index in range(logistics_state.ground_piles.size()):
		var raw_ground_pile = logistics_state.ground_piles[pile_index]
		var valid := raw_ground_pile is Dictionary
		var ground_pile: Dictionary = raw_ground_pile if valid else {}
		var ground_pile_id := int(ground_pile.get("id", -1))
		var amount := int(ground_pile.get("amount", 0))
		valid = (
			valid
			and ground_pile_id > 0
			and not observed_ids.has(ground_pile_id)
			and int(
				logistics_state.ground_pile_index_by_id.get(
					ground_pile_id,
					-1
				)
			) == pile_index
			and amount > 0
			and amount <= CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY
			and not CityLogisticsSystem.city_ground_pile_is_construction_reserved(
				ground_pile
			)
		)
		_expect(valid, "Released piles must preserve capacity, ownership, and ID indices.")
		observed_ids[ground_pile_id] = true

	_expect(
		observed_ids.size() == logistics_state.ground_pile_index_by_id.size(),
		"The ground-pile index must remain a complete bijection after release."
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
