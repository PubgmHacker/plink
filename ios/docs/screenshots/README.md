# App Store screenshots

Capture output lands here. The directory is tracked, and otherwise empty, so that the
capture commands in the release runbook have somewhere to write without a `mkdir`.

Sizes, naming prefixes, the rescaling step, and the content rules — which services may
appear in a frame and which must not — are in
[docs/runbooks/ios-build-and-release.md § 5](../../../docs/runbooks/ios-build-and-release.md#5-screenshots).

Screenshots themselves are deliberately not committed: they are regenerated from the
current build for every submission, and a stale frame in the tree is worse than none.
