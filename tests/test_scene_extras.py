import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / "assets"))
import scenes
import scene_extras as extras


class ExtensionsTest(unittest.TestCase):
    def scene(self, **extra):
        return dict(id="test", name="Test", icon="code", settings={}, **extra)

    def test_extended_schema_round_trip_and_old_library(self):
        data = scenes.defaults()
        data["scenes"].append(self.scene(favourite=True, shortcut="SUPER + SHIFT + F8", duration=90, triggers=[{"type": "app", "value": "steam"}]))
        data["scenes"][-1]["settings"] = {"apps": ["steam.desktop"], "powerProfile": "balanced", "brightness": {"DP-2": .5}, "displays": [{"name": "DP-2", "mode": "2560x1440@144", "x": 0, "y": 0, "scale": 1}]}
        data.update(undoState={"settings": {"dnd": False}, "lastId": ""}, expiresAt=12345, automationEnabled=True, automationPaused=True)
        self.assertEqual(scenes.validate(json.loads(json.dumps(data))), data)
        self.assertEqual(scenes.validate(scenes.defaults()), scenes.defaults())

    def test_invalid_extension_values(self):
        for change in [{"duration": -1}, {"duration": True}, {"shortcut": "SUPER + $(bad)"}, {"favourite": 1}, {"triggers": [{"type": "shell", "value": "bad"}]}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                scenes.validate({"version": 1, "scenes": [self.scene(**change)]})
        for settings in [{"apps": "steam"}, {"powerProfile": "turbo"}, {"brightness": {"DP-2": float("nan")}}, {"displays": [{"name": "AI-private", "mode": "1920x1080@60", "x": 0, "y": 0, "scale": 1}]}]:
            s = self.scene(); s["settings"] = settings
            with self.subTest(settings=settings), self.assertRaises(ValueError):
                scenes.validate({"version": 1, "scenes": [s]})

    def test_import_collision_and_local_rules_disabled(self):
        exported = {"version": 1, "scenes": [self.scene(shortcut="SUPER + F8", triggers=[{"type": "app", "value": "steam"}], favourite=True)]}
        incoming = extras.import_scenes(exported, [self.scene()], scenes.validate)
        self.assertEqual(incoming[0]["id"], "test-2")
        self.assertNotIn("shortcut", incoming[0]); self.assertNotIn("triggers", incoming[0])
        self.assertTrue(incoming[0]["favourite"])
        self.assertIn("shortcut", exported["scenes"][0])

    def test_display_partial_failure_and_lua_argument_safety(self):
        d = {"name": "DP-2", "mode": "2560x1440@144", "x": 0, "y": 0, "scale": 1}
        commands = []
        def runner(cmd):
            commands.append(cmd)
            return json.dumps([{"name": "DP-2", "availableModes": ["2560x1440@143.97Hz"]}]) if cmd[-1] == "monitors" else "ok\n"
        missing = dict(d, name="missing")
        self.assertEqual(extras.apply_displays([missing, d], runner), ["Display could not be applied: missing"])
        self.assertEqual(len([c for c in commands if c[1] == "eval"]), 1)
        self.assertIn('output = "DP-2"', commands[-1][-1])

    def test_compositor_semantic_error_is_failure(self):
        d = {"name": "DP-2", "mode": "1920x1080@60", "x": 0, "y": 0, "scale": 1}
        def runner(cmd):
            return json.dumps([{"name": "DP-2", "availableModes": ["1920x1080@60.00Hz"]}]) if cmd[-1] == "monitors" else "Invalid scale"
        self.assertEqual(extras.apply_displays([d], runner), ["Display could not be applied: DP-2"])

    def test_environment_excludes_private_virtual_monitor(self):
        def runner(cmd):
            if cmd[0] == "hyprctl":
                return json.dumps([dict(name=n, width=1920, height=1080, refreshRate=60, x=0, y=0, scale=1) for n in ["DP-2", "AI-private"]])
            return "balanced" if cmd[-1] == "get" else "* balanced:\n  power-saver:\n  performance:\n"
        e = extras.environment(runner)
        self.assertEqual([d["name"] for d in e["displays"]], ["DP-2"])
        self.assertEqual(e["powerProfiles"], ["balanced", "power-saver", "performance"])

    def test_shortcuts_conflict_does_not_unbind_user(self):
        commands = []
        def runner(cmd):
            commands.append(cmd)
            return json.dumps([{"modmask": 64, "key": "F8", "dispatcher": "exec", "arg": "steam"}])
        self.assertEqual(extras.sync_shortcuts([self.scene(shortcut="SUPER + F8")], runner), ["Shortcut already in use: SUPER + F8"])
        self.assertEqual(len(commands), 1)

    def test_own_shortcut_removed_and_new_binding_created(self):
        commands = []
        def runner(cmd):
            commands.append(cmd)
            if cmd[-1] == "binds":
                return json.dumps([{"modmask": 64, "key": "F8", "dispatcher": "exec", "arg": "qs ipc -c caelestia call scenes activate removed"}])
            return "ok"
        self.assertEqual(extras.sync_shortcuts([self.scene(shortcut="SUPER + F9")], runner), [])
        self.assertIn('hl.unbind("SUPER + F8")', commands[1][-1])
        self.assertIn('hl.bind("SUPER + F9"', commands[2][-1])

    def test_shared_shortcut_never_unbound(self):
        commands = []
        def runner(cmd):
            commands.append(cmd)
            return json.dumps([{"modmask": 64, "key": "F8", "dispatcher": "exec", "arg": arg} for arg in ["qs ipc -c caelestia call scenes activate removed", "steam"]])
        self.assertEqual(extras.sync_shortcuts([], runner), ["Shared shortcut could not be removed: F8"])
        self.assertEqual(len(commands), 1)

    def test_preview_missing_resources_is_read_only(self):
        def runner(cmd):
            raise FileNotFoundError()
        self.assertEqual(scenes.preflight({"wallpaper": "/absent", "rgbProfile": "absent"}, runner), {"wallpaper": False, "rgbProfile": False})


if __name__ == "__main__":
    unittest.main()
