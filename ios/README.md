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
