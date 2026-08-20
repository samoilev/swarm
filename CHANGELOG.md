# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions 1.0.0 through 2.1.0 were released under the project's earlier Russian name and
had Russian-only release notes. Those notes are translated here, so this file is the
single English record of what changed and when.

## [Unreleased]

### Changed

- The person editor's evidence section is now a list of sources you can read back, edit
  and delete, replacing a form that could only ever add. Each entry is one source plus
  one citation, and the archival fields are labelled the way a Russian archive reference
  reads: **Фонд**, **Опись**, **Дело**, **Лист**. The GEDCOM tags behind them (`PUBL`,
  `REPO`, `CALN`, `PAGE`) are unchanged, so files written by earlier versions still read
  back the same.
- Sources gained a web address, exported as `1 _URL` — the tag the project's own source
  packs already use. Imported `_URL` lines are now a real field instead of preserved text.
- Editing a source that several people cite forks it instead of rewriting what everyone
  else points at. Deleting the last citation of an app-created source removes the record;
  imported records are always kept.
- `AUTH` and `QUAY` no longer have editor fields. Both still survive import and export
  verbatim, and a library saved by an earlier version keeps its author. They now appear
  after the modelled `NOTE` in exported files rather than before it.
- A value shaped like `@X@` typed into a text field is escaped on export, so it can no
  longer leave the file naming a record that does not exist.

### Removed

- The shared source library, the "Для факта" target picker and the reliability field.
  Citations added in the editor now attach to the person. Citations an imported file
  attached to a birth, a name, a union, a parent link or an attachment are kept and still
  export, but the editor no longer lists or creates them.

## [3.2.1] — 2026-08-15

Swarm is now free software under the **GNU General Public License v3.0**. MIT let anyone
ship a closed-source paid fork; the GPL makes derivatives publish their source instead.
It does not restrict commercial use, which no OSI-approved license can do. Releases up
to and including 3.2.0 stay MIT and cannot be revoked — only this version and later
carry the GPL, so forks and redistributors of anything after 3.2.0 must comply with it,
while code taken from 3.2.0 or earlier remains available under MIT.

### Added

- “About Swarm” links to the public GitHub repository.

### Changed

- The opening fit and the focus glide run smoothly. Portraits are around 1000×1400 in a
  66×88pt slot, and the image was rebuilt from data inside the card's body on every
  evaluation, discarding its decode each time — 273ms of main-thread first paint and
  215MB of texture for a 47-person tree, spent while the entrance cascade and the 1.2s
  glide were running. Downsampling once and caching brings that to 27ms and 15MB; 352px
  keeps the portrait 1:1 at maximum zoom.
- The dot grid animates with the tree instead of jumping to its final phase on the first
  frame and sitting still while the cards glided, which read as the tree sliding over
  frozen paper.
- README gains a Quick look screenshot section, puts Build and run ahead of Example
  trees, folds Privacy into Features, and drops the example-tree table and most of the
  storage-model detail.

### Removed

- The public documentation is trimmed to the README, this changelog, the security policy
  and the third-party notices. The contributing guide, code of conduct, support page,
  product brief and pull request template are gone, along with the issue-template links
  that pointed at them.

## [3.2.0] — 2026-08-10

### Added

- Six historical family trees ship as importable examples, one folder per tree, with
  GEDCOM, portraits and documentary attachments. Public-record trees to try the app on
  instead of your own family data, and trees safe to attach to a bug report.
  `Examples/CREDITS.csv` records per-file license and attribution: 11 of the 184 images
  are CC BY or CC BY-SA and cannot be redistributed bare.
- Portraits open full size from the record. The inspector's header photo and a new
  first row under Files both open the sheet; the portrait stays in `Media/`, so the row
  is a view of it rather than a second copy in `Attachments/`.
- Full text on hover for titles, subtitles and library captions, but only when they are
  actually clipped.

### Changed

