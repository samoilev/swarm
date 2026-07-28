# Contributing to Swarm

Thanks for looking. Please read this before opening anything.

## What is welcome right now

**Bug reports and feature requests.** Open an issue — these are genuinely useful and
they get read.

**Pull requests are not being accepted yet.** Swarm has one maintainer, no contributor
license process, and no review capacity. Unsolicited PRs will most likely be closed
without review, even good ones. That is a bandwidth limit, not a judgment of the work.
If you want to change something, open an issue first and say so; if it makes sense,
you'll be asked for a PR.

Fork freely — the code is MIT licensed.

## Reporting a bug

Use the bug report form. It asks for macOS version, Swarm version (see the `VERSION`
file), and which interface language you were using — Russian and English take different
code paths, so this matters.

### Never attach a real family GEDCOM

Genealogy files contain living people's names, birth dates and places. Do not paste or
attach a real one to a public issue.

To share a reproduction, either:

- Reduce it to the smallest synthetic GEDCOM that still fails. The fixtures in
  `Tests/SwarmCoreTests/` show the shape and level of detail that works, and they are
  fully synthetic — copy one and modify it.
- Or replace every name, date and place with invented values, keeping only the
  structure that triggers the bug.

If a bug only reproduces with real data, say so in the issue and it can be handled
privately.

## Building and testing

```sh
swift build              # build everything
swift run Swarm          # launch the app
./Scripts/run-tests.sh   # run the test suite
```

`Scripts/run-tests.sh` wraps `swift test` and adds the Swift Testing framework paths,
which SwiftPM does not add automatically on machines with only the Command Line Tools
installed.

Native UI smoke tests require full Xcode: open `SwarmUI.xcworkspace` and run the shared
`Swarm-UI` scheme.

## Formatting

Formatting is enforced in CI with a pinned SwiftFormat version:

```sh
mint run nicklockwood/SwiftFormat@0.61.1 --lint .   # check, as CI does
mint run nicklockwood/SwiftFormat@0.61.1 .          # apply
```

`brew install swiftformat` also works locally, but the pinned version is what CI runs.

## Both languages, every time

Swarm ships in Russian and English. Russian is the default and the source language:
Russian strings are the lookup keys, and English translations live in
`Swarm/Core/Resources/Localization/en.lproj/Localizable.strings`.

Any change that touches user-facing text must cover both languages — controls, menus,
help text, accessibility labels, empty and error states, generated labels, and exported
or printed copy. Route all UI copy through `L10n`; never add a bare user-facing string
literal. A test enforces that every `L10n` key has an English translation, so a missed
one fails the build.

Check that the English string still fits the layout. English is often longer.
