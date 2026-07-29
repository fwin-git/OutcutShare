#!/bin/zsh
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
    print -u2 -- "Localization source check requires ripgrep (rg)."
    exit 1
fi

if (( $# > 0 )); then
    source_files=("$@")
else
    source_files=()
    while IFS= read -r source_file; do
        case "$source_file" in
            */DemoContent.swift|*/DemoHarness.swift) continue ;;
        esac
        source_files+=("$source_file")
    done < <(rg --files Sources/OutcutShare -g '*.swift' | sort)
fi

patterns=(
    '\b(Text|Button|Toggle|Picker|Label|Section|LabeledContent|TextField)\(\s*"[^"]*[A-Za-z][^"]*"'
    '\b(NSMenuItem|NSMenu)\(\s*title:\s*"[^"]*[A-Za-z][^"]*"'
    '\.(title|messageText|informativeText|toolTip)\s*=\s*"[^"]*[A-Za-z][^"]*"'
    '\baddButton\(withTitle:\s*"[^"]*[A-Za-z][^"]*"'
    '\.(help|accessibilityLabel)\(\s*"[^"]*[A-Za-z][^"]*"'
    '\b(help|caption|title|accessibilityDescription):\s*"[^"]*[A-Za-z][^"]*"'
    '\bdrawHint\(\s*"[^"]*[A-Za-z][^"]*"'
    'NSLocalizedDescriptionKey:\s*"[^"]*[A-Za-z][^"]*"'
    '^\s*return\s*"[^"]*[A-Za-z][^"]*"'
    'case\s+\.[A-Za-z][A-Za-z0-9_]*:\s*return\s*"[^"]*[A-Za-z][^"]*"'
)

is_allowlisted_technical_string() {
    case "$1" in
        'Sources/OutcutShare/CaptureNaming.swift|return "\(prefix)_\(formatter.string(from: date)).\(ext)"')
            return 0
            ;;
        'Sources/OutcutShare/CaptureNaming.swift|return "\(stem)_\(counter).\(ext)"')
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

found=0
for pattern in "${patterns[@]}"; do
    matches="$(rg -n --no-heading --color never "$pattern" -- "${source_files[@]}" || true)"
    for match in ${(f)matches}; do
        source_file="${match%%:*}"
        remainder="${match#*:}"
        source_text="${remainder#*:}"
        source_text="${source_text#"${source_text%%[![:space:]]*}"}"
        signature="$source_file|$source_text"
        is_allowlisted_technical_string "$signature" && continue
        print -r -- "$match"
        found=1
    done
done

if (( found )); then
    print -u2 -- "Unlocalized user-facing string literals found."
    exit 1
fi
