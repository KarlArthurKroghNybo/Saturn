pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

ConnectedRect {
    id: root

    required property var scene
    readonly property bool selected: Scenes.lastId === scene.id

    signal edited
    signal previewed

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + Tokens.padding.large * 2

    StateLayer {
        onClicked: root.edited()
    }
    RowLayout {
        id: content

        anchors.left: parent.left
        anchors.margins: Tokens.padding.largeIncreased
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.medium

        StyledRect {
            color: root.selected ? Colours.palette.m3primaryContainer : Colours.palette.m3secondaryContainer
            implicitHeight: implicitWidth
            implicitWidth: symbol.implicitWidth + Tokens.padding.medium * 2
            radius: Tokens.rounding.full

            MaterialIcon {
                id: symbol

                anchors.centerIn: parent
                color: root.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer
                fill: root.selected ? 1 : 0
                fontStyle: Tokens.font.icon.medium
                text: root.scene.icon
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font: Tokens.font.body.medium
                text: root.scene.name
            }
            StyledText {
                Layout.fillWidth: true
                animate: true
                color: root.selected && Scenes.failures.length ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
                font: Tokens.font.label.small
                text: root.selected ? Scenes.statusLabel + " · " + Scenes.describe(root.scene.settings) : Scenes.describe(root.scene.settings)
            }
        }
        MaterialIcon {
            color: Colours.palette.m3primary
            fill: 1
            fontStyle: Tokens.font.icon.small
            text: "star"
            visible: root.scene.favourite || false
        }
        IconButton {
            disabled: Scenes.busy
            icon: "visibility"
            type: IconButton.Text

            onClicked: root.previewed()
        }
        IconButton {
            disabled: Scenes.busy
            icon: "edit"
            type: IconButton.Text

            onClicked: root.edited()
        }
        IconButton {
            disabled: Scenes.busy
            icon: root.selected && !Scenes.customized && !Scenes.failures.length ? "check" : "play_arrow"
            isRound: true
            type: IconButton.Tonal

            onClicked: Scenes.activate(root.scene.id)
        }
    }
}
