# Settings reference

Menu bar → **Settings…** — seven pages.

## General

| Setting | Effect | Default |
| --- | --- | --- |
| Share as | Virtual Display (share a screen) or Hidden Window (share a window) | Virtual Display |
| Crisp text (Retina output) | Gives the virtual display 2× pixel density — sharpest with Retina sources, reduces compression artifacts otherwise; more bandwidth. Virtual Display mode only | off |
| Follow movement | Snap or smooth glide when follow mode moves the region | Glide |
| Resize region to followed window | Follow mode adopts the window's size (aspect-fitted in Virtual Display mode) | on |
| Follow | Off / Active Window / Cursor (also in menu bar → Follow) | Off |
| Show floating hotbar | Quick-action bar next to the region: stop, pause, record, highlights, preview, resize, save preset, follow. Auto-positions below → side → top; drag the ≡ grabber to place it manually; ✕ hides it until re-enabled | on |
| Show shared-output preview | Small floating window with exactly what viewers see — no need to keep Zoom/Teams open. Also toggled by the hotbar's eye button | off |
| Share window title | The name sharing apps list for the hidden share window in their window pickers (Hidden Window mode) | Outcut Share (Share Region) |
| Capture frame rate | 30/60 fps — applies to both the shared picture and recordings | 30 fps |
| Launch at login | Start with macOS (app bundle only) | off |
| Show Dock icon while active | Dock, ⌘-Tab and Force Quit presence while sharing or settings open | off |
| Version | Current version + build for support | — |

The **preview window** docks outside the region (right → left → below →
above, wherever there's free space) so it never covers what you're
sharing. Drag it anywhere by its picture (the ≡ grabber marks the spot),
resize it from the edges — the region's aspect ratio is kept — and use the
pause button in its top-right corner to pause/resume sharing even with the
hotbar hidden. It always floats above the dimming. The choice persists.

Follow mode itself is enabled per-session from the menu bar:
**Follow → Active Window / Cursor**.

## Appearance

| Setting | Effect | Default |
| --- | --- | --- |
| Dim screen outside region | Local dimming overlay | on |
| Dim amount | 0–90 % black outside the region | 60 % |
| Highlight cursor | Halo around the cursor — visible to viewers only | on |
| Show click ripples | Click animation — viewers only | on |
| Show border around region | Frame just outside the region | on |
| Border color / style / thickness / radius | Any color incl. opacity · solid, dashed, dotted · 1–10 pt · 0–30 pt | red · dashed · 3 pt · 8 pt |

Dimming and border are local-only: they're excluded from what viewers see.

## Privacy

| Setting | Effect | Default |
| --- | --- | --- |
| When paused, viewers see | Frozen last frame, or a blurred privacy screen with a slashed-eye note | Privacy screen |
| Hide notification banners from viewers | Notification Center is excluded from the capture — banners stay visible on your screen but never appear in the shared picture | on |
| Hidden apps | Windows of the apps you add never appear in the shared picture; viewers see what's behind them. “Add App…” opens a searchable list of installed apps (sensitive apps suggested first, Browse… for unusual locations). Changes apply live | empty |

## Recording

| Setting | Effect | Default |
| --- | --- | --- |
| Save recordings to | Folder for .mp4 recordings | ~/Movies/OutcutShare |

## Presets

Rename or delete saved regions. Save new ones while sharing via menu bar →
*Presets → Save Current Region as Preset…*. The first nine are shared
instantly with ⌃⌥⌘1–9; presets remember their share mode and fall back to
the best-matching screen if their display is gone.

## Shortcuts

See [hotkeys.md](hotkeys.md).
