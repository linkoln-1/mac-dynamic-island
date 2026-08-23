# Releasing PersonalIsland

## One-time setup (already done unless noted)

1. Apple Developer Program membership — active.
2. **Developer ID Application certificate** (NOT "Apple Development"):
   Xcode → Settings → Accounts → your team → Manage Certificates → "+" →
   Developer ID Application. Requires Account Holder/Admin role.
3. **Notary credentials** (interactive, run once):
   ```bash
   xcrun notarytool store-credentials personalisland-notary \
     --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>
   ```
   App-specific password: appleid.apple.com → Sign-In and Security → App-Specific Passwords.
4. Sparkle EdDSA keys — generated on this machine (private key in login Keychain,
   public key in Support/Info.plist `SUPublicEDKey`). Back the private key up:
   `generate_keys -x sparkle_private_key_backup.pem` (keep it OUT of the repo).

## Cutting a release

```bash
./scripts/release.sh 1.0.0
```

The script: bumps version → Release build signed with Developer ID + hardened
runtime → verifies signature → builds DMG → signs DMG → notarizes (waits) →
staples → prints the Sparkle `sign_update` signature.

Then:
1. Add a release `<item>` to `appcast.xml` with the printed `sparkle:edSignature`,
   `length`, version and the GitHub download URL; commit + push.
2. `gh release create v1.0.0 build/PersonalIsland-1.0.0.dmg --title "PersonalIsland 1.0.0" --notes "..."`
3. The appcast URL in the app points at raw.githubusercontent main/appcast.xml —
   existing users get the update automatically via Sparkle.

Appcast item template:

```xml
<item>
  <title>1.0.1</title>
  <sparkle:version>1.0.1</sparkle:version>
  <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
  <enclosure
    url="https://github.com/linkoln-1/mac-dynamic-island/releases/download/v1.0.1/PersonalIsland-1.0.1.dmg"
    sparkle:edSignature="SIGNATURE_FROM_sign_update"
    length="LENGTH_FROM_sign_update"
    type="application/octet-stream"/>
</item>
```

## Notes

- Distribution is outside the App Store only (private APIs, ~/.claude and
  ~/.codex access are incompatible with sandboxing).
- Hardened runtime entitlement `com.apple.security.automation.apple-events` is
  required for the AppleScript media fallbacks (Support/PersonalIsland.entitlements).
- Debug builds stay ad-hoc signed; only `scripts/release.sh` produces
  distributable artifacts.
