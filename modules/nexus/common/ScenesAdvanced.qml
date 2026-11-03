pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    required property Item dialogParent
    required property var draft
    readonly property list<MenuItem> powerItems: [
        MenuItem {
            icon: "remove"
            text: Tr.tr("Keep current")
        },
        MenuItem {
            icon: "eco"
            text: Tr.tr("Power saver")
        },
        MenuItem {
            icon: "balance"
            text: Tr.tr("Balanced")
        },
        MenuItem {
            icon: "speed"
            text: Tr.tr("Performance")
        }
    ]
    property string ruleType: "monitor"
    property string ruleValue: ""
    readonly property list<MenuItem> triggerItems: [
        MenuItem {
            icon: "monitor"
            text: Tr.tr("Monitor attached")
        },
        MenuItem {
            icon: "headphones"
            text: Tr.tr("Audio device connected")
        },
        MenuItem {
            icon: "apps"
            text: Tr.tr("App opened")
        }
    ]

    signal metadataChanged(key: string, value: var)
    signal settingChanged(key: string, value: var)

    function brightness(name: string, value: var): void {
        const values = JSON.parse(JSON.stringify(draft.settings.brightness || {}));
        if (value === null)
            delete values[name];
        else
            values[name] = value;
        settingChanged("brightness", Object.keys(values).length ? values : null);
    }
    function display(index: int, key: string, value: var): void {
        const items = JSON.parse(JSON.stringify(draft.settings.displays));
        items[index][key] = value;
        settingChanged("displays", items);
    }

    spacing: Tokens.spacing.extraSmall / 2

    SectionHeader {
        text: Tr.tr("Displays & power")
    }
    SelectRow {
        active: root.powerItems[["", "power-saver", "balanced", "performance"].indexOf(root.draft?.settings.powerProfile || "")]
        first: true
        label: Tr.tr("Power profile")
        last: true
        menuItems: root.powerItems
        subtext: Tr.tr("Unavailable profiles are skipped")

        onSelected: item => root.settingChanged("powerProfile", [null, "power-saver", "balanced", "performance"][root.powerItems.indexOf(item)])
    }
    Repeater {
        model: Brightness.monitors.filter(m => !m.modelData.name.startsWith("AI-"))

        ColumnLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            ToggleRow {
                Layout.topMargin: Tokens.spacing.small
                checked: parent.modelData.modelData.name in (root.draft?.settings.brightness || {})
                enabled: Number.isFinite(parent.modelData.brightness)
                first: true
                last: !checked
                subtext: Number.isFinite(parent.modelData.brightness) ? Tr.tr("Set this display's brightness") : Tr.tr("Brightness control unavailable")
                text: Tr.tr("Brightness: %1").arg(parent.modelData.modelData.name)

                onToggled: root.brightness(parent.modelData.modelData.name, checked ? parent.modelData.brightness : null)
            }
            SliderRow {
                icon: "brightness_6"
                label: Tr.tr("Brightness")
                last: true
                value: root.draft?.settings.brightness?.[parent.modelData.modelData.name] || 0
                valueLabel: `${Math.round(value * 100)}%`
                visible: parent.modelData.modelData.name in (root.draft?.settings.brightness || {})

                onMoved: value => root.brightness(parent.modelData.modelData.name, value)
            }
        }
    }
    ToggleRow {
        Layout.topMargin: Tokens.spacing.small
        checked: "displays" in (root.draft?.settings || {})
        first: true
        last: !checked
        subtext: Tr.tr("Save resolution, refresh rate, position and scale")
        text: Tr.tr("Display layout")

        onToggled: root.settingChanged("displays", checked ? JSON.parse(JSON.stringify(Scenes.environment.displays)) : null)
    }
    Repeater {
        model: root.draft?.settings.displays || []

        ColumnLayout {
            id: displayGroup

            required property int index
            required property var modelData

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            InfoRow {
                first: true
                icon: "monitor"
                label: displayGroup.modelData.name
                last: true
                subtext: Scenes.environment.monitors.some(m => m.name === displayGroup.modelData.name) ? "" : Tr.tr("Saved display unavailable")
            }
            TextFieldRow {
                first: true
                label: Tr.tr("Resolution & refresh rate")
                subtext: Tr.tr("Width×height@Hz")
                value: displayGroup.modelData.mode

                validator: RegularExpressionValidator {
                    regularExpression: /\d+x\d+@[\d.]+/
                }

                onValueEdited: value => root.display(displayGroup.index, "mode", value)
            }
            TextFieldRow {
                label: Tr.tr("Horizontal position")
                smallField: true
                value: String(displayGroup.modelData.x)

                validator: IntValidator {
                }

                onEditingFinished: value => {
                    if (value.trim() && Number.isInteger(Number(value)))
                        root.display(displayGroup.index, "x", Number(value));
                }
            }
            TextFieldRow {
                label: Tr.tr("Vertical position")
                smallField: true
                value: String(displayGroup.modelData.y)

                validator: IntValidator {
                }

                onEditingFinished: value => {
                    if (value.trim() && Number.isInteger(Number(value)))
                        root.display(displayGroup.index, "y", Number(value));
                }
            }
            TextFieldRow {
                label: Tr.tr("Scale")
                last: true
                smallField: true
                value: String(displayGroup.modelData.scale)

                validator: DoubleValidator {
                    bottom: 0.5
                    decimals: 2
                    locale: "C"
                    top: 4
                }

                onEditingFinished: value => {
                    if (Number(value) >= 0.5 && Number(value) <= 4)
                        root.display(displayGroup.index, "scale", Number(value));
                }
            }
            DialogSelectButton {
                acceptLabel: Tr.tr("Select")
                header: Tr.tr("Choose a display mode")
                icon: "monitor"
                label: Tr.tr("Supported modes")
                model: (Scenes.environment.monitors.find(m => m.name === displayGroup.modelData.name)?.availableModes || []).map(m => ({
                            id: m.replace("Hz", ""),
                            label: m
                        }))
                rootParent: root.dialogParent

                onAccepted: root.display(displayGroup.index, "mode", selectedItem)
            }
        }
    }
    TextButton {
        text: Tr.tr("Use current layout")
        type: TextButton.Text
        visible: "displays" in (root.draft?.settings || {})

        onClicked: root.settingChanged("displays", JSON.parse(JSON.stringify(Scenes.environment.displays)))
    }
    SectionHeader {
        text: Tr.tr("Applications")
    }
    InfoRow {
        first: true
        icon: "apps"
        label: Tr.tr("Open apps on activation")
        last: true
        subtext: Tr.tr("Running apps with a known window class are reused. Undo leaves apps open.")
    }
    Repeater {
        model: root.draft?.settings.apps || []

        RowLayout {
            required property string modelData

            Layout.fillWidth: true

            InfoRow {
                Layout.fillWidth: true
                first: true
                icon: "apps"
                label: DesktopEntries.applications.values.find(a => a.id === parent.modelData)?.name || parent.modelData
                last: true
            }
            IconButton {
                icon: "close"
                type: IconButton.Text

                onClicked: root.settingChanged("apps", root.draft.settings.apps.filter(a => a !== parent.modelData))
            }
        }
    }
    DialogSelectButton {
        acceptLabel: Tr.tr("Add")
        header: Tr.tr("Choose an app")
        icon: "add"
        label: Tr.tr("Add app")
        model: [...DesktopEntries.applications.values].filter(a => !(root.draft?.settings.apps || []).includes(a.id)).sort((a, b) => a.name.localeCompare(b.name)).map(a => ({
                    id: a.id,
                    label: a.name
                }))
        rootParent: root.dialogParent

        onAccepted: root.settingChanged("apps", [...(root.draft.settings.apps || []), selectedItem])
    }
    SectionHeader {
        text: Tr.tr("Activation")
    }
    ToggleRow {
        checked: root.draft?.favourite || false
        first: true
        subtext: Tr.tr("Include this scene when cycling favourites")
        text: Tr.tr("Favourite")

        onToggled: root.metadataChanged("favourite", checked)
    }
    TextFieldRow {
        label: Tr.tr("Keyboard shortcut")
        subtext: Tr.tr("For example SUPER + SHIFT + F8; leave empty to disable")
        value: root.draft?.shortcut || ""

        onValueEdited: value => root.metadataChanged("shortcut", value.trim().toUpperCase())
    }
    TextFieldRow {
        label: Tr.tr("Restore after")
        last: true
        smallField: true
        subtext: Tr.tr("Minutes; 0 keeps the scene active")
        value: String(root.draft?.duration || 0)

        validator: IntValidator {
            bottom: 0
            top: 10080
        }

        onEditingFinished: value => {
            if (value.trim() && Number.isInteger(Number(value)) && Number(value) >= 0 && Number(value) <= 10080)
                root.metadataChanged("duration", Number(value));
        }
    }
    SectionHeader {
        text: Tr.tr("Automatic activation")
    }
    InfoRow {
        first: true
        icon: "auto_awesome"
        label: Tr.tr("Activate when a device connects or an app opens")
        last: true
        subtext: Tr.tr("Enable automation on the Scenes page. Manual choices pause it until resumed.")
    }
    Repeater {
        model: root.draft?.triggers || []

        RowLayout {
            required property int index
            required property var modelData

            Layout.fillWidth: true

            InfoRow {
                Layout.fillWidth: true
                first: true
                icon: root.triggerItems[["monitor", "audio", "app"].indexOf(parent.modelData.type)].icon
                label: parent.modelData.value
                last: true
                subtext: root.triggerItems[["monitor", "audio", "app"].indexOf(parent.modelData.type)].text
            }
            IconButton {
                icon: "close"
                type: IconButton.Text

                onClicked: root.metadataChanged("triggers", root.draft.triggers.filter((t, i) => i !== parent.index))
            }
        }
    }
    SelectRow {
        active: root.triggerItems[["monitor", "audio", "app"].indexOf(root.ruleType)]
        first: true
        label: Tr.tr("Rule type")
        menuItems: root.triggerItems

        onSelected: item => {
            root.ruleType = ["monitor", "audio", "app"][root.triggerItems.indexOf(item)];
            root.ruleValue = "";
        }
    }
    TextFieldRow {
        label: root.ruleType === "app" ? Tr.tr("Window class") : Tr.tr("Device name")
        last: true
        subtext: root.ruleType === "app" ? Tr.tr("Exact app window class, such as steam") : Tr.tr("Exact monitor or audio output name")
        value: root.ruleValue

        onValueEdited: value => root.ruleValue = value.trim()
    }
    RowLayout {
        DialogSelectButton {
            Layout.fillWidth: true
            acceptLabel: Tr.tr("Select")
            header: Tr.tr("Choose a trigger")
            icon: "devices"
            label: Tr.tr("Choose connected")
            model: root.ruleType === "monitor" ? Scenes.environment.monitors.map(m => ({
                        id: m.name,
                        label: m.description || m.name
                    })) : root.ruleType === "audio" ? Audio.sinks.map(n => ({
                        id: n.name,
                        label: n.description || n.name
                    })) : [...new Set(Hypr.toplevels.values.map(t => t.lastIpcObject?.class).filter(c => c))].map(c => ({
                        id: c,
                        label: c
                    }))
            rootParent: root.dialogParent

            onAccepted: root.ruleValue = selectedItem
        }
        TextButton {
            disabled: !root.ruleValue || root.ruleValue.startsWith("AI-") || (root.draft?.triggers || []).some(t => t.type === root.ruleType && t.value === root.ruleValue)
            text: Tr.tr("Add rule")
            type: TextButton.Text

            onClicked: {
                root.metadataChanged("triggers", [...(root.draft.triggers || []),
                    {
                        type: root.ruleType,
                        value: root.ruleValue
                    }
                ]);
                root.ruleValue = "";
            }
        }
    }
}
