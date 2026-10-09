import QtQuick
import "../../common"
import "../../services"
import "../../services/DesktopMetadata.js" as MetadataModel

Item {
    id: root

    property int activeWorkspaceId: 1
    property int monitorId: -1
    property var monitorData: null
    property real stripSpacing: 16
    property real thumbnailWidth: 200
    property real thumbnailHeight: 113
    property real labelHeight: 22
    property real labelGap: 5
    property bool reorderActive: false
    property int draggedWorkspaceId: -1
    property int insertionWorkspaceId: -1
    property bool insertionAfter: false
    property int windowDropWorkspaceId: -1
    signal workspaceActivated(int workspaceId)
    signal windowMoveRequested(string address, int workspaceId)

    function syncFromStore() {
        desktopModel.clear();
        DesktopMetadata.entries.forEach(entry => {
            desktopModel.append({
                workspaceId: entry.workspaceId,
                displayName: entry.name
            });
        });
    }

    function currentEntries() {
        const result = [];
        for (let index = 0; index < desktopModel.count; index += 1) {
            const entry = desktopModel.get(index);
            result.push({ workspaceId: entry.workspaceId, name: entry.displayName });
        }
        return result;
    }

    function currentOrder() {
        return currentEntries().map(entry => entry.workspaceId);
    }

    function workspaceAt(sceneX, sceneY) {
        for (let index = 0; index < workspaceRepeater.count; index += 1) {
            const candidate = workspaceRepeater.itemAt(index);
            if (candidate?.containsWindowDropPoint(sceneX, sceneY))
                return candidate.workspaceId;
        }
        return -1;
    }

    function beginReorder(workspaceId) {
        if (!(workspaceId >= 1 && workspaceId <= 10))
            return;
        root.reorderActive = true;
        root.draggedWorkspaceId = workspaceId;
        root.insertionWorkspaceId = workspaceId;
        root.insertionAfter = false;
        viewport.interactive = false;
    }

    function previewReorder(workspaceId, targetInsertionIndex, after) {
        if (!root.reorderActive)
            root.beginReorder(workspaceId);
        if (root.draggedWorkspaceId !== workspaceId)
            return;

        const current = {
            version: 1,
            order: root.currentOrder(),
            entries: root.currentEntries()
        };
        const next = MetadataModel.reorder(current, workspaceId, targetInsertionIndex);
        const fromIndex = current.order.indexOf(workspaceId);
        const toIndex = next.order.indexOf(workspaceId);
        if (fromIndex >= 0 && toIndex >= 0 && fromIndex !== toIndex)
            desktopModel.move(fromIndex, toIndex, 1);
        root.insertionWorkspaceId = workspaceId;
        root.insertionAfter = after;
    }

    function previewReorderAt(workspaceId, sceneX) {
        const local = thumbnailRow.mapFromItem(null, sceneX, 0);
        const pitch = Math.max(1, root.thumbnailWidth + root.stripSpacing);
        const boundary = Math.max(0, Math.min(
            desktopModel.count,
            Math.round((local.x + root.stripSpacing / 2) / pitch)
        ));
        root.previewReorder(
            workspaceId,
            boundary,
            boundary >= desktopModel.count
        );
    }

    function finishReorder(workspaceId, canceled) {
        if (!root.reorderActive || root.draggedWorkspaceId !== workspaceId)
            return;
        const committedOrder = root.currentOrder();
        root.reorderActive = false;
        root.draggedWorkspaceId = -1;
        root.insertionWorkspaceId = -1;
        root.insertionAfter = false;
        viewport.interactive = true;
        if (canceled)
            root.syncFromStore();
        else
            DesktopMetadata.setOrder(committedOrder);
    }

    ListModel {
        id: desktopModel
    }

    Connections {
        target: DesktopMetadata
        function onStateChanged() {
            if (!root.reorderActive)
                root.syncFromStore();
        }
    }

    Component.onCompleted: syncFromStore()

    Flickable {
        id: viewport
        anchors.fill: parent
        contentWidth: Math.max(width, thumbnailRow.implicitWidth)
        contentHeight: height
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: thumbnailRow
            x: Math.max(0, (viewport.width - implicitWidth) / 2)
            y: viewport.height > implicitHeight
                ? (viewport.height - implicitHeight) / 2 : 0
            spacing: root.stripSpacing

            Repeater {
                id: workspaceRepeater
                model: desktopModel
                delegate: WorkspaceThumbnail {
                    required property int index
                    required workspaceId
                    required displayName
                    visualIndex: index
                    activeWorkspaceId: root.activeWorkspaceId
                    // Neighbors dim slightly while one desktop is being dragged.
                    opacity: root.reorderActive && workspaceId !== root.draggedWorkspaceId ? 0.86 : 1.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.OutCubic
                        }
                    }
                    monitorId: root.monitorId
                    monitorData: root.monitorData
                    width: root.thumbnailWidth
                    height: root.labelHeight + root.labelGap + root.thumbnailHeight
                    labelHeight: root.labelHeight
                    labelGap: root.labelGap
                    dropHovered: root.windowDropWorkspaceId === workspaceId
                    insertionBefore: root.reorderActive
                        && root.insertionWorkspaceId === workspaceId
                        && !root.insertionAfter
                    insertionAfter: root.reorderActive
                        && root.insertionWorkspaceId === workspaceId
                        && root.insertionAfter
                    onActivated: workspaceId => root.workspaceActivated(workspaceId)
                    onWindowMoveRequested: (address, workspaceId) => root.windowMoveRequested(address, workspaceId)
                    onRenameRequested: (workspaceId, name) => DesktopMetadata.renameWorkspace(workspaceId, name)
                    onDesktopDragStarted: workspaceId => root.beginReorder(workspaceId)
                    onDesktopDragMoved: (workspaceId, sceneX) =>
                        root.previewReorderAt(workspaceId, sceneX)
                    onDesktopDragHovered: (workspaceId, targetInsertionIndex, after) =>
                        root.previewReorder(workspaceId, targetInsertionIndex, after)
                    onDesktopDragFinished: (workspaceId, canceled) => root.finishReorder(workspaceId, canceled)

                    Behavior on x {
                        enabled: !root.reorderActive || workspaceId !== root.draggedWorkspaceId
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }
            }
        }
    }

    WheelHandler {
        target: viewport
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        orientation: Qt.Horizontal
    }
}
