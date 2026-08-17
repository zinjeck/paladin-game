extends RefCounted
class_name CityPresentationBinding

# Non-owning presentation identity shared by CityRenderer and every helper it
# owns. Authoritative gameplay data remains inside CitySettlementSimulationState.

var settlement_context: SettlementSimulationContext
var city_state: CitySettlementSimulationState
var settlement_id: int = SettlementData.INVALID_SETTLEMENT_ID
var city_world: WorldData
var city_seed: int = 0
var generation: int = 0


func configure(
	context: SettlementSimulationContext,
	binding_generation: int
) -> bool:
	clear()
	if (
		context == null
		or binding_generation <= 0
		or not context.supports_city_simulation()
		or not WorldPoliticalState.is_registered_settlement_context(context)
	):
		return false

	var target_state: CitySettlementSimulationState = (
		context.get_city_simulation_state()
	)
	if (
		target_state == null
		or not target_state.city_world is WorldData
		or target_state.city_world.width <= 0
		or target_state.city_world.height <= 0
		or target_state.city_seed <= 0
	):
		return false

	settlement_context = context
	city_state = target_state
	settlement_id = context.settlement_id
	city_world = target_state.city_world
	city_seed = target_state.city_seed
	generation = binding_generation
	return true


func clear() -> void:
	settlement_context = null
	city_state = null
	settlement_id = SettlementData.INVALID_SETTLEMENT_ID
	city_world = null
	city_seed = 0
	generation = 0


func is_valid() -> bool:
	return (
		settlement_context != null
		and city_state != null
		and settlement_id > 0
		and generation > 0
		and city_world != null
		and city_seed > 0
		and WorldPoliticalState.is_registered_settlement_context(
			settlement_context
		)
		and settlement_context.settlement_id == settlement_id
		and is_same(
			settlement_context.get_city_simulation_state(),
			city_state
		)
		and is_same(city_state.city_world, city_world)
		and city_state.city_seed == city_seed
	)


func matches_context(context: SettlementSimulationContext) -> bool:
	return (
		is_valid()
		and context != null
		and is_same(settlement_context, context)
		and context.settlement_id == settlement_id
	)


func matches_binding(other: CityPresentationBinding) -> bool:
	return (
		is_valid()
		and other != null
		and other.is_valid()
		and is_same(self, other)
		and generation == other.generation
	)
