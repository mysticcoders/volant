#!/usr/bin/env python3
"""Shared local/CI change classification. Include dirty files locally, never launch UI."""
import argparse
import fnmatch
import json
import subprocess
from pathlib import Path

UI_PATTERNS = (
    "Volant/**/*View.swift", "Volant/**/*Panel.swift", "Volant/**/*WindowController.swift",
    "Volant/Search/AppIndex.swift", "Volant/Search/IconCache.swift", "Volant/Files/*", "Volant/Notes/NotesStore.swift", "Volant/Clipboard/*", "Volant/Extensions/*", "Core/Sources/VolantCore/Extensions/*", "VolantExtensionHost/*", "extensions/*", "Volant/Panel/*", "Core/Sources/VolantCore/Calculator/TimeCalculator.swift", "Volant/Usage/UsageStore.swift", "Volant/Shortcuts/*", "Core/Sources/VolantCore/Shortcuts/*", "Volant/Servers/*", "Core/Sources/VolantCore/Servers/*", "Volant/Emoji/*", "Volant/Translation/*", "Volant/Dictionary/*", "Volant/Dictation/DictationIndicator*.swift", "Volant/Dictation/DictationTyping*.swift", "Volant/HotKeys/DictationEscapeKey.swift", "Volant/Settings/Shortcut*.swift", "Volant/Settings/GlobalShortcutRow.swift",
    "Core/Sources/VolantCore/Settings/*", "Core/Sources/VolantCore/AI/*", "Volant/Settings/AppBindingEditor.swift", "Volant/Settings/MCPSettingsSection.swift", "Volant/MCP/MCPApprovals.swift", "Volant/Settings/LanguageSetting.swift", "Volant/Settings/AppBindingRow.swift", "Volant/HotKeys/KeyCombo.swift", "Volant/Settings/StatusMenu.swift", "Volant/Settings/SettingsStyle.swift", "Volant/Settings/ICloudSettingsSync.swift", "Volant/Settings/CryptoKeySection.swift", "Volant/Settings/ACPAccountsSection.swift",
    "Volant/Notes/LiveMarkdown*.swift", "Volant/Agents/*Model.swift", "Volant/Agents/HerdrFooterStatus.swift", "Volant/Agents/RexFooterStatus.swift", "Volant/Agents/HerdrQueryHeader.swift", "Volant/Agents/ChatContextPicker.swift", "Volant/Agents/ACPConversations.swift",
    "Volant/App/main.swift", "Volant/App/AppDelegate.swift", "Volant/Resources/*", "Volant/Appearance/*",
    "Volant/Settings/AIModelDiscovery.swift", "Volant/Settings/ACPAgentDetection.swift", "Volant/Settings/AICredentials.swift", "Core/Sources/VolantCore/Clipboard/*", "Core/Sources/VolantCore/Emoji/*", "Core/Sources/VolantCore/Launcher/*", "Core/Sources/VolantCore/Agents/*", "Core/Sources/VolantCore/Herdr/*", "Core/Sources/VolantCore/Rex/*", "Shared/HerdrQuestion.swift", "Shared/HerdrClaudeQuestion.swift", "Shared/HerdrResponseController.swift", "Shared/ExtensionImageDecoding.swift", "Volant/SystemControl/SystemSettingsDestination.swift",
    "tools/launcher/*", "Volant/Settings/SettingsSection.swift",
    # Search Menu Items: the launcher fixture drives its model; Settings shows its switch.
    "Volant/MenuItems/*", "Core/Sources/VolantCore/MenuItems/*", "Volant/Settings/MenuItemsSettingsSection.swift",
    # Focus: the launcher rows and form, the focus bar, reminder and menu bar item, and its Settings section.
    "Volant/Focus/*", "Core/Sources/VolantCore/Focus/*", "Volant/Settings/FocusSettingsSection.swift",
    # Breaks: the launcher rows, heads-up and Gentle panel, the full-screen overlays, and its Settings section.
    "Volant/Breaks/*", "Core/Sources/VolantCore/Breaks/*", "Volant/Settings/BreakSettingsSection.swift",
    "tools/check-launcher.sh", "tools/check-launcher-actions.sh", "tools/app-module.sh", "tools/check-dictation-hud.sh", "tools/run-bounded-check.py",
    # Launcher fixtures drive these directly: volume and audio routes, Wi-Fi and Bluetooth, system actions,
    # Caffeinate, snippet and quicklink forms, and app shortcut bindings.
    "Volant/SystemControl/*", "Volant/Camera/*", "Volant/Snippets/*", "Volant/Quicklinks/*", "Volant/Settings/AppBindingStore.swift",
    "VolantTests/LiveMarkdownTests.swift", "VolantTests/NotesStoreTests.swift",
    # The Actions fixture draws SVG row previews with the extension helper's code.
    "Shared/ExtensionSVGRasterizer.swift",
)
NATIVE_PATTERNS = ("Volant/*", "VolantTests/*", "VolantAgentHost/*", "VolantExtensionHost/*", "VolantAIHost/*", "VolantInputHost/*", "VolantFetchHost/*", "VolantRatesHost/*", "VolantWeatherHost/*", "VolantMCPBridge/*", "Integrations/*",
                   "Shared/*", "Core/*", "extensions/*", "docs/releases/*", "Scripts/*", "tools/*", "project.yml", ".swiftlint.yml", ".github/workflows/*")

