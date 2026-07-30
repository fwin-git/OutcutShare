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
.build/debug/OutcutShare --vd-test                              # virtual display only
.build/debug/OutcutShare --share-test=100,100,800,600,8         # full pipeline, 8 s
.build/debug/OutcutShare --share-test=100,100,800,600,8,window  # hidden-window mode
.build/debug/OutcutShare --share-test=0,0,1,1,8,monitor         # virtual monitor (rect ignored)
.build/debug/OutcutShare --hotkeys-test                         # registered shortcuts
.build/debug/OutcutShare --permissions-test                     # permission status
.build/debug/OutcutShare --show-settings=shortcuts              # open a settings pane
```

`--share-test` composes with `--move-by=dx,dy`, `--resize-by=dw,dh`,
`--pause-at=t1,t2`, `--record-at=t1,t2`, `--follow=activeWindow|cursor` and
`--preview` (shows the shared-output preview panel).
`--show-settings` composes with `--close-settings-after=secs` (teardown /
performance verification).

## Demo recordings

```sh
.build/debug/OutcutShare --demo=monitor   # Virtual Monitor showcase
.build/debug/OutcutShare --demo=region    # selection modifiers + mock call mirror
.build/debug/OutcutShare --demo=follow    # follow modes (window / cursor)
.build/debug/OutcutShare --demo=zoom      # viewer zoom + live preset switch
.build/debug/OutcutShare --demo=capture   # screenshot/record → card, drag-out, trim
.build/debug/OutcutShare --demo=pause     # privacy pause + resume in the call mirror
.build/debug/OutcutShare --demo=raycast   # still of the Raycast command list (.png)
```

Records a feature walkthrough to `~/Movies/OutcutShare/Demos/` — a clean
16:9 stage (1080p on large screens) with a backdrop and fake app windows
(spawned by a helper process so the real cross-app machinery runs), driven
by synthetic input with a keystroke chip for held modifiers. Nothing
personal appears in frame. The run takes over the mouse for ~30 s (3 s
countdown, Ctrl-C aborts) and needs Screen Recording + Accessibility for
the invoking binary. The `raycast` scenario is a still, not a clip: it
opens Raycast, types "outcut", captures the window and Escs out (the
extension must be imported, see [raycast](raycast.md)).

`Scripts/demo-gif.sh take.mp4 docs/media/demo-x.gif` converts a keeper
take to a README GIF (900 px wide, 12.5 fps).

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
