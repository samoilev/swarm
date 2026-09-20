# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions 1.0.0 through 2.1.0 were released under the project's earlier Russian name and
had Russian-only release notes. Those notes are translated here, so this file is the
single English record of what changed and when.

## [Unreleased]

## [3.5.6] — 2026-09-20

### Fixed

- Saving an imported tree no longer moves files referenced only by family-level or
  foreign GEDCOM records into Swarm's recovery Trash. This affected the two family
  attachments in the bundled Curie example: the GEDCOM reference survived, but an
  archive exported after editing the tree omitted the files. Saving now derives the
  complete active-file set from the final lossless GEDCOM and recovers files misplaced
  by affected versions when they are still within the 30-day recovery window.

### Changed

- Releases now include a ready-to-import Curie family ZIP, with image credits and
  licenses, so Swarm can be tried without supplying personal family data.
- Installation instructions explain the unsigned first launch more clearly, and the
  README states precisely when Apple Maps may use a network connection.

## [3.5.5] — 2026-09-20

**Liquid Glass is back on macOS 26 and later.** It was absent from 3.5.3 and 3.5.4
entirely: every availability guard in the glass shim read `#available(macOS 99.0, *)`,
left behind by a script used to preview the macOS 15 fallback while the platform-support
work was in progress. 99 is never true, so every machine ran the fallback rendering — no
glass effects, no glass buttons, no shared-background control — whatever version of macOS
it was on.

### Fixed

- All six remaining guards in the shim are back to `macOS 26.0`. The 3.5.4 fix had
  restored two of them, which is why the dark-appearance pill behind the wordmark went
  away while the glass itself did not come back.
- CI now fails on any guard in that file that is not `macOS 26.0`. Nothing else could have
  caught this: the app builds, the tests pass, the formatter is satisfied, and the lint
  that keeps 26-only symbols contained excludes this very file by design.

### Note on the 3.5.4 entry

The cause given for the toolbar background in 3.5.4 — a modifier reaching a generic `Self`
through a protocol extension — was wrong, and so was the comment that shipped with it. The
test that appeared to confirm it differed from the failing code only in spelling `26.0`
rather than `99.0`. The comment is corrected in the source. The closure-based shim
introduced there stays, because it is sound on its own terms, not because the previous
form was broken.

## [3.5.4] — 2026-09-19

### Fixed

- Toolbar items no longer carry the grouped background they ask to hide. The shim added
  with the macOS 15 support work was an extension on the `ToolbarContent` protocol taking
  an already-built item as `Self`, and SwiftUI declares that modifier on both
  `ToolbarContent` and `CustomizableToolbarContent`, so through a generic `Self` it never
  attached. The items now come in as a closure and are built inside the availability
  branch, so the modifier applies to a concrete toolbar item. Invisible against the sepia
  toolbar in the light appearance, which is why the screenshots and pixel-diffs taken
  while developing it all passed; in the dark appearance it is a pale pill behind the
  wordmark and the workspace title, which is how 3.5.3 shipped.

## [3.5.3] — 2026-09-19

Swarm runs on **macOS 15 or later**, on Intel as well as Apple silicon. The floor was
macOS 26 and the build was arm64-only, which locked out every Intel Mac and every machine
not yet updated. The DMG ships universal now.

Liquid Glass is unaffected on macOS 26 and later. The system picks the new look from the
SDK a binary was linked against, not from its deployment target — separate fields in the
load command — which was verified by pixel-diffing the library, the workspace toolbar and
the add-relative sheet against 3.5.2 on macOS 27: zero differing pixels.

### Changed

- All 117 macOS 26 call sites moved behind shims in one file, the only place allowed to
  name a 26-only symbol, with a lint step on the free Ubuntu CI job keeping them there.
  Below 26 the fallbacks reuse the app's own button style rather than stock AppKit
  controls, which would read as a second design system beside the sepia ones in the same
  rows.
- The DMG script stops hardcoding the products path, which SwiftPM had already moved, and
  pins the linked SDK and minimum OS explicitly. Without that pin the current default
  build system writes the SDK field as the deployment target, which would silently drop
  every macOS 26 user into the old look with nothing in the pipeline noticing. The script
  now fails on a non-universal binary or a linked SDK below 26.0, and publishing is gated
  on smoke-testing the built DMG on both an Intel and an Apple-silicon macOS 15 runner.
- The README drops its universal-binary badge; the badge row already carries the macOS
  floor, and the architecture is covered in the Install section in prose.

