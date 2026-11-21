import QtQuick
import QtQuick.Layouts
import Quickshell
import "kit/Theme"
import "kit/Theme" as Kit
import "kit/Ui" as O

// Barcraft Studio, drawn with the Omarchy UI kit (kit/, github.com/omacom/
// omarchy-ui): the shell's own components as a library, so the Studio looks
// and behaves like Omarchy Control and follows the theme the same way.
//
// Tabs: Skins (pick, preview on hover or under the cursor, give a screen its
// own skin, manage saved skins), then Colors, Geometry, Surface and Behavior,
// every skin field as a settings row, save and share below them.
//
// Keyboard: arrows or hjkl move the cursor, Left/Right adjust the row under
// it, Return or Space activates, 1-5 pick a tab, R renames and Delete removes
// a saved skin, Esc closes, Tab moves to the next panel on the bar.
Column {
  id: root

  property var bar: null
  property var engine: null
  property var strings: null
  // The card's room for this content, so the body scrolls rather than grows.
  property real maxHeight: Style.space(680)
  property bool panelOpen: true
  // Set by the widget to open on a tab (`omarchy-shell barcraft studio geometry`).
  property string requestedTab: ""
  property int tabRequest: 0
  onTabRequestChanged: if (requestedTab !== "") setTab(requestedTab)
  Component.onCompleted: if (requestedTab !== "") setTab(requestedTab)
  // The key catcher, to hand the keyboard back to after editing text.
  property Item keyTarget: null

  property string activeTab: "presets"
  property string colorTarget: "surface"
  property string screenTarget: ""
  property string statusMessage: ""
  property bool statusError: false
  property string renamingId: ""
  property string confirmDeleteId: ""
  property string confirmOverwriteName: ""
  property string pendingPreview: ""

  property bool keyboardMode: false
  property var navItems: []
  property Item navCurrent: null
  property point lastPointer: Qt.point(-1, -1)

  readonly property bool textEditing: nameField.activeFocus || renamingId !== ""
  readonly property color fg: Kit.Color.popups.text
  readonly property color dimFg: Kit.Color.textDim
  readonly property var screenNames: {
    var out = []
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) out.push(list[i].name)
    return out
  }
  readonly property var palette: engine ? engine.themeColors : ({})
  // Skin tiles, four to a row.
  readonly property real cardWidth: Math.floor((width - Style.spacing.sm * 3) / 4)

  spacing: Style.spacing.md

  function tr(key, fallback) {
    return strings ? strings.t(key) : (fallback || key)
  }

  function num(value, decimals) {
    return Kit.I18n.formatNumber(value, decimals || 0)
  }

  function percent(value) {
    return num(Math.round(value * 100)) + "%"
  }

  // A built-in skin's description in the Omarchy language; saved skins keep
  // the words their author wrote.
  function skinDescription(skin) {
    if (!skin) return ""
    if (skin.source !== "builtin") return skin.description || ""
    var key = "skin." + skin.id
    var text = strings ? strings.t(key) : key
    return text && text !== key ? text : (skin.description || "")
  }

  // ---- Status line ---------------------------------------------------------

  Timer {
    id: statusTimer
    interval: 3200
    repeat: false
    onTriggered: root.statusMessage = ""
  }

  function showStatus(msg, isError) {
    statusMessage = msg
    statusError = !!isError
    statusTimer.restart()
  }

  Connections {
    target: root.engine
    function onNotice(key, arg, isError) {
      root.showStatus(root.tr(key).arg(arg), isError)
    }
  }

  onPanelOpenChanged: {
    if (panelOpen) return
    keyboardMode = false
    renamingId = ""
    confirmDeleteId = ""
    confirmOverwriteName = ""
    pendingPreview = ""
    previewTimer.stop()
    if (engine) engine.clearPreview()
  }

  // ---- Preview -------------------------------------------------------------

  Timer {
    id: previewTimer
    interval: 160
    repeat: false
    onTriggered: {
      if (!root.engine) return
      if (root.pendingPreview !== "" && root.activeTab === "presets") root.engine.previewById(root.pendingPreview, root.screenTarget)
      else root.engine.clearPreview()
    }
  }

  function hoverPreview(id, on) {
    if (on) pendingPreview = id
    else if (pendingPreview === id) pendingPreview = ""
    previewTimer.restart()
  }

  readonly property var tabs: ["presets", "colors", "geometry", "surface", "behavior"]
  readonly property bool craftTab: activeTab !== "presets"

  function setTab(tab) {
    if (activeTab === tab || tabs.indexOf(tab) < 0) return
    if (textEditing) {
      renamingId = ""
      restoreKeys()
    }
    activeTab = tab
    navCurrent = tabRow
    restoreKey = ""
    pendingPreview = ""
    previewTimer.stop()
    if (engine) engine.clearPreview()
    body.flickable.contentY = 0
  }

  function stepTab(direction) {
    var i = tabs.indexOf(activeTab)
    setTab(tabs[(i + direction + tabs.length) % tabs.length])
  }

  // ---- Choosing and managing skins -------------------------------------------

  function pickSkin(id) {
    if (!engine) return
    pendingPreview = ""
    previewTimer.stop()
    if (id === "standard") {
      engine.setStandard(!engine.standard)
      return
    }
    if (screenTarget === "") engine.selectSkin(id)
    else engine.selectForScreen(screenTarget, id)
  }

  function chosenId() {
    if (!engine) return ""
    engine.revision
    return engine.chosenIdFor(screenTarget)
  }

  Timer {
    id: confirmTimer
    interval: 3000
    repeat: false
    onTriggered: root.confirmDeleteId = ""
  }

  function requestDelete(id, name) {
    if (!engine) return
    if (confirmDeleteId === id) {
      confirmDeleteId = ""
      engine.deleteUserSkin(id)
      return
    }
    confirmDeleteId = id
    confirmTimer.restart()
    showStatus(tr("status.confirmDelete").arg(name), true)
  }

  function startRename(id) {
    confirmDeleteId = ""
    renamingId = id
  }

  function finishRename(id, text, commit) {
    if (renamingId !== id) return
    renamingId = ""
    if (commit && engine) {
      var slug = engine.renameUserSkin(id, text)
      if (slug) restoreKey = "card:" + slug
      for (var i = 0; i < navItems.length; i++) {
        if (navItems[i].navKey === restoreKey) {
          navCurrent = navItems[i]
          restoreKey = ""
        }
      }
    }
    restoreKeys()
  }

  Timer {
    id: overwriteTimer
    interval: 4000
    repeat: false
    onTriggered: root.confirmOverwriteName = ""
  }

  function saveSkin() {
    if (!engine) return
    var wanted = nameField.text || engine.committedSkin.name
    var confirmed = confirmOverwriteName !== "" && confirmOverwriteName === wanted
    var res = engine.saveUserSkin(wanted, confirmed)
    if (res && res.needsConfirm) {
      confirmOverwriteName = wanted
      overwriteTimer.restart()
      showStatus(tr("status.confirmOverwrite").arg(res.conflictName), true)
      return
    }
    confirmOverwriteName = ""
    overwriteTimer.stop()
    nameField.text = ""
  }

  function restoreKeys() {
    if (keyTarget) Qt.callLater(function() { if (root.keyTarget) root.keyTarget.forceActiveFocus() })
  }

  // ---- Keyboard cursor -------------------------------------------------------

  // A card rebuilt under the cursor (saved skins reload, a rename gives it a
  // new id) takes the cursor back by its key.
  property string restoreKey: ""

  function registerNav(item) {
    if (navItems.indexOf(item) < 0) navItems = navItems.concat([item])
    if (restoreKey !== "" && item.navKey === restoreKey) {
      navCurrent = item
      restoreKey = ""
    }
  }

  function unregisterNav(item) {
    var i = navItems.indexOf(item)
    if (i >= 0) {
      var next = navItems.slice()
      next.splice(i, 1)
      navItems = next
    }
    if (navCurrent === item) {
      navCurrent = null
      if (restoreKey === "") restoreKey = item.navKey
    }
  }

  // Visible rows in reading order, with their centers.
  function visibleNav() {
    var out = []
    for (var i = 0; i < navItems.length; i++) {
      var item = navItems[i]
      if (!item || !item.visible || !item.navEnabled || item.width <= 0 || item.height <= 0) continue
      var p = item.mapToItem(root, item.width / 2, item.height / 2)
      // Compare rows in the full document. Scrolled-off rows otherwise
      // overlap the pinned tabs and footer in window coordinates.
      var scroll = body.flickable
      var offset = item.inFooter ? Math.max(0, scroll.contentHeight - scroll.height)
        : item === tabRow ? 0 : scroll.contentY
      out.push({ item: item, x: p.x, y: p.y + offset })
    }
    out.sort(function(a, b) { return Math.abs(a.y - b.y) > 6 ? a.y - b.y : a.x - b.x })
    return out
  }

  function setCurrent(item) {
    navCurrent = item
    if (!item) return
    if (item !== tabRow && !item.inFooter) body.ensureVisible(item)
    pendingPreview = item.navPreviewId
    previewTimer.restart()
  }

  function navMove(dx, dy) {
    keyboardMode = true
    var list = visibleNav()
    if (list.length === 0) return
    var idx = -1
    for (var i = 0; i < list.length; i++) if (list[i].item === navCurrent) idx = i
    if (idx < 0) {
      setCurrent(list[0].item)
      return
    }
    var cur = list[idx]
    if (dy !== 0) {
      var rowGap = Infinity
      for (var j = 0; j < list.length; j++) {
        var d = (list[j].y - cur.y) * dy
        if (d > 6 && d < rowGap) rowGap = d
      }
      if (rowGap === Infinity) return
      var best = null
      for (var k = 0; k < list.length; k++) {
        var dk = (list[k].y - cur.y) * dy
        if (Math.abs(dk - rowGap) > 6) continue
        if (!best || Math.abs(list[k].x - cur.x) < Math.abs(best.x - cur.x)) best = list[k]
      }
      if (best) setCurrent(best.item)
    } else if (dx !== 0) {
      if (cur.item.navGrid) {
        var n = list[idx + dx]
        if (n) setCurrent(n.item)
      } else {
        cur.item.adjust(dx)
      }
    }
  }

  function navActivate() {
    keyboardMode = true
    if (navCurrent && navCurrent.visible) navCurrent.activate()
    else navMove(0, 1)
  }

  function navDelete() {
    if (navCurrent && navCurrent.visible) navCurrent.remove()
  }

  function navText(t) {
    var n = parseInt(t, 10)
    if (n >= 1 && n <= tabs.length) { setTab(tabs[n - 1]); return }
    if (navCurrent && navCurrent.visible) navCurrent.textKey(t)
  }

  // The pointer moving takes the keyboard cursor away.
  HoverHandler {
    onPointChanged: {
      var p = point.scenePosition
      if (root.keyboardMode && (Math.abs(p.x - root.lastPointer.x) > 4 || Math.abs(p.y - root.lastPointer.y) > 4)) root.keyboardMode = false
      root.lastPointer = Qt.point(p.x, p.y)
    }
  }

  // ---- Header and tabs ---------------------------------------------------------

  O.PanelHero {
    id: hero
    width: parent.width
    foreground: root.fg
    title: root.tr("title", "Barcraft")
    meta: {
      if (!root.engine) return ""
      root.engine.revision
      if (root.engine.previewing) return root.tr("meta.preview").arg(root.engine.previewSkin.name)
      if (root.engine.standard) return root.tr("meta.standard", "Omarchy standard")
      var name = root.engine.committedSkin.name
      if (root.engine.usingThemeSkin) return root.tr("meta.theme").arg(name)
      if (root.engine.hasCustomDraft) return root.tr("meta.custom").arg(name)
      return root.tr("meta.preset").arg(name)
    }
    iconComponent: Component {
      BarcraftMark {
        width: Math.round(Style.font.display * 1.5)
        height: Math.round(width * 0.56)
        ink: root.fg
      }
    }
  }

  NavItem {
    id: tabRow
    navKey: "tabs"
    width: parent.width
    implicitHeight: tabBar.implicitHeight
    height: implicitHeight
    onAdjust: function(direction) { root.stepTab(direction) }
    onActivate: root.stepTab(1)

    O.Tabs {
      id: tabBar
      width: parent.width
      model: [
        root.tr("tab.presets", "Skins"),
        root.tr("tab.colors", "Colors"),
        root.tr("tab.geometry", "Geometry"),
        root.tr("tab.surface", "Surface"),
        root.tr("tab.behavior", "Behavior")
      ]
      // Tabs assigns currentIndex on pointer selection. A separate Binding
      // keeps it synchronized across clicks, number shortcuts and IPC.
      Binding on currentIndex { value: root.tabs.indexOf(root.activeTab) }
      cursorIndex: tabRow.navFocused ? currentIndex : -1
      activeFocusOnTab: false
      onActiveFocusChanged: if (activeFocus) root.restoreKeys()
      onActivated: function(index) { root.setTab(root.tabs[index]) }
    }
  }

  // ---- Body (scrolls) -------------------------------------------------------

  O.ScrollArea {
    id: body
    readonly property real chrome: hero.height + tabRow.height
      + (footer.visible ? footer.implicitHeight + root.spacing : 0)
      + (statusText.visible ? statusText.implicitHeight + root.spacing : 0)
      + (keysHint.visible ? keysHint.implicitHeight + root.spacing : 0)
      + root.spacing * 2
    width: parent.width
    maxHeight: Math.max(Style.space(140), root.maxHeight - chrome)
    spacing: Style.spacing.md

    // ========================================================================
    // SKINS
    // ========================================================================
    Column {
      width: parent.width
      spacing: Style.spacing.md
      visible: root.activeTab === "presets" && !!root.engine

      // Per-screen skins, when there is more than one screen.
      ChoiceRow {
        navKey: "screens"
        visible: root.screenNames.length > 1
        label: root.tr("label.applyTo", "Apply to")
        value: root.screenTarget === "" ? "*all*" : root.screenTarget
        options: {
          var out = [{ value: "*all*", label: root.tr("screens.all", "All screens") }]
          for (var i = 0; i < root.screenNames.length; i++) out.push({ value: root.screenNames[i], label: root.screenNames[i] })
          return out
        }
        onPicked: function(v) {
          root.screenTarget = v === "*all*" ? "" : v
          root.pendingPreview = ""
          previewTimer.restart()
        }
      }

      RowLayout {
        width: parent.width
        visible: root.screenTarget !== ""
        spacing: Style.spacing.md

        HintText {
          Layout.fillWidth: true
          text: root.tr("hint.screenSkin", "")
        }

        ActionButton {
          navKey: "useMain"
          visible: !!root.engine && (root.engine.revision, root.engine.hasMonitorSkin(root.screenTarget))
          text: root.tr("action.useMain", "Use main skin")
          onTriggered: if (root.engine) root.engine.selectForScreen(root.screenTarget, "")
        }
      }

      // Every skin in one grid: Omarchy's own bar first (the way back, a
      // click again leaves it), the theme's skin, the presets.
      Grid {
        width: parent.width
        columns: 4
        columnSpacing: Style.spacing.sm
        rowSpacing: Style.spacing.sm

        SkinCard {
          visible: root.screenTarget === ""
          width: root.cardWidth
          cardId: "standard"
          standardTile: true
          title: root.tr("tile.standard", "Omarchy")
          subtitle: root.tr("label.standardHint", "")
        }

        SkinCard {
          visible: !!root.engine && root.engine.themeSkin !== null
          width: root.cardWidth
          cardId: "theme"
          skinData: root.engine ? root.engine.themeSkin : null
          title: root.tr("card.theme", "Theme skin")
          subtitle: root.engine && root.engine.themeSkin ? root.engine.themeSkin.name : ""
        }

        Repeater {
          model: root.engine ? root.engine.builtinSkins : []

          SkinCard {
            required property var modelData
            width: root.cardWidth
            cardId: modelData.id
            skinData: modelData
            title: modelData.name
            subtitle: root.skinDescription(modelData)
          }
        }
      }

      // Saved skins (~/.config/omarchy/bar/skins/*.toml)
      RowLayout {
        width: parent.width
        spacing: Style.spacing.md

        O.PanelSectionHeader {
          Layout.fillWidth: true
          foreground: root.fg
          text: root.tr("section.user", "Your skins")
        }

        ActionButton {
          navKey: "pasteSkins"
          text: root.tr("action.paste", "Paste skin")
          iconText: "󰆒"
          onTriggered: if (root.engine) root.engine.importFromClipboard()
        }
      }

      Grid {
        width: parent.width
        columns: 4
        columnSpacing: Style.spacing.sm
        rowSpacing: Style.spacing.sm
        visible: !!root.engine && root.engine.userSkins.length > 0

        Repeater {
          model: root.engine ? root.engine.userSkins : []

          SkinCard {
            required property var modelData
            width: root.cardWidth
            cardId: modelData.id
            skinData: modelData
            title: modelData.name
            subtitle: root.skinDescription(modelData)
            userSkin: true
          }
        }
      }

      // Only when the theme ships a [bar-skin] to follow.
      ToggleRow {
        navKey: "followTheme"
        visible: root.screenTarget === "" && !!root.engine && root.engine.themeSkin !== null
        label: root.tr("label.followTheme", "Follow theme skin")
        hint: root.tr("label.followThemeHint", "")
        checked: root.engine ? root.engine.followTheme : true
        onToggled: if (root.engine) root.engine.setFollowTheme(!root.engine.followTheme)
      }
    }

    // ========================================================================
    // COLORS: fill, what to paint, the picker, tone
    // ========================================================================
    Column {
      width: parent.width
      spacing: Style.spacing.xxs
      visible: root.activeTab === "colors" && !!root.engine

      StandardHint {}

      ChoiceRow {
        navKey: "fill"
        label: root.tr("label.fill", "Fill")
        value: root.engine ? root.engine.fill : "solid"
        options: [
          { value: "solid", label: root.tr("fill.solid", "Solid") },
          { value: "gradient", label: root.tr("fill.gradient", "Gradient") }
        ]
        onPicked: function(v) {
          root.engine.updateField("fill", v)
          if (v === "gradient") root.colorTarget = "gradient"
          else if (root.colorTarget === "gradient") root.colorTarget = "surface"
        }
      }

      ChoiceRow {
        navKey: "colorTarget"
        label: root.tr("label.colorTarget", "Paint")
        value: root.colorTarget
        options: {
          var out = [
            { value: "surface", label: root.tr("colorTarget.surface", "Surface") },
            { value: "foreground", label: root.tr("colorTarget.foreground", "Icons") },
            { value: "accent", label: root.tr("colorTarget.accent", "Accent") }
          ]
          if (root.engine && root.engine.fill === "gradient") out.push({ value: "gradient", label: root.tr("colorTarget.gradient", "Blend") })
          return out
        }
        onPicked: function(v) { root.colorTarget = v }
      }

      NavItem {
        id: colorNav
        navKey: "color"
        width: parent.width
        implicitHeight: picker.implicitHeight + Style.spacing.md * 2
        height: implicitHeight
        onAdjust: function(direction) { picker.stepSwatch(direction) }
        onActivate: picker.pickerExpanded = !picker.pickerExpanded

        readonly property string field: root.colorTarget === "foreground" ? "customForeground"
          : (root.colorTarget === "accent" ? "customAccent"
            : (root.colorTarget === "gradient" ? "gradientTo" : "customBackground"))
        readonly property string value: !root.engine ? "" : (root.colorTarget === "foreground" ? root.engine.customForeground
          : (root.colorTarget === "accent" ? root.engine.customAccent
            : (root.colorTarget === "gradient" ? root.engine.gradientTo : root.engine.customBackground)))

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: colorNav.navFocused ? Style.hoverFillFor(root.fg, Kit.Color.accent) : "transparent"
        }

        ColorPickerField {
          id: picker
          x: Style.spacing.rowPaddingX
          y: Style.spacing.md
          width: parent.width - Style.spacing.rowPaddingX * 2
          strings: root.strings
          foreground: root.fg
          dimForeground: root.dimFg
          themePalette: root.engine ? root.engine.themePalette : []
          resetLabel: root.colorTarget === "foreground" || root.colorTarget === "gradient"
            ? root.tr("color.auto", "Auto") : root.tr("color.theme", "Theme")
          currentValue: colorNav.value
          resolvedColor: {
            if (!root.engine || colorNav.value === "") return fallbackColor
            root.engine.themeColors
            var hex = root.engine.resolveColorRef(colorNav.value)
            return hex !== "" ? Qt.color(hex) : fallbackColor
          }
          fallbackColor: {
            if (!root.engine) return Kit.Color.background
            if (root.colorTarget === "foreground") return root.engine.effectiveForeground
            if (root.colorTarget === "accent" || root.colorTarget === "gradient") return root.engine.resolvedAccent
            return root.engine.surfaceColor
          }
          onColorPicked: function(value) { root.engine.updateField(colorNav.field, value) }
        }
      }

      Section {
        title: root.tr("section.tone", "Tone")

        SliderRow {
          navKey: "surfaceTone"
          label: root.tr("label.surfaceTone", "Surface depth")
          valueText: root.percent(root.engine ? root.engine.surfaceTone : 1)
          minimum: 0.5
          maximum: 1.5
          step: 0.05
          integer: false
          value: root.engine ? root.engine.surfaceTone : 1
          onChangedValue: function(v) { root.engine.updateField("surfaceTone", v) }
        }

        SliderRow {
          navKey: "contrast"
          label: root.tr("label.contrast", "Text contrast")
          valueText: root.percent(root.engine ? root.engine.contrast : 1)
          minimum: 0.5
          maximum: 1.5
          step: 0.05
          integer: false
          value: root.engine ? root.engine.contrast : 1
          onChangedValue: function(v) { root.engine.updateField("contrast", v) }
        }
      }
    }

    // ========================================================================
    // GEOMETRY: architecture, size, gaps, width, corners, icons
    // ========================================================================
    Column {
      width: parent.width
      spacing: Style.spacing.xxs
      visible: root.activeTab === "geometry" && !!root.engine

      StandardHint {}

      ChoiceRow {
        navKey: "mode"
        label: root.tr("section.mode", "Architecture")
        value: root.engine ? root.engine.mode : "floating"
        options: [
          { value: "edge", label: root.tr("mode.edge", "Edge") },
          { value: "floating", label: root.tr("mode.floating", "Floating") },
          { value: "islands", label: root.tr("mode.islands", "Islands") }
        ]
        onPicked: function(v) { root.engine.updateField("mode", v) }
      }

      SliderRow {
        navKey: "height"
        label: root.tr("label.height", "Height")
        autoAvailable: true
        isAuto: !!root.engine && root.engine.look.heightAuto
        valueText: isAuto ? root.num(root.engine.look.barSizePx) + " px"
          : root.num(root.engine ? root.engine.skinHeight : 30) + " px"
        minimum: 22
        maximum: 48
        step: 1
        value: root.engine ? root.engine.skinHeight : 30
        onChangedValue: function(v) { root.engine.updateField("height", Math.round(v)) }
        onAutoToggled: root.engine.updateField("height", isAuto ? root.engine.skinHeight : "auto")
      }

      SliderRow {
        navKey: "edgeMargin"
        visible: !!root.engine && root.engine.mode !== "edge"
        label: root.tr("label.edgeMargin", "Edge gap")
        autoAvailable: true
        isAuto: !!root.engine && root.engine.look.edgeAuto
        valueText: isAuto ? root.num(root.engine.look.edgePx) + " px"
          : root.num(root.engine ? root.engine.edgeMargin : 6) + " px"
        minimum: 0
        maximum: 20
        step: 1
        value: root.engine ? root.engine.edgeMargin : 6
        onChangedValue: function(v) { root.engine.updateField("edgeMargin", Math.round(v)) }
        onAutoToggled: root.engine.updateField("edgeMargin", isAuto ? root.engine.edgeMargin : "auto")
      }

      SliderRow {
        navKey: "sideMargin"
        visible: !!root.engine && root.engine.mode !== "edge"
        label: root.tr("label.sideMargin", "Side margin")
        autoAvailable: true
        isAuto: !!root.engine && root.engine.look.sideAuto
        valueText: isAuto ? root.num(root.engine.look.sidePx) + " px"
          : root.num(root.engine ? root.engine.sideMargin : 10) + " px"
        minimum: 0
        maximum: 36
        step: 1
        value: root.engine ? root.engine.sideMargin : 10
        onChangedValue: function(v) { root.engine.updateField("sideMargin", Math.round(v)) }
        onAutoToggled: root.engine.updateField("sideMargin", isAuto ? root.engine.sideMargin : "auto")
      }

      SliderRow {
        navKey: "width"
        visible: !!root.engine && root.engine.mode !== "edge"
        label: root.tr("label.width", "Width")
        valueText: root.num(root.engine ? root.engine.look.widthPercent : 100) + "%"
        minimum: 30
        maximum: 100
        step: 5
        value: root.engine ? root.engine.look.widthPercent : 100
        onChangedValue: function(v) { root.engine.updateField("width", Math.round(v)) }
      }

      SliderRow {
        navKey: "radius"
        visible: !!root.engine && root.engine.mode !== "edge"
        label: root.tr("label.radius", "Corners")
        autoAvailable: true
        isAuto: !!root.engine && root.engine.look.radiusAuto
        valueText: isAuto ? root.num(root.engine.look.radiusPx) + " px"
          : root.num(root.engine ? root.engine.radius : 10) + " px"
        minimum: 0
        maximum: 24
        step: 1
        value: root.engine ? root.engine.radius : 10
        onChangedValue: function(v) { root.engine.updateField("radius", Math.round(v)) }
        onAutoToggled: root.engine.updateField("radius", isAuto ? root.engine.radius : "auto")
      }

      SliderRow {
        navKey: "iconScale"
        label: root.tr("label.iconScale", "Icon size")
        valueText: root.percent(root.engine ? root.engine.iconScale : 1)
        minimum: 0.8
        maximum: 1.5
        step: 0.05
        integer: false
        value: root.engine ? root.engine.iconScale : 1
        onChangedValue: function(v) { root.engine.updateField("iconScale", v) }
      }
    }

    // ========================================================================
    // SURFACE: opacity, border, widgets, shadow, blur, bezel, art
    // ========================================================================
    Column {
      width: parent.width
      spacing: Style.spacing.xxs
      visible: root.activeTab === "surface" && !!root.engine

      StandardHint {}

      SliderRow {
        navKey: "opacity"
        label: root.tr("label.opacity", "Opacity")
        autoAvailable: true
        isAuto: !!root.engine && root.engine.look.alphaAuto
        valueText: root.percent(root.engine ? root.engine.backgroundAlpha : 0.92)
        minimum: 0
        maximum: 1.0
        step: 0.02
        integer: false
        value: root.engine ? root.engine.backgroundAlpha : 0.92
        onChangedValue: function(v) { root.engine.updateField("backgroundAlpha", v) }
        onAutoToggled: root.engine.updateField("backgroundAlpha", isAuto ? root.engine.backgroundAlpha : "auto")
      }

      ChoiceRow {
        navKey: "border"
        label: root.tr("label.borderRole", "Border")
        value: root.engine ? root.engine.borderRole : "subtle"
        options: [
          { value: "none", label: root.tr("border.none", "None") },
          { value: "subtle", label: root.tr("border.subtle", "Subtle") },
          { value: "accent", label: root.tr("border.accent", "Accent") },
          { value: "hyprland", label: root.tr("border.hyprland", "Hyprland") }
        ]
        onPicked: function(v) {
          root.engine.updateField("border", v)
          if (v !== "none" && root.engine.borderWidth === 0) root.engine.updateField("borderWidth", 1)
        }
      }

      ChoiceRow {
        navKey: "widgetStyle"
        label: root.tr("label.widgetStyle", "Widgets")
        value: root.engine ? root.engine.widgetStyle : "plain"
        options: [
          { value: "plain", label: root.tr("widgetStyle.plain", "Plain") },
          { value: "pills", label: root.tr("widgetStyle.pills", "Pills") },
          { value: "chips", label: root.tr("widgetStyle.chips", "Chips") }
        ]
        onPicked: function(v) { root.engine.updateField("widgetStyle", v) }
      }

      ToggleRow {
        navKey: "shadow"
        label: root.tr("label.shadow", "Shadow")
        hint: root.tr("label.shadowHint", "")
        checked: root.engine ? root.engine.shadow : false
        onToggled: root.engine.updateField("shadow", !root.engine.shadow)
      }

      SliderRow {
        navKey: "shadowStrength"
        visible: !!root.engine && root.engine.shadow
        label: root.tr("label.shadowStrength", "Shadow depth")
        valueText: root.percent(root.engine ? root.engine.shadowStrength : 0.5)
        minimum: 0.1
        maximum: 1.0
        step: 0.05
        integer: false
        value: root.engine ? root.engine.shadowStrength : 0.5
        onChangedValue: function(v) { root.engine.updateField("shadowStrength", v) }
      }

      ToggleRow {
        navKey: "blur"
        label: root.tr("label.blur", "Glass blur")
        hint: root.tr("label.blurHint", "")
        checked: root.engine ? root.engine.blurActive : false
        onToggled: root.engine.setBlur(!root.engine.blurActive)
      }

      ChoiceRow {
        navKey: "bezel"
        label: root.tr("section.bezel", "Bezel")
        value: root.engine ? root.engine.bezel : "none"
        options: [
          { value: "none", label: root.tr("bezel.none", "Flat") },
          { value: "raised", label: root.tr("bezel.raised", "Raised") },
          { value: "inset", label: root.tr("bezel.inset", "Inset") },
          { value: "ridge", label: root.tr("bezel.ridge", "Ridge") },
          { value: "glass", label: root.tr("bezel.glass", "Glass") }
        ]
        onPicked: function(v) { root.engine.updateField("bezel", v) }
      }

      SliderRow {
        navKey: "bezelStrength"
        visible: !!root.engine && root.engine.bezel !== "none"
        label: root.tr("label.bezelStrength", "Bezel depth")
        valueText: root.percent(root.engine ? root.engine.bezelStrength : 0.75)
        minimum: 0.2
        maximum: 1.0
        step: 0.05
        integer: false
        value: root.engine ? root.engine.bezelStrength : 0.75
        onChangedValue: function(v) { root.engine.updateField("bezelStrength", v) }
      }

      ChoiceRow {
        navKey: "art"
        label: root.tr("section.art", "Craft Art")
        value: root.engine ? root.engine.art : "none"
        options: [
          { value: "none", label: root.tr("art.none", "Clean") },
          { value: "matrix", label: root.tr("art.matrix", "Matrix") },
          { value: "runeforge", label: root.tr("art.runeforge", "Runeforge") }
        ]
        onPicked: function(v) { root.engine.updateField("art", v) }
      }

      ToggleRow {
        navKey: "themeTint"
        visible: !!root.engine && root.engine.hasArt
        label: root.tr("label.themeTint", "Tint art with theme")
        hint: root.tr("label.themeTintHint", "")
        checked: root.engine ? root.engine.themeTint : false
        onToggled: root.engine.updateField("themeTint", !root.engine.themeTint)
      }
    }

    // ========================================================================
    // BEHAVIOR: auto-hide, and how Barcraft joins Omarchy
    // ========================================================================
    Column {
      width: parent.width
      spacing: Style.spacing.xxs
      visible: root.activeTab === "behavior" && !!root.engine

      StandardHint {}

      ToggleRow {
        navKey: "autoHide"
        label: root.tr("label.autoHide", "Auto-hide")
        hint: root.tr("label.autoHideHint", "")
        checked: root.engine ? root.engine.autoHide : false
        onToggled: root.engine.toggleAutoHide()
      }

      ChoiceRow {
        navKey: "autohideWhen"
        visible: !!root.engine && root.engine.autoHide
        label: root.tr("label.autohideWhen", "Hide")
        value: root.engine ? root.engine.prefs.autohideWhen : "always"
        options: [
          { value: "always", label: root.tr("autohideWhen.always", "Always") },
          { value: "windows", label: root.tr("autohideWhen.windows", "Only with windows") }
        ]
        onPicked: function(v) { root.engine.setPref("autohideWhen", v) }
      }

      SliderRow {
        navKey: "autohideDelay"
        visible: !!root.engine && root.engine.autoHide
        label: root.tr("label.autohideDelay", "Hide after")
        valueText: root.num(root.engine ? root.engine.prefs.autohideDelay : 320) + " ms"
        minimum: 100
        maximum: 2000
        step: 50
        value: root.engine ? root.engine.prefs.autohideDelay : 320
        onChangedValue: function(v) { root.engine.setPref("autohideDelay", Math.round(v)) }
      }

      ToggleRow {
        navKey: "revealOnWorkspace"
        visible: !!root.engine && root.engine.autoHide
        label: root.tr("label.revealOnWorkspace", "Peek on workspace switch")
        hint: root.tr("label.revealOnWorkspaceHint", "")
        checked: root.engine ? root.engine.prefs.revealOnWorkspace : false
        onToggled: root.engine.setPref("revealOnWorkspace", !root.engine.prefs.revealOnWorkspace)
      }

      Section {
        title: root.tr("section.omarchy", "Omarchy")

        ToggleRow {
          navKey: "omarchyMenu"
          label: root.tr("label.omarchyMenu", "Show in Omarchy menu")
          hint: root.tr("label.omarchyMenuHint", "")
          checked: root.engine ? root.engine.prefs.omarchyMenu : false
          onToggled: root.engine.setPref("omarchyMenu", !root.engine.prefs.omarchyMenu)
        }

        ToggleRow {
          navKey: "updateCheck"
          label: root.tr("label.updateCheck", "Check after Omarchy updates")
          hint: root.tr("label.updateCheckHint", "")
          checked: root.engine ? root.engine.prefs.updateCheck : false
          onToggled: root.engine.setPref("updateCheck", !root.engine.prefs.updateCheck)
        }
      }
    }
  }

  // ---- Footer: stays put under the editing tabs -------------------------------

  Column {
    id: footer
    width: parent.width
    spacing: Style.spacing.sm
    visible: root.craftTab && !!root.engine

    O.PanelSeparator {
      width: parent.width
      foreground: root.fg
    }

    RowLayout {
      width: parent.width
      spacing: Style.spacing.sm

      NavItem {
        id: nameNav
        navKey: "skinName"
        inFooter: true
        Layout.fillWidth: true
        implicitHeight: Style.spacing.controlHeight
        Layout.preferredHeight: implicitHeight
        onActivate: nameField.forceActiveFocus()
        onTextKey: function(t) {
          nameField.forceActiveFocus()
          nameField.insert(nameField.length, t)
        }

        // The kit's field chrome around a LineField (see LineField.qml).
        O.BorderSurface {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.fg, Kit.Color.accent)
          borderSpec: Border.controlSpec(nameField.activeFocus ? "focus" : (nameNav.navFocused || nameHover.hovered ? "hover-cursor" : "normal"), root.fg, Kit.Color.accent)

          HoverHandler {
            id: nameHover
            cursorShape: Qt.IBeamCursor
          }

          Item {
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            clip: true

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: nameField.text === ""
              textFormat: Text.PlainText
              text: root.tr("placeholder.skinName", "Save as skin name…")
              color: Kit.Color.textFaint
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            LineField {
              id: nameField
              anchors.verticalCenter: parent.verticalCenter
              color: root.fg
              selectionColor: Style.selectionFillFor(root.fg, Kit.Color.accent)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              maximumLength: 40
              takesPaste: true
              onPasteRequested: if (root.engine) root.engine.pasteInto(nameField)
              onKeyPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  event.accepted = true
                  root.saveSkin()
                  root.restoreKeys()
                } else if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.restoreKeys()
                }
              }
            }
          }
        }
      }

      ActionButton {
        navKey: "save"
        inFooter: true
        text: root.tr("action.save", "Save")
        selected: nameField.text.trim().length > 0
        onTriggered: root.saveSkin()
      }
    }

    RowLayout {
      width: parent.width
      spacing: Style.spacing.sm

      ActionButton {
        navKey: "copy"
        inFooter: true
        text: root.tr("action.copyToml", "Copy TOML")
        iconText: "󰆏"
        onTriggered: if (root.engine) root.engine.copyActiveToml()
      }

      ActionButton {
        navKey: "paste"
        inFooter: true
        text: root.tr("action.paste", "Paste skin")
        iconText: "󰆒"
        onTriggered: if (root.engine) root.engine.importFromClipboard()
      }

      Item { Layout.fillWidth: true }

      ActionButton {
        navKey: "reset"
        inFooter: true
        text: root.tr("action.reset", "Reset")
        iconText: "󰜉"
        onTriggered: if (root.engine) root.engine.resetToPreset()
      }
    }
  }

  Text {
    id: statusText
    visible: root.statusMessage !== ""
    textFormat: Text.PlainText
    text: root.statusMessage
    color: root.statusError ? Kit.Color.urgent : Kit.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    width: parent.width
  }

  // The keys, as key caps, while the keyboard drives.
  Flow {
    id: keysHint
    width: parent.width
    visible: root.keyboardMode && root.statusMessage === ""
    spacing: Style.spacing.md

    Repeater {
      model: [
        { keys: "Up+Down", label: root.tr("keys.move", "move") },
        { keys: "Left+Right", label: root.tr("keys.adjust", "adjust") },
        { keys: "Enter", label: root.tr("keys.pick", "pick") },
        { keys: "1-5", label: root.tr("keys.tabs", "tabs") },
        { keys: "R", label: root.tr("keys.rename", "rename") },
        { keys: "Delete", label: root.tr("keys.delete", "delete") }
      ]

      Row {
        required property var modelData
        spacing: Style.spacing.xxs

        O.KeyCombo {
          anchors.verticalCenter: parent.verticalCenter
          keys: modelData.keys
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: modelData.label
          color: root.dimFg
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ===========================================================================
  // Building blocks, from the kit
  // ===========================================================================

  // Anything the keyboard cursor can stop on. Rows react to the signals and
  // draw the cursor the kit's way (hasCursor).
  component NavItem: Item {
    id: navItem

    property string navKey: ""
    property bool navEnabled: true
    property bool inFooter: false
    // Left/Right move between tiles or footer controls.
    property bool navGrid: inFooter
    // A skin id to preview on the bar while the cursor rests here.
    property string navPreviewId: ""
    readonly property bool navFocused: root.keyboardMode && root.navCurrent === navItem

    signal adjust(int direction)
    signal activate()
    signal remove()
    signal textKey(string text)

    Component.onCompleted: root.registerNav(navItem)
    Component.onDestruction: root.unregisterNav(navItem)
  }

  // Shown on the editing tabs while Omarchy standard is on.
  component StandardHint: Text {
    width: parent ? parent.width : 0
    visible: !!root.engine && root.engine.standard
    bottomPadding: Style.spacing.sm
    textFormat: Text.PlainText
    color: Kit.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    text: root.tr("hint.standardCraft", "")
  }

  // A group inside a tab: the kit's section header, then its rows.
  component Section: Column {
    property string title: ""
    width: parent.width
    spacing: Style.spacing.xxs
    topPadding: Style.spacing.md

    O.PanelSectionHeader {
      visible: parent.title !== ""
      x: Style.spacing.rowPaddingX
      foreground: root.fg
      text: parent.title
    }
  }

  component HintText: Text {
    textFormat: Text.PlainText
    color: root.dimFg
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // A settings row with a pick-one control (kit SettingRow + ButtonGroup).
  component ChoiceRow: NavItem {
    id: choice
    property string label: ""
    property string value: ""
    property var options: []
    signal picked(string value)

    width: parent ? parent.width : 0
    implicitHeight: choiceRow.implicitHeight
    height: implicitHeight

    function indexOfValue() {
      for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
      return -1
    }

    onAdjust: function(direction) {
      if (options.length === 0) return
      var i = indexOfValue()
      var next = i < 0 ? 0 : Math.max(0, Math.min(options.length - 1, i + direction))
      if (next !== i) picked(options[next].value)
    }
    onActivate: {
      if (options.length === 0) return
      picked(options[(indexOfValue() + 1) % options.length].value)
    }

    O.SettingRow {
      id: choiceRow
      width: parent.width
      label: choice.label
      hasCursor: choice.navFocused
      foreground: root.fg

      O.ButtonGroup {
        focusable: false
        foreground: root.fg
        fontSize: Style.font.bodySmall
        value: choice.value
        options: choice.options
        cursorIndex: choice.navFocused ? choice.indexOfValue() : -1
        onChanged: function(v) { choice.picked(v) }
      }
    }
  }

  // A settings row with a slider: Auto (follow Omarchy), the slider, the value.
  component SliderRow: NavItem {
    id: sRow
    property string label: ""
    property string valueText: ""
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property bool integer: true
    property real value: 0
    property bool autoAvailable: false
    property bool isAuto: false
    signal changedValue(real v)
    signal autoToggled()

    width: parent ? parent.width : 0
    implicitHeight: sliderRow.implicitHeight
    height: implicitHeight
    onActivate: if (autoAvailable) autoToggled()

    onAdjust: function(direction) {
      var next = Math.max(minimum, Math.min(maximum, value + step * direction))
      if (integer) next = Math.round(next)
      else next = Math.round(next / step) * step
      if (Math.abs(next - value) > 0.0001) changedValue(next)
    }

    O.SettingRow {
      id: sliderRow
      width: parent.width
      label: sRow.label
      hasCursor: sRow.navFocused
      foreground: root.fg

      Row {
        spacing: Style.spacing.sm

        O.Button {
          visible: sRow.autoAvailable
          anchors.verticalCenter: parent.verticalCenter
          text: root.tr("label.auto", "Auto")
          fontSize: Style.font.caption
          bordered: true
          selected: sRow.isAuto
          tooltipText: root.tr("hint.auto", "")
          onClicked: sRow.autoToggled()
        }

        O.ValueSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(120)
          minimum: sRow.minimum
          maximum: sRow.maximum
          step: sRow.step
          integer: sRow.integer
          value: sRow.value
          onMoved: function(v) { sRow.changedValue(v) }
          onReleased: function(v) { sRow.changedValue(v) }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(42)
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: sRow.valueText
          color: sRow.isAuto ? Kit.Color.accent : root.dimFg
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }

  // A settings row with a switch; its explanation is a tooltip.
  component ToggleRow: NavItem {
    id: tRow
    property string label: ""
    property string hint: ""
    property bool checked: false
    signal toggled()

    width: parent ? parent.width : 0
    implicitHeight: toggleRow.implicitHeight
    height: implicitHeight
    onAdjust: function(direction) { if ((direction > 0) !== checked) toggled() }
    onActivate: toggled()

    HoverHandler { id: toggleHover }

    O.SettingRow {
      id: toggleRow
      width: parent.width
      label: tRow.label
      hasCursor: tRow.navFocused
      foreground: root.fg

      O.ToggleSwitch {
        checked: tRow.checked
        hasCursor: tRow.navFocused
        foreground: root.fg
        onToggled: tRow.toggled()
      }
    }

    O.PanelToolTip {
      visible: toggleHover.hovered && tRow.hint !== ""
      delay: 500
      text: tRow.hint
    }
  }

  component ActionButton: NavItem {
    id: action
    property string text: ""
    property string iconText: ""
    property bool selected: false
    signal triggered()

    implicitWidth: actionButton.implicitWidth
    implicitHeight: actionButton.implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    width: implicitWidth
    height: implicitHeight
    onActivate: triggered()

    O.Button {
      id: actionButton
      anchors.fill: parent
      text: action.text
      iconText: action.iconText
      selected: action.selected
      hasCursor: action.navFocused
      bordered: true
      onClicked: action.triggered()
    }
  }

  // A skin as a compact tile on the kit's cursor surface: its thumbnail and
  // name, the description a tooltip; hovering previews it on the bar.
  component SkinCard: NavItem {
    id: card
    property var skinData: null
    property string cardId: ""
    property string title: ""
    property string subtitle: ""
    property bool userSkin: false
    // The Omarchy tile: drawn as Omarchy's own bar.
    property bool standardTile: false
    readonly property bool chosen: root.chosenId() === cardId
    readonly property bool hot: cardHover.hovered || navFocused
    readonly property bool renaming: root.renamingId === cardId && userSkin
    readonly property bool confirmingDelete: root.confirmDeleteId === cardId

    navKey: "card:" + cardId
    navGrid: true
    navPreviewId: cardId
    height: Style.space(52)

    onActivate: root.pickSkin(cardId)
    onRemove: if (userSkin) root.requestDelete(cardId, title)
    onTextKey: function(t) { if (userSkin && (t === "r" || t === "R")) root.startRename(cardId) }

    HoverHandler {
      id: cardHover
      cursorShape: Qt.PointingHandCursor
      onHoveredChanged: root.hoverPreview(card.cardId, hovered)
    }

    O.CursorSurface {
      anchors.fill: parent
      hasCursor: card.hot
      current: card.chosen
      bordered: true
      foreground: root.fg
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      onClicked: {
        root.keyboardMode = false
        root.navCurrent = card
        root.pickSkin(card.cardId)
      }
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(6)
      spacing: Style.space(5)

      SkinThumbnail {
        width: parent.width
        height: Style.space(22)
        skin: card.skinData
        standard: card.standardTile
        paletteMap: root.palette
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(4)

        Text {
          visible: !card.renaming
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: card.title
          color: card.chosen ? Kit.Color.accent : root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          elide: Text.ElideRight
        }

        Item {
          visible: card.renaming
          Layout.fillWidth: true
          Layout.preferredHeight: renameLoader.item ? renameLoader.item.implicitHeight : 0
          clip: true

          Loader {
            id: renameLoader
            active: card.renaming
            width: parent.width
            sourceComponent: Component {
              Item {
                implicitHeight: renameField.implicitHeight

                LineField {
                  id: renameField
                  text: card.title
                  maximumLength: 40
                  takesPaste: true
                  color: root.fg
                  selectionColor: Style.selectionFillFor(root.fg, Kit.Color.accent)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  Component.onCompleted: {
                    forceActiveFocus()
                    selectAll()
                  }
                  onPasteRequested: if (root.engine) root.engine.pasteInto(renameField)
                  onActiveFocusChanged: if (!activeFocus) root.finishRename(card.cardId, text, false)
                  onKeyPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      event.accepted = true
                      root.finishRename(card.cardId, text, true)
                    } else if (event.key === Qt.Key_Escape) {
                      event.accepted = true
                      root.finishRename(card.cardId, text, false)
                    }
                  }
                }
              }
            }
          }
        }

        CardIcon {
          visible: card.userSkin && (card.hot || card.confirmingDelete) && !card.renaming
          glyph: "󰏫"
          tip: root.tr("card.rename", "Rename (R)")
          onTriggered: root.startRename(card.cardId)
        }

        CardIcon {
          visible: card.userSkin && (card.hot || card.confirmingDelete) && !card.renaming
          glyph: "󰆴"
          danger: card.confirmingDelete
          tip: root.tr("card.delete", "Delete (Del)")
          onTriggered: root.requestDelete(card.cardId, card.title)
        }
      }
    }

    O.PanelToolTip {
      visible: cardHover.hovered && card.subtitle !== "" && !card.renaming
      delay: 500
      text: card.subtitle
    }
  }

  component CardIcon: Text {
    id: icon
    property string glyph: ""
    property string tip: ""
    property bool danger: false
    signal triggered()

    textFormat: Text.PlainText
    text: glyph
    color: danger ? Kit.Color.urgent : (iconMouse.containsMouse ? Kit.Color.accent : root.dimFg)
    font.family: Style.font.family
    font.pixelSize: Style.font.body

    MouseArea {
      id: iconMouse
      anchors.fill: parent
      anchors.margins: -Style.space(3)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: icon.triggered()
    }

    O.PanelToolTip {
      visible: iconMouse.containsMouse && icon.tip !== ""
      text: icon.tip
    }
  }
}
