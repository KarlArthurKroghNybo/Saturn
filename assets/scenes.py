#!/usr/bin/env python3
"""Scene persistence and adapters for the shell's existing wallpaper/RGB tools."""
import json
import os
from pathlib import Path
import subprocess
import sys
import sqlite3
import tempfile
import scene_extras as extras


def defaults():
    return {"version": 1, "scenes": [
        {"id": "coding", "name": "Coding", "icon": "code", "settings": {"dnd": True}},
        {"id": "gaming", "name": "Gaming", "icon": "sports_esports", "settings": {}},
        {"id": "chill", "name": "Chill", "icon": "self_improvement", "settings": {"dnd": True}},
    ], "lastId": "", "failures": []}


def validate(data):
    if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(data.get("scenes"), list):
        raise ValueError("Ugyldigt sceneformat")
    ids = set()
    for scene in data["scenes"]:
        if not isinstance(scene, dict) or not isinstance(scene.get("id"), str) or not scene["id"] or scene["id"] in ids:
            raise ValueError("Ugyldigt eller gentaget scene-id")
        ids.add(scene["id"])
        if not isinstance(scene.get("name"), str) or not scene["name"].strip() or not isinstance(scene.get("icon"), str):
            raise ValueError("Scenen mangler navn eller ikon")
        settings = scene.get("settings")
        if not isinstance(settings, dict) or set(settings) - {"wallpaper", "rgbProfile", "sink", "volume", "dnd", "brightness", "displays", "powerProfile", "apps"}:
            raise ValueError("Ugyldige sceneindstillinger")
        extras.validate_scene(scene)
        for key, value in settings.items():
            if key in {"brightness", "displays", "apps"}:
                continue
            if key == "dnd":
                valid = isinstance(value, bool)
            elif key == "volume":
                valid = type(value) in (int, float) and 0 <= value <= 2
            else:
                valid = isinstance(value, str) and bool(value.strip())
            if not valid:
                raise ValueError("Ugyldig værdi: " + key)
    if data.get("lastId", "") and data["lastId"] not in ids:
        raise ValueError("Ukendt aktiv scene")
    if not isinstance(data.get("failures", []), list):
        raise ValueError("Ugyldig status")
    for key in ("automationEnabled", "automationPaused"):
        if key in data and not isinstance(data[key], bool):
            raise ValueError("Invalid automation state")
    if "expiresAt" in data and (type(data["expiresAt"]) not in (int, float) or not 0 <= data["expiresAt"] < 1e15):
        raise ValueError("Invalid expiration")
    undo = data.get("undoState")
    if undo is not None:
        if not isinstance(undo, dict) or not isinstance(undo.get("settings"), dict):
            raise ValueError("Invalid restore snapshot")
        validate({"version": 1, "scenes": [{"id": "restore", "name": "Restore", "icon": "undo", "settings": undo["settings"]}]})
    return data


