# ADR 0001: Core Audio Process Tap Is the System-Audio Backend

## Status

Accepted.

## Context

Antrum records local meetings without joining calls. The App Store build should avoid Screen Recording permission and avoid implying screen capture.

## Decision

Use Core Audio process taps for system audio on macOS 14.2 or later. Do not ship a ScreenCaptureKit fallback.

## Consequences

- App Store privacy copy is simpler and more accurate.
- macOS 14.0 and 14.1 can launch the app, but full system-audio meeting recording requires macOS 14.2 or later.
- The failure path should tell the user what to fix next.
