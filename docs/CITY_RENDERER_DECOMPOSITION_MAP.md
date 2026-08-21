# CityRenderer decomposition map

Status: implemented and mechanically ratcheted on 2026-08-20. `CityRenderer.gd` is 2,763 physical lines and 145 top-level functions, down from 8,383 lines and 288 functions. It declares 58 plain top-level variables, two annotated exported variables, and 19 constants: 79 top-level var-plus-const declarations. The mechanically checked field inventory therefore contains 60 names.

`CityRenderer` is now the settlement-view scene facade for the detailed backend, not the owner of a city simulation. Stateful presentation, interactions, diagnostics, panels, infrastructure, natural features, and citizen visuals live in existing or settlement-neutral components. The name “city” remains where a component truthfully depends on the currently implemented city-detail backend; reusable boundaries use “settlement.”

## Confirmed current behavior and timing

`configure_initial_settlement_presentation()` is the canonical pre-tree entry. `GameSession.show_settlement_view()` selects a registered target and calls the settlement-neutral lifecycle. A missing, unregistered, or unsupported detailed target leaves the renderer disabled and hidden. The city-named lifecycle functions are compatibility facades for the current detailed backend.

Rebinding is transactional. The facade creates a fresh immutable token, runs every helper's non-mutating preflight, commits the same exact token to every helper and the city-specific invalidation tracker, then publishes facade aliases. If a helper fails after preflight, `_recover_city_presentation_binding_after_failed_commit()` reserves the failed generation and restores the prior exact context through a fresh, higher-generation token. Completed-assembly validation failure follows the same monotonic restoration rule and restores retained natural-feature resources through their exact-source cache. If both commit and recovery fail, `_fail_city_presentation_closed()` invalidates pending reveals and disables the mixed presentation. A/B/A, partial-helper-failure, double-failure, hidden-reveal, pending-reveal, exact natural-feature restoration, and gameplay-snapshot regressions cover these paths.

The facade still owns scene lifecycle order, Godot input entry points, camera and terrain assembly, retained-layer composition, redraw scheduling, and atomic reveal. Draw order is unchanged: workplace preview at z -1; infrastructure, roads, sites, piles, zones, and debug background at z 0; citizens at z 10; interactions, commands, selections, placement previews, hover, and debug labels at z 20. `CityRenderLayer` owns per-layer timing measurement.

The final facade budgets are 2,800 physical lines, 155 top-level functions, and 90 top-level var-plus-const declarations. Static audit failure is required before any limit can be exceeded.

## Binding and authority contract

`SettlementPresentationBinding` is an immutable, one-shot, non-owning identity token for one exact registered settlement. It snapshots settlement context, settlement ID, polity ID, settlement type, backend kind, backend owner, and generation. Its public properties are read-only views. `can_rebind()` is pure, `rebind()` can succeed only once, and `reset()` invalidates the token without lowering its accepted-generation high-water mark.

Backend data is explicit capability data rather than universal settlement data. `CityPresentationBinding` is the current city-detail adapter and advertises `CAPABILITY_CITY_DETAIL`, `CAPABILITY_SETTLEMENT_WORLD`, and `CAPABILITY_DETERMINISTIC_SEED` only after exact validation. A generic village or outpost is a valid settlement identity for the neutral base. It has no invented city capability, and every current city-detail consumer rejects it cleanly without replacing its previous presentation.

Presentation components may query only the exact state/capabilities supplied by their token. They may not discover an active, current, or presented settlement; receive `CityRenderer`; branch on settlement type; repair simulation owners; or issue implicit no-target commands. `CityPresentationInvalidationTracker` remains honestly city-specific because it observes versions and exact owner identities from the current city-detail backend. It never consumes events, rebuilds caches, redraws, or mutates gameplay.

Dependencies are narrow, explicit, and non-owning. Mutable values in a presenter are UI state or exact-source presentation caches, never authoritative settlement data.

The renderer has no direct dependency on resource-container, citizen-runtime, citizen-registry, object, construction, logistics, work, assignment, employment, or workplace-production gameplay systems. Placement commits go through `CityObjectSystem` behind `SettlementPlacementController`; debug mutations go through structured, exact-token methods on `CityDebugPresentation`.

The city-specific tracker surface remains deliberately narrow: `can_rebind_city_presentation`, `rebind_city_presentation`, `is_bound_to_city_presentation`, `reset`, `reset_observations`, `accepts_generation`, `capture_current_versions`, `create_change_flags`, `collect_city_state_change_flags`, and `collect_city_world_version_change_flags`.

