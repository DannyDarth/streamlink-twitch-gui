# StreamHub iOS security audit — initial findings

Audit branch: `security/ios-hardening-audit` (based on `feature/ios-twitchadblock-rebuild`).

## Confirmed configuration findings

1. `.github/workflows/streamhub-ios.yml` sets `permissions: contents: write` for the whole workflow. This is needed by the current automatic GitHub Release publishing step, but gives write scope to build steps too. Proposed mitigation: split build and release into separate jobs with read-only permissions for build and write permission only for release, with explicit artifact transfer.
2. The workflow installs XcodeGen via unpinned `brew install xcodegen`. This is a supply-chain reproducibility concern, not a demonstrated vulnerability. Pin or verify the tool version before changing the build.
3. `ios/project.yml` sets `INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsLocalNetworking: YES`. Confirm no localhost playback/proxy feature needs it before removing the exception.
4. Workflow publishes a prerelease on each successful build, including branch pushes. Consider limiting release publication to manual, approved runs.

## Next audit scope

- Inspect all Swift networking and WKWebView navigation delegates, URL construction, redirects, and script message handlers.
- Review OAuth token storage, logs, and Keychain usage.
- Inspect dependencies and any committed secrets.
- Validate that hardening preserves fullscreen embedded playback, Kick/Twitch directories, Followed, and unsigned IPA packaging.

These findings are configuration risks and review items, **not** confirmed exploitable CVEs. No production app behavior has been changed.
