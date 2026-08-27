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

  function setTransparency(level) {
    var v = Math.max(0, Math.min(100, Math.round(level)))
    root.transparency = v          // optimistic, so the slider does not snap back
    apply(["transparency", String(v)])
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
      if (!root.ancSupported || root.transparency < 0) return
      root.setTransparency(root.transparency + (delta > 0 ? 10 : -10))
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
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.setTransparency(root.transparency + dx * 10)
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
          value: root.transparency >= 0 ? root.transparency : 100
          onMoved: function(v) { root.transparency = Math.round(v) }
          onReleased: function(v) { root.setTransparency(v) }
        }

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          height: transparencyLabel.implicitHeight
          visible: root.ancSupported

          Text {
            text: "Transparency"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.left: parent.left
          }
          Text {
            id: transparencyLabel
            text: root.transparency >= 0 ? root.transparency + " / 100" : "—"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.horizontalCenter: parent.horizontalCenter
          }
          Text {
            text: "ANC"
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
            text: "Transparency"
            bordered: true
            selected: root.transparency === 0
            foreground: root.barForeground
            onClicked: root.setTransparency(0)
          }
          Button {
            text: "ANC"
            bordered: true
            selected: root.transparency === 100
            foreground: root.barForeground
            onClicked: root.setTransparency(100)
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
