# Outcut Share Creative App Icon Variations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five substantially more original app-icon PNG concepts while preserving the existing six concepts unchanged.

**Architecture:** Generate each concept independently with the built-in ChatGPT image generator and no reference-image inputs. Copy the accepted outputs into `app-icon-concepts/`, normalize them to 1024 × 1024, then inspect full-size and 64px comparison sheets before committing.

**Tech Stack:** Built-in ChatGPT image generation, ImageMagick, shell validation, Git

## Global Constraints

- Keep every existing file in `app-icon-concepts/`.
- Do not use the six supplied inspiration images as generation inputs.
- Each new concept must use a distinct metaphor, silhouette, and dominant palette.
- Each final concept must be a flattened 1024 × 1024 PNG.
- No text, letters, numbers, trademarks, watermarks, isometric scenes, pedestals, or floor shadows.
- Do not modify application source files.

---

### Task 1: Preserve the Existing Set and Record Prompts

**Files:**
- Create: `app-icon-concepts/prompts-creative.md`
- Create: `/tmp/outcut-share-existing-icons.sha256`

**Interfaces:**
- Consumes: existing `app-icon-concepts/01-*.png` through `06-*.png`
- Produces: exact prompt record and preservation hashes used by Task 3

- [ ] **Step 1: Hash the existing six PNGs**

Run:

```bash
shasum -a 256 app-icon-concepts/0[1-6]-*.png \
  > /tmp/outcut-share-existing-icons.sha256
```

Expected: six hash lines.

- [ ] **Step 2: Write the five generation prompts**

Create `app-icon-concepts/prompts-creative.md` with one complete `logo-brand`
prompt for Portal Cut, Relay Ribbon, Prism Slice, Magnetic Crop, and Broadcast
Aperture. Each prompt must restate the no-reference-input rule and the shared
avoid list.

- [ ] **Step 3: Validate the prompt record**

Run:

```bash
test "$(rg -c '^## ' app-icon-concepts/prompts-creative.md)" -eq 5
rg -n 'Primary request:|Color palette:|Constraints:|Avoid:' \
  app-icon-concepts/prompts-creative.md
```

Expected: five headings and all four prompt fields for each concept.

### Task 2: Generate Five Independent PNG Concepts

**Files:**
- Create: `app-icon-concepts/07-portal-cut.png`
- Create: `app-icon-concepts/08-relay-ribbon.png`
- Create: `app-icon-concepts/09-prism-slice.png`
- Create: `app-icon-concepts/10-magnetic-crop.png`
- Create: `app-icon-concepts/11-broadcast-aperture.png`

**Interfaces:**
- Consumes: five prompts from `app-icon-concepts/prompts-creative.md`
- Produces: five independent raster icon candidates for Task 3

- [ ] **Step 1: Generate Portal Cut**

Use one built-in image-generation call with no referenced images. Copy the
accepted output to `app-icon-concepts/07-portal-cut.png`.

- [ ] **Step 2: Generate Relay Ribbon**

Use a separate built-in image-generation call with no referenced images. Copy
the accepted output to `app-icon-concepts/08-relay-ribbon.png`.

- [ ] **Step 3: Generate Prism Slice**

Use a separate built-in image-generation call with no referenced images. Copy
the accepted output to `app-icon-concepts/09-prism-slice.png`.

- [ ] **Step 4: Generate Magnetic Crop**

Use a separate built-in image-generation call with no referenced images. Copy
the accepted output to `app-icon-concepts/10-magnetic-crop.png`.

- [ ] **Step 5: Generate Broadcast Aperture**

Use a separate built-in image-generation call with no referenced images. Copy
the accepted output to `app-icon-concepts/11-broadcast-aperture.png`.

### Task 3: Normalize, Compare, and Verify

**Files:**
- Modify: `app-icon-concepts/07-portal-cut.png`
- Modify: `app-icon-concepts/08-relay-ribbon.png`
- Modify: `app-icon-concepts/09-prism-slice.png`
- Modify: `app-icon-concepts/10-magnetic-crop.png`
- Modify: `app-icon-concepts/11-broadcast-aperture.png`
- Create: `app-icon-concepts/contact-sheet-creative.png`
- Create: `/tmp/outcut-share-creative-icons-small.png`

**Interfaces:**
- Consumes: Tasks 1–2 outputs
- Produces: final normalized PNGs and visual-review sheets

- [ ] **Step 1: Normalize every new icon**

Run:

```bash
for icon_path in app-icon-concepts/{07,08,09,10,11}-*.png
do
  dimensions=$(magick identify -format '%wx%h' "$icon_path")
  if [ "$dimensions" != "1024x1024" ]; then
    normalized="${icon_path%.png}-normalized.png"
    magick "$icon_path" -resize '1024x1024^' -gravity center \
      -extent 1024x1024 "$normalized"
    mv "$normalized" "$icon_path"
  fi
done
```

- [ ] **Step 2: Build full-size and 64px comparison sheets**

Run:

```bash
montage app-icon-concepts/{07,08,09,10,11}-*.png \
  -thumbnail 360x360 -tile 3x2 -geometry +28+32 \
  -background '#18181c' app-icon-concepts/contact-sheet-creative.png

montage app-icon-concepts/{07,08,09,10,11}-*.png \
  -thumbnail 64x64 -tile 3x2 -geometry +18+20 \
  -background '#18181c' /tmp/outcut-share-creative-icons-small.png
```

- [ ] **Step 3: Inspect and reject weak outputs**

Inspect every icon and both sheets. Regenerate any output containing text,
watermarks, a literal copy of concepts 01–06, weak 64px contrast, or a
perspective product scene.

- [ ] **Step 4: Verify artifact preservation and dimensions**

Run:

```bash
shasum -a 256 -c /tmp/outcut-share-existing-icons.sha256
test "$(find app-icon-concepts -maxdepth 1 -type f \
  \( -name '0[7-9]-*.png' -o -name '1[01]-*.png' \) \
  | wc -l | tr -d ' ')" -eq 5
for icon_path in app-icon-concepts/{07,08,09,10,11}-*.png
do
  test "$(magick identify -format '%wx%h' "$icon_path")" = "1024x1024"
done
test -s app-icon-concepts/contact-sheet-creative.png
git diff --check
```

- [ ] **Step 5: Run the project test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit only the new icon artifacts**

Run:

```bash
git add app-icon-concepts
git commit -m "art: add creative Outcut Share icon variations"
```
