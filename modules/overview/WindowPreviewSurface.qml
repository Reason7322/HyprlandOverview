import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import "../../common"
import "../../services"

Item {
    id: root

    property var toplevel: null
    property var windowData: null
    property int monitorId: -1
    property int recaptureToken: 0
    property real cornerRadius: Appearance.rounding.windowRounding
    property bool previewCaptureEnabled: true
    property bool cropToFill: Config.options.windowPreview.cropToFill
    readonly property bool previewsEnabled: Config.options.overview.previewsEnabled
    readonly property string previewMode: {
        const mode = `${Config.options.overview.previewMode ?? "live"}`.trim().toLowerCase();
        return (mode === "event" || mode === "snapshot") ? "event" : "live";
    }
    readonly property bool livePreviewEnabled: previewsEnabled && previewMode === "live"
    readonly property bool shouldCapture: {
        if (!GlobalStates.overviewOpen || !previewsEnabled || !previewCaptureEnabled)
            return false;
        if (!toplevel || !windowData)
            return false;
        return Config.options.overview.includeInactiveMonitorPreviews
            || (windowData?.monitor ?? -1) === monitorId;
    }

    clip: true

    ScreencopyView {
        id: preview
        readonly property real srcAspect: {
            const sourceWidth = root.windowData?.size?.[0] ?? 0;
            const sourceHeight = root.windowData?.size?.[1] ?? 0;
            return sourceWidth > 0 && sourceHeight > 0 ? sourceWidth / sourceHeight : 1;
        }
        anchors.centerIn: parent
        width: root.cropToFill
            ? Math.max(root.width, root.height * srcAspect)
            : Math.min(root.width, root.height * srcAspect)
        height: root.cropToFill
            ? Math.max(root.height, root.width / Math.max(0.01, srcAspect))
            : Math.min(root.height, root.width / Math.max(0.01, srcAspect))
        captureSource: root.shouldCapture ? root.toplevel : null
        live: root.livePreviewEnabled
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: previewMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    Item {
        id: previewMask
        anchors.fill: preview
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
        }
    }

    function refreshCapture() {
        if (!GlobalStates.overviewOpen || root.livePreviewEnabled || !root.previewsEnabled)
            return;
        root.previewCaptureEnabled = false;
        previewResetTimer.restart();
    }

    Timer {
        id: previewResetTimer
        interval: Math.max(1, Config.options.overview.previewRecaptureDelayMs)
        repeat: false
        onTriggered: root.previewCaptureEnabled = true
    }

    onRecaptureTokenChanged: {
        if (recaptureToken > 0)
            refreshCapture();
    }
}
