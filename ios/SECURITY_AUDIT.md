# StreamHub iOS security audit — pre-merge review

Audit branch: `security/ios-hardening-audit`  
Intended merge target: `feature/ios-twitchadblock-rebuild` (NOT `master`)  
Reviewed through tested application commit: `c42ba4e3986bb97bee2d2d7d3be511957cab14f3`

## Verification status

- User reported 40/40 successive iOS GitHub Actions builds passing.
- User reported 8/8 on-device iPhone regression tests passing on `c42ba4e`, including Twitch, Kick, Followed, embedded playback, fullscreen, audio shutdown, search, artwork, viewer counts, and existing ad-handling behavior.
- These tests demonstrate successful build and observed functionality, not absence of all vulnerabilities.
- Comparing with `feature/ios-twitchadblock-rebuild`: security branch is 43 commits ahead, zero behind **before this documentation update**. Changes were confined to iOS source/configuration and the iOS workflow.
- `master` has substantially diverged; do not merge this security branch directly into `master`.

## Implemented mitigations reviewed

1. iOS workflow defaults to `contents: read`; the separate publishing job alone requests `contents: write`, restricted to approved branches and events.
2. GitHub Actions checkout/upload/download dependencies are pinned to full commit hashes. Runner generation and job timeouts are specified.
3. XcodeGen is installed with Homebrew, and the workflow verifies version 2.46.0 before building. The Homebrew formula/package is **not** pinned to an immutable checksum.
4. IPA packaging checks executable name, arm64, device platform, bundle identifier, unsigned status, expected privacy usage descriptions, background modes, and absence of App Transport Security exceptions. Release artifacts include SHA-256 checksums.
5. Reviewed `FilteredWebPlayer.swift`, `FollowedView.swift`, and `TwitchBrowserView.swift`: HTTPS navigation restrictions, credential-bearing URL rejection, limited about:blank handling, untrusted top-level redirect blocking, and Web Inspector disabled on supported iOS versions.
6. Reviewed `KickDirectory.swift` and `KickGamesDirectory.swift`: HTTPS endpoint and expected-host validation, 2xx response checks, and 5 MB response limits before JSON parsing. Artwork URLs are HTTPS-only.
7. Reviewed `TwitchProxyPlaylistResolver.swift`: token-bearing playlist URLs are not included in surfaced proxy error messages in the reviewed paths.
8. `ios/project.yml` does not request the former `NSAllowsLocalNetworking` exception.

## Dependency and secrets review

- `ios/project.yml` contains no declared external Swift package dependencies; the reviewed iOS sources use Apple frameworks (Foundation, SwiftUI, WebKit, Combine).
- `ios/StreamHub/AdBlockingSettings.swift` uses WebKit content rule lists, not an additional package.
- Build tooling dependencies include Xcode/XcodeGen, Homebrew and the pinned GitHub Actions. The macOS runner and Xcode versions are version-family constrained rather than immutable image hashes.
- No `ios/Package.resolved`, `ios/StreamHub/Info.plist`, or iOS `Podfile` was verified through the targeted file reads. The workflow generates the app Info.plist.
- Targeted GitHub code-search queries on the **default branch** for common secret markers (`AKIA`, `BEGIN PRIVATE KEY`, `client_secret`, `github_pat_`, `sk_live_`) returned no matches. This is **not a comprehensive secrets scan**: GitHub search covers the default branch, not necessarily the audit branch, and simple string searches miss many secret formats and git history.
- No credential value is reproduced in this audit. The repository's full history, dependency vulnerability databases, binary assets and generated IPA were not independently scanned here.

## Remaining risks / follow-up

- Supply-chain reproducibility: Homebrew XcodeGen installation verifies version but not immutable package digest; evaluate a digest-verified distribution in a separate, tested change.
- The iOS workflow still publishes prereleases on successful approved-branch pushes; consider manual-only publication if desired.
- Review all unexamined Swift files, full git history, dependency advisories, binary assets and the final built IPA with dedicated scanning tools before calling this a comprehensive security audit.
- WebView login and streaming may depend on third-party HTTPS frames. Preserve those flows when considering stricter host restrictions.
- Existing embedded ad-handling behavior is not guaranteed by these mitigations; the user reports that it passed the current on-device regression tests.

## Merge guardrails

1. Prepare a **draft** pull request into `feature/ios-twitchadblock-rebuild`.
2. Confirm the final PR diff and checks; this documentation-only update does not alter runtime code.
3. Do not merge without explicit user approval.
4. Keep Windows stable releases and `master` untouched.