### Fixed

- The trailing toolbar cluster is back below macOS 26. The flexible spacer resolved to
  nothing there, on the reasoning that a primary-action item right-aligns by itself and
  that a spacer in a toolbar item collapses. Neither holds: the library's search, sort,
  import and new-tree controls all packed against the wordmark on the leading edge.
  Onboarding's toolbar had the same spacer and the same problem.
- Circular fallback buttons take the toolbar's control size below macOS 26. The glass
  button style supplies control metrics on 26 and later, so the home and share buttons
  rendered full size there despite framing no label, while below 26 both collapsed to the
  size of their 12pt glyph. Circles now take a minimum 30×30 square — a minimum rather
  than a fixed frame, so the 34pt panel close buttons keep their own size.
- The duplicate-suggestion row had been rendering a blank icon: the symbol it asked for
  does not exist on any macOS.

## [3.5.2] — 2026-09-18

### Fixed

- Interface copy reads as written rather than translated, in both languages. The pass
  covers the workspace and its toolbars, the library, onboarding, recovery, the merge and
  version-history sheets, validator messages and the strings the persistence layer
  surfaces — the places where a machine-like phrasing had survived. The map privacy text
  is shorter, and formatting that the layout depends on is preserved, so nothing that had
  been fitted to a row grew out of it.

## [3.5.1] — 2026-09-17

### Fixed

- The library toolbar draws to one control height. It was built two ways at once: the
  filter field and the sort pill were glass with an explicit frame, while import, New Tree
  and the overflow were system glass buttons sized from their own label and padding. They
  came out 34 and 37 points at the default step, and only the first pair grew with the
  interface setting, so the row disagreed with itself further at every step up. All five
  now share the scaled 34pt the workspace toolbar already uses, so the two windows draw
  the same row, and the wordmark scales its rule, gaps and dot along with its type instead
  of holding fixed points while the words grew.
- The sex labels no longer wrap inside their buttons. The maiden name field shares the row
  and took every point it was offered, squeezing the pair until “Мужской” broke across two
  lines — Russian shows it first, its words being longer than the English. The labels hold
  their own width now and the field takes what is left, including the “Не указан” hint,
  which started wrapping once the buttons stopped.
- Settings copy reads straight in both languages. The map footer said “offline” twice, the
  provider summary and the privacy line sitting one sentence apart; the summary now names
  what the provider needs and the privacy line where the data stays, matching how the
  English pair already read. “The visible map region” is viewport-speak, so both languages
  now say which part of the map the reader is looking at. The size dialog called the
  person card a “form” in English where every other string calls it a profile, the
  language row drops to “Язык”/“Language” rather than spending “Interface” on two adjacent
  rows, and the map section header goes singular.
- The Help section on maps matches that copy, having kept the wording Settings was cleaned
  up out of — “локально” for what Settings calls this Mac, and the viewport phrasing for
  what Apple actually sees. A GEDCOM is also a file, not a place to keep things in.

## [3.5.0] — 2026-09-17

### Added

- The interface scales from a setting. Five steps — 85, 92, 100, 115 and 130% — sit in the
  ⌘, window beside the language, applied live. Every glyph used to be a fixed point size,
  so a reader on a 5K display had no way to enlarge 10–13pt serif chrome short of the
  system-wide Zoom. The canvas, the fan chart's ring labels and the map's place labels
  keep their own sizes, because their geometry is fixed and enlarged text would overflow a
  card; the tree keeps its own zoom. Exported PDFs are untouched by construction — a
  document should not change size because the reader's screen preference did.
- The save history has its own panel. The 50-deep revision list has shipped since the
  folder layout landed, but it was buried in Recovery, a library-only rescue sheet that
  also holds deleted files and archived trees, with no route to it at all from inside an
  open tree. Предыдущие версии now opens from the save clock, the wrench menu and the
  library card menu. Rows carry people and family counts read off each revision, plus the
  difference from the tree as it stands, and the live tree heads the list, because history
  holds the state *before* each save. Restoring asks first and says the replaced state
  becomes the newest version, which it does — a restore is itself a save.
- A person's photographs can be browsed from the card. The header gains a scrolling strip
  of miniatures — the portrait first, then every image attachment — and the full-size
  viewer walks the whole set with arrows, wrapping at either end. Image attachments were
  previously reachable only as 40pt rows in Файлы, each one a handoff to Finder. Tiles
  share a height and keep their own width, clamped to 2:1, because family photos come in
  whatever shape the scanner left them.
