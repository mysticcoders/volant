# Running Shortcuts from Volant

Volant can launch a saved shortcut through Apple's documented URL scheme. A shortcut can contain actions provided by other apps through App Intents. Create the workflow in Shortcuts first, then add a quicklink to Volant's `config.json` and choose Reload Config.

For a shortcut named `Capture Text` that accepts text input, add this entry to your existing `quicklinks` array:

```json
{
  "name": "capture",
  "url": "shortcuts://run-shortcut?name=Capture%20Text&input=text&text={query}"
}
```

Type `capture buy coffee` and press Return. Volant opens Shortcuts with `buy coffee` as input. Typed text is percent-encoded as a single value, including ampersands, plus signs, percent signs and Unicode. Shortcut names in the configured URL must also be URL-encoded.

For a workflow without input, use `shortcuts://run-shortcut?name=Example`. For an intentional clipboard workflow, use `shortcuts://run-shortcut?name=Example&input=clipboard`. Clipboard input is opt-in per quicklink; Volant does not attach it automatically.

This runs shortcuts already saved in your collection. It does not enumerate all third-party App Intents, install shortcuts, or return workflow results to Volant. Shortcuts handles action permissions, prompts and execution errors, including a missing or renamed shortcut. Volant reports invalid URLs and failures to hand the URL to an application, but a successful handoff does not establish that the workflow finished successfully.

Volant's sandbox entitlements remain unchanged. Workflows run in Shortcuts and may use the network, run scripts, or modify data through their own actions and permissions. Volant's extension capability restrictions do not apply to Shortcuts.

## Why this route

Apple documents App Intents as a way to expose an app's actions to system experiences. We have not found a public general-purpose API for Volant to enumerate and invoke every other app's intents directly. The supported bridge is a saved shortcut containing those actions.

Apple also provides `shortcuts list` and `shortcuts run` on macOS. That is a potential discovery/result bridge, but its operation from Volant's sandbox has not been verified. The initial integration uses URL handoff and existing quicklink configuration, with no shell process or new entitlement.

Sources checked 2026-09-13:

- [Apple: Run a shortcut using a URL scheme on Mac](https://support.apple.com/guide/shortcuts-mac/run-a-shortcut-from-a-url-apd624386f42/mac)
- [Apple: Run shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)
- [Apple: AppIntent](https://developer.apple.com/documentation/appintents/appintent)

## Remaining validation

Run a fictional text-only shortcut from the signed sandboxed app, then check missing-shortcut behavior and Unicode input. No personal workflows were executed during implementation. Automatic discovery and result callbacks remain future work.
