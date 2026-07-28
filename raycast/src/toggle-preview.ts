import { send } from "./outcut";

export default async function command() {
  await send("toggle?option=preview", "Toggled preview window");
}
