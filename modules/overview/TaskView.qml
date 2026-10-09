import QtQuick
import Quickshell.Hyprland
import "../../common"
import "../../common/functions"
import "../../services"
import "TaskViewGeometry.js" as TaskViewGeometry

Item {
    id: root

    required property var panelWindow
    readonly property var monitor: panelWindow.monitor
    readonly property int monitorId: monitor?.id ?? -1
    readonly property var monitorData: HyprlandData.monitors.find(candidate => candidate.id === root.monitorId) ?? null
    readonly property real displayAspect: {
        const m = root.monitorData;
        if (!m || !(m.width > 0) || !(m.height > 0))
            return 16 / 9;
        const w = m.transform % 2 === 1 ? m.height : m.width;
        const h = m.transform % 2 === 1 ? m.width : m.height;
        return w / h;
    }
    readonly property int activeWorkspaceId: {
        const current = monitor?.activeWorkspace?.id ?? 1;
        return current >= 1 && current <= 10 ? current : 1;
    }
    property int recaptureToken: 0
    property string draggedWindowAddress: ""
    property int windowDropWorkspaceId: -1
    readonly property var viewMetrics: TaskViewGeometry.taskViewMetrics(width, height, root.displayAspect)

    focus: panelWindow.monitorIsFocused && GlobalStates.overviewOpen
    // Inline desktop-name editors consume Enter/Escape first. The overview
    // still receives unhandled keys after the focused child.
    Keys.priority: Keys.AfterItem

    function activateWorkspace(workspaceId) {
        if (!(workspaceId >= 1 && workspaceId <= 10))
            return;
        GlobalStates.overviewOpen = false;
        if (Hyprland.usingLua)
            Hyprland.dispatch(`hl.dsp.focus({workspace = '${workspaceId}'})`);
        else
            Hyprland.dispatch(`workspace ${workspaceId}`);
    }

    function moveWindow(address, workspaceId) {
        if (!/^0x[0-9a-f]+$/i.test(`${address ?? ""}`)
                || !(workspaceId >= 1 && workspaceId <= 10))
            return;
        if (Hyprland.usingLua)
            Hyprland.dispatch(`hl.dsp.window.move({workspace = '${workspaceId}', follow = false, window = 'address:${address}'})`);
        else
            Hyprland.dispatch(`movetoworkspacesilent ${workspaceId}, address:${address}`);
    }

    function beginWindowDrag(address) {
        if (!/^0x[0-9a-f]+$/i.test(`${address ?? ""}`))
            return;
        root.draggedWindowAddress = `${address}`;
        root.windowDropWorkspaceId = -1;
    }

    function updateWindowDrag(address, sceneX, sceneY) {
        if (`${address ?? ""}` !== root.draggedWindowAddress)
            return;
        root.windowDropWorkspaceId = workspaceStrip.workspaceAt(sceneX, sceneY);
    }

    function finishWindowDrag(address, canceled) {
        if (`${address ?? ""}` !== root.draggedWindowAddress)
            return;
        const targetWorkspaceId = root.windowDropWorkspaceId;
        root.draggedWindowAddress = "";
        root.windowDropWorkspaceId = -1;
        if (!canceled && targetWorkspaceId >= 1)
            root.moveWindow(address, targetWorkspaceId);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (windowOverview.cancelActiveDrag()) {
                event.accepted = true;
                return;
            }
            GlobalStates.overviewOpen = false;
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!windowOverview.activateSelected())
                GlobalStates.overviewOpen = false;
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
                || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            const backwards = event.key === Qt.Key_Backtab
                || event.key === Qt.Key_Up
                || (event.key === Qt.Key_Tab
                    && (event.modifiers & Qt.ShiftModifier));
            windowOverview.selectRelative(backwards ? -1 : 1);
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Delete
                || (event.key === Qt.Key_W
                    && (event.modifiers & Qt.ControlModifier))) {
            windowOverview.closeSelected();
            event.accepted = true;
            return;
        }

        let target = -1;
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9)
            target = event.key - Qt.Key_0;
        else if (event.key === Qt.Key_0)
            target = 10;
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_H)
            target = DesktopMetadata.visualNeighbor(root.activeWorkspaceId, -1);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_L)
            target = DesktopMetadata.visualNeighbor(root.activeWorkspaceId, 1);

        if (target >= 1) {
            root.activateWorkspace(target);
            event.accepted = true;
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const name = `${event?.name ?? event?.event ?? event?.type ?? ""}`;
            if (name === "openwindow" || name === "closewindow" || name === "movewindow"
                    || name === "movewindowv2" || name === "workspace" || name === "workspacev2")
                root.recaptureToken += 1;
        }
    }

    Item {
        id: windowRegion
        x: root.viewMetrics.windowRegion.x
        y: root.viewMetrics.windowRegion.y
        width: root.viewMetrics.windowRegion.width
        height: root.viewMetrics.windowRegion.height

        WindowOverview {
            id: windowOverview
            anchors.fill: parent
            workspaceId: root.activeWorkspaceId
            monitorId: root.monitorId
            monitorData: root.monitorData
            recaptureToken: root.recaptureToken
            onWindowDragStarted: address => root.beginWindowDrag(address)
            onWindowDragMoved: (address, sceneX, sceneY) =>
                root.updateWindowDrag(address, sceneX, sceneY)
            onWindowDragFinished: (address, canceled) =>
                root.finishWindowDrag(address, canceled)
        }
    }

    Item {
        id: desktopStrip
        x: root.viewMetrics.desktopStrip.x
        y: root.viewMetrics.desktopStrip.y
        width: root.viewMetrics.desktopStrip.width
        height: root.viewMetrics.desktopStrip.height

        WorkspaceStrip {
            id: workspaceStrip
            anchors.fill: parent
            stripSpacing: root.viewMetrics.desktopStrip.spacing
            thumbnailWidth: root.viewMetrics.desktopStrip.thumbnailWidth
            thumbnailHeight: root.viewMetrics.desktopStrip.thumbnailHeight
            labelHeight: root.viewMetrics.desktopStrip.labelHeight
            labelGap: root.viewMetrics.desktopStrip.labelGap
            activeWorkspaceId: root.activeWorkspaceId
            monitorId: root.monitorId
            monitorData: root.monitorData
            windowDropWorkspaceId: root.windowDropWorkspaceId
            onWorkspaceActivated: workspaceId => root.activateWorkspace(workspaceId)
            onWindowMoveRequested: (address, workspaceId) => root.moveWindow(address, workspaceId)
        }
    }
}
