# Outcut Share App Icon Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate eight polished PNG candidates across four approved Outcut Share icon concepts, select one final per concept, and deliver the complete set with contact sheets in a local project folder.

**Architecture:** Use one built-in ChatGPT image-generation call per distinct candidate, with two deliberately different prompts for each concept. Preserve every generated candidate under `app-icon-concepts/variants/`, copy the strongest candidate for each concept to the four stable final filenames, then use ImageMagick only for format normalization, thumbnails, and contact-sheet assembly.

**Tech Stack:** Built-in ChatGPT image generator, PNG, ImageMagick (`magick` and `montage`), macOS shell utilities, Codex image inspection.

## Global Constraints

- Produce four substantially different concepts: Convex Ultrawide, Spectrum Slice, Signal Window, and Tile Lift.
- Produce two candidates per concept and keep all eight candidates.
- Deliver 1024 × 1024 pixel square, full-bleed PNG artwork.
- Keep primary content centered with optical safe space for the macOS rounded-rectangle mask.
- Use no text, letters, trademarks, watermarks, or replicas of Apple hardware.
- Use simple bold silhouettes, a small number of layers, rounded geometry, controlled depth, and restrained translucent glass inspired by macOS 26.
- Use different palettes and different primary metaphors across the four concepts.
- The Convex Ultrawide physical shell must bow outward toward the viewer, while every internal element remains straight and unwarped.
- Deliver flattened PNG previews, not Icon Composer layer files.
- Do not modify Outcut Share application code or bundle metadata.

---

## File Structure

- Create: `app-icon-concepts/prompts.md` — records the exact eight generation prompts and the built-in generation path.
- Create: `app-icon-concepts/variants/01-convex-ultrawide-v1.png` — detailed convex ultrawide candidate.
- Create: `app-icon-concepts/variants/01-convex-ultrawide-v2.png` — simplified convex ultrawide candidate.
- Create: `app-icon-concepts/variants/02-spectrum-slice-v1.png` — luminous oblique slice candidate.
- Create: `app-icon-concepts/variants/02-spectrum-slice-v2.png` — minimal prism-window candidate.
- Create: `app-icon-concepts/variants/03-signal-window-v1.png` — glass broadcast-window candidate.
- Create: `app-icon-concepts/variants/03-signal-window-v2.png` — simplified live-signal candidate.
- Create: `app-icon-concepts/variants/04-tile-lift-v1.png` — warm modular desktop candidate.
- Create: `app-icon-concepts/variants/04-tile-lift-v2.png` — reduced floating-pane candidate.
- Create: `app-icon-concepts/01-convex-ultrawide.png` — selected final for concept 1.
- Create: `app-icon-concepts/02-spectrum-slice.png` — selected final for concept 2.
- Create: `app-icon-concepts/03-signal-window.png` — selected final for concept 3.
- Create: `app-icon-concepts/04-tile-lift.png` — selected final for concept 4.
- Create: `app-icon-concepts/contact-sheet-all.png` — all eight candidates side by side.
- Create: `app-icon-concepts/contact-sheet.png` — four selected finals side by side.

### Task 1: Record Prompts and Prepare the Delivery Folder

**Files:**
- Create: `app-icon-concepts/prompts.md`
- Create directory: `app-icon-concepts/variants/`

**Interfaces:**
- Consumes: Approved design spec at `docs/superpowers/specs/2026-07-27-outcut-share-app-icon-design.md`.
- Produces: Eight exact prompt specifications and the directory structure used by Tasks 2–6.

- [ ] **Step 1: Create the delivery directory**

Run:

```bash
mkdir -p app-icon-concepts/variants
```

Expected: both `app-icon-concepts/` and `app-icon-concepts/variants/` exist.

- [ ] **Step 2: Write all eight exact prompts to `prompts.md`**

Use `apply_patch` to create the file with:

- the built-in image generator named as the generation path;
- one structured `logo-brand` prompt per candidate;
- the shared full-bleed, no-text, no-watermark, no-Apple-hardware constraints;
- explicit convex-shell and straight-interior invariants in both Ultrawide prompts;
- separate palette and composition instructions for every other concept.

