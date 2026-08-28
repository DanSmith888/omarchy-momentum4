import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Sennheiser Momentum 4: battery pill in the bar, noise control in a popup.
//
// Extends Ui/Panel, which is the same base the first-party audio and network
// widgets use — it provides the open/close/toggle contract, IPC target and
// keyboard handling, so the widget and its popup are one component.
//
// Battery comes from BlueZ org.bluez.Battery1 (generic to any headset that
// reports it, and requires `Experimental = true` in /etc/bluetooth/main.conf).
// Noise control speaks GAIA over RFCOMM via bin/m4ctl.
//
// State is polled rather than subscribed: reading noise control means opening
// an RFCOMM socket, and holding that open would lock out other clients.
Panel {
  id: root
  moduleName: "momentum4"
  ipcTarget: "momentum4"

  property int percentage: -1
  property string deviceName: ""
  property bool ancSupported: false
  property bool ancOn: false
  property string mode: ""            // "adaptive" | "custom" | "off"
  property string antiwind: ""
  property int transparency: -1
  property var bassBoost: null        // null = unsupported on this firmware
  property var controls: null         // on-cup touch/button controls
  property var eq: null               // 5 gains in dB
  property var presets: []            // from presets.json via m4ctl
  property bool charging: false       // USB cable attached
  property bool devicePresent: false  // any supported headset connected
  property bool busy: false

  readonly property bool present: percentage >= 0
  readonly property bool low: present && percentage <= 20

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function apply(args) {
    if (!root.ancSupported || root.busy) return
    root.busy = true
    actionProc.command = [root.pluginDir + "bin/m4ctl"].concat(args)
    actionProc.running = true
  }

  // Axis runs ANC (left) to Transparency (right), matching the Sennheiser
  // iOS app. That ordering happens to match the hardware exactly — raw 0 is
  // full ANC and raw 100 is full transparency — so the slider value is the
  // device value and no conversion is needed. The earlier Transparency-left
  // layout read more naturally but required inverting every read and write,
  // and disagreed with the app.
  function rawFromUi(uiLevel) { return Math.max(0, Math.min(100, Math.round(uiLevel))) }
  function uiFromRaw(raw) { return raw }

  readonly property int uiLevel: root.transparency

  function setUiLevel(level) {
    var v = rawFromUi(level)
    root.transparency = v          // optimistic, so the slider does not snap back
    apply(["transparency", String(v)])
  }

  function setBass(on) {
    if (root.bassBoost === null) return
    apply(["bass", on ? "on" : "off"])
  }

  // Only Custom exposes the slider and anti-wind — Adaptive drives them
  // itself and Off bypasses them, exactly as the Sennheiser app does.
  readonly property bool customMode: root.mode === "custom"

  function setMode(m) { if (root.mode !== m) apply(["mode", m]) }
  function setAntiwind(v) { if (root.antiwind !== "") apply(["antiwind", v]) }

  // The device has no preset storage: applying one writes all five bands,
  // exactly as the phone app does.
  function applyPreset(name) { apply(["preset", name]) }

  // Which preset the current curve matches, or "" for a custom curve.
  // Compared in tenths of a dB to avoid round-trip float noise.
  function activePreset() {
    if (!root.eq) return ""
    for (var i = 0; i < root.presets.length; i++) {
      var g = root.presets[i].gains, ok = true
      if (!g || g.length !== root.eq.length) continue
      for (var b = 0; b < g.length; b++)
        if (Math.round(g[b] * 10) !== Math.round(root.eq[b] * 10)) { ok = false; break }
      if (ok) return root.presets[i].name
    }
    return ""
  }

  function setControls(on) {
    if (root.controls === null) return
    apply(["controls", on ? "on" : "off"])
  }

  Process {
    id: statusProc
    command: [root.pluginDir + "bin/hp-status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = String(this.text).trim()
        if (out === "") { root.percentage = -1; root.devicePresent = false; return }
        try {
          var d = JSON.parse(out)
          root.devicePresent = !!d.mac
          root.charging     = d.charging === true
          root.percentage   = (typeof d.battery === "number") ? d.battery : -1
          root.deviceName   = d.name || ""
          root.ancSupported = d.anc_supported === true
          root.ancOn        = d.anc === true
          if (typeof d.transparency === "number") root.transparency = d.transparency
          root.bassBoost = (typeof d.bass_boost === "boolean") ? d.bass_boost : null
          root.controls = (typeof d.controls === "boolean") ? d.controls : null
          root.mode = d.mode || ""
          root.antiwind = d.antiwind || ""
          root.eq = (Array.isArray(d.eq) && d.eq.length) ? d.eq : null
        } catch (e) {
          root.percentage = -1
          root.devicePresent = false
        }
      }
    }
  }

  // Preset definitions are static; load once rather than on every poll.
  Process {
    id: presetProc
    command: [root.pluginDir + "bin/m4ctl", "presets", "--json"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.presets = JSON.parse(String(this.text).trim()) || [] }
        catch (e) { root.presets = [] }
      }
    }
  }

  Process {
    id: actionProc
    onExited: { root.busy = false; root.refresh() }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Poll faster while the popup is open so the readout tracks the device.
  // triggeredOnStart matters: without it the panel shows up to a minute of
  // stale state for the first five seconds after opening, which reads as a
  // bug when the setting was just changed in the phone app.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!root.busy) root.refresh()
  }

  visible: root.devicePresent
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // WidgetButton, not BarIconButton: the latter is glyph-only and pins its
  // width to one icon slot, so "90%" would overflow into the next widget.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Battery vanishes from Bluetooth while the cable is attached, so show a
    // charging glyph rather than an empty pill the user cannot interpret.
    text: root.present ? "󰋋  " + root.percentage + "%"
        : root.charging ? "󰋋  󰂄"
        : "󰋋"
    hasVisualContent: text !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75
    active: root.low
    tooltipText: {
      if (root.deviceName === "") return "Headphones"
      var t = root.deviceName
      if (root.present) t += " — " + root.percentage + "%"
      if (root.charging) t += root.present ? " (charging)" : " — charging"
      else if (!root.present) t += " — battery unknown"
      return t
    }

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }

    onWheelMoved: function(delta) {
      if (!root.ancSupported || root.uiLevel < 0) return
      root.setUiLevel(root.uiLevel + (delta > 0 ? 10 : -10))
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    // panelColumn.implicitHeight excludes its own anchors.margins, so passing
    // it raw made the panel two paddings too short and clipped the last row.
    contentHeight: panel.fittedContentHeight(
      panelColumn.implicitHeight + Style.spacing.panelPadding * 2, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.setUiLevel(root.uiLevel + dx * 10)
      }

      Column {
        id: panelColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.sm

        Text {
          text: root.deviceName !== "" ? root.deviceName : "Headphones"
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          text: root.present ? "Battery " + root.percentage + "%" + (root.charging ? " — charging" : "")
              : root.charging ? "Charging — battery not reported over Bluetooth"
              : "Battery unknown"
          color: root.low ? Color.urgent : Qt.darker(root.barForeground, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelSeparator {
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: root.barForeground
        }

        PanelSectionHeader {
          text: "NOISE CONTROL"
          foreground: root.barForeground
          visible: root.ancSupported
        }

        // Three-way mode, matching the app. On the wire this is two things:
        // ANC on/off (0x1a05) and adaptive-vs-custom (0x1a01 id 3).
        Row {
          spacing: Style.spacing.sm
          visible: root.ancSupported

          Button {
            text: "Adaptive"
            bordered: true
            selected: root.mode === "adaptive"
            foreground: root.barForeground
            onClicked: root.setMode("adaptive")
          }
          Button {
            text: "Custom"
            bordered: true
            selected: root.mode === "custom"
            foreground: root.barForeground
            onClicked: root.setMode("custom")
          }
          Button {
            text: "Off"
            bordered: true
            selected: root.mode === "off"
            foreground: root.barForeground
            onClicked: root.setMode("off")
          }
        }

        // End labels track the mode the way the app does: percentages only
        // when Custom is actually in charge of the split.
        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          height: ancLabel.implicitHeight
          visible: root.ancSupported
          opacity: root.customMode ? 1.0 : 0.45

          Text {
            id: ancLabel
            anchors.left: parent.left
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: root.mode === "adaptive" ? "ANC"
                : root.mode === "off" ? "ANC 0%"
                : "ANC " + (100 - root.uiLevel) + "%"
          }
          Text {
            anchors.right: parent.right
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: root.mode === "adaptive" ? "Transparency"
                : root.mode === "off" ? "0% Transparency"
                : root.uiLevel + "% Transparency"
          }
        }

        PanelSlider {
          id: slider
          anchors.left: parent.left
          anchors.right: parent.right
          visible: root.ancSupported
          enabled: root.customMode
          opacity: root.customMode ? 1.0 : 0.45
          bar: root.bar
          minimum: 0
          maximum: 100
          step: 5
          integer: true
          value: root.uiLevel >= 0 ? root.uiLevel : 0
          onMoved: function(v) { root.transparency = root.rawFromUi(v) }
          onReleased: function(v) { root.setUiLevel(v) }
        }

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          height: awRow.implicitHeight
          visible: root.antiwind !== ""
          opacity: root.customMode ? 1.0 : 0.45

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Anti-wind"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Row {
            id: awRow
            anchors.right: parent.right
            spacing: Style.spacing.sm

            // Tri-state, matching the app: the main switch and its Auto/Max
            // sub-setting are one field on the device.
            Button {
              text: "Off"
              bordered: true
              selected: root.antiwind === "off"
              foreground: root.barForeground
              enabled: root.customMode
              onClicked: root.setAntiwind("off")
            }
            Button {
              text: "Auto"
              bordered: true
              selected: root.antiwind === "auto"
              foreground: root.barForeground
              enabled: root.customMode
              onClicked: root.setAntiwind("auto")
            }
            Button {
              text: "Max"
              bordered: true
              selected: root.antiwind === "max"
              foreground: root.barForeground
              enabled: root.customMode
              onClicked: root.setAntiwind("max")
            }
          }
        }

        PanelSeparator {
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: root.barForeground
          visible: root.bassBoost !== null
        }

        PanelSectionHeader {
          text: "SOUND"
          foreground: root.barForeground
          visible: root.bassBoost !== null || root.eq !== null
        }

        // Presets are ours, not the device's — applying one writes all bands.
        // "Custom" lights when the curve matches no preset, which is what
        // happens as soon as a band is changed by hand.
        Flow {
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.spacing.sm
          visible: root.presets.length > 0 && root.eq !== null

          Repeater {
            model: root.presets
            Button {
              text: modelData.name
              bordered: true
              selected: root.activePreset() === modelData.name
              foreground: root.barForeground
              onClicked: root.applyPreset(modelData.name)
            }
          }

          Button {
            text: "Custom"
            bordered: true
            selected: root.activePreset() === ""
            foreground: root.barForeground
            // Reflects state rather than setting it: clicking does nothing,
            // because "custom" is simply "matches no preset".
            onClicked: {}
          }
        }

        // Only shown when the firmware supports it: 2.13.42 rejects the
        // command outright, 3.38.3 accepts it, so this appears or hides
        // itself depending on what the headphones actually answer.
        // Read-only. The curve reads fine over 0x1003 but the device rejects
        // every write shape tried against 0x1002, so there is nothing honest
        // to offer as a control yet — showing a curve the user cannot change
        // is better than a slider that silently does nothing.
        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          visible: root.eq !== null
          height: Style.space(46)

          readonly property int bands: root.eq ? root.eq.length : 0
          readonly property real maxAbs: 25      // observed range of the presets

          // Zero line
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Qt.darker(root.barForeground, 2.0)
          }

          Row {
            anchors.fill: parent
            spacing: Style.spacing.sm

            Repeater {
              model: root.eq ? root.eq.length : 0

              Item {
                width: (parent.width - (parent.spacing * (root.eq.length - 1))) / root.eq.length
                height: parent.height

                readonly property real v: root.eq[index]
                // Presets observed so far sit within about +/-4 dB.
                readonly property real frac: Math.max(-1, Math.min(1, v / 4))

                Rectangle {
                  width: parent.width
                  // A flat band still gets a sliver, so the bar reads as
                  // "zero" rather than "missing".
                  height: Math.max(2, Math.abs(parent.frac) * (parent.height / 2 - 8))
                  color: root.barForeground
                  opacity: parent.v === 0 ? 0.35 : 0.9
                  radius: 1
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: parent.frac >= 0
                     ? parent.height / 2 - height
                     : parent.height / 2
                }
              }
            }
          }
        }

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          visible: root.eq !== null
          height: eqLabels.implicitHeight

          Row {
            id: eqLabels
            anchors.fill: parent
            spacing: Style.spacing.sm
            Repeater {
              model: root.eq ? root.eq.length : 0
              Text {
                width: (parent.width - (parent.spacing * (root.eq.length - 1))) / root.eq.length
                horizontalAlignment: Text.AlignHCenter
                text: (root.eq[index] > 0 ? "+" : "") + root.eq[index].toFixed(1)
                color: Qt.darker(root.barForeground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // Labelled row, matching how Anti-wind sits under Noise control.
        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          height: bassRow.implicitHeight
          visible: root.bassBoost !== null

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Bass boost"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Row {
            id: bassRow
            anchors.right: parent.right
            spacing: Style.spacing.sm

            Button {
              text: "Off"
              bordered: true
              selected: root.bassBoost === false
              foreground: root.barForeground
              onClicked: root.setBass(false)
            }
            Button {
              text: "On"
              bordered: true
              selected: root.bassBoost === true
              foreground: root.barForeground
              onClicked: root.setBass(true)
            }
          }
        }

        PanelSeparator {
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: root.barForeground
          visible: root.controls !== null
        }

        PanelSectionHeader {
          text: "HEADPHONE CONTROLS"
          foreground: root.barForeground
          visible: root.controls !== null
        }

        // The on-cup touch/button controls. The device stores this inverted
        // (0 = enabled), which m4ctl normalises, so this stays a plain
        // enabled/disabled pair.
        Row {
          spacing: Style.spacing.sm
          visible: root.controls !== null

          Button {
            text: "Off"
            bordered: true
            selected: root.controls === false
            foreground: root.barForeground
            onClicked: root.setControls(false)
          }
          Button {
            text: "On"
            bordered: true
            selected: root.controls === true
            foreground: root.barForeground
            onClicked: root.setControls(true)
          }
        }

        Text {
          text: "Noise control unavailable for this device"
          visible: !root.ancSupported
          color: Qt.darker(root.barForeground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          width: parent.width
        }
      }
    }
  }
}
