pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root
    title: "Gem arbejdsområder"
    property var draft: null
    property string error: ""
    property string deleteId: ""
    function edit(profile: var): void {
        draft = JSON.parse(JSON.stringify(profile));
        error = "";
    }
    function meta(key: string, value: var): void {
        const copy = JSON.parse(JSON.stringify(draft));
        copy[key] = value;
        draft = copy;
    }
    function saveDraft(): void {
        const copy = JSON.parse(JSON.stringify(draft));
        try {
            for (const app of copy.apps) {
                if (app.argumentsText !== undefined) {
                    app.arguments = JSON.parse(app.argumentsText || "[]");
                    delete app.argumentsText;
                }
                if (!Array.isArray(app.arguments) || !app.arguments.every(a => typeof a === "string"))
                    throw new Error();
            }
            error = "";
            WorkspaceProfiles.put(copy);
        } catch (e) { error = "Argumenter skal være en JSON-liste med tekst. Ret feltet før du gemmer."; }
    }
    function app(index: int, key: string, value: var): void {
        const copy = JSON.parse(JSON.stringify(draft));
        copy.apps[index][key] = value;
        error = "";
        draft = copy;
    }
    function removeApp(index: int): void {
        const copy = JSON.parse(JSON.stringify(draft));
        copy.apps.splice(index, 1);
        error = "";
        draft = copy;
    }
    property Connections profileConnections: Connections {
        target: WorkspaceProfiles
        function onCaptured(profile: var): void { root.edit(profile); }
        function onSaved(): void { root.draft = null; }
    }
    ColumnLayout {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.cappedWidth
        spacing: Tokens.spacing.small
        RowLayout {
            TextButton {
                text: "Ny profil"
                disabled: WorkspaceProfiles.busy || !WorkspaceProfiles.loaded
                onClicked: root.edit({id: "", name: "", icon: "workspaces", focusWorkspace: "", apps: []})
            }
            TextButton {
                text: "Gem aktuelle vinduer…"
                disabled: WorkspaceProfiles.busy || !WorkspaceProfiles.loaded
                onClicked: WorkspaceProfiles.capture()
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: "Åbn og placér dine apps uden at lukke andre vinduer. Dev, Gaming og Study er tomme eksempler, du selv kan udfylde. AI Spaces holdes adskilt."
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.Wrap
        }
        StyledText {
            Layout.fillWidth: true
            text: WorkspaceProfiles.message
            visible: !!text
            wrapMode: Text.Wrap
        }
        StyledText {
            Layout.fillWidth: true
            text: WorkspaceProfiles.warnings.join("\n")
            visible: !!text
            color: Colours.palette.m3error
            wrapMode: Text.Wrap
        }
        Repeater {
            model: WorkspaceProfiles.profiles
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                MaterialIcon { text: modelData.icon; color: Colours.palette.m3primary }
                StyledText { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight }
                TextButton {
                    text: "Aktivér"
                    disabled: WorkspaceProfiles.busy || modelData.apps.length === 0
                    onClicked: WorkspaceProfiles.activate(modelData.id)
                }
                IconButton {
                    icon: "edit"
                    type: IconButton.Text
                    disabled: WorkspaceProfiles.busy
                    onClicked: root.edit(modelData)
                }
                IconButton {
                    icon: root.deleteId === modelData.id ? "check" : "delete"
                    type: IconButton.Text
                    disabled: WorkspaceProfiles.busy
                    onClicked: {
                        if (root.deleteId === modelData.id) {
                            WorkspaceProfiles.remove(modelData.id);
                            root.deleteId = "";
                        } else {
                            root.deleteId = modelData.id;
                        }
                    }
                }
            }
        }
        StyledText {
            text: "Tryk på fluebenet for at bekræfte sletning."
            visible: !!root.deleteId
            color: Colours.palette.m3onSurfaceVariant
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.draft !== null
            enabled: !WorkspaceProfiles.busy
            spacing: Tokens.spacing.extraSmall / 2
            SectionHeader { first: true; text: "Redigér profil" }
            StyledText {
                Layout.fillWidth: true
                text: "Gennemgå alle startkommandoer før du gemmer. Vinduesprocesser kan indeholde midlertidige argumenter. Program og argumenter køres direkte; mappe, fil eller URL tilføjes som ét sidste argument."
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.Wrap
            }
            TextFieldRow {
                first: true
                label: "Navn"
                value: root.draft?.name ?? ""
                onValueEdited: value => root.meta("name", value)
            }
            TextFieldRow {
                label: "Ikon (Material Symbols)"
                value: root.draft?.icon ?? "workspaces"
                onValueEdited: value => root.meta("icon", value)
            }
            TextFieldRow {
                last: true
                label: "Workspace med fokus efter aktivering"
                placeholderText: "Tomt: behold fokus"
                value: root.draft?.focusWorkspace ?? ""
                onValueEdited: value => root.meta("focusWorkspace", value)
            }
            Repeater {
                // Stable indices keep the focused editor alive while its draft changes.
                model: root.draft?.apps.length ?? 0
                ColumnLayout {
                    id: entry
                    required property int index
                    readonly property var appData: root.draft?.apps[index] ?? ({})
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall / 2
                    SectionHeader { text: `App ${entry.index + 1}` }
                    TextFieldRow {
                        first: true
                        label: "Program"
                        placeholderText: "Vælg et installeret program"
                        value: entry.appData.program ?? ""
                        onValueEdited: value => root.app(entry.index, "program", value)
                    }
                    TextFieldRow {
                        label: "Argumenter (JSON-liste)"
                        placeholderText: '["--flag", "tekst med mellemrum"]'
                        value: entry.appData.argumentsText ?? JSON.stringify(entry.appData.arguments ?? [])
                        onValueEdited: value => root.app(entry.index, "argumentsText", value)
                    }
                    TextFieldRow {
                        label: "Mål-workspace"
                        value: entry.appData.workspace ?? "1"
                        onValueEdited: value => root.app(entry.index, "workspace", value)
                    }
                    TextFieldRow {
                        label: "Skærm (valgfri)"
                        placeholderText: Hypr.monitorNames().filter(n => !n.startsWith("AI-")).join(", ")
                        value: entry.appData.monitor ?? ""
                        onValueEdited: value => root.app(entry.index, "monitor", value)
                    }
                    TextFieldRow {
                        label: "Mappe, fil eller URL (valgfri)"
                        value: entry.appData.resource ?? ""
                        onValueEdited: value => root.app(entry.index, "resource", value)
                    }
                    TextFieldRow {
                        label: "Vinduesklasse til genbrug (eksakt)"
                        value: entry.appData.matchClass ?? ""
                        onValueEdited: value => root.app(entry.index, "matchClass", value)
                    }
                    TextFieldRow {
                        last: true
                        label: "Vinduestitel (valgfri, eksakt)"
                        value: entry.appData.matchTitle ?? ""
                        onValueEdited: value => root.app(entry.index, "matchTitle", value)
                    }
                    ToggleRow {
                        first: true
                        last: true
                        text: "Åbn altid nyt"
                        subtext: "Appen skal understøtte nye vinduer; tilføj evt. dens new-window-argument."
                        checked: entry.appData.alwaysNew ?? false
                        onToggled: root.app(entry.index, "alwaysNew", checked)
                    }
                    TextButton { text: "Fjern app"; onClicked: root.removeApp(entry.index) }
                }
            }
            TextButton {
                text: "Tilføj app"
                onClicked: root.meta("apps", [...root.draft.apps, {program: "", arguments: [], workspace: "1", monitor: "", resource: "", matchClass: "", matchTitle: "", alwaysNew: false}])
            }
            StyledText {
                Layout.fillWidth: true
                text: root.error
                visible: !!text
                color: Colours.palette.m3error
                wrapMode: Text.Wrap
            }
            RowLayout {
                TextButton {
                    text: "Gem profil"
                    disabled: !!root.error
                    onClicked: root.saveDraft()
                }
                TextButton { text: "Annullér"; onClicked: { root.draft = null; root.error = ""; } }
            }
        }
    }
}
