# Outcut Share App Icon Generation V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the rejected first icon set and generate six original, compact, reference-guided Outcut Share PNG concepts with a new contact sheet.

**Architecture:** Treat all six attached images as style and composition references, never as edit targets. Use one built-in ChatGPT image-generation call per original concept, copy each result into a freshly recreated `app-icon-concepts/` folder, normalize every icon to 1024 × 1024, then create and visually inspect full-size and small-size contact sheets.

**Tech Stack:** Built-in ChatGPT image generator, PNG, ImageMagick (`magick` and `montage`), Git.

## Global Constraints

- Delete the previous `app-icon-concepts/` artwork before saving new candidates.
- Use all six attached images only as style and composition references.
- Produce six original concepts named Focus Frame, Cursor Lift, Shared Pane Stack, Convex Window, Region Out, and Split Selection.
- Use a front-facing compact composition, one rounded enclosure, and one bold centered metaphor.
- Use two to five large shapes, controlled color, and gentle bevel or translucent depth.
- Do not use an isometric scene, pedestal, cast floor shadow, deep ambient void, cinematic lighting, text, letters, numbers, logos, trademarks, or watermarks.
- Deliver flattened 1024 × 1024 PNGs without changing application code or bundle metadata.
- Preserve unrelated working-tree changes.

---

### Task 1: Remove the Rejected Set and Record New Prompts

**Files:**
- Delete: `app-icon-concepts/`
- Create: `app-icon-concepts/prompts.md`

**Interfaces:**
- Consumes: `docs/superpowers/specs/2026-07-27-outcut-share-app-icon-design-v2.md`
- Produces: a clean delivery folder and six exact prompts for Task 2.

- [ ] **Step 1: Confirm the destructive target**

Run:

```bash
find /Users/reesz/Desktop/Fw/Projekte/tmp/screen-region-monitor-share/app-icon-concepts \
  -maxdepth 2 -type f -print | sort
```

Expected: only the rejected first-pass icon files, prompt record, and contact sheets are listed.

- [ ] **Step 2: Delete the rejected folder and recreate it empty**

Run:

```bash
rm -rf -- /Users/reesz/Desktop/Fw/Projekte/tmp/screen-region-monitor-share/app-icon-concepts
mkdir -p /Users/reesz/Desktop/Fw/Projekte/tmp/screen-region-monitor-share/app-icon-concepts
```

Expected: `find app-icon-concepts -mindepth 1 -print` produces no output.

- [ ] **Step 3: Write the exact six generation prompts**

Create `app-icon-concepts/prompts.md` with one `logo-brand` prompt for each
concept. Every prompt must:

- label Images 1–6 as style/composition references, not edit targets;
- repeat the compact front-facing and no-isometric constraints;
- describe the concept-specific glyph and palette from the V2 design spec;
- prohibit copying any reference's exact glyph or layout;
- prohibit text, watermark, exterior product mockups, and floating scene
  presentation.

Expected: `rg -n '^## ' app-icon-concepts/prompts.md` prints six headings.

### Task 2: Generate Six Reference-Guided Icons

**Files:**
- Create: `app-icon-concepts/01-focus-frame.png`
- Create: `app-icon-concepts/02-cursor-lift.png`
- Create: `app-icon-concepts/03-shared-pane-stack.png`
- Create: `app-icon-concepts/04-convex-window.png`
- Create: `app-icon-concepts/05-region-out.png`
- Create: `app-icon-concepts/06-split-selection.png`

**Interfaces:**
- Consumes: six prompts from `app-icon-concepts/prompts.md` and all six attached reference-image paths.
- Produces: six PNG files for Task 3 validation.

- [ ] **Step 1: Generate Focus Frame**

Call the built-in image generator with the Focus Frame prompt and these six
reference image paths:

```text
/var/folders/b9/9swzzx013j7dsgsn_ddk8qmc0000gn/T/clipboard-2026-07-27-115600-632B82A0.png
/var/folders/b9/9swzzx013j7dsgsn_ddk8qmc0000gn/T/clipboard-2026-07-27-115648-AD30C002.png
/var/folders/b9/9swzzx013j7dsgsn_ddk8qmc0000gn/T/clipboard-2026-07-27-115701-72CA763B.png
/var/folders/b9/9swzzx013j7dsgsn_ddk8qmc0000gn/T/clipboard-2026-07-27-115726-709F7BC8.png
/var/folders/b9/9swzzx013j7dsgsn_ddk8qmc0000gn/T/clipboard-2026-07-27-115812-806EAB74.png
/var/folders/b9/9swzzx013j7dsgsn_ddk8qmc0000gn/T/clipboard-2026-07-27-115817-5CE183F2.png
```

Copy the returned image to `app-icon-concepts/01-focus-frame.png`.

- [ ] **Step 2: Generate Cursor Lift**

