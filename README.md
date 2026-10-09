# This entire thing has been forked and vibe-coded by Codex and a local llm in its entirety. Use at your own discretion.

HyprlandOverview

A Quickshell workspace/window overview for Hyprland with live previews, persistent workspace names and visual ordering, window drag-and-drop between workspaces, and a Liquid Glass-inspired interface.

This project is a fork/derivative of [Shanu-Kumawat/quickshell-overview](https://github.com/Shanu-Kumawat/quickshell-overview), originally imported from upstream commit `47f0d402822b26805ed0ecea4a770c38c537b728` and then substantially redesigned.

## Requirements

- Hyprland
- Quickshell

## Install

Clone the repository to your Quickshell overview config directory:

```bash
git clone https://github.com/Reason7322/HyprlandOverview ~/.config/quickshell/overview
```

Launch it with:

```bash
qs -p ~/.config/quickshell/overview
```

Workspace names and visual order are stored under:

```text
~/.local/state/hyprland-overview-desktops.json
```

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
