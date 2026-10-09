# Release preparation

**English** · [简体中文](releasing.zh-CN.md)

## Source

- Software license: GPL-3.0-only. Preserve `LICENSE`, `THIRD_PARTY_NOTICES.md`, upstream notices and font licenses.
- The Xiaomi photo is excluded from the software license. Its ownership and removal notice are in both READMEs and the bundled third-party notices; no redistribution authorization has been documented.
- Public source must exclude `Signing.local.xcconfig`, private keys, certificate exports, notarization credentials and local build products.
- Every binary release must identify its exact source revision and provide corresponding source from the same release location. Include configuration and build instructions, but no private signing keys.
- The public build defaults are arm64 and ad-hoc signing. A maintainer's optional local signing override is not part of the source release.


## Signed downloads

Development signing and ad-hoc signing are for local builds. A public download uses a **Developer ID Application** certificate, Hardened Runtime and Apple notarization. No Developer ID certificate, notarization credential or completed notarization is supplied by this repository.

After installing your own Developer ID Application certificate, build into a separate directory so daily-use builds are unaffected. Replace both placeholders with your own values:

```sh
xcodebuild -project MiRemoteHelper/MiRemoteHelper.xcodeproj \
  -scheme MiRemoteHelper -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/Distribution \
  CODE_SIGN_STYLE=Manual \
  'CODE_SIGN_IDENTITY=Developer ID Application: YOUR NAME (YOUR_TEAM_ID)' \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ENABLE_HARDENED_RUNTIME=YES \
  'OTHER_CODE_SIGN_FLAGS=--timestamp' build

codesign --verify --deep --strict --verbose=2 \
  'build/Distribution/Build/Products/Release/Mi Remote Helper.app'
```

Run `python3 scripts/check-release-security.py "build/Distribution/Build/Products/Release/Mi Remote Helper.app" --distribution` before uploading. The [security policy](security.md) documents the empty Release entitlement allowlist and permission boundaries.

The app’s Release configuration disables base entitlement injection and enables Hardened Runtime. Before notarizing, inspect the signature with `codesign -d --entitlements - --xml` and `codesign -d --verbose=4`: `com.apple.security.get-task-allow` must be absent or false, the runtime flag must be present, and Developer ID signing must include a secure timestamp. Strict signature verification alone does not check these distribution requirements. See [Apple’s notarization troubleshooting](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

Use `xcrun notarytool store-credentials` to configure a Keychain profile named `mi-remote-notary` interactively. Do not put passwords or API private keys in repository files. Submit the archive, check that its status is **Accepted**, then staple and verify:

```sh
ditto -c -k --keepParent \
  'build/Distribution/Build/Products/Release/Mi Remote Helper.app' \
  build/MiRemoteHelper-notarization.zip
xcrun notarytool submit build/MiRemoteHelper-notarization.zip \
  --keychain-profile mi-remote-notary --wait

# Run only after the submission is Accepted.
xcrun stapler staple 'build/Distribution/Build/Products/Release/Mi Remote Helper.app'
xcrun stapler validate 'build/Distribution/Build/Products/Release/Mi Remote Helper.app'
spctl --assess --type execute --verbose=2 \
  'build/Distribution/Build/Products/Release/Mi Remote Helper.app'

ditto -c -k --keepParent \
  'build/Distribution/Build/Products/Release/Mi Remote Helper.app' \
  build/MiRemoteHelper-arm64.zip
```

The notarization upload ZIP is not the final download: package again after stapling. Validate the resulting app on another Apple Silicon Mac, including Bluetooth, Accessibility, Input Monitoring, login startup and actual dictation. Hardened Runtime and notarization do not establish hardware compatibility.

Keep the corresponding source archive beside the final app ZIP. Generate it from the exact committed release revision, never from an unrelated current branch or a tree with unpublished changes:

```sh
# Run at the exact committed revision used to build the release.
git archive --format=zip --output=build/MiRemoteHelper-source.zip HEAD
```

References: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [customizing notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [GPL-3.0 section 6](https://www.gnu.org/licenses/gpl-3.0.html#section6).
