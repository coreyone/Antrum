# Visual QA

Visual QA should validate actual product states, not isolated atoms.

## Local QA

Run `make run`, then validate the states below manually. Keep captures local unless they have been deliberately sanitized for documentation.

## Required Screenshot States

- Idle record/import.
- Meeting detection prompt.
- Recording active.
- Model setup.
- Processing skeleton.
- Review/export.
- Dictation settings.
- Dictation HUD.

## Checks

- Text does not overlap or truncate badly.
- Native controls retain expected focus and hover behavior.
- Reduce Transparency fallback remains readable.
- Reduce Motion removes nonessential animation.
- Spectral accents appear only for audio/activity states.
- Window layouts fit minimum supported size.

## Drift Signals

- New raw color literals outside `AppTheme`.
- New font sizes outside `AppTheme.Typography`.
- New custom button styles for ordinary actions.
- Screenshots that no longer match workflow templates.