## Current component boundaries

| Implemented owner | Confirmed responsibility and dependencies | Rebind and reset contract |
| --- | --- | --- |
| `CityRenderer` | Scene lifecycle, exact binding transaction, input priority, layer composition, camera/terrain orchestration, and reveal. Depends only on narrow presentation owners and session/clock services. | Rebind distributes one fresh token atomically; reset/clear cancels presentation interactions and observations only. |
| `SettlementPresentationBinding` | Universal registered settlement identity and named backend-capability gateway. | Rebind is immutable and one-shot; reset clears identity while preserving the generation high-water mark. |
| `CityPresentationBinding` | Honest adapter for the city-detail state, world, and deterministic seed capabilities. | Rebind validates the exact city backend through the base; reset clears adapter capability snapshots. |
| `CityPresentationInvalidationTracker` | Exact city-detail owner/version observations and pure change flags. | Rebind accepts one newer city token; reset clears observations without lowering its high-water mark. |
| `Camera` | Settlement-keyed position/zoom retention and world-bound camera configuration. | Rebind stores the previous target and restores the next; reset/clear disables target-specific observation. |
| `MapTextureCache` | Exact-world terrain texture setup, view-mode cache lookup, and retained terrain sprite inputs. | Rebind receives exact world/version/payload identity; reset/clear invalidates mismatched cached sources. |
| `SettlementNaturalFeaturePresenter` | Retained tree/rock nodes, multimeshes, bounded exact-source cache, incremental removals, and view visibility. | Rebind uses the exact immutable settlement presentation token; reset clears retained indices without lowering generation acceptance. |
| `SettlementInfrastructurePresenter` | Completed objects, roads, construction sites, and ground-pile drawing. | Rebind requires the city-detail capability through a neutral token; reset drops only presentation identity. |
| `CityCitizenMovementPresentation` | Cosmetic movement synchronization, citizen/cargo buffers, geometry, and drawing. | Rebind requires an explicit city-detail capability and tile size; reset clears cosmetic state and preserves the high-water mark. |
| `SettlementPlacementController` | Object placement, road drag/preview, validation, and explicit commit routing. | Rebind requires an explicit capability and clears previews; reset cancels interaction state without commands. |
| `SettlementSelectionController` | Hover, canonical selected entity, drag geometry, hit testing, and highlights. | Rebind clears selection/hover after pure preflight; reset clears transient state and preserves the high-water mark. |
| `SettlementCommandController` | Command tools, cancel mode, command drag, preview, explicit commits, and overlay drawing. | Rebind clears command interaction state after pure preflight; reset issues no gameplay command. |
| `SettlementUiController` | Bottom chrome, object/build/map/command menus, resource bar, layout, and typed controller coordination. | Rebind refreshes one exact token; reset hides chrome without invoking actions. Exactly four callbacks cross the facade. |
| `CityInformationPanel` | Settlement title, clock, population, and resource summary presentation. | Rebind accepts the neutral token and required city capability; reset clears its UI binding while preserving high-water. |
| `CityObjectPanelAnchor` | Citizen, object, construction, storage, and workplace panels plus viewport-safe world attachment. | Rebind accepts the neutral token and tile size; reset clears panels and target identity only. |
| `CityDebugPresentation` | Diagnostic panels, selected debug tile, navigation probes/path, debug drawing, and structured debug command ports. | Rebind validates one exact city token and debug helper; reset clears diagnostic presentation while preserving high-water. |
| `CityWorkplaceZoneOverlayCache` | Selected/active workplace zone geometry keyed by exact owner and input identity. | Rebind validates one exact city token; reset clears cached overlays without gameplay mutation. |
| `CityRenderLayer` | Retained draw callbacks, z ordering, redraw entry, and per-layer timing metrics. | Facade rebind hides/reveals layers atomically; reset/clear retires callbacks with the layer node. |

## Complete field inventory

Each source field is assigned exactly once below. A field listed under a component is either that component reference, a narrow compatibility view of its state, or facade instrumentation for calls into it.

### `CityRenderer`

`local_tiles_per_world_tile`, `city_tile_size`, `session_prepared_city_payload`, `initial_city_presentation_configured`, `session_view_active`, `city_layers_have_been_presented`, `city_presentation_rebind_generation`, `city_presentation_rebind_pending`, `city_last_rebind_duration_usec`, `city_initialization_duration_usec`, `city_generation_duration_usec`.

