# omarchy-momentum4

Bluetooth headphone battery and noise control in the [Omarchy](https://omarchy.org/) status bar.

![bar widget](docs/screenshot.png)

- **Battery** for *any* Bluetooth headset, read from BlueZ's `org.bluez.Battery1`
- **Noise control** for supported devices — currently the Sennheiser Momentum 4
- No daemon. Each poll shells out, reads, and exits

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-momentum4.git --enable
```

Then enable BlueZ's experimental interfaces, which is what exposes battery at all:

```bash
sudo sed -i 's/^#Experimental = false/Experimental = true/' /etc/bluetooth/main.conf
sudo systemctl restart bluetooth
```

Without that line there is no `org.bluez.Battery1` and the widget stays hidden.

**Battery also disappears while the headphones are plugged in over USB.** They
enumerate as a USB audio card (`alsa_card.usb-Sonova_Consumer_Hearing_MOMENTUM_4_…`)
and stop reporting battery over the Bluetooth link, so `Battery1` vanishes even
though Bluetooth stays connected and `Experimental` is still set. This is the
headphones' behaviour, not a fault in the setup — unplug them and it returns.

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

## Firmware probe

`bin/gaia-probe` sweeps GAIA command IDs and reports which the firmware
answers, mapping the real feature set independently of what the vendor app
chooses to show.

```bash
bin/gaia-probe                              # default vendor range
bin/gaia-probe --start 0x1A00 --end 0x1AFF
bin/gaia-probe --json
```

It probes **odd IDs only** by default. Observed commands pair as
`SET`(even)/`GET`(odd), so odd IDs are overwhelmingly reads — a convention, not
a guarantee. `--even` widens it at your own risk.

### Reading the output

A success reply is weaker evidence than it looks. This firmware **acks most
unknown IDs in a range with an identical one-byte payload**, so counting
successes alone wildly over-reports. The probe groups replies by payload and
surfaces only the outliers, which are the ones carrying real state.

### Findings on Momentum 4 (firmware as of 2026-08)

Sweeping `0x1000-0x10FF` and `0x1A00-0x1AFF`, 256 odd IDs:

| Command | Payload | Notes |
|---|---|---|
| `0x1a01` | `010202000300` | **Unknown.** Six bytes, likely a noise-control capability or config structure |
| `0x1a03` | `64` | Transparency (100) — known |
| `0x1a05` | `01` | ANC status — known |
| `0x1007` | `00` | Unknown |
| `0x1081` `0x1083` `0x1085` | `05` each | Unknown cluster; consecutive odd IDs sharing a value suggests one feature group |

Everything else returned the bulk ack. Note `0x1a05`'s real payload happens to
equal the bulk ack byte, so payload-distinctiveness alone would miss it — known
commands are labelled from a table for that reason.

## Firmware differences

Captures either side of the 2.13.42 → 3.38.3 update are in `probes/`. Diffing
them identified the firmware-version command and one capability change.

| Command | 2.13.42 | 3.38.3 | Meaning |
|---|---|---|---|
| `0x1009` get bass boost | rejected | **acked** | Bass boost is unsupported on 2.x and works on 3.x |
| `0x1201` | `0002000d002a` | `000300260003` | **Firmware version** — three big-endian uint16s: `2,13,42` then `3,38,3` |
| `0x100f`, `0x1013` | absent | present | New, undecoded |
| `0x1007` | `f9` | — | No longer distinct |

Everything else was identical, so the update did **not** renumber the command
space — `m4ctl` needed no changes to keep working.

### "Rejected" does not mean unsupported

The single most important lesson here. `gaia-probe` sends **empty payloads**, and
a command that needs an argument answers with the *error* form — indistinguishable
from a genuinely unsupported command:

```
0x1003 with empty payload  -> 0x1183 (error)
0x1003 with payload 00     -> 0x1103 (ok), returns the EQ curve
```

Every sweep therefore filed EQ under "rejected" and moved on. Roughly 490
commands per sweep land in that bucket, and an unknown number of them are
parameterised getters rather than dead ends.

Three separate sweeps came back clean for EQ, phone-call settings and
auto-pause because of this. Sweeping harder would never have found them.

### Notifications beat sweeping

`bin/gaia-listen` registers for notification features and prints what the device
pushes unprompted. It found the EQ command in seconds after three sweeps had
failed, because the device volunteers the command id when a setting changes —
no need to guess an argument.

The protocol has three response forms, not two:

| Form | Meaning |
|---|---|
| `command \| 0x0100` | success |
| `command \| 0x0180` | error |
| `command \| 0x0080` | unsolicited notification |

Registering feature ids 0-32 got 13 accepted: 0, 2, 3, 4, 8, 9, 10, 11, 12, 13,
16, 20, 32. The reference implementation only knew about 8, 12 and 13.

### 0x0607 takes the headphones down

**Do not send `0x0607`.** Two independent sweeps of `0x0000-0x0FFF` — one with
no pacing, one at 0.12s with reconnect handling — both died at exactly this id
with "Connection reset by peer", after which the headphones dropped off the bus
entirely and needed a power cycle. It is very likely a reset or disconnect in
GAIA's core command space.

`gaia-probe` now skips it unconditionally via its `DANGEROUS` set. The rest of
`0x0000-0x0FFF` remains unswept as a result, so anything living there is still
undiscovered.

### Sweeping is not free

3.38.3 is markedly less tolerant of rapid probing. The sweep that ran clean on
2.13.42 at default spacing dropped the GAIA session on 3.38.3 and left the
headphones needing a re-pair. Use `--delay 0.08` or higher.

## Noise control model

The app presents one three-way control, but on the wire it is two things:

| App mode | `0x1a05` (ANC) | `0x1a01` id 3 |
|---|---|---|
| Adaptive | on | 1 |
| Custom | on | 0 |
| Off | off | — |

Only **Custom** exposes the slider and Anti-wind; Adaptive drives them itself
and Off bypasses them. The panel mirrors that, dimming both unless Custom is
selected, and showing percentages only in Custom — as the app does.

Writing a field means reading `0x1a01`, changing one byte and writing the whole
table back via `0x1a00`; the device does not accept partial writes.

## EQ

A five-band **parametric** EQ. Every command is per-band, indexed 0-4; band 5
and above answer with error `0x83` (out of range), distinct from `0x05` (bad
payload), which is how the band count was confirmed.

| Command | Payload | Meaning |
|---|---|---|
| `0x1001` | `<band><gain>` | **Set** a band's gain |
| `0x1002` | `<band>` | Get a band's gain |
| `0x1003` | any byte | Get all five gains at once |
| `0x100b` | `<band>` | Frequency — 90, 325, 1500, 6500, 6500 Hz |
| `0x100d` | `<band>` | Q factor (fixed point: 2048, then 2908) |
| `0x100f` | `<band>` | Filter type (14 on every band) |
| `0x1011` | `<band>` | Unknown, reads zero |
| `0x1013` | — | Unknown, reads `0000` |

`0x100f` and `0x1013` are the two commands that appeared with firmware 3.x —
that update added the parametric EQ.

### Presets live in the app, not the headphones

The Sennheiser app ships eight read-only presets (Neutral, Rock, Pop, Dance,
Hip-Hop, Classical, Movie, Jazz); editing one forces a copy. Custom presets
appear to be stored app-side too.

**The headphones hold only the active curve.** There is no preset-switch
command and no preset list to read — switching a preset in the app simply
writes the bands one at a time, which is exactly what `gaia-listen` shows as a
run of `0x1082` notifications with one byte changing per packet.

Any preset feature on Linux therefore means storing the curves ourselves and
pushing them band by band, the same way the app does.

## Still to decode

From the app's Noise control sub-page:

- **Anti-wind settings**: Auto / Max — a likely candidate for `0x1a01` id 2 (byte[3]), which has only ever read `0`
- **Phone calls**: toggle plus a Low/High level slider
- **Auto-pause**: pause audio when Transparency is enabled

## Decoding features

`bin/gaia-diff` compares two `gaia-probe` captures; `bin/gaia-watch` polls
specific commands and prints changes live. The loop:

1. `gaia-probe … --json > before.json`
2. Change **one** setting in the Sennheiser app
3. `gaia-probe … --json > after.json`
4. `gaia-diff before.json after.json` — whatever moved is that feature
5. Once located, `gaia-watch <cmd> --bytes` decodes individual fields in seconds

### Decoded so far

| Command | Field | Meaning |
|---|---|---|
| `0x1201` | 3× uint16 BE | Firmware version (`2,13,42` then `3,38,3`) |
| `0x1a01` | — | Three `(id, value)` pairs: `01 vv │ 02 vv │ 03 vv` |
| `0x1a01` | byte[1] (id 1) | **Anti-Wind** — `0` off, `1` on |
| `0x1a01` | byte[3] (id 2) | Unknown, observed only as `0` |
| `0x1a01` | byte[5] (id 3) | **Adaptive ANC** — `1` adaptive, `0` custom |
| `0x1a03` | byte[0] | Noise control, 0 = full ANC … 100 = full transparency |
| `0x1a05` | byte[0] | ANC on/off — the "Off" leg of the app's three-way mode |
| `0x1a00` | whole table | **Writes** the `0x1a01` table; field changes are read-modify-write |
| `0x1009` | byte[0] | Bass boost (rejected on firmware 2.x, works on 3.x) |
| `0x1003` / `0x1002` | 5 signed bytes | **EQ curve**, one per band. The getter *requires* an argument; its value is ignored |
| `0x1607` / `0x1606` | byte[0] | **Headphone Controls** (on-cup touch/buttons). **Inverted**: `0` = enabled, `1` = disabled |

Headphone Controls was *not* in the `0x1a01` table — a live watch of the known
structures showed nothing, and only a full sweep either side of the app's
switch found it, as a single changed line out of 1024 commands. Worth
remembering: the quick watch only works once a sweep has located the command.

`0x1a01` is a small table of `(id, value)` pairs rather than a flat struct,
which is why single bytes move independently when settings change. Two of its
three ids are decoded; id 2 has only ever been seen as `0`, so it needs a
feature toggled that we have not found yet.

Anti-Wind was also observed holding value `2` before the app's switch was first
used — most likely an unset/auto default, though that is unconfirmed. Anything
exposing Anti-Wind in a UI should treat a value other than `0`/`1` as "not
explicitly set" rather than assuming on.

ANC on/off is **not** in this table — it is `0x1a05`.

## Credits

Protocol constants and the RFCOMM channel-probing approach for the Momentum 4
are derived from [momentum4-control](https://github.com/f3Y0/momentum4-control)
by f3Y0, MIT licensed.

## Licence

MIT
