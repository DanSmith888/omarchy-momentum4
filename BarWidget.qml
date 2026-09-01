import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Sennheiser Momentum 4: the battery pill in the bar, and the host for the
// control panel.
//
// This is the manifest entry point. It owns nothing but the pill and the IPC
// target; every piece of device state lives in Panel.qml, which is loaded
// here and read through panelLoader.item. That split is the shape the shell
// routes on, Bar.findPanelWidget looks for open/close/opened on the widget
// mounted in the bar slot, and the popout coordinator identifies the panel
// by that same widget, so the pill must be the thing the bar sees.
BarWidget {
  id: root
  moduleName: "dansmith888.momentum4"

  readonly property var panel: panelLoader.item

  // Mirrors of the panel's state, so the pill has nothing to compute.
  readonly property bool devicePresent: panel ? panel.devicePresent === true : false
  readonly property bool present: panel ? panel.present === true : false
  readonly property bool low: panel ? panel.low === true : false
  readonly property bool charging: panel ? panel.charging === true : false
  readonly property int percentage: panel ? panel.percentage : -1
  readonly property string deviceName: panel ? panel.deviceName : ""

  // ---- Panel lifecycle. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool opened: panel ? panel.opened === true : false

  function open() { if (panel) panel.open() }
  function close() { if (panel) panel.close() }
  function togglePanel() { if (panel) panel.toggle() }
  function refresh() { if (panel) panel.refresh() }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panel ? panel.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() { if (panel) panel.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Hidden, not removed, when no headphones are connected: the slot stays in
  // shell.json and the pill reappears on its own once they pair.
  visible: root.devicePresent
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Single IPC target for the plugin; Panel.qml sets manageIpc: false so the
  // two never register the same name twice.
  //   omarchy-shell shell toggle dansmith888.momentum4
  IpcHandler {
    target: "dansmith888.momentum4"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.broadcast("refresh") }
  }

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
      if (root.present) t += ", " + root.percentage + "%"
      if (root.charging) t += root.present ? " (USB-C connected)" : ", USB-C connected"
      else if (!root.present) t += ", battery unknown"
      if (root.panel && root.panel.stale) t += " (last known, device busy)"
      return t
    }

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    // Scroll on the pill nudges the ANC ↔ Transparency slider.
    onWheelMoved: function(delta) {
      if (!root.panel || !root.panel.ancSupported || root.panel.uiLevel < 0) return
      root.panel.setUiLevel(root.panel.uiLevel + (delta > 0 ? 10 : -10))
    }
  }
}
