import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "testutil.js" as TestUtil
import "../../js/launchers.js" as Launchers

// BarWidget.qml: shows the `here` project's short name (glyph only when
// there is none) and an attention dot iff Attention is non-empty. Left
// click toggles its popup (a KeyboardPanel holding ThisWeekView), right
// click is Continue on `here`, middle click a refresh (task fc1f340d).
TestCase {
  id: testCase
  name: "BarWidget"
  when: windowShown
  visible: true
  width: 300
  height: 100

  readonly property string fixtureUrl: Qt.resolvedUrl("../../testdata/this-week-here.json")

  Component {
    id: barWidgetComponent
    Loader { source: Qt.resolvedUrl("../../BarWidget.qml") }
  }

  property var loader: null

  TestActions { id: act; testCase: testCase }

  function fixture(mutate) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", fixtureUrl, false)
    xhr.send()
    var data = JSON.parse(xhr.responseText.replace(/@NOW/g, new Date().toISOString()).replace(/@D\d/g, "2026-01-01"))
    if (mutate) mutate(data)
    return data
  }

  // The widget fetches on creation, so the canned responses go in first.
  function start(data, defaultAgent) {
    ProcessController.reset()
    Quickshell.reset()
    ProcessController.respond(Launchers.thisWeekCommand(), { stdout: JSON.stringify(data), stderr: "", exitCode: 0 })
    ProcessController.respond(Launchers.defaultAgentCommand(), { stdout: defaultAgent === undefined ? "claude\n" : defaultAgent, stderr: "", exitCode: 0 })
    loader = barWidgetComponent.createObject(testCase)
    tryCompare(loader, "status", Loader.Ready, 2000)
    verify(loader.item !== null, "BarWidget.qml failed to load: status=" + loader.status)
    act.launchedNext(function (r) { return ProcessController.keyFor(r.command) === ProcessController.keyFor(Launchers.thisWeekCommand()) }, "initial this-week fetch")
    act.drain()
    return loader.item
  }

  function cleanup() {
    if (loader) loader.destroy()
    loader = null
  }

  function weekRuns() {
    return ProcessController.runs.filter(function (r) { return r.command[0] === "backstory" })
  }

  function barLabel(widget) {
    return TestUtil.findFirst(widget, function (n) { return n.objectName === "barLabel" })
  }

  function labelShows(widget, text) {
    act.settled(function () { var l = barLabel(widget); return l !== null && l.text === text }, "barLabel never showed " + JSON.stringify(text))
  }

  function dot(widget) {
    return TestUtil.findFirst(widget, function (n) { return n.objectName === "attentionDot" })
  }

  function test_shows_here_project_name() {
    var widget = start(fixture())
    labelShows(widget, "foo")
  }

  // With BACKSTORY_PROJECT_ROOTS set, `backstory this-week --json --here auto`
  // answers `recent` with the most recent IN-SCOPE project (cmd/backstory's
  // TestHereNamesMostRecentInScopeProject) even when a newer out-of-scope
  // session exists; the bar widget shows that name.
  function test_shows_most_recent_in_scope_project_name() {
    var widget = start(fixture(function (d) {
      d.here = { project_key: "scoped-key", display_name: "projects/scoped", cwd: "/home/brian/projects/scoped", source: "recent" }
    }))
    labelShows(widget, "scoped")
  }

  function test_attention_dot_iff_attention_non_empty() {
    var widget = start(fixture())
    act.settled(function () { return dot(widget) !== null }, "dot should be visible with attention")
    cleanup()
    widget = start(fixture(function (d) { d.attention = [] }))
    // Negative: the dot must stay absent once the data (the label) has rendered.
    act.settled(function () { return barLabel(widget) !== null && barLabel(widget).text !== "" }, "label never rendered")
    compare(dot(widget), null)
  }

  // The bar lines its slots up at their top, so a widget shorter than the
  // bar sits above the icons beside it: it takes the bar's own thickness.
  function test_fills_the_bar_thickness() {
    var widget = start(fixture())
    widget.bar = fakeBar(31)
    compare(widget.implicitHeight, 31)
  }

  function test_glyph_only_when_no_here() {
    var widget = start(fixture(function (d) { delete d.here }))
    var glyph = TestUtil.findFirst(widget, function (n) { return n.objectName === "barGlyph" })
    verify(glyph !== null && glyph.text !== "", "glyph never rendered")
    verify(barLabel(widget) === null, "label shown with no here project")
  }

  // The bar a Panel root is given: barSize, the label font, and the
  // panel-switching hook Tab calls (it records each direction).
  function fakeBar(size) {
    return Qt.createQmlObject('import QtQuick; QtObject { property int barSize: ' + size
      + '; property string fontFamily: "sans-serif"; property var switched: []; '
      + 'function switchPanelFrom(panel, direction) { switched = switched.concat([direction]); return true } }', testCase)
  }

  function openPopup(widget) {
    act.clickWhenReady(widget, { button: Qt.LeftButton, desc: "bar widget", until: function () { return widget.opened } })
    act.settled(function () { return widget.testPopup.loadedContent !== null }, "popup content never built")
    return widget.testPopup.loadedContent
  }

  function test_left_click_opens_the_popup_with_this_week() {
    var widget = start(fixture())
    var content = openPopup(widget)
    verify(typeof content.handleKey === "function", "popup content has no key handler")
    compare(Quickshell.execDetachedCalls.length, 0, "a left click ran a command: " + JSON.stringify(Quickshell.execDetachedCalls))
    act.clickWhenReady(widget, { button: Qt.LeftButton, desc: "bar widget again", until: function () { return !widget.opened } })
  }

  function test_esc_in_the_popup_closes_it() {
    var widget = start(fixture())
    var content = openPopup(widget)
    verify(content.handleKey(Qt.Key_Escape, Qt.NoModifier))
    compare(widget.opened, false)
  }

  function test_pop_out_closes_the_popup_and_summons_the_window() {
    var widget = start(fixture())
    var content = openPopup(widget)
    // The popup's content is outside the test scene, so the button can't be
    // clicked here; tst_panel's test_pop_out_button_asks_the_host clicks it.
    var view = TestUtil.findFirst(content, function (n) { return n.canPopOut !== undefined })
    verify(view !== null && view.canPopOut === true, "the popup's view offers no pop-out")
    verify(TestUtil.findFirst(content, function (n) { return n.tooltipText === "Pop out" }) !== null, "no pop-out button in the popup")
    view.helpOpen = true
    view.popOutRequested()
    compare(widget.opened, false)
    var run = act.detachedNext(function (c) { return c.command[2] === "summon" }, "window summon")
    compare(JSON.stringify(run.command.slice(0, 4)), JSON.stringify(["omarchy-shell", "shell", "summon", "backstory.this-week"]))
    // The window opens where the popup was: the snapshot taken before it closed.
    compare(JSON.parse(run.command[4]).view, "help")
  }

  function test_tab_moves_to_the_next_bar_panel() {
    var widget = start(fixture())
    widget.bar = fakeBar(26)
    var content = openPopup(widget)
    verify(content.handleKey(Qt.Key_Tab, Qt.NoModifier))
    verify(content.handleKey(Qt.Key_Backtab, Qt.ShiftModifier))
    compare(widget.bar.switched, [1, -1])
  }

  function test_label_drops_projects_prefix() {
    var widget = start(fixture())
    labelShows(widget, "foo")
  }

  function test_right_click_is_continue_on_here() {
    var widget = start(fixture())
    act.clickWhenReady(widget, { button: Qt.RightButton, desc: "bar widget (right)" })
    var run = act.launchedNext(function (r) { return r.command[0] === "xdg-terminal-exec" }, "right click Continue launch")
    compare(Quickshell.execDetachedCalls.length, 0)
    // foo's agents[0] is claude: launched from the launch table, not omarchy.
    compare(JSON.stringify(run.command.slice(0, 3)), JSON.stringify(["xdg-terminal-exec", "--", "sh"]))
    compare(JSON.stringify(run.command.slice(7, 10)), JSON.stringify(Launchers.LAUNCH_TABLE.claude.argv))
    var prompt = run.command[run.command.length - 1]
    verify(prompt.indexOf("handoff-0042") >= 0 && prompt.indexOf("Wire the bar") >= 0)
    compare(run.workingDirectory, "/home/brian/projects/foo")
  }

  function test_right_click_focuses_the_open_window() {
    var widget = start(fixture(function (d) { d.where_left_off[0].project.window = "0x55aa" }))
    act.clickWhenReady(widget, { button: Qt.RightButton, desc: "bar widget (right)" })
    var run = act.launchedNext(function (r) { return JSON.stringify(r.command) === JSON.stringify(Launchers.focusWindowCommand("0x55aa")) }, "right click focus")
    compare(JSON.stringify(run.command), JSON.stringify(Launchers.focusWindowCommand("0x55aa")))
  }

  function test_middle_click_refreshes() {
    var widget = start(fixture())
    var before = weekRuns().length
    act.clickWhenReady(widget, { button: Qt.MiddleButton, desc: "bar widget (middle)" })
    act.settled(function () { return weekRuns().length >= before + 1 }, "middle click never refreshed")
    act.drain()
    compare(weekRuns().length, before + 1)
    compare(Quickshell.execDetachedCalls.length, 0)
  }

  function test_refreshes_every_interval() {
    var widget = start(fixture())
    widget.refreshIntervalMs = 30
    var before = weekRuns().length
    tryVerify(function () { return weekRuns().length > before }, 2000)
  }
}
