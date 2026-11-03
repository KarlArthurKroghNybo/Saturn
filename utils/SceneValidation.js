.pragma library

function error(scene) {
    if (!scene || !scene.name || !scene.name.trim()) return "Enter a scene name";
    if (scene.id && !/^[a-zA-Z0-9_-]+$/.test(scene.id)) return "Invalid scene id";
    if (scene.shortcut) {
        const parts = scene.shortcut.toUpperCase().split("+").map(p => p.trim());
        if (parts.length < 2 || parts.slice(0, -1).some(p => !["SUPER", "SHIFT", "CTRL", "ALT"].includes(p)) || !/^[A-Z0-9_]+$/.test(parts[parts.length - 1]) || new Set(parts.slice(0,-1)).size !== parts.length - 1) return "Use a shortcut such as SUPER + SHIFT + F8";
    }
    if (!Number.isInteger(scene.duration || 0) || (scene.duration || 0) < 0 || (scene.duration || 0) > 10080) return "Duration must be 0–10080 minutes";
    const s = scene.settings;
    if (!s || Object.keys(s).some(k => !["wallpaper", "rgbProfile", "sink", "volume", "dnd", "brightness", "displays", "powerProfile", "apps"].includes(k))) return "Invalid scene settings";
    for (const key of ["wallpaper", "rgbProfile", "sink"]) if (key in s && (typeof s[key] !== "string" || !s[key].trim())) return "Choose a value for " + key;
    if ("volume" in s && (!Number.isFinite(s.volume) || s.volume < 0 || s.volume > 2)) return "Invalid volume";
    if ("dnd" in s && typeof s.dnd !== "boolean") return "Invalid notification setting";
    if ("powerProfile" in s && !["power-saver", "balanced", "performance"].includes(s.powerProfile)) return "Invalid power profile";
    if ("brightness" in s && (!s.brightness || Array.isArray(s.brightness) || typeof s.brightness !== "object" || Object.keys(s.brightness).some(n => !n || !Number.isFinite(s.brightness[n]) || s.brightness[n] < 0 || s.brightness[n] > 1))) return "Invalid brightness";
    if ("apps" in s && (!Array.isArray(s.apps) || s.apps.length > 30 || s.apps.some(a => typeof a !== "string" || !a.trim()))) return "Invalid app list";
    if ("displays" in s) {
        if (!Array.isArray(s.displays)) return "Invalid display layout";
        const names = new Set();
        for (const d of s.displays) {
            if (!d || !/^[A-Za-z0-9_.:-]+$/.test(d.name) || d.name.startsWith("AI-") || names.has(d.name) || !/^\d+x\d+@[\d.]+$/.test(d.mode) || !Number.isInteger(d.x) || !Number.isInteger(d.y) || !Number.isFinite(d.scale) || d.scale < .5 || d.scale > 4 || !Number.isInteger(d.transform || 0) || (d.transform || 0) < 0 || (d.transform || 0) > 7) return "Invalid display mode, position or scale";
            names.add(d.name);
        }
    }
    if (scene.triggers && (!Array.isArray(scene.triggers) || scene.triggers.length > 20 || scene.triggers.some(t => !t || !["monitor", "audio", "app"].includes(t.type) || typeof t.value !== "string" || !t.value.trim()))) return "Invalid automatic activation rule";
    return "";
}