Expected: `rg -n "^## " app-icon-concepts/prompts.md` shows eight candidate headings.

- [ ] **Step 3: Review prompt distinction**

Run:

```bash
rg -n "Primary request:|Color palette:|Constraints:|Avoid:" app-icon-concepts/prompts.md
```

Expected: each candidate has a unique primary request and the four concepts have distinct palette descriptions.

### Task 2: Generate and Validate Convex Ultrawide Candidates

**Files:**
- Create: `app-icon-concepts/variants/01-convex-ultrawide-v1.png`
- Create: `app-icon-concepts/variants/01-convex-ultrawide-v2.png`

**Interfaces:**
- Consumes: the two Convex Ultrawide prompts from `app-icon-concepts/prompts.md`.
- Produces: two PNG candidates for Task 6 selection.

- [ ] **Step 1: Generate candidate v1**

Call the built-in image generator once with the detailed Convex Ultrawide v1 prompt. Copy the returned PNG into:

```text
app-icon-concepts/variants/01-convex-ultrawide-v1.png
```

- [ ] **Step 2: Generate candidate v2**

Call the built-in image generator once with the simplified Convex Ultrawide v2 prompt. Copy the returned PNG into:

```text
app-icon-concepts/variants/01-convex-ultrawide-v2.png
```

- [ ] **Step 3: Inspect both candidates**

Open both PNGs with the local image viewer and reject any candidate where:

- the monitor shell does not visibly bulge outward toward the viewer;
- the internal screen, dashed rectangle, content lines, cursor, or share glyph curves;
- the monitor resembles a specific Apple product;
- text or watermark appears.

- [ ] **Step 4: Normalize dimensions only if required**

Run:

```bash
for icon_path in \
  app-icon-concepts/variants/01-convex-ultrawide-v1.png \
  app-icon-concepts/variants/01-convex-ultrawide-v2.png
do
  icon_dimensions=$(magick identify -format '%wx%h' "$icon_path")
  if [ "$icon_dimensions" != "1024x1024" ]; then
    normalized_path="${icon_path%.png}-normalized.png"
    magick "$icon_path" -resize 1024x1024^ -gravity center -extent 1024x1024 "$normalized_path"
    mv "$normalized_path" "$icon_path"
  fi
done
magick identify -format '%f %wx%h\n' app-icon-concepts/variants/01-convex-ultrawide-v*.png
```

Expected: both output lines end in `1024x1024`.

### Task 3: Generate and Validate Spectrum Slice Candidates

**Files:**
- Create: `app-icon-concepts/variants/02-spectrum-slice-v1.png`
- Create: `app-icon-concepts/variants/02-spectrum-slice-v2.png`

**Interfaces:**
- Consumes: the two Spectrum Slice prompts from `app-icon-concepts/prompts.md`.
- Produces: two PNG candidates for Task 6 selection.

- [ ] **Step 1: Generate candidate v1**

Call the built-in image generator once with the luminous oblique Spectrum Slice v1 prompt and copy the returned PNG to:

```text
app-icon-concepts/variants/02-spectrum-slice-v1.png
```

- [ ] **Step 2: Generate candidate v2**

Call the built-in image generator once with the reduced prism-window Spectrum Slice v2 prompt and copy the returned PNG to:

```text
app-icon-concepts/variants/02-spectrum-slice-v2.png
```

- [ ] **Step 3: Inspect both candidates**

Open both PNGs and reject any candidate that reads primarily as a photo editor, rainbow brand, deck of cards, or generic image stack. Confirm that a rectangular live layer is visibly extracted from a larger dark plane and that no text or watermark appears.

- [ ] **Step 4: Normalize dimensions only if required**

Run:

```bash
for icon_path in \
  app-icon-concepts/variants/02-spectrum-slice-v1.png \
  app-icon-concepts/variants/02-spectrum-slice-v2.png
do
  icon_dimensions=$(magick identify -format '%wx%h' "$icon_path")
  if [ "$icon_dimensions" != "1024x1024" ]; then
    normalized_path="${icon_path%.png}-normalized.png"
    magick "$icon_path" -resize 1024x1024^ -gravity center -extent 1024x1024 "$normalized_path"
    mv "$normalized_path" "$icon_path"
  fi
done
magick identify -format '%f %wx%h\n' app-icon-concepts/variants/02-spectrum-slice-v*.png
```

