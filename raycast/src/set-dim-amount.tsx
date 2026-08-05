import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { useEffect, useState } from "react";
import { readAppState } from "./appState";
import { send } from "./outcut";

const PRESETS = [
  { percent: 0, title: "Off" },
  { percent: 20, title: "20 %" },
  { percent: 40, title: "40 %" },
  { percent: 60, title: "60 %" },
  { percent: 80, title: "80 %" },
];

function setDim(percent: number) {
  return send(`dim?percent=${percent}`, percent === 0 ? "Dimming off" : `Dim ${percent} %`);
}

/** "45", "45.5" or "45%" → 45; anything outside 0–90 → null. */
function parsePercent(text: string): number | null {
  const raw = text.trim().replace(/%$/, "").trim();
  if (!raw) return null;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 && value <= 90 ? value : null;
}

export default function SetDimAmount() {
  // -1 while loading; dimming disabled reads as 0 so "Off" gets the mark.
  const [current, setCurrent] = useState(-1);
  const [searchText, setSearchText] = useState("");
  useEffect(() => {
    readAppState().then(
      (s) => setCurrent(s.dimmingEnabled ? s.dimPercent : 0),
      () => setCurrent(60),
    );
  }, []);
  const typed = parsePercent(searchText);
  return (
    <List
      isLoading={current === -1}
      searchBarPlaceholder="Type a percent (0–90)"
      onSearchTextChange={setSearchText}
    >
      {typed !== null && (
        <List.Section title="Custom">
          <List.Item
            title={typed === 0 ? "Turn Dimming Off" : `Set to ${typed} %`}
            icon={Icon.Pencil}
            actions={
              <ActionPanel>
                <Action
                  title={typed === 0 ? "Turn Dimming Off" : `Set Dim to ${typed} %`}
                  icon={Icon.Moon}
                  onAction={() => setDim(typed)}
                />
              </ActionPanel>
            }
          />
        </List.Section>
      )}
      <List.Section title="Presets" subtitle="local only — viewers never see dimming">
        {PRESETS.map((preset) => (
          <List.Item
            key={preset.percent}
            title={preset.title}
            icon={preset.percent === 0 ? Icon.CircleDisabled : Icon.Moon}
            accessories={current === preset.percent ? [{ icon: Icon.Checkmark, tooltip: "Current" }] : []}
            actions={
              <ActionPanel>
                <Action
                  title={preset.percent === 0 ? "Turn Dimming Off" : `Set Dim to ${preset.title}`}
                  icon={preset.percent === 0 ? Icon.CircleDisabled : Icon.Moon}
                  onAction={() => setDim(preset.percent)}
                />
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
    </List>
  );
}
