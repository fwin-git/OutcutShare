# Development

## Build & test

```sh
make app     # builds build/OutcutShare.app (stamped with git-based build number)
make run     # builds and launches it
make test    # unit tests (swift test)
```

Requires Xcode command line tools on macOS 14+. `make app` signs with your
first *Apple Development* identity when one exists (override with
`make app CODESIGN_ID=…`) so the Screen Recording grant survives rebuilds;
otherwise it falls back to ad-hoc signing.

## Debug flags

End-to-end verification without clicking through the UI:

```sh
.build/debug/OutcutShare --vd-test                             # virtual display only
.build/debug/OutcutShare --share-test=100,100,800,600,8        # full pipeline, 8 s
.build/debug/OutcutShare --share-test=100,100,800,600,8,window # hidden-window mode
.build/debug/OutcutShare --hotkeys-test                        # registered shortcuts
.build/debug/OutcutShare --permissions-test                    # permission status
.build/debug/OutcutShare --show-settings=shortcuts             # open a settings pane
```

`--share-test` composes with `--move-by=dx,dy`, `--resize-by=dw,dh`,
`--pause-at=t1,t2`, `--record-at=t1,t2` and `--follow=activeWindow|cursor`.

## Releases

```sh
make release
```

`Scripts/release.sh` derives the next version from conventional commits since
the last tag (`feat:` → minor, `fix:`/other → patch, breaking → major), runs
the tests, tags, and pushes. CI builds the bundle with the tag version and
publishes a GitHub release whose changelog is generated from `feat:`/`fix:`
commit subjects (`Scripts/changelog.sh`) — so keep commit messages
feature-oriented.
