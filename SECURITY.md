# Security policy

## Supported versions

The latest commit on `main` is the only supported version. There are no published
binaries and no backported fixes to older tags.

## Threat model

Swarm is a local-only desktop app. It has no accounts, no server, no sync, no
analytics, and no AI services. It sends no genealogy data anywhere. Place lookup runs
entirely against bundled data files, so it makes no network requests. The one optional
network path is Apple Maps: with the default `appleMaps` provider, MapKit renders tiles
and Apple may receive the viewed map region. The `offlineVector` provider in Settings
removes even that.

The app is not run in the macOS App Sandbox, so it can read files the user selects
anywhere on disk.

That leaves file parsing as the meaningful attack surface. The most valuable reports
concern:

- **GEDCOM parsing** — a crafted `.ged` file that causes a crash, memory exhaustion,
  infinite loop, or a write outside the tree's own folder.
- **Path handling** — tree, media or attachment names that escape
  `~/Library/Application Support/Swarm/`, including via the legacy-storage migration.
- **Bundled data parsing** — malformed TSV or GeoJSON that destabilizes the app.
- **Data loss** — any path where import, merge, migration or the history/trash
  mechanism destroys a tree without a recoverable copy.

## Reporting a vulnerability

Report privately through GitHub's
[private vulnerability reporting](https://docs.github.com/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository — use **Security ▸ Report a vulnerability**. Please do not open a
public issue for a security problem.

Include what you did, what happened, and what you expected. If a file triggers the
problem, attach a **synthetic** one — never a real family GEDCOM.

This is a single-maintainer hobby project, so expect a first response in days rather
than hours. There is no bug bounty.
