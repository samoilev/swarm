# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions 1.0.0 through 2.1.0 were released under the project's earlier Russian name and
had Russian-only release notes. Those notes are translated here, so this file is the
single English record of what changed and when.

## [Unreleased]

## [2.2.1] — 2026-07-28

### Fixed

- **The downloadable app crashed on launch for everyone except the person who built
  it.** SwiftPM's generated `Bundle.module` searches only next to the executable and an
  absolute path inside the build machine's `.build` directory — never
  `Contents/Resources`, where a packaged `.app` keeps its resources. On the build
  machine the leftover `.build` directory satisfied it and hid the fault. Resource
  lookups now resolve through the app bundle first and fall back to `Bundle.module` for
  `swift run` and tests. Every DMG published before this one was affected.
- Releases are now smoke-tested with the build directory hidden, which reproduces a
  user's machine, so a packaging fault of this kind fails the release instead of
  shipping.

## [2.2.0] — 2026-07-28

### Added

- **Downloadable builds.** Each release now carries a DMG built by GitHub Actions from a
  clean checkout, together with a SHA-256 checksum. The build is **not** signed with an
  Apple Developer ID and is not notarized, so the first launch needs a right-click →
  Open. Apple silicon only.
- A test asserting that every translatable string has an English entry, so an
  untranslated string fails the build instead of quietly falling back to Russian.

### Changed

- Renamed the project to **Swarm**. Existing data is migrated automatically on first
  launch: the old application-support folder is moved, per-tree metadata folders are
  renamed, and the saved interface-language preference carries over. GEDCOM files
  exported by earlier versions still import unchanged.
- Opened the source under the MIT license, with third-party data attribution, a security
  policy, contribution guidelines and a code of conduct.

### Fixed

- Corrected the Russian feminine labels for adoptive and uncertain daughters.

## [2.1.0] — 2026-07-18

### Added

- **English interface.** Every screen, menu, error message and export is now available
  in English as well as Russian. Switch languages in Settings; the change applies
  immediately, without restarting.

## [2.0.0] — 2026-07-17

A release about trusting the archive: harder to corrupt, easier to repair, and able to
merge with a relative's tree.

### Added

- **Saves that cannot be interrupted halfway.** Every save is written to a temporary
  folder, checksummed file by file, and swapped into place only after it verifies. A
  power cut mid-save can no longer leave a half-written archive.
- **Version history.** The last 50 saves of each tree are kept, and any of them can be
  restored.
- **Trash.** Photos and documents removed from a person's card stay recoverable for 30
  days.
- **Backups** taken before any large operation are kept indefinitely. History, trash and
  backups all live in a new **Recovery** section.
- **Tree merging.** When a relative sends their tree, or you export one from another
  service, Swarm brings across the missing people, dates and sources and merges matching
  people into one instead of duplicating them. Exact matches are found automatically;
  likely matches are only ever suggested, and the decision stays yours. A backup is taken
  first, and any error rolls the tree back to exactly its previous state.
- **Import preview.** Before anything touches the archive, you see how many people,
  unions and sources were found, plus every error and warning. Verified against real
  exports from Ancestry, Gramps and MyHeritage.
- **Sources and evidence.** Any fact — a name, date, place or relationship — can carry a
  source with a page reference, a quotation and a confidence level.
- **Explicit parent relationship types**: biological, adoptive, guardianship, and
  step-parent. Kinship names take them into account.
- **Four new sections.** *People* — a searchable, sortable list with a "missing data"
  filter. *Timeline* — every person's events in order. *Places* — which places recur most
  often. *Review* — every problem found in the data, plus possible duplicates, each
  linking straight to the relevant card.

### Changed

- **Apple Maps is now the default map**, with cities and terrain. The fully offline map
  is still one click away in Settings if you want no network requests at all. Under
  either option, names, events and notes are never sent anywhere.

### Breaking

- **Trees created by 1.x cannot be saved until you upgrade their format.** They open and
  read normally, and Swarm changes nothing on disk by itself. Run the format upgrade once
  from the Recovery section; a full backup is taken automatically first and the original
  files are not deleted.
- **GEDCOM export now produces a folder, not a single file.** `Media/` and `Attachments/`
  sit alongside the `.ged`.

## [1.10.0] — 2026-07-05

### Added

- **Lossless GEDCOM round-tripping.** Import → edit → export no longer drops anything.
  Structures Swarm doesn't display — event-level notes, `SOUR` records, other programs'
  custom tags — are preserved and written back out unchanged.
- **The original imported file is kept** alongside the tree as `original-import.ged`, in
  case of any compatibility surprise.

### Fixed

- **Correct term for a wife's father.** He is now «Тесть» rather than «Свёкор». The full
  set of husband-side and wife-side in-law terms is covered by tests.
- Long notes now wrap at the standard 255-character limit, and slashes in names no longer
  corrupt the record.
- **An unreadable tree now says so** and opens its folder in Finder. Previously it
  vanished from the library without a word.
- Marriage data is no longer lost when one spouse is deleted.
- Date validation rejects impossible dates such as 31 February.

