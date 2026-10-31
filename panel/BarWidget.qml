import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "js/model.js" as Model
import "js/derive.js" as Derive
import "js/launchers.js" as Launchers
import "js/format.js" as Format

// The "bar-widget" entry point (manifest.json "kinds": ["panel",
// "bar-widget"], round 2 defect B: "Nothing on screen opens the panel; ...
// add a bar widget ... whose click toggles the panel"). A single Nerd Font
// glyph placed in the bar.
//
// Round 4 desk defect A: a click here used to flip a shared PanelState
// singleton directly, but the host only ever shows a plugin panel through
// its OWN toggle machinery — the singleton flip never reached it, so
// clicking the bar glyph did nothing. MEASURED FIX (hand-patched on the
// desk, confirmed working): route the click through the same call the
// host's own bar-widget plugins use — ridgetopai.omarcade's own
// Marquee.qml:253 — `Quickshell.execDetached(["omarchy-shell", "shell",
// "toggle", "backstory.this-week", "{}"])`, named once in js/launchers.js
// (task 4fe02e30 DONE WHEN clause 5's "every command the QML runs comes
// from js/launchers.js"). This file spawns no process of its own beyond
// that one execDetached call — like every file in this plugin except
// js/launchers.js itself.
//
// It shows the `here` project's short name (the calendar glyph only when
// there is no `here`) and a dot when Attention is non-empty. Left click
// toggles the panel, right click is Continue on `here`, middle click
// refreshes; it refreshes on every click (the panel opening or closing),
// and every refreshIntervalMs.
Item {
  id: root

  property int refreshIntervalMs: 60000
  property var payload: null
  // Injected by the host. Its slots line up at their top, so the widget
  // takes the bar's full thickness to sit level with the icons beside it
  // ($OMARCHY_PATH/shell/plugins/bar/README.md, "Custom user modules").
  property var bar: null

  readonly property var hereData: root.payload ? Model.topHere(root.payload) : null
  readonly property var hereProject: root.payload ? Derive.hereSummary(root.payload) : null
  readonly property string hereName: root.hereData ? Model.shortName(Model.hereDisplayName(root.hereData)) : ""
  readonly property bool needsAttention: root.payload ? Model.topAttention(root.payload).length > 0 : false
  readonly property bool vertical: root.bar ? root.bar.vertical === true : false
  readonly property string labelText: root.vertical ? "" : root.hereName

  // Backstory's glyph: md-script_text, an ancient scroll with writing.
  readonly property string scrollGlyph: String.fromCodePoint(0xF0BC2)

  implicitWidth: button.implicitWidth
  implicitHeight: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal

  function refresh() {
    continueAction.refreshDefaultAgent()
    dataProcess.running = false
    dataProcess.running = true
  }

  Component.onCompleted: root.refresh()

  Timer {
    interval: root.refreshIntervalMs
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  ContinueAction { id: continueAction }

  Process {
    id: dataProcess
    command: Launchers.thisWeekCommand()
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.payload = JSON.parse(text || "{}")
        } catch (e) {
          root.payload = null
        }
      }
    }
  }

  TextMetrics {
    id: labelMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.bar.iconFont
    text: root.labelText
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.scrollGlyph
    labelText: root.labelText
    slotSize: Style.bar.iconSlot + (root.labelText !== "" ? labelMetrics.advanceWidth + Style.space(4) : 0)
    tooltipText: ""
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        continueAction.continueOn(root.hereProject)
      } else if (mouseButton === Qt.MiddleButton) {
        root.refresh()
      } else {
        Quickshell.execDetached(Launchers.barToggleCommand())
        root.refresh()
      }
    }
  }

  // The problem dot at the icon's upper right; the icon is the right end of
  // the button's centered label-and-icon group.
  Item {
    anchors.verticalCenter: button.verticalCenter
    x: (button.width + width) / 2 - width
    width: Style.bar.iconCanvas + (root.labelText !== "" ? labelMetrics.advanceWidth + Style.space(4) : 0)
    height: Style.bar.iconCanvas

    BorderSurface {
      objectName: "attentionDot"
      visible: root.needsAttention
      width: Style.space(6)
      height: width
      radius: width / 2
      color: Commons.Color.bar.active
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: -Style.space(1)
      borderSpec: Border.flat(Commons.Color.popups.background, Style.spacing.hairline)
    }
  }
}
