/** Shape JSONEncoder writes for SettingsStore.presets (see Presets.swift). */
export interface Preset {
  id: string;
  name: string;
  region: { x: number; y: number; width: number; height: number; displayID: number };
  shareModeRaw: string;
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** First match wins — fine here: the keys we read are unique, top-level
 *  keys of the exported com.outcutshare.app domain. */
function extractValue(plist: string, key: string, tag: "string" | "data" | "real"): string | null {
  const re = new RegExp(`<key>${escapeRegExp(key)}</key>\\s*<${tag}>([\\s\\S]*?)</${tag}>`);
  const match = plist.match(re);
  return match ? match[1] : null;
}

export function extractStringKey(plist: string, key: string): string | null {
  return extractValue(plist, key, "string");
}

export function extractRealKey(plist: string, key: string): number | null {
  const raw = extractValue(plist, key, "real");
  if (raw === null) return null;
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

/** Booleans export as self-closing <true/> / <false/> tags. */
export function extractBoolKey(plist: string, key: string): boolean | null {
  const re = new RegExp(`<key>${escapeRegExp(key)}</key>\\s*<(true|false)\\s*/>`);
  const match = plist.match(re);
  return match ? match[1] === "true" : null;
}

export function parsePresets(plist: string): Preset[] {
  const raw = extractValue(plist, "presets", "data");
  if (!raw) return [];
  try {
    // Buffer.from(…, "base64") skips invalid characters instead of
    // throwing, so garbage input fails at JSON.parse and lands in catch.
    const decoded = JSON.parse(
      Buffer.from(raw.replace(/\s+/g, ""), "base64").toString("utf8"),
    );
    return Array.isArray(decoded) ? decoded : [];
  } catch {
    return [];
  }
}
