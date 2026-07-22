# Contributing to jfrog-oss-hello

Thanks for your interest. This repository is a hello-world example of a
JFrog OSS-policy-compliant project; the same workflow applies whether you
fork it or contribute to it.

## Contributor License Agreement (CLA)

Before your first contribution can be merged you must sign the
[JFrog Contributor License Agreement](https://jfrog.com/cla/). This is a
one-time requirement per contributor; the CLAssistant bot will comment on your
first PR with the signing link, and the `cla` check gates the merge.

## Getting started

We use [uv](https://docs.astral.sh/uv/) for a reproducible, locked dev
environment. Pip works as a fallback.

```bash
uv sync                          # creates .venv, installs locked dev deps
uv run pre-commit install        # enables the lint/secret/header hooks on commit
make check                       # lint + tests - should pass before you start
```

Pip fallback:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
make check
```

## Development workflow

1. Branch from the latest `main`.
2. Make your change. New source files must start with `(c) JFrog Ltd. (YEAR)`.
3. `make check` (lint + tests) must pass.
4. Open a PR into `main` and apply one release-note label (`new feature` /
   `improvement` / `bug` / `breaking change` / `ignore for release`).

## Test tiers

| Tier | Command | Cost | Runs in CI |
|---|---|---|---|
| Unit (fast, offline, free) | `make test` / `pytest tests/` | free | yes, on every PR |
| Lint + hygiene | `make lint` (black, isort, ruff, markdownlint, gitleaks, bandit, copyright headers) | free | yes, on every PR |
| Wheel install smoke | `make verify-wheel` | free | yes, in the `build` job |

This example has no credentialed/integration tier. If you add one, gate it per
the convention below.

## What runs where

| Check | Local (`make check`) | CI on every PR | Frogbot (gated) |
|---|:---:|:---:|:---:|
| black / isort / ruff | ✅ | ✅ | - |
| markdownlint | ✅ | ✅ | - |
| gitleaks (secrets) | ✅ | ✅ | - |
| bandit (SAST) | ✅ | ✅ | - |
| copyright headers | ✅ | ✅ | - |
| unit tests (3.11-3.14) | local version | ✅ matrix | - |
| wheel build + smoke | - | ✅ | - |
| CLAssistant (CLA signed) | - | ✅ | - |
| Frogbot SCA + secrets | - | - | ✅ |

## Credentialed CI workflows

Public repos treat **every PR as untrusted**. The per-PR `test.yml` runs with
**no secrets** (`permissions: contents: read`). Anything credentialed follows
the four-rule convention (reference impl: `jfrog/jfrog-cli`):

1. Trigger on `pull_request_target` (in addition to `push`).
2. Gate every job behind the maintainer-applied `safe to test` label
   (or `github.event_name == 'push'`).
3. Check out the PR head SHA explicitly.
4. Pin every third-party action to a commit SHA, not a moving tag.

The `safe to test` label is auto-stripped after each run by
[`removeLabel.yml`](.github/workflows/removeLabel.yml), so each credentialed
run requires a fresh maintainer review of the diff.

## Releases

Releases are tag-driven (see [`release.yml`](.github/workflows/release.yml)):

- `vX.Y.Z-rcN` (pre-release) -> TestPyPI rehearsal.
- `vX.Y.Z` (clean) -> PyPI (reviewer-gated) + a GitHub Release with auto-notes.

Operational setup (Trusted Publisher registration, GitHub Environments, branch
protection) is summarized in [README.md](README.md) ("When you fork").

## License

By contributing, you agree your contributions are licensed under the
[Apache License 2.0](LICENSE).
