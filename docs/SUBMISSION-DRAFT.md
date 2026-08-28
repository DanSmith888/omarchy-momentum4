<!-- Draft marketplace submission. NOT submitted. Review, then:
gh issue create --repo HANCORE-linux/omarchy-plugin-marketplace --title "[Plugin]: Momentum4" --body-file docs/SUBMISSION-DRAFT.md
(strip this comment first, and push the repo + v1.0.0 tag before submitting) -->
### Repository URL

https://github.com/DanSmith888/omarchy-momentum4

### Category

Hardware

### Tags

bar, media, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Self-contained: stdlib Python only, no external binaries, no network access. Talks to BlueZ over D-Bus and to the headphones over an RFCOMM socket, as the user.

The plugin never runs sudo. Battery needs `Experimental = true` in /etc/bluetooth/main.conf, which the README asks the user to set themselves as a one-time manual step — that is the only privileged mention and the reason the baseline reports the `privilege` capability.

`tools/` is the reverse-engineering kit behind PROTOCOL.md; the widget never executes it.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
