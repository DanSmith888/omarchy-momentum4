# Sennheiser Momentum 4 — GAIA protocol notes

Everything here was found by observation against a Momentum 4 on firmware
**3.38.3** (some notes cover 2.13.42). It is not official and not complete.

## GAIA in one paragraph

GAIA is Qualcomm's control protocol for Bluetooth audio devices built on their
chips, inherited from CSR. It rides over RFCOMM — a plain Bluetooth serial
channel — and each manufacturer gets its own command namespace, which is why
the framing is shared knowledge but every vendor's commands must be
reverse-engineered separately.

```
FF 03 │ length(2) │ vendor(2) │ command(2) │ payload
  ▲        ▲           ▲           ▲
magic    bytes    0x0495 =      16-bit
                Sennheiser     command id
```

Three response forms, not two:

| Form | Meaning |
|---|---|
| `command \| 0x0100` | success |
| `command \| 0x0180` | error |
| `command \| 0x0080` | unsolicited notification |

Common error payloads: `0x05` for a malformed or wrong-length payload, `0x83`
for an index out of range.

## Commands

### Noise control

| Command | Payload | Meaning |
|---|---|---|
| `0x1a05` | byte | ANC on/off — the "Off" leg of Smart Control's three-way mode |

### Battery and phone-call features (`0x04xx`–`0x08xx`)

