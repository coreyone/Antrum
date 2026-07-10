# Design Accessibility

Antrum targets keyboard-first macOS operation and VoiceOver-readable task flows.

## Non-Negotiables

- Interactive targets should be at least 44 pt where layout allows.
- Icon-only controls require accessibility labels.
- Dynamic status areas should expose meaningful state labels.
- Reduced Motion must remove nonessential animation.
- Reduced Transparency must keep surfaces legible.
- Color cannot be the only indicator of recording, failure, completion, or selection.
- Small text must meet contrast expectations on its surface.

## Keyboard

- Native buttons, toggles, pickers, and text fields should preserve system focus.
- Menu bar commands may mirror key actions.
- Hidden overflow controls should not contain required primary actions.

## VoiceOver

Use combined accessibility elements for repeated content blocks when it improves scanability:

- Transcript block: speaker, time range, text.
- Recording timer: state and duration.
- HUD: app feature and current state.

## Motion And Transparency

Liquid Glass must have an explicit non-glass fallback. Waveform motion and loading animation must respect Reduce Motion.
