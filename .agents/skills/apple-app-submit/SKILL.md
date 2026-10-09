---
name: apple-app-submit
description: Upload verified iOS or macOS builds, distribute them through TestFlight, or submit the selected App Store platform for review while preserving the requested release mode.
---

# Apple app upload, TestFlight and review

Read the current repository's `README.md`, linked store docs, release report and
project-owned configuration. Resolve requested platform/variant, bundle ID, App
Store ID, signing team, version/build and distribution channel from the project,
then confirm them in App Store Connect through **ego-browser**. Never take app
identifiers, team IDs, credentials or review contacts from a previous project.
For multi-platform app records, verify the selected **iOS or macOS platform**.

Upload, processing, TestFlight distribution, beta review, retail review and public
release are separate outcomes. Complete only the requested stage; a TestFlight
request does not require retail listing completion or authorize store submission.
Preserve sales status, pricing and territories unless asked to change them.

## Validate and upload

Use the archive/export produced by
[apple-app-build-prod](../apple-app-build-prod/SKILL.md). Match its bundle ID,
platform, version/build, signing and variant-specific production configuration
to the intended store app. Record pending runtime checks; a TestFlight upload may
precede distributed-runtime verification. Check existing builds before an upload
or retry so the same version/build is not delivered twice.

Use an existing Xcode account or App Store Connect API key for the verified team.
Verify key ID/issuer and app access against the console before first use; a local
key filename does not establish ownership. Keep private keys/tokens out of logs
and repository files. Inspect installed CLI help for current supported validation,
upload and status commands, or use Xcode's distribution workflow.

- **iOS:** validate/upload the exported store IPA.
- **macOS:** validate/upload the exported Mac App Store package from the selected
  archive; confirm app and package signing. Do not send a direct-distribution
  Developer ID app/DMG through the App Store flow.

Record artifact hash, upload result and delivery ID. Delivery success does not
prove processing or testing availability. Check processing for the exact matching
platform/version/build and complete encryption answers from actual app/SDK behavior.
If a command's outcome is ambiguous, inspect delivery status/current builds before
retrying; don't keep submitting while processing is pending.

## TestFlight

Wait for a processed usable build, then assign it to the intended existing testing
group or create one within the requested scope. Check group distribution settings
and actual tester membership; a default group may have zero testers. Use verified
project/account identities for the user's internal testing; don't invent external
recipients or create a public invitation link without a distribution request.
If a required tester address is missing, finish build preparation before asking.

Save useful What to Test notes from project files, reflecting changes and pending
hardware checks, and verify persistence after reload. Inspect available beta
locales rather than assuming retail locales are also configured for TestFlight.
Enable feedback when useful for the requested testing.

Internal testing and external beta review have different prerequisites. Complete
the required beta information/review for the chosen route; missing retail assets
are not automatically a blocker for internal tests. Verify the group's exact build
is **Testing** (or equivalent) and record whether testers are invited, accepted or
installed. An invitation does not prove acceptance or installation. Report external
beta review as pending until actually approved and distributed.

## Retail review

Use [apple-app-listing](../apple-app-listing/SKILL.md) for metadata/screenshots.
Select the editable platform/version matching the processed build. Verify canonical
copy per locale, accurate platform-specific screenshots, working required URLs,
published privacy declarations, age rating, review contacts and login requirements.
Complete relevant Release runtime checks and select the intended processed build.

Preserve the chosen release mode. When asked only for review and no mode is set,
choose manual release. Don't change phased release, ratings reset or other
platforms as a shortcut. The user's review-submission request authorizes the final
submission; don't add a redundant approval gate. Public release needs its own
instruction. For genuinely missing credentials, URLs, subjects or required facts,
finish independent preparation and identify the precise remaining input.

Add for Review may only stage a version. Inspect the final review summary, submit
when authorized and verify Waiting for Review or the actual resulting state.
If already submitted, report that state instead of submitting twice.

Record console URL, platform/variant, selected build, upload/processing outcome,
testing group/tester state or review status, release mode and remaining work in
the project's release reports. Never call a draft, delivery or invitation a
completed review or verified installation.
