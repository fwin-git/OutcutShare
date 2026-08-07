#!/bin/bash
# Notarizes the built app bundle for distribution outside the App Store:
# re-signs with a Developer ID certificate (hardened runtime + timestamp),
# submits to Apple's notary service, staples the ticket, and produces the
# shippable zip. Run via `make notarize` so the bundle is built first.
#
# Credentials, in order of precedence:
#   NOTARY_KEY / NOTARY_KEY_ID / NOTARY_ISSUER_ID   App Store Connect API key
#                                                    (path, key id, issuer id)
#   NOTARY_PROFILE (default "outcut-share")          keychain profile stored via
#     xcrun notarytool store-credentials outcut-share \
#       --apple-id <apple-id> --team-id WZLMH3HPDE \
#       --password <app-specific password from appleid.apple.com>
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/OutcutShare.app
[ -d "$APP" ] || { echo "No $APP — run 'make notarize' (builds first)."; exit 1; }

# The dev build signs with Apple Development for a stable TCC identity;
# notarization instead requires Developer ID Application. Re-sign on top.
IDENTITY=${NOTARIZE_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 "Developer ID Application" | awk '{print $2}' || true)}
if [ -z "$IDENTITY" ]; then
    cat >&2 <<'EOF'
No "Developer ID Application" certificate in the keychain.
Create one (Account Holder only): Xcode → Settings → Accounts → team
WZLMH3HPDE → Manage Certificates → + → Developer ID Application,
or https://developer.apple.com/account/resources/certificates/list.
(The existing "Apple Distribution" cert is App Store-only and won't work.)
EOF
    exit 1
fi

if [ -n "${NOTARY_KEY:-}" ]; then
    creds=(--key "$NOTARY_KEY" --key-id "${NOTARY_KEY_ID:?NOTARY_KEY_ID not set}" \
           --issuer "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID not set}")
else
    creds=(--keychain-profile "${NOTARY_PROFILE:-outcut-share}")
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")

echo "— signing $APP v$version as $IDENTITY (hardened runtime)…"
codesign --force --options runtime --timestamp -s "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "— submitting to Apple's notary service (usually a few minutes)…"
submit_zip=build/notarize-submit.zip
rm -f "$submit_zip"
ditto -c -k --keepParent "$APP" "$submit_zip"
out=$(xcrun notarytool submit "$submit_zip" "${creds[@]}" --wait 2>&1) || {
    echo "$out"
    cat >&2 <<'EOF'
Submission failed before a verdict — usually missing credentials. Store them:
  xcrun notarytool store-credentials outcut-share \
    --apple-id <apple-id> --team-id WZLMH3HPDE --password <app-specific pw>
(App-specific password: https://account.apple.com → Sign-In and Security.)
EOF
    exit 1
}
echo "$out"
if ! echo "$out" | grep -q "status: Accepted"; then
    id=$(echo "$out" | awk '/^  id: /{print $2; exit}')
    echo "— rejected; fetching the notary log for $id…" >&2
    xcrun notarytool log "$id" "${creds[@]}" >&2 || true
    exit 1
fi
rm -f "$submit_zip"

echo "— stapling the ticket…"
xcrun stapler staple "$APP"
spctl --assess --type exec -vv "$APP"

ship_zip="build/OutcutShare-v$version.zip"
rm -f "$ship_zip"
ditto -c -k --keepParent "$APP" "$ship_zip"
echo "Notarized and stapled: $ship_zip"
