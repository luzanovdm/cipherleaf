# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.

Use [GitHub's private vulnerability reporting
form](https://github.com/luzanovdm/cipherleaf/security/advisories/new). Include
the affected version, a minimal reproduction, and the expected impact. Do not
include real secret values or private age identities.

Test only with synthetic data and systems you own or are authorized to use.
Please allow time for investigation and a coordinated fix before public
disclosure.

## Supported versions

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| `main` | Yes, as unreleased development code |
| Older releases | No |

This is a small, volunteer-maintained project. Reports are handled on a
best-effort basis; there is no response-time guarantee or bug bounty program.

## Operational guidance

- Keep age identity files outside source repositories.
- Give identity files the narrowest practical filesystem permissions.
- Do not use Cipherleaf in a recorded or remotely shared desktop session.
- Review the redacted change list and recipient status before every save.
- Commit only SOPS ciphertext.
- Rotate a secret if its plaintext or a private identity may have been exposed.
