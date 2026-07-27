# Outcut Share App Icon Concept Design

Date: 2026-07-27

## Goal

Create four substantially different app-icon concepts for Outcut Share as
actual PNG artwork. The set should feel native beside macOS 26 icons while
communicating the app's central promise: isolate one region of an ultrawide
screen and expose it as a focused shareable output.

This is concept-art delivery only. The work does not add an icon to the app
bundle or change application code.

## Project Findings

Outcut Share is a native Swift/AppKit menu-bar utility. A user draws or recalls
a rectangular screen region; the app captures that region and presents it as a
virtual display or hidden shareable window. Its existing interface uses:

- a dashed selection rectangle;
- dimmed content outside the selected region;
- a separate display or window as the shared output;
- cursor interaction and live sharing;
- a configurable border whose current default happens to be red, but red is
  not a brand color.

The repository does not currently contain an app-icon asset, and its bundle
metadata does not point to one.

## Shared Visual Construction

All four concepts will use the following common production rules:

- 1024 × 1024 pixel PNG;
- square, full-bleed icon artwork with centered primary content and generous
  optical safe space for the macOS rounded-rectangle mask;
- no text, letters, trademarks, watermarks, or replicas of Apple hardware;
- simple, bold silhouettes with a small number of distinct layers;
- rounded geometry, controlled depth, and restrained translucent glass
  material inspired by the macOS 26 visual language;
- strong contrast and recognizable structure when downscaled;
- different palettes and different primary metaphors across the set;
- flattened PNG previews suitable for review, not native Icon Composer layer
  files.

## Concept 1: Convex Ultrawide

A generic ultrawide monitor has a physical shell that bows outward toward the
viewer as a clearly convex glass form. The center appears closer than the
sides, helped by a restrained central highlight and receding side edges.

Everything rendered inside the physical monitor remains optically flat:

- the display surface is a straight, axis-aligned rounded rectangle;
- the dashed selected region is straight and rectangular;
- simple content lines are unwarped;
- a crisp pointer cursor approaches a compact share-arrow glyph.

The palette uses midnight blue, cool cyan, violet, and a small warm selection
accent. The monitor must remain generic and must not resemble a specific Apple
product.

## Concept 2: Spectrum Slice

A luminous rectangular spectrum layer lifts cleanly out of a dark oblique
display plane. The extracted layer is the focal object, expressing both
"cutting out" and converting part of a screen into a separate live surface.

The composition uses angular spatial depth rather than a monitor silhouette.
The palette moves from cyan through violet to warm amber. The result should feel
precise and premium, not like a photo editor, rainbow logo, or stack of cards.

## Concept 3: Signal Window

A compact selected window sits inside a calm glass field and emits two or three
restrained live-signal arcs from one side. This concept emphasizes that the
chosen region is actively being shared.

The palette uses deep teal with mint and lime highlights. The signal should
feel like a live broadcast from a focused window, avoiding a generic upload
button, Wi-Fi logo, or AirPlay replica.

## Concept 4: Tile Lift

A dim modular desktop is suggested by a few simple glass panes. One warm,
bright rectangular pane detaches and floats above the others, making "share
one part, not everything" tangible.

The palette uses dark aubergine-brown with amber, peach, and ember highlights.
The lifted pane needs a strong silhouette and clear depth separation without
becoming a generic window-management or grid-layout icon.

## Generation and Selection

Each concept will be generated in a separate built-in image-generation call
using its own prompt. Separate calls are required because these are different
assets rather than variations of one prompt.

If a first render misses a defining constraint, one targeted iteration may be
used for that concept while repeating all invariants. In particular, the
Convex Ultrawide render must be rejected if any screen content or the selected
rectangle is curved.

Final files will be saved as:

- `app-icon-concepts/01-convex-ultrawide.png`
- `app-icon-concepts/02-spectrum-slice.png`
- `app-icon-concepts/03-signal-window.png`
- `app-icon-concepts/04-tile-lift.png`

A contact sheet will also be saved as
`app-icon-concepts/contact-sheet.png` to present the set side by side.

## Validation

Before delivery:

1. Confirm all four files are valid 1024 × 1024 PNGs.
2. Inspect each at full size for composition, unwanted text, watermarks, and
   metaphor drift.
3. Inspect downscaled previews to check silhouette and small-size legibility.
4. Confirm the four concepts remain visibly different in structure and color.
5. Confirm the Convex Ultrawide has a convex physical shell with straight,
   unwarped internal content.
6. Confirm the deliverables exist in `app-icon-concepts/` and do not overwrite
   unrelated project assets.
