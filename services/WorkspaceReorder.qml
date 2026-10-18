pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string stateRoot: {
        const configured = `${Quickshell.env("XDG_STATE_HOME") ?? ""}`.trim();
        if (configured.length > 0)
            return configured;
        return `${Quickshell.env("HOME")}/.local/state`;
    }
    readonly property string requestPath:
        `${stateRoot}/hyprland-overview-reorder-request.json`
    readonly property string rulesPath:
        `${Quickshell.env("HOME")}/.config/hypr/modules/rules.lua`
    property bool busy: false
    property bool blocked: false
    property string lastStatus: "idle"
    property string lastError: ""
    signal finished(string status, string message)

    function request(slotOrder, identityOrder) {
        if (root.busy || root.blocked)
            return false;
        if (!Array.isArray(slotOrder) || !Array.isArray(identityOrder)
                || slotOrder.length !== identityOrder.length)
            return false;

        const expectedClients = (HyprlandData.windowList ?? [])
            .filter(client => /^0x[0-9a-f]+$/i.test(`${client?.address ?? ""}`)
                && Number.isInteger(client?.workspace?.id)
                && client.workspace.id >= 1)
            .map(client => ({
                address: `${client.address}`,
                workspaceId: client.workspace.id
            }));
        const payload = {
            version: 1,
            slotOrder: slotOrder.slice(),
            identityOrder: identityOrder.slice(),
            expectedClients: expectedClients
        };

        root.busy = true;
        root.lastStatus = "running";
        root.lastError = "";
        requestFile.setText(JSON.stringify(payload, null, 2) + "\n");
        reorderProcess.running = true;
        return true;
    }

    FileView {
        id: requestFile
        path: root.requestPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: error => {
            root.busy = false;
            root.lastStatus = "error";
            root.lastError = FileViewError.toString(error);
            root.finished(root.lastStatus, root.lastError);
        }
    }

    Process {
        id: reorderProcess
        command: [
            "python3",
            `${Quickshell.shellDir}/services/workspace_reorder.py`,
            "apply",
            "--metadata",
            DesktopMetadata.statePath,
            "--rules",
            root.rulesPath,
            "--request",
            root.requestPath,
            "--confirm-live-reorder"
        ]
        stdout: StdioCollector {
            id: reorderOutput
        }
        stderr: StdioCollector {
            id: reorderError
        }
        onExited: (exitCode, exitStatus) => {
            let status = "error";
            let message = reorderError.text.trim();
            try {
                const payload = JSON.parse(reorderOutput.text.trim());
                status = `${payload?.status ?? "error"}`;
                message = `${payload?.message ?? message}`;
            } catch (error) {
                if (message.length === 0)
                    message = `workspace reorder helper returned invalid output: ${error}`;
            }

            root.busy = false;
            root.blocked = status === "recovery_incomplete"
                || message.includes("unresolved prior transaction");
            root.lastStatus = status;
            root.lastError = status === "success" ? "" : message;
            HyprlandData.updateAll();
            DesktopMetadata.loadFromDisk();
            root.finished(status, message);
        }
    }
}
