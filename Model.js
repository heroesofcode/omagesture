.pragma library

// Shared, UI-free logic for Omagesture.
//
// Panel.qml owns pixels; this file owns the action catalogue, the defaults and
// the command handed to omagesture-apply. The script stays the only thing that
// writes Lua, so the panel and the CLI cannot disagree about what a gesture
// means.

// Every action the panel offers, in menu order. `value` is the token
// omagesture-apply understands; `label` is what a person reads.
//
// All of these except "Omarchy menu" are native Hyprland gesture actions,
// which means they animate continuously under your fingers rather than firing
// at the end of the swipe.
var ACTIONS = [
  { value: "none",          label: "Nothing" },
  { value: "workspace",     label: "Switch workspace" },
  { value: "special",       label: "Scratchpad" },
  { value: "fullscreen",    label: "Fullscreen" },
  { value: "maximize",      label: "Maximize" },
  { value: "float",         label: "Float / tile" },
  { value: "move_window",   label: "Move window" },
  { value: "resize_window", label: "Resize window" },
  { value: "close_window",  label: "Close window" },
  { value: "zoom",          label: "Zoom screen" },
  { value: "menu",          label: "Omarchy menu" }
]

var CLICK_METHODS = [
  { value: "clickfinger", label: "Two fingers = right click" },
  { value: "buttonareas", label: "Bottom-right = right click" }
]

var DRAG_MODES = [
  { value: "off",         label: "Off" },
  { value: "threefinger", label: "Three fingers" },
  { value: "fourfinger",  label: "Four fingers" }
]

// How far a workspace swipe travels. Hyprland's default walks only the
// workspaces that already exist and wraps at the end, which caps you at one
// past the last open one; "numbered" targets by workspace number instead.
var SWIPE_RANGES = [
  { value: "numbered", label: "Every workspace" },
  { value: "existing", label: "Only open ones" }
]

// What the middle button does. Under `clickfinger` that is a three-finger
// click, so the first two entries turn a three-finger press-and-drag into
// window resizing or moving.
var MIDDLE_BUTTONS = [
  { value: "none",       label: "Nothing" },
  { value: "resize",     label: "Hold & drag to resize" },
  { value: "move",       label: "Hold & drag to move" },
  { value: "screenshot", label: "Screenshot region" },
  { value: "paste",      label: "Paste selection" }
]

// Mirrors manifest.json's barWidget.defaults and the DEFAULTS block in
// omagesture-apply.
//
// Repeated here on purpose: the shell hands a freshly enabled widget an empty
// settings object, so reading the manifest alone would generate an empty
// gesture file on first run and only come good once the user touched
// something. Going through defaultFor() means the first write is already the
// intended mapping.
var DEFAULTS = {
  enabled: true,
  naturalScroll: true,
  clickMethod: "clickfinger",
  drag: "off",
  middleButton: "move",
  swipeRange: "numbered",
  swipeForever: false,

  // Two fingers stay unmapped: their swipes are scroll, and a pinch here is
  // both taken from applications and easy to trigger by accident while resting
  // two fingers on a buttonpad.
  g2PinchIn: "none",
  g2PinchOut: "none",

  // Three fingers: the MacBook reflex. Slide between workspaces, and swipe up
  // for the Omarchy menu.
  g3Left: "workspace",
  g3Right: "workspace",
  g3Up: "menu",
  g3Down: "none",
  g3PinchIn: "none",
  g3PinchOut: "none",

  // Four fingers resize the focused window, on both axes.
  //
  // This is a swipe rather than the more obvious pinch because libinput does
  // not report pinch on this trackpad above two fingers — a three- or
  // four-finger squeeze arrives as a horizontal swipe, so a pinch mapping here
  // would never fire. Mirroring the three-finger workspace swipe was the old
  // default and bought nothing, since three fingers already do it.
  g4Left: "resize_window",
  g4Right: "resize_window",
  g4Up: "resize_window",
  g4Down: "resize_window",
  g4PinchIn: "none",
  g4PinchOut: "none"
}

var GESTURE_KEYS = ["Left", "Right", "Up", "Down", "PinchIn", "PinchOut"]

function defaultFor(key) {
  return DEFAULTS.hasOwnProperty(key) ? DEFAULTS[key] : "none"
}

// Settings keys for one finger count: left, right, up, down, pinch in, out.
function slotKeys(fingers) {
  var keys = []
  for (var i = 0; i < GESTURE_KEYS.length; i++) keys.push("g" + fingers + GESTURE_KEYS[i])
  return keys
}

function labelFor(value) {
  for (var i = 0; i < ACTIONS.length; i++) {
    if (ACTIONS[i].value === value) return ACTIONS[i].label
  }
  return value
}

// Whole settings object with every key resolved. `get` is a one-argument
// function returning the effective value for a key, so this stays free of QML.
function settingsFor(get) {
  var out = {}
  for (var key in DEFAULTS) {
    if (DEFAULTS.hasOwnProperty(key)) out[key] = get(key)
  }
  return out
}

function commandFor(scriptPath, get) {
  return ["bash", scriptPath, JSON.stringify(settingsFor(get))]
}

// One-line description of the active mapping, for the bar tooltip.
function summary(get) {
  if (!get("enabled")) return "Gestures off"

  var parts = []
  var fingerCounts = [3, 4]
  for (var f = 0; f < fingerCounts.length; f++) {
    var n = fingerCounts[f]
    var left = get("g" + n + "Left")
    if (left !== "none" && left === get("g" + n + "Right")) {
      parts.push(n + " fingers: " + labelFor(left).toLowerCase())
    }
  }

  return parts.length ? parts.join(" · ") : "Omagesture"
}
