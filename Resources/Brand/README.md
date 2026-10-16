# Headset Gesture Brand Assets

## App icon — "Earbud tap"

A single white earbud on a white tile, with three systemBlue tap marks radiating
off its stem. It reads as "the headset button, pressed": the device is the
subject, the blue marks are the gesture. The look follows macOS system-app
conventions — a light tile, one physical object with soft shading and a drop
shadow, and a single system accent colour.

- Canvas 1024×1024; the tile is the centered 824×824 continuous-corner square
  (corner radius 185), leaving room for the drop shadow.
- The earbud leans right, rotated 12.9° clockwise about the canvas centre; the
  tap marks stay fanned around the horizontal. The dark speaker grille
  and the blue marks are what keep the icon identifiable at 16/32 px.
- No text, no fine detail, no trademarks.

### Palette

| Role | Hex | Note |
| --- | --- | --- |
| Tile top | `#FFFFFF` | |
| Tile bottom | `#F0F0F4` | |
| Earbud body | `#FFFFFF` → `#C9CFDA` | horizontal shading |
| Earbud rim | `#D3D8E0` | 6 px stroke, separates the earbud from the white tile |
| Earbud shadow | `#1C2B4A` @ 40 % | |
| Speaker grille | `#1C1C1E` @ 85 % | systemGray6 (dark) |
| Tap marks | `#007AFF` | systemBlue |

Two alternates are kept in the renderer: a silver tile (`#F7F7FA` → `#DCDDE3`,
no rim, `--variant earbud-silver`) and a systemBlue tile (`#4BA6FF` → `#0059D6`,
white marks, `--variant earbud-blue`).

### Regenerating

```bash
swift scripts/render-app-icon.swift
```

```bash
./scripts/generate-app-icon.sh
```

The first writes `AppIcon.png` (1024×1024, transparent outside the tile); the
second builds `Resources/AppIcon.icns` from it. `swift scripts/render-app-icon.swift --sheet out.png`
renders a review sheet with every palette at 64/32/16 px.

## Menu bar icon

The menu bar item does not shrink the app icon. It is a monochrome template
image (`isTemplate = true`) drawn in code at 18 pt by
`Sources/HeadsetGestureApp/MenuBarIcon.swift`, so macOS tints it for light,
dark and highlighted menu bars. The earbud silhouette is constant; a small
badge in the lower-right corner carries the state:

| State | Glyph |
| --- | --- |
| Connected | solid earbud + tap marks |
| Waiting for device | outlined earbud, no marks |
| Paused (interception off) | outlined earbud + pause bars |
| Permission missing | outlined earbud + exclamation badge |
