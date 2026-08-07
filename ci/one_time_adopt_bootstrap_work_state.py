from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


repo = Path(__file__).resolve().parents[1]
path = repo / "scripts/world/simulation/WorldPoliticalState.gd"
text = path.read_text(encoding="utf-8")

text = replace_once(
    text,
    '''\tvar fingerprint := _build_foundation_world_fingerprint()\n\tif fingerprint == _foundation_world_fingerprint:\n\t\treturn _has_live_foundation_registry()\n\n\treset_state()\n''',
    '''\tvar fingerprint := _build_foundation_world_fingerprint()\n\tif fingerprint == _foundation_world_fingerprint:\n\t\treturn _has_live_foundation_registry()\n\n\t# Some low-level simulation/bootstrap paths can create local work before the\n\t# political registry exists. Preserve that pre-context state exactly once\n\t# when the first City settlement adopts the current city simulation. Never\n\t# carry it across an already-live political registry into another world.\n\tvar should_adopt_unbound_work_state := not _has_live_foundation_registry()\n\tvar unbound_work_state_to_adopt = _unbound_city_work_state\n\n\treset_state()\n''',
    "capture unbound bootstrap work state",
)

text = replace_once(
    text,
    '''\tif capital_state == null:\n\t\treset_state()\n\t\treturn false\n\tcapital_state.capture_from_world_data()\n''',
    '''\tif capital_state == null:\n\t\treset_state()\n\t\treturn false\n\tif should_adopt_unbound_work_state:\n\t\tcapital_state.work_state = unbound_work_state_to_adopt\n\tcapital_state.capture_from_world_data()\n''',
    "adopt unbound bootstrap work state",
)

path.write_text(text, encoding="utf-8")
print("Added bootstrap CityWorkState adoption.")
