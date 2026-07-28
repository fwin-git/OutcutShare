import { test } from "node:test";
import assert from "node:assert/strict";
import { extractStringKey, parsePresets } from "../src/plist";

const SAMPLE_PRESETS = [
  {
    id: "AAAAAAAA-0000-0000-0000-000000000001",
    name: "Left Half",
    region: { x: 0, y: 100, width: 1280, height: 720, displayID: 3 },
    shareModeRaw: "hiddenWindow",
  },
];

// `defaults export` wraps base64 <data> at 68 chars with tab indentation —
// the extractor must tolerate embedded whitespace.
function wrap(b64: string): string {
  return b64.replace(/(.{60})/g, "$1\n\t");
}

function plistWith(entries: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
${entries}
</dict>
</plist>`;
}

const FULL = plistWith(`	<key>followMode</key>
	<string>cursor</string>
	<key>presets</key>
	<data>
	${wrap(Buffer.from(JSON.stringify(SAMPLE_PRESETS)).toString("base64"))}
	</data>
	<key>shareMode</key>
	<string>virtualMonitor</string>`);

test("extractStringKey finds a top-level string", () => {
  assert.equal(extractStringKey(FULL, "followMode"), "cursor");
  assert.equal(extractStringKey(FULL, "shareMode"), "virtualMonitor");
});

test("extractStringKey returns null for absent keys", () => {
  assert.equal(extractStringKey(FULL, "missing"), null);
});

test("parsePresets round-trips despite base64 line wrapping", () => {
  const presets = parsePresets(FULL);
  assert.equal(presets.length, 1);
  assert.equal(presets[0].name, "Left Half");
  assert.equal(presets[0].id, "AAAAAAAA-0000-0000-0000-000000000001");
  assert.equal(presets[0].region.width, 1280);
});

test("parsePresets returns [] when the key is absent", () => {
  assert.deepEqual(parsePresets(plistWith("\t<key>other</key>\n\t<string>x</string>")), []);
});

test("parsePresets returns [] on malformed payloads", () => {
  const bad = plistWith("\t<key>presets</key>\n\t<data>!!!not-base64!!!</data>");
  assert.deepEqual(parsePresets(bad), []);
});
