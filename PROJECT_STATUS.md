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
- QML parsed by an actual Quickshell instance: **NOT TESTED**.
- Live preview/window operations/workspace reordering: **NOT TESTED in this branch**.
- Deployment onto owner's running overview: **NOT DONE**.
- Second machine / other compositor version: **NOT TESTED**.

### Remaining acceptance and risks
- Portability is partially implemented but not accepted until the fresh clone launches and renders, window drag/drop works, safe content reordering works and fails safely, and cross-machine behavior is demonstrated.
- IPC calls are not atomic; if Quickshell or the compositor is killed mid-transaction, automatic rollback may not run. Unsupported window states are refused.
- Real reordering of user-defined pinned rules across all Hyprland configurations is not portable without changing those users' rules; this branch deliberately refuses it. The owner's original rules.lua-aware helper is retained in Git history and source but not invoked by default.
- A separate non-live fresh-config QML start check and then an owner-approved live visual/functional acceptance check are necessary.
- No merge to main, live install/restart, or system configuration edits are authorized by this checkpoint alone.

### Next potential action
Investigate the static QML/runtime integration on a disposable non-live Quickshell configuration where startup cannot replace or disrupt the current instance. Perform live acceptance only with Reason's separate exact-scope authorization.
