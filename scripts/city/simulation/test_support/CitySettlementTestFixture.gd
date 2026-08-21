extends RefCounted
class_name CitySettlementTestFixture

# Reusable low-level test fixture for code that requires a real registered city
# owner. A fixture owns the process-wide test registry for its lifetime, so
# cleanup always restores a deterministic empty session.

var culture: Dictionary = {}
var polity: Dictionary = {}
var settlement: Dictionary = {}
var settlement_context: SettlementSimulationContext = null
var city_state: CitySettlementSimulationState = null

var culture_id: int = CultureData.INVALID_CULTURE_ID
var polity_id: int = PolityData.INVALID_POLITY_ID
var settlement_id: int = SettlementData.INVALID_SETTLEMENT_ID

var _cleaned_up: bool = false


static func create(values: Dictionary = {}):
	var fixture = load(
		"res://scripts/city/simulation/test_support/CitySettlementTestFixture.gd"
	).new()
	if fixture._create_registered_city(values):
		return fixture
	fixture.cleanup()
	return null


func is_registered() -> bool:
	return (
		not _cleaned_up
		and settlement_context != null
		and city_state != null
		and WorldPoliticalState.is_registered_settlement_context(
			settlement_context
		)
	)


func cleanup() -> void:
	if _cleaned_up:
		return
	_cleaned_up = true
	WorldData.reset_runtime_session_state()

	culture = {}
	polity = {}
	settlement = {}
	settlement_context = null
	city_state = null
	culture_id = CultureData.INVALID_CULTURE_ID
	polity_id = PolityData.INVALID_POLITY_ID
	settlement_id = SettlementData.INVALID_SETTLEMENT_ID


func _create_registered_city(values: Dictionary) -> bool:
	WorldData.reset_runtime_session_state()

	var label := str(values.get("label", "Explicit Test")).strip_edges()
	if label.is_empty():
		label = "Explicit Test"

	culture = WorldData.create_culture(
		str(values.get("culture_name", label + " Culture"))
	)
	culture_id = int(culture.get("id", CultureData.INVALID_CULTURE_ID))
	if culture_id <= 0:
		return false

	polity = WorldPoliticalState.create_polity({
		"name": str(values.get("polity_name", label + " Polity")),
		"polity_type": str(
			values.get("polity_type", PolityData.POLITY_TYPE_KINGDOM)
		),
		"primary_culture_id": culture_id,
	})
	polity_id = int(polity.get("id", PolityData.INVALID_POLITY_ID))
	if polity_id <= 0:
		return false

	settlement = WorldPoliticalState.create_settlement({
		"name": str(values.get("settlement_name", label + " City")),
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": values.get(
			"world_region_top_left",
			Vector2i.ZERO
		),
		"world_region_center": values.get(
			"world_region_center",
			Vector2i.ZERO
		),
		"world_region_size": int(values.get("world_region_size", 1)),
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	settlement_id = int(
		settlement.get("id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	if settlement_id <= 0:
		return false

	if bool(values.get("is_player_polity", true)):
		WorldPoliticalState.player_polity_id = polity_id
	if (
		bool(values.get("is_capital", true))
		and not WorldPoliticalState.set_polity_capital(
			polity_id,
			settlement_id
		)
	):
		return false
	settlement_context = WorldPoliticalState.get_settlement_context(
		settlement_id
	)
	if settlement_context == null:
		return false
	city_state = settlement_context.get_city_simulation_state()
	if city_state == null:
		return false

	var city_world = values.get("city_world")
	if city_world != null:
		if not WorldPoliticalState.store_city_world_for_settlement(
			settlement_id,
			city_world,
			int(values.get("city_seed", 0))
		):
			return false

	return is_registered()