### Performance

- **Photos load on demand** instead of all at once, cutting memory use substantially on
  trees with many portraits.
- **Place search no longer blocks the interface** — the ~455,000-settlement database is
  searched in the background.

## [1.9.0] — 2026-06-21

### Added

- **Tree diagram in PDF export.** The first page is now the tree itself, rotated 270° to
  fit landscape, followed by the individual person cards. The diagram is drawn as
  vectors, so cards and text stay sharp at any zoom; portraits are included if they are
  shown on the canvas.
- **Export just the selection.** A separate button exports only the highlighted
  people — the relationship path between two ⌘-selected people, or a selected person's
  ancestors and descendants.
- **Burial place on the map**, shown as its own marker and joined to the place of death
  by a dotted line.

## [1.8.1] — 2026-06-21

### Changed

- Internal cleanup only, with no change in behaviour: removed about 250 lines of dead
  code and unused abstractions, and simplified offline place lookup to a single
  synchronous search against the local GeoNames database.

## [1.8.0] — 2026-06-18

### Added

- **Person search (⌘F).** Search by name; picking a result pans and centres the tree on
  that person.
- **Automatic centring** — selecting an off-screen person smoothly brings them to the
  middle.
- **Arrow-key navigation**: ↑ parent, ↓ child, ← / → siblings.
- **Tree minimap** in the bottom-right corner while zoomed in — an overview, and a click
  to jump.
- **Keyboard shortcut bar** in the bottom-left, collapsible to an icon in one click.
- **Relationship in one ⌘-click.** Hold ⌘ and pick a second person: Swarm names how the
  two are related and highlights the path between them.
- **Sex icons (♂/♀)** on cards, so sex reads without relying on colour.

### Changed

- Much smoother and faster zooming and panning, with card text sharp at any scale.
- Animations respect the system "Reduce motion" setting.

### Fixed

- Connector lines no longer judder while panning.
- Clicking empty background now clears the selection.

## [1.7.1] — 2026-06-18

### Fixed

- **Sharp tree at every zoom level.** Card text and lines no longer pixelate when zoomed
  in: the tree renders with headroom and scales through a single hardware transform.
- Zooming is smooth and stable — cards, labels and connectors move as one piece, without
  jerking or stalling as the scale changes.
- Clicking any empty background clears the card selection and closes the detail panel.

## [1.7.0] — 2026-06-18

A release about accessibility and peace of mind.

### Added

- **VoiceOver support.** Toolbar buttons and person cards in every view — tree, ancestor
  fan and map — are read out with name, life dates and sex. Nodes can be selected from
  the keyboard. Saving, adding and deleting are announced.
- **Undo (⌘Z) and Redo (⌘⇧Z)** for adding, editing and deleting people. An accidental
  deletion is no longer permanent.
- **"How are they related?"** — a new button that names the relationship between two
  people. The capability existed before, but was hidden.
- A **Back** button in the inspector, stepping back through the chain of relatives.
- A **"Saved" confirmation** after editing, and the time of the last save always visible
  in the toolbar.
- An empty tree now offers to add the first person.

### Changed

- Muted text contrast raised to **WCAG AA**, making labels noticeably easier to read.
- Inspector labels are larger.

## [1.6.0] — 2026-06-13

### Changed

- **Standard GEDCOM coordinates.** Place coordinates are now written as the standard
  `PLAC › MAP › LATI/LONG` triple, so trees open correctly in Ancestry, Gramps and
  MyHeritage with their place maps intact. The old format is still read.
- **Geocoding is now fully offline.** Place names are never sent over the network;
  coordinates come only from the bundled GeoNames database.
- **Rewritten GEDCOM parser** with exact tag recognition and tolerance for non-standard
  files — Windows-1251 and UTF-16 encodings, a missing `TRLR`, values that begin with a
  tag name, and similar.

### Fixed

- Saving now touches only the tree that changed, and no longer rewrites unmodified photos
  on every edit.
- Save and export errors are shown to the user instead of being swallowed silently.

### Internal

- Split the domain logic into a `FamilyTreeCore` library with unit tests (~84% coverage
  of the core logic) and continuous integration — build, tests and formatting checks on
  every commit.

## [1.5.0] — 2026-06-03

### Added

- **Momentum scrolling** — the tree keeps gliding after you release the mouse.
- **Spring-animated wheel zoom**, anchored to the cursor.
- **⌘+ / ⌘−** zoom relative to the centre of the screen; **⌘0** returns to fit-to-window.

### Changed

- The place-of-death field accepts free text instead of requiring a pick from the list.
- The edit button moved out of the toolbar and into the opened person card.

### Fixed

- Coordinates now resolve correctly for identically named towns, by taking the region
  into account.
- Minimap pins are visible again, and their labels show the settlement name instead of
  "Birth" / "Death".
- The minimap updates immediately after a birth or death place changes.
- The city dropdown no longer covers other fields, and clicking away closes it.

## [1.4.0] — 2026-06-03

### Added

