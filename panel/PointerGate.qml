import QtQuick

// Lets hover move a highlight only when the pointer really moves. Qt Quick
// re-sends hover at a still pointer whenever items move under it (a view
// sliding in, a list scrolling), which would take the highlight the keys
// just set. hold() notes where the pointer was last seen, even once it is
// off this item (a shorter view can leave it below, and Qt then clears
// `point`); hover(act) then waits until the pointer moves from that spot.
//
// Put it on the item that holds the rows: Qt hands hover to the rows
// first, so a row's hover arrives just before this handler sees the move
// that caused it, and runs then if the move was real.
HoverHandler {
  id: gate

  property var seenAt: null
  property var heldAt: null
  property var pending: null

  function hold() {
    gate.heldAt = gate.seenAt
    gate.pending = null
  }

  // Runs act now, or, while held, when the pointer first moves.
  function hover(act) {
    if (gate.heldAt === null) act()
    else gate.pending = act
  }

  onPointChanged: {
    if (!gate.hovered) return
    var p = gate.point.scenePosition
    gate.seenAt = p
    if (gate.heldAt === null) return
    if (Math.abs(p.x - gate.heldAt.x) < 1 && Math.abs(p.y - gate.heldAt.y) < 1) return
    var act = gate.pending
    gate.heldAt = null
    gate.pending = null
    if (act) act()
  }
}