### `SettlementPresentationBinding`

No CityRenderer top-level field remains assigned here.

### `CityPresentationBinding`

`city_presentation_binding`, `city_presentation_binding_generation`, `bound_settlement_context`, `bound_city_state`, `bound_city_settlement_id`, `city_world`, `city_seed`.

### `CityPresentationInvalidationTracker`

`city_presentation_invalidation_tracker`.

### `Camera`

`camera`.

### `MapTextureCache`

`city_terrain_texture`, `city_terrain_sprite`, `city_texture_cache`, `city_map_texture_setup_duration_usec`, `city_map_texture_cache_reused_on_entry`.

### `SettlementNaturalFeaturePresenter`

`settlement_natural_feature_presenter`, `city_natural_feature_setup_duration_usec`, `city_natural_feature_cache_reused_on_entry`.

### `SettlementInfrastructurePresenter`

`settlement_infrastructure_presenter`.

### `CityCitizenMovementPresentation`

`city_citizen_movement_presentation`.

### `SettlementPlacementController`

`settlement_placement_controller`, `is_road_placement_active`, `is_road_dragging`, `road_preview_tiles`, `road_preview_lookup`.

### `SettlementSelectionController`

`settlement_selection_controller`, `hovered_city_tile`, `selected_city_entity_kind`, `selected_city_entity_id`, `selected_city_object_id`, `selected_city_citizen_id`, `selected_city_construction_site_id`, `is_object_selection_dragging`.

### `SettlementCommandController`

`settlement_command_controller`.

### `SettlementUiController`

`ui_layer`, `ui_root`, `settlement_ui_controller`.

### `CityInformationPanel`

`city_information_ui`.

### `CityObjectPanelAnchor`

`settlement_entity_panel_presentation`.

### `CityDebugPresentation`

`city_debug_presentation`.

### `CityWorkplaceZoneOverlayCache`

`active_workplace_preview_refresh_pending`, `workplace_zone_overlay_cache`.

### `CityRenderLayer`

`city_presentation_draw_count`, `city_presentation_last_draw_duration_usec`, `city_presentation_total_draw_duration_usec`, `city_presentation_last_draw_layer`, `city_active_workplace_preview_render_layer`, `city_background_render_layer`, `city_citizen_render_layer`, `city_interaction_render_layer`.

## Complete function inventory

Each remaining facade function is assigned exactly once. Component-assigned names are intentionally thin routing or compatibility seams; state and substantive behavior live in the named owner.

### `CityRenderer`

`_ready`, `set_session_view_active`, `_city_presentation_interactions_are_cleared`, `_clear_city_presentation_interactions`, `_set_descendant_canvas_layers_visible`, `get_game_session_controller`, `_process`, `_process_texture_cache_and_camera`, `_update_active_city_interaction_state`, `_apply_city_change_refreshes`, `_input`, `_unhandled_input`, `connect_simulation_clock_signals`, `_exit_tree`.

### `SettlementPresentationBinding`

`configure_initial_settlement_presentation`, `can_rebind_settlement_presentation`, `rebind_settlement_presentation`, `validate_settlement_presentation_binding`, `get_settlement_presentation_binding`.

### `CityPresentationBinding`

`configure_initial_city_presentation`, `_bind_city_presentation_references`, `_recover_city_presentation_binding_after_failed_commit`, `_fail_city_presentation_closed`, `_publish_city_presentation_binding`, `_bind_city_presentation_helpers`, `_can_bind_city_presentation_helpers`, `_has_valid_bound_city_presentation`, `get_bound_settlement_context`, `get_city_presentation_binding`, `can_rebind_city_presentation`, `rebind_city_presentation`, `validate_city_presentation_binding`.

### `CityPresentationInvalidationTracker`

`_reset_city_presentation_observers`, `_capture_bound_city_presentation_versions`, `_collect_city_change_flags`, `_collect_city_world_change_flags`, `_collect_world_data_change_flags`.

### `Camera`

`_store_bound_city_camera_state`, `_configure_city_camera_for_bound_settlement`, `create_city_camera`, `get_city_tile_from_mouse`, `get_city_tile_under_mouse`.

### `MapTextureCache`

`install_session_prepared_city_map_textures`, `setup_city_texture_cache`, `has_valid_saved_city_map_texture_cache`, `get_saved_city_map_texture_cache`, `store_saved_city_map_texture_cache`, `rebuild_city_terrain_texture`, `apply_cached_city_map_mode_texture`, `create_city_terrain_sprite`, `refresh_city_terrain_sprite`.