- The tree is laid out as a layered DAG, which is what a genealogy is. The old engine
  ran a tidy-tree over the home couple's ancestors only, and descendants, second spouses
  and detached branches fell through to a leftover loop that made each its own root.
  That one fact produced every reported symptom: marriage lines drawn straight across a
  row to a partner stranded in another band, couples never adjacent, and no
  representation at all for a person with more than one union. Unions are now nodes in a
  bipartite graph, generations come from longest paths over union-find classes that
  merge partners and siblings under an acyclicity guard, ancestors are pulled down to
  rest directly above their children, orderings are seeded outward from the home couple
  so a pedigree's two ancestral lines stay separated, and each generation gap carries
  routed lane bands whose height grows with the number of lanes.
- Columns are placed with Brandes–Köpf. The previous relaxation only nudged vertices
  toward their neighbours and gave up whenever separation blocked the move, so a couple
  with an only child could sit permanently off to one side and its descent kept a kink
  no amount of iteration removed. Alignments are now chosen first and whole chains
  compacted together, so an alignment is never bent by a later squeeze.
- The three tree-control pills moved to the toolbar's centre. Principal is the only
  placement macOS 26 centres — flexible spacers around an automatic group collapse to
  nothing — and the title block's cap rose from 160pt to 260pt.
- Smaller card font and adjusted card transparency.

### Fixed

- Saving a saved file no longer duplicates records. An example tree grew from 1803 to
  2925 lines over three saves: RESI/IMMI branches and FAM-level source citations were
  both modelled and preserved verbatim, so export wrote each twice and the next parse
  read four. Those branches are now parsed completely enough to be reproduced, and a
  branch whose citation was already read is no longer kept beside it.
- Editing a person with an alternate name no longer saves the alternate over the primary
  and drops the surname. The scalar name fields are seeded from the primary structured
  name instead of holding whatever the last `1 NAME` line wrote. This needed the two
  name paths to agree first: `_MARNM` takes the maiden name from the NAME slash form,
  and GIVN/SURN are sanitized on read the way the NAME line always was.
- Another program's citation detail survives a save. A cited source's unmodelled
  sub-lines were re-emitted only when the source xref failed to resolve, so in the
  normal case a save replaced the imported branch and dropped foreign place ids and
  every note past the first — 58 lines gone from a 12-person tree in one save. Event
  extras also track which level-2 branch a deeper line came from, so dropping a replaced
  source cannot swallow detail belonging to the event's place.
- Portraits no longer vanish after an edit. The editor works on a deep copy that
  round-trips through JSON and cannot carry the transient `Media/` folder, so the draft
  read back no portrait and Save wrote that emptiness onto the live person. Repointing
  the media folder now drops a cached read unless bytes are unsaved, so a lookup made
  before the folder was known cannot stick as “no portrait”.
- Tracing a relationship through one parent lights that parent's line only. Each child
  had a single highlight route carrying both parents' connections and both approach
  legs, so following the mother lit the father's half as well. Each child now gets one
  route per parent, drawn three ways because a marriage is: neighbouring partners take
  their half of the row line, a routed pair its own drop plus the lane run, and a spouse
  chain the same onto the shared line. Parent-to-child routes also used to begin at the
  union anchor, leaving the drop from the parents' cards unlit — 32 broken routes in one
  tree, worst on distant pairs where more of the path is made of these joins.
- Library card captions show their hover help. A Button takes the hover from its own
  label, so help attached to the caption never fired.

## [3.1.0] — 2026-08-09

### Added

- A bottom-to-top tree layout, the shape most printed genealogies use, with ancestors
  at the bottom. It is a vertical flip of the finished top-down drawing rather than a
  sign threaded through every depth, bus and elbow calculation.
