from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORLD_DATA = ROOT / "scripts/world/simulation/WorldData.gd"
BASE_TRANSFORM = ROOT / "ci/one_time_extract_city_work_api.py"

text = WORLD_DATA.read_text(encoding="utf-8")
old = "\tvar command := get_city_player_command_by_id(target_object_id)"
new = (
    "\tvar command := "
    "WorldPoliticalState.get_current_city_work_state()"
    ".get_player_command_by_id(target_object_id)"
)
count = text.count(old)
if count != 1:
    raise RuntimeError(
        "remaining WorldData player-command lookup: "
        f"expected exactly one match, found {count}"
    )
WORLD_DATA.write_text(text.replace(old, new, 1), encoding="utf-8")

# Execute the assertion-driven base transform after removing the one legitimate
# legacy internal lookup that lived outside the extracted primitive region.
code = compile(
    BASE_TRANSFORM.read_text(encoding="utf-8"),
    str(BASE_TRANSFORM),
    "exec",
)
exec(code, {"__file__": str(BASE_TRANSFORM), "__name__": "__main__"})
