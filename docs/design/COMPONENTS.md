# Design Components

Antrum is a native macOS app. Prefer system controls and SwiftUI/AppKit behavior before custom controls.

## Buttons

Use native `.bordered` and `.borderedProminent` buttons for ordinary app actions. Use `appGlassButton` only when a product-specific glass treatment is part of the surface.

Variants:

- Primary: one obvious next action in the current state.
- Secondary: available but non-primary actions.
- Destructive: destructive confirmation only.
- Plain icon: compact dismiss or info actions with accessibility labels.

Rules:

- Buttons must have stable labels.
- Icon-only buttons require `.accessibilityLabel`.
- Keep hit targets near 44 pt where the layout allows.

## Panels And Surfaces

Use `chunkyPanel`, `appGlassControlSurface`, `appGlassStatusSurface`, and `thinHeaderSurface` for product surfaces. These own visual grouping, not behavior.

Rules:

- Do not put UI cards inside cards.
- Use glass for layering, not decoration.
- Prefer existing radii and strokes.

## HUDs

HUDs are non-activating, compact, and local to a transient task.

Required HUDs:

- Dictation HUD.
- Meeting detection HUD.

Rules:

- Respect Reduce Transparency.
- Keep copy short.
- Use spectral waveform color only for audio activity.

## Toasts And Banners

Use toast for transient success, status, and failure confirmations. Use banner/error surfaces for recoverable blocking errors.

Rules:

- Failure copy must explain the next action.
- Toasts should auto-dismiss unless they block progress.

## Model Setup

Model rows must show:

- Model purpose.
- Download source.
- Approximate size.
- Download, retry, downloading, downloaded states.

## Speaker Row

Speaker rows own per-meeting identity edits.

States:

- Normal.
- Renamed.
- Merged.
- Overlong name warning.
- Empty sample.

Rules:

- Speaker names update transcript blocks immediately.
- Merge controls must be constrained to existing speakers.

## Transcript Block

Transcript blocks preview exported Markdown order and labels.

Rules:

- Timestamp, speaker label, and text must be VoiceOver readable.
- Filtered preview must not imply export changes unless export changes too.

## Settings Sections

Settings use native controls. The system owns behavior and accessibility; the theme owns surface and hierarchy.
