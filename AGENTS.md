# AGENTS.md

Guidance for AI coding agents working in this repository. (Human contributors:
see [CONTRIBUTING.md](CONTRIBUTING.md).)

## What this is

`jfrog-secret-rotator-gcp` is a python gcp cloud function and setup m,anual instructions and terraform setup whose purpose is to
be a working example of a gcp cloud function service that handles a JFrog short lived access token rotation inside a GCP secret manager secret. 
The value is the ability to integrate the rotating secret to be used by a GAR repository that is configured as a proxy into JFrog repository.

## Layout

- `secret-rotator/main.py` - the function that perform the jfrog oidc token exchnage and secret rotation.
- `docs/manual-setup.md` - manual setup instructions. 
- `docs/terraform-setup.md` - terraform setup instructions.
- `terraform-example` -  terraform files for a terraform setup of the rotation components and secret
- `README.md` - canonical entrypoint: disclaimer, what's applied here, and the apply-on-fork settings.

## Conventions (must follow)

- **Copyright header:** every new `*.py` / `*.sh` file starts with `# (c) JFrog Ltd. (<year>)` (e.g. `# (c) JFrog Ltd. (2026)`).
- **Style:** black + isort + ruff at line-length 120 for code, markdownlint for docs; `make check` must pass.
- **ASCII-only prose:** use ASCII hyphens (`-`), never the Unicode em-dash (U+2014) or en-dash (U+2013), in docs and comments.
- **No secrets** in any per-PR workflow; credentialed jobs are
  `pull_request_target` + `safe to test` gated, SHA-pinned.
- **Zero runtime dependencies** by default. If you add one, it must be in an
  Acceptable license bucket (the JFrog Xray SBOM is authoritative) and you must
  add a matching entry to `NOTICE`.
- **Durable docs:** do not assert exact counts ("N tests", "N agents") that
  drift; link the source of truth or use a CLI command instead.
- **Release model:** tag-driven only. Never add auto-publish-on-merge.

