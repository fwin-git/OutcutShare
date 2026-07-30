#!/bin/zsh
set -euo pipefail

app="${1:?usage: Scripts/verify-localizations.sh <app-path>}"
resources="$app/Contents/Resources"
executable="$app/Contents/MacOS/OutcutShare"

locales=(en de fr es zh-Hans ja pt-BR ko zh-Hant it)
expected=(
    "Select Region & Share"
    "Bereich auswählen und teilen"
    "Sélectionner une zone et partager"
    "Seleccionar región y compartir"
    "选择区域并共享"
    "範囲を選択して共有"
    "Selecionar região e compartilhar"
    "영역 선택 및 공유"
    "選取區域並分享"
    "Seleziona area e condividi"
)

[[ -x "$executable" ]] || {
    print -u2 -- "Missing executable: $executable"
    exit 1
}

for locale in "${locales[@]}"; do
    for table in Localizable InfoPlist; do
        path="$resources/$locale.lproj/$table.strings"
        [[ -f "$path" ]] || {
            print -u2 -- "Missing localization: $path"
            exit 1
        }
    done
done

for index in {1..${#locales}}; do
    locale="${locales[$index]}"
    actual="$("$executable" "--localization-test=$locale")"
    [[ "$actual" == "${expected[$index]}" ]] || {
        print -u2 -- "$locale: expected '${expected[$index]}', got '$actual'"
        exit 1
    }
done

print -- "Verified localizations: ${locales[*]}"
