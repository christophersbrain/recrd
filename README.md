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