Call the built-in image generator once with the Cursor Lift prompt and the same
six reference-image paths. Copy the result to
`app-icon-concepts/02-cursor-lift.png`.

- [ ] **Step 3: Generate Shared Pane Stack**

Call the built-in image generator once with the Shared Pane Stack prompt and
the same six reference-image paths. Copy the result to
`app-icon-concepts/03-shared-pane-stack.png`.

- [ ] **Step 4: Generate Convex Window**

Call the built-in image generator once with the Convex Window prompt and the
same six reference-image paths. Copy the result to
`app-icon-concepts/04-convex-window.png`.

- [ ] **Step 5: Generate Region Out**

Call the built-in image generator once with the Region Out prompt and the same
six reference-image paths. Copy the result to
`app-icon-concepts/05-region-out.png`.

- [ ] **Step 6: Generate Split Selection**

Call the built-in image generator once with the Split Selection prompt and the
same six reference-image paths. Copy the result to
`app-icon-concepts/06-split-selection.png`.

### Task 3: Normalize and Visually Validate

**Files:**
- Modify: `app-icon-concepts/01-focus-frame.png`
- Modify: `app-icon-concepts/02-cursor-lift.png`
- Modify: `app-icon-concepts/03-shared-pane-stack.png`
- Modify: `app-icon-concepts/04-convex-window.png`
- Modify: `app-icon-concepts/05-region-out.png`
- Modify: `app-icon-concepts/06-split-selection.png`
- Create: `app-icon-concepts/contact-sheet.png`

**Interfaces:**
- Consumes: all six generated PNGs.
- Produces: normalized icons and the final review sheet.

- [ ] **Step 1: Normalize all six icons**

Run:

```bash
for icon_path in app-icon-concepts/0*.png
do
  icon_dimensions=$(magick identify -format '%wx%h' "$icon_path")
  if [ "$icon_dimensions" != "1024x1024" ]; then
    normalized_path="${icon_path%.png}-normalized.png"
    magick "$icon_path" -resize 1024x1024^ -gravity center -extent 1024x1024 "$normalized_path"
    mv "$normalized_path" "$icon_path"
  fi
done
magick identify -format '%f %m %wx%h\n' app-icon-concepts/0*.png
```

Expected: six output lines ending in `PNG 1024x1024`.

- [ ] **Step 2: Build the full-size contact sheet**

Run:

```bash
montage app-icon-concepts/0*.png \
  -thumbnail 360x360 \
  -tile 3x2 \
  -geometry +28+32 \
  -background '#18181c' \
  app-icon-concepts/contact-sheet.png
```

Expected: a three-column, two-row sheet containing the six new icons.

- [ ] **Step 3: Build the small-size validation sheet**

Run:

```bash
montage app-icon-concepts/0*.png \
  -thumbnail 64x64 \
  -tile 3x2 \
  -geometry +18+20 \
  -background '#18181c' \
  /tmp/outcut-share-icons-v2-small.png
```

Expected: all six metaphors remain recognizable at 64 × 64.

- [ ] **Step 4: Perform visual rejection checks**

Inspect every icon, `contact-sheet.png`, and the small-size sheet. Reject and
regenerate any image that:

- copies a reference's distinctive glyph or exact layout;
- contains text, numbers, watermark, or accidental logo;
- shows a floating object in a cinematic void or an isometric scene;
- loses the centered metaphor at 64 × 64;
- fails to communicate selection, extraction, or sharing.

### Task 4: Verify and Commit the Replacement Set

**Files:**
- Create: six final icon PNGs, one contact sheet, and `prompts.md`.
- Delete: all files from the rejected first set.

**Interfaces:**
- Consumes: the validated V2 delivery folder.
- Produces: a clean committed replacement set.

- [ ] **Step 1: Verify file names and dimensions**

Run:

```bash
set -e
test "$(find app-icon-concepts -maxdepth 1 -type f -name '0*.png' | wc -l | tr -d ' ')" -eq 6
test "$(rg -c '^## ' app-icon-concepts/prompts.md)" -eq 6
for icon_path in app-icon-concepts/0*.png
do
  test "$(magick identify -format '%wx%h' "$icon_path")" = "1024x1024"
done
test -s app-icon-concepts/contact-sheet.png
git diff --check
```

Expected: exit code 0.

- [ ] **Step 2: Verify unrelated changes remain untouched**

Run:

```bash
git status --short
```

Expected: only the icon replacement, V2 design documentation, and V2 plan are
new or modified by this task.

- [ ] **Step 3: Run the full project test suite**

Run:

```bash
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 4: Commit only the replacement artwork and plan**

Run:

```bash
git add app-icon-concepts docs/superpowers/plans/2026-07-27-outcut-share-app-icon-generation-v2.md
git commit -m "art: replace Outcut Share icon concepts"
```

Expected: the commit records deletion of the rejected set and creation of the
six new icons, new contact sheet, prompt record, and execution plan.
