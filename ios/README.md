# StreamHub iOS

Native SwiftUI iPhone application, isolated from the existing NW.js Windows app.

## Windows-only build process

1. Open GitHub Actions and select **StreamHub iOS unsigned IPA**.
2. Choose **Run workflow** on `feature/kick-clean-rebuild`.
3. Download the `streamhub-ios-unsigned-ipa` artifact after the job succeeds.
4. Extract the artifact ZIP to get `StreamHub-iOS-unsigned.ipa`.
5. Sign and install the IPA on your iPhone using a Windows sideloading tool such as AltStore/AltServer or Sideloadly. A raw unsigned IPA cannot launch without signing.

The GitHub-hosted macOS runner supplies Xcode. XcodeGen creates the Xcode project from `project.yml`.

This is a **foundation build**, not a functional streaming client yet. Twitch/Kick APIs, stream playback, and branding assets remain to be implemented and validated.


## Experimental TwitchAdBlock playback adapter

The `feature/ios-twitchadblock-rebuild` branch preserves StreamHub's existing SwiftUI/WKWebView Twitch/Kick interface and adds an opt-in **Play with TwitchAdBlock engine (experimental)** button in the native Twitch player. Its standalone Swift networking adapts the randomized playback-platform token technique from [level3tjg/TwitchAdBlock](https://github.com/level3tjg/TwitchAdBlock) (MIT license) and first attempts that author's Luminous HTTPS playlist endpoint before falling back to direct HLS using a randomized token. It does **not** package, inject, or redistribute TwitchAdBlock's prepatched Twitch IPAs or private Twitch-app hooks.

This is a first integration test, not verified adblocking. The on-screen status reports the transport used and any known stitched-ad playlist markers. Ad-free playback is not guaranteed, and a clean playlist does not prove ads cannot be inserted later. It transmits channel requests and IP addresses to a third-party proxy if that route is available. Normal Twitch web playback is kept as the fallback; Twitch/Kick browsing and the Windows program are unchanged.

Attribution: the approach is based on `level3tjg/TwitchAdBlock` (Copyright (c) 2025 level3tjg), distributed under the MIT license: https://github.com/level3tjg/TwitchAdBlock/blob/master/LICENSE .
