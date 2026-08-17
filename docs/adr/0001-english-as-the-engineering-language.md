# ADR-0001: English as the engineering language

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** project maintainers

## Context

Plink is a Russian-language product. It launched in Russian, its largest audience is
Russian-speaking, and its interface copy is written in Russian first.

For most of the project's life that leaked into the codebase. Identifiers were English
because the languages force it, but comments, commit messages, internal documents, and
schema annotations were Russian — often in the same file, sometimes in the same
sentence. At the point this was measured, roughly a third of comments in the backend
and a quarter in the iOS app were Russian, distributed across every subsystem rather
than isolated to any one of them.

Three concrete costs:

1. **Search stops working.** Looking for what handles a ban means searching `ban`,
   `бан`, `блокировка`, and `заблокирован`. Every one of them returns a partial answer,
   and no single query tells you that you have a partial answer.
2. **Review stops working.** A reviewer who does not read Russian can approve a diff
   whose comment says the opposite of what the code does.
3. **Hiring narrows to people who read both.** For a product expanding
   internationally, that is a constraint on the team imposed by an accident of
   authorship rather than by any engineering need.

The product being Russian does not require the codebase to be. These are different
artifacts with different audiences: one is read by users, the other by whoever
maintains it.

## Decision

The engineering language is English. Everything a maintainer reads is English:

| What                                     | Language                        |
| ---------------------------------------- | ------------------------------- |
| Identifiers, types, functions, filenames | English                         |
| Code comments and doc comments           | English                         |
| Commit messages, pull requests, review   | English                         |
| `docs/`, `README`, ADRs, runbooks        | English                         |
| **User-facing product copy**             | **Localized — never hardcoded** |

Russian remains a first-class product locale. It is not a second-class one either: the
default locale is Russian, and `en` and `zh` sit alongside it in the string catalog.
The rule is about where the text lives, not which language matters.

User-facing text never appears as a literal in a view. It goes in the string catalog
and is referenced by key, so a translator can work without opening a Swift file. That
separation is what makes this decision cheap — once copy is out of the source, there is
nothing left in the source that needs to be Russian.

## Consequences

### What this makes easier

- One search term finds every site. Grep becomes trustworthy.
- Anyone who reads English can review any file.
- Contributors do not need Russian to work on the backend.
- Enforcing "no hardcoded user strings" and "comments in English" is the same check
  twice: a Cyrillic literal in a view is a localization bug, and Cyrillic in a comment
  is a language-policy violation. Both are mechanically detectable.

### What this makes harder

- Comments written in the author's second language say less than they would have in
  their first. Some nuance is genuinely lost, and pretending otherwise would be
  dishonest.
- Discussing product copy in English adds a translation step to conversations that used
  to happen directly.
- The one-time conversion touched roughly a thousand comment sites. Every one of them
  was an opportunity to change meaning by accident.

### What has to be true for this to keep working

That the team's shared language stays English. If Plink becomes a Russian-only company
with a Russian-only team, this decision is worth reopening — the argument above is about
audience, and the audience would have changed.

## Alternatives considered

**Leave it mixed.** The status quo, and free. Rejected because the cost is not
stable: every new file adds to it, and the search problem gets worse with size, not
better.

**Russian as the engineering language, consistently.** Coherent, and it fits the
current team. Rejected because it makes the hiring pool a subset of Russian speakers
permanently, for a product explicitly aiming outside that market, and because the
tooling around code — libraries, error messages, Stack Overflow, this repository's own
dependencies — is English regardless.

**English for new code, leave existing comments alone.** Tempting because it costs
nothing today. Rejected because it produces the worst outcome: a codebase where you
cannot predict which language a comment will be in, so you have to search both forever,
with no end date.

## References

- Language policy in [CONTRIBUTING.md](../../CONTRIBUTING.md#language-policy)
- [Localization architecture](../architecture/localization.md)
- `ios/Plink/Localization/LocalizationManager.swift` — the string table
