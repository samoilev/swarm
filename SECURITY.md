# Security policy

Only the latest release and the latest commit on `main` are supported. Older tags get no
backported fixes.

## Threat model

Swarm is a local-only desktop app: no accounts, no server, no sync, no analytics, no AI.
It sends no genealogy data anywhere, and place lookup runs against bundled data files.
The one optional network path is Apple Maps. With the default `appleMaps` provider,
MapKit renders tiles and Apple may receive the viewed region. The `offlineVector`
provider removes even that.

The app does not run in the macOS App Sandbox, so it can read files the user selects
anywhere on disk. That makes file parsing the main risk. The reports worth most:

- **GEDCOM parsing.** A crafted `.ged` file that crashes the app, exhausts memory, loops
  forever, or writes outside the tree's own folder.
- **Path handling.** Tree, media or attachment names that escape
  `~/Library/Application Support/Swarm/`, including through the legacy-storage migration.
- **Bundled data parsing.** Malformed TSV or GeoJSON that crashes or hangs the app.
- **Data loss.** Any path where import, merge, migration, or the history and trash
  mechanism destroys a tree without leaving a recoverable copy.

## Reporting

Report privately through **Security ▸ Report a vulnerability** on this repository, not as
a public issue. Include what you did, what happened, and what you expected. If a file
triggers the problem, attach a synthetic one. Never a real family GEDCOM.

This is a single-maintainer project, so expect a first response in days rather than hours.
There is no bug bounty.
