from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


repo = Path(__file__).resolve().parents[1]
world_data_path = repo / "scripts/world/simulation/WorldData.gd"
political_state_path = repo / "scripts/world/simulation/WorldPoliticalState.gd"

world_data = world_data_path.read_text(encoding="utf-8")

proxy_specs = [
    ("city_player_commands", "Array", "player_commands"),
    ("city_player_command_index_by_id", "Dictionary", "player_command_index_by_id"),
    ("city_player_command_id_by_tile", "Dictionary", "player_command_id_by_tile"),
    ("next_city_player_command_id", "int", "next_player_command_id"),
    ("next_city_player_command_group_id", "int", "next_player_command_group_id"),
    ("city_work_orders", "Dictionary", "work_orders"),
    ("city_work_order_id_by_source_key", "Dictionary", "work_order_id_by_source_key"),
    ("next_city_work_order_id", "int", "next_work_order_id"),
    ("city_player_command_version", "int", "player_command_version"),
    ("city_work_order_version", "int", "work_order_version"),
]

initializers = {
    "Array": "[]",
    "Dictionary": "{}",
    "int": "0",
}
# The three next-ID fields historically start at one rather than zero.
initializers["next_city_player_command_id"] = "1"
initializers["next_city_player_command_group_id"] = "1"
initializers["next_city_work_order_id"] = "1"

for world_name, type_name, state_name in proxy_specs:
    initializer = initializers.get(world_name, initializers[type_name])
    old = f"static var {world_name}: {type_name} = {initializer}"
    new = (
        f"static var {world_name}: {type_name}:\n"
        "\tget:\n"
        f"\t\treturn WorldPoliticalState.get_current_city_work_state().{state_name}\n"
        "\tset(value):\n"
        f"\t\tWorldPoliticalState.get_current_city_work_state().{state_name} = value"
    )
    world_data = replace_once(
        world_data,
        old,
        new,
        f"WorldData proxy {world_name}",
    )

world_data_path.write_text(world_data, encoding="utf-8")

political_state = political_state_path.read_text(encoding="utf-8")
political_state = replace_once(
    political_state,
    'const CitySettlementSimulationStateScript = preload(\n\t"res://scripts/city/simulation/CitySettlementSimulationState.gd"\n)\n',
    'const CitySettlementSimulationStateScript = preload(\n\t"res://scripts/city/simulation/CitySettlementSimulationState.gd"\n)\nconst CityWorkStateScript = preload(\n\t"res://scripts/city/simulation/CityWorkState.gd"\n)\n',
    "WorldPoliticalState CityWorkState preload",
)
political_state = replace_once(
    political_state,
    'var _foundation_world_fingerprint: String = ""\n',
    'var _foundation_world_fingerprint: String = ""\nvar _unbound_city_work_state = CityWorkStateScript.new()\n',
    "WorldPoliticalState fallback state",
)
political_state = replace_once(
    political_state,
    '\t_foundation_world_fingerprint = ""\n\n\nfunc synchronize_foundation_with_world_data() -> bool:',
    '\t_foundation_world_fingerprint = ""\n\t_unbound_city_work_state = CityWorkStateScript.new()\n\n\nfunc synchronize_foundation_with_world_data() -> bool:',
    "WorldPoliticalState fallback reset",
)
political_state = replace_once(
    political_state,
    'func get_active_city_simulation_state():\n\treturn get_city_simulation_state(active_settlement_id)\n\n\nfunc get_polity_snapshot()',
    'func get_active_city_simulation_state():\n\treturn get_city_simulation_state(active_settlement_id)\n\n\n# Compatibility owner for code paths that run before a settlement context is\n# established (primarily low-level tests and reset/setup code). Runtime city\n# work always resolves to the active settlement state once one exists.\nfunc get_current_city_work_state():\n\tvar active_city_state = get_active_city_simulation_state()\n\tif (\n\t\tactive_city_state != null\n\t\tand active_city_state.work_state is CityWorkState\n\t):\n\t\treturn active_city_state.work_state\n\treturn _unbound_city_work_state\n\n\nfunc get_polity_snapshot()',
    "WorldPoliticalState current work-state accessor",
)
political_state_path.write_text(political_state, encoding="utf-8")

print("Applied one-time CityWorkState storage extraction.")