- Hover states on the toolbar's shared-glass icons. The system highlight only reaches
  controls that carry their own glass, so the ends of the bar lit up under the pointer
  while the whole middle answered with nothing. Buttons, menus and the auto-repeat
  steppers now share one chrome treatment: the fill is gated on the control being
  enabled, so a clamped stepper stays dead, the grid menu wears the accent disc while
  its section is on screen, and the fan-level steppers carry the help labels zoom
  already had.
- Three or more surnames on a library card render as “и другие” / “and others”.

### Changed

- Help was rewritten to one idea per section and now carries the local-data and
  recovery facts that Settings used to state itself.
- The Settings window takes its height from its content instead of a hardcoded 590pt.
- Import GEDCOM in the library toolbar is icon-only, so the row stops overflowing at
  the 600pt minimum width. Past overflow AppKit collapses the flexible spacer and
  left-packs the survivors, which used to drag New Tree off the trailing edge.
- The README banner and social preview center the wordmark and drop their taglines,
  which still claimed macOS 14+ after the requirement moved to 26.
- Internal cleanup of dead code and duplicated helpers, 161 lines lighter with no
  change in behaviour: unreachable tree-store members are gone, the sync/async API
  pairs collapse to the verified form that surfaces write failures, drifting copies of
  the date, place, parentage, editor-field, fit-to-screen and GEDCOM-tokenizer helpers
  are hoisted to one home, and the hand-rolled leap-year table gives way to
  `DateComponents.isValidDate`.

### Fixed

- The serif theme renders New York through the `.serif` design. `NSFont(name: "New
  York")` is nil — it is a system face, not an installed family — so the custom font
  fell back to SF and every weight applied on top of it logged “Unable to update Font
  Descriptor's weight”, around twenty lines per launch.
- The inspector hides its scroll indicators. The overlay scroller landed on the close
  button and swallowed the click until it faded.

### Removed

- Settings drops its in-panel title, its section dividers, and the local-data and
  recovery blocks.

## [3.0.0] — 2026-08-08

Swarm is rebuilt on native macOS 26 chrome throughout, so this release **requires macOS
26 or later** and drops support for earlier systems.

### Added

- Tree cards in the library draw a scaled picture of the record itself, taken from the
  layout engine and cached on the tree store, instead of one arbitrary person's
  photograph standing in for a whole family.
- Opening a tree hands the card's nodes to the canvas through matched geometry, so the
  record grows out of the card rather than cutting to it.
- Creating a tree takes the whole window, with the card it will produce drawn live
  beside the form.
- Exact lineage connections and shortest-path relationship highlighting between two
  selected people.
- Regression coverage for lineage, relationship paths, layout, localization, GEDCOM
  round-trips, and the UI.

### Changed

- The opened-tree workspace now uses the native macOS 26 unified toolbar and Liquid
  Glass controls. Swarm now requires macOS 26 or later.
- “About Swarm” is now a native singleton window with the app icon, English product
  and version details, and Liquid Glass Help and Close actions.
- Tree creation, tree renaming, recovery, and Settings now share native macOS 26
  Liquid Glass headers, selection controls, and action groups. Language selection has
  been removed from tree creation and remains available in Settings.
- Selecting two people now emphasizes only their shortest relationship path.
- The library shares the unified toolbar the tree workspace already uses, with the
  traffic lights inline. It used to draw its own title under a stock title bar, so one
  window read as two applications.
- The person inspector floats over the canvas instead of sitting in an opaque slab
  welded to the window edge. Tree and fan draw their full width beneath it, and both
  take a trailing inset so fit, focus and pan bounds still measure the uncovered
  viewport. Map and the list views keep their own column, where rows sliding under
  glass would be lost.
- The inspector header puts back, edit and close on one row, with a rounded portrait
  and a placeholder, and moves delete past the record where it is labelled.
- Larger tree previews and titles in the library, with adjusted generation labels and
  a realigned toolbar wordmark.
- Compact toolbar overflow and the library's action controls.
- Keyboard navigation, canvas bounds, the minimap, and initial centering.
- Deployment targets and release metadata raised to macOS 26.

### Fixed

