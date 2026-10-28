> ### This overview is 100% vibe coded by OpenAI Codex and my locally running Qwen model. Use it at your own discretion.

# HyprlandOverview — deployed Quickshell source

This is the owner's **deployed** Hyprland Quickshell workspace overview, with live window previews, drag-and-drop, workspace naming and reordering, and Liquid Glass integration.

## Provenance and verification

The source files were taken from the clean Qwen development worktree at commit `b3a2ceb3c5afdeadd179297c1f481d564d4362d2` (2026-10-14). A previous byte-for-byte comparison verified that this exact source revision matches the installed overview at `~/.config/quickshell/overview`, excluding three generated/machine-specific files. The original GitHub history is preserved; the separate Forge and Qwen histories have not been rewritten or merged.

## Running and configuring

The deployable Quickshell module is `shell.qml` with `common/`, `modules/`, `services/`, `assets/`, and `config.example.json`. Copy the module into an appropriate Quickshell configuration directory and adapt `config.example.json` to your own Hyprland environment. Integration with Noctalia and theme generation depends on the owner's separate configuration and is not self-contained here.

Generated `common/Appearance.colors.qml`, local `config.json`, and deployment metadata `.hyprland-overview-stage.json` are intentionally not tracked. This archive repair confirmed source parity; it did **not** launch Quickshell, modify the live installation, or rerun UI tests. Experimental branches may differ from the currently deployed revision.
