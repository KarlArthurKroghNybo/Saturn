pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Plugins
import qs.services

Scope {
    Variants {
        model: Plugins.entryPoints(EntryPointType.Custom)

        EntryPointLoader {
            required property pluginEntryPoint modelData

            entryPoint: modelData
        }
    }

    Variants {
        model: Screens.screens

        Scope {
            id: screenScope

            required property ShellScreen modelData

            Variants {
                model: Plugins.entryPoints(EntryPointType.ShellPanel)

                PluginPanel {
                    required property pluginEntryPoint modelData

                    screen: screenScope.modelData
                    entryPoint: modelData
                }
            }
        }
    }
}
