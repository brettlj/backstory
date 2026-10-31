import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "js/model.js" as Model
import "js/derive.js" as Derive
import "js/launchers.js" as Launchers
import "js/glyphs.js" as Glyphs
import "js/format.js" as Format

// Backstory's this-week content: the HERE card, Needs you and Recent, with
// their data, selection and keys. It runs `backstory this-week --json --here
// auto` and never reads the store itself (PLAN.md Phase 4 "Human look",
// decision 9be5c1d5). A host surface (Panel.qml's window) binds `active` to
// whether it is showing and closes itself on closeRequested.
Item {
  id: root

  // True while the host surface is showing; turning on refreshes the data,
  // turning off returns to the main body.
  property bool active: false
  signal closeRequested()

  property var weekData: null
  property bool loading: false
  // A fresh panel (the shell unloads it on a bar or keybind close) has no
  // data until this-week first answers; until then it shows no empty state.
  property bool hasLoaded: false
  readonly property bool waitingForFirstData: root.loading && !root.hasLoaded
  property bool groupEditorOpen: false
  property bool memoryOpen: false
  property bool helpOpen: false
  property string memoryProjectKey: ""
  property string memoryDisplayName: ""
  property string memoryLocation: ""

  readonly property var attentionItems: root.weekData ? Model.topAttention(root.weekData) : []
  readonly property var whereLeftOffRows: root.weekData ? Model.topWhereLeftOff(root.weekData) : []
  readonly property var weekDays: root.weekData ? Model.topWeek(root.weekData) : []
  readonly property var hereData: root.weekData ? Model.topHere(root.weekData) : null
  readonly property var hereProject: root.weekData ? Derive.hereSummary(root.weekData) : null
  readonly property string hereName: root.hereData ? Model.shortName(Model.hereDisplayName(root.hereData)) : ""
  readonly property string summaryText: Format.summaryLine(Derive.weekTotals(root.weekDays))
  property real nowMs: Date.now()

  // The content's natural height, padding included; the host sizes to it.
  implicitHeight: contentColumn.implicitHeight + Style.spacing.panelPadding * 2
  readonly property Item scrollArea: scroller

  // Which group rows are expanded, keyed by group name. Collapsed by
  // default — a group is a human-made summary already; a click reveals it.
  property var expandedGroups: ({})

  // Which folder rows show their per-agent sub-rows, keyed by rowId (row
  // key plus cwd). Collapsed by default.
  property var expandedRows: ({})

  // Keyboard navigation runs over the rows as drawn: standalone rows, a
  // group's children only while it is expanded, and an expanded folder
  // row's per-agent sub-rows right after it. Each entry is
  // {summary, agent}; agent is "" for a folder row.
  readonly property var navRows: {
    var out = []
    function add(summary) {
      out.push({ summary: summary, agent: "" })
      if (root.expandedRows[root.rowId(summary)]) {
        var agents = Model.summaryAgents(summary)
        for (var j = 0; j < agents.length; j++) out.push({ summary: summary, agent: Model.agentId(agents[j]) })
      }
    }
    for (var i = 0; i < root.whereLeftOffRows.length; i++) {
      var row = root.whereLeftOffRows[i]
      var g = Model.rowGroup(row)
      if (g !== undefined && g !== "") {
        if (root.expandedGroups[g]) {
          var kids = Model.rowChildren(row)
          for (var k = 0; k < kids.length; k++) add(kids[k])
        }
      } else if (Model.rowProject(row)) {
        add(Model.rowProject(row))
      }
    }
    return out
  }
  property int selectedIndex: 0
  readonly property var selectedEntry: root.selectedIndex >= 0 && root.selectedIndex < root.navRows.length ? root.navRows[root.selectedIndex] : null
  readonly property var selectedSummary: root.selectedEntry ? root.selectedEntry.summary : null
  readonly property string selectedAgent: root.selectedEntry ? root.selectedEntry.agent : ""
  readonly property string selectedId: root.selectedSummary ? rowId(root.selectedSummary) : ""
  readonly property string footerHint: "j/k move \u00b7 \u2192 agents \u00b7 \u2190 fold \u00b7 Enter continue \u00b7 t terminal \u00b7 m memory \u00b7 ? help \u00b7 r refresh \u00b7 Esc close"

  function rowId(summary) {
    return Model.summaryProjectKey(summary) + "\n" + Model.summaryCwd(summary)
  }

  // After new data lands, select the `here` project's row, else the first.
  function resetSelection() {
    var idx = 0
    if (root.hereProject) {
      for (var i = 0; i < root.navRows.length; i++) {
        if (root.navRows[i].agent === "" && rowId(root.navRows[i].summary) === rowId(root.hereProject)) { idx = i; break }
      }
    }
    root.selectedIndex = idx
  }

  function toggleGroup(group) {
    var next = Object.assign({}, root.expandedGroups)
    next[group] = !next[group]
    root.expandedGroups = next
  }

  // Expands / collapses a folder row's agent sub-rows. Collapsing while a
  // sub-row is selected moves the selection back onto the folder row.
  function setRowExpanded(summary, expanded) {
    var id = root.rowId(summary)
    if (!!root.expandedRows[id] === expanded) return
    if (expanded && Model.summaryAgents(summary).length === 0) return
    var next = Object.assign({}, root.expandedRows)
    if (expanded) next[id] = true
    else delete next[id]
    if (!expanded && root.selectedAgent !== "" && root.selectedId === id) root.selectedIndex -= root.agentIndexOf(summary, root.selectedAgent) + 1
    root.expandedRows = next
  }

  function toggleRow(summary) {
    root.setRowExpanded(summary, !root.expandedRows[root.rowId(summary)])
  }

  function agentIndexOf(summary, agent) {
    var agents = Model.summaryAgents(summary)
    for (var i = 0; i < agents.length; i++) if (Model.agentId(agents[i]) === agent) return i
    return 0
  }

  function moveSelection(delta) {
    if (root.navRows.length === 0) return
    // Up on the first row scrolls the whole card to the top, so the HERE
    // card and Needs you above Recent are in view again.
    if (delta < 0 && root.selectedIndex === 0) {
      scroller.contentY = 0
      return
    }
    root.selectedIndex = Math.max(0, Math.min(root.navRows.length - 1, root.selectedIndex + delta))
    var row = root.selectedRowIn(recentSection)
    if (row) root.revealInScroller(row)
  }

  // The visible row (project, group or agent sub-row) whose `selected` is
  // set, so a key move can scroll it into view; null when there is none.
  function selectedRowIn(item) {
    for (var i = 0; i < item.children.length; i++) {
      var child = item.children[i]
      if (!child.visible) continue
      if (child.selected === true) return child
      var found = root.selectedRowIn(child)
      if (found) return found
    }
    return null
  }

  function summaryMemory(summary) {
    root.openMemory(Model.summaryProjectKey(summary), Model.summaryDisplayName(summary), Model.summaryCwd(summary) || "")
  }

  // The content's key handler; returns whether it consumed the key. Esc
  // asks the host to close; the row keys act only on the main body, never
  // while the group editor or Memory view is showing.
  function handleKey(key, modifiers) {
    if (key === Qt.Key_Escape) { root.closeRequested(); return true }
    if (root.groupEditorOpen || root.memoryOpen) return false
    if (root.helpOpen) {
      if (key === Qt.Key_Question) { root.helpOpen = false; return true }
      return false
    }
    var s = root.selectedSummary
    switch (key) {
    case Qt.Key_J: case Qt.Key_Down: root.moveSelection(1); return true
    case Qt.Key_K: case Qt.Key_Up: root.moveSelection(-1); return true
    case Qt.Key_Right: if (s) root.setRowExpanded(s, true); return true
    case Qt.Key_Left: if (s) root.setRowExpanded(s, false); return true
    case Qt.Key_Return: case Qt.Key_Enter: root.continueOn(s, root.selectedAgent); return true
    case Qt.Key_T: if (s) root.openTerminal(Model.summaryCwd(s)); return true
    case Qt.Key_M: if (s) root.summaryMemory(s); return true
    case Qt.Key_Question: root.helpOpen = true; return true
    case Qt.Key_R: root.refresh(); return true
    }
    return false
  }

  // agent: a sub-row's chosen agent id, "" / absent for a folder row.
  function continueOn(summary, agent) {
    continueAction.continueOn(summary, agent || "")
  }

  function refresh() {
    root.nowMs = Date.now()
    continueAction.refreshDefaultAgent()
    root.loading = true
    dataProcess.running = false
    dataProcess.running = true
  }

  // The ONE place the content reacts to its host showing or hiding,
  // whichever entry point flipped it.
  onActiveChanged: {
    if (root.active) {
      root.refresh()
    } else {
      root.groupEditorOpen = false
      root.memoryOpen = false
      root.helpOpen = false
    }
  }

  function openMemory(projectKey, displayName, cwd) {
    root.memoryProjectKey = projectKey
    root.memoryDisplayName = displayName
    root.memoryLocation = cwd
    root.memoryOpen = true
  }

  // Scrolls the Flickable so `target` lies inside its visible viewport: the
  // user never scrolls to find what a click just produced. An item taller
  // than the viewport is shown from its top. Every positioner between
  // target and the content is laid out first, innermost first: a row's
  // agent sub-rows sit in a nested Column that is not yet positioned right
  // after the row expands.
  function revealInScroller(target) {
    for (var p = target.parent; p && p !== scroller.contentItem; p = p.parent)
      if (typeof p.forceLayout === "function") p.forceLayout()
    var top = target.mapToItem(scroller.contentItem, 0, 0).y
    var bottom = top + target.height
    var y = scroller.contentY
    if (bottom > y + scroller.height) y = bottom - scroller.height
    if (top < y) y = top
    scroller.contentY = Math.max(0, Math.min(y, scroller.contentHeight - scroller.height))
  }

  // Click anywhere on a row opens a terminal at that project's cwd
  // (AGENT-CONTRACT.md: "same-agent resume is reopening a terminal at the
  // session's cwd"). --dir carries the target explicitly; workingDirectory
  // is set too so a terminal launcher that ignores --dir still lands right.
  function openTerminal(cwd) {
    Quickshell.execDetached({
      command: Launchers.terminalLaunchCommand(cwd),
      workingDirectory: cwd
    })
  }

  ContinueAction { id: continueAction }

  Process {
    id: dataProcess
    command: Launchers.thisWeekCommand()
    stdout: StdioCollector {
      onStreamFinished: {
        root.loading = false
        root.hasLoaded = true
        try {
          root.weekData = JSON.parse(text || "{}")
          root.resetSelection()
        } catch (e) {
          root.weekData = null
        }
      }
    }
  }

  Flickable {
    id: scroller
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    contentWidth: width
    contentHeight: contentColumn.implicitHeight
    clip: true

    // Round 4 desk defect B: GroupEditor used to be a sibling of
    // `card` anchored `anchors.right: card.left` — outside the
    // PanelWindow's own surface (implicitWidth/Height are card's own
    // width/height, so anything anchored outside card never had a
    // window to render into). Now it lives INSIDE this Flickable, as
    // one more child of `card`, so it is always within the window's
    // implicit bounds; the gear/back control swaps which one is
    // visible instead of opening a second surface.
    Column {
      id: contentColumn
      width: parent.width

      Column {
        id: body
        visible: !root.groupEditorOpen && !root.memoryOpen && !root.helpOpen
        width: parent.width
        spacing: Style.spacing.panelGap

        Row {
          width: parent.width

          Text {
            textFormat: Text.PlainText
            text: "Backstory"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            color: Commons.Color.popups.text
            width: parent.width - groupsButton.width - closeButton.width
          }

          PanelActionButton {
            id: groupsButton
            iconText: Glyphs.gear()
            tooltipText: "Groups"
            foreground: Commons.Color.popups.text
            hoverColor: Commons.Color.accent
            onClicked: root.groupEditorOpen = !root.groupEditorOpen
          }

          PanelActionButton {
            id: closeButton
            iconText: Glyphs.close()
            tooltipText: "Close"
            foreground: Commons.Color.popups.text
            hoverColor: Commons.Color.urgent
            onClicked: root.closeRequested()
          }
        }

        HereCard {
          visible: root.hereProject !== null
          width: parent.width
          summary: root.hereProject
          hereName: root.hereName
          defaultAgent: continueAction.defaultAgent
          continueLabel: continueAction.labelFor(root.hereProject)
          expanded: root.hereProject !== null && !!root.expandedRows[root.rowId(root.hereProject)]
          onToggleExpanded: if (root.hereProject) root.toggleRow(root.hereProject)
          week: root.weekDays
          nowMs: root.nowMs
          onContinueRequested: root.continueOn(root.hereProject)
          onTerminalRequested: root.openTerminal(Model.summaryCwd(root.hereProject))
          onMemoryRequested: root.summaryMemory(root.hereProject)
        }

        // Needs you: rendered only when non-empty (PANEL-CONTRACT.md
        // "Attention", decision 9be5c1d5 — an empty array is itself
        // the "nothing to flag" signal, not an absent section).
        Column {
          visible: root.attentionItems.length > 0
          width: parent.width
          spacing: Style.spacing.labelGap

          PanelSectionHeader { text: "NEEDS YOU"; foreground: Commons.Color.popups.text }
          AttentionSection { items: root.attentionItems; width: parent.width; onDismissed: root.refresh() }
        }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          PanelSectionHeader { text: "RECENT"; foreground: Commons.Color.popups.text }
          WhereLeftOffSection {
            id: recentSection
            rows: root.whereLeftOffRows
            waiting: root.waitingForFirstData
            week: root.weekDays
            expandedGroups: root.expandedGroups
            selectedId: root.selectedId
            selectedAgent: root.selectedAgent
            expandedRows: root.expandedRows
            nowMs: root.nowMs
            onToggleRow: (summary) => root.toggleRow(summary)
            onLaunchRequested: (summary, agent) => root.continueOn(summary, agent)
            width: parent.width
            onToggleGroup: (group) => root.toggleGroup(group)
            onOpenTerminal: (cwd) => root.openTerminal(cwd)
            onContinueRequested: (summary) => root.continueOn(summary)
            onOpenMemory: (projectKey, displayName, cwd) => root.openMemory(projectKey, displayName, cwd)
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.summaryText
          visible: !root.waitingForFirstData
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Qt.darker(Commons.Color.popups.text, 1.3)
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.footerHint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Qt.darker(Commons.Color.popups.text, 1.3)
          wrapMode: Text.WordWrap
        }
      }

      GroupEditor {
        visible: root.groupEditorOpen
        width: parent.width
        onCloseRequested: root.groupEditorOpen = false
        onChanged: root.refresh()
      }

      HelpView {
        visible: root.helpOpen
        width: parent.width
        onCloseRequested: root.helpOpen = false
      }

      MemoryView {
        visible: root.memoryOpen
        width: parent.width
        projectKey: root.memoryProjectKey
        displayName: root.memoryDisplayName
        location: root.memoryLocation
        onReveal: (target) => root.revealInScroller(target)
        onCloseRequested: root.memoryOpen = false
        onChanged: root.refresh()
      }
    }
  }
}
