<!-- Marketplace submission for omarchyplugins.com. To send:
gh issue create --repo HANCORE-linux/omarchy-plugin-marketplace --title "[Plugin]: Sennheiser Momentum 4" --body-file docs/SUBMISSION-DRAFT.md
(strip this comment block first; the form also works, paste each section into its field) -->
### Repository URL

https://github.com/DanSmith888/omarchy-momentum4

### Category

Hardware

### Tags

bar, media, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Your Sennheiser Momentum 4, controlled from the bar instead of your phone. Battery in the pill; click it for everything the Smart Control app gives you: Adaptive/Custom/Off noise control with the ANC to Transparency slider, anti-wind, the five-band EQ with all eight presets, bass boost, Speech Clarity, and the device settings (on-head detection, smart pause, auto-answer, auto power off, comfort calls, touch controls). Change something on the phone and the panel follows.

Zero setup: pair the headphones, `omarchy plugin add`, done. No app to install, no daemon, no root, no BlueZ tweaks. Talks straight to the headphones in their own protocol using plain Python from the standard library, as your user, over a Bluetooth socket. `omarchy plugin remove` takes everything with it.

Bonus for tinkerers: PROTOCOL.md documents the Momentum 4's command set, found by reverse-engineering, useful for anyone writing for these headphones on any platform. The `tools/` folder is that research kit; the widget never runs it.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
