import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common"
import "../../common/functions"
import "../../services"

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: root
            required property var modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            readonly property bool monitorIsFocused: Hyprland.focusedMonitor?.id === monitor?.id
            readonly property bool closeOnFocusLoss: Config.options.overview.closeOnFocusLoss

            screen: modelData
            visible: GlobalStates.overviewOpen
            color: "transparent"
            implicitWidth: screen.width
            implicitHeight: screen.height

            WlrLayershell.namespace: Config.options.overview.effects.enableBlur
                ? "quickshell:overview-blur" : "quickshell:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors { top: true; bottom: true; left: true; right: true }

            Rectangle {
                anchors.fill: parent
                visible: Config.options.overview.effects.enableBackdrop
                color: Appearance.m3colors.m3shadow
                opacity: Config.options.overview.effects.backdropOpacity
            }

            TaskView {
                anchors.fill: parent
                panelWindow: root
            }

            HyprlandFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.monitorIsFocused
                active: false
                onCleared: {
                    if (root.closeOnFocusLoss && canBeActive)
                        GlobalStates.overviewOpen = false;
                }
            }

            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    if (GlobalStates.overviewOpen)
                        delayedGrabTimer.restart();
                    else
                        grab.active = false;
                }
            }

            Connections {
                target: Hyprland
                function onFocusedMonitorChanged() {
                    if (!GlobalStates.overviewOpen)
                        return;
                    grab.active = root.monitorIsFocused;
                }
            }

            Timer {
                id: delayedGrabTimer
                interval: Config.options.hacks.arbitraryRaceConditionDelay
                repeat: false
                onTriggered: {
                    if (grab.canBeActive)
                        grab.active = GlobalStates.overviewOpen;
                }
            }

        }
    }

    IpcHandler {
        target: "overview"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
    }
}
