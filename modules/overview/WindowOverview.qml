import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../common"
import "../../services"
import "TaskViewGeometry.js" as TaskViewGeometry
import "WindowSelection.js" as WindowSelection

Item {
    id: root

    property int workspaceId: 1
    property int monitorId: -1
    property var monitorData: null
    property int recaptureToken: 0
    property var windowByAddress: HyprlandData.windowByAddress
    property var windowList: HyprlandData.windowList
    property string selectedAddress: ""
    readonly property var toplevels: ToplevelManager.toplevels
    signal windowDragStarted(string address)
    signal windowDragMoved(string address, real sceneX, real sceneY)
    signal windowDragFinished(string address, bool canceled)

    function toplevelForAddress(address) {
        const values = root.toplevels?.values ?? [];
        return values.find(candidate =>
            `0x${candidate?.HyprlandToplevel?.address ?? ""}` === `${address ?? ""}`
        ) ?? null;
    }

    readonly property var cards: {
        windowList;
        return (windowList ?? [])
            .filter(win => win?.workspace?.id === root.workspaceId
                && win?.monitor === root.monitorId
                && `${win?.address ?? ""}`.length > 0);
    }
    readonly property var cardAddresses: cards.map(card => `${card?.address ?? ""}`)
    readonly property real captionHeight: Math.max(40, Appearance.font.pixelSize.small + 22)
    readonly property var cardAspects: cards.map(windowData => {
        const size = windowData?.size ?? [16, 9];
        return Math.max(1, size[0] ?? 16) / Math.max(1, size[1] ?? 9);
    })
    readonly property var cardRects: {
        width;
        height;
        return TaskViewGeometry.arrangeCards(width, height, cardAspects, captionHeight);
    }

    function reconcileSelection() {
        root.selectedAddress = WindowSelection.reconcile(
            root.cardAddresses, root.selectedAddress);
        return root.selectedAddress;
    }

    function selectAddress(address) {
        root.selectedAddress = WindowSelection.reconcile(
            root.cardAddresses, address);
        return root.selectedAddress.length > 0;
    }

    function selectRelative(direction) {
        root.selectedAddress = WindowSelection.move(
            root.cardAddresses, root.selectedAddress, direction);
        return root.selectedAddress.length > 0;
    }

    function selectedCard() {
        for (let index = 0; index < cardRepeater.count; index += 1) {
            const card = cardRepeater.itemAt(index);
            if (card?.address === root.selectedAddress)
                return card;
        }
        return null;
    }

    function activateSelected() {
        root.reconcileSelection();
        return root.selectedCard()?.activateWindow() ?? false;
    }

    function closeSelected() {
        root.reconcileSelection();
        return root.selectedCard()?.closeWindow() ?? false;
    }

    function cancelActiveDrag() {
        for (let index = 0; index < cardRepeater.count; index += 1) {
            const card = cardRepeater.itemAt(index);
            if (card?.cancelWindowDrag())
                return true;
        }
        return false;
    }

    onCardsChanged: Qt.callLater(() => root.reconcileSelection())
    onWorkspaceIdChanged: {
        root.selectedAddress = "";
        Qt.callLater(() => root.reconcileSelection());
    }
    Component.onCompleted: root.reconcileSelection()

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen)
                root.reconcileSelection();
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.cards.length === 0
        text: `Workspace ${root.workspaceId} is empty`
        color: Appearance.colors.colSubtext
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
    }

    Repeater {
        id: cardRepeater
        model: root.cards
        delegate: WindowPreviewCard {
            required property var modelData
            required property int index
            readonly property var cardRect: root.cardRects[index] ?? ({ x: 0, y: 0, width: 1, height: 1 })
            x: cardRect.x
            y: cardRect.y
            width: cardRect.width
            height: cardRect.height
            captionHeight: root.captionHeight
            address: `${modelData?.address ?? ""}`
            toplevel: root.toplevelForAddress(address)
            windowData: modelData ?? null
            monitorId: root.monitorId
            recaptureToken: root.recaptureToken
            selected: root.selectedAddress === address
            onSelectionRequested: address => root.selectAddress(address)
            onWindowDragStarted: address => root.windowDragStarted(address)
            onWindowDragMoved: (address, sceneX, sceneY) =>
                root.windowDragMoved(address, sceneX, sceneY)
            onWindowDragFinished: (address, canceled) =>
                root.windowDragFinished(address, canceled)
        }
    }
}
