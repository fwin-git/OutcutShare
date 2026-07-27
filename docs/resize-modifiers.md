# Selection & resize modifiers

![All selection modes in action — freeform, standard sizes, aspect lock, Space move, window pick](media/demo-region.gif)

The same modifier language works in both overlays: the initial **selection**
(Select Region & Share) and the later **adjustment** (Move / Resize Region,
⌃⌥⌘M). They follow the macOS screenshot conventions.

## While selecting

| Input | Effect |
| --- | --- |
| Drag | Draw the region |
| **Space** (before dragging) | Window-pick mode: hover highlights a window, click takes its bounds. Space again returns to dragging |
| **Space** (while dragging) | Freezes the selection's size and moves it with the mouse |
| **⇧ Shift** (while dragging) | Locks the current aspect ratio |
| **⌃ Ctrl** (while dragging) | Snaps to viewer-friendly sizes — 1280×720, 1600×900, 1920×1080 — previewed as colored outlines with resolution labels |
| **Esc** | Cancel |

## While adjusting (Move / Resize)

- Drag **inside** the region to move it; arrow keys nudge 1 pt (⇧ = 10 pt).
- Drag a **corner** to resize (18 pt grab padding).
- In **Hidden Window mode** (free aspect) the four **edges** resize too, with
  a 14 pt grab band on both sides of the border. In Virtual Display mode
  resizing is corner-only and locked to the region's aspect ratio.
- **Space** (idle) opens the same window-pick mode: click a window to snap
  the region to its bounds and commit.
- **Space** (mid-resize) freezes the shape and moves it; release to continue
  resizing from the new spot.
- **⇧ / ⌃** work like in selection (free-aspect mode only).
- **Return** commits, **Esc** reverts position *and* size.

Everything applies live — viewers see the region pan/resize without the
share ever interrupting.
