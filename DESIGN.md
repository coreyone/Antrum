# Antrum Design System

Version: alpha

Antrum uses a dark graphite local-machine interface: native macOS controls, Liquid Glass surfaces where the platform supports them, restrained spectral accents for live audio, and monospaced utility typography. The app should feel like a focused local instrument, not a SaaS dashboard or a web app port.

## Principles

- Local trust first: copy, state, and permissions must make local processing obvious.
- Native before custom: use macOS controls and system behaviors unless the product has a concrete reason not to.
- One job per state: record/import, prepare models, process, review, export, dictate.
- Glass is structure, not decoration: Liquid Glass should clarify layering and affordance.
- Spectral color means live audio or active capture. Do not use rainbow color as decoration.
- Short copy beats instruction blocks. Controls carry the workflow.
- Accessibility is part of the component contract, not a later pass.

## Visual Direction

The shipped direction is dark graphite Liquid Glass.

- Canvas: deep graphite, not pure black.
- Surfaces: graphite panels with native material or Liquid Glass.
- Text: near-white primary text, muted gray secondary text.
- Accent: system-compatible blue focus and selection.
- Live audio: spectral waveform accents for dictation, recording, and meeting-detection activity.
- Typography: monospaced system stack for precision and local-machine character.

Do not return to the older warm paper pixel system unless a future ADR explicitly reverses this decision.

## Foundations

### Tokens

The machine-readable token source is `design/tokens.json`. The Swift source of truth at runtime is `Sources/AppTheme.swift`.

Token categories:

- Color: canvas, surfaces, borders, text, focus, selection, glass, waveform.
- Typography: display, title, section, body, caption, micro, label.
- Spacing: 4, 6, 8, 10, 12, 14, 16, 18, 24.
- Radius: badge, control, card, panel, drop target, HUD bar.
- Stroke: hairline, control, heavy.
- Motion: short feedback durations only.
- Layering: base, content, modal, HUD, toast.
- Component dimensions: HUDs, settings panel, model setup, control minimum target.

Semantic tokens are preferred over raw values. New raw colors, radii, font sizes, or shadows require a design-system update.

### Typography

Use monospaced system type for the product surface. Keep the scale small and stable:

- Display: only for the primary idle command.
- Title: processing and review headers.
- Section: panel and settings group headers.
- Body/body strong: primary row and form text.
- Caption/micro/label: metadata, chips, helper text, timestamps.

Do not add new type sizes casually. Use tabular numerals for counts, times, and progress.

### Motion

Motion should confirm state, not entertain.

- Use opacity, small scale, and waveform changes.
- Keep feedback under 200 ms where possible.
- Respect Reduce Motion.
- Do not animate layout in ways that move task-critical controls.

### Accessibility

Target keyboard-first macOS use, VoiceOver-readable controls, sufficient contrast, minimum 44 pt interactive targets where possible, Reduce Motion, and Reduce Transparency fallbacks.

## Components

The component catalog lives in `docs/design/COMPONENTS.md`.

System buttons are the default for ordinary app actions. Custom glass button/surface modifiers are reserved for product-specific surfaces, HUDs, model setup, and places where native controls alone do not express the local-machine hierarchy.

Required component families:

- Native buttons, toggles, pickers, text fields, menus.
- App panels and glass control surfaces.
- Toasts, banners, inline errors, empty states.
- Model setup popover and model rows.
- Dictation HUD and meeting detection HUD.
- Speaker rows and transcript blocks.
- Settings sections and permission rows.

## Workflow Templates

The workflow catalog lives in `docs/design/WORKFLOWS.md`.

Required workflows:

- First-run permissions.
- Idle record/import.
- Meeting detection prompt.
- Recording active and stopping.
- Model setup.
- Processing.
- Review/export.
- Dictation settings and dictation HUD.

Every workflow template must include normal, empty, loading, error, permission, and recovery states when applicable.

## Customization Boundary

The customization model lives in `docs/design/CUSTOMIZATION.md`.

System owns:

- Behavior, accessibility, keyboard operation, reduced-motion behavior, error states, permission recovery, and interaction contracts.

Theme owns:

- Semantic color, material strength, typography scale, spacing scale, radius scale, and accent use.

Override order:

1. Semantic token.
2. Component variant.
3. Local style override.
4. Source ownership.

Forking or wrapping core UI should be treated as a signal that the design system is missing a capability.

## Governance

- Product-facing visual direction changes require an ADR.
- Token changes require an update to `design/tokens.json`, `Sources/AppTheme.swift`, and design docs.
- New component variants require docs and, where practical, tests.
- Visual QA should include screenshot smoke coverage for primary states.
- Design debates should resolve against user flow clarity, accessibility, and repeated usage evidence before taste.

## Do

- Use native macOS controls first.
- Use Liquid Glass for meaningful layering.
- Keep UI dense but calm.
- Use spectral waveform accents only for audio activity.
- Prefer semantic tokens and existing modifiers.
- Keep permission and privacy copy honest and local.

## Do Not

- Add web-app chrome, dashboards, cards inside cards, or marketing hero layouts.
- Add decorative gradients, orbs, bokeh, or color washes.
- Use rainbow color outside live audio/activity surfaces.
- Hide primary actions in overflow menus.
- Add new settings to the main workflow unless they unblock the current task.
- Create one-off raw colors, font sizes, or button treatments without updating the system.
