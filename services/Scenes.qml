pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.modules.launcher.services as Launcher
import Caelestia
import Caelestia.I18n
import Caelestia.Config
import Caelestia.Services
import qs.services
import qs.utils
import "../utils/SceneValidation.js" as SceneValidation

Singleton {
    id: root

    readonly property var activeScene: scenes.find(s => s.id === lastId) ?? null
    property var appliedValues: ({})
    property bool automationEnabled: false
    readonly property string automationLabel: !automationEnabled ? Tr.tr("Automation off") : automationPaused ? Tr.tr("Automation paused") : Tr.tr("Automation on")
    property bool automationPaused: false
    property bool busy: false
    readonly property bool canUndo: undoState !== null && !busy
    property real clockNow: Date.now()
    readonly property string currentWallpaper: waywallenCurrent || Wallpapers.actualCurrent
    readonly property bool customized: activeScene !== null && (failures.length ? !sameValues(values(activeScene.settings), appliedValues) : !matches(activeScene.settings))
    property var environment: ({
            displays: [],
            monitors: [],
            powerProfile: "",
            powerProfiles: []
        })
    property bool environmentLoaded: false
    property real expiresAt: 0
    property var failures: []
    readonly property string helper: Quickshell.shellPath("assets/scenes.py")
    property string lastId: ""
    property bool loaded: false
    readonly property var nativePowerProfile: PowerProfiles.profile
    property var pendingPreview: null
    property var pendingScene: null
    property bool preservedMute: false
    property real preservedVolume: 0
    readonly property bool previewChecking: preflightProc.running
    property int previewGeneration: 0
    property var previewRows: []
    property bool restoring: false
    property var rgbState: ({})
    property var scenes: []
    property var shortcutFailures: []
    readonly property string statePath: Quickshell.env("CAELESTIA_SCENES_STATE") || `${Paths.config}/scenes.json`
    readonly property string status: busy ? "Anvender…" : failures.length ? (customized ? "Delvist anvendt · Tilpasset" : "Delvist anvendt") : !activeScene ? "Ingen aktiv scene" : customized ? "Tilpasset" : "Anvendt"
    readonly property string statusLabel: busy ? Tr.tr("Applying…") : failures.length ? (customized ? Tr.tr("Partially applied · Customised") : Tr.tr("Partially applied")) : !activeScene ? Tr.tr("No active scene") : customized ? Tr.tr("Customised") : Tr.tr("Active")
    readonly property string temporaryLabel: expiresAt ? Tr.tr("Restores in %1 min").arg(Math.max(1, Math.ceil((expiresAt - clockNow) / 60000))) : ""
    property string transferMessage: ""
    property var triggerEdges: ({})
    property bool triggersPrimed: false
    property var undoState: null
    property var wallpaperChoices: []
    property string waywallenCurrent: ""

    function activate(id: string): bool {
        const scene = find(id);
        if (!scene) {
            Toaster.toast(Tr.tr("Scenes"), Tr.tr("Scene not found"), "warning");
            return false;
        }
        return start(scene, false);
    }
    function capture(name: string): void {
        const settings = {
            dnd: Notifs.dnd
        };
        if (currentWallpaper)
            settings.wallpaper = currentWallpaper;
        if (Audio.sink?.ready && Audio.sink?.audio) {
            settings.sink = Audio.sink.name;
            settings.volume = Math.min(1, Audio.volume);
        }
        if (rgbState.mode === "profile" && rgbState.profile)
            settings.rgbProfile = rgbState.profile;
        settings.displays = JSON.parse(JSON.stringify(environment.displays));
        settings.brightness = {};
        for (const m of Brightness.monitors) {
            if (!m.modelData.name.startsWith("AI-") && Number.isFinite(m.brightness))
                settings.brightness[m.modelData.name] = m.brightness;
        }
        if (environment.powerProfile)
            settings.powerProfile = currentPower();
        put({
            id: "",
            name: name.trim() || "Aktuel opsætning",
            icon: "bookmark",
            settings: settings
        });
    }
    function checkTriggers(): void {
        const edges = {};
        let candidate = null;
        for (const scene of scenes) {
            for (const trigger of scene.triggers || []) {
                const key = `${scene.id}:${trigger.type}:${trigger.value}`;
                const present = trigger.type === "monitor" ? Quickshell.screens.some(m => m.name === trigger.value && !m.name.startsWith("AI-")) : trigger.type === "audio" ? Audio.sinks.some(n => n.name === trigger.value && n.ready) : Hypr.toplevels.values.some(t => t.lastIpcObject?.class?.toLowerCase() === trigger.value.toLowerCase());
                edges[key] = present;
                if (triggersPrimed && present && !triggerEdges[key] && !candidate)
                    candidate = scene;
            }
        }
        triggerEdges = edges;
        triggersPrimed = true;
        if (candidate && loaded && automationEnabled && !automationPaused && !busy && !expiresAt && !(lastId === candidate.id && !customized))
            start(candidate, true);
    }
    function currentPower(): string {
        return nativePowerProfile === PowerProfile.PowerSaver ? "power-saver" : nativePowerProfile === PowerProfile.Performance ? "performance" : "balanced";
    }
    function cycle(): bool {
        const choices = scenes.filter(s => s.favourite);
        if (!choices.length) {
            Toaster.toast(Tr.tr("Scenes"), Tr.tr("Choose favourites in the scene editor"), "star");
            return false;
        }
        return activate(choices[(choices.findIndex(s => s.id === lastId) + 1) % choices.length].id);
    }
    function describe(settings: var): string {
        const items = [];
        if ("wallpaper" in settings)
            items.push(Tr.tr("Wallpaper"));
        if ("rgbProfile" in settings)
            items.push(Tr.tr("Lighting"));
        if ("sink" in settings)
            items.push(Tr.tr("Audio output"));
        if ("volume" in settings)
            items.push(`${Math.round(settings.volume * 100)}%`);
        if ("dnd" in settings)
            items.push(settings.dnd ? Tr.tr("Do not disturb") : Tr.tr("Notifications on"));
        if ("powerProfile" in settings)
            items.push(Tr.tr("Power"));
        if ("brightness" in settings)
            items.push(Tr.tr("Brightness"));
        if ("displays" in settings)
            items.push(Tr.tr("Displays"));
        if (settings.apps?.length)
            items.push(Tr.tr("%1 apps").arg(settings.apps.length));
        return items.length ? items.join(" · ") : Tr.tr("Keeps current settings");
    }
    function document(): var {
        return {
            version: 1,
            scenes: scenes,
            lastId: lastId,
            failures: failures,
            appliedValues: appliedValues,
            undoState: undoState,
            expiresAt: expiresAt,
            automationEnabled: automationEnabled,
            automationPaused: automationPaused
        };
    }
    function duplicate(id: string): bool {
        const scene = find(id);
        if (!scene)
            return false;
        const copy = JSON.parse(JSON.stringify(scene));
        copy.id = "";
        copy.name = Tr.tr("%1 copy").arg(scene.name);
        delete copy.shortcut;
        delete copy.triggers;
        return put(copy);
    }
    function exportFile(id: string, file: string): bool {
        const scene = find(id);
        if (transferProc.running || (!scene && id !== "all"))
            return false;
        transferProc.operation = "export";
        transferProc.command = ["python3", helper, "export", statePath, JSON.stringify({
                file: file,
                scenes: id === "all" ? scenes : [scene]
            })];
        transferProc.running = true;
        return true;
    }
    function find(id: string): var {
        return scenes.find(s => s.id === id) ?? scenes.find(s => s.name.toLowerCase() === id.toLowerCase());
    }
    function finish(): void {
        if (!busy || applyProc.running || audioTimer.running || wallpaperProc.running || environmentProc.running)
            return;
        const applied = pendingScene;
        lastId = pendingScene.id;
        if (restoring && undoState) {
            lastId = scenes.some(s => s.id === undoState.lastId) ? undoState.lastId : "";
        }
        if ("wallpaper" in pendingScene.settings && !(pendingScene.settings.wallpaper.startsWith("waywallen:") ? waywallenCurrent === pendingScene.settings.wallpaper : Wallpapers.actualCurrent === pendingScene.settings.wallpaper) && !failures.some(f => f.startsWith("Wallpaper")))
            failures = [...failures, "Wallpaper blev ikke bekræftet"];
        if ("powerProfile" in pendingScene.settings && currentPower() !== pendingScene.settings.powerProfile && !failures.includes("Power profile unavailable"))
            failures = [...failures, "Power profile could not be applied"];
        for (const d of pendingScene.settings.displays || []) {
            const m = environment.displays.find(v => v.name === d.name);
            if ((!m || m.mode.split("@")[0] !== d.mode.split("@")[0] || Math.abs(parseFloat(m.mode.split("@")[1]) - parseFloat(d.mode.split("@")[1])) >= 0.15 || m.x !== d.x || m.y !== d.y || m.scale !== d.scale || m.transform !== (d.transform || 0)) && !failures.some(f => f.includes(d.name)))
                failures = [...failures, "Display change was not confirmed: " + d.name];
        }
        if (!restoring && undoState?.rgb && JSON.stringify(undoState.rgb) === JSON.stringify(rgbState)) {
            const snapshot = JSON.parse(JSON.stringify(undoState));
            snapshot.rgb = null;
            delete snapshot.settings.rgbProfile;
            undoState = snapshot;
        }
        appliedValues = values(pendingScene.settings);
        if (restoring) {
            if (!failures.length && undoState) {
                failures = undoState.failures || [];
                appliedValues = undoState.appliedValues || {};
                undoState = null;
            }
            expiresAt = 0;
        }
        restoring = false;
        busy = false;
        pendingScene = null;
        save();
        Toaster.toast(Tr.tr("Scenes"), failures.length ? `${applied.name}: ${failures.join(" · ")}` : Tr.tr("%1 applied").arg(applied.name), failures.length ? "warning" : applied.icon);
    }
    function importFile(file: string): bool {
        if (!loaded || busy || transferProc.running)
            return false;
        transferProc.operation = "import";
        transferProc.command = ["python3", helper, "import", statePath, JSON.stringify({
                file: file,
                existing: scenes
            })];
        transferProc.running = true;
        return true;
    }
    function matches(s: var): bool {
        const extrasMatch = (!("powerProfile" in s) || currentPower() === s.powerProfile) && Object.keys(s.brightness || {}).every(name => Math.abs((Brightness.getMonitor(name)?.brightness ?? -1) - s.brightness[name]) < 0.02) && (s.displays || []).every(d => {
            const m = environment.displays.find(m => m.name === d.name);
            return m && Math.abs(parseFloat(m.mode.split("@")[1]) - parseFloat(d.mode.split("@")[1])) < 0.15 && m.mode.split("@")[0] === d.mode.split("@")[0] && m.x === d.x && m.y === d.y && m.scale === d.scale && m.transform === (d.transform || 0);
        });
        return extrasMatch && (!("wallpaper" in s) || (s.wallpaper.startsWith("waywallen:") ? s.wallpaper === waywallenCurrent : s.wallpaper === Wallpapers.actualCurrent)) && (!("rgbProfile" in s) || (rgbState.mode === "profile" && rgbState.profile === s.rgbProfile)) && (!("sink" in s) || s.sink === Audio.sink?.name) && (!("volume" in s) || (!!Audio.sink?.ready && Math.abs(Audio.volume - s.volume) < 0.015)) && (!("dnd" in s) || s.dnd === Notifs.dnd);
    }
    function preview(scene: var): var {
        const rows = [];
        const s = scene.settings;
        function add(label, before, after, available, key) {
            rows.push({
                label: label,
                before: String(before),
                after: String(after),
                available: !!available,
                key: key || ""
            });
        }
        if ("wallpaper" in s)
            add(Tr.tr("Wallpaper"), currentWallpaper, s.wallpaper, s.wallpaper.startsWith("waywallen:") ? wallpaperChoices.some(w => w.id === s.wallpaper) : true, "wallpaper");
        if ("rgbProfile" in s)
            add(Tr.tr("Lighting"), rgbState.mode === "profile" ? rgbState.profile : rgbState.mode, s.rgbProfile, true, "rgbProfile");
        if ("sink" in s)
            add(Tr.tr("Audio output"), Audio.sink?.description || Audio.sink?.name || "", Audio.sinks.find(n => n.name === s.sink)?.description || s.sink, Audio.sinks.some(n => n.name === s.sink && n.ready));
        if ("volume" in s)
            add(Tr.tr("Volume"), `${Math.round(Audio.volume * 100)}%`, `${Math.round(s.volume * 100)}%`, Audio.sinks.some(n => n.ready && (!("sink" in s) || n.name === s.sink)));
        if ("dnd" in s)
            add(Tr.tr("Do not disturb"), Notifs.dnd ? Tr.tr("On") : Tr.tr("Off"), s.dnd ? Tr.tr("On") : Tr.tr("Off"), true);
        if ("powerProfile" in s)
            add(Tr.tr("Power profile"), currentPower(), s.powerProfile, environment.powerProfiles.includes(s.powerProfile));
        for (const name of Object.keys(s.brightness || {})) {
            const m = Brightness.getMonitor(name);
            add(Tr.tr("Brightness: %1").arg(name), Number.isFinite(m?.brightness) ? `${Math.round(m.brightness * 100)}%` : "—", `${Math.round(s.brightness[name] * 100)}%`, !!m && Number.isFinite(m.brightness));
        }
        for (const d of s.displays || []) {
            const old = environment.displays.find(m => m.name === d.name);
            add(d.name, old ? `${old.mode}, ${old.x}×${old.y}, ${old.scale}×` : "—", `${d.mode}, ${d.x}×${d.y}, ${d.scale}×`, !!old, "display:" + d.name);
        }
        for (const id of s.apps || [])
            add(Tr.tr("Open app"), "", DesktopEntries.applications.values.find(a => a.id === id)?.name || id, DesktopEntries.applications.values.some(a => a.id === id));
        previewRows = rows;
        previewGeneration++;
        if (!preflightProc.running) {
            preflightProc.generation = previewGeneration;
            preflightProc.command = ["python3", helper, "preflight", statePath, JSON.stringify({
                    settings: s
                })];
            preflightProc.running = true;
        } else
            pendingPreview = scene;
        return rows;
    }
    function put(scene: var): bool {
        const error = SceneValidation.error(scene);
        if (error) {
            Toaster.toast(Tr.tr("Scenes"), error, "warning");
            return false;
        }
        if (!loaded || busy || !scene.name.trim())
            return false;
        const copy = JSON.parse(JSON.stringify(scene));
        copy.name = copy.name.trim();
        copy.icon = copy.icon.trim() || "bookmark";
        if (!copy.id)
            copy.id = `scene-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        const index = scenes.findIndex(s => s.id === copy.id);
        const next = scenes.slice();
        if (index < 0)
            next.push(copy);
        else
            next[index] = copy;
        scenes = next;
        syncShortcuts();
        triggersPrimed = false;
        save();
        return true;
    }
    function remove(id: string): void {
        if (!loaded || busy)
            return;
        scenes = scenes.filter(s => s.id !== id);
        syncShortcuts();
        triggersPrimed = false;
        if (lastId === id) {
            lastId = "";
            failures = [];
        }
        save();
    }
    function resumeAutomation(): void {
        automationPaused = false;
        triggersPrimed = false;
        save();
    }
    function sameValues(a: var, b: var): bool {
        return Object.keys(a).every(k => k === "volume" ? Math.abs(a[k] - b[k]) < 0.015 : JSON.stringify(a[k]) === JSON.stringify(b[k]));
    }
    function save(): void {
        if (loaded)
            saveTimer.restart();
    }
    function setAutomation(enabled: bool): void {
        automationEnabled = enabled;
        automationPaused = false;
        triggersPrimed = false;
        save();
    }
    function snapshot(s: var): var {
        const result = {};
        if ("wallpaper" in s && currentWallpaper)
            result.wallpaper = currentWallpaper;
        if ("rgbProfile" in s && rgbState.mode === "profile" && rgbState.profile)
            result.rgbProfile = rgbState.profile;
        if ("sink" in s && Audio.sink?.ready)
            result.sink = Audio.sink.name;
        if (("volume" in s || "sink" in s) && Audio.sink?.ready)
            result.volume = Math.min(2, Audio.volume);
        if ("dnd" in s)
            result.dnd = Notifs.dnd;
        if ("powerProfile" in s && environment.powerProfile)
            result.powerProfile = environment.powerProfile;
        if ("brightness" in s) {
            result.brightness = {};
            for (const name of Object.keys(s.brightness)) {
                const m = Brightness.getMonitor(name);
                if (m && Number.isFinite(m.brightness))
                    result.brightness[name] = m.brightness;
            }
        }
        if ("displays" in s)
            result.displays = environment.displays.filter(d => s.displays.some(v => v.name === d.name));
        return result;
    }
    function start(scene: var, automatic: bool): bool {
        if (!loaded || !environmentLoaded || busy)
            return false;
        if (!automatic)
            automationPaused = true;
        if (!restoring) {
            undoState = {
                settings: snapshot(scene.settings),
                lastId: lastId,
                failures: failures,
                appliedValues: appliedValues,
                rgb: "rgbProfile" in scene.settings ? JSON.parse(JSON.stringify(rgbState)) : null
            };
            expiresAt = scene.duration ? Date.now() + scene.duration * 60000 : 0;
        }
        preservedVolume = Audio.volume;
        preservedMute = Audio.muted;
        busy = true;
        pendingScene = scene;
        failures = [];
        const s = scene.settings;
        save();
        if ("powerProfile" in s) {
            if (environment.powerProfiles.includes(s.powerProfile))
                PowerProfiles.profile = s.powerProfile === "power-saver" ? PowerProfile.PowerSaver : s.powerProfile === "performance" ? PowerProfile.Performance : PowerProfile.Balanced;
            else
                failures = [...failures, "Power profile unavailable"];
        }
        for (const name of Object.keys(s.brightness || {})) {
            const m = Brightness.getMonitor(name);
            if (m && Number.isFinite(m.brightness))
                m.setBrightness(s.brightness[name]);
            else
                failures = [...failures, "Brightness unavailable: " + name];
        }
        for (const id of s.apps || []) {
            const app = DesktopEntries.applications.values.find(a => a.id === id);
            if (!app)
                failures = [...failures, "App unavailable: " + id];
            else if (!app.startupClass || !Hypr.toplevels.values.some(t => t.lastIpcObject?.class?.toLowerCase() === app.startupClass.toLowerCase()))
                Launcher.Apps.launch(app);
        }
        if ("dnd" in s)
            Notifs.dnd = s.dnd;
        if ("sink" in s) {
            const node = Audio.sinks.find(n => n.name === s.sink && n.ready);
            if (node)
                Audio.setAudioSink(node);
            else
                failures = [...failures, "Lydoutput mangler"];
        }
        // Volume is set after PipeWire has acknowledged the default output.
        audioTimer.attempts = 0;
        audioTimer.start();
        applyProc.command = ["python3", helper, "apply", statePath, JSON.stringify({
                settings: s,
                smart: GlobalConfig.services.smartScheme,
                lua: Hypr.usingLua,
                restoreRGB: scene.restoreRGB || null
            })];
        applyProc.running = true;
        return true;
    }
    function syncShortcuts(): void {
        if (Quickshell.env("CAELESTIA_SCENES_NO_SHORTCUTS"))
            return;
        shortcutTimer.restart();
    }
    function undo(): bool {
        if (!loaded || !environmentLoaded || !canUndo)
            return false;
        const previous = JSON.parse(JSON.stringify(undoState));
        restoring = true;
        automationPaused = true;
        expiresAt = 0;
        return start({
            id: previous.lastId || "",
            name: Tr.tr("Previous setup"),
            icon: "undo",
            settings: previous.settings,
            restoreRGB: previous.rgb
        }, false);
    }
    function values(s: var): var {
        const result = {};
        if ("wallpaper" in s)
            result.wallpaper = s.wallpaper.startsWith("waywallen:") ? currentWallpaper : Wallpapers.actualCurrent;
        if ("rgbProfile" in s)
            result.rgbProfile = `${rgbState.mode}:${rgbState.profile}`;
        if ("sink" in s)
            result.sink = Audio.sink?.name || "";
        if ("volume" in s)
            result.volume = Audio.volume;
        if ("dnd" in s)
            result.dnd = Notifs.dnd;
        if ("powerProfile" in s)
            result.powerProfile = currentPower();
        if ("brightness" in s)
            result.brightness = Object.keys(s.brightness).map(name => ({
                        name: name,
                        value: Brightness.getMonitor(name)?.brightness ?? -1
                    }));
        if ("displays" in s)
            result.displays = environment.displays.filter(d => s.displays.some(v => v.name === d.name));
        return result;
    }

    Component.onCompleted: {
        loadProc.running = true;
        wallpaperProc.running = true;
        environmentProc.running = true;
    }
    onCustomizedChanged: {
        if (loaded && !busy && customized && !automationPaused) {
            automationPaused = true;
            save();
        }
    }

    Process {
        id: loadProc

        command: ["python3", root.helper, "load", root.statePath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.error)
                        throw new Error(data.error);
                    root.scenes = data.scenes;
                    root.lastId = data.lastId || "";
                    root.failures = data.failures || [];
                    root.appliedValues = data.appliedValues || {};
                    root.undoState = data.undoState || null;
                    root.expiresAt = data.expiresAt || 0;
                    root.automationEnabled = data.automationEnabled || false;
                    root.automationPaused = data.automationPaused || false;
                    root.loaded = true;
                    root.syncShortcuts();
                } catch (e) {
                    Toaster.toast(Tr.tr("Scenes"), Tr.tr("Could not load scenes: %1").arg(String(e)), "warning");
                }
            }
        }
    }
    Timer {
        id: saveTimer

        interval: 200

        onTriggered: {
            if (saveProc.running) {
                restart();
                return;
            }
            saveProc.command = ["python3", root.helper, "save", root.statePath, JSON.stringify(root.document())];
            saveProc.running = true;
        }
    }
    Process {
        id: saveProc

        onExited: (code, status) => {
            if (code !== 0)
                Toaster.toast(Tr.tr("Scenes"), Tr.tr("Could not save scenes"), "warning");
        }
    }
    Process {
        id: applyProc

        property string response: ""

        stdout: StdioCollector {
            onStreamFinished: applyProc.response = text
        }

        onExited: (code, status) => {
            try {
                const result = JSON.parse(response);
                root.failures = [...root.failures, ...(result.failures || [])];
                if (result.error || code !== 0)
                    throw new Error();
            } catch (e) {
                root.failures = [...root.failures, "Wallpaper/RGB kunne ikke bekræftes"];
            }
            rgbFile.reload();
            if (!environmentProc.running)
                environmentProc.running = true;
            if (!wallpaperProc.running)
                wallpaperProc.running = true;
            else
                Qt.callLater(root.finish);
        }
    }
    Timer {
        id: audioTimer

        property int attempts: 0

        interval: 100
        repeat: true

        onTriggered: {
            const s = root.pendingScene.settings;
            const correctSink = !("sink" in s) || Audio.sink?.name === s.sink;
            if (("volume" in s || "sink" in s) && correctSink && Audio.sink?.ready && Audio.sink?.audio) {
                Audio.setVolume("volume" in s ? s.volume : root.preservedVolume);
                Audio.sink.audio.muted = root.preservedMute;
            }
            if (attempts === 10) {
                for (const name of Object.keys(s.brightness || {}))
                    Brightness.getMonitor(name)?.initBrightness();
            }
            if (++attempts < 20)
                return;
            if (attempts < 100 && Object.keys(s.brightness || {}).some(name => Brightness.getMonitor(name)?.initProc.running))
                return;
            if ("sink" in s && !correctSink && !root.failures.includes("Lydoutput mangler"))
                root.failures = [...root.failures, "Lydoutput blev ikke skiftet"];
            if ("volume" in s && (!correctSink || !Audio.sink?.ready || Math.abs(Audio.volume - s.volume) >= 0.015))
                root.failures = [...root.failures, "Lydstyrke kunne ikke anvendes"];
            for (const name of Object.keys(s.brightness || {})) {
                const m = Brightness.getMonitor(name);
                if ((!m || !Number.isFinite(m.brightness) || m.initProc.running || Math.abs(m.brightness - s.brightness[name]) >= 0.02) && !root.failures.includes("Brightness unavailable: " + name))
                    root.failures = [...root.failures, "Brightness could not be applied: " + name];
            }
            stop();
            root.finish();
        }
    }
    Timer {
        interval: 3000
        repeat: true
        running: true

        onTriggered: {
            if (!wallpaperProc.running && !root.busy)
                wallpaperProc.running = true;
        }
    }
    Process {
        id: wallpaperProc

        command: ["python3", root.helper, "wallpaper-status", root.statePath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text);
                    root.waywallenCurrent = state.current || "";
                    if (JSON.stringify(root.wallpaperChoices) !== JSON.stringify(state.choices || []))
                        root.wallpaperChoices = state.choices || [];
                } catch (e) {
                    root.waywallenCurrent = "";
                }
            }
        }

        onExited: Qt.callLater(root.finish)
    }
    FileView {
        id: rgbFile

        path: `${Paths.config}/rgb.json`
        printErrors: false
        watchChanges: true

        onFileChanged: reload()
        onLoadFailed: root.rgbState = ({})
        onLoaded: {
            try {
                root.rgbState = JSON.parse(text());
            } catch (e) {
                root.rgbState = ({});
            }
        }
    }
    Timer {
        interval: 1500
        repeat: true
        running: root.loaded

        onTriggered: {
            root.clockNow = Date.now();
            if (!environmentProc.running && !root.busy)
                environmentProc.running = true;
            if (!root.busy && root.expiresAt && root.clockNow >= root.expiresAt)
                root.undo();
            root.checkTriggers();
        }
    }
    Process {
        id: environmentProc

        command: ["python3", root.helper, "environment", root.statePath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (!data.error) {
                        root.environmentLoaded = true;
                        if (JSON.stringify(root.environment) !== JSON.stringify(data))
                            root.environment = data;
                    }
                } catch (e) {}
            }
        }

        onExited: Qt.callLater(root.finish)
    }
    Timer {
        id: shortcutTimer

        interval: 250

        onTriggered: {
            if (shortcutProc.running) {
                restart();
                return;
            }
            shortcutProc.command = ["python3", root.helper, "shortcuts", root.statePath, JSON.stringify({
                    scenes: root.scenes,
                    lua: Hypr.usingLua
                })];
            shortcutProc.running = true;
        }
    }
    Connections {
        function onConfigReloaded(): void {
            root.syncShortcuts();
        }

        target: Hypr
    }
    Process {
        id: shortcutProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.shortcutFailures = data.error ? [data.error] : data.failures || [];
                } catch (e) {
                    root.shortcutFailures = [Tr.tr("Shortcuts unavailable")];
                }
            }
        }
    }
    Process {
        id: transferProc

        property string operation

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.error)
                        throw new Error(data.error);
                    if (transferProc.operation === "import") {
                        root.scenes = [...root.scenes, ...data.scenes];
                        root.save();
                        root.syncShortcuts();
                        root.transferMessage = Tr.tr("Imported %1 scenes; configure local shortcuts and rules in the editor").arg(data.scenes.length);
                    } else
                        root.transferMessage = Tr.tr("Scenes exported");
                } catch (e) {
                    root.transferMessage = String(e);
                }
                Toaster.toast(Tr.tr("Scenes"), root.transferMessage, "bookmark");
            }
        }
    }
    Process {
        id: preflightProc

        property int generation: 0

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const available = JSON.parse(text);
                    if (preflightProc.generation === root.previewGeneration)
                        root.previewRows = root.previewRows.map(r => ({
                                    label: r.label,
                                    before: r.before,
                                    after: r.after,
                                    key: r.key,
                                    available: r.key in available ? available[r.key] : r.available
                                }));
                } catch (e) {}
            }
        }

        onExited: {
            if (root.pendingPreview) {
                const scene = root.pendingPreview;
                root.pendingPreview = null;
                Qt.callLater(() => root.preview(scene));
            }
        }
    }
    IpcHandler {
        function activate(id: string): bool {
            return root.activate(id);
        }
        function automation(enabled: bool): void {
            root.setAutomation(enabled);
        }
        function cancelTimer(): void {
            root.expiresAt = 0;
            root.save();
        }
        function capture(name: string): void {
            root.capture(name);
        }
        function cycle(): bool {
            return root.cycle();
        }
        function duplicate(id: string): bool {
            return root.duplicate(id);
        }
        function exportFile(id: string, path: string): bool {
            return root.exportFile(id, path);
        }
        function importFile(path: string): bool {
            return root.importFile(path);
        }
        function list(): string {
            return JSON.stringify(root.scenes);
        }
        function preview(id: string): string {
            const scene = root.find(id);
            return JSON.stringify(scene ? root.preview(scene) : []);
        }
        function previewStatus(): string {
            return JSON.stringify({
                checking: root.previewChecking,
                rows: root.previewRows
            });
        }
        function resume(): void {
            root.resumeAutomation();
        }
        function status(): string {
            return JSON.stringify({
                id: root.lastId,
                status: root.status,
                canUndo: root.canUndo,
                expiresAt: root.expiresAt,
                automationEnabled: root.automationEnabled,
                automationPaused: root.automationPaused,
                shortcutFailures: root.shortcutFailures,
                failures: root.failures
            });
        }
        function temporary(id: string, minutes: int): bool {
            const scene = root.find(id);
            if (!scene || minutes < 1 || minutes > 10080)
                return false;
            const copy = JSON.parse(JSON.stringify(scene));
            copy.duration = minutes;
            return root.start(copy, false);
        }
        function undo(): bool {
            return root.undo();
        }

        target: "scenes"
    }
}
