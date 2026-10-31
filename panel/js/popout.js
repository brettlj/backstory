.pragma library

// The bar popup's pop-out into the window (BarWidget.qml -> Panel.qml). The
// popup sends where its card is on screen as `from`; the window starts there,
// then rests the bar's height below the bar and the same to the left, one
// diagonal move. Any process that can summon the window can send `from`, so a
// rect that isn't plain numbers in range is refused.

var LIMIT = 100000

function isCoord(v) {
  return typeof v === "number" && isFinite(v) && Math.abs(v) <= LIMIT
}

// from: { x, y, w, h } of the popup's card (screen, logical px), the bar's
// thickness `bar` and the card's `gap` below it, and the monitor's origin
// monX, monY. Returns the same, rounded, or null when anything is off.
function fromRect(v) {
  if (!v || typeof v !== "object") return null
  var keys = ["x", "y", "w", "h", "bar", "gap", "monX", "monY"]
  for (var i = 0; i < keys.length; i++) if (!isCoord(v[keys[i]])) return null
  if (v.w <= 0 || v.h <= 0 || v.bar < 0 || v.gap < 0) return null
  var r = {}
  for (var k = 0; k < keys.length; k++) r[keys[k]] = Math.round(v[keys[k]])
  return r
}

// Where the window rests: the bar's height below the bar (the card hangs one
// gap below it) and the same to the left, taller by `grow` (the grab handle).
function restRect(from, grow) {
  return {
    x: from.x - from.bar,
    y: from.y - from.gap + from.bar,
    w: from.w,
    h: from.h + Math.round(grow)
  }
}
