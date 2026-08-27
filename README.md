# omarchy-headphones

Bluetooth headphone battery and noise control in the [Omarchy](https://omarchy.org/) status bar.

![bar widget](docs/screenshot.png)

- **Battery** for *any* Bluetooth headset, read from BlueZ's `org.bluez.Battery1`
- **Noise control** for supported devices — currently the Sennheiser Momentum 4
- No daemon. Each poll shells out, reads, and exits

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-headphones.git --enable
```

Then enable BlueZ's experimental interfaces, which is what exposes battery at all:

```bash
sudo sed -i 's/^#Experimental = false/Experimental = true/' /etc/bluetooth/main.conf
sudo systemctl restart bluetooth
```

Without that line there is no `org.bluez.Battery1` and the widget stays hidden.

## Usage

| Action | Effect |
|---|---|
| Left click | Toggle between full ANC and full transparency |
| Right click | Jump to full ANC |
| Scroll | Adjust noise control in steps of 10 |
| Middle click | Force a refresh |

The pill turns the bar's urgent colour at 20% battery or below.

## CLI

The backends are usable on their own:

```bash
bin/hp-status          # one JSON line: battery, name, noise-control state
bin/m4ctl get          # Momentum 4: ANC, transparency, bass boost, battery
bin/m4ctl transparency 0    # 0 = full transparency, 100 = full ANC
bin/m4ctl anc on|off
bin/m4ctl battery --json
```

## Supported devices

**Battery** works for any headset that reports it to BlueZ.

**Noise control** needs a device-specific backend. Adding one means writing a
script that speaks the device's protocol and answers `get --json`, then adding a
name pattern to `BACKENDS` in `bin/hp-status`.

| Device | Battery | Noise control | Notes |
|---|---|---|---|
| Sennheiser Momentum 4 | ✅ | ✅ | GAIA over RFCOMM |
| AirPods (all) | ❌ | ❌ | Apple does not report battery to BlueZ; control needs AACP |

### A note on bass boost

The Momentum 4 rejects GAIA's bass-boost command, replying with the error form
(`0x1189`) rather than a value. `m4ctl` reports it as `unsupported` instead of
reading the error payload as `true` — worth knowing if you compare against other
implementations, which sometimes don't check the error bit.

## Credits

Protocol constants and the RFCOMM channel-probing approach for the Momentum 4
are derived from [momentum4-control](https://github.com/f3Y0/momentum4-control)
by f3Y0, MIT licensed.

## Licence

MIT
