import QtQuick
import Quickshell
import Quickshell.Wayland

// Minimal stand-in for qs.Ui.OverlayWindow, a fresh full-screen layer-shell
// surface per open in the real shell (so, like PanelWindow.qml in the
// Quickshell stubs, a QtObject outside the test scene). The real one reveals
// its content once the output's scale is known; here that is at once.
QtObject {
  id: window

  property bool shown: false
  // The real one's defaults: it takes the keyboard, and with no mask (as on
  // any PanelWindow) the whole surface takes clicks.
  property int shownKeyboardFocus: WlrKeyboardFocus.Exclusive
  property Region mask: null
  readonly property bool contentRevealed: window.shown
  readonly property bool visible: window.shown

  default property list<QtObject> data

  readonly property Item contentItem: _content

  property Item _content: Item {}

  Component.onCompleted: {
    for (var i = 0; i < window.data.length; i++) {
      var child = window.data[i]
      if (child && ("parent" in child)) child.parent = window._content
    }
  }
}
