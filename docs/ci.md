# CI

Workflow: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml). Runs on every
pull request, every push to `main`, and manually (`workflow_dispatch`). A newer
push to the same PR/branch cancels the older run.

| job | runner | what it does |
|-----|--------|--------------|
| **Validate content JSON** | `ubuntu-latest` | `Tools/normalize.py` self-check; `Tools/validate_matn.py` on every file in `Resources/Content/`, in both layouts (bayt list, schemaVersion 1; pages, schemaVersion 2). Stdlib only, takes a few seconds. |
| **Build & unit tests** | `macos-26`, Xcode 26.6 | `xcodegen generate`, resolve SPM (WhisperKit), pick the newest available iPhone simulator from `simctl list -j`, then `xcodebuild test`. On failure the `.xcresult` is uploaded as an artifact (kept 7 days). |
| **Unsigned device build** | `macos-26`, Xcode 26.6 | `xcodebuild build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`. Catches device-only build breaks without needing certificates. |

Notes:

- **No signing in CI.** `Config/Local.xcconfig` doesn't exist on the runner, so
  the project uses the `com.farhan` defaults from `Config/Signing.xcconfig`.
  Every build passes `CODE_SIGNING_ALLOWED=NO`.
- **Xcode version.** Locally we use Xcode 27. GitHub's GA `macos-26` image tops
  out at Xcode 26.6 (iOS 26.5 SDK), which is enough for the iOS 26 deployment
  target. Xcode 27 is only on the `xcode-27` preview image. To move to it, set
  `runs-on: xcode-27` and `XCODE_APP: /Applications/Xcode_27.app` in the
  workflow. Do that once the image is GA, or earlier if the app starts using
  iOS 27 SDK APIs.
- **Whisper end-to-end tests are off.** They only run with `WHISPER_E2E=1`
  (`TEST_RUNNER_WHISPER_E2E=1`) and download a 632 MB model, so CI never sets it.
- **Caching.** The SPM checkout (`SourcePackages/`, via
  `-clonedSourcePackagesDirPath`) is cached, keyed on `project.yml` and the Xcode
  path. DerivedData is not cached because the build is small and a stale cache
  causes more trouble than it saves.
- **Dependabot** (`.github/dependabot.yml`) opens one grouped PR each month to
  bump the GitHub Actions versions.

Reproduce the test job locally:

```sh
xcodegen generate
xcodebuild -project HifzAlMutun.xcodeproj -scheme HifzAlMutun \
  -destination "id=$(python3 .github/scripts/pick_simulator.py)" \
  CODE_SIGNING_ALLOWED=NO test
```

## Later: TestFlight

Nothing deploys yet because the repo has no App Store credentials. When it does,
add a `testflight` job that runs on pushes to `main` (or on `v*` tags), has
`needs: [content, test, device-build]`, and uses a protected `release`
environment.

**Repository/environment secrets required:**

| secret | what |
|--------|------|
| `ASC_KEY_ID` | App Store Connect API key ID (Users and Access → Integrations → App Store Connect API, role *App Manager*). |
| `ASC_ISSUER_ID` | The issuer ID shown on that same page. |
| `ASC_KEY_P8` | Contents of the `.p8` private key (base64). |
| `DEVELOPMENT_TEAM` | The 10-character Apple team ID. |
| `BUNDLE_ID_PREFIX` | A prefix registered to that team (replaces `com.farhan`). |

Signing needs **one** of the following:

- **Manual:** `DIST_CERT_P12` (base64 Apple Distribution certificate + key),
  `DIST_CERT_PASSWORD`, `PROVISIONING_PROFILE` (base64 App Store profile for
  `$(BUNDLE_ID_PREFIX).hifzalmutun`), plus a throwaway `KEYCHAIN_PASSWORD`.
- **`fastlane match`:** `MATCH_GIT_URL` (private certs repo),
  `MATCH_PASSWORD` (encryption passphrase), and `MATCH_GIT_BASIC_AUTHORIZATION`
  (base64 `user:token` with read access to that repo).

**Job steps:**

1. Checkout, select Xcode, `brew install xcodegen`, `xcodegen generate`.
2. Write `Config/Local.xcconfig` from the secrets (`DEVELOPMENT_TEAM`,
   `BUNDLE_ID_PREFIX`, `CODE_SIGN_STYLE = Manual`).
3. Install signing assets. Either create a temporary keychain, import the .p12
   and copy the profile into `~/Library/MobileDevice/Provisioning Profiles/`,
   or run `fastlane match appstore --readonly`.
4. Set the build number to something unique, e.g.
   `CURRENT_PROJECT_VERSION=${{ github.run_number }}` on the command line.
5. `xcodebuild archive -scheme HifzAlMutun -destination 'generic/platform=iOS'
   -archivePath build/HifzAlMutun.xcarchive`, then `xcodebuild -exportArchive`
   with an `ExportOptions.plist` (`method = app-store-connect`).
6. Upload the `.ipa` with `xcrun altool --upload-app` (or `fastlane pilot` /
   `upload_to_testflight`), authenticating with the API key from steps above.
7. Always delete the temporary keychain at the end.