Expected: both output lines end in `1024x1024`.

### Task 4: Generate and Validate Signal Window Candidates

**Files:**
- Create: `app-icon-concepts/variants/03-signal-window-v1.png`
- Create: `app-icon-concepts/variants/03-signal-window-v2.png`

**Interfaces:**
- Consumes: the two Signal Window prompts from `app-icon-concepts/prompts.md`.
- Produces: two PNG candidates for Task 6 selection.

- [ ] **Step 1: Generate candidate v1**

Call the built-in image generator once with the glass broadcast-window Signal Window v1 prompt and copy the returned PNG to:

```text
app-icon-concepts/variants/03-signal-window-v1.png
```

- [ ] **Step 2: Generate candidate v2**

Call the built-in image generator once with the simplified live-signal Signal Window v2 prompt and copy the returned PNG to:

```text
app-icon-concepts/variants/03-signal-window-v2.png
```

- [ ] **Step 3: Inspect both candidates**

Open both PNGs and confirm that a selected rectangular window emits two or three restrained signal arcs. Reject Wi-Fi, AirPlay, upload-button, antenna-tower, text, or watermark interpretations.

- [ ] **Step 4: Normalize dimensions only if required**

Run:

```bash
for icon_path in \
  app-icon-concepts/variants/03-signal-window-v1.png \
  app-icon-concepts/variants/03-signal-window-v2.png
do
  icon_dimensions=$(magick identify -format '%wx%h' "$icon_path")
  if [ "$icon_dimensions" != "1024x1024" ]; then
    normalized_path="${icon_path%.png}-normalized.png"
    magick "$icon_path" -resize 1024x1024^ -gravity center -extent 1024x1024 "$normalized_path"
    mv "$normalized_path" "$icon_path"
  fi
done
magick identify -format '%f %wx%h\n' app-icon-concepts/variants/03-signal-window-v*.png
```

Expected: both output lines end in `1024x1024`.

### Task 5: Generate and Validate Tile Lift Candidates

**Files:**
- Create: `app-icon-concepts/variants/04-tile-lift-v1.png`
- Create: `app-icon-concepts/variants/04-tile-lift-v2.png`

**Interfaces:**
- Consumes: the two Tile Lift prompts from `app-icon-concepts/prompts.md`.
- Produces: two PNG candidates for Task 6 selection.

- [ ] **Step 1: Generate candidate v1**

Call the built-in image generator once with the warm modular-desktop Tile Lift v1 prompt and copy the returned PNG to:

```text
app-icon-concepts/variants/04-tile-lift-v1.png
```

- [ ] **Step 2: Generate candidate v2**

Call the built-in image generator once with the reduced floating-pane Tile Lift v2 prompt and copy the returned PNG to:

```text
app-icon-concepts/variants/04-tile-lift-v2.png
```

- [ ] **Step 3: Inspect both candidates**

Open both PNGs and confirm that one warm pane visibly detaches from a dim modular desktop. Reject generic window-manager grids, calculator-like layouts, text, or watermarks.

- [ ] **Step 4: Normalize dimensions only if required**

Run:

```bash
for icon_path in \
  app-icon-concepts/variants/04-tile-lift-v1.png \
  app-icon-concepts/variants/04-tile-lift-v2.png
do
  icon_dimensions=$(magick identify -format '%wx%h' "$icon_path")
  if [ "$icon_dimensions" != "1024x1024" ]; then
    normalized_path="${icon_path%.png}-normalized.png"
    magick "$icon_path" -resize 1024x1024^ -gravity center -extent 1024x1024 "$normalized_path"
    mv "$normalized_path" "$icon_path"
  fi
done
magick identify -format '%f %wx%h\n' app-icon-concepts/variants/04-tile-lift-v*.png
```

Expected: both output lines end in `1024x1024`.

### Task 6: Select Finals and Build Contact Sheets