### `SettlementNaturalFeaturePresenter`

`setup_city_natural_feature_rendering`, `store_city_natural_feature_cache`, `refresh_city_natural_feature_instance_visibility`, `rebuild_city_natural_feature_multimeshes`, `apply_city_surface_feature_changes`, `should_draw_city_trees`.

### `SettlementInfrastructurePresenter`

`get_city_object_by_id`, `get_city_object_world_rect`.

### `CityCitizenMovementPresentation`

No CityRenderer top-level function remains assigned here.

### `SettlementPlacementController`

`cancel_active_city_object_placement`, `start_road_placement`, `cancel_road_placement`, `confirm_active_city_object_placement`, `handle_road_left_mouse_pressed`, `handle_road_left_mouse_released`, `start_road_drag_selection`, `update_road_drag_selection`, `rebuild_road_preview_rectangle`, `confirm_road_preview`, `start_city_object_placement`, `clear_city_object_placement`, `has_active_city_object_placement`, `active_city_object_placement_uses_environmental_source`, `is_uncommitted_city_placement_preview_active`, `get_active_city_object_placement_preview`.

### `SettlementSelectionController`

`_update_city_hover_state`, `start_object_selection_drag`, `update_object_selection_drag`, `finish_object_selection_drag`, `has_selected_city_entity`, `set_selected_city_object`, `set_selected_city_construction_site`, `clear_selected_city_entity`, `_apply_city_selection_transition`, `queue_city_selection_visual_change`, `is_city_object_selectable`, `is_city_construction_site_selectable`, `draw_selected_city_citizen_highlight`, `draw_selected_city_object_highlight`, `draw_selected_city_construction_site_highlight`, `get_city_hover_highlight_tiles`, `draw_hovered_city_tile_highlight`.

### `SettlementCommandController`

`is_city_player_command_mode_active`, `is_city_player_command_tool_active`, `start_city_player_command_drag`, `update_city_player_command_drag`, `finish_city_player_command_drag`, `cancel_city_player_command_drag`.

### `SettlementUiController`

`create_city_ui`, `_is_bound_settlement_map_mode_ready`, `_apply_bound_settlement_map_mode`, `_on_settlement_ui_change`, `_on_settlement_back_requested`, `set_city_view_mode`, `update_city_ui_layout`.

### `CityInformationPanel`

`create_city_information_panel`, `on_simulation_time_changed`.

### `CityObjectPanelAnchor`

`_ensure_settlement_entity_panel_presentation`, `update_construction_site_info_panel_screen_position`, `hide_workplace_details_ui`, `hide_construction_site_info_panel`, `update_selected_entity_panel`, `_hide_selected_city_object_panel`.

### `CityDebugPresentation`

`add_debug_resource_to_selected_stockpile`, `has_debug_selected_city_tile`, `set_debug_selected_city_tile`, `clear_debug_selected_city_tile`, `update_debug_panel_text`, `create_debug_panel`, `clear_debug_navigation_result`, `request_debug_navigation_path`, `assign_debug_navigation_path_to_selected_citizen`, `get_citizen_debug_list_text`, `toggle_debug_mode`, `_get_city_debug_presentation_values`.

### `CityWorkplaceZoneOverlayCache`

`draw_selected_workplace_zone_background`, `draw_active_workplace_zone_background`, `refresh_active_workplace_zone_preview_cache`, `refresh_selected_workplace_zone_cache`, `draw_workplace_resource_zone_preview`, `draw_selected_workplace_resource_zone`.

### `CityRenderLayer`

`_set_city_render_layers_visible`, `_request_all_city_render_layers_redraw_even_if_hidden`, `_finish_city_presentation_rebind`, `create_city_render_layers`, `queue_city_active_workplace_preview_layer_redraw`, `queue_city_background_layer_redraw`, `queue_city_citizen_layer_redraw`, `queue_city_interaction_layer_redraw`, `queue_all_city_render_layers_redraw`, `_on_city_render_layer_drawn`, `draw_city_active_workplace_preview_layer`, `draw_city_background_layer`, `draw_city_citizen_layer`, `draw_city_interaction_layer`.

## Characterization matrix

