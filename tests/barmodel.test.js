// Regression tests for BarModel.js (fullscreen input check and first-run
// Studio button placement). Run: node tests/barmodel.test.js
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "..", "BarModel.js"))

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
  } catch (e) {
    console.error("FAIL " + name)
    throw e
  }
}

const SCREEN = { x: 0, y: 0, width: 1920, height: 1080 }
const STOCK_LAYOUT = {
  left: [{ id: "omarchy.menu" }, { id: "omarchy.workspaces" }],
  centerBegin: [{ id: "omarchy.indicators" }],
  center: [{ id: "omarchy.clock", format: "dddd HH:mm" }],
  centerEnd: [{ id: "omarchy.weather" }],
  tray: [],
  right: [{ id: "omarchy.tray" }, { id: "omarchy.audio" }, { id: "omarchy.power" }]
}

function toplevel(opts) {
  return {
    workspace: { id: opts.wsId, name: opts.wsName || String(opts.wsId) },
    lastIpcObject: {
      fullscreen: opts.fullscreen === undefined ? 2 : opts.fullscreen,
      at: opts.at || [0, 0],
      size: opts.size || [1920, 1080]
    }
  }
}

// ---- fullscreenOn -----------------------------------------------------------

test("fullscreenOn: real fullscreen window covering output returns true", () => {
  const list = [toplevel({ wsId: 1, fullscreen: 2, at: [0, 0], size: [1920, 1080] })]
  assert.strictEqual(M.fullscreenOn(list, 1, true, null, SCREEN), true)
})

test("fullscreenOn: fullscreen column outside viewport (scrolling layout) returns false", () => {
  const list = [
    toplevel({ wsId: 1, fullscreen: 2, at: [1920, 0], size: [1920, 1080] }),
    toplevel({ wsId: 1, fullscreen: 2, at: [-1920, 0], size: [1920, 1080] })
  ]
  assert.strictEqual(M.fullscreenOn(list, 1, true, null, SCREEN), false)
})

test("fullscreenOn: special workspace over a fullscreen normal window returns false", () => {
  const list = [
    toplevel({ wsId: 1, wsName: "1", fullscreen: 2, at: [0, 0], size: [1920, 1080] }),
    toplevel({ wsId: -98, wsName: "special:scratchpad", fullscreen: 0, at: [200, 150], size: [1200, 700] })
  ]
  assert.strictEqual(M.fullscreenOn(list, 1, true, "special:scratchpad", SCREEN), false)
})

test("fullscreenOn: fullscreen window inside the active special workspace returns true", () => {
  const list = [
    toplevel({ wsId: -98, wsName: "special:scratchpad", fullscreen: 2, at: [0, 0], size: [1920, 1080] })
  ]
  assert.strictEqual(M.fullscreenOn(list, 1, false, "special:scratchpad", SCREEN), true)
})

test("fullscreenOn: 1 px rounding tolerance at fractional scale returns true, 2 px inset returns false", () => {
  const rounded = [toplevel({ wsId: 2, fullscreen: 2, at: [1, 1], size: [1918, 1078] })]
  assert.strictEqual(M.fullscreenOn(rounded, 2, true, null, SCREEN), true)

  const inset = [toplevel({ wsId: 2, fullscreen: 2, at: [2, 2], size: [1916, 1076] })]
  assert.strictEqual(M.fullscreenOn(inset, 2, true, null, SCREEN), false)
})

test("fullscreenOn: maximized window (bit 2 unset) and workspace without fullscreen return false", () => {
  const maximized = [toplevel({ wsId: 1, fullscreen: 1, at: [0, 0], size: [1920, 1080] })]
  assert.strictEqual(M.fullscreenOn(maximized, 1, true, null, SCREEN), false)

  const full = [toplevel({ wsId: 1, fullscreen: 2, at: [0, 0], size: [1920, 1080] })]
  assert.strictEqual(M.fullscreenOn(full, 1, false, null, SCREEN), false)
})

// ---- placeStudioButton ------------------------------------------------------

test("placeStudioButton: missing bar.layout keeps stock widgets and appends the button to right", () => {
  const config = { version: 1, bar: { id: "thepixelgardener.barcraft" } }
  const out = M.placeStudioButton(config, "thepixelgardener.barcraft", STOCK_LAYOUT)
  assert.ok(out !== null)
  assert.deepStrictEqual(out.bar.layout.left.map(e => e.id), ["omarchy.menu", "omarchy.workspaces"])
  assert.deepStrictEqual(out.bar.layout.center.map(e => e.id), ["omarchy.clock"])
  assert.deepStrictEqual(
    out.bar.layout.right.map(e => e.id),
    ["omarchy.tray", "omarchy.audio", "omarchy.power", "thepixelgardener.barcraft"]
  )
  assert.strictEqual(out.bar.barcraft.studioButtonPlaced, true)
  // Running again is a no-op.
  assert.strictEqual(M.placeStudioButton(out, "thepixelgardener.barcraft", STOCK_LAYOUT), null)
})

