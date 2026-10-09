import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../common"
import "../../common/functions"
import "../../common/widgets"
import "../../services"

Item {
    id: root

    required property int workspaceId
    required property string displayName
    property int visualIndex: 0
    property int activeWorkspaceId: 1
    property int monitorId: -1
    property var monitorData: null
    property var windowByAddress: HyprlandData.windowByAddress
    property var windowList: HyprlandData.windowList
    readonly property var toplevels: ToplevelManager.toplevels
    property real labelHeight: 22
    property real labelGap: 5
    property bool dropHovered: false
    property bool hovered: false
    property bool headerHovered: false
    property bool editing: false
    property bool reorderDragging: false
    // Lift scale applied while this desktop is the one being dragged.
    property real dragLift: reorderDragging ? 1.045 : 1.0
    property bool insertionBefore: false
    property bool insertionAfter: false
    signal activated(int workspaceId)
    signal windowMoveRequested(string address, int workspaceId)
    signal renameRequested(int workspaceId, string name)
    signal desktopDragStarted(int workspaceId)
    signal desktopDragMoved(int workspaceId, real sceneX)
    signal desktopDragHovered(int workspaceId, int targetInsertionIndex, bool after)
    signal desktopDragFinished(int workspaceId, bool canceled)

    z: root.reorderDragging ? 10 : 1

    // Lift the dragged desktop above its neighbors; siblings slide out of the
    // way through the strip's temporary model order.
    transform: Scale {
        xScale: root.dragLift
        yScale: root.dragLift
        origin.x: root.width / 2
        origin.y: root.height / 2
    }

    Behavior on dragLift {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    function toplevelForAddress(address) {
        const values = root.toplevels?.values ?? [];
        return values.find(candidate =>
            `0x${candidate?.HyprlandToplevel?.address ?? ""}` === `${address ?? ""}`
        ) ?? null;
    }

    function containsWindowDropPoint(sceneX, sceneY) {
        const local = previewFrame.mapFromItem(null, sceneX, sceneY);
        return local.x >= 0 && local.x <= previewFrame.width
            && local.y >= 0 && local.y <= previewFrame.height;
    }

    function beginRename() {
        root.editing = true;
        renameField.text = root.displayName;
        renameField.forceActiveFocus();
        renameField.selectAll();
    }

    function commitRename() {
        if (!root.editing)
            return;
        const value = renameField.text;
        root.editing = false;
        root.renameRequested(root.workspaceId, value);
    }

    function cancelRename() {
        if (!root.editing)
            return;
        root.editing = false;
        renameField.text = root.displayName;
    }

    readonly property bool active: workspaceId === activeWorkspaceId
    readonly property real sourceWidth: monitorData?.transform % 2 === 1
        ? (monitorData?.height ?? 0) : (monitorData?.width ?? 0)
    readonly property real sourceHeight: monitorData?.transform % 2 === 1
        ? (monitorData?.width ?? 0) : (monitorData?.height ?? 0)
    readonly property real usableWidth: sourceWidth
        - (monitorData?.reserved?.[0] ?? 0) - (monitorData?.reserved?.[2] ?? 0)
    readonly property real usableHeight: sourceHeight
        - (monitorData?.reserved?.[1] ?? 0) - (monitorData?.reserved?.[3] ?? 0)
    readonly property var windowToplevels: {
        windowList;
        return (windowList ?? [])
            .filter(win => win?.workspace?.id === root.workspaceId
                && `${win?.address ?? ""}`.length > 0);
    }
    readonly property int windowCount: windowToplevels.length
    readonly property bool occupied: windowCount > 0

    Item {
        id: labelArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.labelHeight

        Rectangle {
            id: editBackdrop
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            radius: Appearance.rounding.small
            color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 0.55)
            border.width: 1
            border.color: ColorUtils.applyAlpha(
                Appearance.colors.colOnLayer0, 0.30)
            opacity: root.editing ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                radius: 1
                color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.5)
            }
        }

        Text {
            id: workspaceLabel
            visible: !root.editing
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            text: root.displayName
            color: root.dropHovered
                ? Appearance.colors.colPrimary
                : root.active
                ? Appearance.colors.colOnLayer0
                : (root.headerHovered
                    ? Appearance.colors.colOnLayer1
                    : Appearance.colors.colSubtext)
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: root.active ? Font.DemiBold : Font.Normal
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        TextInput {
            id: renameField
            visible: root.editing
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            color: Appearance.colors.colOnLayer0
            selectionColor: Appearance.colors.colPrimary
            selectedTextColor: Appearance.colors.colOnPrimary
            cursorDelegate: Rectangle {
                width: 1
                color: Appearance.colors.colOnLayer1
            }
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smaller
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            onActiveFocusChanged: {
                if (!activeFocus && root.editing)
                    root.commitRename();
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.commitRename();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.cancelRename();
                    event.accepted = true;
                }
            }
        }

        Item {
            id: dragProxy
            width: 1
            height: 1
            property int workspaceId: root.workspaceId
            Drag.active: reorderHandle.drag.active && !root.editing
            Drag.source: dragProxy
            Drag.keys: ["hyprland-overview-desktop-reorder"]
            Drag.supportedActions: Qt.MoveAction
            Drag.mimeData: ({
                "application/x-hyprland-overview-desktop-id": `${root.workspaceId}`
            })
        }

        MouseArea {
            id: reorderHandle
            anchors.fill: parent
            enabled: !root.editing
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: root.reorderDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onEntered: root.headerHovered = true
            onExited: root.headerHovered = false
            drag.target: dragProxy
            drag.axis: Drag.XAxis
            drag.threshold: 8
            property bool announced: false
            onPressed: {
                announced = false;
                dragProxy.x = 0;
                dragProxy.y = 0;
            }
            onPositionChanged: mouse => {
                if (drag.active && !announced) {
                    announced = true;
                    root.reorderDragging = true;
                    root.desktopDragStarted(root.workspaceId);
                }
                if (announced) {
                    const scenePosition = root.mapToItem(null, mouse.x, mouse.y);
                    root.desktopDragMoved(root.workspaceId, scenePosition.x);
                }
            }
            onReleased: {
                const wasDragging = announced;
                announced = false;
                root.reorderDragging = false;
                dragProxy.x = 0;
                dragProxy.y = 0;
                if (wasDragging)
                    root.desktopDragFinished(root.workspaceId, false);
            }
            onCanceled: {
                const wasDragging = announced;
                announced = false;
                root.reorderDragging = false;
                dragProxy.x = 0;
                dragProxy.y = 0;
                if (wasDragging)
                    root.desktopDragFinished(root.workspaceId, true);
            }
            onDoubleClicked: root.beginRename()
        }

        DropArea {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width / 2
            keys: ["hyprland-overview-desktop-reorder"]
            onEntered: drag => {
                const workspaceId = Number(drag.source?.workspaceId ?? -1);
                root.desktopDragHovered(workspaceId, root.visualIndex, false);
            }
        }

        DropArea {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width / 2
            keys: ["hyprland-overview-desktop-reorder"]
            onEntered: drag => {
                const workspaceId = Number(drag.source?.workspaceId ?? -1);
                root.desktopDragHovered(workspaceId, root.visualIndex + 1, true);
            }
        }
    }

    Rectangle {
        id: previewFrame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(1, root.height - root.labelHeight - root.labelGap)
        radius: Appearance.rounding.small
        readonly property real previewInset: 3
        color: ColorUtils.applyAlpha(
            root.active || root.dropHovered
                ? Appearance.colors.colSecondaryContainer
                : Appearance.colors.colLayer1,
            Config.options.overview.effects.workspaceOpacity
                * (root.occupied ? 1.0 : 0.9)
        )
        border.width: root.active || root.dropHovered ? 2
            : root.hovered ? 2 : 1
        border.color: {
            if (root.active || root.dropHovered)
                return Appearance.colors.colPrimary;
            if (root.hovered)
                return ColorUtils.applyAlpha(
                    Appearance.colors.colOnLayer0, 0.45);
            return ColorUtils.applyAlpha(
                Appearance.colors.colOutline,
                Config.options.overview.effects.glassBorderOpacity);
        }
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: previewFrameMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Item {
            id: previewArea
            anchors.fill: parent
            anchors.margins: previewFrame.previewInset
            clip: true

            Repeater {
                model: root.windowToplevels
                delegate: WindowPreviewSurface {
                    required property var modelData
                    readonly property string address: `${modelData?.address ?? ""}`
                    readonly property bool singleWindowPreview: root.windowCount === 1
                    windowData: modelData ?? null
                    readonly property real horizontalScale: previewArea.width / Math.max(1, root.usableWidth)
                    readonly property real verticalScale: previewArea.height / Math.max(1, root.usableHeight)
                    readonly property real fittedScale: Math.min(horizontalScale, verticalScale)
                    cropToFill: singleWindowPreview ? true
                        : Config.options.windowPreview.cropToFill
                    cornerRadius: singleWindowPreview
                        ? Math.max(0,
                            previewFrame.radius - previewFrame.previewInset)
                        : Appearance.rounding.windowRounding
                    x: singleWindowPreview ? 0
                        : Math.max(0, ((windowData?.at?.[0] ?? root.monitorData?.x ?? 0)
                            - (root.monitorData?.x ?? 0)) * fittedScale)
                    y: singleWindowPreview ? 0
                        : Math.max(0, ((windowData?.at?.[1] ?? root.monitorData?.y ?? 0)
                            - (root.monitorData?.y ?? 0)) * fittedScale)
                    width: singleWindowPreview ? previewArea.width
                        : Math.max(8, (windowData?.size?.[0] ?? 1) * fittedScale)
                    height: singleWindowPreview ? previewArea.height
                        : Math.max(6, (windowData?.size?.[1] ?? 1) * fittedScale)
                    toplevel: root.toplevelForAddress(address)
                    monitorId: root.monitorId
                }
            }
        }

        LiquidGlassMaterial {
            anchors.fill: parent
            radius: previewFrame.radius
            strength: root.active || root.dropHovered ? 0.92 : 0.72
            active: root.active || root.dropHovered
            highlightColor: Appearance.colors.colOnLayer1
        }

        Rectangle {
            id: windowDropTarget
            z: 2
            anchors.centerIn: parent
            width: Math.min(parent.width - 16, dropTargetText.implicitWidth + 24)
            height: 28
            radius: Appearance.rounding.normal
            opacity: root.dropHovered ? 1 : 0
            scale: root.dropHovered ? 1 : 0.94
            color: ColorUtils.applyAlpha(
                Appearance.colors.colPrimary,
                Math.min(0.92, Config.options.overview.effects.panelOpacity + 0.14)
            )
            border.width: 1
            border.color: ColorUtils.applyAlpha(
                Appearance.colors.colOnPrimary, 0.56)

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                id: dropTargetText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, windowDropTarget.width - 16)
                text: `Move to ${root.displayName}`
                color: Appearance.colors.colOnPrimary
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Rectangle {
            id: activeUnderline
            z: 1
            visible: root.active
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: Math.min(52, parent.width * 0.24)
            height: 3
            radius: 2
            color: Appearance.colors.colPrimary
        }
    }

    Item {
        id: previewFrameMask
        x: previewFrame.x
        y: previewFrame.y
        width: previewFrame.width
        height: previewFrame.height
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: previewFrame.radius
        }
    }

    Rectangle {
        id: insertionBeforeIndicator
        anchors.left: parent.left
        anchors.leftMargin: -Math.max(3, root.labelGap / 2)
        anchors.verticalCenter: previewFrame.verticalCenter
        width: 4
        height: previewFrame.height * 0.8
        radius: width / 2
        color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.85)
        opacity: root.reorderDragging ? 0 : (root.insertionBefore ? 1 : 0)
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        id: insertionAfterIndicator
        anchors.right: parent.right
        anchors.rightMargin: -Math.max(3, root.labelGap / 2)
        anchors.verticalCenter: previewFrame.verticalCenter
        width: 4
        height: previewFrame.height * 0.8
        radius: width / 2
        color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.85)
        opacity: root.reorderDragging ? 0 : (root.insertionAfter ? 1 : 0)
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: previewClickArea
        anchors.fill: previewFrame
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered = true
        onExited: root.hovered = false
        onClicked: {
            if (root.workspaceId >= 1 && root.workspaceId <= 10)
                root.activated(root.workspaceId);
        }
    }

}
