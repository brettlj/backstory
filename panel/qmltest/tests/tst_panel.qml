import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "testutil.js" as TestUtil
import "../../js/launchers.js" as Launchers
import "../../js/glyphs.js" as Glyphs

// The Panel.qml integration suite (task 4fe02e30 Part 1 harness): feeds
// the plugin's real Process stub the committed this-week golden, `{}`, and
// an all-empty-arrays payload, asserting the golden's display names render
// (DONE WHEN clause 2); walks the visible item tree with the panel open
// and with the group editor open, asserting every visible item's mapped
// rect lies inside PanelWindow's implicit bounds (DONE WHEN clause 3); and
// asserts the recorded argv for a Where-you-left-off row click (DONE WHEN
// clause 4 — clause 6's own cwd-interpolation/shape assertions live in
// panel_contract_test.go's Go+Node harness; this file exercises the same
// terminalLaunchCommand through the real QML click path).
TestCase {
  id: testCase
  name: "Panel"
  when: windowShown
  visible: true
  width: 900
  height: 900

  readonly property string goldenUrl: Qt.resolvedUrl("../../../cmd/backstory/testdata/thisweek/all.json.golden")

  function readFixture(url) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", url, false)
    xhr.send()
    if (xhr.status !== 200) {
      fail("could not read fixture " + url + ": status " + xhr.status)
    }
    return xhr.responseText
  }

  readonly property string emptyArraysPayload: JSON.stringify({
    attention: [], where_left_off: [], week: []
  })

  Component {
    id: panelComponent
    Loader { source: Qt.resolvedUrl("../../Panel.qml") }
  }

  property var loader: null
  property var panel: null

  TestActions { id: act; testCase: testCase }

  function init() {
    ProcessController.reset()
    Quickshell.reset()
    Hyprland.reset()
    loader = panelComponent.createObject(testCase)
    tryCompare(loader, "status", Loader.Ready, 2000)
    verify(loader.item !== null, "Panel.qml failed to load: status=" + loader.status)
    panel = loader.item
    // See Panel.qml's own doc comment on testContentItem: PanelWindow's
    // contentItem is otherwise a disconnected subtree (our stub PanelWindow
    // is a QtObject, not a real QQuickWindow, so nothing parents it into
    // testCase's own shown window) — reparenting it here is what makes
    // a click deliverable to anything inside the panel at all.
    panel.testContentItem.parent = loader
  }

  function cleanup() {
    if (loader) loader.destroy()
    loader = null
    panel = null
  }

  // openWith registers `command`'s canned response, opens the panel (which
  // triggers refresh() -> dataProcess.running = true, synchronously
  // resolved by the Process stub) and returns once data has landed.
  function openWith(payloadText) {
    ProcessController.respond(Launchers.thisWeekCommand(), { stdout: payloadText, stderr: "", exitCode: 0 })
    panel.open("{}")
    tryCompare(panel.view, "loading", false, 2000)
    // Column/Row (QtQuick's positioners) recompute implicitWidth/Height
    // via a deferred polish pass, not synchronously on every child change
    // (a read right after a data change saw a stale pre-data height), so
    // wait for the rendered texts and height to stop changing.
    act.quiescent(function () { return [TestUtil.collectVisibleTexts(panel.testContentItem), panel.testImplicitHeight] }, "panel never finished rendering")
  }

  function test_open_with_a_snapshot_restores_it() {
    openWith(readFixture(goldenUrl))
    panel.close()
    panel.open(JSON.stringify({ view: "help" }))
    compare(panel.opened, true)
    compare(panel.view.helpOpen, true)
  }

  function test_plain_open_keeps_the_view_showing() {
    openWith(readFixture(goldenUrl))
    panel.view.helpOpen = true
    panel.open("{}")
    compare(panel.view.helpOpen, true)
  }

  function test_open_with_an_unreadable_payload_opens_the_main_view() {
    panel.open("{not json")
    compare(panel.opened, true)
    compare(panel.view.helpOpen || panel.view.memoryOpen || panel.view.groupEditorOpen, false)
    panel.close()
    panel.open(JSON.stringify({ view: "help", pad: new Array(70000).join("x") }))
    compare(panel.view.helpOpen, false, "an oversized payload was read")
  }

  function popOutButton() {
    return TestUtil.findFirst(panel.testContentItem, function (n) { return n.tooltipText === "Pop out" })
  }

  function test_window_offers_no_pop_out() {
    openWith(readFixture(goldenUrl))
    compare(popOutButton(), null)
  }

  function test_window_ignores_p() {
    openWith(readFixture(goldenUrl))
    var asked = 0
    panel.view.popOutRequested.connect(function () { asked++ })
    verify(!panel.view.handleKey(Qt.Key_P, Qt.NoModifier))
    compare(asked, 0)
    compare(panel.view.footerHint.indexOf("p pop out"), -1)
  }

  function test_pop_out_button_asks_the_host() {
    panel.view.canPopOut = true
    openWith(readFixture(goldenUrl))
    var asked = 0
    panel.view.popOutRequested.connect(function () { asked++ })
    act.clickWhenReady(popOutButton, { desc: "pop-out button", until: function () { return asked === 1 } })
  }

  function test_each_sub_view_header_offers_the_pop_out() {
    panel.view.canPopOut = true
    openWith(readFixture(goldenUrl))
    var asked = 0
    panel.view.popOutRequested.connect(function () { asked++ })
    var views = ["helpOpen", "groupEditorOpen", "memoryOpen"]
    for (var i = 0; i < views.length; i++) {
      panel.view.showMain()
      panel.view[views[i]] = true
      act.clickWhenReady(popOutButton, { desc: "pop-out button in " + views[i], until: function () { return asked === i + 1 } })
    }
  }

  // ---- Pin: the window follows you to every workspace ----
  // The window as Hyprland lists it, next to a terminal with the same title.
  function listWindow(activated, workspace) {
    Hyprland.toplevels = { values: [
      { address: "aa11", title: "backstory", activated: false, workspace: { id: 1 }, wayland: { appId: "com.mitchellh.ghostty" } },
      { address: "bb22", title: "backstory", activated: activated, workspace: { id: workspace }, wayland: { appId: "org.quickshell" } }
    ] }
  }

  function pinButton() {
    return TestUtil.findFirst(panel.testContentItem, function (n) { return n.objectName === "pinButton" })
  }

  function test_pin_toggles_hyprlands_pin_on_this_window_and_shows_it() {
    listWindow(true, 1)
    openWith(readFixture(goldenUrl))
    compare(pinButton().iconText, Glyphs.pinOutline(), "the window opened pinned")
    act.clickWhenReady(pinButton, { desc: "pin button", until: function () { return panel.pinned } })
    compare(Hyprland.dispatched, ['hl.dsp.window.pin({ action = "on", window = "address:0xbb22" })'])
    compare(pinButton().iconText, Glyphs.pin())
    act.clickWhenReady(pinButton, { desc: "pin button again", until: function () { return !panel.pinned } })
    compare(Hyprland.dispatched[1], 'hl.dsp.window.pin({ action = "off", window = "address:0xbb22" })')
  }

  function test_the_window_opens_unpinned() {
    listWindow(true, 1)
    openWith(readFixture(goldenUrl))
    panel.togglePin()
    compare(panel.pinned, true)
    panel.close()
    panel.open("{}")
    compare(panel.pinned, false)
  }

  function test_every_view_header_offers_the_pin() {
    openWith(readFixture(goldenUrl))
    var views = ["helpOpen", "groupEditorOpen", "memoryOpen"]
    for (var i = 0; i < views.length; i++) {
      panel.view.showMain()
      panel.view[views[i]] = true
      act.settled(function () { return TestUtil.slideDone(panel.testContentItem, ["helpPage", "groupsPage", "memoryPage"][i]) && pinButton() !== null }, "no pin button in " + views[i])
    }
  }

  function test_renders_golden_display_names() {
    openWith(readFixture(goldenUrl))
    var golden = JSON.parse(readFixture(goldenUrl))

    var names = {}
    var i
    for (i = 0; i < golden.where_left_off.length; i++) {
      var row = golden.where_left_off[i]
      if (row.project) names[row.project.display_name] = true
      if (row.children) {
        for (var j = 0; j < row.children.length; j++) names[row.children[j].display_name] = true
      }
    }

    // Group children are drawn only while their group is expanded; a
    // workspace-keyed row's text is "<dir> · workspace notes".
    panel.view.toggleGroup("widget-suite")
    var rendered = []
    var missing = []
    function allRendered() {
      rendered = TestUtil.collectVisibleTexts(panel.testContentItem)
      var renderedSet = {}
      for (var k = 0; k < rendered.length; k++) {
        renderedSet[rendered[k]] = true
        renderedSet[rendered[k].replace(/ \u00b7 workspace notes$/, "")] = true
      }
      missing = []
      // Rows drop the leading "projects/" (decision 63ce9687 P4).
      for (var name in names) {
        if (renderedSet[name.replace(/^projects\/(?=.)/, "")] !== true) missing.push(name)
      }
      return missing.length === 0
    }
    act.settled(allRendered, "expected display names to be rendered; missing " + JSON.stringify(missing) + "; got " + JSON.stringify(rendered))
  }

  // Needs You's Dismiss on a stale-handoff row runs `backstory affirm <id>`
  // for THAT handoff (and only that row has the button).
  function test_needs_you_dismiss_runs_affirm_for_that_handoff() {
    openWith(JSON.stringify({
      attention: [
        { kind: "possibly-stale-handoff", project_key: "wobble-party", reason: "wobble-party: handoff possibly stale \u2014 cargo test failed (exit 101) after it", handoff_id: "h-wobble", evidence_ids: ["7"] },
        { kind: "expired-claim", project_key: "wobble-party", reason: "claim c1 expired with no outcome recorded", evidence_ids: ["c1"] }
      ],
      where_left_off: [], week: []
    }))
    function dismissButtons() {
      return TestUtil.findAll(panel.testContentItem, function (n) { return n.objectName === "attentionDismiss" && n.visible })
    }
    act.settled(function () { return dismissButtons().length === 1 }, "expected exactly one visible Dismiss button")
    ProcessController.reset()
    ProcessController.respond(Launchers.thisWeekCommand(), { stdout: emptyArraysPayload, stderr: "", exitCode: 0 })
    act.clickWhenReady(function () { var b = dismissButtons(); return b.length === 1 ? b[0] : null }, { desc: "attention Dismiss" })
    var affirmJson = JSON.stringify(Launchers.affirmCommand("h-wobble"))
    act.launchedNext(function (r) { return JSON.stringify(r.command) === affirmJson }, "affirm")
    compare(JSON.stringify(Launchers.affirmCommand("h-wobble")), JSON.stringify(["backstory", "affirm", "h-wobble"]))
    tryCompare(panel.view, "loading", false, 2000)
    compare(panel.view.attentionItems.length, 0)
  }

  function test_handles_empty_object_payload() {
    openWith("{}")
    compare(panel.view.attentionItems.length, 0)
    compare(panel.view.whereLeftOffRows.length, 0)
    compare(panel.view.weekDays.length, 0)
  }

  // A fresh panel (the shell unloads it on a bar or keybind close) has no
  // data until this-week answers. It must not claim "Nothing this week."
  // meanwhile: filmed, the empty card showed for 40-70 ms before the data.
  // The panel here is fresh, as the shell creates it; nothing is assigned to
  // `data`, which on Qt 6.12 reads as Item's own `data` list, not null, so
  // "no data yet" must not be tested by `data === null`.
  function test_no_empty_state_while_first_load_runs() {
    panel.view.loading = true
    var texts = TestUtil.collectVisibleTexts(panel.testContentItem)
    verify(texts.indexOf("Nothing this week.") < 0, "empty state shown while the first load runs: " + texts)
    verify(texts.indexOf(panel.view.summaryText) < 0, "summary '" + panel.view.summaryText + "' shown while the first load runs")

    panel.view.loading = false
    texts = TestUtil.collectVisibleTexts(panel.testContentItem)
    verify(texts.indexOf("Nothing this week.") >= 0, "a first load that ends with no answer shows the empty state: " + texts)

    openWith("{}")
    texts = TestUtil.collectVisibleTexts(panel.testContentItem)
    verify(texts.indexOf("Nothing this week.") >= 0, "an empty answer shows the empty state: " + texts)

    panel.view.loading = true
    texts = TestUtil.collectVisibleTexts(panel.testContentItem)
    verify(texts.indexOf(panel.view.summaryText) >= 0, "a later refresh hid the summary: " + texts)
  }

  function test_handles_all_empty_arrays_payload() {
    openWith(emptyArraysPayload)
    compare(panel.view.attentionItems.length, 0)
    compare(panel.view.whereLeftOffRows.length, 0)
    compare(panel.view.weekDays.length, 0)
  }

  function assertLayoutWithinBounds(label) {
    // The polish pass lands a few ticks after a data change: wait for the
    // bounds to hold rather than reading them once.
    var outOfBounds = []
    act.settled(function () {
      outOfBounds = TestUtil.collectOutOfBounds(
        panel.testContentItem, panel.testContentItem,
        panel.testImplicitWidth, panel.testImplicitHeight)
      return outOfBounds.length === 0
    }, label + ": item(s) out of PanelWindow bounds "
      + "(" + panel.testImplicitWidth + "x" + panel.testImplicitHeight + "): "
      + JSON.stringify(outOfBounds).slice(0, 2000))
  }

  function assertWithinScroller(label) {
    function clipped() { return TestUtil.collectClipped(panel.testContentItem) }
    act.quiescent(clipped, label + ": layout never settled")
    compare(JSON.stringify(clipped()), "[]", label + ": item(s) clipped by the scroller")
  }

  function test_layout_within_bounds_panel_open() {
    openWith(readFixture(goldenUrl))
    compare(panel.view.groupEditorOpen, false)
    assertLayoutWithinBounds("panel open, group editor closed")
  }

  function test_layout_within_scroller_panel_open() {
    openWith(readFixture(goldenUrl))
    assertWithinScroller("panel open")
  }

  function test_layout_within_bounds_group_editor_open() {
    openWith(readFixture(goldenUrl))
    ProcessController.respond(Launchers.groupListCommand(), { stdout: JSON.stringify({ groups: [], ungrouped: [] }), stderr: "", exitCode: 0 })
    panel.view.groupEditorOpen = true
    act.settled(function () { return panel.view.groupEditorOpen }, "group editor never opened")
    assertLayoutWithinBounds("group editor open")
  }

  function test_row_click_opens_terminal_at_cwd() {
    openWith(readFixture(goldenUrl))
    var golden = JSON.parse(readFixture(goldenUrl))
    var target = null
    for (var i = 0; i < golden.where_left_off.length; i++) {
      if (golden.where_left_off[i].project) { target = golden.where_left_off[i].project; break }
    }
    verify(target !== null, "fixture assumption broke: golden has no standalone project row")

    function findRow() {
      return TestUtil.findFirst(panel.testContentItem, function (node) {
        return node.summary && node.summary.cwd === target.cwd
      })
    }
    act.settled(function () { return findRow() !== null }, "could not find a rendered row for cwd " + target.cwd)

    var want = Launchers.terminalLaunchCommand(target.cwd)
    act.clickWhenReady(findRow, { desc: "row for " + target.cwd })
    var last = act.detachedNext(function (c) { return JSON.stringify(c.command) === JSON.stringify(want) }, "row click terminal")
    compare(JSON.stringify(last.command), JSON.stringify(want))
    compare(last.workingDirectory, target.cwd)
  }
}
