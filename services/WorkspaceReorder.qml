pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "PortableReorder.js" as Reorder

// Standalone, fail-closed Hyprland workspace content permutation.
// No Python, Lua compiler, config rewrite, or Hyprland reload.
Singleton {
    id: root
    property bool busy: false
    property bool blocked: false
    property string lastStatus: "idle"
    property string lastError: ""
    property var pendingPlan: null
    property var pendingSlots: []
    property var pendingIdentities: []
    property string dispatchMode: ""
    property string stage: ""
    property string failureMessage: ""
    signal finished(string status, string message)

    function finish(status, message) {
        root.busy = false;
        root.lastStatus = status;
        root.lastError = status === "success" ? "" : message;
        HyprlandData.updateAll();
        root.finished(status, message);
    }

    function request(slots, identities) {
        if (root.busy || root.blocked)
            return false;
        try {
            Reorder.permutation(slots, identities);
        } catch (error) {
            root.finish("refused", String(error));
            return false;
        }
        root.pendingSlots = slots.slice();
        root.pendingIdentities = identities.slice();
        root.busy = true;
        root.lastStatus = "checking";
        root.lastError = "";
        probe.running = true;
        return true;
    }

    function runMoves(moves) {
        if (moves.length === 0) {
            verify.running = true;
            return;
        }
        commands.command = ["sh", "-c", Reorder.batch(moves, root.dispatchMode)];
        commands.running = true;
    }

    function recover(reason) {
        root.failureMessage = reason;
        root.stage = "recover";
        if (root.pendingPlan.rows.length === 0) {
            root.finish("error", reason);
            return;
        }
        // Restore every originally captured window, even if the first phase
        // failed halfway through. Never write or reload Hyprland config.
        runMoves(root.pendingPlan.recovery);
    }

    function advance() {
        if (root.stage === "first") {
            root.stage = "second";
            runMoves(root.pendingPlan.second);
        } else if (root.stage === "second") {
            DesktopMetadata.applyPermutation(root.pendingPlan.mapping);
            root.finish("success", "workspace content reordered");
        } else if (root.stage === "recover") {
            root.finish("recovered", root.failureMessage
                + "; original window workspace IDs restored");
        }
    }

    Process {
        id: probe
        command: [
            "sh", "-c",
            "set -e\n"
            + "hyprctl -j clients\nprintf '\\n__HYPR_OVERVIEW_SPLIT_1__\\n'\n"
            + "hyprctl -j workspaces\nprintf '\\n__HYPR_OVERVIEW_SPLIT_2__\\n'\n"
            + "hyprctl -j workspacerules\nprintf '\\n__HYPR_OVERVIEW_SPLIT_3__\\n'\n"
            + "hyprctl systeminfo || true\nprintf '\\n__HYPR_OVERVIEW_SPLIT_4__\\n'\n"
            + "hyprctl version\n"
        ]
        stdout: StdioCollector { id: probeOut }
        stderr: StdioCollector { id: probeError }
        onExited: (code, status) => {
            if (code !== 0) {
                root.finish("refused", "cannot inspect Hyprland: " + probeError.text.trim());
                return;
            }
            try {
                const parts = probeOut.text.split(/\n__HYPR_OVERVIEW_SPLIT_[1-4]__\n/);
                if (parts.length !== 5)
                    throw new Error("invalid Hyprland preflight response");
                const clients = JSON.parse(parts[0]);
                const workspaces = JSON.parse(parts[1]);
                const rules = JSON.parse(parts[2]);
                root.dispatchMode = Reorder.provider(parts[3], parts[4]);
                root.pendingPlan = Reorder.plan(
                    root.pendingSlots, root.pendingIdentities, clients, workspaces, rules);
                if (root.pendingPlan.rows.length === 0) {
                    DesktopMetadata.applyPermutation(root.pendingPlan.mapping);
                    root.finish("success", "reordered empty desktop metadata");
                    return;
                }
                root.stage = "first";
                root.runMoves(root.pendingPlan.first);
            } catch (error) {
                root.finish("refused", String(error));
            }
        }
    }

    Process {
        id: commands
        stdout: StdioCollector { id: commandOut }
        stderr: StdioCollector { id: commandError }
        onExited: (code, status) => {
            if (code !== 0 || commandOut.text.includes("error:")) {
                const problem = "window move failed: " + commandError.text.trim();
                if (root.stage === "recover") {
                    root.blocked = true;
                    root.finish("recovery_incomplete", root.failureMessage + "; " + problem);
                } else {
                    root.recover(problem);
                }
                return;
            }
            verify.running = true;
        }
    }

    Process {
        id: verify
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector { id: verifyOut }
        stderr: StdioCollector { id: verifyError }
        onExited: (code, status) => {
            let valid = false;
            if (code === 0) {
                try {
                    valid = Reorder.checkClients(
                        JSON.parse(verifyOut.text), root.pendingPlan.rows, root.stage);
                } catch (error) {
                    valid = false;
                }
            }
            if (valid) {
                root.advance();
            } else if (root.stage === "recover") {
                root.blocked = true;
                root.finish("recovery_incomplete", root.failureMessage
                    + "; cannot verify restored window positions");
            } else {
                root.recover("window positions changed during reordering");
            }
        }
    }
}