- Heritage highlighting follows exact relationship branches instead of coloring an
  unrelated part of a shared sibling connector.
- Selected and lineage cards retain their opaque archival fills, and the command-hint
  pill and minimap keep crisp, continuous edges.
- Importing accepts an archive folder, not only the `.ged` file inside it.
- GEDCOM names, places, evidence, events, and UTF-16 data survive a round trip.
- Validation, archives, attachments, and living-person handling are hardened.
- Scrolling inside the floating inspector no longer zooms the tree behind it. The
  window-wide scroll monitor only checked bounds, so a full-width canvas caught scrolls
  meant for the card; it now skips the covered trailing strip.

### Removed

- ⌘N and File ▸ New Tree. Creating a record is rare and deliberate, and a shortcut
  firing a full-window takeover over an open tree would throw the reader out of one
  without asking. The library's own button is the only door in.
- Redundant language selectors and legacy interface copy.

## [2.3.0] — 2026-07-29

### Added

- Motion across the tree screen. Cards lift under the pointer, the selection ring settles
  onto the chosen card, the lineage badge scales in, and the rest of the tree fades back
  so the selected person's line reads at a glance.
- Rearrangement in place of redrawing. Switching between top-down and left-right, adding
  a relative, deleting one, or refreshing the layout now glides every card to its new
  position; the connector lines fade for the move and return once the cards have settled.
- Hover states on the inspector's actions and on its links to relatives, which gave no
  response to the pointer before.
- A mandatory bilingual Russian/English chooser on pristine installations, with the
  same immediate language switch in the library, onboarding, Settings, and Help.
- Bilingual contextual Help for first steps, genealogy dates, kinship, workspaces,
  keyboard navigation, map privacy, and recovery.
- A pinned 476,958-place bilingual GeoNames snapshot (`geonames-2026-07-28`) covering
  every populated place in the 15 former-USSR countries and population ≥500 places plus
  populated-place capital/admin seats across Europe and all North America, including
  Central America and the Caribbean.
- Population-ranked, zoom-aware Russian/English labels on the offline map.

### Changed

- Momentum panning runs at the display's own refresh rate, with decay measured in time
  rather than frames, so the glide is the same on a 60 Hz screen and on ProMotion.
- Adding or editing a person no longer refits the viewport unless the tree has outgrown
  it. A single addition used to shift the whole canvas.
- The inspector, toasts, the search field, the kinship banner, and switching between the
  tree, fan, and map views now animate in and out instead of appearing and vanishing.
- Motion is defined in one place, and every animation honours the system Reduce Motion
  setting.
- English now uses given-name-first presentation, surname-first sorting, optional
  patronymics, native examples, unambiguous `5 Mar 1978` dates, and locale-aware counted
  nouns throughout the interface and PDFs.
- Kinship is computed as language-neutral descriptors and formatted explicitly in
  Russian or English, including neutral-sex lineage and first through fourth cousins
  one, two, or three generations removed in either direction.
- Place search, labels, ID lookup, and coordinate resolution now share one bilingual
  index. Ambiguous bare names no longer receive an arbitrary pin.

### Fixed

- The toolbar zoom buttons no longer pull the tree toward the top-left corner. They hold
  the viewport centre, matching ⌘+ and ⌘−.
- The inspector panel slides in. Its animation was declared but never ran.

### Removed

- The legacy `places.tsv` and `geonames_ussr.tsv` snapshots, superseded by the single
  versioned bilingual index.

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

[Unreleased]: https://github.com/samoilev/swarm/compare/v3.2.1...HEAD
[3.2.1]: https://github.com/samoilev/swarm/compare/v3.2.0...v3.2.1
[3.2.0]: https://github.com/samoilev/swarm/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/samoilev/swarm/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/samoilev/swarm/compare/v2.3.0...v3.0.0
[2.3.0]: https://github.com/samoilev/swarm/compare/v2.2.1...v2.3.0
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
