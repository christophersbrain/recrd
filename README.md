# recrd

Simple macOS screen recorder app.

## Requirements

- macOS 12+
- Xcode command line tools (`xcode-select --install`)

## Run directly

```bash
cd /Users/christopherwhite/Desktop/untitled\ folder\ 3/recrd
swift run
```

## Build a `.app` bundle

```bash
cd /Users/christopherwhite/Desktop/untitled\ folder\ 3/recrd
./scripts/build-app.sh
open dist/recrd.app
```

The build script creates/uses a persistent local code-signing identity so Screen Recording permission remains stable across rebuilds.

## In-app updates (Sparkle)

`recrd` now includes Sparkle and a `Check for Updates…` menu item under the app menu.

Default appcast URL in the built app:

`https://raw.githubusercontent.com/christophersbrain/recrd/main/appcast.xml`

Optional build-time overrides:

```bash
RECRD_APPCAST_URL="https://your-feed-url/appcast.xml" \
RECRD_SPARKLE_PUBLIC_KEY="your_ed25519_public_key" \
./scripts/build-app.sh
```

To ship updates from GitHub, publish signed release artifacts and keep `appcast.xml` updated at your feed URL.

### One-time GitHub setup

In your GitHub repo settings (`Settings -> Secrets and variables -> Actions`), add:

- `SPARKLE_PUBLIC_KEY`: your Sparkle Ed25519 public key
- `SPARKLE_PRIVATE_KEY`: your Sparkle Ed25519 private key
- `MACOS_CERTIFICATE_P12_BASE64`: base64 of your Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD`: password for that `.p12`
- `MACOS_SIGNING_IDENTITY`: exact codesign identity string (example: `Developer ID Application: Your Name (TEAMID)`)

Generate keys locally once:

```bash
cd /Users/christopherwhite/Desktop/untitled\ folder\ 3/recrd
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

Important: Sparkle `generate_appcast` requires update archives signed with a valid Apple Developer ID Application certificate.
Ad-hoc or local self-signed identities are not sufficient for production updates.

To encode your `.p12` for `MACOS_CERTIFICATE_P12_BASE64`:

```bash
cd /Users/christopherwhite/Desktop/untitled\ folder\ 3/recrd
./scripts/encode-p12.sh /path/to/developer-id.p12
```

### Release flow (auto appcast update)

This repo includes a release workflow at:

`/.github/workflows/release.yml`

When you push a tag like `v1.0.1`, GitHub Actions will:

- build `recrd.app`
- zip it as `recrd-v1.0.1.zip`
- generate/sign `appcast.xml`
- create a GitHub Release and upload both files
- commit updated `appcast.xml` back to `main`

Release commands:

```bash
cd /Users/christopherwhite/Desktop/untitled\ folder\ 3/recrd
git tag v1.0.1
git push origin v1.0.1
```

## How it works

- Click `Start Recording`, then click again, hold, drag, and release to select the recording rectangle.
- Recording starts when you release the mouse.
- Click `Stop Recording` to finalize the file.
- Click `Take Screenshot` to save a PNG of your main display.
- On launch, the app creates `~/Desktop/recrd` if needed.
- All recordings and screenshots are saved in `~/Desktop/recrd`.
- Screenshot names: `scr_0.png`, `scr_1.png`, ...
- Recording names: `vid_0.mov`, `vid_1.mov`, ...
- Files in `~/Desktop/recrd` are automatically deleted after 14 days.
- Open `Preferences` to tune selection dim and release glow behavior.

On first use, macOS will ask for screen recording permission. If you deny it, enable it at:

`System Settings > Privacy & Security > Screen Recording`

After enabling permission, quit and reopen `recrd`.
