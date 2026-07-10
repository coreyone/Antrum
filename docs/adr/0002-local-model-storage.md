# ADR 0002: Local Model Storage Lives Under Antrum Application Support

## Status

Accepted.

## Context

FluidAudio model downloads are required for local transcription and dictation. Users and reviewers need a clear deletion path.

## Decision

Store Antrum-owned models in `~/Library/Application Support/Antrum/Models` and migrate older Antrum-used FluidAudio model folders into that location on launch.

## Consequences

- Uninstall and privacy instructions have one primary app-support folder.
- Model setup can disclose source and approximate size before download.
- Migration must remain tested because it touches user-local files.
