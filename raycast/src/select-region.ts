import { send } from "./outcut";

export default async function command() {
  await send("select", "Starting selection");
}
