# Momentum4, Omarchy plugin

Sennheiser Momentum 4 battery, noise control, EQ, phone-call and touch
settings in the Omarchy bar. Speaks the headphones' own GAIA protocol over
Bluetooth RFCOMM; nothing else will work with it.

Read the `omarchy-plugin-dev` skill first; it holds the conventions. This
file holds only what is specific to this repo.

## Identity

- id / IPC target / `moduleName`: `dansmith888.momentum4`
- repo: `https://github.com/DanSmith888/omarchy-momentum4.git`
- installed copy: `~/.config/omarchy/plugins/dansmith888.momentum4`
- kind: `bar-widget`, entry point `BarWidget.qml`; published; manifest 1.3.7, tags up to `v1.3.7` (tag on release)

## Map

- `manifest.json`, the contract; bump `version` on release.
- `BarWidget.qml`, entry point. Owns the pill and the single `IpcHandler`;
  forwards open/close/opened/closeForPopoutSwitch to `Panel.qml`. Scroll on
  the pill nudges ANC↔Transparency; middle-click refreshes.
- `Panel.qml`, owns all device state (~20 properties; `null` = firmware
  did not answer → control hidden). Three `Process`es: `m4status` poll,
  `m4ctl presets --json` once, `m4ctl <verb>` actions gated by `busy`.
- `bin/m4status`, one JSON line; `{}` when no headset. Finds the device via
  `bluetoothctl`, then calls `m4ctl get --json`. `usb_connected` comes from
  `/proc/asound/cards` and is deliberately not called "charging".
- `bin/m4ctl`, the CLI and the whole protocol. `get`, `doctor`, `eq*`,
  `preset`, `mode`, `antiwind`, `transparency`, `bass`, `controls`,
  `sound-mode`, `auto-off`, and one verb per `BOOL_FEATURES` entry. Holds `PLUGIN_ID` /
  `REPO_URL`. Every RFCOMM open goes through the `Momentum4` context manager
  → one `flock` on `$XDG_RUNTIME_DIR/m4ctl.lock`.
- `presets.json`, EQ presets, data not code. Device stores only the active
  curve, so applying a preset writes all five bands. Device units are dB×10.
- `PROTOCOL.md`, `probes/`, `tools/gaia-*`, `tools/eq-capture`, the
  reverse-engineering kit. **Never run by the widget.** `probes/decode/*.json`
  are captured firmware answers per feature.
- `docs/SUBMISSION-DRAFT.md`, marketplace issue body; submitted 1 Sep 2026, awaiting maintainer approval.

## Dev loop

```bash
omarchy plugin validate . && ~/.claude/skills/omarchy-plugin-dev/scripts/lint.sh
rsync -a --delete --exclude .git --exclude .claude ./ ~/.config/omarchy/plugins/dansmith888.momentum4/
omarchy-shell shell toggle dansmith888.momentum4
qs log -p "$OMARCHY_PATH/shell" --tail 100
bin/m4ctl doctor          # hardware → GAIA → battery → plugin files → bar placement
```

## Rules

- Keep in sync on release: `manifest.version`, git tag `vX.Y.Z`,
  `moduleName` in both QML files, `PLUGIN_ID`/`REPO_URL` in `bin/m4ctl`,
  README commands, `docs/SUBMISSION-DRAFT.md`.
- stdlib Python only in `bin/`; no root, no network; lock in
  `$XDG_RUNTIME_DIR`, never `/tmp`.
- Never edit `/usr/share/omarchy/**`.
- No `git push`, tag push, or marketplace submission unless Daniel says so.

## Gotchas

- Reading the device means holding an exclusive RFCOMM socket, so state is
  **polled**, not subscribed: 5s while absent, 60s while present, 5s while
  the panel is open, `triggeredOnStart` on both timers.
- `stale`: headset connected but `m4ctl` could not reach it (phone app or a
  research tool holds the channel, or the lock timed out). Keep last-good
  readings, dim the panel, disable writes, do not blank the pill.
- Battery disappears from GAIA while USB is attached; the pill shows a
  charging glyph instead of an empty value.
- Slider writes are optimistic; EQ drags update locally and commit on
  release, one RFCOMM round-trip per pixel would queue behind the lock.
- Several `0x06xx` commands reset the headphones or the link; the
  `DANGEROUS` set in `tools/gaia-probe` (`0x0607, 0x060F, 0x0613, 0x0683,
  0x0685`) is the blocklist. Read `PROTOCOL.md` before probing.
- Only Custom mode exposes the ANC slider and anti-wind; Speech Clarity dims
  the EQ. Both mirror the Sennheiser app, not a hardware restriction.
