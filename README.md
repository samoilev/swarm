<div align="center">
  <img src="docs/swarm-readme-banner-2560.png" width="100%" alt="Swarm — family trees, offline, on your own disk. macOS 14+, GEDCOM 5.5.1, MIT." />
  <br />
  <br />
  <br />
  <p>
    <a href="https://github.com/samoilev/swarm/actions/workflows/ci.yml"><img src="https://github.com/samoilev/swarm/actions/workflows/ci.yml/badge.svg" alt="CI status" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3B2F21?style=flat" alt="MIT license" /></a>
    <img src="https://img.shields.io/badge/macOS-14%2B-4F4132?style=flat" alt="macOS 14 or later" />
    <img src="https://img.shields.io/badge/Swift-5.9%2B-4F4132?style=flat" alt="Swift 5.9 or later" />
    <br />
    <img src="https://img.shields.io/badge/GEDCOM-5.5.1-6B5D4B?style=flat" alt="GEDCOM 5.5.1" />
    <img src="https://img.shields.io/badge/dependencies-none-6B5D4B?style=flat" alt="No third-party dependencies" />
    <img src="https://img.shields.io/badge/telemetry-none-6B5D4B?style=flat" alt="No telemetry" />
    <a href="#status"><img src="https://img.shields.io/badge/binaries-build%20from%20source-8A7C68?style=flat" alt="No published binaries; build from source" /></a>
  </p>
</div>

---

Swarm builds, visualizes and exports family trees, with particular attention to
Russian-language genealogy — full kinship terminology, patronymics, Cyrillic place data,
and the encodings that Soviet-era records arrive in.

Your trees are plain GEDCOM files in a folder you can open in Finder. There are no
accounts, no cloud sync, no analytics, and no AI services. Editing, search, validation
and place lookup all run offline.

- **Platform:** macOS 14+, SwiftUI + AppKit, Apple silicon
- **Toolchain:** Swift 5.9+ (developed against Swift 6.x), Swift Package Manager
- **Dependencies:** none — no third-party Swift packages
- **License:** [MIT](LICENSE)

## Status

Swarm works and is used daily, but treat it as a personal project rather than a finished
product:

