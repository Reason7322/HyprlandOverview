# HyprlandOverview — project status (2026-11-02)

## Original product goal

A Hyprland + Quickshell user should be able to clone this repository and run the overview without the owner's Noctalia, Liquid Glass generator, personalized Lua rules, Python, or `luac`. Preserve usable workspace thumbnails, live window previews, window dragging, saved workspace naming and **actual workspace content reordering**, not just cosmetic rearrangement. Preserve the owner's live desktop and data throughout the repair.

## Checkout and version

- Repair branch: `sol/portable-standalone`, based on GitHub `main` at `f0643a18681cd2c606df47032bdcadfb7f97c48e`.
- Workspace: `/home/reason/Projects/ChatGPTProjects/HyprlandOverview/`.
- Implemented via Remote Desktop Commander by ChatGPT (GPT-6 / Sol); earlier source development involved Forge (Codex) and Qwen.
- **Publication milestone authorized November 2, 2026:** promote the tested standalone release to GitHub `main` without replacing the owner's deployed overview. GitHub `main` can fast-forward from this branch; the unrelated historical `handoff/main` is preserved rather than overwritten or combined.

## Supported versions and acceptance

- Owner-selected support target: Hyprland **0.56 or newer** and the **current stable Quickshell** (upstream stable **0.3.2** as of November 2, 2026).
- Direct hardware verification: **Hyprland 0.57.0 + Quickshell 0.3.2**. Hyprland **0.56.x was not tested**, nor were other machines and future Quickshell/Hyprland versions; these are supported targets, not independently verified combinations.
- Owner accepted the original mouse drag-and-drop interaction based on regular daily use. The repaired source preserved the interaction and live-tested its QML reordering backend, but physical dragging on the repaired branch was not separately observed.

## Code changes

- Added version-controlled `common/Appearance.colors.qml` so the standalone palette exists on a fresh clone, with default color-source setting independent of Noctalia.
- Changed the reordering implementation to use `hyprctl eval` on verified Lua-backed Hyprland and a legacy dispatch path for older Hyprland. Reorder targets windows by their actual addresses and permutes their numeric workspace IDs directly; **no temporary workspace IDs** are generated.
- Retained preflight rejection for unsafe workspace placement rules, cross-monitor permutations and complex window states. Styling-only workspace rules are allowed.
- Live reordering no longer invokes the historical Python helper, edits `hyprland.lua` / `rules.lua`, or reloads Hyprland.
- Uses Quickshell's persistent metadata service for names and the workspace mapping. Requires metadata initialization before accepting a reorder; no silent success when it is not ready.
- Updated README and added isolated Node.js tests for the planner and command construction. No compilation step needed.

## Verification evidence

**CODED:** Changes are in the review branch.

**TESTED — source:** `node --check services/PortableReorder.js` passed; `node --test tests/portable_reorder.test.cjs` passed 8/8; `git diff --check` passed.

**VERIFIED IN REAL HYPRLAND + QUICKSHELL (not a VM):** Fedora 44, Hyprland 0.57.0, Quickshell 0.3.2, monitor DP-2. Source was launched with `qs -p` in a separate instance using isolated XDG config/state/cache. QML loaded, overview panel/workspace thumbnails/live previews rendered, and IPC open/close worked. A warning about an unavailable generic app icon was nonfatal. Screenshot: `/home/reason/Projects/ChatGPTProjects/Scratch/HyprlandOverview/overview-open.png`.

**FRESH PUBLIC GIT CLONE:** Cloned the review branch from GitHub at source commit `6c0408039932d57dea292c59479692789be87b40` into `/home/reason/Projects/ChatGPTProjects/Scratch/HyprlandOverview/fresh-release-clone`. The clone had no `config.json`, generated state file, or deployment metadata; it included the default palette and `shell.qml`. Node.js tests passed 8/8 in that exact clone. Quickshell reported `Configuration Loaded` when launched from the clone with fresh XDG directories during a bounded six-second test. Log: `/home/reason/Projects/ChatGPTProjects/Scratch/HyprlandOverview/fresh-clone-runtime.log`.

**WORKSPACE REORDERING:** The owner's explicit authorization covered 10, 11 and 12, which already contained Dolphin and Kate (10), Deadband (11), and MusicSync (12). The test QML service successfully swapped the *actual* window contents of 10 and 11. Independent `hyprctl clients -j` queries verified both swapped destinations. MusicSync on 12 and all unrelated windows stayed in place. A custom workspace name moved with its workspace identity in the isolated persistent metadata store. The tester then restored Dolphin, Kate and Deadband to their original workspaces; verification showed **zero discrepancies**.

**WORKSPACE NAMING:** Renaming workspace 10 persisted to the isolated XDG state file and loaded with the same name after a separate Quickshell restart. The owner's real state file was never modified.

**RECOVERY:** Injected a failure on the second move (Kate to workspace 11), after Dolphin had already moved. Quickshell emitted `PORTABLE_TEST_FINISHED recovered` and restored all original window positions through its own rollback path; no external restoration was needed in that failure run. The exact intercepted commands are recorded in `/home/reason/Projects/ChatGPTProjects/Scratch/HyprlandOverview/reorder-injection.trace`. Evidence files: `success-driver.log` and `recovery-driver.log` in the same Scratch directory. Recovery of a compositor crash or system shutdown was not tested.

**SAFETY:** Owner's original overview stayed running as `qs -c overview` PID 2019. The owner's real workspace metadata hash was `43d6cc1665f209bbda9b10f3f47f18f613c5144d650859f8e3a03a469b10049f` before and after. No live theme files, Hyprland config files or running overview instance were changed or restarted. Only authorized workspace IDs were used for moves.

## Outstanding acceptance / limitations

- Mouse-driven interaction was **accepted by the owner** based on daily use of the original Qwen-built overview; direct mouse drag on the repaired release was not separately observed, though its QML reordering backend was exercised live.
- Compatibility with *other* physical systems, monitors and Hyprland/Quickshell versions remains unverified. In particular, the legacy Hyprland dispatch mode was not tested live.
- Reordering of pinned/workspace-rule-bound windows, cross-monitor permutations, grouped/pinned/fullscreen/special client states is deliberately refused instead of risking changes to other users' configurations.
- Window moves are not atomic; automatic rollback cannot be promised if the compositor or test process exits mid-operation.
- Publication to GitHub `main` was authorized on November 2, 2026. Promotion is by **fast-forward** from the review branch; no live-installation deployment is authorized. The separate `handoff/main` has an unrelated older history and must not be force-updated.

## Next potential action

Publish the owner-approved reviewed standalone source as the default GitHub `main` branch, verify the live remote SHA and README, then stop. No local live deployment, release tag, or separate work is authorized by this milestone.
