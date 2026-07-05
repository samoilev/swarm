# Родословная Студия (FamilyTreeStudio)

A native macOS app for building, visualizing, and exporting family trees, aimed at
Russian-speaking genealogy. Trees are stored locally as GEDCOM files; everything runs
fully offline.

- **Platform:** macOS 14+, SwiftUI + AppKit
- **Toolchain:** Swift 5.9+ (developed against Swift 6.x), Swift Package Manager
- **Dependencies:** none (no third-party packages)

## Features

- Tidy tree diagram (Buchheim–Jünger–Leipert layout), ancestor fan chart, and a map of
  birth/death/burial places.
- Russian kinship naming — direct lineage, full/half siblings, cousins (incl. removed),
  and in-laws (свёкор/тесть, деверь/шурин, золовка/свояченица, …).
- Photos and arbitrary file attachments per person.
- GEDCOM 5.5.1 import/export that interoperates with Ancestry, Gramps, and MyHeritage,
  including standard map coordinates. Structures the app doesn't model (event-level
  notes, source records, custom tags) are **preserved through import → edit → export**,
  and the original imported file is kept verbatim as `original-import.ged`.

## Architecture

The code is split into two SPM targets so the domain logic can be tested independently
of the UI:

```
FamilyTreeStudio/
  Core/        → FamilyTreeCore library (pure logic, no SwiftUI)
    Models/    → Person, Union, FamilyTree, FamilyIndex, FamilyDate, calculators
    Services/  → GEDCOMParser, GEDCOMSerializer, TreeStore, TreeLayoutEngine
    Resources/ → bundled GeoNames / places TSVs
  App/         → FamilyTreeStudio executable (SwiftUI views, theme, app entry)
Tests/
  FamilyTreeCoreTests/  → Swift Testing suites for the Core library
```

**SwiftPM is the canonical (and only) build.** Open the package directly in Xcode
(`File ▸ Open…` the folder) or build from the command line — there is no `.xcodeproj`.

### Storage model — GEDCOM is the source of truth

Trees live in `~/Library/Application Support/FamilyTreeStudio/`, one folder per tree:

```
<Tree Name>/
  ├── <Tree Name>.ged      — the tree itself (stable identity stored as the _TREEID tag)
  ├── original-import.ged  — verbatim copy of an imported file (if the tree was imported)
  ├── Media/               — person portrait photos (GEDCOM OBJE)
  └── Attachments/         — arbitrary files attached to people (GEDCOM _ATTC)
Archived/                  — trees removed from the library but kept on disk
```

Because identity lives inside the GEDCOM (`_TREEID`), the folder/file can be renamed
freely when the tree is renamed.

**Custom tags** (beyond standard GEDCOM 5.5.1): `_TREEID`, `_NAME`, `_SUBTITLE`, `_HOME`,
`_ROOT` (HEAD metadata); `_PATR` (patronymic), `_MARNM` (married name), `_ATTC`
(attachment). Coordinates are written as the **standard** `PLAC › MAP › LATI/LONG`
triple so they interoperate with other tools; legacy `_COORD lat lon` is still read, and
used as a private fallback when coordinates have no place to host a `MAP`.

### Privacy

Fully offline. Place names are geocoded solely against the bundled GeoNames database and
never leave the device; a place not in the database simply isn't pinned on the map. The
app makes no network calls at all (no networking APIs are linked). It is **not** run in
the macOS App Sandbox — privacy comes from being genuinely offline, not from a sandbox
profile — so it can read the GEDCOM files and photos you point it at anywhere on disk.

## Build & run

```sh
swift build              # build everything
swift run FamilyTreeStudio   # launch the app
```

Or use the VS Code launch configurations in `.vscode/launch.json`.

## Tests

```sh
./Scripts/run-tests.sh   # runs `swift test`
```

The suite uses [Swift Testing](https://developer.apple.com/documentation/testing)
(`import Testing`). On machines with only the Command Line Tools installed, SwiftPM
doesn't add the test frameworks to the search path automatically, so the wrapper script
passes them; with full Xcode (and in CI), plain `swift test` works.

Coverage (core logic line coverage is ~84%):

```sh
swift test --enable-code-coverage
```

## Linting

Formatting is enforced with [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
using the conservative `.swiftformat` config:

```sh
brew install swiftformat
swiftformat --lint .     # check (CI runs this)
swiftformat .            # apply
```

## Release

`build_dmg.sh` builds a release binary, assembles the `.app` (copying both the app and
core resource bundles), signs it, and produces a DMG. The version is read from the
`VERSION` file.

For a distributable, notarized build set the relevant environment variables:

```sh
CODESIGN_IDENTITY="Developer ID Application: …" \
NOTARY_PROFILE="<notarytool keychain profile>" \
./build_dmg.sh
# or APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD instead of NOTARY_PROFILE
```

Without `CODESIGN_IDENTITY` the script ad-hoc-signs and skips notarization (local use
only; Gatekeeper will warn).

## Continuous integration

`.github/workflows/ci.yml` runs on every push to `main` and every PR: it builds all
targets, runs the tests, and checks formatting. The job fails on any build error, test
failure, or formatting violation.