- The photo viewer takes the shape of what it holds. A landscape scan — a page of a
  casualty list, a group photograph — used to be drawn inside a portrait-shaped card, so
  the part worth reading got a third of the window. The arrows moved out of the card and
  onto the dimmer beside it, off the top of a face or a line of text.
- A focus scope on the map: one person, their branch, or everyone. In a 68-person tree a
  selected person's lineage is most of the map, so there was no way to look at one path on
  its own. Person scope keeps the selected person at full strength and fades everyone else
  to 20% — nothing is removed, so context and click targets stay — and fitting the camera
  then frames just that person's places.
- Everyone off the selected branch fades on the map. The selected person keeps a thicker
  path, their branch stays at full strength, and the rest drop to 20% but stay clickable.
  The emphasis rules live in the core module so the MapKit and offline providers share one
  testable definition.
- The inspector's mini map opens the full map on that person, where their branch stays lit
  and everyone else fades. The thumbnail itself still passes hit testing through — MapKit
  eats scroll-wheel events and would break a scroll already in progress — so the click
  target is a button around it.
- The map reports a failed load and offers a retry. A missing place index, tiles that
  never arrive and unreadable bundled vectors all failed silently before, and none could
  be retried without relaunching. A spinner appears once a load passes five seconds, then
  a card naming the failed source with Retry and, on Apple Maps, a switch to the
  network-free offline renderer.
- A scale bar and a zoom-aware graticule on the offline map, which offered no way to judge
  distance, and whose fixed 30/15-degree grid drew nothing once the viewport was narrower
  than one cell. The tree's own places are labelled too; gazetteer cities were named while
  the family's villages stayed bare dots.
- Export gains a File-menu item with ⌘E and a row in the compact overflow. It was
  reachable only through an icon-only toolbar button, which does not survive the system
  overflow.

### Changed

- The person card puts the name on its own line, under a round medallion. The name used to
  share a row with the portrait, leaving it panel width minus 125pt — 120pt at the narrow
  end, where a surname in 20pt serif does not fit, so it broke wherever the layout engine
  chose or ran off the edge. The medallion's window is anchored to the top of the frame, so
  a face lands in the circle rather than a chin and a chest, and a person with no
  photograph gets initials, which read at that size where the silhouette was a blot.
- The medallion grew from 84 to 104pt and the pinned bar's name from two steps below
  everything else to 15 over 13, with the header's pair two steps down instead of four.
  Section headings take a new 13pt step, so the card no longer reads as one flat list of
  11pt tracked caps.
- The card's edit and close controls are pinned over the scroller, outside the top fade.
  On a tall record both were buried, so closing or editing meant scrolling back to the top
  first. Paper fades in behind them once the record reaches it, and the name follows 24pt
  later, by which time the big one is gone — the card never shows the same name twice.
- Settings is laid out as a grouped form. Nine radio pills in three rows gave every setting
  the same weight and squeezed the five scale steps until only their percentages fit. Rows
  name the setting on the left and carry its control on the right, the scale rides one
  slider, and the map provider's summary joins the privacy line as a footnote.
- The export panel's three rows are one shape. They were 60/36/60pt tall, capsules
  carrying two lines of text, and a disabled row that gave no reason for being dead. Rows
  are cards now, each with a description; the selection row stays a disabled button with
  the same geometry as its neighbours and shows how many people are selected. The panel's
  width goes through the shared scaler and its height is the content's own, so a longer
  translation or a larger interface step grows the sheet instead of clipping inside it. A
  footer line says what will land on disk, read from metadata rather than the media folder.
- Interface copy simplified in both languages, with the English and Russian tables brought
  into line with each other. Kinship labels read as sentences across generations and
  uncertainty — “Great-great-grandfather”, “Ancestor, 5 generations back”, “Father
  (uncertain)” — and the family-editing screens lost the phrasing that did not survive
  translation.
- Scroll-wheel zoom on the canvas takes the same 0.6× cut the pinch constants took, and its
  per-event clamp is reciprocal, so one notch in and one notch out return to the same
  scale; the old pair did not. Pinch zoom crossed the whole scale range in one gesture:
  tree damping drops from 0.5 to 0.3, and the fan chart and offline map, undamped
  entirely, now match.
- The minimap legend moved to the top-left, out from under pins near the lower edge, and
  the offline minimap gained the same legend, which it did not have.
