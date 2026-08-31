<!-- Marketplace submission for omarchyplugins.com. To send:
gh issue create --repo HANCORE-linux/omarchy-plugin-marketplace --title "[Plugin]: Momentum4" --body-file docs/SUBMISSION-DRAFT.md
(strip this comment block first; the form also works — paste each section into its field) -->
### Repository URL

https://github.com/DanSmith888/omarchy-momentum4

### Category

Hardware

### Tags

bar, media, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Battery, noise control, EQ and device settings for the Sennheiser Momentum 4, in the bar. Speaks the headphones' own GAIA protocol over RFCOMM — no external CLI, no daemon, no network, no root. Plain Python from the standard library; the widget runs `bin/m4status` and `bin/m4ctl` as the user, which ask `bluetoothctl` which device is connected and then talk to the headphones over a Bluetooth socket. The only file written outside the plugin folder is a lock in `$XDG_RUNTIME_DIR`.

Install is a single `omarchy plugin add`; nothing in BlueZ or /etc needs changing. `omarchy plugin remove` takes everything with it.

`tools/` is the reverse-engineering kit behind PROTOCOL.md (which documents the command set for anyone else writing for these headphones). The widget never executes it.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
