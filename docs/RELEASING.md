# Publishing Browser Switchboard

Suggested repository name: `browser-switchboard`.

Suggested GitHub description: **A native macOS app that routes links to your preferred browser, per app or per click.**

## Repository

1. Confirm the proposed MIT license and copyright notice in `LICENSE`.
2. Create an empty GitHub repository under the intended owner and push the source files. Keep private notes, local app bundles, credentials, and build output out of the repository. See `.gitignore`.
3. Check that the **Build and test** workflow passes.
4. Enable **Sponsorships** in the repository settings to show the PayPal link from `.github/FUNDING.yml`.

## Downloadable release

The local-test ZIP has an ad hoc code signature. Distribute source if a Developer ID signing setup is unavailable. For a public binary release, use a Developer ID Application certificate and an Apple notarization keychain profile. Keep the signing credentials outside the repository.

```sh
export DEVELOPER_ID="Developer ID Application: NAME (TEAMID)"
export NOTARY_PROFILE="your-notary-profile"

BUILD_ARCH=arm64 bash ./build.sh "build/arm64/Browser Switchboard.app"
bash ./package-release.sh "build/arm64/Browser Switchboard.app"

BUILD_ARCH=x86_64 bash ./build.sh "build/x86_64/Browser Switchboard.app"
bash ./package-release.sh "build/x86_64/Browser Switchboard.app"
```

The packaging script verifies the signature and architecture, runs self-tests when the build matches the current machine, submits the app to Apple, staples and validates the notarization ticket, then creates the ZIP and SHA-256 checksum in `dist/`.

Before publishing, download the draft assets on a separate Mac or clean test account. Check that macOS accepts the app and that the default browser registration, both languages, fixed routing, and the per-link chooser work. Include an Intel Mac and macOS 13 in the compatibility pass when those systems are available.

Create a draft GitHub release with tag `v2.1.1` and use the matching `CHANGELOG.md` entry for the release notes. Attach the notarized ZIPs and their checksums, then publish when ready.

[Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/) · [GitHub release documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
