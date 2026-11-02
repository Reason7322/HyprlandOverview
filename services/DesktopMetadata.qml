pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "DesktopMetadata.js" as MetadataModel

Singleton {
    id: root

    readonly property string stateRoot: {
        const configured = String(Quickshell.env("XDG_STATE_HOME") ?? "").trim();
        if (configured.length > 0) return configured;
        return String(Quickshell.env("HOME") ?? "") + "/.local/state";
    }
    readonly property string statePath: stateRoot + "/hyprland-overview-desktops.json"
    property var state: MetadataModel.normalize(null)
    readonly property var order: state.order
    readonly property var entries: state.entries
    property bool loadComplete: false
    property bool migrationRunning: false // Kept for compatibility with WorkspaceStrip.
    property bool storageReady: false
    property string lastError: ""

    function loadFromDisk() {
        if (!root.storageReady) return;
        const payload = stateFile.text().trim();
        if (payload.length === 0) {
            root.state = MetadataModel.normalize(null);
            root.lastError = "";
            root.loadComplete = true;
            return;
        }
        try {
            root.state = MetadataModel.normalize(JSON.parse(payload));
            root.lastError = "";
        } catch (error) {
            root.state = MetadataModel.normalize(null);
            root.lastError = String(error);
            console.warn("overview: invalid saved desktop metadata, keeping file", error);
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
        if (!root.loadComplete) return;
        root.persist(MetadataModel.rename(root.state, workspaceId, name));
    }

    function reorderWorkspace(workspaceId, targetInsertionIndex) {
        if (!root.loadComplete) return;
        root.persist(MetadataModel.reorder(root.state, workspaceId, targetInsertionIndex));
    }

    function setOrder(order) {
        if (!root.loadComplete) return;
        const current = MetadataModel.serialize(root.state);
        current.order = order;
        root.persist(current);
    }

    function applyPermutation(mapping) {
        if (!root.loadComplete) return;
        const current = MetadataModel.serialize(root.state);
        const saved = Object.assign({}, current.names);
        const next = Object.assign({}, saved);
        Object.keys(mapping).forEach(from => {
            delete next[String(mapping[from])];
        });
        Object.keys(mapping).forEach(from => {
            if (Object.prototype.hasOwnProperty.call(saved, from))
                next[String(mapping[from])] = saved[from];
        });
        current.names = next;
        root.persist(current);
    }

    function visualNeighbor(workspaceId, direction, reportedWorkspaceIds) {
        const merged = MetadataModel.mergeReported(root.state, reportedWorkspaceIds ?? []);
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
        onLoaded: root.loadFromDisk()
        onFileChanged: stateFile.reload()
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("overview: desktop metadata load failed", FileViewError.toString(error));
            if (root.storageReady) root.loadFromDisk();
        }
        onSaveFailed: error => {
            root.lastError = FileViewError.toString(error);
            console.warn("overview: desktop metadata save failed", root.lastError);
        }
    }

    Process {
        id: createStateDirectory
        command: ["mkdir", "-p", root.stateRoot]
        onExited: (code, status) => {
            root.storageReady = code === 0;
            if (root.storageReady) {
                stateFile.reload();
                root.loadFromDisk();
            } else {
                root.lastError = "Could not create desktop metadata directory";
                root.loadComplete = true;
                console.warn("overview:", root.lastError);
            }
        }
    }

    Component.onCompleted: createStateDirectory.running = true
}
