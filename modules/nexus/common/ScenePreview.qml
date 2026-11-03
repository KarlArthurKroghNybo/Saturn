pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.services

DialogRowButton {
    id: root

    required property Item dialogParent
    required property var scene

    acceptLabel: Tr.tr("Done")
    header: Tr.tr("Changes in %1").arg(scene?.name || Tr.tr("this scene"))
    horizontalContentMargin: -Tokens.padding.small
    icon: "visibility"
    label: Tr.tr("Preview activation")
    rootParent: dialogParent
    separateContent: true

    content: Component {
        VerticalFadeListView {
            bottomMargin: Tokens.padding.medium
            model: Scenes.previewRows.length ? Scenes.previewRows : [
                {
                    label: Tr.tr("Keeps current settings"),
                    before: "",
                    after: "",
                    available: true
                }
            ]
            topMargin: Tokens.padding.medium

            delegate: InfoRow {
                required property int index
                required property var modelData

                first: index === 0
                icon: modelData.available ? "arrow_forward" : "warning"
                iconColour: modelData.available ? Colours.palette.m3primary : Colours.palette.m3error
                label: modelData.label
                last: index === ListView.view.count - 1
                subtext: (modelData.before ? modelData.before + " → " : "") + modelData.after
                value: modelData.available ? "" : Tr.tr("Unavailable")
                width: ListView.view.width
            }
        }
    }

    onOpenChanged: {
        if (open && scene)
            Scenes.preview(scene);
    }
}
