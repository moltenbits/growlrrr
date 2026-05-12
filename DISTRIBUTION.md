# Distribution & Signing

This document covers what's needed to ship a notarized release of growlrrr through Homebrew without triggering Gatekeeper.

## Background

macOS has two layers of security for distributed apps:

1. **Code Signing** — Gatekeeper requires apps to be signed with a **Developer ID Application** certificate, issued only to Apple Developer Program members. Ad-hoc signing (`codesign --sign -`) works locally but Gatekeeper blocks it on any other machine.

2. **Notarization** — Since macOS Catalina, apps distributed outside the App Store must also be **notarized** — submitted to Apple's service which scans for malware and staples a ticket back to the app.

Without both, users see "from an unidentified developer" warnings and have to right-click → Open or override Gatekeeper in System Settings.

## One-time Apple Developer setup

### 1. Enroll in the Apple Developer Program ($99/year)

[developer.apple.com/programs](https://developer.apple.com/programs/).

### 2. Create a Developer ID Application certificate

In Xcode:
1. **Settings → Accounts**, sign in with your Apple ID.
2. Select your team → **Manage Certificates**.
3. Click `+` → **Developer ID Application**.

Verify it landed in your keychain:
```bash
security find-identity -v -p codesigning
# Should list: "Developer ID Application: <Team Name> (<TEAM_ID>)"
```

### 3. Create an app-specific password for notarization

1. Go to [appleid.apple.com](https://appleid.apple.com) → **Sign-In and Security → App-Specific Passwords**.
2. Create one labeled `growlrrr-notarization`.

### 4. Store notarization credentials in keychain (for local use)

```bash
xcrun notarytool store-credentials "growlrrr-notarization" \
  --apple-id "your@email.com" \
  --team-id "<TEAM_ID>" \
  --password "<app-specific-password>"
```

This creates a keychain profile that `notarytool` can use without prompts.

## Local signing & notarization

### Configure `.env`

The `.env` file in the project root (gitignored) provides team info to `scripts/bundle.sh`:

```bash
TEAM_NAME="<Your Team Name>"
TEAM_ID="<TEAM_ID>"
```

See `.env.example` for the format.

### Build, sign, notarize, and staple

```bash
make notarize
```

This single target does everything:

1. Builds the release executable (`swift build -c release`).
2. Assembles the `.app` bundle and signs it with your Developer ID identity, enables hardened runtime, and includes a secure timestamp.
3. Verifies the signature.
4. Submits to Apple's notary service via `notarytool submit --wait`.
5. Staples the notarization ticket and validates it.
6. Produces `.build/release/growlrrr.app` (notarized + stapled) and `.build/release/growlrrr.zip` (distributable artifact).

By default it reads notarization credentials from the `growlrrr-notarization` keychain profile (set up in step 4 of the Apple Developer setup above). Override with `NOTARY_PROFILE=<other>` if needed.

### Verifying

Optional sanity checks after `make notarize`:

```bash
# Confirm the signature is from your Developer ID and includes hardened runtime + timestamp
codesign --display --verbose=2 .build/release/growlrrr.app

# Confirm Gatekeeper accepts the bundle (works offline thanks to the staple)
spctl --assess --type execute --verbose .build/release/growlrrr.app
# Expect: "accepted" and "source=Notarized Developer ID"
```

### Custom app bundles

The custom apps growlrrr creates at runtime in `~/.growlrrr/apps/` (e.g., `Xcode.app`, `Code.app`) stay ad-hoc signed. They're only created on the user's own machine and never cross the Gatekeeper quarantine boundary, so they don't need a Developer ID signature.

## GitHub Actions CI setup

The release workflow (`.github/workflows/release.yml`) signs and notarizes on every `v*` tag push.

### 1. Export the certificate

Run the following from the project root. It generates a strong export password, exports your code-signing identity from the login keychain as a `.p12`, and copies the base64-encoded contents to your clipboard ready to paste into a GitHub secret.

```bash
P12_PASS=$(openssl rand -base64 24)
echo "P12_PASSWORD (save this for the GitHub secret):"
echo "$P12_PASS"

security export \
  -k ~/Library/Keychains/login.keychain-db \
  -t identities \
  -f pkcs12 \
  -P "$P12_PASS" \
  -o ~/Desktop/growlrrr-cert.p12

base64 -i ~/Desktop/growlrrr-cert.p12 | pbcopy
echo "BUILD_CERTIFICATE_BASE64 copied to clipboard."
```

macOS may prompt you to allow keychain access while exporting — click **Allow**.

> **Note:** `security export -t identities` dumps every code-signing identity in your login keychain, not just the Developer ID one. That's fine — when CI signs with `codesign --sign "Developer ID Application: ..."`, only the matching identity is used. After you've set the GitHub secrets and stashed the `.p12` in 1Password, you can `rm ~/Desktop/growlrrr-cert.p12`.

### 2. Add repository secrets

In **Settings → Secrets and variables → Actions** on the GitHub repo:

| Secret | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | The base64-encoded `.p12` |
| `P12_PASSWORD` | The password used when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | Any random string. macOS requires a password to create a keychain, but the keychain on the CI runner is temporary (destroyed when the job finishes) and never accessed by a human — the password is just a technical requirement, not a real security boundary. |
| `TEAM_NAME` | Your team name as it appears in the Developer ID identity |
| `TEAM_ID` | Your team ID |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_APP_PASSWORD` | The app-specific password from step 3 above |

### 3. What the workflow does

On a `v*` tag push:

1. Imports the certificate into a temporary keychain on the runner.
2. Runs `scripts/release.sh` with `TEAM_NAME`, `TEAM_ID`, `APPLE_ID`, `APPLE_APP_PASSWORD` set in the environment, which:
   - Calls `scripts/bundle.sh` to build and sign the app with Developer ID + hardened runtime + timestamp.
   - Calls `notarytool submit --wait` with inline credentials.
   - Calls `stapler staple` on the bundle.
   - Creates `dist/growlrrr-<version>-macos.tar.gz`.
3. Creates a GitHub Release with the tarball attached.
4. Updates the `moltenbits/homebrew-tap` cask formula with the new version, URL, and SHA256.

### 4. Cutting a release

```bash
git tag v1.4.0
git push origin v1.4.0
```

After the workflow completes, users can install the notarized version:
```bash
brew install --cask moltenbits/tap/growlrrr
```

## File reference

| File | Purpose |
|---|---|
| `.env` | Local signing config (gitignored): `TEAM_NAME`, `TEAM_ID` |
| `.env.example` | Committed template showing the expected format |
| `scripts/bundle.sh` | Builds the `.app`, signs it (Developer ID if `.env` set, ad-hoc otherwise) |
| `scripts/release.sh` | Calls `bundle.sh`, conditionally notarizes, creates `dist/*.tar.gz` |
| `Makefile` (`notarize` target) | Wraps notarization for local use; supports both keychain profile and inline credentials |
| `.github/workflows/release.yml` | CI workflow that imports cert, signs, notarizes, releases, updates Homebrew tap |

## Troubleshooting

### Notarization fails with "The signature does not include a secure timestamp"
The `--timestamp` flag isn't being applied. Check `bundle.sh` and confirm the codesign command includes `--timestamp`.

### Notarization fails with "The executable does not have the hardened runtime enabled"
The `--options runtime` flag isn't being applied. Check `bundle.sh`.

### `spctl --assess` returns "rejected"
Either the staple is missing (`xcrun stapler validate <app>` to confirm) or the bundle wasn't notarized successfully. Check the notarytool log:
```bash
xcrun notarytool log <submission-id> --keychain-profile growlrrr-notarization
```

### "errSecInternalComponent" during codesign in CI
The temporary keychain isn't unlocked or the cert isn't trusted by `apple-tool`. Confirm the workflow runs `security set-key-partition-list -S apple-tool:,apple: ...` after importing.
