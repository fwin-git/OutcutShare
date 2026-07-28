import { send } from "./outcut";

export default async function command() {
  await send("share-last", "Sharing last region");
}