- Documentation corrected where it had drifted: bug-report placeholders asked for macOS
  15.2 and Swarm 2.1.0 on an app that requires macOS 26; release notes told users to
  right-click and Open, a bypass that no longer works for an unsigned app on current
  macOS; the Swift 6 badge implied Swift 6 language mode where the manifest is
  tools-version 5.9; and map providers were named by raw value, so neither string was
  findable in the Settings menu being described.

### Fixed

- Notes no longer lose text on save. The `.ged` file is the save format, not just an
  export, so a lossy round trip is data loss on an ordinary save-and-reopen, and there were
  three ways it happened invisibly: a note line after the first was cut at about 200 bytes,
  because the continuation was split into a level the walker ignored; a pasted line or
  paragraph separator was written inline, and since the readers split on those characters
  the record tore in half, making an app-created tree unreadable on next launch; and
  leading and trailing whitespace, which in a free-form note is content, was trimmed by the
  tokenizer. Notes now warn past 100k characters instead of being limited, and the counter
  never truncates, blocks or rejects a paste.
- The offline map is usable at real zoom. Labels were queried from inside the draw closure,
  so every frame of every pan walked a 5-degree gazetteer bucket — the densest hold 27,000
  rows and sit over St Petersburg, Moscow and Kyiv — and the query now runs on a quantised
  viewport key, roughly once per half-screen of movement. Coastlines and borders are culled
  to the viewport instead of re-projected whole each frame, panning tracks the pointer
  instead of moving on mouse-up, the wheel zooms anchored under the cursor, and zoom no
  longer goes dead after about five clicks with 8× of range left.
- The library shows a tree's real modification date. GEDCOM carries no modification
  timestamp, so every reload rebuilt each tree with the current date: every card read
  “изменено только что” and the recency order collapsed into load order. The header now
  carries created and updated stamps, written below the imported-header passthrough so a
  save cannot freeze them, and files without them fall back to the file's own dates.
- Seven defects found in the post-3.4.0 end-to-end run, each reproduced with a named root
  cause: changing the interface size discarded unsaved drafts; the missing-photo message
  truncated to an ellipsis because the photo aspect was applied to the whole builder; Zoom
  In zoomed out above 200%, the keyboard clamping to 2.0 while the toolbar ran to 8; Try
  Again could not recover, because a failed parse was cached past every retry and a missed
  bundle lookup is memoised for the life of the process; Restore reported existing media as
  missing, a revision living two levels above the media it references; a failed restore
  advanced the displayed save time, stamping “now” on a rollback; and Export was reachable
  only through a toolbar button that the system overflow drops.
- Sex read as a clipped “Муж”/“Жен” on the person card. The literals bypassed the string
  table, where “Муж” is already claimed as Husband.
- The notes caret sat to the right of the placeholder it replaced — different insets on the
  two, neither accounting for the container inset the text view adds. The relatives heading
  read “Родственные”, an adjective with no noun.

## [3.4.0] — 2026-08-29

### Added

- Chronology is checked across records, not only within one person. Burial before death,
  a marriage before a partner's birth, a child born before a parent, and a child born
  more than a year after a parent died are all reported in the Review workspace. They are
  warnings rather than errors: each has a rare but real explanation, and a research file
  should not be blocked over one.
- Type, layout and elevation tokens in the theme. The palette and motion were already
  tokenized; the screens meanwhile asked for 30 distinct font sizes, 29 padding values off
  any grid, 13 corner radii for four roles, and around 15 shadow recipes in two
  conventions. The new tokens distil what the screens already use most, so adopting one is
  not a restyle. Type is deliberately fixed-point: the canvas, fan chart and PDF share
  hand-tuned metrics, so Dynamic Type is declined — now stated in the theme rather than
  claimed by a stale comment.
- ⌘↩ to save and Esc to cancel in the person editor, which had neither.

### Changed

- Structured events are the single source of truth on a person and a union. Every event
  was kept twice — flat fields such as `birthDate` and `marriageDate` alongside
  `events[]` — held together by four hand-maintained sync directions and a re-entrancy
  flag, which was also the vector for the mini-map data-corruption bug. The flat fields
  are computed accessors now and the sync machinery is gone. Getters reproduce the old
  strings exactly, so every consumer reads what it always did.
- Saving no longer re-parses the whole archive. A 2000-person tree spent 0.53s of a 0.77s
  save re-reading the previous GEDCOM on the main thread, purely to build a name map used
  only when an attachment has to be trashed. The map is resolved lazily now, at most once:
  the same save takes 0.24s.
