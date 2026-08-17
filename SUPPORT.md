# Support

## Using the app

| What you need                             | Where to go                                                                                            |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Account, billing, or subscription problem | `support@plink.app`                                                                                    |
| Something is broken in the app            | [Open a bug report](https://github.com/PubgmHacker/plink/issues/new?template=bug_report.yml)           |
| An idea for the product                   | [Open a feature request](https://github.com/PubgmHacker/plink/issues/new?template=feature_request.yml) |
| A security vulnerability                  | `security@plink.app` — see [SECURITY.md](SECURITY.md). Never a public issue.                           |
| Data export or account deletion (GDPR)    | In-app: Settings → Account → Delete account. Or `privacy@plink.app`.                                   |
| Licensing and commercial questions        | `legal@plink.app`                                                                                      |

Support replies in Russian and English.

## Before reporting a sync problem

Most "it went out of sync" reports resolve to one of these, and checking first saves
a round trip:

1. **Is the host still the host?** The drift badge shows your offset from the host's
   timeline. If the host left, the role moved to another participant and the timeline
   moved with it.
2. **Is the source playable in-app?** YouTube, VK Video, Rutube, and direct media URLs
   play in-app. Everything else — including subscription services — is watched through
   screen share, where the picture comes from the host's device and the badge does not
   apply.
3. **Does it survive a rejoin?** Leave and re-enter the room. Sync state is server-held,
   so a rejoin gets you a clean snapshot.

If the drift badge holds a value above roughly 1 s for more than a few seconds, that is
a bug worth reporting — include the room code so the session can be found in the logs.

## Contributing

This is a proprietary repository. Access does not imply a contribution license — see
[LICENSE](LICENSE). If you have repository access, [CONTRIBUTING.md](CONTRIBUTING.md) is
the working agreement.

## What is not supported

- Playing DRM-protected content in the in-app player. It is not a bug; it is a
  deliberate limitation. See [ADR-0003](docs/adr/0003-honest-service-catalog.md).
- Devices below iOS 17.
- Modified or sideloaded builds.