**Files:**
- Create: `app-icon-concepts/01-convex-ultrawide.png`
- Create: `app-icon-concepts/02-spectrum-slice.png`
- Create: `app-icon-concepts/03-signal-window.png`
- Create: `app-icon-concepts/04-tile-lift.png`
- Create: `app-icon-concepts/contact-sheet-all.png`
- Create: `app-icon-concepts/contact-sheet.png`

**Interfaces:**
- Consumes: all eight PNG candidates from Tasks 2–5.
- Produces: the four stable final concept filenames and two review sheets.

- [ ] **Step 1: Build the all-candidate contact sheet**

Run:

```bash
montage app-icon-concepts/variants/*.png \
  -thumbnail 360x360 \
  -tile 4x2 \
  -geometry +28+36 \
  -background '#10131a' \
  app-icon-concepts/contact-sheet-all.png
```

Expected: a two-row sheet containing eight distinct icon candidates.

- [ ] **Step 2: Inspect at full and small sizes**

Open `contact-sheet-all.png`, then create and inspect a small-size sheet:

```bash
montage app-icon-concepts/variants/*.png \
  -thumbnail 96x96 \
  -tile 4x2 \
  -geometry +18+22 \
  -background '#10131a' \
  /tmp/outcut-share-icon-small-sheet.png
```

Expected: each candidate keeps a recognizable primary silhouette at 96 × 96.

- [ ] **Step 3: Copy the strongest candidate for each concept**

For each concept, compare both candidates against its explicit rejection
criteria. Run exactly one command from each pair:

```bash
# Convex Ultrawide — choose one:
cp app-icon-concepts/variants/01-convex-ultrawide-v1.png app-icon-concepts/01-convex-ultrawide.png
cp app-icon-concepts/variants/01-convex-ultrawide-v2.png app-icon-concepts/01-convex-ultrawide.png

# Spectrum Slice — choose one:
cp app-icon-concepts/variants/02-spectrum-slice-v1.png app-icon-concepts/02-spectrum-slice.png
cp app-icon-concepts/variants/02-spectrum-slice-v2.png app-icon-concepts/02-spectrum-slice.png

# Signal Window — choose one:
cp app-icon-concepts/variants/03-signal-window-v1.png app-icon-concepts/03-signal-window.png
cp app-icon-concepts/variants/03-signal-window-v2.png app-icon-concepts/03-signal-window.png

# Tile Lift — choose one:
cp app-icon-concepts/variants/04-tile-lift-v1.png app-icon-concepts/04-tile-lift.png
cp app-icon-concepts/variants/04-tile-lift-v2.png app-icon-concepts/04-tile-lift.png
```

Expected: four stable final filenames exist, and each is byte-identical to the
chosen candidate for its concept.

- [ ] **Step 4: Build the selected-finals contact sheet**

Run:

```bash
montage \
  app-icon-concepts/01-convex-ultrawide.png \
  app-icon-concepts/02-spectrum-slice.png \
  app-icon-concepts/03-signal-window.png \
  app-icon-concepts/04-tile-lift.png \
  -thumbnail 420x420 \
  -tile 4x1 \
  -geometry +28+34 \
  -background '#10131a' \
  app-icon-concepts/contact-sheet.png
```

Expected: one row with the four selected concepts in approved order.

- [ ] **Step 5: Verify PNG count, dimensions, and format**

Run:

```bash
find app-icon-concepts -type f -name '*.png' -print | sort
magick identify -format '%f %m %wx%h\n' app-icon-concepts/variants/*.png app-icon-concepts/0*.png
```

Expected:

- 14 PNG files: eight candidates, four finals, and two contact sheets;
- all eight candidates and four finals report `PNG 1024x1024`;
- no unrelated project files changed during generation.

- [ ] **Step 6: Final visual inspection**

Open all four selected finals and `contact-sheet.png`. Confirm:

- the four structures and palettes are visibly different;
- no generated text, watermark, accidental logo, or mockup framing appears;
- the Convex Ultrawide shell is convex and all interior content is uncurved;
- each icon remains legible when represented at small size.

- [ ] **Step 7: Commit the delivered artwork**

Run:

```bash
git add app-icon-concepts
git commit -m "art: add Outcut Share icon concepts"
```

Expected: the commit contains the prompt record, eight candidates, four selected finals, and two contact sheets.
