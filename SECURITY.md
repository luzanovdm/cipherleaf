# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.

Use GitHub's private vulnerability reporting feature for this repository.
Include the affected version, a minimal reproduction, and the expected impact.
Do not include real secret values or private age identities.

## Supported versions

Security fixes are applied to the latest release and the default branch.

## Operational guidance

- Keep age identity files outside source repositories.
- Give identity files the narrowest practical filesystem permissions.
- Do not use Cipherleaf in a recorded or remotely shared desktop session.
- Review the redacted change list and recipient status before every save.
- Commit only SOPS ciphertext.
- Rotate a secret if its plaintext or a private identity may have been exposed.
