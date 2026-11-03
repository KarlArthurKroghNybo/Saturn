pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus

ColumnLayout {
    spacing: Tokens.spacing.small
    RowLayout {
        Layout.fillWidth: true
        MaterialIcon { text: "workspaces"; color: Colours.palette.m3primary }
        StyledText { text: "Arbejdsområder"; font: Tokens.font.body.medium }
        StyledText {
            Layout.fillWidth: true
            text: WorkspaceProfiles.message || "Vælg en gemt profil"
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
            elide: Text.ElideRight
        }
        IconButton {
            icon: "tune"
            type: IconButton.Text
            onClicked: WindowFactory.create(null, {initialPage: PageRegistry.workspaceProfilesIndex})
        }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: Math.max(1, Math.min(4, WorkspaceProfiles.profiles.length))
        columnSpacing: Tokens.spacing.small
        rowSpacing: Tokens.spacing.small
        Repeater {
            model: WorkspaceProfiles.profiles
            IconTextButton {
                required property var modelData
                Layout.fillWidth: true
                icon: modelData.icon
                text: modelData.name
                type: IconTextButton.Tonal
                disabled: WorkspaceProfiles.busy || !WorkspaceProfiles.loaded
                onClicked: {
                    if (modelData.apps.length)
                        WorkspaceProfiles.activate(modelData.id);
                    else
                        WindowFactory.create(null, {initialPage: PageRegistry.workspaceProfilesIndex});
                }
            }
        }
    }
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 4
        radius: 2
        color: Colours.tPalette.m3surfaceContainerHighest
        visible: WorkspaceProfiles.busy && WorkspaceProfiles.operation === "activate"
        StyledRect {
            height: parent.height
            width: parent.width * (WorkspaceProfiles.total ? WorkspaceProfiles.completed / WorkspaceProfiles.total : 0)
            radius: 2
            color: Colours.palette.m3primary
            Behavior on width { Anim {} }
        }
    }
}
