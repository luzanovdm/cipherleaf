# Contributing

Issues and pull requests are welcome. Use synthetic data in every public
artifact.

## Before you start

Search existing issues and pull requests before opening a new one. Small bug
fixes and documentation improvements can go directly to a pull request. Open
an issue before substantial user-interface, security-model, or architecture
changes so the scope can be agreed before implementation.

Report suspected vulnerabilities through the private process in
[SECURITY.md](SECURITY.md), never in a public issue.

## Contribution workflow

1. Fork the repository and create a focused branch from the latest `main`.
2. Make the smallest coherent change and add or update tests where behavior
   changes.
3. Run all validation commands below.
4. Open a pull request and complete the template.

The protected `main` branch accepts changes through pull requests with passing
CI. Maintainers squash-merge accepted changes so each pull request becomes one
signed, reviewable commit.

## Setup

Install Xcode 26 or newer, then:

```sh
brew bundle
Scripts/test.sh
shellcheck Scripts/*.sh
actionlint .github/workflows/*.yml
```

`Brewfile` is the source of truth for command-line development dependencies.
Use `brew bundle check` to confirm that they are already installed.

The generated Xcode project is not committed. Change `project.yml`, regenerate
with XcodeGen, and include project-generation coverage in local validation.

## Architecture

Cipherleaf uses domain-oriented source placement and one-way framework
dependencies:

```text
CipherleafDomain
       ↑
CipherleafApplication
       ↑
CipherleafInfrastructure

Cipherleaf app composition → all three frameworks
```

User interface code belongs to `Domains/<Domain>` or to a routed/window-level
composition in `Pages`. Do not create a generic `Views` directory. Keep
`DocumentSession` behind domain facades rather than injecting it into views.

Read [docs/architecture.md](docs/architecture.md) and the repository
[AGENTS.md](AGENTS.md) before moving responsibilities between layers.

## Security-sensitive changes

Changes involving subprocesses, file replacement, identity handling,
diagnostics, clipboard behavior, or plaintext lifetime require failure-path
tests as well as a happy path.

Do not add:

- plaintext temporary files;
- secret values in arguments, logs, alerts, snapshots, or test names;
- inherited key environment variables;
- automatic recipient changes during a normal document save;
- silent recovery after an uncertain atomic-install outcome.

Fixtures must clearly contain synthetic values only. Never attach a real
encrypted manifest unless all of its public metadata is intentionally public.

## Pull requests

Keep pull requests focused. Explain the user-visible outcome, security
properties affected, and validation performed. UI changes should include a
screenshot made with synthetic values. Update `CHANGELOG.md` when a change is
visible to users or affects release, compatibility, or security behavior.

Review feedback is part of the contribution: keep the branch current, answer
questions, and avoid unrelated cleanup in the same pull request. Generated
Xcode projects, build products, signing material, real identities, and real
encrypted documents must not be committed.

## Licensing

Cipherleaf does not require a contributor license agreement. By submitting a
contribution, you agree that it is licensed under the repository's
[MIT License](LICENSE).
