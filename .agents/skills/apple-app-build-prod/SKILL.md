---
name: apple-app-build-prod
description: Build and verify signed Release archives for native iOS or macOS apps, including app variants, device or Mac verification, and App Store or TestFlight export preparation.
---

# Apple app Release builds

## Resolve the project

Read the current repository's `README.md` and linked release/store docs first.
Use project-owned configuration (such as `Store/store.config.json`) when present;
do not require that path or schema in other repositories. Resolve the requested
platform, app variant, scheme, bundle ID, App Store ID, signing team, version/build,
supported OS and distribution channel from those sources and build settings.
App identifiers, credentials, SDK IDs and product behavior never come from this
skill or a previous project's report.

Confirm the selected scheme with `xcodebuild -list` and its Release settings with
`-showBuildSettings`. Inspect the source project or generator configuration when
settings disagree with documentation; reconcile the intended identity with the
existing store app before signing/uploading. Do not change bundle IDs to resolve
a signing error. Regenerate generated projects using their documented workflow.
Preserve unrelated working changes and existing variant isolation.

## Archive and export

Check current App Store Connect/TestFlight builds before choosing a build number.
Use **ego-browser** for browser work and confirm the account/team and app. An
uploaded version/build pair cannot be overwritten. Keep each platform/variant's
numbering rules from project documentation; do not assume all targets share them.

Run existing checks appropriate to the changes. Version-only changes need artifact
metadata verification; unchanged tests need not be repeated. Archive the selected
scheme in Release using the project's workspace or project and a destination from
`xcodebuild -showdestinations`:

- **iOS:** archive for generic iOS devices; simulator builds are not upload artifacts.
- **macOS:** archive the selected Mac target. Distinguish native macOS, Mac Catalyst
  and iOS-on-Mac support from the actual project; do not add another platform.

Keep logs, `.xcarchive` and exports outside tracked source. Use the verified team
and project signing policy. If signing fails, inspect the error and available
certificates/profiles before rebuilding. Do not create new keys or switch teams
as an automatic workaround.

Inspect the archive and exported app for bundle ID, version/build, signing team,
entitlements, embedded frameworks, privacy manifests and configuration-specific
service IDs. Validate all nested signed code for Mac targets. Legacy App ID
prefixes may differ from team IDs; verify the intended account and profile rather
than assuming those values must match. Confirm variant exclusions and production
settings against the repository's release checklist.

Export with the installed Xcode's supported options (`xcodebuild -help`) for the
requested channel. Preserve the verified version/build, disabling automatic build
number management where supported. App Store/TestFlight exports use the App Store
Connect distribution method; verify the resulting **iOS IPA** or **Mac store
package**. A direct macOS distribution task uses its own signing/notarization
workflow and is not an App Store upload; consult project docs for that channel.

## Runtime verification

- **iOS:** use `xcrun devicectl list devices` to find the intended device, install
  the Release export and launch its bundle ID. Verify changed flows and real
  hardware/permissions/SDK behavior. Simulator placeholders do not prove hardware
  features work. TestFlight may be used when the device is unavailable locally.
- **macOS:** run the exported app on a supported Mac and verify changed flows,
  permissions, sandbox-dependent file/network access and relevant architectures.
  An unsigned development run does not validate the distributed signing/sandbox.
  Use the distributed TestFlight build for behavior that depends on that channel.

Record exact platform/variant, version/build, device or Mac/OS, artifact hash,
checks performed and remaining checks in the repository's release report location.
Compiler success, installation and complete runtime verification are separate
results. TestFlight upload may precede final distributed-runtime verification;
carry pending checks into the report and complete them before final store review.

For metadata/screenshots use [apple-app-listing](../apple-app-listing/SKILL.md).
For upload, TestFlight or review use [apple-app-submit](../apple-app-submit/SKILL.md).
