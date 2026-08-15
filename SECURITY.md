# Security policy

Only the latest release and the latest commit on `main` are supported. Older tags get no
backported fixes.

## Threat model

Swarm is a local-only desktop app: no accounts, no server, no sync, no analytics, no AI.
It sends no genealogy data anywhere, and place lookup runs entirely against bundled data
files. The one optional network path is Apple Maps — with the default `appleMaps`
provider, MapKit renders tiles and Apple may receive the viewed region. The
`offlineVector` provider removes even that.

The app does not run in the macOS App Sandbox, so it can read files the user selects
anywhere on disk. That leaves file parsing as the meaningful attack surface. The most
valuable reports concern:

- **GEDCOM parsing** — a crafted `.ged` file that causes a crash, memory exhaustion,
  infinite loop, or a write outside the tree's own folder.
- **Path handling** — tree, media or attachment names that escape
  `~/Library/Application Support/Swarm/`, including via the legacy-storage migration.
- **Bundled data parsing** — malformed TSV or GeoJSON that destabilizes the app.
- **Data loss** — any path where import, merge, migration or the history and trash
  mechanism destroys a tree without a recoverable copy.

## Reporting

Report privately through **Security ▸ Report a vulnerability** on this repository, not as
a public issue. Include what you did, what happened, and what you expected. If a file
triggers the problem, attach a **synthetic** one — never a real family GEDCOM.

This is a single-maintainer project, so expect a first response in days rather than hours.
There is no bug bounty.
