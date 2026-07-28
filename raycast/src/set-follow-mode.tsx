import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { useEffect, useState } from "react";
import { readAppState } from "./appState";
import { send } from "./outcut";

const MODES = [
  { value: "off", title: "Off", icon: Icon.CircleDisabled },
  { value: "activeWindow", title: "Active Window", icon: Icon.AppWindow },
  { value: "cursor", title: "Cursor", icon: Icon.Mouse },
];

export default function SetFollowMode() {
  const [current, setCurrent] = useState<string | null>(null);
  useEffect(() => {
    readAppState().then((s) => setCurrent(s.followMode), () => setCurrent("off"));
  }, []);
  return (
    <List isLoading={current === null}>
      {MODES.map((mode) => (
        <List.Item
          key={mode.value}
          title={mode.title}
          icon={mode.icon}
          accessories={current === mode.value ? [{ icon: Icon.Checkmark, tooltip: "Current" }] : []}
          actions={
            <ActionPanel>
              <Action
                title={`Follow: ${mode.title}`}
                icon={mode.icon}
                onAction={() => send(`follow?mode=${mode.value}`, `Follow: ${mode.title}`)}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
