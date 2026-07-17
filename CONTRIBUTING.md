# Contributing

Issues and pull requests are welcome. Use synthetic data in every public
artifact.

## Setup

Install Xcode 26 or newer, then:

```sh
brew install actionlint age ripgrep shellcheck sops xcodegen
Scripts/test.sh
shellcheck Scripts/*.sh
actionlint .github/workflows/*.yml
```

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
screenshot made with synthetic values.
