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
    property string lastError: ""

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

    function visualNeighbor(workspaceId, direction) {
        return MetadataModel.neighbor(root.order, workspaceId, direction);
    }

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onFileChanged: root.loadFromDisk()
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

    Component.onCompleted: loadFromDisk()
}
