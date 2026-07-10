# Design Customization Model

Antrum is not a multi-brand product today, but it still needs a clear ownership boundary.

## System Owns

- Component behavior.
- Accessibility labels and focus behavior.
- Permission recovery paths.
- Error, empty, loading, and disabled states.
- Workflow order.
- Recording, dictation, and meeting-detection copy constraints.

## Theme Owns

- Semantic colors.
- Native material strength.
- Typography scale.
- Spacing scale.
- Radius scale.
- Stroke scale.
- Spectral waveform colors.

## Override Order

1. Change or add a semantic token.
2. Add a documented component variant.
3. Use a local style override with a comment explaining why.
4. Take source ownership and update docs/tests.

Forking a component should trigger a design-system review.
