# Product

## Register

product

## Users

Russian-speaking people building and preserving their family history — from one
person digitizing a grandparent's notes to someone maintaining a tree across many
generations. They work at home on their own Mac, often from old photographs,
documents, and memory, and they care about privacy: the app is fully offline and
nothing about their family ever leaves the device.

The job to be done: record relatives accurately (with correct Russian kinship
terms), see how everyone connects (tree diagram, ancestor fan chart, map of
places), attach the photos and documents that make a person real, and move the
tree in and out of other genealogy tools without losing anything via GEDCOM.

## Product Purpose

A native macOS app to build, visualize, and export family trees, with GEDCOM
5.5.1 as the source of truth and everything running fully offline.

Success looks like a trustworthy, lasting home for family history: Russian kinship
naming that's actually correct (direct lineage, full/half siblings, cousins incl.
removed, in-laws), clean tree / fan-chart / map visualizations, lossless GEDCOM
interop with Ancestry, Gramps, and MyHeritage, and durable local storage where
identity lives inside the file (`_TREEID`) so trees survive being renamed or moved.

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
5. **Private by default.** The app is a vault: fully offline, nothing leaves the
   device. The design should reinforce that sense of safekeeping, not undercut it.

## Accessibility & Inclusion

- **Commitment: WCAG AA contrast** across the sepia palette. The warm near-white
  backgrounds (`paper`, `cardBg`, `panelBg`) paired with muted inks (`inkSoft`,
  `line`) are the real risk; hold body text to ≥4.5:1 and large/UI text to ≥3:1.
- **Russian-language UI.** Interface text and kinship terminology must stay
  idiomatic; copy is written in Russian first, not translated mechanically.
- **Known consideration (not yet a commitment):** the male/female card tints
  (`cardBgMale` / `cardBgFemale`, `cardLineMale` / `cardLineFemale`) currently
  signal sex through color alone, which color-blind users may not perceive. Worth a
  non-color cue (label, icon, or shape) if/when this becomes a priority.