# Paths known to need no macOS job: documentation, the website (its own job always runs), the iOS app
# (not built in CI yet) and repository housekeeping. Anything in neither list is unrecognized.
OTHER_PATTERNS = ("docs/*", "website/*", "ios/*", ".github/*", "AGENTS.md", "README.md", "CONTRIBUTING.md", "LICENSE",
                  "justfile", ".gitignore", ".gitleaksignore")


def matches(path, patterns):
    """Whether any pattern in the list covers the path."""
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def unclassified(paths):
    """Paths neither list recognizes. They widen the run to native and UI; they never justify a skip."""
    return [p for p in paths if not matches(p, NATIVE_PATTERNS) and not matches(p, OTHER_PATTERNS)]


def classify(paths, full=False):
    """Select the macOS jobs for the changed paths; `full` or an unrecognized path selects both."""
    widen = full or bool(unclassified(paths))
    return {"native": widen or any(matches(p, NATIVE_PATTERNS) for p in paths),
            "ui": widen or any(matches(p, UI_PATTERNS) for p in paths)}


def reason(paths, full=False):
    """One line for the job log saying why the selection is what it is."""
    unknown = unclassified(paths)
    if full:
        return "full run requested"
    if unknown:
        return "unrecognized paths widen the run to native and UI: " + ", ".join(unknown[:10])
    return "selected from the changed paths"


def git(*args):
    return subprocess.check_output(["git", *args]).decode().split("\0")


def changed(base, head, dirty=False):
    paths = git("diff", "--name-only", "--no-renames", "-z", base + "..." + head)
    if dirty:
        paths += git("diff", "--name-only", "--no-renames", "-z", "HEAD")
        paths += git("ls-files", "--others", "--exclude-standard", "-z")
    return sorted(set(filter(None, paths)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--include-working-tree", action="store_true")
    parser.add_argument("--github-output")
    parser.add_argument("--full", action="store_true", help="select native and UI regardless of the changed paths")
    args = parser.parse_args()
    paths = changed(args.base, args.head, args.include_working_tree)
    scope = classify(paths, args.full)
    print(json.dumps({**scope, "reason": reason(paths, args.full), "files": paths}, indent=2))
    if args.github_output:
        with Path(args.github_output).open("a") as output:
            for key, value in scope.items():
                output.write(f"{key}={str(value).lower()}\n")
