import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "js/launchers.js" as Launchers
import "js/popout.js" as Popout

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
  // Pinned, the window shows on every workspace (Hyprland's pin); it opens
  // unpinned, on the workspace it opened on.
  property bool pinned: false

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

  // A summon's payload may carry a view snapshot (the bar popup's pop-out:
  // ThisWeekView.snapshot()); the window then opens where the popup was. A
  // plain "{}" (CTRL+SHIFT+B, IPC) opens as it always has. Any process can
  // send a payload, so an oversized or unreadable one is ignored.
  function open(payloadJson) {
    var state = null
    if (typeof payloadJson === "string" && payloadJson.length <= 65536) {
      try { state = JSON.parse(payloadJson) } catch (e) { state = null }
    }
    // A pop-out starts before the window maps, so it maps hidden.
    var from = state && typeof state === "object" ? Popout.fromRect(state.from) : null
    if (!root.opened && from) root.startPopOut(from)
    if (!root.opened) root.pinned = false
    root.opened = true
    if (state && typeof state === "object" && state.view !== undefined) view.restore(state)
  }

  // ---- The pop-out from the bar popup (BarWidget.qml sends `from`) ----
  // The window maps under popOutTitle, which ops/hyprland/backstory.lua draws
  // with no decorations, and with the card hidden. Once it sits on the
  // popup's card and has its data it shows, with its usual title, and closes
  // the popup, which fades out over it; then Hyprland moves it one diagonal
  // step to rest (js/popout.js restRect). popOutGrow is how much taller it
  // gets on the way.
  readonly property string popOutTitle: root.windowTitle + "-popout"
  property bool popping: false
  property bool cardRevealed: true
  property var popFrom: null
  property string popAddr: ""
  // The grab handle's height: the window grows by it on the way to rest.
  readonly property real popOutGrow: handle.fullHeight
  // The popup's close fade (KeyboardPanel's 120 ms), before the move, so the
  // fading popup is not left behind.
  readonly property int popOutHoldMs: 140

  function startPopOut(from) {
    root.popFrom = from
    root.popping = true
    root.cardRevealed = false
    popPlace.tries = 0
    popPlace.start()
  }

  // The window is placed or given up on: show it and close the popup.
  function revealPopOut() {
    root.cardRevealed = true
    root.popping = false
    Quickshell.execDetached(Launchers.popupCloseCommand())
  }

  function stopPopOut() {
    popPlace.stop()
    popReveal.stop()
    popMove.stop()
    root.popping = false
    root.cardRevealed = true
  }

  // Waits for the window among Hyprland's, then puts it on the popup's card.
  Timer {
    id: popPlace
    property int tries: 0
    interval: 16
    repeat: true
    onTriggered: {
      var a = root.windowAddress(root.windowToplevel())
      popPlace.tries++
      if (a === "" && popPlace.tries < 60) return
      popPlace.stop()
      if (a === "") { root.revealPopOut(); return }
      root.popAddr = a
      // Resize first: Hyprland keeps a resized window centered, so a move
      // after it lands where it says.
      Hyprland.dispatch(Launchers.resizeWindowDispatch(a, root.popFrom.w, root.popFrom.h))
      Hyprland.dispatch(Launchers.moveWindowToDispatch(a, root.popFrom.x, root.popFrom.y))
      popReveal.tries = 0
      popReveal.start()
    }
  }

  // Waits for the view's data (up to about 0.6 s), then shows the window.
  Timer {
    id: popReveal
    property int tries: 0
    interval: 16
    repeat: true
    onTriggered: {
      popReveal.tries++
      if ((view.loading || !view.hasLoaded) && popReveal.tries < 40) return
      popReveal.stop()
      root.revealPopOut()
      popMove.start()
    }
  }

  // One diagonal move to rest, animated by Hyprland's own window animation,
  // then the window's rule (no_anim) again.
  Timer {
    id: popMove
    interval: root.popOutHoldMs
    onTriggered: {
      var a = root.popAddr
      var rest = Popout.restRect(root.popFrom, root.popOutGrow)
      Hyprland.dispatch(Launchers.windowAnimDispatch(a, true))
      handle.shown = true
      Hyprland.dispatch(Launchers.resizeWindowDispatch(a, rest.w, rest.h))
      Hyprland.dispatch(Launchers.moveWindowToDispatch(a, rest.x, rest.y))
      popAnimDone.start()
    }
  }

  Timer {
    id: popAnimDone
    interval: 800
    onTriggered: Hyprland.dispatch(Launchers.windowAnimDispatch(root.popAddr, false))
  }

  // This window among Hyprland's: its title and Quickshell's app id, as the
  // windowrule in ops/hyprland/backstory.lua matches it. null if not found.
  function windowToplevel() {
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      var t = all[i]
      if ((t.title === root.windowTitle || t.title === root.popOutTitle) && t.wayland && t.wayland.appId === "org.quickshell") return t
    }
    return null
  }

  // The window's Hyprland address as 0x<hex>, or "" when it is not one.
  function windowAddress(toplevel) {
    var a = toplevel ? String(toplevel.address || "") : ""
    if (a.indexOf("0x") !== 0) a = "0x" + a
    return Launchers.isWindowAddress(a) ? a : ""
  }

  function togglePin() {
    var a = root.windowAddress(root.windowToplevel())
    if (a === "") return
    root.pinned = !root.pinned
    Hyprland.dispatch(Launchers.pinWindowDispatch(a, root.pinned))
  }

  function close() {
    root.stopPopOut()
    handle.shown = false
    root.opened = false
  }

  // The shortcut's first step (ops/hyprland/backstory.lua): toggle the
  // window when it is open, and say so; "closed" sends the shortcut on to
  // the bar popup.
  function toggleIfOpen() {
    if (!root.opened) return "closed"
    root.toggle()
    return "ok"
  }

  // The window's IPC toggle: open the window; close it when it has focus; otherwise focus it, first moving it to the workspace you are
  // on when it is elsewhere and not pinned.
  function toggle() {
    if (!root.opened) { root.open("{}"); return }
    var t = root.windowToplevel()
    var a = root.windowAddress(t)
    if (a === "") { root.close(); return }
    var ws = Hyprland.focusedWorkspace
    var elsewhere = ws && ws.id >= 1 && t.workspace && t.workspace.id !== ws.id
    // Hyprland leaves `activated` set after you switch to an empty
    // workspace, so a window elsewhere does not count as focused.
    if (t.activated && !elsewhere) { root.close(); return }
    if (elsewhere && !root.pinned) Hyprland.dispatch(Launchers.moveWindowDispatch(a, ws.id))
    Hyprland.dispatch(Launchers.focusWindowDispatch(a))
  }

  IpcHandler {
    target: "backstory.this-week"
    function open(): string { root.open("{}"); return "ok" }
    function close(): string { root.close(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function toggleIfOpen(): string { return root.toggleIfOpen() }
    function refresh(): string { view.refresh(); return "ok" }
    function ping(): string { return "ok" }
  }

  // A regular xdg toplevel (NOT a wlr-layer-shell PanelWindow): Hyprland
  // manages toplevels, so Omarchy's own move/resize binds (SUPER+drag,
  // resize keys) work on it. ops/hyprland/backstory.lua floats it by
  // windowTitle at a default size/position.
  FloatingWindow {
    id: panel
    title: root.popping ? root.popOutTitle : root.windowTitle
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

    // The window's fill. Hyprland draws its border, corners and shadow, as
    // on any other window, so the card draws none of its own.
    Rectangle {
      id: card
      width: panel.width
      height: panel.height
      color: Util.alpha(Commons.Color.popups.background, 0.98)
      border.width: 0

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
      // Hidden while a pop-out puts the window in place.
      visible: root.cardRevealed
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
      // Only after a pop-out; it grows in as the window does.
      GrabHandle {
        id: handle
        width: card.width
      }

      ThisWeekView {
        id: view
        y: handle.height
        width: card.width / root.zoom
        height: (card.height - handle.height) / root.zoom
        scale: root.zoom
        transformOrigin: Item.TopLeft
        active: root.opened
        canPin: true
        pinned: root.pinned
        onPinRequested: root.togglePin()
        onCloseRequested: root.close()
      }
    }
  }
}
