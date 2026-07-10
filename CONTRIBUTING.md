# Contributing to Antrum

## Before opening a pull request

1. Read [README.md](README.md), [PRIVACY.md](PRIVACY.md), and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
2. Keep audio, transcripts, screenshots, logs, calendar details, credentials, and other personal data out of commits and issues.
3. Make focused changes. Update tests and privacy or permission copy when behavior changes.
4. Run:

```bash
make lint
make secret-scan
make test
```

## Pull requests

- Explain the user problem and implementation choice.
- State exact validation performed.
- Do not change entitlements, recording consent, local-processing claims, or model-download behavior without tests and maintainer review.
- Contributions are accepted under the repository's Apache-2.0 license.

## Respectful collaboration

Keep discussion specific, constructive, and free of personal data. Use GitHub's reporting tools for abusive platform behavior. Do not use public issues to disclose security vulnerabilities; follow [SECURITY.md](SECURITY.md).
