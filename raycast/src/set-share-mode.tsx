import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { useEffect, useState } from "react";
import { readAppState } from "./appState";
import { send } from "./outcut";

const MODES = [
  { value: "hiddenWindow", title: "Hidden Window", subtitle: "share window in the meeting app" },
  { value: "virtualDisplay", title: "Virtual Display", subtitle: "share screen in the meeting app" },
  { value: "virtualMonitor", title: "Virtual Monitor", subtitle: "private extra screen" },
];

export default function SetShareMode() {
  const [current, setCurrent] = useState<string | null>(null);
  useEffect(() => {
    readAppState().then((s) => setCurrent(s.shareMode), () => setCurrent("virtualDisplay"));
  }, []);
  return (
    <List isLoading={current === null}>
      <List.Section title="Share as" subtitle="applies while not sharing">
        {MODES.map((mode) => (
          <List.Item
            key={mode.value}
            title={mode.title}
            subtitle={mode.subtitle}
            icon={Icon.Monitor}
            accessories={current === mode.value ? [{ icon: Icon.Checkmark, tooltip: "Current" }] : []}
            actions={
              <ActionPanel>
                <Action
                  title={`Share as ${mode.title}`}
                  icon={Icon.Monitor}
                  onAction={() => send(`share-mode?mode=${mode.value}`, `Share as ${mode.title}`)}
                />
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
    </List>
  );
}
