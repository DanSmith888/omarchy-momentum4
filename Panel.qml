import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Sennheiser Momentum 4: the control panel, and the owner of all device state.
//
// Loaded by BarWidget.qml (the manifest entry point), which injects bar,
// anchorItem and hostWidget and forwards open/close/toggle to us. Extends
// Ui/Panel for the open/close controller and keyboard handling; IPC is left
// to the bar widget so the target is registered once.
//
// Everything, battery included, speaks GAIA over RFCOMM via bin/m4ctl. No
// BlueZ extras and no root are involved.
//
// State is polled rather than subscribed: reading the device means opening
// an RFCOMM socket, and holding that open would lock out other clients.
Panel {
  id: root
  moduleName: "dansmith888.momentum4"
  manageIpc: false

  // Injected by BarWidget.qml. The bar tracks the widget mounted in its slot,
  // not this nested panel, so everything the bar identifies a panel by has to
  // be that widget.
  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

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
  property string soundMode: ""       // "eq" | "speech"
  // Plain on/off features; null = the firmware did not answer.
  property var autoAnswer: null
  property var comfortCall: null
  property var smartPause: null
  property var onHead: null
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

  // Speech Clarity replaces the graphic EQ and bass boost in the app. The
  // device still answers those commands in either mode, so the dimming here
  // is a deliberate mirror of the app rather than something the hardware
  // enforces.
  readonly property bool eqMode: root.soundMode !== "speech"
  function setSoundMode(m) { if (root.soundMode !== m) apply(["sound-mode", m]) }

  readonly property real eqRange: 6.0   // dB shown at full bar height

  // Drag and scroll update the local curve immediately so the bar tracks the
  // finger, and only commit on release — writing on every pixel of a drag
  // would queue dozens of RFCOMM round trips behind the lock.
  function setEqLocal(band, db) {
    if (!root.eq) return
    var next = root.eq.slice()
    next[band] = Math.max(-root.eqRange, Math.min(root.eqRange, Math.round(db * 10) / 10))
    root.eq = next
  }

  function commitEqBand(band) {
    if (!root.eq) return
    apply(["eq-set", String(band), String(root.eq[band])])
  }

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

  function setFeature(cmd, current, on) {
    if (current === null) return
    apply([cmd, on ? "on" : "off"])
  }

  function setControls(on) {
    if (root.controls === null) return
    apply(["controls", on ? "on" : "off"])
  }

  Process {
    id: statusProc
    command: [root.pluginDir + "bin/m4status"]
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
          root.soundMode = d.sound_mode || ""
          root.autoAnswer  = (typeof d.auto_answer  === "boolean") ? d.auto_answer  : null
          root.comfortCall = (typeof d.comfort_call === "boolean") ? d.comfort_call : null
          root.smartPause  = (typeof d.smart_pause  === "boolean") ? d.smart_pause  : null
          root.onHead      = (typeof d.on_head      === "boolean") ? d.on_head      : null
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

  // Poll quickly while nothing is connected and slowly once something is.
  // A flat 60s meant the widget could take a full minute to appear after the
  // headphones woke and paired, which reads as "it isn't working".
  Timer {
    interval: root.devicePresent ? 60000 : 5000
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    // panelColumn.implicitHeight excludes its own anchors.margins, so passing
    // it raw made the panel two paddings too short and clipped the last row.
    contentHeight: panel.fittedContentHeight(
      panelColumn.implicitHeight + Style.spacing.panelPadding * 2, Style.space(900))

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

        Row {
          spacing: Style.spacing.sm
          visible: root.soundMode !== ""

          Button {
            text: "Graphic EQ"
            bordered: true
            selected: root.soundMode === "eq"
            foreground: root.barForeground
            tooltipText: "Five-band equaliser with presets"
            onClicked: root.setSoundMode("eq")
          }
          Button {
            text: "Speech Clarity"
            bordered: true
            selected: root.soundMode === "speech"
            foreground: root.barForeground
            tooltipText: "Tunes for voice. Replaces the equaliser and bass boost, which are disabled while it is on."
            onClicked: root.setSoundMode("speech")
          }
        }

        // Separates the mode choice from the controls that mode governs.
        PanelSeparator {
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: root.barForeground
          visible: root.soundMode !== ""
        }

        PanelSectionHeader {
          text: "EQUALISER"
          foreground: root.barForeground
          visible: root.eq !== null
          opacity: root.eqMode ? 1.0 : 0.4
        }

        // Presets are ours, not the device's — applying one writes all bands.
        // "Custom" lights when the curve matches no preset, which is what
        // happens as soon as a band is changed by hand.
        Flow {
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.spacing.sm
          visible: root.presets.length > 0 && root.eq !== null
          enabled: root.eqMode
          opacity: root.eqMode ? 1.0 : 0.4

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

        // One PanelSlider per band, rotated upright so it matches the noise
        // control above rather than being a bespoke widget. Reads over
        // 0x1003, writes per band over 0x1001.
        Row {
          anchors.left: parent.left
          anchors.right: parent.right
          visible: root.eq !== null
          enabled: root.eqMode
          opacity: root.eqMode ? 1.0 : 0.4
          spacing: Style.spacing.sm

          Repeater {
            model: root.eq ? root.eq.length : 0

            Column {
              id: bandCol
              width: (parent.width - (parent.spacing * (root.eq.length - 1))) / root.eq.length
              spacing: 2

              readonly property real v: root.eq[index]

              Item {
                width: parent.width
                height: Style.space(74)

                PanelSlider {
                  // Rotated, so its width becomes the visible height.
                  width: parent.height
                  rotation: -90
                  anchors.centerIn: parent
                  bar: root.bar
                  minimum: -root.eqRange
                  maximum: root.eqRange
                  step: 0.5
                  value: bandCol.v
                  onMoved: function(nv) { root.setEqLocal(index, nv) }
                  onReleased: function(nv) {
                    root.setEqLocal(index, nv)
                    root.commitEqBand(index)
                  }
                }
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: (bandCol.v > 0 ? "+" : "") + bandCol.v.toFixed(1)
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              // The app's nominal labels; the device's real centres are
              // 90/325/1500/6500/6500 Hz.
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: ["63Hz", "250Hz", "1kHz", "4kHz", "8kHz"][index]
                color: Qt.darker(root.barForeground, 1.5)
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
          enabled: root.eqMode
          opacity: root.eqMode ? 1.0 : 0.4

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
          text: "TOUCH CONTROLS"
          foreground: root.barForeground
          visible: root.controls !== null
        }

        // The on-cup touch/button controls. The device stores this inverted
        // (0 = enabled), which m4ctl normalises, so this stays a plain
        // enabled/disabled pair.
        Item {
          width: parent.width
          height: controlsRow.height
          visible: root.controls !== null

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Touch controls"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Row {
            id: controlsRow
            anchors.right: parent.right
            spacing: Style.spacing.sm

            Button {
              text: "Off"
              bordered: true
              selected: root.controls === false
              foreground: root.barForeground
              tooltipText: "Enable or disable the touch controls on the ear cup"
              onClicked: root.setControls(false)
            }
            Button {
              text: "On"
              bordered: true
              selected: root.controls === true
              foreground: root.barForeground
              tooltipText: "Enable or disable the touch controls on the ear cup"
              onClicked: root.setControls(true)
            }
          }
        }

        PanelSeparator {
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: root.barForeground
          visible: root.onHead !== null || root.smartPause !== null || root.autoAnswer !== null || root.comfortCall !== null
        }

        // Smart Control's Device Settings pane, in its order. Descriptions are
        // the app's own, as tooltips.
        PanelSectionHeader {
          text: "DEVICE SETTINGS"
          foreground: root.barForeground
          visible: root.onHead !== null || root.smartPause !== null || root.autoAnswer !== null || root.comfortCall !== null
        }

        Item {
          width: parent.width
          height: onHeadRow.height
          visible: root.onHead !== null

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "On-head Detection"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Row {
            id: onHeadRow
            anchors.right: parent.right
            spacing: Style.spacing.sm

            Button {
              text: "Off"
              bordered: true
              selected: root.onHead === false
              foreground: root.barForeground
              tooltipText: "Enable smart pause, hold calls automatically, power saving mode"
              onClicked: root.setFeature("on-head", root.onHead, false)
            }
            Button {
              text: "On"
              bordered: true
              selected: root.onHead === true
              foreground: root.barForeground
              tooltipText: "Enable smart pause, hold calls automatically, power saving mode"
              onClicked: root.setFeature("on-head", root.onHead, true)
            }
          }
        }

        Item {
          width: parent.width
          height: smartPauseRow.height
          visible: root.smartPause !== null
          // On-head Detection gates Smart Pause (the app's own description
          // says so), so it reads as unavailable while the sensor is off.
          enabled: root.onHead !== false
          opacity: root.onHead !== false ? 1.0 : 0.4

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Smart Pause"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Row {
            id: smartPauseRow
            anchors.right: parent.right
            spacing: Style.spacing.sm

            Button {
              text: "Off"
              bordered: true
              selected: root.smartPause === false
              foreground: root.barForeground
              tooltipText: "Pause music by taking headphones off. Continue when putting back on."
              onClicked: root.setFeature("smart-pause", root.smartPause, false)
            }
            Button {
              text: "On"
              bordered: true
              selected: root.smartPause === true
              foreground: root.barForeground
              tooltipText: "Pause music by taking headphones off. Continue when putting back on."
              onClicked: root.setFeature("smart-pause", root.smartPause, true)
            }
          }
        }

        Item {
          width: parent.width
          height: autoAnswerRow.height
          visible: root.autoAnswer !== null

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Auto-Answer Calls"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Row {
            id: autoAnswerRow
            anchors.right: parent.right
            spacing: Style.spacing.sm

            Button {
              text: "Off"
              bordered: true
              selected: root.autoAnswer === false
              foreground: root.barForeground
              tooltipText: "Answers calls when you put headphones on."
              onClicked: root.setFeature("auto-answer", root.autoAnswer, false)
            }
            Button {
              text: "On"
              bordered: true
              selected: root.autoAnswer === true
              foreground: root.barForeground
              tooltipText: "Answers calls when you put headphones on."
              onClicked: root.setFeature("auto-answer", root.autoAnswer, true)
            }
          }
        }

        Item {
          width: parent.width
          height: comfortCallRow.height
          visible: root.comfortCall !== null

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Comfort Calls"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Row {
            id: comfortCallRow
            anchors.right: parent.right
            spacing: Style.spacing.sm

            Button {
              text: "Off"
              bordered: true
              selected: root.comfortCall === false
              foreground: root.barForeground
              tooltipText: "Gives phone calls a more natural sound stage"
              onClicked: root.setFeature("comfort-call", root.comfortCall, false)
            }
            Button {
              text: "On"
              bordered: true
              selected: root.comfortCall === true
              foreground: root.barForeground
              tooltipText: "Gives phone calls a more natural sound stage"
              onClicked: root.setFeature("comfort-call", root.comfortCall, true)
            }
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
