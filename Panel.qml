import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omagesture — bar button plus a gesture-mapping popup.
//
// The panel never writes Lua. It persists the mapping into its inline
// shell.json entry and shells out to omagesture-apply, which owns the
// generated Hyprland config, so there is one place a gesture's Lua can be
// wrong instead of two.
Panel {
  id: root
  moduleName: "io.github.heroesofcode.omagesture"
  ipcTarget: "io.github.heroesofcode.omagesture"

  readonly property string scriptPath: Qt.resolvedUrl("omagesture-apply").toString().replace("file://", "")

  readonly property bool gesturesOn: get("enabled") === true
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // A multi-finger drag and a swipe of the same finger count cannot coexist:
  // libinput gives the contact to the drag. omagesture-apply drops the drag
  // and says so in the generated file; surface it here too, so the setting
  // does not look like it silently did nothing.
  readonly property bool dragShadowed: {
    var mode = get("drag")
    if (mode === "off" || !gesturesOn) return false
    var keys = Model.slotKeys(mode === "threefinger" ? 3 : 4)
    for (var i = 0; i < keys.length; i++) {
      if (get(keys[i]) !== "none") return true
    }
    return false
  }

  // The workspace-swipe tuning only means anything while some gesture is
  // actually mapped to "workspace", so the section hides rather than offering
  // settings that change nothing.
  readonly property bool workspaceSwipeMapped: {
    if (!gesturesOn) return false
    var fingerCounts = [2, 3, 4]
    for (var f = 0; f < fingerCounts.length; f++) {
      var keys = Model.slotKeys(fingerCounts[f])
      for (var i = 0; i < keys.length; i++) {
        if (get(keys[i]) === "workspace") return true
      }
    }
    return false
  }

  // Under clickfinger the middle button is a three-finger click, so binding it
  // buys press-and-drag window handling — at the cost of applications never
  // seeing a middle click again. Say which half of that trade is in effect.
  readonly property string middleButtonNote: {
    var v = get("middleButton")
    var what = v === "resize" ? "Three-finger click and drag resizes the window."
             : v === "move"   ? "Three-finger click and drag moves the window."
             : "Three-finger click is bound."
    return what + " Applications no longer receive middle click, so there is no"
      + " paste-on-middle-click and no open-link-in-new-tab."
  }

  property bool dropdownOwnsKeys: false

  // Effective value for a settings key: whatever the shell persisted, else the
  // plugin's own default. Every read goes through here so an unsaved key never
  // reads as "none" and silently unmaps a gesture.
  function get(key) { return root.setting(key, Model.defaultFor(key)) }

  // Persist into the inline shell.json entry, then regenerate the Lua. The
  // regeneration is debounced so walking a dropdown with the keyboard does not
  // fire a hyprctl reload per hovered row.
  function save(patch) {
    root.settings = Object.assign({}, root.settings, patch)
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
    applyDebounce.restart()
  }

  // The panel edits whole axes, pinch included. Hyprland's combined directions
  // (`horizontal`, `vertical`, `pinch`) shadow their halves, and only the
  // combined form animates continuously under your fingers — so offering the
  // halves separately would invite a mapping that cannot exist. The
  // per-direction keys stay editable from the plugin's settings schema for
  // anyone who wants an asymmetric map.
  readonly property var axisSlots: ({ horizontal: [0, 1], vertical: [2, 3], pinch: [4, 5] })

  function saveAxis(fingers, axis, value) {
    var keys = Model.slotKeys(fingers)
    var slots = axisSlots[axis]
    var patch = {}
    patch[keys[slots[0]]] = value
    patch[keys[slots[1]]] = value
    save(patch)
  }

  function axisValue(fingers, axis) {
    return get(Model.slotKeys(fingers)[axisSlots[axis][0]])
  }

  function apply() {
    if (applyProc.running) { applyDebounce.restart(); return }
    applyProc.command = Model.commandFor(root.scriptPath, root.get)
    applyProc.running = true
  }

  Timer {
    id: applyDebounce
    interval: 350
    onTriggered: root.apply()
  }

  Process {
    id: applyProc
    onExited: reloadProc.running = true
  }

  Process {
    id: reloadProc
    command: ["hyprctl", "reload"]
  }

  // Regenerate whenever the persisted settings change, including the moment
  // the shell first hands them over: a freshly enabled widget starts with an
  // empty object, so applying only at Component.onCompleted would write the
  // defaults and never revisit them. The debounce collapses the burst.
  onSettingsChanged: applyDebounce.restart()

  // A fresh install, or a generated file removed by something else, heals
  // itself without the user ever opening the panel.
  Component.onCompleted: applyDebounce.restart()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰠡"
    tooltipText: Model.summary(root.get)
    onPressed: function(b) {
      if (b === Qt.RightButton) root.save({ enabled: !root.gesturesOn })
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.dropdownOwnsKeys
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // The card height is capped to what fits on screen, and this panel is
      // taller than a small laptop display once both finger columns and the
      // touchpad section are open — without this the bottom rows were simply
      // cut off rather than reachable.
      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroll.width
          spacing: Style.space(14)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroSwitch.implicitHeight)

            Text {
              id: heroIcon
              text: "󰠡"
              color: root.gesturesOn ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Behavior on color { ColorAnimation { duration: 200 } }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroSwitch.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Omagesture"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: Model.summary(root.get).toUpperCase()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }

            ToggleSwitch {
              id: heroSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.gesturesOn
              foreground: root.foreground
              onToggled: root.save({ enabled: !root.gesturesOn })
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- Swipes, one column per finger count ----------
          Row {
            width: parent.width
            spacing: Style.space(18)
            opacity: root.gesturesOn ? 1.0 : 0.45

            Behavior on opacity { NumberAnimation { duration: 160 } }

            FingerColumn {
              width: (parent.width - parent.spacing) / 2
              fingers: 3
              title: "THREE FINGERS"
            }

            FingerColumn {
              width: (parent.width - parent.spacing) / 2
              fingers: 4
              title: "FOUR FINGERS"
            }
          }

          // Two fingers get pinch only. Their swipes are scroll, and a gesture
          // bound there would take scrolling away from every application.
          Column {
            width: parent.width
            spacing: Style.space(10)
            opacity: root.gesturesOn ? 1.0 : 0.45

            Behavior on opacity { NumberAnimation { duration: 160 } }

            PanelSectionHeader {
              text: "TWO FINGERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SettingDropdown {
              width: (parent.width - Style.space(18)) / 2
              label: "Pinch"
              boundValue: root.axisValue(2, "pinch")
              onPicked: function(v) { root.saveAxis(2, "pinch", v) }
            }

            Text {
              visible: root.axisValue(2, "pinch") !== "none"
              width: parent.width
              text: "While this is mapped, the compositor takes the two-finger pinch before applications see it — browsers and image viewers lose their own pinch-to-zoom."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- Workspace swipe ----------
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.workspaceSwipeMapped

            PanelSectionHeader {
              text: "WORKSPACE SWIPE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SettingDropdown {
              width: (parent.width - Style.space(18)) / 2
              label: "Reaches"
              actionOptions: Model.SWIPE_RANGES
              boundValue: root.get("swipeRange")
              onPicked: function(v) { root.save({ swipeRange: v }) }
            }

            Toggle {
              width: parent.width
              label: "Keep swiping without lifting"
              description: "Cross several workspaces in one motion instead of one per swipe."
              checked: root.get("swipeForever") === true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.save({ swipeForever: root.get("swipeForever") !== true })
            }
          }

          PanelSeparator {
            foreground: root.foreground
            visible: root.workspaceSwipeMapped
          }

          // ---------- Touchpad behaviour ----------
          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "TOUCHPAD"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Toggle {
              width: parent.width
              label: "Natural scrolling"
              description: "Content follows your fingers, as on macOS."
              checked: root.get("naturalScroll") === true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.save({ naturalScroll: root.get("naturalScroll") !== true })
            }

            Row {
              width: parent.width
              spacing: Style.space(18)

              SettingDropdown {
                width: (parent.width - parent.spacing) / 2
                label: "Click method"
                actionOptions: Model.CLICK_METHODS
                boundValue: root.get("clickMethod")
                onPicked: function(v) { root.save({ clickMethod: v }) }
              }

              SettingDropdown {
                width: (parent.width - parent.spacing) / 2
                label: "Middle click"
                actionOptions: Model.MIDDLE_BUTTONS
                boundValue: root.get("middleButton")
                onPicked: function(v) { root.save({ middleButton: v }) }
              }
            }

            SettingDropdown {
              width: (parent.width - Style.space(18)) / 2
              label: "Multi-finger drag"
              actionOptions: Model.DRAG_MODES
              boundValue: root.get("drag")
              onPicked: function(v) { root.save({ drag: v }) }
            }

            Text {
              visible: root.get("middleButton") !== "none"
              width: parent.width
              text: root.middleButtonNote
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.dragShadowed
              width: parent.width
              text: "Drag stays off while swipes of the same finger count are mapped — libinput can only give those fingers to one of the two."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }

  // One finger count: both axes plus both pinches.
  component FingerColumn: Column {
    id: fingerColumn

    required property int fingers
    required property string title

    spacing: Style.space(10)

    PanelSectionHeader {
      text: fingerColumn.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    SettingDropdown {
      width: fingerColumn.width
      label: "Swipe ← →"
      boundValue: root.axisValue(fingerColumn.fingers, "horizontal")
      onPicked: function(v) { root.saveAxis(fingerColumn.fingers, "horizontal", v) }
    }

    SettingDropdown {
      width: fingerColumn.width
      label: "Swipe ↑ ↓"
      boundValue: root.axisValue(fingerColumn.fingers, "vertical")
      onPicked: function(v) { root.saveAxis(fingerColumn.fingers, "vertical", v) }
    }

    SettingDropdown {
      width: fingerColumn.width
      label: "Pinch"
      boundValue: root.axisValue(fingerColumn.fingers, "pinch")
      onPicked: function(v) { root.saveAxis(fingerColumn.fingers, "pinch", v) }
    }
  }

  // Dropdown that reports its popup state, so the panel's key catcher stops
  // competing for j/k while a list is open.
  //
  // `value` is driven from `boundValue` through a handler rather than bound
  // straight to it: Dropdown assigns to its own `value` when a row is chosen,
  // which would destroy a declarative binding and leave the control deaf to
  // any later change made elsewhere, such as the settings schema.
  component SettingDropdown: Dropdown {
    property string boundValue: ""
    property var actionOptions: Model.ACTIONS

    signal picked(string value)

    options: actionOptions
    value: boundValue

    onBoundValueChanged: if (value !== boundValue) value = boundValue
    onChanged: function(v) { picked(v) }
    onPopupOpenChanged: root.dropdownOwnsKeys = popupOpen
  }
}
