import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { extractStringKey, parsePresets, Preset } from "./plist";

const run = promisify(execFile);

export interface AppState {
  presets: Preset[];
  followMode: string;
  shareMode: string;
}

/** `defaults export` goes through cfprefsd, so values are never stale.
 *  Fallbacks mirror SettingsStore's init defaults. */
export async function readAppState(): Promise<AppState> {
  const { stdout } = await run(
    "/usr/bin/defaults",
    ["export", "com.outcutshare.app", "-"],
    { maxBuffer: 16 * 1024 * 1024 },
  );
  return {
    presets: parsePresets(stdout),
    followMode: extractStringKey(stdout, "followMode") ?? "off",
    shareMode: extractStringKey(stdout, "shareMode") ?? "virtualDisplay",
  };
}
