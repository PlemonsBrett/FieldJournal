# Contributing to Field Journal

Field Journal is a small, solo-maintained WoW Forever beta addon. Contributions are welcome — bug fixes, `good first issue`s, and art (see the banner in [README.md](README.md)) most of all.

## Before you start

- Check the [open issues](https://github.com/PlemonsBrett/FieldJournal/issues) and [milestones](https://github.com/PlemonsBrett/FieldJournal/milestones) for what's already planned. Issues labeled [`good first issue`](https://github.com/PlemonsBrett/FieldJournal/labels/good%20first%20issue) are small and self-contained.
- For anything larger than a small fix, open an issue first to talk through the approach before writing code.

## Development setup

The addon targets Lua 5.1 (WoW's runtime). The test suite is a hand-rolled Lua 5.1 test runner with no external dependencies.

```sh
lua5.1 tests/run_tests.lua
```

Vendored libraries under `Libs/` (AceDB-3.0, etc.) are never hand-edited except for the one documented, clearly-commented exception noted in `CHANGELOG.md` for a load-time crash fix on this beta client — treat vendored code as read-only.

The codebase is split into a namespaced module layout: `Core/` (bootstrap, database, migrations, slash commands), `Data/` (quest log, diary, crafting, bestiary), `UI/` (window, widgets, note editor). Follow that split for new code rather than adding to a monolith.

## Commit messages: Conventional Commits

Every commit message must follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[(scope)][!]: <description>
```

Allowed types: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`, `ci`, `chore`, `style`. Merge and revert commits (Git-generated subjects) are exempt.

This isn't just style — the release pipeline runs [git-cliff](https://git-cliff.org/) over these prefixes (`cliff.toml`) to build each release's changelog section automatically, grouped by type. A commit with the wrong prefix either lands in the wrong section or gets silently dropped.

A local `commit-msg` hook enforces this on your machine. Install it once per clone:

```sh
git config core.hooksPath .githooks
```

## Pull requests

`main` is protected: changes land through a pull request with at least one approving review, and force-pushes/deletion of `main` are blocked. Before opening a PR:

1. Run the test suite (`lua5.1 tests/run_tests.lua`) — CI runs it again on the PR, but catching failures locally saves a round trip.
2. Keep commits Conventional-Commits-formatted (see above).
3. Describe what changed and why in the PR description; link the issue it addresses if there is one.

CI also dry-runs the [BigWigs packager](https://github.com/BigWigsMods/packager) on every PR so a packaging mistake fails before it can reach a release.

## Release process

Contributors don't need to do anything to cut a release — merging to `main` triggers it automatically. See [README.md](README.md#continuous-integration-and-wago-releases) for the full pipeline (draft release → manual publish → Wago.io upload).