IDs from [momentumctl](https://github.com/gjabell/momentumctl) (MIT), verified
here on firmware 3.38.3 two ways: `probes/decode/momentumctl-verify.json` has
each get plus a set → readback → restore for every boolean, and each ID was
then watched with `tools/gaia-watch` while the matching switch was flipped in
Smart Control's **Device Settings** pane — every one moved in step. Same
framing as everything else: get takes no payload, set takes one byte, the
reply is `command | 0x0100`.

| Get | Set | Payload | Meaning |
|---|---|---|---|
| `0x0603` | — | byte, percent | **Battery.** Makes `org.bluez.Battery1` unnecessary (which, it turned out, this BlueZ populates from HFP without the `Experimental` flag anyway) |
| `0x0401` | `0x0400` | byte bool | On-head Detection — also gates Smart Pause and call hold |
| `0x080b` | `0x080a` | byte bool | Auto-Answer Calls |
| `0x080d` | `0x080c` | byte bool | Smart Pause (pause on take-off) |
| `0x0815` | `0x0814` | byte bool | Comfort Calls ("more natural sound stage" on calls) |

These are *not* inverted, unlike the touch controls at `0x1607`. The device
sends **no notification** when the app changes them, which is why listening
never found them — polling did.

### Audio mode priority (`0x14xx`) — a restart flag, not the mode

| Get | Payload | Meaning |
|---|---|---|
| `0x1407` | byte | **"Audio mode change pending"**, not Hi-Res itself. It was the only byte in `0x0827–0x1fff` that differed between snapshots with Hi-Res on and off — but it read `01` right after the switch was flipped and `00` once the headphones had restarted, *with Hi-Res still on*. A one-byte write to `0x1406` is rejected (`0x05`) |
| `0x1409` | byte, `02` seen | unknown; did not move for Tone & voice prompts or Auto Power Off |
| `0x140b` | 6 bytes, all zero | unknown |

The actual Hi-Res setting (aptX Adaptive, 24 bit/96 kHz) was **not found**. It
is also inert on Linux: WirePlumber offers SBC/AAC/aptX/aptX HD only, so the
link negotiates aptX HD at 44.1 or 48 kHz whatever the headphones are set to.

### Auto Power Off and events (`0x06xx`, `0x08xx`, `0x04xx`)

| Command | Payload | Meaning |
|---|---|---|
| `0x0601` get | `00` → `00 <sec:u16>` | **Auto Power Off** in seconds; `0` = Never. An *empty* get is rejected with `0x05` — the index byte is why no sweep ever found it. Read as 3600/1800 as the app was stepped through 60/30 |
| `0x0600` set | `00 <sec:u16>` | Setter; accepted with the current value |
| `0x0682` push | byte | **Charging**: `01` when the cable goes in, `00` when it comes out — from the headphones, so a wall charger counts. No getter found (`0x0601 [01..10]`, `0x0605`, `0x0603 [n]` all miss), so it can only be observed, not polled |
| `0x0880` push | byte | Audio link state: `0b` active, `ff` idle |
| `0x089a` push | u32 | Active stream sample rate: `0xac44` 44100 (A2DP), `0xbb80` 48000, `0x3e80` 16000 (HFP voice), `0` stopped |
| `0x0482` push | byte | On-head sensor event (`02`, `03` seen while the headphones were handled) |

Battery over GAIA (`0x0603`) keeps answering while charging — only BlueZ's
`Battery1` went blank on the cable.

### Paired devices (`0x14xx`) — read-only, and one of them is a trap

| Command | Payload | Meaning |
|---|---|---|
| `0x1401` get | `<index>` → `<index> 01 01 <name…> 00` | **Paired device list**: index 0 was the phone, index 1 this PC, names as C strings |
| `0x1403` | `<index>` → bare OK | **Forgets that device.** Found the hard way: an indexed scan sent `0x1403 [00]` and the phone's pairing was gone. Blocklisted |
| `0x0801`, `0x0805`, `0x0817` | `<index>` → bare OK | Also act on a device index, effect unknown; blocklisted on the same signature |

**Rule for indexed scans:** a getter answers an index with *data*; an ID that
answers an indexed payload with an empty OK is an action. Stop at the first
one — do not probe the next index.

**Not found: Tone & voice prompts** (voice / tone only / off, plus a language). Changing them moved no
odd ID in `0x0827–0x1fff` or `0x2001–0x27ff`, and nothing in the response-form
mirrors `0x09xx`/`0x15xx` (which simply repeat `0x08xx`/`0x14xx`). Watching
`0x1401–0x141f` and `0x0807`/`0x0813` live while they were stepped through
every value showed nothing either. What remains is the `0x04xx`/`0x06xx`
hazard group, even-numbered IDs, or gets that need a payload — none of which
is worth another sweep. Also seen and unexplained: `0x0807 = 00`,
`0x0813 = 00`, `0x0819 = 05 00 01 02 03 04`, `0x2003`/`0x2005` (24 zero
bytes), `0x2007` (14 zero bytes).

## ⚠️ `0x06xx` is the power/system group

`0x0607` is not alone. A paced probe of `0x0609–0x06ff` reset the link at
`0x0613`, reconnected, and reset again at `0x0685`; the headphones were
offline shortly after. Polling `0x0403–0x041f` with `0x0601`/`0x0605` also
reset the link once. The resets are certain (the probe logs the ID in flight);
the going-offline is not — the headphones were idle on a desk throughout, and
Auto Power Off was set to 15 minutes, which fits the timing as well as any
command does. Both IDs are in `gaia-probe`'s blocklist regardless; do not
sweep this group.

Why our sweeps missed them: they live in the range that `0x0607` sits in the
middle of, and both sweeps of it took the headphones offline before reaching
the `0x08xx` group. Reading someone else's working implementation beat
sweeping, the same way listening did for EQ.
| `0x1a03` | byte | Noise level, 0 = full ANC … 100 = full transparency |
| `0x1a01` | 6 bytes | Table of `(id, value)` pairs: `01 vv │ 02 vv │ 03 vv` |
| `0x1a00` | 6 bytes | **Writes** the whole `0x1a01` table |

Inside the `0x1a01` table:

| Field | Meaning |
|---|---|
| byte[1] — id 1 | **Anti-wind**: `0` off, `1` max, `2` auto |
| byte[3] — id 2 | Unknown; only ever observed as `0` |
| byte[5] — id 3 | **Adaptive** (`1`) vs **Custom** (`0`) |

The device accepts no partial writes, so changing one field is
read-modify-write.

The app's three-way mode is two things on the wire:

| App mode | `0x1a05` | `0x1a01` id 3 |
|---|---|---|
| Adaptive | on | 1 |
| Custom | on | 0 |
| Off | off | — |

### Equaliser

Five-band parametric. All commands are per-band, indexed 0-4; band 5 and above
answer `0x83`, which is how the band count was confirmed.

| Command | Payload | Meaning |
|---|---|---|
| `0x1001` | `<band><gain>` | **Set** a band's gain |
| `0x1002` | `<band>` | Get a band's gain |
| `0x1003` | any byte | Get all five gains |
| `0x100b` | `<band>` | Centre frequency — 90, 325, 1500, 6500, 6500 Hz |
| `0x100d` | `<band>` | Q factor, fixed point (2048, then 2908) |
| `0x100f` | `<band>` | Filter type (14 on every band) |
| `0x1011` | `<band>` | Unknown, reads zero |
| `0x1013` | — | Unknown, reads `0000` |

**Gain is dB × 10.** Confirmed against Smart Control's Pop preset, which reads
`0/20/25/15/-20` on the wire and `0/2.0/2.5/1.5/-2.0` dB in the UI.

`0x100f` and `0x1013` appeared with firmware 3.x — that update added the
parametric EQ.

**Presets are not on the device.** Smart Control holds them and pushes each band
in turn; there is no preset-switch command and no list to read. A run of
`0x1082` notifications with one byte changing per packet is Smart Control
applying a preset.

Smart Control identifies the active preset by **matching the curve values**, so
writing a preset's exact gains from anywhere — this plugin included — makes it
tick that preset in the app. Write different values and it reads as custom.

### Sound mode, bass, controls

| Command | Payload | Meaning |
|---|---|---|
| `0x0804` | — | Read sound mode. Echoes any argument rather than writing |
| `0x0803` | 2 bytes | **Set** sound mode: `0001` Graphic EQ, `0002` Speech Clarity |
| `0x1009` | byte | Bass boost. Rejected on firmware 2.x, works on 3.x |
| `0x1607` | byte | Touch controls. **Inverted**: `0` enabled, `1` disabled |
| `0x1606` | byte | Set touch controls |
| `0x1201` | 3× uint16 BE | Firmware version (`2,13,42` then `3,38,3`) |

Speech Clarity does **not** stop the device answering EQ or bass-boost
commands — Smart Control greys them out as a UI convention only.

## ⚠️ 0x0607 takes the headphones offline

**Do not send it.** Two independent sweeps of `0x0000-0x0FFF`, one unpaced and
one at 0.12s with reconnect handling, both died at exactly this id with
"Connection reset by peer", after which the headphones dropped off the bus and
needed a power cycle. Probably a reset or disconnect in GAIA's core space.
`gaia-probe` skips it unconditionally.

## Tools

| Tool | Purpose |
|---|---|
| `bin/m4ctl` | The CLI, and the protocol implementation everything else reuses |
| `bin/m4status` | One JSON line for the bar widget |
| `tools/gaia-probe` | Sweep a command range and report what answers |
| `tools/gaia-diff` | Compare two probe captures |
| `tools/gaia-watch` | Poll specific commands, reporting which byte changed |
| `tools/gaia-listen` | Register for notifications and print what the device pushes |
| `tools/eq-capture` | Record each EQ curve as presets are cycled in Smart Control |

Captures live in `probes/`, including both sides of the 2.13.42 → 3.38.3
firmware update.

## Method — and three traps

**Sweeping cannot see parameterised commands.** `gaia-probe` sends empty
payloads, and a command needing an argument answers with the *error* form,
indistinguishable from unsupported:

```
0x1003 empty payload  -> 0x1183 (error)
0x1003 payload 00     -> 0x1103 (ok, returns the EQ curve)
```

Three sweeps therefore filed the EQ under "rejected" and missed it entirely,
along with ~490 other commands per sweep that remain unexplored for the same
reason.

**A success reply is weak evidence.** This firmware acks most unknown ids in a
range with an identical one-byte payload — 62 of 64 "supported" results in
`0x1A00-0x1AFF` were the same blind ack. Group replies by payload and look at
the outliers.

**Listening beats sweeping.** `gaia-listen` found the EQ command in seconds
after three sweeps had failed, because the device volunteers the command id
when a setting changes. It also found the sound-mode switch at `0x080x` — a
range never swept, because `0x0607` sits in the middle of it. Everything else
had been found in `0x1xxx` purely because that is where the first finds
happened to be.

## Not found

- **Phone calls** (transparency during calls) and its level slider
- **Auto-pause** (pause when transparency is enabled)

Neither appeared in any sweep, nor in the notification stream while they were
toggled. They may be phone-side behaviour: Smart Control detects the call and sends
the transparency command the headphones already understand, needing no device
setting at all.
