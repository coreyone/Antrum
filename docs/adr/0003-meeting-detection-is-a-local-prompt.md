# ADR 0003: Meeting Detection Is a Local Prompt

## Status

Accepted.

## Context

Antrum should help users notice recordable calls without bots, tab inspection, or automatic recording.

## Decision

Poll local microphone-use state for allowlisted meeting-capable apps and show a prompt. Do not inspect browser tabs, window titles, page URLs, camera state, or calendar state for detection.

## Consequences

- Browser detection remains heuristic and must use "microphone active" language.
- False positives are possible.
- Dismissal suppresses prompts until microphone activity clears.
