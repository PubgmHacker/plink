# ADR-NNNN: Short title in the imperative or as a noun phrase

- **Status:** Proposed | Accepted | Superseded by [ADR-NNNN](NNNN-….md) | Rejected
- **Date:** YYYY-MM-DD
- **Deciders:** who agreed to this

## Context

What situation forces a decision? Constraints, the failure that prompted it, what
was already true. Enough that someone with no memory of this period can follow the
argument.

Facts, not conclusions. If a number drove the decision, give the number.

## Decision

What was decided, in the present tense: "Room state lives in Redis and is mutated
through Lua scripts."

State it so that a reviewer can tell whether a given diff complies.

## Consequences

### What this makes easier

### What this makes harder

Be specific and honest. Every real decision costs something; a record that lists no
cost is not describing a decision.

### What has to be true for this to keep working

Assumptions that could expire. This is the section that tells a future reader when
to reopen the question.

## Alternatives considered

**Option — why not.** One paragraph each, for options genuinely on the table. Include
doing nothing when that was an option.

Do not pad this with alternatives nobody considered. The purpose is to stop the same
argument being had twice, not to demonstrate thoroughness.

## References

Links to the code that implements this, related records, and any external material
the argument depends on.
