# Localization Contributor Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document Outcut Share's localization architecture and workflow, require future user-facing features to support every available language, and integrate the completed localization branch into `main`.

**Architecture:** Add one contributor-facing localization guide as the source of operational instructions, link it from existing documentation, and keep the concise policy invariant in `AGENTS.md`. Preserve the existing runtime and catalog implementation; this change documents and enforces the established workflow without changing application behavior.

**Tech Stack:** Markdown, Apple String Catalogs, Swift/XCTest, zsh, Git.

## Global Constraints

- The supported locale identifiers are exactly `en`, `de`, `fr`, `es`, `zh-Hans`, `ja`, `pt-BR`, `ko`, `zh-Hant`, and `it`.
- English remains the development language and fallback.
- Every new or changed user-facing feature must be finalized in every supported locale in the same change.
- Preserve placeholder signatures, brand identities, filenames, extensions, protocol values, and technical units where translation would change their meaning.
- Do not change application behavior, add dependencies, push, or release.
- Merge the verified feature branch into local `main` with a merge commit.

---

### Task 1: Add the Localization Contributor Guide

**Files:**

- Create: `docs/localization.md`
- Modify: `README.md`
- Modify: `docs/development.md`

**Interfaces:**

- Consumes: `Sources/OutcutShare/L10n.swift`, both catalogs under `Resources/Localization/`, `Support/Info.plist`, `LocalizationCatalogTests`, and both localization verification scripts.
- Produces: one discoverable contributor workflow for adding copy, adding a locale, and verifying packaged output.

- [ ] **Step 1: Write `docs/localization.md`**

Document the exact locale set; catalog/runtime data flow; responsibility of
each localization file; the workflow for adding or changing user-facing copy;
the workflow for adding a locale; placeholder, terminology, and technical
identity rules; and the static, test, build, packaged-runtime, and visual QA
commands.

- [ ] **Step 2: Link the guide from contributor entry points**

Add `Localization` to the README documentation table and a short localization
pointer in `docs/development.md`.

- [ ] **Step 3: Verify guide facts against repository contracts**

Run:

```bash
test -f docs/localization.md
rg -n 'pt-BR|zh-Hant|Scripts/verify-localizations.sh|LocalizationCatalogTests' \
  docs/localization.md
test "$(jq '.strings | length' Resources/Localization/Localizable.xcstrings)" = 257
```

Expected: the guide exists, names the locale and validation contracts, and
the documented application-key count is `257`.

---

### Task 2: Add the Agent Localization Invariant

**Files:**

- Modify: `AGENTS.md`

**Interfaces:**

- Consumes: the workflow defined in `docs/localization.md`.
- Produces: a concise instruction that future agents must localize all new or
  changed user-facing features for the complete supported locale set.

- [ ] **Step 1: Add a localization policy under code conventions**

Require user-facing strings to use `L10n.Key` and
`Resources/Localization/Localizable.xcstrings`, require finalized values for
all supported locales in the same feature change, and point to
`docs/localization.md` for the full workflow.

- [ ] **Step 2: Verify the policy is explicit**

Run:

```bash
rg -n 'Every new or changed user-facing feature|docs/localization.md' AGENTS.md
```

Expected: both the invariant and guide link are present.

---

### Task 3: Verify and Commit the Documentation

**Files:**

- Verify: `AGENTS.md`
- Verify: `README.md`
- Verify: `docs/development.md`
- Verify: `docs/localization.md`
- Verify: `docs/superpowers/plans/2026-07-30-localization-contributor-docs.md`

**Interfaces:**

- Consumes: the completed documentation edits.
- Produces: a clean, committed feature branch ready for integration.

- [ ] **Step 1: Run localization and formatting gates**

Run:

```bash
Scripts/check-localization-source.sh
jq empty Resources/Localization/Localizable.xcstrings \
  Resources/Localization/InfoPlist.xcstrings
swift test --filter LocalizationCatalogTests
git diff --check
```

Expected: every command passes with zero failures.

- [ ] **Step 2: Review the documentation diff**

Run:

```bash
git diff -- AGENTS.md README.md docs/development.md docs/localization.md \
  docs/superpowers/plans/2026-07-30-localization-contributor-docs.md
```

Expected: the diff is limited to the requested guide, policy, discoverability
links, and this plan.

- [ ] **Step 3: Commit**

Run:

```bash
git add AGENTS.md README.md docs/development.md docs/localization.md \
  docs/superpowers/plans/2026-07-30-localization-contributor-docs.md
git commit -m "docs: explain the localization workflow"
```

---

### Task 4: Merge Locally into Main

**Files:**

- Integrate: `feature/i18n-localization`
- Target: `main`

**Interfaces:**

- Consumes: the clean, verified feature branch.
- Produces: local `main` containing the localization implementation and
  contributor documentation.

- [ ] **Step 1: Confirm branch topology and clean worktrees**

Run:

```bash
git status --short --branch
git merge-base --is-ancestor main feature/i18n-localization
git -C ../.. status --short --branch
```

Expected: both worktrees are clean and `main` is an ancestor of the feature
branch.

- [ ] **Step 2: Merge with an explicit merge commit**

From the main worktree, run:

```bash
git merge --no-ff feature/i18n-localization
```

Expected: the merge completes without conflicts. Do not push or release.

- [ ] **Step 3: Verify the merged result**

From the main worktree, run:

```bash
swift test
make -B app
Scripts/verify-localizations.sh build/OutcutShare.app
codesign --verify --deep --strict --verbose=2 build/OutcutShare.app
git status --short --branch
```

Expected: all 195 tests pass, the signed app builds without warnings, all ten
locale probes pass, the signature satisfies its designated requirement, and
local `main` is clean and ahead of `origin/main`.