- **Attach any file to a person** — photos, PDFs, documents — with thumbnails.
- **Birth and death coordinates**, entered by hand or filled in from the place list.
- **A minimap inside the opened person card**, with birth and death pins.
- **Photo cropping on upload**, with a consistent 3:4 portrait format everywhere.
- **Selectable text** in the person card view.
- Place search now covers name, region and country, returns up to 60 scrollable results,
  and no longer shows Latin transliterations. Enter confirms free-text entry.
- **PDF export of person cards** — white background, full-size images from attachments,
  one person per page.
- GEDCOM export now includes attachments, in an `Attachments` folder beside the `.ged`.

### Changed

- **Readable tree folder names.** The folder and GEDCOM file now carry the tree's name
  instead of a UUID. The tree's identity moved inside the GEDCOM as `_TREEID`, so
  renaming no longer breaks it. Old folders migrate automatically on first launch.
- New Tree and Import GEDCOM moved into their own bar above the library grid.
- Photos in the tree are shown by default.
- The fan chart shows maiden names (centre and outer sectors) and birth years at every
  sector size.
- Surnames of any length now fit tree nodes without truncation.

### Removed

- Poster / PNG export.

## [1.3.0] — 2026-06-02

### Added

- **Couple-anchored tree layout.** Married partners are drawn adjacent, with each side's
  ancestry fanning upward, which removes the long connectors that used to cross between
  branches. Connector routing is standardised and separate branches are spaced more
  clearly.
- **Free-text notes in the Add Person form** — previously edit-only — in a vertically
  resizable field.
- **Native file dialogs** for photo and GEDCOM import and PNG/PDF export, with clear
  error messages on failure.
- Toolbar overflow menu for narrow windows; zoom and level steppers support
  press-and-hold.

### Changed

- **Smoother navigation**: wheel zoom toward the cursor, plus a softened, centred
  trackpad pinch.
- **ФИО name order** (surname, given name, patronymic) applied consistently across
  dropdowns, the inspector, exports and input forms.
- **Reworked kinship engine.** Descendant spouses get qualified labels (e.g. «Муж
  внучки»), direct spouses are recognised, half-siblings are distinguished
  (единокровный / единоутробный), and parents recorded in separate records are merged
  correctly. Canvas dual-selection and the relationship dialog now agree.
- GEDCOM import falls back to Windows-1251 and UTF-16 encodings.
- Tree layout is cached and recomputed only on structural change.

### Fixed

- Toolbar buttons no longer stop responding after panning or zooming the canvas.
- Corrected the inverted parent/child direction when adding a relative.
- Place and geocoding databases load off the main thread with debounced search, so
  opening a form or the map no longer freezes.
- Added missing settlements: Могоча, and Прииск имени Серго Орджоникидзе.

## [1.2.0] — 2026-06-01

### Added

- **Offline geocoding from GeoNames** — over 252,000 settlements of the former USSR,
  resolving coordinates without an internet connection for the great majority of places.
- **Historical place names** are understood (Ленинград → Санкт-Петербург, Сталинград →
  Волгоград, and others).
- ё/е normalisation in search.
- Fallback to Apple's `CLGeocoder` for places outside the database.

### Changed

- Automatic tree centring, a dotted background grid, and popovers for map pins.

## [1.1.0] — 2026-05-31

### Added

- **Configurable fan chart depth** — 2 to 8 generations, defaulting to 4 — with automatic
  fit-to-window on open and on depth change.
- Adaptive sector text: falls back to "Surname G.P." when space runs short.

### Changed

- Unified tree grid with a standard 40 px gap between all cards.
- Family branches are separated onto their own sides, so connectors no longer cross.

### Fixed

- Overlapping cards, caused by inline-spouse centring.

## [1.0.0] — 2026-05-31

First release. A macOS app for building a family tree.

### Added

- Tree visualisation using the Buchheim layout algorithm.
- Ancestor fan chart.
- GEDCOM (`.ged`) as the storage format, with import and export.
- Photos, patronymics and maiden names.
- Kinship calculation.
- PDF export.
- Russian interface with a warm sepia theme.

Requires macOS 14+ on Apple silicon.

[Unreleased]: https://github.com/samoilev/swarm/compare/v2.2.1...HEAD
[2.2.1]: https://github.com/samoilev/swarm/compare/v2.2.0...v2.2.1
[2.2.0]: https://github.com/samoilev/swarm/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/samoilev/swarm/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/samoilev/swarm/compare/v1.10.0...v2.0.0
[1.10.0]: https://github.com/samoilev/swarm/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/samoilev/swarm/compare/v1.8.1...v1.9.0
[1.8.1]: https://github.com/samoilev/swarm/compare/v1.8.0...v1.8.1
[1.8.0]: https://github.com/samoilev/swarm/compare/v1.7.1...v1.8.0
[1.7.1]: https://github.com/samoilev/swarm/compare/v1.7.0...v1.7.1
[1.7.0]: https://github.com/samoilev/swarm/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/samoilev/swarm/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/samoilev/swarm/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/samoilev/swarm/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/samoilev/swarm/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/samoilev/swarm/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/samoilev/swarm/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/samoilev/swarm/releases/tag/v1.0.0
