pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Plugins
import qs.components
import qs.components.containers
import qs.services

StyledWindow {
    id: root

    required property pluginEntryPoint entryPoint
    readonly property string edge: entryPoint.properties.edge ?? "top"
    readonly property string alignment: entryPoint.properties.alignment ?? "center"
    // qmllint disable missing-property
    readonly property bool panelVisible: entryLoader.item?.panelVisible ?? true
    readonly property bool interactive: entryLoader.item?.panelInputEnabled ?? entryPoint.properties.interactive ?? false
    readonly property bool overFullscreen: entryLoader.item?.panelOverFullscreen ?? false
    // qmllint enable missing-property

    name: `plugin-${entryPoint.plugin.id.replace("/", "-")}`
    visible: entryLoader.status === EntryPointLoader.Ready && panelVisible
    implicitWidth: Math.max(1, entryLoader.implicitWidth)
    implicitHeight: Math.max(1, entryLoader.implicitHeight)

    anchors.top: edge === "top" || ((edge === "left" || edge === "right") && alignment === "start")
    anchors.bottom: edge === "bottom" || ((edge === "left" || edge === "right") && alignment === "end")
    anchors.left: edge === "left" || ((edge === "top" || edge === "bottom") && alignment === "start")
    anchors.right: edge === "right" || ((edge === "top" || edge === "bottom") && alignment === "end")

    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: overFullscreen ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        item: root.interactive ? entryLoader : null
        width: root.interactive ? root.width : 0
        height: root.interactive ? root.height : 0
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer
    }

    EntryPointLoader {
        id: entryLoader

        anchors.fill: parent
        entryPoint: root.entryPoint
    }

    HoverHandler {
        id: hover
    }

    Binding {
        // qmllint disable missing-property
        when: entryLoader.item !== null && "panelHostHovered" in entryLoader.item
        target: entryLoader.item
        property: "panelHostHovered"
        value: hover.hovered
        // qmllint enable missing-property
    }
}