| Responsibility/behavior | Permanent coverage |
| --- | --- |
| Initial explicit bind | `CityRendererExplicitBindingTest` and `SettlementPresentationBindingTest` cover registered pre-tree binding plus invalid/missing capability rejection. |
| A -> B -> A | `SettlementPresentationRebindTest` covers exact context/world restoration, independent camera state, and retained layer visibility. |
| Stale generation rejection | Binding, helper, controller, presenter, and tracker tests assert monotonic rejection and reset-preserved high-water marks. |
| Version invalidation | `CityPresentationInvalidationTrackerTest` covers every version and equal-version owner replacement. |
| Terrain cache | Renderer smoke and helper-binding tests cover exact-world reuse/rejection. |
| Natural features | Renderer smoke/rebind coverage and the natural-feature presenter contract cover rebuild, incremental removal, visibility, and exact-source cache identity. |
| Citizen draw/movement | `CityCitizenMovementPresentationTest` covers synchronization, buffers, cargo, geometry, stale binding, and reset. |
| Objects, roads, construction, piles, overlays | Renderer smoke plus `SettlementInfrastructurePresenterTest` and overlay-cache coverage preserve visuals and owner identity. |
| Building placement | `CityRendererInteractionCharacterizationTest` covers preview, commit, cancel, and gameplay immutability. |
| Road drag | Interaction characterization covers press/drag/preview/commit/cancel ordering. |
| Player commands | `SettlementCommandControllerTest` and renderer interaction characterization cover command drag and cancel behavior. |
| Selection/hover | `SettlementSelectionControllerTest` and renderer characterization cover exact binding, hit testing, drag, and hover. |
| Panels and viewport safety | `CityObjectPanelAnchorTest` and `CityPanelViewportSafetyTest` cover attachment, layout, and rebind/reset. |
| Debug navigation/path | Helper-binding and renderer tests cover diagnostic identity, navigation result/path, structured commands, and reset. |
| Camera per settlement | Rebind tests cover independent A/B/A camera state. |
| Hidden/inactive renderer then reveal | Interaction and rebind tests cover generation-checked hidden/pending reveal and rollback. |
| Pure redraw/rebind mutates no gameplay | Deep snapshots and exact owner identities are compared across success, failure, helper fault, and retry. |
| Pause/speed | Explicit-binding and rebind regressions assert unchanged clock pause and speed. |

The dedicated settlement component scenes are runnable and carry checked-in script UIDs. Placement and natural-feature integration remain covered in the renderer characterization/smoke scenes because their behavior crosses retained scene nodes; the extracted owners themselves still expose exact binding and reset seams.

## Decomposition result and remaining facade boundary

The reduction is substantive rather than file slicing. `SettlementPlacementController`, `SettlementSelectionController`, `SettlementCommandController`, `SettlementInfrastructurePresenter`, and `SettlementUiController` receive the neutral binding base and explicitly request the city-detail capability they currently need. None receives the renderer or discovers which settlement is active. `CityObjectPanelAnchor`, `CityCitizenMovementPresentation`, `CityInformationPanel`, and `CitizenDebugPanel` follow the same capability rule. `CityDebugPresentation` and `CityPresentationInvalidationTracker` remain city-named because their read models are deliberately backend-specific.

UI no longer turns the facade into a controller hub. `SettlementUiController` receives three concrete typed controllers and exactly four Callables: map readiness, map apply, back navigation, and a single presentation-change notification channel. Panels, formatting, menu state, and chrome are owned outside the renderer.

The facade's remaining central work is cross-component ordering imposed by the Godot scene: input dispatch, retained draw composition, terrain/camera assembly, and atomic bind/reveal. Compatibility forwarding properties for placement and selection are derived views into their owners, not duplicate state. They can be retired as external characterization callers migrate, but they may not acquire new behavior.

## Decomposition durability rules

- Keep `CityRenderer` at or below the three static budgets and update the exact inventories whenever a facade member changes.
- Prefer an existing focused owner. Add a component only when no current owner has a coherent responsibility boundary.
- Settlement-named production components must not reference `CityRenderer`, discover active/current/presented settlement state, or branch on settlement type. Backend differences belong behind named capabilities and adapters.
- `can_bind_settlement_presentation` is a pure preflight. A successful bind advances the component high-water mark. Reset clears presentation state without lowering it or mutating gameplay.
- Every binding transaction publishes one exact token to all helpers and the tracker. A partial commit must restore the previous target through a fresh higher generation; the failed target remains retryable.
- Preserve draw order, input priority, panel layout, camera retention, cache source identity, pause/speed, and zero-gameplay-mutation characterization.
- `CityPresentationInvalidationTracker` stays city-specific until a genuinely backend-neutral invalidation schema exists. A cosmetic rename without a neutral contract is forbidden.
