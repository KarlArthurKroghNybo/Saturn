pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root
    property var profiles: []
    property bool loaded: false
    readonly property bool busy: worker.running
    property string operation: ""
    property string message: ""
    property var warnings: []
    property int completed: 0
    property int total: 0
    signal captured(draft: var)
    signal saved

    function run(action: string, value: string): bool {
        if (busy || (!loaded && action !== "list"))
            return false;
        operation = action;
        warnings = [];
        completed = 0;
        total = 0;
        message = action === "activate" ? "Åbner arbejdsområde…" : "";
        worker.command = ["python3", Quickshell.shellPath("assets/workspace_profiles.py"), action, value || "", ...(Hypr.usingLua ? ["--lua"] : [])];
        worker.running = true;
        return true;
    }
    function activate(id: string): bool { return run("activate", id); }
    function capture(): bool { return run("capture", ""); }
    function put(profile: var): bool { return run("save", JSON.stringify(profile)); }
    function remove(id: string): bool { return run("delete", id); }
    function receive(line: string): void {
        try {
            const data = JSON.parse(line);
            if (data.event === "profiles") {
                profiles = data.profiles;
                loaded = true;
                if (operation === "save")
                    saved();
            } else if (data.event === "capture") {
                captured(data.draft);
            } else if (data.event === "progress") {
                completed = data.completed;
                total = data.total;
                message = data.message;
            } else if (data.event === "done") {
                warnings = data.warnings;
                message = data.message;
                Toaster.toast("Arbejdsområder", warnings.length ? `${message}: ${warnings.slice(0, 2).join(" · ")}` : message, warnings.length ? "warning" : "workspaces");
            } else if (data.event === "error") {
                message = data.message;
                Toaster.toast("Arbejdsområder", message, "warning");
            }
        } catch (e) {
            message = "Kunne ikke læse svaret fra profilservicen";
        }
    }
    Component.onCompleted: run("list", "")
    Process {
        id: worker
        stdout: SplitParser { onRead: line => root.receive(line) }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    root.message = text.trim().slice(0, 240);
                    Toaster.toast("Arbejdsområder", root.message, "warning");
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && !root.message)
                root.message = "Profilservicen stoppede uventet";
        }
    }
    IpcHandler {
        target: "workspaceProfiles"
        function activate(id: string): bool { return root.activate(id); }
        function list(): string { return JSON.stringify(root.profiles); }
        function status(): string { return JSON.stringify({busy: root.busy, completed: root.completed, total: root.total, message: root.message, warnings: root.warnings}); }
    }
}
