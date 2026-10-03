# Native list reorder implementation plan

Goal: adopt native List/onMove with safe physical menu-bar commit and responsive feedback.
Architecture: PanelView owns native sections; MenuPinCore converts indices into a relative move; AppModel keeps requested display order separate from scanned frames until verified commit.

- [x] Add and observe failing core tests for upward/downward, beginning/end, no-op, invalid and multi-item moves.
- [x] Implement MenuOrder.listMove, preserving the existing relative move API.
- [x] Replace list rendering with List sections/onMove, remove competing custom drag/drop, retain row controls; disable search/unknown/unidentified moves.
- [x] Validate snapshot and references before committing; animate display preview and confirmed/failed settlement, respect Reduce Motion.
- [x] Run core tests and Release compile; verify native demo drag, cancellation, search, pin and menu actions.
- [x] Independently review modified code and fix actionable issues.
- [x] Bump version, build final artifact from authoritative source, quit installed old process, install/relaunch and verify signature/hash/version/process.

Acceptance adjustment after controlled UI testing: keep native name Button and dedicate left ≡ to reordering on macOS 15; full-row name-region dragging is not claimed. Real third-party movement remains outside completed demo checks; see VALIDATION.md.
