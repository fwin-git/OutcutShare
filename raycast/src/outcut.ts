import { open, showHUD } from "@raycast/api";

/** Fire an outcutshare:// deep link; the app is launched if not running.
 *  One-way by design — the app owns all failure UI beyond "not installed". */
export async function send(pathAndQuery: string, hud: string): Promise<void> {
  try {
    await open(`outcutshare://${pathAndQuery}`);
    await showHUD(hud);
  } catch {
    await showHUD("❌ Couldn't reach Outcut Share — is the app installed?");
  }
}
