# Design PR Checklist

Use this for UI-facing changes.

- [ ] Does the change preserve dark graphite Liquid Glass direction?
- [ ] Does it use native macOS controls where practical?
- [ ] Are new colors, spacing, radii, shadows, or type sizes tokenized?
- [ ] Are empty, loading, error, permission, disabled, and recovery states handled where relevant?
- [ ] Are icon-only controls labeled for accessibility?
- [ ] Does motion respect Reduce Motion?
- [ ] Does glass/transparency have a readable fallback?
- [ ] Does the change avoid rainbow/spectral color outside audio activity?
- [ ] Do docs or tokens need updates?
- [ ] Does `make test` still pass?
