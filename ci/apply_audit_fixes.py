from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / "ci" / ".audit_fixes_applied"


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


if MARKER.exists():
    print("Audited fixes already applied; nothing to do.")
    raise SystemExit(0)

work_system = ROOT / "scripts/city/simulation/systems/CityWorkSystem.gd"
construction_system = ROOT / "scripts/city/simulation/systems/CityConstructionSystem.gd"
work_test = ROOT / "scripts/city/simulation/CityUnifiedWorkSystemTest.gd"
workflow = ROOT / ".github/workflows/godot-ci.yml"

replace_once(
    work_system,
    "\trefresh_work_order_runtimes([order_id])\n"
    "\treturn get_city_work_order_by_id(order_id)\n\n\n"
    "static func refresh_work_order_runtimes(raw_order_ids: Array) -> void:\n",
    "\trefresh_work_order_runtimes([order_id])\n"
    "\treturn get_city_work_order_by_id(order_id)\n\n\n"
    "# Construction-site removal is an atomic lifecycle boundary. Removing the\n"
    "# matching parent order here prevents validators and schedulers from ever\n"
    "# observing a dangling order between site completion/cancellation and the\n"
    "# next broad work-board synchronization.\n"
    "static func remove_construction_work_order_for_site(site_id: int) -> void:\n"
    "\tif site_id <= 0:\n"
    "\t\treturn\n\n"
    "\tvar source_key := _make_construction_source_key(site_id)\n"
    "\tvar order_id := int(\n"
    "\t\tWorldData.city_work_order_id_by_source_key.get(source_key, -1)\n"
    "\t)\n\n"
    "\tif order_id > 0:\n"
    "\t\t_remove_order_record(order_id)\n\n\n"
    "static func refresh_work_order_runtimes(raw_order_ids: Array) -> void:\n",
    "add construction-order lifecycle removal",
)

replace_once(
    construction_system,
    "\tvar site: Dictionary = WorldData.city_construction_sites[site_index]\n\n"
    "\tfor raw_tile in site.get(\"footprint_tiles\", []):\n",
    "\tvar site: Dictionary = WorldData.city_construction_sites[site_index]\n\n"
    "\t# The site and its parent order are one logical record. Remove the order\n"
    "\t# in the same operation so completion and direct cancellation leave a\n"
    "\t# valid state even before the next work-board synchronization.\n"
    "\tCityWorkSystem.remove_construction_work_order_for_site(site_id)\n\n"
    "\tfor raw_tile in site.get(\"footprint_tiles\", []):\n",
    "remove parent order with construction site",
)

replace_once(
    work_test,
    "\tvar blocked_road_id := int(blocked_road.get(\"id\", -1))\n\n"
    "\t_expect(\n"
    "\t\tblocked_road_id > 0,\n"
    "\t\t\"The rebalance fixture must create a material-blocked road.\"\n"
    "\t)\n"
    "\t_expect(\n"
    "\t\t_get_assignment_snapshot(left_builder_id)\n",
    "\tvar blocked_road_id := int(blocked_road.get(\"id\", -1))\n\n"
    "\t_expect(\n"
    "\t\tblocked_road_id > 0,\n"
    "\t\t\"The rebalance fixture must create a material-blocked road.\"\n"
    "\t)\n"
    "\tCityWorkSystemScript.synchronize_player_work_board()\n"
    "\tvar blocked_blueprint_switch_count := (\n"
    "\t\tCityConstructionSystemScript\n"
    "\t\t.rebalance_uncommitted_construction_workers(blocked_road_id)\n"
    "\t)\n"
    "\t_expect(\n"
    "\t\tblocked_blueprint_switch_count == 0\n"
    "\t\tand _get_assignment_snapshot(left_builder_id)\n",
    "make blocked-blueprint fixture invoke production rebalance trigger",
)

replace_once(
    work_test,
    "\tif near_site_id <= 0:\n"
    "\t\treturn\n\n"
    "\tvar near_order := _find_order(\n",
    "\tif near_site_id <= 0:\n"
    "\t\treturn\n\n"
    "\t# This synthetic material-requiring road bypasses the production road\n"
    "\t# placement API, so the test must explicitly invoke the same scheduling\n"
    "\t# boundary that production placement invokes.\n"
    "\tCityWorkSystemScript.synchronize_player_work_board()\n"
    "\tvar switched_to_near := (\n"
    "\t\tCityConstructionSystemScript\n"
    "\t\t.rebalance_uncommitted_construction_workers(near_site_id)\n"
    "\t)\n\n"
    "\tvar near_order := _find_order(\n",
    "invoke rebalance for synthetic nearby fixture",
)

replace_once(
    work_test,
    "\t_expect(\n"
    "\t\tstr(left_after_near_blueprint.get(\"kind\", \"\"))\n"
    "\t\t== WorldData.CITY_CITIZEN_TASK_KIND_HAUL\n",
    "\t_expect(\n"
    "\t\tswitched_to_near == 1\n"
    "\t\tand str(left_after_near_blueprint.get(\"kind\", \"\"))\n"
    "\t\t== WorldData.CITY_CITIZEN_TASK_KIND_HAUL\n",
    "assert exactly one nearby reassignment",
)

replace_once(
    work_test,
    "\tvar material_blocked_site := _create_material_blocked_site(\n"
    "\t\tVector2i(20, 4),\n"
    "\t\t1\n"
    "\t)\n"
    "\tvar reassigned_task := WorldData.get_city_citizen_current_task(citizen_id)\n",
    "\tvar material_blocked_site := _create_material_blocked_site(\n"
    "\t\tVector2i(20, 4),\n"
    "\t\t1\n"
    "\t)\n"
    "\t# The helper intentionally creates a low-level synthetic site; mirror the\n"
    "\t# production placement boundary before checking blocked reassignment.\n"
    "\tCityWorkSystemScript.synchronize_player_work_board()\n"
    "\tvar blocked_reassignment_count := (\n"
    "\t\tCityConstructionSystemScript\n"
    "\t\t.rebalance_uncommitted_construction_workers(\n"
    "\t\t\tint(material_blocked_site.get(\"id\", -1))\n"
    "\t\t)\n"
    "\t)\n"
    "\tvar reassigned_task := WorldData.get_city_citizen_current_task(citizen_id)\n",
    "invoke rebalance for blocked-worker synthetic fixture",
)

replace_once(
    work_test,
    "\t_expect(\n"
    "\t\tint(material_blocked_site.get(\"id\", -1)) > 0\n"
    "\t\tand int(reassigned_task.get(\"work_order_id\", -1))\n",
    "\t_expect(\n"
    "\t\tint(material_blocked_site.get(\"id\", -1)) > 0\n"
    "\t\tand blocked_reassignment_count == 1\n"
    "\t\tand int(reassigned_task.get(\"work_order_id\", -1))\n",
    "assert blocked worker switches exactly once",
)

replace_once(
    workflow,
    "on:\n"
    "  push:\n"
    "    branches:\n"
    "      - main\n"
    "      - \"ci/**\"\n"
    "      - \"paladin/**\"\n"
    "  pull_request:\n",
    "on:\n"
    "  push:\n"
    "    branches:\n"
    "      - main\n"
    "  pull_request:\n",
    "remove duplicate branch and pull-request CI runs",
)

MARKER.write_text(
    "Applied construction lifecycle fix and updated synthetic rebalance fixtures.\n",
    encoding="utf-8",
    newline="\n",
)
print("Applied audited fixes successfully.")
