"""Validated scene extensions; compositor operations never interpolate shell commands."""
import copy
import json
import math
import re
import shlex
from pathlib import Path

MODS = {"SHIFT": 1, "CTRL": 4, "ALT": 8, "SUPER": 64}


def shortcut(value):
    parts = [p.strip() for p in value.upper().split("+")]
    if len(parts) < 2 or any(p not in MODS for p in parts[:-1]) or not re.fullmatch(r"[A-Z0-9_]+", parts[-1]):
        raise ValueError("Use a shortcut such as SUPER + SHIFT + F8")
    if len(set(parts[:-1])) != len(parts[:-1]):
        raise ValueError("Repeated shortcut modifier")
    return sum(MODS[p] for p in parts[:-1]), parts[-1], " + ".join([m for m in MODS if m in parts[:-1]] + [parts[-1]])


def validate_scene(scene):
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", scene["id"]):
        raise ValueError("Invalid scene id")
    if "favourite" in scene and not isinstance(scene["favourite"], bool):
        raise ValueError("Invalid favourite")
    if scene.get("shortcut"):
        shortcut(scene["shortcut"])
    duration = scene.get("duration", 0)
    if type(duration) is not int or not 0 <= duration <= 10080:
        raise ValueError("Duration must be 0–10080 minutes")
    triggers = scene.get("triggers", [])
    if not isinstance(triggers, list) or len(triggers) > 20:
        raise ValueError("Invalid triggers")
    for t in triggers:
        if not isinstance(t, dict) or set(t) != {"type", "value"} or t["type"] not in {"monitor", "audio", "app"} or not isinstance(t["value"], str) or not t["value"].strip():
            raise ValueError("Invalid automatic activation rule")
    s = scene["settings"]
    if "apps" in s and (not isinstance(s["apps"], list) or len(s["apps"]) > 30 or any(not isinstance(a, str) or not a.strip() for a in s["apps"])):
        raise ValueError("Invalid app list")
    if "brightness" in s:
        if not isinstance(s["brightness"], dict) or any(not isinstance(k, str) or not k or type(v) not in (int, float) or not 0 <= v <= 1 for k, v in s["brightness"].items()):
            raise ValueError("Invalid brightness")
    if "powerProfile" in s and s["powerProfile"] not in {"power-saver", "balanced", "performance"}:
        raise ValueError("Invalid power profile")
    if "displays" in s:
        if not isinstance(s["displays"], list):
            raise ValueError("Invalid display layout")
        names = set()
        for d in s["displays"]:
            if not isinstance(d, dict) or set(d) - {"name", "mode", "x", "y", "scale", "transform"} or not all(k in d for k in ("name", "mode", "x", "y", "scale")):
                raise ValueError("Invalid display")
            if not isinstance(d["name"], str) or not re.fullmatch(r"[A-Za-z0-9_.:-]+", d["name"]) or d["name"].startswith("AI-") or d["name"] in names:
                raise ValueError("Invalid display name")
            names.add(d["name"])
            if not isinstance(d["mode"], str) or not re.fullmatch(r"\d+x\d+@[\d.]+", d["mode"]) or type(d["x"]) is not int or type(d["y"]) is not int or type(d["scale"]) not in (int, float) or not math.isfinite(d["scale"]) or not 0.5 <= d["scale"] <= 4 or type(d.get("transform", 0)) is not int or not 0 <= d.get("transform", 0) <= 7:
                raise ValueError("Invalid display mode, position or scale")


def lua_string(value):
    # Restricted UTF-8 strings emitted as quoted Lua literals (JSON escape set is compatible here).
    return json.dumps(value, ensure_ascii=False)


def check_response(result):
    if result.strip().lower() != "ok":
        raise ValueError(result.strip() or "Compositor did not acknowledge the change")


def display_snapshot(monitors):
    return [{"name": m["name"], "mode": f'{m["width"]}x{m["height"]}@{m["refreshRate"]:.2f}', "x": m["x"], "y": m["y"], "scale": m["scale"], "transform": m.get("transform", 0)} for m in monitors if not m["name"].startswith("AI-") and not m.get("disabled")]


def environment(runner):
    result = {"displays": [], "monitors": [], "powerProfile": "", "powerProfiles": []}
    try:
        monitors = json.loads(runner(["hyprctl", "-j", "monitors"]))
        result["displays"] = display_snapshot(monitors)
        result["monitors"] = [m for m in monitors if not m["name"].startswith("AI-")]
    except Exception:
        pass
    try:
        result["powerProfile"] = runner(["powerprofilesctl", "get"]).strip()
        result["powerProfiles"] = re.findall(r"^\s*\*?\s*(power-saver|balanced|performance):", runner(["powerprofilesctl", "list"]), re.M)
    except Exception:
        pass
    return result