- The merge suggestion scan buckets candidates by normalized name and birth year and
  builds each index once, instead of comparing every incoming person against every local
  one. A 2000×2000 preview takes 0.4s, where it previously rebuilt two whole-tree indexes
  on each of four million pairs.
- The import preview reports what the validator found. It read only parse diagnostics, so
  a file whose Review page listed nine issues — a self-parent link, an ancestry cycle and
  six chronology problems — was presented as “0 errors, 0 warnings, проверка пройдена” and
  imported without acknowledgement. The counts, the list and the “check passed” line are
  honest now, and importing requires ticking an acknowledgement. The findings do not
  refuse the file: parse and structure failures still make one unimportable, but a
  readable file with damaged relationships stays importable and is fixed in Review.
- `TreeStore` is pinned to the main actor. Its async methods have no suspension points, so
  callers hopped off the main actor and mutated observed models while SwiftUI was reading
  them. Strict concurrency checking is on for the core module to keep those paths from
  returning, and the GEDCOM preview parse moved off the file-importer callback, so
  importing a large archive no longer freezes the interface.
- The undo controller lives in the core module, caps its stacks at 50 snapshots, and
  reports encode and decode failures instead of swallowing them — a failed undo used to
  pop the entry and lose it.
- The map legend moved to the top-left, off MapKit's attribution and legal link, which
  Apple's terms require to stay visible. The offline vector map's second, undeclared sepia
  palette became theme tokens, so the two palettes cannot drift apart, and letter tracking
  collapsed from eight values for one visual role to a single token.
- The stock bordered search fields became one component, and nine raw reds at four
  opacities became the theme's danger color, which was built for 6.23:1 on paper where
  system red sits near 3.4:1. The About window is localized and takes the locale and
  contrast modifiers the other scenes already had.
- Internal tidying with no behaviour change: the shared form-field and section components
  moved out of whichever screen happened to declare them first, the editor and export
  sheets reuse the panel header they had each hand-copied, and 118 call sites that already
  asked for exactly a token's font size now name the step instead of the number.
- The native UI suite runs again. It had not moved since 3.3.1 and failed all 14 cases
  before reaching an assertion; it now passes 13 with 1 skipped, and its assertions check
  outcomes — a restore is proved by the canvas showing the restored name — rather than
  status lines. Two of them described things that never existed, and the file-open journey
  is skipped with its reason recorded: Launch Services routes `.ged` to a registered
  application, never a test bundle.
- README rewritten.

### Fixed

- A person who is their own parent no longer crashes the app. A `FAM` listing the same
  individual as both partner and child reaches the canvas through an accepted import
  baseline, where routing asked for a connector between a person and themselves and
  tripped a precondition — a hard crash on opening the tree. Fixed at both sources rather
  than by loosening the invariant.
- The Review workspace marked imported problems as blocking while a save let them through,
  the opposite of the promise in its own hint line. Its validation context now defaults to
  the tree's accepted baseline, so no call site can forget it.
- Clearing a portrait kept the filename, so the exporter re-emitted the media record and
  the next load silently restored the deleted photo.
- Merging ran outside the undo controller, so ⌘Z after a merge restored and saved the
  pre-merge tree and discarded the merged data. Optimizing the root from the toolbar
  likewise mutated structure with no undo entry and no save.
- “Keep both” in a merge de-duplicates by content rather than by identity. These records
  carry a UUID, so the same birth arriving from two files never compared equal and the
  merged person kept two birth events.
- The person mini-map wrote geocoded coordinates back into the person from a passive
  preview, which landed on disk with the next unrelated save.
- Five rollback paths hand-copied field lists and two of them dropped fields, losing a
  person's links or a tree's import report on cancel. All routes go through one deep copy
  now, guarded by byte-equality completeness tests.
- Cancelling a sheet recorded a phantom undo entry: the encoder's hash-seeded key order
  made the “did anything change” comparison always true.
- The canvas thumbnailer read the cached full-size photo, pinning megabytes for every card
  drawn — exactly what downsampling exists to avoid — and its cache could collide between
  two portraits of equal byte count.
- Failures that were silently discarded now surface: archiving returned the source folder
  on failure and the library revealed it as success, and delete, save-warning, PDF and
  photo-import failures were all dropped. The recovery sheet could also be left
  permanently disabled by a guard that skipped its reset, and a toast timer cleared newer
  toasts posted within 2.5 seconds.
