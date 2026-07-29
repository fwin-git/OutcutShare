#!/bin/zsh
set -euo pipefail

if (( $# > 0 )); then
    source_files=("$@")
else
    source_files=(
        Sources/OutcutShare/FollowController.swift
        Sources/OutcutShare/Hotkeys.swift
        Sources/OutcutShare/SettingsStore.swift
        Sources/OutcutShare/StatusBarController.swift
        Sources/OutcutShare/PermissionsView.swift
        Sources/OutcutShare/AppPicker.swift
        Sources/OutcutShare/SettingsView.swift
        Sources/OutcutShare/SettingsShortcutsPage.swift
        Sources/OutcutShare/DimPreview.swift
        Sources/OutcutShare/RegionPreviewCanvas.swift
        Sources/OutcutShare/Hotbar.swift
        Sources/OutcutShare/LiveFrameWindow.swift
        Sources/OutcutShare/MonitorDrag.swift
        Sources/OutcutShare/PreviewWindow.swift
        Sources/OutcutShare/RegionMover.swift
        Sources/OutcutShare/RegionSelector.swift
    )
fi

patterns=(
    '\b(Text|Button|Toggle|Picker|Label|Section|LabeledContent|TextField)\(\s*"[^"]*[A-Za-z][^"]*"'
    '\b(NSMenuItem|NSMenu)\(\s*title:\s*"[^"]*[A-Za-z][^"]*"'
    '\.(title|messageText|informativeText|toolTip)\s*=\s*"[^"]*[A-Za-z][^"]*"'
    '\baddButton\(withTitle:\s*"[^"]*[A-Za-z][^"]*"'
    '\.(help|accessibilityLabel)\(\s*"[^"]*[A-Za-z][^"]*"'
    '\b(help|caption|label|accessibilityDescription):\s*"[^"]*[A-Za-z][^"]*"'
    '\bdrawHint\(\s*"[^"]*[A-Za-z][^"]*"'
    'case\s+\.[A-Za-z][A-Za-z0-9_]*:\s*return\s*"[^"]*[A-Za-z][^"]*"'
)

found=0
for pattern in "${patterns[@]}"; do
    matches="$(rg -n --no-heading --color never "$pattern" -- "${source_files[@]}" || true)"
    if [[ -n "$matches" ]]; then
        print -r -- "$matches"
        found=1
    fi
done

if (( found )); then
    print -u2 -- "Unlocalized user-facing string literals found."
    exit 1
fi
