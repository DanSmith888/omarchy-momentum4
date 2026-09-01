# Sennheiser Momentum 4

Control Sennheiser Momentum 4 headphones from the [Omarchy](https://omarchy.org/)
bar: battery, noise control, EQ and touch controls, without reaching for
your phone.

![Battery in the bar](docs/bar.png)

![The panel](docs/panel.png)

Built for one set of headphones. It speaks the Momentum 4's own protocol
and will not work with anything else. Plain standard-library Python, no
packages, no binaries, no root.

## Install

Pair the headphones over Bluetooth, then:

```bash
omarchy plugin add https://github.com/DanSmith888/omarchy-momentum4.git --enable
```

### Check it

```bash
~/.config/omarchy/plugins/dansmith888.momentum4/bin/m4ctl doctor
```

Checks every link from the headphones to the bar and says how to fix
whatever is broken.

## Update

```bash
omarchy plugin update dansmith888.momentum4 && omarchy restart shell
```

## Remove

```bash
omarchy plugin remove dansmith888.momentum4
```

Nothing is left behind except a lock file in `$XDG_RUNTIME_DIR`.

## Using it

Left-click the battery pill for the panel. Scroll on it to adjust the noise
level. Middle-click to refresh. From a hotkey:

```bash
omarchy-shell shell toggle dansmith888.momentum4
```

## What it does

Everything Sennheiser's Smart Control app exposes that the headphones will
report:

- Battery in the bar; in the panel, the codec and sample rate PipeWire is
  sending (aptX HD at 44.1 kHz, for example)
- Noise control: Adaptive, Custom or Off, with the ANC to Transparency slider
- Anti-wind: Off, Auto or Max
- Sound mode: Graphic EQ or Speech Clarity
- Five-band EQ: Smart Control's eight presets, or drag any band
- Bass boost
- Touch controls on or off
- Device settings: On-head Detection, Smart Pause, Auto-Answer Calls,
  Comfort Calls, Auto Power Off

Not covered: tone and voice prompts, and Hi-Res mode (their commands were
not found; see [PROTOCOL.md](PROTOCOL.md)). Hi-Res is moot on Linux, where
the link is aptX HD regardless.

Everything is read back from the headphones, so a change made in Smart
Control shows up here.

## Requirements

- Omarchy with `omarchy-shell`
- A Sennheiser Momentum 4, paired over Bluetooth
- Python 3, standard library only

## Command line

```bash
m4ctl get [--json]
m4ctl mode adaptive|custom|off
m4ctl antiwind off|auto|max
m4ctl transparency 0-100        # 0 = full ANC, 100 = full transparency
m4ctl sound-mode eq|speech
m4ctl preset Rock               # m4ctl presets lists them
m4ctl eq                        # show the curve
m4ctl eq-set 2 -1.5             # band 0-4, gain in dB
m4ctl bass on|off
m4ctl controls on|off
m4ctl auto-answer on|off
m4ctl comfort-call on|off
m4ctl smart-pause on|off
m4ctl on-head on|off
m4ctl auto-off never|15|30|60   # minutes idle before power off
m4ctl doctor
```

## Hacking on it

```bash
omarchy plugin validate .

# Qt 6 qmllint with the shell's qs.* imports resolvable (/usr/bin/qmllint is Qt 5).
mkdir -p "$XDG_RUNTIME_DIR/qsroot" && ln -sfn "$OMARCHY_PATH/shell" "$XDG_RUNTIME_DIR/qsroot/qs"
/usr/lib/qt6/bin/qmllint -I "$XDG_RUNTIME_DIR/qsroot" BarWidget.qml Panel.qml

# Copy into the plugins dir (never symlink; the validator rejects symlinks).
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/dansmith888.momentum4/
omarchy-shell shell toggle dansmith888.momentum4
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

`Style.*` "not found on type QObject" lint messages are noise; anything
tagged `[syntax]` is real.

## Good to know

- **Charging is not shown.** The headphones announce cable in and out but
  cannot be asked, and this widget polls. Battery keeps reading normally
  while charging.
- **"USB-C connected" means plugged into this PC**, detected when the
  headphones enumerate as a USB audio card (`/proc/asound/cards`). A wall
  charger or another machine shows nothing.
- **EQ presets live in this repo** ([`presets.json`](presets.json)), not in
  the headphones, which only hold the active curve. Smart Control ticks
  whichever preset matches the current curve, so if you edit a preset here
  it will show as a custom curve there.
- **Band labels are Smart Control's** (63 Hz to 8 kHz). The hardware's real
  centres are 90/325/1500/6500/6500 Hz.

## What runs, and as whom

Plugins run unsandboxed inside the Omarchy shell as your user.

- `bin/m4status` and `bin/m4ctl` ask `bluetoothctl` which device is
  connected and talk to the headphones over an RFCOMM socket. Nothing else.
- No root, no network, no background services, no writes outside
  `$XDG_RUNTIME_DIR` (a lock file).
- `tools/` is the reverse-engineering kit behind [PROTOCOL.md](PROTOCOL.md).
  The widget never runs it. `tools/gaia-probe` sends arbitrary commands to
  the headphones; read its `--help` first.

## Related

[omarchy-momentumctl](https://github.com/timmo001/omarchy-momentumctl) is
another Omarchy panel for Sennheiser headsets, built on the
[`momentumctl`](https://github.com/gjabell/momentumctl) CLI, whose source
supplied the battery and call command IDs used here.

## Protocol

[PROTOCOL.md](PROTOCOL.md) documents the Momentum 4's GAIA command set:
IDs, payloads, the tools used to find them, and the traps. Useful for
anything else you write for these headphones, on any platform.

## Credits

Protocol constants and the RFCOMM channel-probing approach come from
[momentum4-control](https://github.com/f3Y0/momentum4-control) by f3Y0
(MIT). The battery, on-head, auto-answer, Smart Pause and Comfort Call
command IDs come from [momentumctl](https://github.com/gjabell/momentumctl)
by gjabell (MIT).

## Licence

MIT, see [LICENSE](LICENSE).