- The editor allowed clearing a person to nameless, which the add sheet already refused.
- Icon-only controls carry accessible names. The source row's edit, open-link and delete
  buttons had tooltips but no name, so VoiceOver announced “pencil”, “arrow up right” and
  “minus”. The two toolbar menus cannot be named this way — macOS builds a menu's control
  from its image and reads out the symbol's own description — so they keep their labels and
  help text and gain stable identifiers instead.

### Removed

- Dead code: written-but-never-read attachment delete tracking, a geocoding cache clear
  with no callers left, an unused PDF export entry point, an unused button style, and a
  smoke-test suite subsumed by the core tests.

## [3.3.1] — 2026-08-22

### Fixed

- Adding a sibling links the person into the existing parent union instead of a
  partner-less stub. Only the subject's own union was checked, so the new sibling landed
  in a stub that union deduplication promptly emptied: the card saved standalone, and
  every later attempt to relink it hit the same stub and was stripped again. Both sides
  are resolved now and joined to whichever union has real parents. A partner-less union
  is only a sibling group with unknown parents, so the whole group moves with the linked
  person; leaving the rest behind dropped their sibling links just as silently. Also
  fixes a single-parent target ending up as a child of two unions.

## [3.3.0] — 2026-08-20

### Added

- The person card lists a person's sources, above Файлы and Ссылки: title, the archival
  reference on one line, and the first two lines of the transcription, which is what says
  *what* a source proves rather than merely that one exists. A source with an address
  opens it in the browser. Person-level citations only, matching the editor.
- Web links on a person, as metadata-only siblings of attachments: no bytes on disk,
  stored as GEDCOM `1 WWW` + `2 TITL` so they survive a round trip and stay readable in
  other software. Only `http`, `https` and `mailto` ever open, so an imported file cannot
  make Swarm launch a local `file://` URL.

### Changed

- The person editor's evidence section is now a list of sources you can read back, edit
  and delete, replacing a form that could only ever add. Nothing in the app had ever
  listed a citation, so an entry could not be corrected or removed and the only proof one
  existed was exporting GEDCOM. Each entry is one source plus one citation, and the
  archival fields are labelled the way a Russian archive reference reads: **Фонд**,
  **Опись**, **Дело**, **Лист**. The GEDCOM tags behind them (`PUBL`, `REPO`, `CALN`,
  `PAGE`) are unchanged, so files written by earlier versions still read back the same.
- The source form opens from “Добавить источник” and closes on Отмена or save, instead of
  sitting open under the list and making a section of mostly-empty fields the first thing
  in view. Editing from a row was invisible, so each row now carries a pencil beside its
  open-link and delete buttons.
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
- Stacked link rows are separated by a rule.

### Fixed

- Dragging the notes resize handle tracks the pointer. The handle sits on the edge it
  resizes, so a local-space translation cancelled itself out and the drag stalled. It
  measures in global space now, without the 10pt minimum distance that made the first
  frame jump, and the handle straddles the edge so it can be grabbed without landing
  inside the text view.
- Two places the sepia never reached in full screen: the window background behind the
  menu-bar strip stayed system white, and the tree title held a fixed 260pt while the bar
  had room to spare.
- A deceased person with no death date no longer shows an age counted to today. A lifespan
  is computed only when a death date exists; otherwise it renders `1900–?`.

### Removed

- The shared source library, the “Для факта” target picker and the reliability field.
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

[Unreleased]: https://github.com/samoilev/swarm/compare/v3.5.6...HEAD
[3.5.6]: https://github.com/samoilev/swarm/compare/v3.5.5...v3.5.6
[3.5.5]: https://github.com/samoilev/swarm/compare/v3.5.4...v3.5.5
[3.5.4]: https://github.com/samoilev/swarm/compare/v3.5.3...v3.5.4
[3.5.3]: https://github.com/samoilev/swarm/compare/v3.5.2...v3.5.3
[3.5.2]: https://github.com/samoilev/swarm/compare/v3.5.1...v3.5.2
[3.5.1]: https://github.com/samoilev/swarm/compare/v3.5.0...v3.5.1
[3.5.0]: https://github.com/samoilev/swarm/compare/v3.4.0...v3.5.0
[3.4.0]: https://github.com/samoilev/swarm/compare/v3.3.1...v3.4.0
[3.3.1]: https://github.com/samoilev/swarm/compare/v3.3.0...v3.3.1
[3.3.0]: https://github.com/samoilev/swarm/compare/v3.2.1...v3.3.0
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