def atomic_save(path, data):
    validate(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".scenes-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def run(command):
    return subprocess.run(command, capture_output=True, text=True, timeout=12 if "openrgb" in Path(command[0]).name else 45, check=True).stdout


BUS = ["busctl", "--user", "--json=short"]
DAEMON = ["org.waywallen.waywallen.Daemon", "/org/waywallen/waywallen/Daemon", "org.waywallen.waywallen.Daemon1"]


def wallpaper_status(runner=run):
    try:
        current = json.loads(runner(BUS + ["get-property"] + DAEMON + ["CurrentWallpaperId"]))["data"]
        result = {"available": True, "current": "waywallen:" + current, "choices": []}
        data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        database = data / "waywallen/waywallen-v2.db"
        try:
            with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as connection:
                result["choices"] = [{"id": "waywallen:" + str(i), "label": name or str(i)} for i, name in
                    connection.execute("SELECT id, display_name FROM item WHERE hidden=0 ORDER BY display_name COLLATE NOCASE")]
        except sqlite3.Error:
            pass
        return result
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return {"available": False, "current": ""}


def waywallen_id(value):
    if value.startswith("waywallen:"):
        return value.split(":", 1)[1]
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    database = data / "waywallen/waywallen-v2.db"
    with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as connection:
        rows = connection.execute("SELECT item.id, item.path, item.preview_path, library.path FROM item JOIN library ON item.library_id=library.id")
        wanted = Path(value).expanduser().resolve()
        for item_id, resource, preview, library in rows:
            if any((Path(library) / p).resolve() == wanted for p in [resource, preview] if p):
                return str(item_id)
    raise ValueError("Wallpaper findes ikke i Waywallens bibliotek")


def apply(settings, smart=True, runner=run, helper=None):
    failures = []
    if "wallpaper" in settings:
        try:
            value = settings["wallpaper"]
            status = wallpaper_status(runner)
            if status["available"]:
                item_id = waywallen_id(value)
                runner(BUS + ["call"] + DAEMON + ["ApplyById", "s", item_id])
                if wallpaper_status(runner)["current"] != "waywallen:" + item_id:
                    raise ValueError("Wallpaper blev ikke bekræftet")
            else:
                if value.startswith("waywallen:"):
                    raise ValueError("Waywallen er ikke tilgængelig")
                path = Path(value).expanduser()
                if not path.is_file():
                    raise ValueError("mangler")
                runner(["caelestia", "wallpaper", "-f", str(path)] + ([] if smart else ["--no-smart"]))
        except (OSError, ValueError, sqlite3.Error, subprocess.SubprocessError):
            failures.append("Wallpaper kunne ikke anvendes")
    if "rgbProfile" in settings:
        try:
            helper = helper or str(Path.home() / ".local/bin/caelestia-openrgb")
            status = json.loads(runner([helper, "status"]))
            if not status.get("available") or settings["rgbProfile"] not in status.get("profiles", []):
                raise ValueError("profil eller plugin mangler")
            # The existing helper selects the profile and mode independently.
            runner([helper, "set-profile", settings["rgbProfile"]])
            result = json.loads(runner([helper, "set-mode", "profile"]))
            if not result.get("available") or result.get("result", {}).get("profileLoaded") != settings["rgbProfile"]:
                raise ValueError("profil kunne ikke indlæses")
        except (OSError, ValueError, subprocess.SubprocessError, AttributeError):
            failures.append("OpenRGB-profil kunne ikke anvendes")
    return failures


def preflight(settings, runner=run):
    result = {}
    if "wallpaper" in settings:
        try:
            value = settings["wallpaper"]
            status = wallpaper_status(runner)
            if status["available"]:
                item_id = waywallen_id(value)
                result["wallpaper"] = any(w["id"] == "waywallen:" + item_id for w in status.get("choices", []))
            else:
                result["wallpaper"] = not value.startswith("waywallen:") and Path(value).expanduser().is_file()
        except Exception:
            result["wallpaper"] = False
    if "rgbProfile" in settings:
        try:
            state = json.loads(runner([str(Path.home() / ".local/bin/caelestia-openrgb"), "status"]))
            result["rgbProfile"] = bool(state.get("available") and settings["rgbProfile"] in state.get("profiles", []))
        except Exception:
            result["rgbProfile"] = False
    if "displays" in settings:
        monitors = extras.environment(runner)["monitors"]
        for display in settings["displays"]:
            monitor = next((m for m in monitors if m["name"] == display["name"]), None)
            result["display:" + display["name"]] = bool(monitor and extras.supported_mode(display, monitor))
    return result


def main():
    operation, path = sys.argv[1:3]
    path = Path(path)
    payload = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
    if operation == "load":
        if path.exists():
            result = validate(json.loads(path.read_text()))
        else:
            result = defaults()
            atomic_save(path, result)
    elif operation == "wallpaper-status":
        result = wallpaper_status()
    elif operation == "save":
        atomic_save(path, payload)
        result = {"ok": True}
    elif operation == "preflight":
        result = preflight(payload["settings"])
    elif operation == "environment":
        result = extras.environment(run)
    elif operation == "shortcuts":
        result = {"failures": extras.sync_shortcuts(payload["scenes"], run, payload.get("lua", True))}
    elif operation == "import":
        if Path(payload["file"]).stat().st_size > 1024 * 1024:
            raise ValueError("Scene file is too large")
        result = {"scenes": extras.import_scenes(json.loads(Path(payload["file"]).read_text()), payload["existing"], validate)}
    elif operation == "export":
        if Path(payload["file"]).expanduser().exists():
            raise ValueError("Export file already exists; choose a new path")
        atomic_save(Path(payload["file"]).expanduser(), {"version": 1, "scenes": payload["scenes"]})
        result = {"ok": True}
    elif operation == "apply":
        settings = payload["settings"]
        result = {"failures": apply(settings, payload.get("smart", True))}
        if payload.get("restoreRGB"):
            try:
                rgb = payload["restoreRGB"]
                helper = str(Path.home() / ".local/bin/caelestia-openrgb")
                if rgb.get("mode") not in {"accent", "custom", "profile", "off"}:
                    raise ValueError("Invalid RGB restore mode")
                if rgb.get("mode") == "custom":
                    run([helper, "set-color", rgb["customColor"]])
                if rgb.get("mode") == "profile":
                    run([helper, "set-profile", rgb["profile"]])
                restored = json.loads(run([helper, "set-mode", rgb["mode"]]))
                if not restored.get("available") or restored.get("result", {}).get("error"):
                    raise ValueError("RGB restore failed")
            except Exception:
                result["failures"].append("Lighting could not be restored")
        if "displays" in settings:
            try:
                result["failures"] += extras.apply_displays(settings["displays"], run, payload.get("lua", True))
            except Exception:
                result["failures"].append("Display settings unavailable")
    else:
        raise ValueError("Ukendt handling")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        sys.exit(1)
