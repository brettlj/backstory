import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Backstory: a CLIENT-only panel, the floating window around ThisWeekView
// (the HERE card, Needs you, and Recent). The host injects
// `open(payloadJson)` / `close()` per the "panel" plugin kind contract
// (docs/omarchy-shell.md "Plugin manifest").
Item {
  id: root

  // Owned locally (round 4: no more PanelState singleton — see
  // BarWidget.qml's own doc comment. BarWidget's click no longer touches
  // this plugin's own QML state at all; it fires `omarchy-shell shell
  // toggle backstory.this-week {}` and trusts the host to call back into
  // the "panel" kind contract's own open()/close()/toggle() below, the
  // same functions IpcHandler answers).
  property bool opened: false

  // The content, reachable by tests (a QML `id` is not reachable from
  // outside this file).
  readonly property alias view: view

  // Zoom: the card fills the window and content renders at
  // (window width / baseWidth) x userZoom. userZoom is the Ctrl+= / Ctrl+- /
  // Ctrl+0 factor, clamped to [minUserZoom, maxUserZoom].
  readonly property real baseWidth: Style.space(380)
  readonly property real baseHeight: Style.space(640)
  readonly property real minUserZoom: 0.75
  readonly property real maxUserZoom: 2.5
  readonly property real zoomStep: 0.1
  property real userZoom: 1.0
  readonly property real zoom: panel.width / root.baseWidth * root.userZoom

  function setUserZoom(value) {
    var clamped = Math.max(root.minUserZoom, Math.min(root.maxUserZoom, value))
    root.userZoom = Math.round(clamped * 100) / 100
  }

  // The key handler behind Keys.onPressed on the card; returns whether it
  // consumed the key. The window takes the zoom keys; the view takes the rest.
  function handleKey(key, modifiers) {
    if (modifiers !== undefined && (modifiers & Qt.ControlModifier)) {
      switch (key) {
      case Qt.Key_Equal: case Qt.Key_Plus: root.setUserZoom(root.userZoom + root.zoomStep); return true
      case Qt.Key_Minus: root.setUserZoom(root.userZoom - root.zoomStep); return true
      case Qt.Key_0: root.setUserZoom(1.0); return true
      }
    }
    return view.handleKey(key, modifiers)
  }

  // Test-only handles onto the FloatingWindow's own `id: panel` (harmless on
  // the real desk: FloatingWindow genuinely has contentItem/implicitWidth/
  // implicitHeight — a QML `id` just isn't reachable from outside this
  // file any other way). qmltest/tests/tst_panel.qml's generic layout-
  // bounds walker (task 4fe02e30 DONE WHEN clause 3) uses these.
  readonly property Item testContentItem: panel.contentItem
  readonly property var testWindow: panel
  readonly property Item testKeyItem: card
  readonly property Item testScroller: view.scrollArea
  readonly property real testImplicitWidth: panel.implicitWidth
  readonly property real testImplicitHeight: panel.implicitHeight

  // Stable window title (Quickshell sets no per-window app_id; Hyprland matches the title) the Hyprland windowrule in
  // ops/hyprland/backstory.lua matches (hyprland_windowrule_test.go and
  // tst_panel_window.qml pin the two together).
  readonly property string windowTitle: "backstory"

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    root.opened ? root.close() : root.open("{}")
  }

  IpcHandler {
    target: "backstory.this-week"
    function open(): string { root.open("{}"); return "ok" }
    function close(): string { root.close(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function refresh(): string { view.refresh(); return "ok" }
    function ping(): string { return "ok" }
  }

  // A regular xdg toplevel (NOT a wlr-layer-shell PanelWindow): Hyprland
  // manages toplevels, so Omarchy's own move/resize binds (SUPER+drag,
  // resize keys) work on it. ops/hyprland/backstory.lua floats it by
  // windowTitle at a default size/position.
  FloatingWindow {
    id: panel
    title: root.windowTitle
    color: "transparent"
    // Re-applies on every opened change, and survives a direct write to
    // panel.visible (which would sever a plain `visible: root.opened` binding).
    Binding { target: panel; property: "visible"; value: root.opened }
    // The window can be hidden by the host/compositor, not only by close():
    // opened follows, so the next toggle() opens instead of "closing" a
    // window that is already gone.
    onVisibleChanged: if (!panel.visible && root.opened) root.close()
    implicitWidth: root.baseWidth
    implicitHeight: Math.min(root.baseHeight, view.implicitHeight * root.zoom)

    BorderSurface {
      id: card
      width: panel.width
      height: panel.height
      color: Util.alpha(Commons.Color.popups.background, 0.98)
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      // Fades in on every open, growing from just under full size, as
      // Omarchy's own panels do (Ui/PopupCard.qml); closing hides it at once.
      // Style.duration (Omarchy 4.5+) makes it 0 when `omarchy toggle
      // animations` is off; 4.0 has no such helper, so it always fades there.
      property real shown: root.opened ? 1 : 0
      Behavior on shown {
        id: showing
        NumberAnimation {
          duration: showing.targetValue > 0 ? (typeof Style.duration === "function" ? Style.duration(180) : 180) : 0
          easing.type: Easing.OutCubic
        }
      }
      opacity: shown
      scale: 0.97 + 0.03 * shown
      transformOrigin: Item.Top

      // Key handling lives on the card so a key reaches it from anywhere in
      // the panel's own subtree; a child that accepts a key (a text field)
      // keeps it.
      focus: root.opened
      Keys.onPressed: (event) => { event.accepted = root.handleKey(event.key, event.modifiers) }

      // Everything scales as one: the view is laid out at card size / zoom
      // and scaled up by zoom, so text, rows and spacing grow together and
      // the extra height scrolls in the view's Flickable.
      ThisWeekView {
        id: view
        width: card.width / root.zoom
        height: card.height / root.zoom
        scale: root.zoom
        transformOrigin: Item.TopLeft
        active: root.opened
        onCloseRequested: root.close()
      }
    }
  }
}
