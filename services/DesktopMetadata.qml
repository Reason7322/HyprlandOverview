pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "DesktopMetadata.js" as MetadataModel

Singleton {
    id: root

    readonly property string stateRoot: {
        const configured = `${Quickshell.env("XDG_STATE_HOME") ?? ""}`.trim();
        if (configured.length > 0)
            return configured;
        const home = `${Quickshell.env("HOME") ?? ""}`.trim();
        return `${home}/.local/state`;
    }
    readonly property string statePath: `${stateRoot}/hyprland-overview-desktops.json`
    property var state: MetadataModel.normalize(null)
    readonly property var order: state.order
    readonly property var entries: state.entries
    property bool loadComplete: false
    property bool migrationRunning: false
    property string lastError: ""

    function startMigration() {
        if (root.migrationRunning)
            return;
        root.migrationRunning = true;
        migrationProcess.running = true;
    }

    function loadFromDisk() {
        const payload = stateFile.text().trim();
        if (payload.length === 0) {
            root.state = MetadataModel.normalize(null);
            root.lastError = "";
            root.loadComplete = true;
            return;
        }

        try {
            const parsed = JSON.parse(payload);
            root.state = MetadataModel.normalize(parsed);
            root.lastError = "";
        } catch (error) {
            root.state = MetadataModel.normalize(null);
            root.lastError = `${error}`;
            console.warn("overview: invalid desktop metadata; using defaults without overwriting it", error);
        }
        root.loadComplete = true;
    }

    function persist(nextState) {
        const normalized = MetadataModel.normalize(MetadataModel.serialize(nextState));
        root.state = normalized;
        root.lastError = "";
        stateFile.setText(JSON.stringify(MetadataModel.serialize(normalized), null, 2) + "\n");
    }

    function renameWorkspace(workspaceId, name) {
        persist(MetadataModel.rename(root.state, workspaceId, name));
    }

    function reorderWorkspace(workspaceId, targetInsertionIndex) {
        persist(MetadataModel.reorder(root.state, workspaceId, targetInsertionIndex));
    }

    function setOrder(order) {
        persist({
            version: 1,
            entries: root.state.entries,
            order: order
        });
    }

    // reportedWorkspaceIds are the workspaces Hyprland currently reports so
    // keyboard navigation reaches desktops beyond the saved strip.
    function visualNeighbor(workspaceId, direction, reportedWorkspaceIds) {
        const merged = MetadataModel.mergeReported(
            root.state, reportedWorkspaceIds ?? []);
        return MetadataModel.neighbor(merged.order, workspaceId, direction);
    }

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onFileChanged: {
            if (!root.migrationRunning)
                root.loadFromDisk();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("overview: desktop metadata load failed", FileViewError.toString(error));
            root.state = MetadataModel.normalize(null);
            root.loadComplete = true;
        }
        onSaveFailed: error => {
            root.lastError = FileViewError.toString(error);
            console.warn("overview: desktop metadata save failed", root.lastError);
        }
    }

    Process {
        id: migrationProcess
        command: [
            "python3",
            `${Quickshell.shellDir}/services/workspace_reorder.py`,
            "migrate-metadata",
            "--metadata",
            root.statePath
        ]
        stdout: StdioCollector {
            id: migrationOutput
        }
        stderr: StdioCollector {
            id: migrationError
        }
        onExited: (exitCode, exitStatus) => {
            root.migrationRunning = false;
            if (exitCode === 0) {
                root.lastError = "";
                root.loadFromDisk();
            } else {
                root.lastError = migrationError.text.trim().length > 0
                    ? migrationError.text.trim() : migrationOutput.text.trim();
                root.loadComplete = true;
                console.warn("overview: desktop metadata migration failed", root.lastError);
            }
        }
    }

    Component.onCompleted: root.startMigration()
}
