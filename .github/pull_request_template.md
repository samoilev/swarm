<!--
Pull requests are not being accepted yet — see CONTRIBUTING.md. Please open an issue
first. If you were asked for a PR, this is the checklist.
-->

## What this changes

<!-- One or two sentences. Link the issue this came from. -->

Closes #

## Checklist

- [ ] `swift build` succeeds
- [ ] `./Scripts/run-tests.sh` passes
- [ ] `mint run nicklockwood/SwiftFormat@0.61.1 --lint .` is clean
- [ ] Every changed line traces back to the issue — no drive-by refactors or reformatting

### Both languages

Skip this section only if the change touches no user-facing text at all.

- [ ] All new user-facing copy goes through `L10n` — no bare string literals
- [ ] English translations added to `Swarm/Core/Resources/Localization/en.lproj/Localizable.strings`
- [ ] Covered: controls, menus, help text, accessibility labels, empty and error states,
      generated labels, and exported or printed copy
- [ ] Checked in the running app in **both** Russian and English — English is often
      longer, so confirm nothing truncates or wraps badly
