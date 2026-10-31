import QtQuick

// Minimal stand-in for qs.Ui.KeyboardPanel, a layer-shell window in the real
// shell (so, like PanelWindow.qml here, a QtObject outside the test scene).
// Its content is built on first open and kept, as the real one's is.
QtObject {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property bool open: false
  property Item focusTarget: null
  property int contentWidth: 0
  property int contentHeight: 0
  property Component content: null
  property bool contentRequested: false

  readonly property Item loadedContent: _loader.item
  readonly property real loadedContentHeight: loadedContent ? loadedContent.implicitHeight : 0

  onOpenChanged: if (open) contentRequested = true

  function fittedContentWidth(width, cap) {
    return cap !== undefined && cap > 0 ? Math.min(width, cap) : width
  }

  function fittedContentHeight(implicitHeight, cap) {
    return cap !== undefined && cap > 0 ? Math.min(implicitHeight, cap) : implicitHeight
  }

  property Loader _loader: Loader {
    active: root.content !== null && root.contentRequested
    sourceComponent: root.content
    width: root.contentWidth
    height: root.contentHeight
  }
}
