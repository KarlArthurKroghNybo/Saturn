pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.I18n
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.modules.nexus.common
import "../../../utils/SceneValidation.js" as SceneValidation

PageBase {
    id: root

    readonly property list<MenuItem> dndItems: [
        MenuItem {
            icon: "remove"
            text: Tr.tr("Keep current")
        },
        MenuItem {
            icon: "do_not_disturb_on"
            text: Tr.tr("On")
        },
        MenuItem {
            icon: "notifications_active"
            text: Tr.tr("Off")
        }
    ]
    readonly property var draft: nState.sceneDraft
    property string exportPath: ""
    property var profiles: []
    property string rgbInfo: ""
    property Process rgbProcess: Process {
        id: rgbProc

        command: [Quickshell.env("HOME") + "/.local/bin/caelestia-openrgb", "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.profiles = result.profiles || [];
                    root.rgbInfo = result.available ? (root.profiles.length ? "" : Tr.tr("No saved OpenRGB profiles")) : Tr.tr("OpenRGB is unavailable");
                } catch (e) {
                    root.rgbInfo = Tr.tr("OpenRGB is unavailable");
                }
            }
        }

        onExited: (code, status) => {
            if (code !== 0)
                root.rgbInfo = Tr.tr("OpenRGB is unavailable");
        }
    }
    property Timer rgbTimeout: Timer {
        interval: 12000
        running: rgbProc.running

        onTriggered: {
            rgbProc.running = false;
            root.rgbInfo = Tr.tr("OpenRGB did not respond");
        }
    }
    property FileDialog wallpaperPicker: FileDialog {
        filterLabel: Tr.tr("Image files")
        filters: ["jpg", "jpeg", "png", "webp", "gif", "avif", "bmp"]
        title: Tr.tr("Select a wallpaper")

        onAccepted: path => root.setting("wallpaper", path)
    }

    function meta(key: string, value: var): void {
        const next = JSON.parse(JSON.stringify(draft));
        next[key] = value;
        nState.sceneDraft = next;
    }
    function setting(key: string, value: var): void {
        const next = JSON.parse(JSON.stringify(draft));
        if (value === null)
            delete next.settings[key];
        else
            next.settings[key] = value;
        nState.sceneDraft = next;
    }

    isSubPage: true
    title: draft?.id ? draft.name || Tr.tr("Edit scene") : Tr.tr("New scene")

    Component.onCompleted: rgbProc.running = true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        enabled: !Scenes.busy
        spacing: Tokens.spacing.extraSmall / 2
        width: root.cappedWidth

        SectionHeader {
            first: true
            text: Tr.tr("General")
        }
        TextFieldRow {
            first: true
            label: Tr.tr("Name")
            value: root.draft?.name ?? ""

            onValueEdited: value => root.meta("name", value)
        }
        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: iconChoices.implicitHeight + Tokens.padding.medium * 2
            last: true

            Flow {
                id: iconChoices

                anchors.left: parent.left
                anchors.margins: Tokens.padding.largeIncreased
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacing.small

                Repeater {
                    model: ["code", "sports_esports", "self_improvement", "headphones", "bedtime", "work", "bookmark", "movie", "nightlight", "coffee", "palette", "rocket_launch"]

                    IconButton {
                        required property string modelData

                        checked: root.draft?.icon === modelData
                        icon: modelData
                        isToggle: true
                        type: IconButton.Tonal

                        onClicked: {
                            root.meta("icon", modelData);
                            internalChecked = checked;
                        }
                    }
                }
            }
        }
        SectionHeader {
            text: Tr.tr("Appearance")
        }
        ToggleRow {
            checked: root.draft !== null && "wallpaper" in root.draft.settings
            first: true
            last: !checked
            subtext: checked ? Tr.tr("Use a saved wallpaper") : Tr.tr("Keep the current wallpaper")
            text: Tr.tr("Wallpaper")

            onToggled: root.setting("wallpaper", checked ? Scenes.currentWallpaper : null)
        }
        TextFieldRow {
            label: Tr.tr("Wallpaper")
            last: true
            subtext: Tr.tr("Image file")
            value: root.draft?.settings.wallpaper ?? ""
            visible: root.draft !== null && "wallpaper" in root.draft.settings && !root.draft.settings.wallpaper.startsWith("waywallen:")

            onValueEdited: value => root.setting("wallpaper", value)
        }
        InfoRow {
            label: Tr.tr("Wallpaper")
            last: true
            value: Scenes.wallpaperChoices.find(w => w.id === root.draft?.settings.wallpaper)?.label || Tr.tr("Saved wallpaper unavailable")
            visible: !!root.draft?.settings.wallpaper?.startsWith("waywallen:")
        }
        DialogSelectButton {
            acceptLabel: Tr.tr("Select")
            header: Tr.tr("Select a wallpaper")
            icon: "wallpaper"
            label: Tr.tr("Wallpaper library")
            model: Scenes.wallpaperChoices
            rootParent: root.flickable
            visible: root.draft !== null && "wallpaper" in root.draft.settings && Scenes.wallpaperChoices.length > 0

            onAccepted: root.setting("wallpaper", selectedItem)
        }
        RowLayout {
            visible: root.draft !== null && "wallpaper" in root.draft.settings

            TextButton {
                text: Tr.tr("Use current")
                type: TextButton.Text

                onClicked: root.setting("wallpaper", Scenes.currentWallpaper)
            }
            TextButton {
                text: Tr.tr("Browse…")
                type: TextButton.Text

                onClicked: root.wallpaperPicker.open()
            }
        }
        SectionHeader {
            text: Tr.tr("Lighting")
        }
        ToggleRow {
            checked: root.draft !== null && "rgbProfile" in root.draft.settings
            first: true
            last: !checked
            subtext: checked ? Tr.tr("Load an OpenRGB profile") : Tr.tr("Keep the current lighting")
            text: Tr.tr("OpenRGB profile")

            onToggled: root.setting("rgbProfile", checked ? (root.profiles[0] || Scenes.rgbState.profile || "") : null)
        }
        TextFieldRow {
            label: Tr.tr("Profile")
            last: true
            subtext: root.rgbInfo
            value: root.draft?.settings.rgbProfile ?? ""
            visible: root.draft !== null && "rgbProfile" in root.draft.settings

            onValueEdited: value => root.setting("rgbProfile", value)
        }
        DialogSelectButton {
            acceptLabel: Tr.tr("Select")
            header: Tr.tr("OpenRGB profile")
            icon: "palette"
            label: Tr.tr("Choose profile")
            model: root.profiles.map(p => ({
                        id: p,
                        label: p
                    }))
            rootParent: root.flickable
            visible: root.draft !== null && "rgbProfile" in root.draft.settings && root.profiles.length > 0

            onAccepted: root.setting("rgbProfile", selectedItem)
        }
        SectionHeader {
            text: Tr.tr("Audio")
        }
        ToggleRow {
            checked: root.draft !== null && "sink" in root.draft.settings
            first: true
            last: !checked
            subtext: checked ? Tr.tr("Switch to the selected device") : Tr.tr("Keep the current output")
            text: Tr.tr("Output device")

            onToggled: root.setting("sink", checked ? (Audio.sink?.name || "") : null)
        }
        AudioDeviceList {
            currentId: Audio.sinks.find(n => n.name === root.draft?.settings.sink)?.id ?? -1
            iconName: "speaker"
            nodes: Audio.sinks
            placeholderIcon: "speaker"
            placeholderText: Tr.tr("No output devices")
            visible: root.draft !== null && "sink" in root.draft.settings

            onSelected: node => root.setting("sink", node.name)
        }
        StyledText {
            Layout.fillWidth: true
            color: Colours.palette.m3error
            text: Tr.tr("Saved output unavailable")
            visible: !!root.draft?.settings.sink && !Audio.sinks.some(n => n.name === root.draft.settings.sink)
            wrapMode: Text.Wrap
        }
        ToggleRow {
            Layout.topMargin: Tokens.spacing.small
            checked: root.draft !== null && "volume" in root.draft.settings
            first: true
            last: !checked
            subtext: checked ? Tr.tr("Set the output volume") : Tr.tr("Keep the current volume")
            text: Tr.tr("Volume")

            onToggled: root.setting("volume", checked ? Math.min(1, Audio.volume) : null)
        }
        SliderRow {
            icon: "volume_up"
            label: Tr.tr("Volume")
            last: true
            value: root.draft?.settings.volume ?? 0
            valueLabel: `${Math.round(value * 100)} %`
            visible: root.draft !== null && "volume" in root.draft.settings

            onMoved: value => root.setting("volume", value)
        }
        SectionHeader {
            text: Tr.tr("Notifications")
        }
        SelectRow {
            active: root.dndItems[root.draft && "dnd" in root.draft.settings ? (root.draft.settings.dnd ? 1 : 2) : 0]
            first: true
            label: Tr.tr("Do not disturb")
            last: true
            menuItems: root.dndItems
            subtext: Tr.tr("Choose whether notifications can appear")

            onSelected: item => root.setting("dnd", root.dndItems.indexOf(item) === 0 ? null : root.dndItems.indexOf(item) === 1)
        }
        ScenesAdvanced {
            Layout.fillWidth: true
            dialogParent: root.flickable
            draft: root.draft

            onMetadataChanged: (key, value) => root.meta(key, value)
            onSettingChanged: (key, value) => root.setting(key, value)
        }
        ScenePreview {
            Layout.fillWidth: true
            dialogParent: root.flickable
            scene: root.draft
        }
        StyledText {
            Layout.fillWidth: true
            color: Colours.palette.m3error
            font: Tokens.font.label.small
            text: SceneValidation.error(root.draft)
            visible: !!text && !!root.draft?.name.trim()
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.spacing.large
            spacing: Tokens.spacing.small

            IconTextButton {
                disabled: !!SceneValidation.error(root.draft)
                horizontalPadding: Tokens.padding.largeIncreased
                icon: "check"
                isRound: true
                text: Tr.tr("Save")
                verticalPadding: Tokens.padding.medium

                onClicked: {
                    root.flickable.forceActiveFocus();
                    Qt.callLater(() => {
                        if (Scenes.put(root.draft))
                            root.nState.closeSubPage();
                    });
                }
            }
            TextButton {
                text: Tr.tr("Cancel")
                type: TextButton.Text

                onClicked: root.nState.closeSubPage()
            }
        }
        SectionHeader {
            text: Tr.tr("Manage scene")
            visible: !!root.draft?.id
        }
        RowLayout {
            visible: !!root.draft?.id

            TextButton {
                text: Tr.tr("Duplicate")
                type: TextButton.Text

                onClicked: {
                    if (Scenes.duplicate(root.draft.id))
                        root.nState.closeSubPage();
                }
            }
            TextButton {
                text: Tr.tr("Export…")
                type: TextButton.Text

                onClicked: {
                    root.exportPath = Quickshell.env("HOME") + "/" + root.draft.id + ".scene.json";
                    exportDialog.open = true;
                }
            }
        }
        DialogRowButton {
            id: exportDialog

            acceptLabel: Tr.tr("Export")
            header: Tr.tr("Export scene")
            icon: "file_upload"
            label: Tr.tr("Export")
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

            onAccepted: Scenes.exportFile(root.draft.id, root.exportPath)
        }
        DialogRowButton {
            acceptLabel: Tr.tr("Delete")
            header: Tr.tr("Delete %1?").arg(root.draft?.name || "")
            icon: "delete"
            label: Tr.tr("Delete scene")
            openHeight: Tokens.padding.extraExtraLarge * 5
            rootParent: root.flickable
            visible: !!root.draft?.id

            content: Component {
                StyledText {
                    text: Tr.tr("This removes the saved scene. Your current settings will stay as they are.")
                    wrapMode: Text.Wrap
                }
            }

            onAccepted: {
                Scenes.remove(root.draft.id);
                root.nState.closeSubPage();
            }
        }
    }
}
