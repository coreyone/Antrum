# Antrum

Local-first meeting transcription for macOS. Record or import audio, process it on-device, repair speaker labels, then export clean Markdown.

## Status

Source-only project. No signed or notarized macOS binaries are published yet. Build locally from source.

## What it does

- Imports `.mp3`, `.wav`, `.m4a`, `.mp4`, and `.mov` files.
- Records microphone and meeting audio as separate local tracks on macOS 14.2 or later.
- Transcribes locally with FluidAudio / Parakeet.
- Labels remote speakers with NVIDIA Sortformer v2.1, with Pyannote Core ML fallback.
- Lets you rename or merge speakers before copying or saving Markdown.
- Provides optional local dictation from the menu bar.

## Requirements

- macOS 14.2 or later for live system-audio capture.
- Xcode and Xcode Command Line Tools.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

## Build and run

```bash
make doctor
make test
make run
```

`make build` creates an unsigned Debug build. `make test` generates the Xcode project from `project.yml` before running tests.

## Models and privacy

Antrum asks before downloading local ASR and diarization models from FluidAudio/Hugging Face. Audio, transcript text, speaker labels, and calendar details are not uploaded by Antrum.

Model weights are not included in this repository. Review their upstream terms before downloading. See [THIRD_PARTY_AND_MODEL_NOTICES.md](THIRD_PARTY_AND_MODEL_NOTICES.md).

Recording is manual and consent-forward. Antrum does not join calls, inspect browser tabs, or start recording automatically. You are responsible for obtaining permission from all meeting participants before recording.

See [PRIVACY.md](PRIVACY.md) for storage and permission details.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Run these checks before opening a pull request:

```bash
make lint
make secret-scan
make test
```

Report vulnerabilities privately through [GitHub private vulnerability reporting](https://github.com/coreyone/Antrum/security/advisories/new). Use [Issues](https://github.com/coreyone/Antrum/issues) for bugs, support, and feature requests.

## License

Licensed under the [Apache License 2.0](LICENSE).
