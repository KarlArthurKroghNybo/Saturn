pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components.filedialog
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property string exportPath: Quickshell.env("HOME") + "/scenes.json"
    property FileDialog importPicker: FileDialog {
        filterLabel: Tr.tr("Scene JSON")
        filters: ["json"]
        title: Tr.tr("Import scenes")

        onAccepted: path => Scenes.importFile(path)
    }
    property var previewScene: null

    function edit(scene: var): void {
        nState.sceneDraft = JSON.parse(JSON.stringify(scene));
        nState.openSubPage(1);
    }

    title: Tr.tr("Scenes")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        spacing: Tokens.spacing.extraSmall / 2
        width: root.cappedWidth

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.small

            IconTextButton {
                disabled: !Scenes.loaded || Scenes.busy
                font: Tokens.font.body.large
                horizontalPadding: Tokens.padding.extraLarge
                icon: "add"
                isRound: true
                shapeMorph: true
                text: Tr.tr("New scene")
                verticalPadding: Tokens.padding.medium

                onClicked: root.edit({
                    id: "",
                    name: "",
                    icon: "bookmark",
                    settings: {}
                })
            }
            IconTextButton {
                disabled: !Scenes.loaded || Scenes.busy
                font: Tokens.font.body.large
                horizontalPadding: Tokens.padding.extraLarge
                icon: "bookmark_add"
                isRound: true
                shapeMorph: true
                text: Tr.tr("Save current")
                type: IconTextButton.Tonal
                verticalPadding: Tokens.padding.medium

                onClicked: {
                    Scenes.capture(Tr.tr("Current setup"));
                    root.edit(Scenes.scenes[Scenes.scenes.length - 1]);
                }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter

            TextButton {
                disabled: !Scenes.canUndo
                text: Tr.tr("Undo scene")
                type: TextButton.Text

                onClicked: Scenes.undo()
            }
            TextButton {
                disabled: Scenes.busy || !Scenes.scenes.some(s => s.favourite)
                text: Tr.tr("Next favourite")
                type: TextButton.Text

                onClicked: Scenes.cycle()
            }
        }
        InfoRow {
            first: true
            icon: "timer"
            label: Scenes.temporaryLabel
            last: true
            subtext: Tr.tr("The previous setup will be restored automatically")
            visible: Scenes.expiresAt > 0
        }
        TextButton {
            text: Tr.tr("Keep this setup")
            type: TextButton.Text
            visible: Scenes.expiresAt > 0

            onClicked: {
                Scenes.expiresAt = 0;
                Scenes.save();
            }
        }
        SectionHeader {
            first: true
            text: Tr.tr("Saved scenes")
        }
        Repeater {
            model: Scenes.scenes

            SceneRow {
                required property int index
                required property var modelData

                first: index === 0
                last: index === Scenes.scenes.length - 1
                scene: modelData

                onEdited: {
                    if (!Scenes.busy)
                        root.edit(scene);
                }
                onPreviewed: {
                    root.previewScene = scene;
                    previewDialog.open = true;
                }
            }
        }
        InfoRow {
            first: true
            icon: "bookmark_border"
            label: Tr.tr("No saved scenes")
            last: true
            subtext: Tr.tr("Save your current setup or create a scene to get started")
            visible: Scenes.loaded && Scenes.scenes.length === 0
        }
        ScenePreview {
            id: previewDialog

            dialogParent: root.flickable
            scene: root.previewScene
            visible: false
        }
        SectionHeader {
            text: Tr.tr("Automation")
        }
        ToggleRow {
            checked: Scenes.automationEnabled
            first: true
            last: true
            subtext: Scenes.automationLabel
            text: Tr.tr("Automatic activation")

            onToggled: Scenes.setAutomation(checked)
        }
        TextButton {
            text: Tr.tr("Resume automation")
            type: TextButton.Text
            visible: Scenes.automationEnabled && Scenes.automationPaused

            onClicked: Scenes.resumeAutomation()
        }
        SectionHeader {
            text: Tr.tr("Import & export")
        }
        RowLayout {
            TextButton {
                disabled: Scenes.busy
                text: Tr.tr("Import…")
                type: TextButton.Text

                onClicked: root.importPicker.open()
            }
            TextButton {
                text: Tr.tr("Export all…")
                type: TextButton.Text

                onClicked: exportDialog.open = true
            }
        }
        StyledText {
            Layout.fillWidth: true
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            text: Scenes.transferMessage
            visible: !!Scenes.transferMessage
            wrapMode: Text.Wrap
        }
        DialogRowButton {
            id: exportDialog

            acceptLabel: Tr.tr("Export")
            header: Tr.tr("Export all scenes")
            icon: "file_upload"
            label: Tr.tr("Export scenes")
            rootParent: root.flickable
            visible: false

            content: Component {
                ColumnLayout {
                    TextFieldRow {
                        first: true
                        label: Tr.tr("New file path")
                        last: true
                        value: root.exportPath

                        onValueEdited: value => root.exportPath = value
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Choose a new JSON file. Existing files are preserved.")
                        wrapMode: Text.Wrap
                    }
                }
            }

            onAccepted: Scenes.exportFile("all", root.exportPath)
        }
        InfoRow {
            first: true
            icon: "warning"
            iconColour: Colours.palette.m3error
            label: Tr.tr("Shortcut needs attention")
            last: true
            subtext: Scenes.shortcutFailures.join(" · ")
            visible: Scenes.shortcutFailures.length > 0
        }
        SectionHeader {
            text: Tr.tr("Could not apply")
            visible: Scenes.failures.length > 0
        }
        InfoRow {
            first: true
            icon: "warning"
            iconColour: Colours.palette.m3error
            label: Scenes.activeScene?.name || ""
            last: true
            subtext: Scenes.failures.join(" · ")
            visible: Scenes.failures.length > 0
        }
    }
}
