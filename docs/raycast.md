# Raycast extension & the outcutshare:// URL scheme

Trigger Outcut Share from [Raycast](https://raycast.com) — or from any
automation tool, via `outcutshare://` deep links. Style and appearance
settings stay in the app; this is about the actions you reach for
mid-presentation.

## Setup

You need Raycast and Node ≥ 20. Then:

```
cd raycast && npm install && npm run dev
```

`npm run dev` imports the extension into Raycast in development mode and
opens it. The extension **stays available after you quit the dev server**
(Ctrl-C) — re-run it only to pick up code changes. Commands appear under
"Outcut Share" in the Raycast root search; assign aliases or hotkeys to
them in Raycast → Settings → Extensions like for any command.

## Commands

| Command | Does |
| --- | --- |
| Share Last Region | Re-share the most recent region (⌃⌥⌘L equivalent) |
| Select Region & Share | Drag-selection overlay — or starts the Virtual Monitor when that share mode is active |
| Share Preset | Lists your saved presets by name; Enter shares one |
| Stop Sharing | End the session |
| Pause / Resume Sharing | Freeze or blur what viewers see |
| Start / Stop Recording | Record the region to .mp4 (only while sharing) |
| Set Follow Mode | Off / Active Window / Cursor, current value check-marked |
| Set Share Mode | Hidden Window / Virtual Display / Virtual Monitor — applies while not sharing |
| Toggle Preview Window | The floating "what viewers see" panel |
| Toggle Hotbar | The floating quick-action bar |
| Toggle Cursor Highlights | Cursor halo + click ripples (viewers only) |
| Toggle Dimming | Local dim outside the region |

The list commands read the app's saved state directly, so they work even
while the app isn't running — opening an entry launches it.

## The URL scheme

Every command above is a deep link; `open "outcutshare://…"` from a
terminal, script, Shortcuts, Alfred, … does the same thing. The app is
launched automatically if it isn't running.

| URL | Action |
| --- | --- |
| `outcutshare://select` | Start selection (or the Virtual Monitor, mode-dependent) |
| `outcutshare://share-last` | Re-share the last region |
| `outcutshare://preset?id=UUID` | Share a preset by id |
| `outcutshare://preset?name=NAME` | …or by name (exact match first, then case-insensitive; id wins when both are given) |
| `outcutshare://stop` | Stop sharing (also dismisses an open selection overlay) |
| `outcutshare://pause` | Toggle pause — no-op while not sharing |
| `outcutshare://record` | Toggle recording — no-op while not sharing |
| `outcutshare://follow?mode=off\|activeWindow\|cursor` | Set follow mode |
| `outcutshare://share-mode?mode=virtualDisplay\|hiddenWindow\|virtualMonitor` | Switch share mode — **only while not sharing**; otherwise the app shows an alert |
| `outcutshare://toggle?option=preview\|hotbar\|cursorHighlights\|dimming` | Flip a presenter option |

Command and parameter values are case-insensitive; unknown or malformed
URLs are ignored. An unknown preset shows an alert naming the query.

## Caveats

- Deep links reach whichever copy of the app LaunchServices registered
  last — after moving or updating the app, launch it once by hand so the
  scheme points at the right copy.
- Raycast's HUD confirms what was *requested*, not what happened — the
  link is one-way. Failures that matter (unknown preset, mode switch
  while sharing) surface as alerts from the app itself.
