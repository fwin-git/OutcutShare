import { send } from "./outcut";

export default async function command() {
  await send("pause", "Toggled pause");
}
