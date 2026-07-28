import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { useEffect, useState } from "react";
import { AppState, readAppState } from "./appState";
import { send } from "./outcut";

export default function SharePreset() {
  const [state, setState] = useState<AppState | null>(null);
  useEffect(() => {
    readAppState().then(setState, () =>
      setState({ presets: [], followMode: "off", shareMode: "virtualDisplay" }),
    );
  }, []);
  return (
    <List isLoading={state === null}>
      <List.EmptyView
        title="No presets saved yet"
        description="Save one from the Outcut Share menu: Presets → Save Current Region as Preset."
        icon={Icon.AppWindowGrid2x2}
      />
      {(state?.presets ?? []).map((preset) => (
        <List.Item
          key={preset.id}
          title={preset.name}
          subtitle={`${Math.round(preset.region.width)} × ${Math.round(preset.region.height)}`}
          icon={Icon.AppWindowGrid2x2}
          actions={
            <ActionPanel>
              <Action
                title="Share Preset"
                icon={Icon.Monitor}
                onAction={() =>
                  send(`preset?id=${encodeURIComponent(preset.id)}`, `Sharing “${preset.name}”`)
                }
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
