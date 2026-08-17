# Runbooks

Procedures, written to be followed rather than read. Each one assumes you are doing
the thing right now, possibly at an inconvenient hour, and does not assume you have
read anything else in this tree first.

| Runbook                                              | Use when                                               |
| ---------------------------------------------------- | ------------------------------------------------------ |
| [release.md](release.md)                             | Cutting a release across more than one surface         |
| [deployment.md](deployment.md)                       | Deploying the backend, or setting up a new environment |
| [ios-build-and-release.md](ios-build-and-release.md) | Cutting a TestFlight build or an App Store submission  |
| [incident-response.md](incident-response.md)         | Something is broken in production, or a secret leaked  |

`release.md` is the coordinator: it decides the version, orders the surfaces, and cuts the
tag. It delegates the mechanics of each surface to the two runbooks below it rather than
repeating them. If you are only deploying the backend, skip it and go straight to
`deployment.md`.

## What makes a runbook different from a doc

A runbook is imperative and numbered. Every step that changes something is followed
by the check that proves it worked, and every procedure states its rollback before
you need it.

Background belongs in [architecture/](../architecture/) and reasoning belongs in
[adr/](../adr/). If a step needs three paragraphs of justification, link to the ADR
and keep the step to one line.

When a procedure turns out to be wrong at 3am, fix it that morning. A runbook is
only worth having if the last person who followed it corrected it.
