# Incident response

For when production is broken, or a secret is exposed. Start at the section that
matches what you are seeing.

| Symptom                                                     | Section                                                                                           |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| A credential is in a commit, a log, or a screenshot         | [Exposed secret](#exposed-secret)                                                                 |
| Rooms will not open; playback does not sync between clients | [Realtime outage](#realtime-outage)                                                               |
| Boot log missing or failing the purchase self-check         | [In-app purchase verification self-check failed](#in-app-purchase-verification-self-check-failed) |
| API returning 5xx broadly                                   | [Backend outage](#backend-outage)                                                                 |
| Data is wrong or missing after a deploy                     | [Bad migration](#bad-migration)                                                                   |

## First moves, whatever it is

1. **Say something.** Post in the incident channel: what you see, when it started,
   what you are doing next. One line beats a perfect summary ten minutes later.
2. **Stop the bleeding before diagnosing.** Roll back, disable the feature flag, or
   revoke the credential first. Root cause can wait; user harm cannot.
3. **Write down what you do as you do it,** with timestamps. You will not reconstruct
   it afterwards, and the postmortem depends on it.
4. **Do not clean up evidence.** Do not force-push, do not delete logs, do not amend
   history until the incident is closed.

One person owns the incident and says so explicitly. If that is not clear, it is you.

---

## Exposed secret

A secret in version control, a log, an error report, or a chat message is
compromised. **Deleting it does not revoke it.** Removing the file, force-pushing, or
adding it to `.gitignore` changes nothing about the credential's validity — assume it
has been read by an automated scanner within minutes of being pushed.

### Procedure

1. **Revoke at the provider, first.** Before writing a commit, before telling anyone.
   Revocation is the only step that actually ends the exposure.
2. **Issue a replacement** and set it wherever it is consumed — for the backend, in
   Railway Variables ([deployment.md §3](deployment.md#3-environment-variables)).
3. **Verify the old credential is dead.** Call the provider with it and confirm you
   get an authentication failure. Do not assume the dashboard's word for it.
4. **Verify the new one works** — check the affected feature end to end, not just that
   the service boots.
5. **Find every other copy.** The same value may be in a second environment, a
   teammate's `.env`, CI secrets, or a password manager entry nobody remembers.
6. **Then** remove it from the working tree and commit.
7. **Check the provider's usage logs** for calls that were not yours, between exposure
   and revocation. If there are any, the incident is now also a billing and abuse
   incident.
8. Write the postmortem. Include how it got committed — the interesting question is
   never the secret, it is the missing guardrail.

### Rewriting history

Rewriting published history is a last resort, not a fix. It does not un-publish
anything: forks, clones, CI caches, and GitHub's own dangling-commit views keep the
old objects, and every collaborator's checkout breaks.

Do it only when the exposed material must be provably absent from the repository —
personal data, or a credential that cannot be revoked. If you do, revoke first anyway,
and coordinate: everyone re-clones.

### Known outstanding exposure

An OpenRouter provider key was committed in a landing-page helper script in commit
`774887b` and removed from the working tree in `b19d8ce`. **The commit is in pushed
history, so that key must be treated as compromised and revoked at the provider if it
has not been already.** Removing it from the file did not revoke it.

The helper script itself has since been deleted; provider credentials are supplied
through the environment.

---

## Realtime outage

Symptoms: rooms cannot be created or joined, participants do not appear, playback
does not follow the host.

Room state, presence, and cross-replica event distribution all live in Redis
([ADR-0009](../adr/0009-redis-as-room-state-authority.md)), so a Redis problem
presents as "the product does not work" while HTTP endpoints look healthy.

1. Check readiness:

   ```bash
   curl -fsS https://<backend-host>/health/ready | jq
   ```

   `"redis": "down"` confirms it. `"redis": "not_configured"` means `REDIS_URL` is
   unset — a configuration error, and the likely cause is a recent deploy.

2. If Redis is down, that is the incident. Restore the Redis service. Room state is
   ephemeral by design: rooms in progress are lost, but nothing durable is.
3. If Redis is up, check whether it is one replica or all of them. A single bad
   instance shows as _some_ users unable to sync while others are fine — restart that
   instance.
4. Check the gateway logs for repeated ticket rejections. A clock skew or a
   `REALTIME_TICKET_TTL_SEC` change can invalidate tickets faster than clients can
   redeem them, which looks like an authentication outage confined to WebSockets.

Playback desync _without_ a connection failure is a different problem — the drift
figure in the room header is the diagnostic ([ADR-0005](../adr/0005-drift-as-a-user-facing-metric.md)),
and it is a bug report, not an incident.

---

## In-app purchase verification self-check failed

At startup the backend verifies a deliberately forged receipt and asserts that it is
rejected. The boot log should contain:

```
[iap] verification self-check passed
```

If it reports a failure, or is missing entirely, receipt verification may be accepting
forgeries — anyone able to construct a receipt can grant themselves a paid
subscription.

1. **Treat it as a security incident, not a billing bug.**
2. Check `ALLOW_UNVERIFIED_IAP` and `ALLOW_SANDBOX_IAP` in the environment. Both must
   be `false` in production. If either is `true`, that is the cause; set it and
   redeploy.
3. Check that `APPLE_ROOT_CA_PEM` or `APPLE_ROOT_CERT_PATH` is present and holds the
   public Apple root certificate. With no root certificate, verification fails closed
   — genuine purchases stop being confirmed, which is a revenue and support problem,
   but not a security one. Note that the self-check passes in that state: it only
   asserts that a forgery is rejected.
4. Roll back to the last deploy whose log shows the self-check passing.
5. Once restored, audit `Subscription` and `TransactionRecord` rows created during the
   window for entitlements granted without a matching verified transaction.

---

## Backend outage

1. `curl /health/live` — if this fails, the process is not running. Check the deploy
   log; the most recent deploy is the most likely cause.
2. `curl /health/ready` — if live passes and ready fails, the body names the failing
   dependency. See [deployment.md §5](deployment.md#5-when-a-deploy-fails).
3. If a deploy is implicated, roll back ([deployment.md §6](deployment.md#6-rollback))
   before investigating further.
4. If nothing was deployed, look at load: `/metrics` (needs `METRICS_TOKEN`) and the
   database's connection count. Connection exhaustion presents as a total outage with
   a healthy process.

---

## Bad migration

A migration that lost or corrupted data needs a **restore**, not a deploy rollback —
rolling back the code leaves the schema change in place.

1. Stop writes if you can do so faster than the damage accumulates.
2. Identify the last known-good point in time from the database's backup history.
3. Restore into a **new** database, never over the live one. You will want the damaged
   state for the postmortem, and a restore that goes wrong over live data ends the
   company's afternoon.
4. Verify the restore, then repoint `DATABASE_URL` and redeploy.
5. Reconcile anything written after the restore point by hand.

This is why migrations are additive and destructive changes are split across two
releases ([deployment.md §4](deployment.md#4-deploying-a-schema-change)). The rule
exists to make this section unnecessary.

---

## After it is over

Write the postmortem within two working days, while people still remember. It is not
a document about who made a mistake — every incident here got through review, so the
question is what made the mistake invisible.

Cover: what users experienced and for how long; the timeline; why detection took as
long as it did; the fix; and the specific changes that would prevent a repeat.

Then file those changes as issues and link them. A postmortem whose action items never
became work is a document that made everyone feel better and changed nothing.
