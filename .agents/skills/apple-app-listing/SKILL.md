---
name: apple-app-listing
description: Prepare and update iOS or macOS App Store metadata and localized screenshots from project documentation and canonical copy, verifying persisted fields and platform-specific assets.
---

# Apple app store listings

Read the current repository's `README.md` and linked store/release docs. Discover
the app's own identity, metadata, review-contact and screenshot sources; use
`Store/store.config.json` or equivalent when present. Resolve platform, variant,
bundle ID, App Store ID and account/team before editing. Cross-check build settings
and the existing App Store Connect record if documentation conflicts. Never reuse
another app's IDs, contacts, claims, locale list, SDK settings or asset paths.

Use **ego-browser** for App Store Connect, reusing the goal's task space. Confirm
the account, app and **iOS or macOS platform** in the console before mutations.
Keep app-level fields separate from platform/version-level fields; don't overwrite
another platform's copy or another variant's advertising claims.

## Copy and privacy

Check implementation and current console state before writing copy. Advertise
implemented, verified behavior; exclude roadmap items and obsolete features.
Preserve existing locales unless requested otherwise, mapping project locale
codes to console codes. Read current field limits in the console or official
documentation. Keep real review contacts and set sign-in/demo requirements from
actual app behavior; no-login is not a universal default.

Use the project's canonical text files. Load text with Node's `fs/promises` inside
`ego-browser nodejs` and pass it to `page.fill` rather than retyping translations.
Wait for the actual save result; disabled Save may mean an in-flight request and
saved labels vary by page/language. Navigate away/back or reload, then compare
persisted text exactly or with a fingerprint. Track verification by locale and
platform. Keyword arrays require the console delimiter before comparison.
The optional [field fingerprint helper](scripts/field-sig.py) accepts any JSON
file plus a dotted string-field path; length alone is insufficient verification.

Derive privacy labels and export-compliance claims from the selected target's code,
entitlements, SDK manifests, actual configuration and current official disclosures.
Do not infer data collection from another variant. Verify support/privacy URLs
are real and reachable. Missing publishing destinations remain project inputs;
prepare local drafts without inserting guessed URLs in the console.

## Screenshots

Read the project's capture and composition convention, using existing scripts if
suitable. Platform-specific tooling belongs with project assets; this skill does
not prescribe a compositor, font family, device frame or fixed dimensions.

- **iOS:** capture the supported device families and display groups actually
  requested by the console. Use real hardware for camera/sensor-dependent screens;
  simulator captures are appropriate for accurately rendered ordinary UI.
- **macOS:** capture the real Mac app's windows and desktop UI at accepted Mac
  screenshot sizes. Preserve aspect ratio and readable controls. Do not stretch
  iPhone screenshots or wrap them in a phone frame for the Mac listing.

Confirm current accepted sizes and required groups in App Store Connect or Apple's
official documentation for the target platform. Wait for transitions to finish.
Keep personal subjects, notifications and raw private captures out of public assets
without authorization. Compose localized screenshots without distorting app content
or inventing UI/features. Inspect outputs/contact sheets for glyphs, wrapping,
controls and actual content before uploading; script success is not visual review.

Record the current locale/device sets before replacements. Check inheritance
before adding localized images; deleting replacements may restore inherited assets.
Prepare and inspect replacements before deleting existing sets. Upload in canonical
order and verify thumbnails, count, dimensions, language and platform afterward.

Record saved fields, verified locales/platforms and unresolved inputs in project
release docs. For submission use [apple-app-submit](../apple-app-submit/SKILL.md).
