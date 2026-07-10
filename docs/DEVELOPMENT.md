# Development

Antrum is a local-first macOS app generated with XcodeGen.

## Setup

1. Install Xcode and Xcode Command Line Tools.
2. Install XcodeGen: `brew install xcodegen`.
3. Run `make doctor`.
4. Run `make test`.
5. Run `make run`.

## Commands

| Command | Purpose |
| --- | --- |
| `make generate` | Generate `Antrum.xcodeproj` from `project.yml`. |
| `make build` | Build an unsigned Debug app. |
| `make test` | Generate the project and run tests. |
| `make run` | Build and launch Antrum. |
| `make lint` | Check public-source policy and screen-capture constraints. |
| `make secret-scan` | Scan tracked text files for common secret patterns. |
| `make public-check` | Reject private artifacts and missing public-repository files. |
| `make doctor` | Print local tool and path diagnostics. |

`Antrum.xcodeproj` is generated from `project.yml`; edit `project.yml` first. The Swift package lockfile is tracked so contributors resolve the same FluidAudio version.

## Environment

| Name | Purpose |
| --- | --- |
| `ANTRUM_FEATURE_DICTATION` | Development override for dictation. `1`, `true`, `yes`, and `on` enable it; other values disable it. |
