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
  property int transparency: -1
  property var bassBoost: null        // null = unsupported on this firmware
  property var controls: null         // on-cup touch/button controls
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
        if (out === "") { root.percentage = -1; return }
        try {
          var d = JSON.parse(out)
          root.percentage   = (typeof d.battery === "number") ? d.battery : -1
          root.deviceName   = d.name || ""
          root.ancSupported = d.anc_supported === true
          root.ancOn        = d.anc === true
          if (typeof d.transparency === "number") root.transparency = d.transparency
          root.bassBoost = (typeof d.bass_boost === "boolean") ? d.bass_boost : null
          root.controls = (typeof d.controls === "boolean") ? d.controls : null
        } catch (e) {
          root.percentage = -1
        }
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
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: if (!root.busy) root.refresh()
  }

  visible: present
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // WidgetButton, not BarIconButton: the latter is glyph-only and pins its
  // width to one icon slot, so "90%" would overflow into the next widget.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.present ? "󰋋  " + root.percentage + "%" : "󰋋"
    hasVisualContent: text !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75
    active: root.low
    tooltipText: root.deviceName !== ""
      ? root.deviceName + (root.present ? " — " + root.percentage + "%" : "")
      : "Headphones"

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
          text: root.present ? "Battery " + root.percentage + "%" : "Battery unknown"
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

        // 0 = full transparency, 100 = full ANC. One axis, as the headphones
        // model it — there is no separate ANC on/off that is not just an end
        // of this range.
        PanelSlider {
          id: slider
          anchors.left: parent.left
          anchors.right: parent.right
          visible: root.ancSupported
          bar: root.bar
          minimum: 0
          maximum: 100
          step: 5
          integer: true
          value: root.uiLevel >= 0 ? root.uiLevel : 100
          onMoved: function(v) { root.transparency = root.rawFromUi(v) }
          onReleased: function(v) { root.setUiLevel(v) }
        }

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          height: transparencyLabel.implicitHeight
          visible: root.ancSupported

          Text {
            text: "ANC"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.left: parent.left
          }
          Text {
            id: transparencyLabel
            text: root.uiLevel >= 0 ? root.uiLevel + " / 100" : "—"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.horizontalCenter: parent.horizontalCenter
          }
          Text {
            text: "Transparency"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.right: parent.right
          }
        }

        Row {
          spacing: Style.spacing.sm
          visible: root.ancSupported

          Button {
            text: "ANC"
            bordered: true
            selected: root.uiLevel === 0
            foreground: root.barForeground
            onClicked: root.setUiLevel(0)
          }
          Button {
            text: "Transparency"
            bordered: true
            selected: root.uiLevel === 100
            foreground: root.barForeground
            onClicked: root.setUiLevel(100)
          }
        }

        PanelSeparator {
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: root.barForeground
          visible: root.bassBoost !== null
        }

        PanelSectionHeader {
          text: "BASS BOOST"
          foreground: root.barForeground
          visible: root.bassBoost !== null
        }

        // Only shown when the firmware supports it: 2.13.42 rejects the
        // command outright, 3.38.3 accepts it, so this appears or hides
        // itself depending on what the headphones actually answer.
        Row {
          spacing: Style.spacing.sm
          visible: root.bassBoost !== null

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
