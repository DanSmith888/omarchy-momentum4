import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bluetooth headphone battery, with noise control for devices that support it.
//
// Battery comes from BlueZ's org.bluez.Battery1 via `bin/hp-battery`, which is
// generic: any Bluetooth headset that reports battery will show up. It needs
// `Experimental = true` in /etc/bluetooth/main.conf, since BlueZ gates that
// interface behind it.
//
// Noise control is device-specific and handled by `bin/m4ctl` (Sennheiser
// Momentum 4, GAIA over RFCOMM). Devices without a backend still get a battery
// reading — the widget degrades to display-only rather than disappearing.
BarWidget {
  id: root
  moduleName: "headphones"

  property int percentage: -1
  property string deviceName: ""
  property bool ancSupported: false
  property bool ancOn: false
  property int transparency: -1

  readonly property bool present: percentage >= 0
  readonly property bool low: present && percentage <= 20

  // WidgetButton, not BarIconButton: the latter is glyph-only (labelVisible
  // false, fixedWidth pinned to slotSize), so text wider than one icon slot
  // overflows into the neighbouring widget.
  visible: present
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  Process {
    id: statusProc
    command: [Qt.resolvedUrl("bin/hp-status").toString().replace("file://", "")]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = this.text.trim()
        if (out === "") { root.percentage = -1; return }
        try {
          var d = JSON.parse(out)
          root.percentage   = (typeof d.battery === "number") ? d.battery : -1
          root.deviceName   = d.name || ""
          root.ancSupported = d.anc_supported === true
          root.ancOn        = d.anc === true
          root.transparency = (typeof d.transparency === "number") ? d.transparency : -1
        } catch (e) {
          root.percentage = -1
        }
      }
    }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  function setTransparency(level) {
    if (!root.ancSupported) return
    actionProc.command = [
      Qt.resolvedUrl("bin/m4ctl").toString().replace("file://", ""),
      "transparency", String(level)
    ]
    actionProc.running = true
  }

  // Poll rather than subscribe: BlueZ emits PropertiesChanged for battery, but
  // the noise-control state has to be read over RFCOMM, and holding that socket
  // open would block other clients. A minute is plenty for a battery figure.
  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-headphones, then the percentage.
    text: root.present ? "󰋋  " + root.percentage + "%" : "󰋋"
    hasVisualContent: text !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75
    active: root.low
    tooltipText: {
      var parts = []
      if (root.deviceName !== "") parts.push(root.deviceName)
      if (root.present) parts.push(root.percentage + "%")
      if (root.ancSupported)
        parts.push(root.transparency >= 0
          ? "Noise control " + root.transparency + "/100"
          : (root.ancOn ? "ANC on" : "ANC off"))
      return parts.length ? parts.join(" — ") : "Headphones"
    }

    onPressed: function(b) {
      if (b === Qt.MiddleButton) { root.refresh(); return }
      if (!root.ancSupported) { root.refresh(); return }
      // Left cycles ANC -> transparency -> ANC; right jumps straight to full ANC.
      if (b === Qt.RightButton) root.setTransparency(100)
      else root.setTransparency(root.transparency >= 50 ? 0 : 100)
    }

    onWheelMoved: function(delta) {
      if (!root.ancSupported || root.transparency < 0) return
      root.setTransparency(Math.max(0, Math.min(100, root.transparency + (delta > 0 ? 10 : -10))))
    }
  }
}