def supported_mode(display, monitor):
    w, h, hz = re.split(r"[x@]", display["mode"])
    return any((match := re.fullmatch(r"(\d+)x(\d+)@([\d.]+)Hz", mode)) and (match[1], match[2]) == (w, h) and abs(float(match[3]) - float(hz)) < 0.15 for mode in monitor.get("availableModes", []))


def apply_displays(displays, runner, lua=True):
    failures = []
    monitors = {m["name"]: m for m in json.loads(runner(["hyprctl", "-j", "monitors"]))}
    for d in displays:
        try:
            m = monitors.get(d["name"])
            if not m or not supported_mode(d, m):
                raise ValueError("Display or mode unavailable")
            if lua:
                fields = {"output": d["name"], "mode": d["mode"], "position": f'{d["x"]}x{d["y"]}', "scale": d["scale"], "transform": d.get("transform", 0)}
                body = ", ".join(k + " = " + (lua_string(v) if isinstance(v, str) else str(v)) for k, v in fields.items())
                check_response(runner(["hyprctl", "eval", "hl.monitor({" + body + "})"]))
            else:
                check_response(runner(["hyprctl", "keyword", "monitor", f'{d["name"]},{d["mode"]},{d["x"]}x{d["y"]},{d["scale"]},transform,{d.get("transform", 0)}']))
        except Exception:
            failures.append("Display could not be applied: " + d["name"])
    return failures


def import_scenes(payload, existing, validate):
    if not isinstance(payload, dict) or payload.get("version") != 1 or not isinstance(payload.get("scenes"), list):
        raise ValueError("Invalid scene export")
    incoming = copy.deepcopy(payload["scenes"])
    validate({"version": 1, "scenes": incoming})
    used = {s["id"] for s in existing}
    for scene in incoming:
        base = scene["id"]
        i = 2
        while scene["id"] in used:
            scene["id"] = f"{base}-{i}"
            i += 1
        used.add(scene["id"])
        # Imported bindings/automation stay inactive until explicitly configured locally.
        scene.pop("shortcut", None)
        scene.pop("triggers", None)
    return incoming


def sync_shortcuts(scenes, runner, lua=True):
    bindings = json.loads(runner(["hyprctl", "-j", "binds"]))
    desired = {}
    failures = []
    prefix = "qs ipc -c caelestia call scenes activate "
    marker = "caelestia-scene:"
    def owned_id(binding):
        description = binding.get("description", "")
        if description.startswith(marker) and re.fullmatch(r"[a-zA-Z0-9_-]+", description[len(marker):]):
            return description[len(marker):]
        arg = binding.get("arg", "")
        if binding.get("dispatcher") == "exec" and arg.startswith(prefix) and re.fullmatch(r"[a-zA-Z0-9_-]+", arg[len(prefix):]):
            return arg[len(prefix):]
        return None
    for s in scenes:
        if s.get("shortcut"):
            mask, key, normalized = shortcut(s["shortcut"])
            slot = (mask, key)
            if slot in desired:
                failures.append("Shortcut repeated: " + normalized)
            else:
                desired[slot] = (s, normalized)
    for b in bindings[:]:
        slot = (b.get("modmask"), b.get("key", "").upper())
        ours = owned_id(b)
        matches = [v for v in bindings if v.get("modmask") == slot[0] and v.get("key", "").upper() == slot[1]]
        if ours and (slot not in desired or ours != desired[slot][0]["id"]):
            # Unbind removes every handler at this chord. Never remove another user's binding.
            if len(matches) > 1:
                failures.append("Shared shortcut could not be removed: " + slot[1])
                continue
            mods = " + ".join(k for k, v in MODS.items() if slot[0] & v)
            if lua:
                check_response(runner(["hyprctl", "eval", "hl.unbind(" + lua_string(mods + " + " + b["key"]) + ")"]))
            else:
                check_response(runner(["hyprctl", "keyword", "unbind", mods.replace(" + ", " ") + "," + b["key"]]))
            bindings.remove(b)
    for slot, (s, normalized) in desired.items():
        existing = [b for b in bindings if b.get("modmask") == slot[0] and b.get("key", "").upper() == slot[1]]
        command = prefix + s["id"]
        if any(owned_id(b) != s["id"] for b in existing):
            failures.append("Shortcut already in use: " + normalized)
        elif not existing:
            if lua:
                check_response(runner(["hyprctl", "eval", "hl.bind(" + lua_string(normalized) + ", hl.dsp.exec_cmd(" + lua_string(command) + "), {description = " + lua_string(marker + s["id"]) + "})"]))
            else:
                mods, key = normalized.rsplit(" + ", 1)
                check_response(runner(["hyprctl", "keyword", "bind", mods.replace(" + ", " ") + "," + key + ",exec," + command]))
    return failures
