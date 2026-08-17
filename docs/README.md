# Plink documentation

Written documentation for the people who build and operate Plink. Product copy and
user-facing help live elsewhere; everything here assumes you have the repository
checked out.

## Start here

| If you are…                                    | Read                                                                                        |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------- |
| New to the codebase                            | [Architecture overview](architecture/README.md), then [CONTRIBUTING.md](../CONTRIBUTING.md) |
| Touching sync or the gateway                   | [Realtime protocol](architecture/realtime-protocol.md)                                      |
| Adding or changing user-facing text            | [Localization](architecture/localization.md)                                                |
| Calling the API                                | [API reference](architecture/api.md)                                                        |
| Wondering why something is built the way it is | [Decision log](adr/README.md)                                                               |
| Cutting a release                              | [Release runbook](runbooks/release.md)                                                      |
| Shipping, or on call                           | [Runbooks](runbooks/)                                                                       |
| Writing or reviewing tests                     | [Testing strategy](qa/testing-strategy.md)                                                  |

## Layout

```
docs/
├── architecture/   how the system is built, and what the contracts are
├── adr/            decision records — why it is built that way
├── runbooks/       operational procedures: deploy, release, incidents
├── qa/             testing strategy and release verification
└── legal/          third-party notices
```

## What belongs where

The distinction matters more than it looks, because it is what keeps this tree from
turning into the pile of dated markdown files it replaced.

**`architecture/`** — how the system works _today_. Present tense, no history. If a
page starts explaining what changed, that content belongs in `adr/` or the
changelog. These pages are expected to be edited in place as the system changes.

**`adr/`** — one decision per file, written once and then left alone. Context,
decision, consequences. An accepted ADR is never rewritten; superseding one means
writing a new record that says so. This is where "why not the obvious thing?"
questions get answered permanently.

**`runbooks/`** — procedures someone follows under pressure, possibly at 3am.
Imperative, numbered, with the verification step after each action and an explicit
rollback. No background reading.

**`qa/`** — what gets tested, at which level, and what must be verified by hand
before a release.

**`legal/`** — generated or curated attribution and licensing material.

Release notes go in [CHANGELOG.md](../CHANGELOG.md) at the repository root, not
here. Nothing in this tree should be dated in its filename: a document that needs a
date to be understood is a status report, and status reports belong in the pull
request that produced them.

## Conventions

- English, per [ADR-0001](adr/0001-english-as-the-engineering-language.md).
- Reference code with repository-relative links so they survive a file move and
  resolve on GitHub.
- Do not paste code that will drift. Link to the file and describe the invariant
  instead — a snippet that no longer matches the source is worse than no snippet.
- Diagrams as Mermaid, in the page. A diagram nobody can edit gets stale and stays
  stale.
