import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("scope", "tools/test-scope.py")
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class ScopeTests(unittest.TestCase):
    def test_no_ui_for_docs_or_backend(self):
        for path in ["AGENTS.md", "docs/roadmap.md", "VolantAgentHost/ACPConnection.swift",
                     "Core/Sources/VolantCore/Calculator/Calculator.swift",
                     ".github/workflows/pr.yml", "Scripts/test.sh"]:
            self.assertFalse(scope.classify([path])["ui"], path)

    def test_ui_dependencies(self):
        for path in ["Volant/Search/AppIndex.swift", "Volant/Search/IconCache.swift", "Volant/Files/FileSearch.swift", "Volant/Notes/NotesStore.swift", "Volant/Clipboard/ClipboardStore.swift", "Volant/Clipboard/KeychainKey.swift", "Volant/Panel/LauncherModel.swift", "Core/Sources/VolantCore/Calculator/TimeCalculator.swift", "Volant/Usage/UsageStore.swift", "Volant/Settings/SettingsWindowController.swift",
                     "Core/Sources/VolantCore/Settings/Preferences.swift", "Core/Sources/VolantCore/AI/AIConfiguration.swift", "Volant/Settings/AISettingsView.swift", "Volant/Settings/ACPAccountsSection.swift",
                     "Volant/Resources/Assets.xcassets/AccentColor.colorset/Contents.json",
                     "Volant/Extensions/ExtensionApproval.swift", "Core/Sources/VolantCore/Extensions/ExtensionProtocol.swift", "VolantExtensionHost/ExtensionHost.swift", "extensions/hello-rust/hello.wasm", "Volant/Notes/LiveMarkdownEditor.swift", "Core/Sources/VolantCore/AI/AIHTTPTypes.swift", "Core/Sources/VolantCore/AI/AIHTTPTransport.swift", "Volant/Settings/AIModelDiscovery.swift", "Core/Sources/VolantCore/Launcher/LauncherRouting.swift", "Core/Sources/VolantCore/Agents/ACPTypes.swift", "Core/Sources/VolantCore/Herdr/HerdrMachines.swift", "Core/Sources/VolantCore/Herdr/HerdrAttention.swift", "Shared/HerdrQuestion.swift", "Shared/HerdrClaudeQuestion.swift", "Shared/HerdrResponseController.swift", "Core/Sources/VolantCore/Agents/AgentProtocol.swift", "Volant/Agents/ACPConversations.swift",
                     "Volant/Appearance/ThemeStore.swift", "Volant/Dictionary/DictionaryModel.swift", "Volant/Dictionary/DictionaryView.swift", "Volant/Translation/TranslationModel.swift", "Volant/Translation/TranslationView.swift", "tools/launcher/check.swift", "tools/check-launcher-actions.sh", "tools/launcher/actions.swift", "tools/launcher/dictation-hud.swift", "tools/check-dictation-hud.sh", "Volant/Dictation/DictationIndicator.swift", "Volant/Dictation/DictationIndicatorPanel.swift", "Volant/HotKeys/DictationEscapeKey.swift", "Volant/Settings/DictationSettingsView.swift", "Volant/Settings/SettingsSection.swift", "Volant/Dictation/DictationTypingAccess.swift", "tools/run-bounded-check.py", "tools/app-module.sh",
                     "Volant/SystemControl/VolumeControl.swift", "Volant/SystemControl/Connectivity.swift", "Volant/SystemControl/Caffeinate.swift",
                     "Volant/Snippets/Snippets.swift", "Volant/Quicklinks/Quicklinks.swift", "Volant/Settings/AppBindingStore.swift"]:
            self.assertEqual(scope.classify([path]), {"native": True, "ui": True}, path)

    def test_current_swiftui_surfaces_are_classified(self):
        for path in Path("Volant").rglob("*.swift"):
            if "import SwiftUI" in path.read_text():
                self.assertTrue(scope.classify([path.as_posix()])["ui"], str(path))

    def test_bundled_release_notes_require_native_checks(self):
        self.assertEqual(scope.classify(["docs/releases/0.3.3.md"]), {"native": True, "ui": False})

    def test_every_helper_requires_native_checks(self):
        for path in ["VolantRatesHost/main.swift", "VolantFetchHost/main.swift", "VolantAgentHost/main.swift", "Integrations/acp/package.json"]:
            self.assertTrue(scope.classify([path])["native"], path)

    def test_tools_the_ui_job_never_runs_do_not_trigger_it(self):
        for path in ["tools/settings/main.swift", "tools/themes/render.swift", "tools/marketing/main.swift", "tools/render-vm.py",
                     "tools/render-marketing.sh", "tools/preview-settings.sh", "tools/test-ui-vm.py", "tools/interaction-speed/main.swift"]:
            self.assertEqual(scope.classify([path]), {"native": True, "ui": False}, path)

    def test_ai_helper_requires_native_checks(self):
        self.assertEqual(scope.classify(["VolantAIHost/AIHTTPHost.swift"]), {"native": True, "ui": False})

    def test_input_helper_and_its_guard_require_native_checks(self):
        for path in ["VolantInputHost/SystemInput.swift", "VolantInputHost/main.swift", "tools/check-input-confinement.py",
                     "Volant/Dictation/InputHostConnection.swift", "Core/Sources/VolantCore/Dictation/InputSessionController.swift"]:
            self.assertEqual(scope.classify([path]), {"native": True, "ui": False}, path)

    def test_mixed_and_deleted_paths(self):
        self.assertTrue(scope.classify(["docs/a.md", "Volant/Settings/OldView.swift"])["ui"])
        self.assertEqual(scope.classify([]), {"native": False, "ui": False})

    def test_command_adapter_build_and_probes_require_native_checks(self):
        for path in ["tools/build-raycast-example.sh", "tools/raycast-wasm/build.mjs",
                     "tools/raycast-wasm/bound-memory.mjs", "tools/extensions/wasi-fixtures/streams.wasm"]:
            self.assertEqual(scope.classify([path]), {"native": True, "ui": False}, path)


unittest.main()
