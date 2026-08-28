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
| `bin/gaia-probe` | Sweep a command range and report what answers |
| `bin/gaia-diff` | Compare two probe captures |
| `bin/gaia-watch` | Poll specific commands, reporting which byte changed |
| `bin/gaia-listen` | Register for notifications and print what the device pushes |
| `bin/eq-capture` | Record each EQ curve as presets are cycled in Smart Control |

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
