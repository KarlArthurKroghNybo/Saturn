pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus

ColumnLayout {
    id: root

    spacing: Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.small
            text: "bookmark"
        }
        StyledText {
            font: Tokens.font.body.medium
            text: Tr.tr("Scenes")
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.spacing.small
            animate: true
            color: Scenes.failures.length ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            elide: Text.ElideRight
            font: Tokens.font.label.small
            text: Scenes.activeScene ? `${Scenes.activeScene.name} · ${Scenes.temporaryLabel || Scenes.statusLabel}` : Tr.tr("Choose a scene")
        }
        IconButton {
            disabled: !Scenes.canUndo
            icon: "undo"
            type: IconButton.Text

            onClicked: Scenes.undo()
        }
        IconButton {
            disabled: Scenes.busy || !Scenes.scenes.some(s => s.favourite)
            icon: "skip_next"
            type: IconButton.Text

            onClicked: Scenes.cycle()
        }
        IconButton {
            disabled: !Scenes.loaded || Scenes.busy
            icon: "bookmark_add"
            type: IconButton.Text

            onClicked: Scenes.capture(Tr.tr("Current setup"))
        }
        IconButton {
            icon: "tune"
            type: IconButton.Text

            onClicked: WindowFactory.create(null, {
                initialPage: PageRegistry.scenesIndex
            })
        }
    }
    GridLayout {
        Layout.fillWidth: true
        columnSpacing: Tokens.spacing.small
        columns: Math.max(1, Math.min(4, Scenes.scenes.length))
        rowSpacing: Tokens.spacing.small

        Repeater {
            model: Scenes.scenes

            StyledRect {
                id: tile

                required property var modelData
                readonly property bool selected: Scenes.lastId === modelData.id

                Layout.fillWidth: true
                Layout.preferredWidth: 1
                color: selected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
                implicitHeight: row.implicitHeight + Tokens.padding.medium * 2
                opacity: Scenes.busy ? 0.6 : 1
                radius: stateLayer.pressed ? Tokens.rounding.medium : Tokens.rounding.large

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
                Behavior on radius {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                StateLayer {
                    id: stateLayer

                    disabled: Scenes.busy || !Scenes.loaded

                    onClicked: Scenes.activate(tile.modelData.id)
                }
                RowLayout {
                    id: row

                    anchors.left: parent.left
                    anchors.margins: Tokens.padding.medium
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        color: tile.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3secondary
                        fill: tile.selected ? 1 : 0
                        fontStyle: Tokens.font.icon.medium
                        text: tile.modelData.icon
                    }
                    StyledText {
                        Layout.fillWidth: true
                        color: tile.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        elide: Text.ElideRight
                        font: Tokens.font.body.small
                        text: tile.modelData.name
                    }
                    MaterialIcon {
                        color: Scenes.failures.length ? Colours.palette.m3error : Colours.palette.m3onSecondaryContainer
                        fontStyle: Tokens.font.icon.small
                        text: Scenes.failures.length ? "warning" : Scenes.customized ? "edit" : "check"
                        visible: tile.selected
                    }
                }
            }
        }
        StyledText {
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            text: Tr.tr("Save your current setup to get started")
            visible: Scenes.scenes.length === 0
        }
    }
}
