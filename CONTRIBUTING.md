# Contributing to Swarm

Thanks for helping. Swarm has one maintainer, so small, focused pull requests get
reviewed fastest.

## Never use real family data

Development builds must not open your own library. Always launch with a throwaway
folder:

```sh
swift run Swarm --storage-folder /tmp/swarm-dev
```

Do the same for anything that imports, merges or exports. Bug reports and test fixtures
use the public-figure trees in [Examples/](Examples/) or synthetic files, and never a
real family GEDCOM.

## Build and test

```sh
swift build
./Scripts/run-tests.sh
swiftformat --lint .
```

- `Scripts/run-tests.sh` wraps `swift test` and adds the framework paths that a
  Command Line Tools-only install needs. With full Xcode, plain `swift test` also works.
- SwiftFormat must be the version CI pins (`SWIFTFORMAT_VERSION` in
  [.github/workflows/ci.yml](.github/workflows/ci.yml)). Check `swiftformat --version`
  first: `.swiftformat` names rules that other versions reject or apply differently.
- UI tests live in `UITests/` and need full Xcode. Open `SwarmUI.xcworkspace` and run the
  `Swarm-UI` scheme.

## What CI checks

A pull request has to pass all of these:

- The build and tests, with compiler warnings treated as errors.
- SwiftFormat at the pinned version.
- No `Dictionary(uniqueKeysWithValues:)` in `Swarm/`. It crashes on a repeated key, and
  the keys usually come from files other programs wrote. Use
  `Dictionary(_:uniquingKeysWith:)` and decide which entry wins.
- macOS 26 APIs only inside `Swarm/App/Theme/SepiaGlass.swift`, whose availability
  checks name 26.0 and nothing else.
- Size caps on four oversized files: `TreeStore.swift`, `MainWorkspace.swift`,
  `EditPersonView.swift` and `TreeCanvasView.swift`. Put new behaviour in a new type. If
  your change makes one of them shorter, lower its cap in `ci.yml` in the same commit.

## Tests

- New behaviour in `Swarm/Core` gets a test in `Tests/SwarmCoreTests/`.
- Every bug fix gets a regression test that fails without the fix. Use
  `DefectRegressionTests.swift` unless a suite named for the area fits better (layout,
  merge, privacy, place index, GEDCOM robustness).
- Test behaviour, not the private shape of the code.
- To measure performance, run the opt-in benchmark before and after your change:

  ```sh
  SWARM_PERF=1 ./Scripts/run-tests.sh --filter LargeTreePerformanceTests
  ```

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/): `fix(gedcom): …`,
`feat(export): …`. Keep diffs small and leave unrelated formatting alone.

## Security

Report vulnerabilities privately, as described in [SECURITY.md](SECURITY.md), not in a
public issue.