- **There is no download.** No signed installer, no notarized build, no auto-update. You
  build it from source. See [Build and run](#build-and-run).
- **Apple silicon only.** No Intel or universal build.
- **Bug reports are welcome; pull requests are not being accepted yet.** See
  [CONTRIBUTING.md](CONTRIBUTING.md).

The DMG files attached to older releases are ad-hoc-signed artifacts kept for historical
reference. They are not supported downloads.

## Screenshots

<!-- TODO: add tree view, fan chart, map and person card screenshots -->

## Features

- **Tree diagram** using the Buchheim–Jünger–Leipert layout, an **ancestor fan chart**,
  and a **map** of birth, death and burial places.
- **Russian kinship naming** — direct lineage, full and half siblings, cousins including
  removed cousins, and in-laws (свёкор/тесть, деверь/шурин, золовка/свояченица, …).
  Ask "how are these two related?" about any pair and get the correct term.
- **Russian and English interfaces**, switchable in Settings without restarting. Russian
  is the default.
- **Photos and arbitrary file attachments** on any person.
- **Workspaces built for large trees** — people, timeline, places, review, recovery, and
  sources and citations.
- **GEDCOM 5.5.1 import and export** that interoperates with Ancestry, Gramps and
  MyHeritage, standard map coordinates included. Structures Swarm doesn't model —
  event-level notes, source records, other programs' custom tags — survive
  import → edit → export unchanged, and the original imported file is kept verbatim as
  `original-import.ged`.
- **Merge someone else's tree into yours** — matching people are combined rather than
  duplicated, exact matches are found automatically, and likely matches are only
  suggested. A backup is taken first and any failure rolls back completely.

## Privacy

Genealogy data is other people's personal data, much of it about people who are still
alive. Swarm is built accordingly:

- **Nothing is uploaded.** No accounts, no sync, no telemetry, no crash reporting, no AI
  services.
- **Place lookup is entirely local.** Names are matched against a bundled snapshot of
  GeoNames data, so searching for a village sends nothing anywhere.
- **The map is the only optional network path.** The default `appleMaps` provider renders
  through MapKit, so Apple supplies the tiles and may receive the region being viewed.
  Swarm does not submit names, records, pins or annotations. The `offlineVector` provider
  in Settings replaces it with bundled Natural Earth vectors and the local place index —
  no MapKit view, no network tiles at all.
- Selected place text, dataset ID and coordinates are stored in the tree, so a later
  place-data update can never silently move a historical place.

Swarm is not run in the macOS App Sandbox, so it can read GEDCOM files and photos you
select anywhere on disk.

## Storage model — GEDCOM is the source of truth

Trees live in `~/Library/Application Support/Swarm/`, one folder per tree:

```
<Tree Name>/
  ├── <Tree Name>.ged      — the tree itself (stable identity stored as the _TREEID tag)
  ├── original-import.ged  — verbatim copy of an imported file (if the tree was imported)
  ├── Media/               — person portrait photos (GEDCOM OBJE)
  ├── Attachments/         — arbitrary files attached to people (GEDCOM _ATTC)
  └── .Swarm/
      ├── History/         — latest 50 previous GEDCOM revisions
      └── Trash/           — replaced/deleted files, retained for 30 days
Archived/                  — trees removed from the library but kept on disk
Recovery/<tree-id>/        — permanent pre-v2 and pre-merge full-bundle backups
```

Because identity lives inside the GEDCOM (`_TREEID`), the folder and file can be renamed
freely when the tree is renamed.

Every save is written to a temporary folder, checksummed file by file, and swapped into
place only after it verifies — a crash or power cut mid-save cannot leave a half-written
archive.

On first launch, Swarm moves storage from the app's previous name into this location, as
long as the `Swarm` folder does not already exist. If both exist, neither is merged or
overwritten: Swarm uses its own folder and reveals the older one in Finder for manual
review.

**Custom tags** (beyond standard GEDCOM 5.5.1): `_FTSVER` and `_FTSID` remain stable
compatibility identifiers; tree metadata uses `_TREEID`, `_NAME`, `_SUBTITLE`, `_HOME`
and `_ROOT`; person data uses `_PATR`, `_MARNM` and `_ATTC`. Coordinates are written as
the **standard** `PLAC › MAP › LATI/LONG` triple so they interoperate with other tools;
legacy `_COORD lat lon` is still read, and used as a private fallback when coordinates
have no place to host a `MAP`.

## Build and run

```sh
git clone https://github.com/samoilev/swarm.git
cd swarm
swift build -c release
swift run -c release Swarm
```

`swift build` alone gives you a debug build, which is fine for development but noticeably
slower on large trees.

You can also open the package folder directly in Xcode (`File ▸ Open…`).

For isolated development, launch with
`--storage-folder /absolute/path/to/temporary-library` to keep a real library untouched.

## Architecture

The code splits into two SPM targets so the domain logic can be tested without the UI:

```
Swarm/
  Core/        → SwarmCore library (pure logic, no SwiftUI)
    Models/    → Person, Union, FamilyTree, FamilyIndex, FamilyDate, calculators
    Services/  → GEDCOMParser, GEDCOMSerializer, TreeStore, TreeLayoutEngine
    Resources/ → bundled GeoNames / places TSVs and Natural Earth vectors
  App/         → Swarm executable (SwiftUI views, theme, app entry)
Tests/
  SwarmCoreTests/   → Swift Testing suites and synthetic GEDCOM fixtures
UITests/             → native XCUITest bundle only; no production sources
SwarmUI.xcworkspace/ → package + test-only Xcode host
```

**SwiftPM is the canonical build.** The small Xcode project under `UITests/` contains
only an XCUITest bundle; `SwarmUI.xcworkspace` combines it with the Swift package, and it
duplicates no production sources or dependencies.

## Tests

```sh
./Scripts/run-tests.sh   # runs `swift test`
```

The suite uses [Swift Testing](https://developer.apple.com/documentation/testing)
(`import Testing`). On machines with only the Command Line Tools installed, SwiftPM
doesn't add the test frameworks to the search path automatically, so the wrapper script
passes them. Filesystem integration tests run serially for deterministic bundle swaps.

Coverage:

```sh
swift test --enable-code-coverage
```

Native smoke tests require full Xcode: open `SwarmUI.xcworkspace` and run the shared
`Swarm-UI` scheme. Every launch gets an isolated `--storage-folder`, so the test host
cannot touch a real library.

## Formatting

Formatting is enforced with [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
using the conservative `.swiftformat` config. CI runs a pinned version:

```sh
mint run nicklockwood/SwiftFormat@0.61.1 --lint .   # check, as CI does
mint run nicklockwood/SwiftFormat@0.61.1 .          # apply
```

`brew install swiftformat` works too, but the pinned version is what CI enforces.

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push to `main` and
every pull request: it builds all targets, runs the tests, and checks formatting. Any
build error, test failure or formatting violation fails the job.

## Packaging a local build

`build_dmg.sh` builds a release binary, assembles the `.app` with both resource bundles,
runs the tests, verifies the app and the DMG, reports architecture and signing status,
and writes a `.sha256` checksum. The version comes from `VERSION`.

Without `CODESIGN_IDENTITY` the script ad-hoc-signs and skips notarization, which is fine
for your own machine — Gatekeeper will warn on first launch. The script keeps an explicit
path for a properly signed build if a Developer ID is ever available:

```sh
CODESIGN_IDENTITY="Developer ID Application: …" \
NOTARY_PROFILE="<notarytool keychain profile>" \
./build_dmg.sh
# or APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD instead of NOTARY_PROFILE
```

Nothing produced this way is published. Distributing a signed, notarized build is a
separate decision that hasn't been taken.

## Contributing and support

- Bug reports and feature requests: [open an issue](https://github.com/samoilev/swarm/issues).
  **Never attach a real family GEDCOM** — see
  [CONTRIBUTING.md](CONTRIBUTING.md#never-attach-a-real-family-gedcom).
- Pull requests: not accepted yet. [CONTRIBUTING.md](CONTRIBUTING.md) explains why.
- Security issues: [SECURITY.md](SECURITY.md) — report privately, not as an issue.
- Getting help: [SUPPORT.md](SUPPORT.md).
- Changes by version: [CHANGELOG.md](CHANGELOG.md).

## License and attribution

Swarm's source code is [MIT licensed](LICENSE).

Bundled place and map data is third-party and carries its own terms — GeoNames under
CC BY 4.0, Natural Earth in the public domain. Full attribution is in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The Swarm name and icon are not covered
by the MIT license; please rename and re-icon any fork you redistribute.
