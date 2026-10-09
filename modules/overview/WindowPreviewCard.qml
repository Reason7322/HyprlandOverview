import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../common"
import "../../common/functions"
import "../../common/widgets"
import "../../services"

Item {
    id: root

    required property string address
    required property var toplevel
    required property var windowData
    property int monitorId: -1
    property int recaptureToken: 0
    property real captionHeight: 44
    property int dropWorkspaceId: -1
    property bool selected: false
    property bool pressed: false
    property bool dragCancellationRequested: false
    property point dragPressScene: Qt.point(0, 0)
    readonly property bool hovered: cardHoverHandler.hovered || closeArea.containsMouse
    readonly property bool dragging: dragHandler.active
    property real interactionScale: dragging ? 1.035 : (pressed ? 0.992 : 1.0)
    signal selectionRequested(string address)
    signal windowDragStarted(string address)
    signal windowDragMoved(string address, real sceneX, real sceneY)
    signal windowDragFinished(string address, bool canceled)

    readonly property var desktopEntry: {
        DesktopEntries.applications.values;
        return DesktopEntries.heuristicLookup(windowData?.class ?? "");
    }
    readonly property string iconName: {
        const raw = `${desktopEntry?.icon ?? ""}`.replace(/^image:\/\/icon\//, "").split("?")[0].trim();
        return raw.length > 0 ? raw : "application-x-executable";
    }

    z: root.dragging ? 50 : (root.selected ? 4 : (root.hovered ? 3 : 1))

    Behavior on interactionScale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    function activateWindow() {
        if (!/^0x[0-9a-f]+$/i.test(root.address))
            return false;
        GlobalStates.overviewOpen = false;
        if (Hyprland.usingLua)
            Hyprland.dispatch(`hl.dsp.focus({ window = 'address:${root.address}' })`);
        else
            Hyprland.dispatch(`focuswindow address:${root.address}`);
        return true;
    }

    function closeWindow() {
        if (!/^0x[0-9a-f]+$/i.test(root.address))
            return false;
        if (Hyprland.usingLua)
            Hyprland.dispatch(`hl.dsp.window.close('address:${root.address}')`);
        else
            Hyprland.dispatch(`closewindow address:${root.address}`);
        return true;
    }

    function cancelWindowDrag() {
        if (!dragHandler.active)
            return false;
        root.dragCancellationRequested = true;
        dragHandler.enabled = false;
        Qt.callLater(() => dragHandler.enabled = true);
        return true;
    }

    Item {
        id: dragProxy
        x: root.dragging ? dragHandler.activeTranslation.x : 0
        y: root.dragging ? dragHandler.activeTranslation.y : 0
        width: 1
        height: 1

        Behavior on x {
            enabled: !root.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.OutCubic
            }
        }

        Behavior on y {
            enabled: !root.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.OutCubic
            }
        }

    }

    Item {
        id: cardVisual
        anchors.fill: parent
        transform: [
            Translate {
                x: dragProxy.x
                y: dragProxy.y
            },
            Scale {
                xScale: root.interactionScale
                yScale: root.interactionScale
                origin.x: root.width / 2
                origin.y: root.height / 2
            }
        ]

    Rectangle {
        id: previewFrame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        width: parent.width
        height: Math.max(1, root.height - root.captionHeight)
        radius: Appearance.rounding.windowRounding
        readonly property real contentInset: border.width
        color: ColorUtils.applyAlpha(
            root.pressed ? Appearance.colors.colLayer2Active
                : root.hovered ? Appearance.colors.colLayer2Hover
                : Appearance.colors.colLayer2,
            Config.options.overview.effects.panelOpacity
        )
        border.width: root.selected || root.hovered ? 2 : 1
        border.color: root.selected
            ? Appearance.colors.colPrimary
            : root.hovered
                ? ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.58)
                : ColorUtils.applyAlpha(Appearance.colors.colOutline, Config.options.overview.effects.glassBorderOpacity)
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: previewFrameMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        WindowPreviewSurface {
            anchors.fill: parent
            anchors.margins: previewFrame.contentInset
            cornerRadius: Math.max(0,
                previewFrame.radius - previewFrame.contentInset)
            toplevel: root.toplevel
            windowData: root.windowData
            monitorId: root.monitorId
            recaptureToken: root.recaptureToken
        }

        LiquidGlassMaterial {
            anchors.fill: parent
            radius: previewFrame.radius
            strength: root.selected ? 1.26 : (root.hovered ? 1.16 : 1.0)
            active: root.selected || root.hovered
        }

        Rectangle {
            id: closeButton
            z: 3
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: 30
            height: 30
            radius: width / 2
            opacity: root.hovered || root.selected ? 1 : 0
            scale: closeArea.pressed ? 0.92 : (closeArea.containsMouse ? 1.06 : 1)
            color: ColorUtils.applyAlpha(
                closeArea.containsMouse
                    ? Appearance.colors.colLayer2Active
                    : Appearance.colors.colLayer1,
                0.92
            )
            border.width: 1
            border.color: ColorUtils.applyAlpha(
                closeArea.containsMouse
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer1,
                closeArea.containsMouse ? 0.92 : 0.42
            )

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
                anchors.centerIn: parent
                text: "×"
                color: Appearance.colors.colOnLayer1
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.larger
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onPressed: root.selectionRequested(root.address)
                onClicked: event => {
                    root.closeWindow();
                    event.accepted = true;
                }
            }
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

    // Small restrained caption beneath the preview, Windows 11 style.
    Item {
        id: captionArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.captionHeight

        Rectangle {
            id: captionPill
            anchors.centerIn: parent
            width: Math.min(parent.width,
                Math.max(120, captionText.implicitWidth
                    + (Config.options.windowPreview.showIcons ? 46 : 24)))
            height: Math.min(32, Math.max(26, parent.height - 8))
            radius: Appearance.rounding.normal
            color: ColorUtils.applyAlpha(
                Appearance.colors.colLayer1,
                Math.min(0.92, Config.options.overview.effects.panelOpacity + 0.18)
            )
            border.width: 1
            border.color: root.selected
                ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.82)
                : ColorUtils.applyAlpha(
                    Appearance.colors.colOutline,
                    Config.options.overview.effects.glassBorderOpacity
                )

            LiquidGlassMaterial {
                anchors.fill: parent
                radius: captionPill.radius
                strength: 0.72
                highlightColor: Appearance.colors.colOnLayer1
            }

            RowLayout {
                id: captionRow
                z: 1
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6

                Image {
                    visible: Config.options.windowPreview.showIcons
                    source: Quickshell.iconPath(root.iconName, "image-missing")
                    sourceSize: Qt.size(16, 16)
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                }
                Text {
                    id: captionText
                    Layout.fillWidth: true
                    text: root.windowData?.title ?? root.windowData?.class ?? ""
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }

    }

    HoverHandler {
        id: cardHoverHandler
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    }

    TapHandler {
        id: cardTapHandler
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onPressedChanged: {
            root.pressed = pressed;
            if (pressed) {
                root.selectionRequested(root.address);
                root.dragPressScene = root.mapToItem(null,
                    point.position.x, point.position.y);
            }
        }
        onTapped: (eventPoint, button) => {
            if (button === Qt.LeftButton) {
                root.activateWindow();
            } else if (button === Qt.MiddleButton) {
                root.closeWindow();
            }
        }
    }

    DragHandler {
        id: dragHandler
        target: null
        acceptedButtons: Qt.LeftButton
        onActiveTranslationChanged: {
            if (active)
                root.windowDragMoved(root.address,
                    root.dragPressScene.x + activeTranslation.x,
                    root.dragPressScene.y + activeTranslation.y);
        }
        onActiveChanged: {
            if (active) {
                root.dragCancellationRequested = false;
                root.selectionRequested(root.address);
                root.windowDragStarted(root.address);
                root.windowDragMoved(root.address,
                    root.dragPressScene.x + activeTranslation.x,
                    root.dragPressScene.y + activeTranslation.y);
            } else {
                const canceled = root.dragCancellationRequested;
                root.dragCancellationRequested = false;
                root.pressed = false;
                root.windowDragFinished(root.address, canceled);
            }
        }
        onCanceled: root.dragCancellationRequested = true
    }
}
