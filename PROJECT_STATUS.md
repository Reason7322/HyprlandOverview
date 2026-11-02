# HyprlandOverview — product status

## Original goal
Make the owner-used Hyprland Quickshell overview installable via a normal Git clone and runnable on other Hyprland + Quickshell desktops, without requiring the owner's Noctalia, Liquid Glass generator, personal Hyprland Lua layout, Python or luac. Preserve previews, window drag/drop, naming and genuine workspace content reordering. Do not modify live Quickshell/Hyprland configuration on M A C H I N E without explicit approval.

## 2026-11-02 repository-only portability work

Implemented by ChatGPT (GPT-6 / Sol) over Remote Desktop Commander, in a separate ChatGPT-owned checkout; the earlier source involved Forge/Codex and Qwen.

Branch: `sol/portable-standalone`, based on public GitHub `main` at `f0643a18681cd2c606df47032bdcadfb7f97c48e`.

### Source changes (not a live deployment)
- Tracked a complete default `common/Appearance.colors.qml` so fresh clones no longer lack a required QML color source; default theme no longer assumes Noctalia.
- Replaced the runtime Python/Lua-config-specific reordering path with `PortableReorder.js` and `WorkspaceReorder.qml`, which preflight Hyprland state, use appropriate Lua/legacy IPC syntax, move real windows between numeric IDs, verify each phase and attempt rollback on errors. The helper refuses pinned workspace placements, cross-monitor permutations and complex window states, rather than editing another user's config.
- Removed runtime Python metadata migration; metadata startup now creates an XDG state directory with standard `mkdir` and reads schema1/schema2 through existing JS normalizer. Original state filename is preserved.
- Added isolated Node.js tests for mapping, safe commands, provider detection, restrictions, and bundled palette.
- Updated README with clone/run/autostart and accurate limitations.

### Evidence
- Node.js model tests: 8 passing (2026-11-02).
- `node --check` on `services/PortableReorder.js`: passed.
- `git diff --check`: passed.
- Quickshell 0.3.2 on Hyprland 0.57.0: **Configuration Loaded** from isolated Git checkout via `qs -p`, with isolated XDG config/state/cache. Test process exited after a bounded run.
- Live actual UI screenshot captured while the isolated instance received IPC `overview open`: workspace tiles, live previews and labels visibly rendered. IPC `open` and `close` returned successfully. Evidence: `/home/reason/Projects/ChatGPTProjects/Scratch/HyprlandOverview/overview-open.png` and `runtime-open.log`. One nonfatal missing-app-icon warning.
- The actual Hyprland 0.57.0 reports `configProvider: lua` and two cosmetic workspace rules (`w[tv1]`, `f[1]`). Initial rule detection falsely refused these. **Fixed in the branch**, extended tests passed, and read-only dry-run plans for 9↔10 and 1↔2 are now accepted. No dispatch commands were executed.
- Real window drag/drop and workspace reordering: **NOT TESTED in this branch**.
- Deployment onto owner's running overview: **NOT DONE**.
- Second machine / other compositor version: **NOT TESTED**.

### Remaining acceptance and risks
- Portability is partially implemented but not accepted until the fresh clone launches and renders, window drag/drop works, safe content reordering works and fails safely, and cross-machine behavior is demonstrated.
- IPC calls are not atomic; if Quickshell or the compositor is killed mid-transaction, automatic rollback may not run. Unsupported window states are refused.
- Real reordering of user-defined pinned rules across all Hyprland configurations is not portable without changing those users' rules; this branch deliberately refuses it. The owner's original rules.lua-aware helper is retained in Git history and source but not invoked by default.
- Isolated runtime QML launch and real UI rendering are confirmed on M A C H I N E. Window moving, workspace renaming persistence, true reorder and rollback still need controlled runtime acceptance; do not move the owner's existing windows without explicit approval.
- No merge to main, live install/restart, or system configuration edits are authorized by this checkpoint alone.

### Next potential action
Arrange a controlled test of actual window movement, workspace name persistence, and content reordering using **disposable windows** with rollback, only after Reason explicitly approves creating and moving those windows on M A C H I N E.
