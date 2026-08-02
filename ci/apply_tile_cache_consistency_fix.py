from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / "ci" / ".tile_cache_consistency_fix_applied"


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


if MARKER.exists():
    print("Tile cache consistency fix already applied.")
    raise SystemExit(0)

renderer = ROOT / "scripts/city/rendering/CityRenderer.gd"
smoke_test = ROOT / "scripts/city/rendering/CityRendererRefactorSmokeTest.gd"

replace_once(
    renderer,
    "\t\tcity_world.consume_city_surface_feature_changes()\n\t\treturn\n",
    "\t\tcity_world.consume_city_surface_feature_changes()\n"
    "\t\t# Tile-data edits can change biome, terrain, resources, or fertility.\n"
    "\t\t# Rebuild only the visible mode synchronously, then warm the remaining\n"
    "\t\t# map textures incrementally so the display and saved cache cannot go stale.\n"
    "\t\trebuild_city_terrain_texture()\n"
    "\t\tupdate_city_map_mode_button_visuals()\n"
    "\t\treturn\n",
    "refresh map textures after tile-data edits",
)

replace_once(
    smoke_test,
    "\tif not bool(validation.get(\"valid\", false)):\n"
    "\t\tfor error in validation.get(\"errors\", []):\n"
    "\t\t\tpush_error(str(error))\n\n"
    "\tvar cached_tree_multimesh_id := (\n",
    "\tif not bool(validation.get(\"valid\", false)):\n"
    "\t\tfor error in validation.get(\"errors\", []):\n"
    "\t\t\tpush_error(str(error))\n\n"
    "\t# Several fixtures deliberately edit authoritative tile data. Complete the\n"
    "\t# resulting incremental refresh before testing scene re-entry so the cache\n"
    "\t# represents the latest city version rather than an intentionally stale one.\n"
    "\trenderer.city_texture_cache.finish_warmup()\n"
    "\trenderer.update_city_map_mode_button_visuals()\n"
    "\t_expect(\n"
    "\t\trenderer.has_valid_saved_city_map_texture_cache(renderer.city_world),\n"
    "\t\t\"The latest tile-data version must finish with a complete saved map cache.\"\n"
    "\t)\n\n"
    "\tvar cached_tree_multimesh_id := (\n",
    "complete current-version cache before re-entry assertion",
)

MARKER.write_text("Applied tile cache consistency fix.\n", encoding="utf-8")
print("Applied tile cache consistency fix.")
