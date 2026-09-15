import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("scope", "tools/test-scope.py")
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class ScopeTests(unittest.TestCase):
    def test_no_ui_for_docs_or_backend(self):
        for path in ["AGENTS.md", "docs/roadmap.md", "VolantAgentHost/ACPConnection.swift",
                     "Volant/Calculator/Calculator.swift", "Volant/Settings/AppBindingStore.swift",
                     ".github/workflows/pr.yml", "Scripts/test.sh"]:
            self.assertFalse(scope.classify([path])["ui"], path)

    def test_ui_dependencies(self):
        for path in ["Volant/Panel/LauncherModel.swift", "Volant/Settings/SettingsWindowController.swift",
                     "Volant/Resources/Assets.xcassets/AccentColor.colorset/Contents.json",
                     "Volant/Notes/LiveMarkdownEditor.swift", "Shared/LauncherRouting.swift",
                     "Volant/Translation/TranslationModel.swift", "Volant/Translation/TranslationView.swift", "tools/launcher/check.swift", "tools/run-bounded-check.py"]:
            self.assertEqual(scope.classify([path]), {"native": True, "ui": True}, path)

    def test_current_swiftui_surfaces_are_classified(self):
        for path in Path("Volant").rglob("*.swift"):
            if "import SwiftUI" in path.read_text():
                self.assertTrue(scope.classify([path.as_posix()])["ui"], str(path))

    def test_mixed_and_deleted_paths(self):
        self.assertTrue(scope.classify(["docs/a.md", "Volant/Settings/OldView.swift"])["ui"])
        self.assertEqual(scope.classify([]), {"native": False, "ui": False})


unittest.main()
