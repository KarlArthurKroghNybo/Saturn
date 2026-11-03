import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
sys.path.insert(0, str(Path(__file__).parents[1] / "assets"))

spec = importlib.util.spec_from_file_location("scenes", Path(__file__).parents[1] / "assets/scenes.py")
scenes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scenes)


class ScenesTest(unittest.TestCase):
    def test_atomic_storage_and_empty_library(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nested/scenes.json"
            data = scenes.defaults()
            scenes.atomic_save(path, data)
            self.assertEqual(json.loads(path.read_text()), data)
            data.update(scenes=[], lastId="")
            scenes.atomic_save(path, data)
            self.assertEqual(json.loads(path.read_text())["scenes"], [])
            with self.assertRaises(ValueError):
                scenes.atomic_save(path, {"version": 2, "scenes": []})
            self.assertEqual(json.loads(path.read_text()), data)

    def test_missing_wallpaper_does_not_block_rgb(self):
        calls = []
        def runner(command):
            if command[0] == "busctl":
                raise FileNotFoundError()
            calls.append(command)
            return json.dumps({"available": True, "profiles": ["My profile"], "result": {"profileLoaded": "My profile"}})
        failures = scenes.apply({"wallpaper": "/does-not-exist", "rgbProfile": "My profile"}, runner=runner)
        self.assertEqual(failures, ["Wallpaper kunne ikke anvendes"])
        self.assertEqual([c[1] for c in calls], ["status", "set-profile", "set-mode"])

    def test_missing_rgb_does_not_block_wallpaper(self):
        with tempfile.NamedTemporaryFile() as image:
            calls = []
            def runner(command):
                calls.append(command)
                if command[0] == "busctl":
                    raise FileNotFoundError()
                if command[0] == "caelestia":
                    return ""
                raise FileNotFoundError()
            failures = scenes.apply({"wallpaper": image.name, "rgbProfile": "absent"}, smart=False, runner=runner)
            self.assertEqual(failures, ["OpenRGB-profil kunne ikke anvendes"])
            self.assertIn("--no-smart", next(c for c in calls if c[0] == "caelestia"))

    def test_rgb_zero_exit_is_not_success(self):
        def runner(command):
            return json.dumps({"available": True, "profiles": ["test"], "result": {"error": "profile_failed"}})
        self.assertEqual(scenes.apply({"rgbProfile": "test"}, runner=runner), ["OpenRGB-profil kunne ikke anvendes"])

    def test_unselected_settings_do_nothing(self):
        def runner(command):
            self.fail("No adapters should run")
        self.assertEqual(scenes.apply({}, runner=runner), [])

    def test_waywallen_uses_daemon_and_confirms_selection(self):
        current = "before"
        calls = []
        def runner(command):
            nonlocal current
            calls.append(command)
            if "ApplyById" in command:
                current = command[-1]
                return json.dumps({"type": "s", "data": "renderer"})
            return json.dumps({"type": "s", "data": current})
        self.assertEqual(scenes.apply({"wallpaper": "waywallen:42"}, runner=runner), [])
        self.assertTrue(any("ApplyById" in c for c in calls))
        self.assertFalse(any(c[0] == "caelestia" for c in calls))

    def test_waywallen_missing_daemon_is_partial_failure(self):
        def runner(command):
            raise FileNotFoundError()
        self.assertEqual(scenes.apply({"wallpaper": "waywallen:42"}, runner=runner), ["Wallpaper kunne ikke anvendes"])

    def test_optional_false_zero_and_validation(self):
        data = scenes.defaults()
        data["scenes"][0]["settings"] = {"dnd": False, "volume": 0}
        scenes.validate(data)
        data["scenes"][0]["settings"]["volume"] = float("nan")
        with self.assertRaises(ValueError):
            scenes.validate(data)


if __name__ == "__main__":
    unittest.main()
