pragma Singleton
import QtQuick

// Test-only registry backing the Process.qml stub below: a QML test
// registers a canned {stdout, stderr, exitCode} response for a given argv
// before flipping a Process's `running` to true, and can read back every
// argv a Process actually ran (task 4fe02e30 DONE WHEN clause 4's recorded
// argv, and "the test feeds stdout + exit code" for Process specifically).
// A response with `held: true` waits, as a slow subprocess would, until the
// test calls release() for its argv.
QtObject {
  id: controller

  property var responses: ({})
  property var runs: []
  // Deliveries waiting on release(): { key, deliver }.
  property var heldRuns: []

  function keyFor(command) {
    return JSON.stringify(command)
  }

  function respond(command, response) {
    var next = Object.assign({}, controller.responses)
    next[controller.keyFor(command)] = response
    controller.responses = next
  }

  function lookup(command) {
    var key = controller.keyFor(command)
    if (Object.prototype.hasOwnProperty.call(controller.responses, key)) {
      return controller.responses[key]
    }
    return { stdout: "", stderr: "", exitCode: 0 }
  }

  function recordRun(command, workingDirectory) {
    var next = controller.runs.slice()
    next.push({ command: command, workingDirectory: workingDirectory })
    controller.runs = next
  }

  function lastRun() {
    return controller.runs.length > 0 ? controller.runs[controller.runs.length - 1] : null
  }

  function hold(command, deliver) {
    controller.heldRuns = controller.heldRuns.concat([{ key: controller.keyFor(command), deliver: deliver }])
  }

  // Delivers every held run of command; returns how many there were.
  function release(command) {
    var key = controller.keyFor(command)
    var due = controller.heldRuns.filter(function (h) { return h.key === key })
    controller.heldRuns = controller.heldRuns.filter(function (h) { return h.key !== key })
    due.forEach(function (h) { h.deliver() })
    return due.length
  }

  function reset() {
    controller.responses = ({})
    controller.runs = []
    controller.heldRuns = []
  }
}
