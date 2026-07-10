# ADR 0005: Sandbox and App Store Posture

## Status

Accepted.

## Context

Antrum is a local-first productivity app intended for Mac App Store distribution.

## Decision

Ship with App Sandbox, microphone, outgoing network client, user-selected read/write files, and calendar entitlements. Use network access only for explicit model downloads.

## Consequences

- App Store readiness tests validate the entitlement surface.
- Release builds keep Hardened Runtime enabled.
- Reviewer notes should stay aligned with actual entitlements and app behavior.
