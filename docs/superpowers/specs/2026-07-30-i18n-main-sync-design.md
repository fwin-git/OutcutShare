# Internationalization Main-Sync Design

## Goal

Merge the latest `main` into `feature/i18n-localization` without losing either
the new showcase/demo behavior or the completed application localization.
Any user-facing production text introduced by `main` must use the existing
typed `L10n` facade and have finalized English, German, French, Spanish,
Simplified Chinese, and Japanese catalog values.

## Integration Strategy

Create a merge commit from `main` into `feature/i18n-localization`. Do not
rebase or cherry-pick the upstream milestone because the user requested a merge
and the localization branch already has a reviewable commit series.

For overlapping files:

- retain `main`'s behavioral additions and bug fixes;
- retain the localization branch's `L10n` calls instead of restoring UI
  literals;
- retain the localization catalogs, source audit, catalog tests, bundle
  metadata, and packaging verifier;
- combine independently added tests rather than choosing one side; and
- preserve `main`'s updated repository instructions and documentation while
  keeping the localization design and implementation plan.

`DemoContent.swift`, `DemoHarness.swift`, debug CLI output, and demo
choreography remain outside runtime localization. They are developer-only
showcase fixtures under the approved localization design. Any production UI
that those fixtures exercise remains localized.

## Audit

Compare `main` to the original fork point and review every changed production
Swift file. Run the production-source localization lint after conflict
resolution. Search the incoming diff for Swift string literals and classify
each one as:

- a production-facing string that requires a semantic typed key and six
  translations; or
- a stable technical/debug value that must remain untranslated.

No whole production file may be excluded from the source lint. Exact technical
allowlist entries require a reason.

## Verification

The synchronized branch is complete only when:

- the merge has no unresolved conflicts;
- the production-source localization lint passes;
- the 257-key baseline remains intact and any new production keys have all six
  finalized translations with matching placeholder signatures;
- all Swift tests pass, including both localization and incoming showcase
  regressions;
- `make app` compiles both catalogs and produces a warning-free signed app;
- the bundle verifier and strict code-signature verification pass;
- runtime probes return the expected string in all six locales;
- locale-specific settings/permissions layout remains readable; and
- the feature worktree is clean after any required localization-fix commit.

No release, push, or merge into `main` is part of this synchronization.
