# Godot 4.7.1 migration plan

This branch isolates the engine migration from gameplay development.

## Automated scope

- Update the project feature marker from Godot 4.4 to Godot 4.7.
- Pin GitHub Actions to Godot 4.7.1.
- Import the project with Godot 4.7.1.
- Run the static GDScript/resource audit.
- Run every `*Test.tscn` scene.
- Boot the configured main scene for a fixed frame count.

## Preserved invariants

- No gameplay rules are intentionally changed.
- No simulation cadence or system order is intentionally changed.
- No rendering architecture is intentionally changed beyond the engine version.
- The migration remains isolated on `migration/godot-4.7.1` until Windows visual validation is complete.

## Required local validation before merge

1. Open a separate physical copy of Paladin with the standard Godot 4.7.1 Windows build.
2. Confirm the project imports without editor-reported errors.
3. Generate a world and verify map controls.
4. Select and found a region, then enter the city.
5. Verify roads, construction, citizens, hunger, employment, hauling, and world/city switching.
6. Run long enough to confirm the former intermittent freeze does not occur.

The branch should not be merged until this local Windows validation is confirmed.
