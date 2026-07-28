# Product

## Users

Russian-speaking people building and preserving their family history — from one
person digitizing a grandparent's notes to someone maintaining a tree across many
generations. They work at home on their own Mac, often from old photographs,
documents, and memory, and they care about privacy: the family record itself never
leaves the Mac, and the map can be switched to a fully offline one.

The job to be done: record relatives accurately (with correct Russian kinship
terms), see how everyone connects (tree diagram, ancestor fan chart, map of
places), attach the photos and documents that make a person real, and move the
tree in and out of other genealogy tools without losing anything via GEDCOM.

## Product Purpose

A native macOS app to build, validate, recover, visualize, merge, and export family
trees, with GEDCOM 5.5.1 as the source of truth and offline-first local storage.

Success means a trustworthy, lasting home for family history: correct Russian kinship
naming (direct lineage, full and half siblings, removed cousins, and in-laws), clear
tree, fan-chart, and map views, lossless GEDCOM interop with Ancestry, Gramps, and
MyHeritage, and durable local storage. Identity lives inside the file (`_TREEID`), so
trees survive being renamed or moved.

## Brand Personality

Warm, archival, trustworthy. The voice is respectful, unhurried, and precise —
the feeling of opening a restored family album, not a software product. Warmth is
carried by material (paper, sepia, serif type) and care for the record, never by
decorative nostalgia or period kitsch. Three words: **warm, archival, trustworthy.**

## Anti-references

- **Clinical SaaS dashboard** — generic gray admin chrome, dense data tables, a
  tool with no soul. This is a family album, not an analytics panel.
- **Cluttered legacy genealogy sites** — the Ancestry / MyHeritage web-2.0 density:
  busy chrome, competing panels, ad-shaped surfaces. Calm beats dense.
- **Cold corporate minimalism** — stark white, hyper-flat, texture-free. Warmth and
  material are the point; do not sand them off in the name of "clean".

## Design Principles

1. **The record is sacred.** GEDCOM is the source of truth; the UI serves the data
   faithfully and never silently distorts or loses it. Interop and durability are
   features, not afterthoughts.
2. **Heirloom, not nostalgia.** Warmth is earned through material and typography,
   not costume. Sepia and serif because they fit the subject — never as a theme
   skin pasted over a generic app.
3. **Kinship is the point.** Correct Russian relationship naming and lineage clarity
   are first-class. The hard, distinctive work (свёкор/тесть, деверь/шурин, removed
   cousins) is the product, not a nice-to-have.
4. **Quiet confidence.** Calm, unhurried surfaces; the tool recedes so the family
   comes forward. Resist dashboard busy-ness and competing emphasis.
5. **The record stays home.** Editing, search, place lookup, validation and storage are
   offline. The map defaults to Apple Maps, which sends only what its network map service
   requires for the viewed region — never intentionally the genealogy record or
   annotations — and Settings offers a fully offline vector map for anyone who wants no
   network at all.

## Accessibility & Inclusion

- **Commitment: WCAG AA contrast** across the sepia palette. The warm near-white
  backgrounds (`paper`, `cardBg`, `panelBg`) paired with muted inks (`inkSoft`,
  `line`) are the real risk; hold body text to ≥4.5:1 and large/UI text to ≥3:1.
- **Bilingual UI (Russian and English).** Russian remains the default and source
  language. Both interfaces must stay idiomatic, including kinship terminology,
  generated labels, accessibility text, error states, and exported presentation copy.
- **Sex is not shown through color alone.** Tree cards pair their tint with a text
  glyph, and VoiceOver descriptions include sex when known.