test("placeStudioButton: customized layout preserves widget order and appends button to right", () => {
  const config = {
    version: 1,
    bar: {
      id: "thepixelgardener.barcraft",
      layout: {
        left: [{ id: "omarchy.workspaces" }, { id: "custom.widget", opt: 1 }],
        centerBegin: [],
        center: [{ id: "omarchy.clock" }],
        centerEnd: [],
        tray: [],
        right: [{ id: "omarchy.audio" }, { id: "omarchy.network" }]
      }
    }
  }
  const out = M.placeStudioButton(config, "thepixelgardener.barcraft", STOCK_LAYOUT)
  assert.ok(out !== null)
  assert.deepStrictEqual(out.bar.layout.left, [{ id: "omarchy.workspaces" }, { id: "custom.widget", opt: 1 }])
  assert.deepStrictEqual(
    out.bar.layout.right.map(e => e.id),
    ["omarchy.audio", "omarchy.network", "thepixelgardener.barcraft"]
  )
  assert.strictEqual(out.bar.barcraft.studioButtonPlaced, true)
})

test("placeStudioButton: button already placed anywhere is not duplicated", () => {
  const config = {
    version: 1,
    bar: {
      id: "thepixelgardener.barcraft",
      layout: {
        left: [{ id: "thepixelgardener.barcraft" }, { id: "omarchy.workspaces" }],
        centerBegin: [],
        center: [{ id: "omarchy.clock" }],
        centerEnd: [],
        tray: [],
        right: [{ id: "omarchy.power" }]
      }
    }
  }
  const out = M.placeStudioButton(config, "thepixelgardener.barcraft", STOCK_LAYOUT)
  assert.ok(out !== null)
  assert.deepStrictEqual(out.bar.layout.left.map(e => e.id), ["thepixelgardener.barcraft", "omarchy.workspaces"])
  assert.deepStrictEqual(out.bar.layout.right.map(e => e.id), ["omarchy.power"])
  assert.strictEqual(out.bar.barcraft.studioButtonPlaced, true)
  // Second pass with flag set returns null.
  assert.strictEqual(M.placeStudioButton(out, "thepixelgardener.barcraft", STOCK_LAYOUT), null)
})

test("placeStudioButton: upgrading from 0.7 (bar.barcraft without flag) sets flag and leaves layout untouched", () => {
  const config = {
    version: 1,
    bar: {
      id: "thepixelgardener.barcraft",
      layout: {
        left: [{ id: "omarchy.workspaces" }],
        centerBegin: [],
        center: [{ id: "omarchy.clock" }],
        centerEnd: [],
        tray: [],
        right: [{ id: "omarchy.power" }]
      },
      barcraft: { skin: "statusline", followTheme: false }
    }
  }
  const out = M.placeStudioButton(config, "thepixelgardener.barcraft", STOCK_LAYOUT)
  assert.ok(out !== null)
  assert.strictEqual(out.bar.barcraft.studioButtonPlaced, true)
  assert.strictEqual(out.bar.barcraft.skin, "statusline")
  // Button was removed intentionally in 0.7 and stays removed.
  assert.deepStrictEqual(out.bar.layout.right.map(e => e.id), ["omarchy.power"])
})

test("placeStudioButton: with flag set and button removed, button stays removed until forced restore", () => {
  const config = {
    version: 1,
    bar: {
      id: "thepixelgardener.barcraft",
      layout: {
        left: [{ id: "omarchy.workspaces" }],
        centerBegin: [],
        center: [{ id: "omarchy.clock" }],
        centerEnd: [],
        tray: [],
        right: [{ id: "omarchy.power" }]
      },
      barcraft: { skin: "floating", studioButtonPlaced: true }
    }
  }
  // Normal startup does nothing.
  assert.strictEqual(M.placeStudioButton(config, "thepixelgardener.barcraft", STOCK_LAYOUT), null)
  assert.deepStrictEqual(config.bar.layout.right.map(e => e.id), ["omarchy.power"])

  // Explicit restoreButton ({ force: true }) puts it back.
  const restored = M.placeStudioButton(config, "thepixelgardener.barcraft", STOCK_LAYOUT, { force: true })
  assert.ok(restored !== null)
  assert.deepStrictEqual(restored.bar.layout.right.map(e => e.id), ["omarchy.power", "thepixelgardener.barcraft"])

  // Calling restoreButton again when already on bar is a no-op.
  assert.strictEqual(M.placeStudioButton(restored, "thepixelgardener.barcraft", STOCK_LAYOUT, { force: true }), null)
})

console.log("BarModel: " + passed + " tests passed")
