# ADR 0004: Dictation Ships by Default

## Status

Accepted.

## Context

Dictation is now a visible App Store feature, not a hidden development flag.

## Decision

Enable dictation by default while preserving a development override through `ANTRUM_FEATURE_DICTATION` and `FeatureFlags.Dictation`.

## Consequences

- App Store and privacy copy must disclose microphone capture, Accessibility paste, temporary audio, local model download, and no dictation history.
- Tests should fail if dictation becomes hidden-only again.
