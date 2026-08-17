# Architecture decision records

An ADR records a decision that constrains future work: a protocol shape, a storage
authority, a dependency that is hard to remove, or a deliberate product limitation.

They exist because the alternative is answering "why is it like this?" from memory,
and memory does not survive a team change. When a code comment needs to justify
itself, it should point here — `// See ADR-0004.` — rather than restate the argument
at every call site.

## Index

| #                                                          | Title                                                         | Status   |
| ---------------------------------------------------------- | ------------------------------------------------------------- | -------- |
| [0001](0001-english-as-the-engineering-language.md)        | English as the engineering language                           | Accepted |
| [0002](0002-host-authoritative-playback.md)                | Host-authoritative playback                                   | Accepted |
| [0003](0003-honest-service-catalog.md)                     | Honest service catalog instead of DRM circumvention           | Accepted |
| [0004](0004-strict-host-matching.md)                       | Strict host matching for embedded content                     | Accepted |
| [0005](0005-drift-as-a-user-facing-metric.md)              | Drift as a user-facing metric                                 | Accepted |
| [0006](0006-fail-fast-configuration.md)                    | Fail-fast configuration                                       | Accepted |
| [0007](0007-generated-xcode-project.md)                    | Generated Xcode project                                       | Accepted |
| [0008](0008-legacy-bundle-identifier.md)                   | Keep the legacy bundle identifier                             | Accepted |
| [0009](0009-redis-as-room-state-authority.md)              | Redis as the authority for room state                         | Accepted |
| [0010](0010-design-tokens-as-the-only-style-source.md)     | Design tokens are the only source of style                    | Accepted |
| [0011](0011-authorization-state-read-from-the-database.md) | Authorization state is read from the database, not the token  | Accepted |
| [0012](0012-pinned-apple-root-ca.md)                       | Purchase receipts are verified against a pinned Apple Root CA | Accepted |

Records 0011 and 0012 both come out of the July 2026 security audit. They are written as
decisions rather than as fixes because that is what they are: each one accepts a permanent
cost — a database dependency on the auth path, a pinned certificate on the purchase path — in
exchange for a property the previous design could not have.

## Writing one

```bash
cp docs/adr/template.md docs/adr/00NN-short-title.md
```

Take the next free number. Numbers are never reused, even if a record is rejected —
a gap is information.

Keep it short. Context, decision, consequences, and the alternatives you actually
considered. If it runs past two screens, the decision is probably several decisions.

Write the consequences honestly, including the bad ones. An ADR that lists only
upsides is marketing, and the next person will not trust the rest of the tree.

## Statuses

| Status         | Meaning                                                           |
| -------------- | ----------------------------------------------------------------- |
| **Proposed**   | Open for discussion; not yet binding                              |
| **Accepted**   | In force. Code is expected to comply.                             |
| **Superseded** | Replaced. The header links to the record that replaced it.        |
| **Rejected**   | Considered and declined. Kept so the argument is not relitigated. |

## The one rule

**An accepted record is never rewritten.** Not to fix its reasoning, not to reflect
a change of mind. Superseding one means writing a new record that says what changed
and why, and editing only the old record's status line to point at it.

The value of this tree is that it says what was believed _at the time_, with the
information available then. A record edited into agreement with the present is worth
nothing — it can no longer tell you that a decision was made under a constraint that
has since disappeared.
