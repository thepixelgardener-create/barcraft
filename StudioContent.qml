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
  // The display an armed overwrite confirmation belongs to: confirming on a
  // different target must never force-overwrite with that target's skin.
  property string confirmOverwriteTarget: ""
  property string lastSaveName: ""
  property string lastSaveTarget: ""
  property string pendingPreview: ""

  SkinLook {
    id: targetLook
    skin: {
      if (!root.engine) return null
      root.engine.revision
      return root.engine.skinForScreen(root.screenTarget)
    }
    paletteMap: root.engine ? root.engine.themeColors : ({})
    barGlassy: root.engine ? root.engine.barGlassy : false
    standard: root.engine ? root.engine.standardFor(root.screenTarget) : false
    vertical: root.engine ? root.engine.vertical : false
  }

  function sharedLabel(text) {
    return root.screenTarget !== "" ? root.tr("label.sharedSuffix", "%1 (shared)").arg(text) : text
  }

  property bool keyboardMode: false
  property var navItems: []
  property Item navCurrent: null
  property point lastPointer: Qt.point(-1, -1)

  readonly property bool textEditing: (draftControls.visible && nameField.activeFocus) || renamingId !== ""
  readonly property color fg: Kit.Color.popups.text
  readonly property color dimFg: Kit.Color.textDim
  readonly property var screenNames: {
    var out = []
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) out.push(list[i].name)
    return out
  }
  function resetDisconnectedTarget() {
    // An empty list is a transient state while outputs reconfigure.
    if (screenNames.length === 0) return
    if (screenTarget !== "" && screenNames.indexOf(screenTarget) === -1) {
      screenTarget = ""
      confirmOverwriteName = ""
      confirmOverwriteTarget = ""
      pendingPreview = ""
      previewTimer.stop()
      if (engine) engine.clearPreview()
    }
  }
  onScreenNamesChanged: resetDisconnectedTarget()
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

  function formatNotice(tpl, arg) {
    var text = String(tpl || "")
    if (text.indexOf("%1") === -1) return text
    var val = String(arg === undefined || arg === null ? "" : arg)
    return text.replace("%1", function() { return val })
  }

  Connections {
    target: root.engine
    function onNotice(key, arg, isError) {
      // Arm the confirmation only while Studio still edits the target that
      // save came from.
      if (key === "status.saveChangedExternally" && root.lastSaveName !== ""
          && root.lastSaveTarget === root.screenTarget) {
        root.confirmOverwriteName = root.lastSaveName
        root.confirmOverwriteTarget = root.lastSaveTarget
        overwriteTimer.restart()
      }
      root.showStatus(root.formatNotice(root.tr(key), arg), isError)
    }
    function onSkinRenamed(oldId, newId) {
      if (!newId) return
      root.restoreKey = "card:" + newId
      for (var i = 0; i < root.navItems.length; i++) {
        if (root.navItems[i].navKey === root.restoreKey) {
          root.navCurrent = root.navItems[i]
          root.restoreKey = ""
          break
        }
      }
    }
  }

  onPanelOpenChanged: {
    if (panelOpen) {
      resetDisconnectedTarget()
      return
    }
    keyboardMode = false
    if (nameField.activeFocus) nameField.focus = false
    renamingId = ""
    confirmDeleteId = ""
    confirmOverwriteName = ""
    confirmOverwriteTarget = ""
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
  readonly property bool hasUnsavedDraft: !!root.engine && (root.engine.revision,
    root.engine.hasDraftFor(root.screenTarget) || root.engine.canUndoPasteFor(root.screenTarget))
  readonly property bool hasMainUnsavedDraft: !!root.engine && (root.engine.revision,
    root.engine.hasDraftFor("") || root.engine.canUndoPasteFor(""))
  readonly property bool hasOtherMainDraft: root.screenTarget !== "" && !root.hasUnsavedDraft && root.hasMainUnsavedDraft
  readonly property bool canUndoPasteHere: !!root.engine && (root.engine.revision,
    root.engine.canUndoPasteFor(root.screenTarget))
  readonly property bool mainCanUndoPaste: !!root.engine && (root.engine.revision,
    root.engine.canUndoPasteFor(""))
  readonly property var themeSkinErrors: root.engine && root.engine.themeSkinInspection
    && root.engine.themeSkinInspection.errors ? root.engine.themeSkinInspection.errors : []
  readonly property int themeSkinErrorCount: root.engine && root.engine.themeSkinInspection
    ? Math.max(themeSkinErrors.length, Number(root.engine.themeSkinInspection.errorCount) || 0) : 0

  function selectScreenTarget(target) {
    root.screenTarget = target
    root.confirmOverwriteName = ""
    root.confirmOverwriteTarget = ""
    root.pendingPreview = ""
    previewTimer.restart()
  }

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

  function pickSkin(id, isUser) {
    if (!engine) return
    pendingPreview = ""
    previewTimer.stop()
    if (!isUser && id === "standard") {
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
    if (commit && engine) engine.renameUserSkin(id, text)
    restoreKeys()
  }

  Timer {
    id: overwriteTimer
    interval: 4000
    repeat: false
    onTriggered: {
      root.confirmOverwriteName = ""
      root.confirmOverwriteTarget = ""
    }
  }

  function saveSkin() {
    if (!engine) return
    var current = engine.committedSkinFor(screenTarget)
    var wanted = nameField.text || (current ? current.name : "")
    var confirmed = confirmOverwriteName !== "" && confirmOverwriteName === wanted
      && confirmOverwriteTarget === screenTarget
    lastSaveName = wanted
    lastSaveTarget = screenTarget
    var res = engine.saveUserSkin(wanted, confirmed, screenTarget)
    if (res && res.needsConfirm) {
      confirmOverwriteName = wanted
      confirmOverwriteTarget = screenTarget
      overwriteTimer.restart()
      showStatus(formatNotice(tr("status.confirmOverwrite"), res.conflictName), true)
      return
    }
    confirmOverwriteName = ""
    confirmOverwriteTarget = ""
    overwriteTimer.stop()
    nameField.text = ""
    if (nameField.activeFocus) {
      nameField.focus = false
      restoreKeys()
    }
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
        : item.inHeader ? 0 : scroll.contentY
      out.push({ item: item, x: p.x, y: p.y + offset })
    }
    out.sort(function(a, b) { return Math.abs(a.y - b.y) > 6 ? a.y - b.y : a.x - b.x })
    return out
  }

  function setCurrent(item) {
    navCurrent = item
    if (!item) return
    if (!item.inHeader && !item.inFooter) body.ensureVisible(item)
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
    if (navCurrent && navCurrent.visible && navCurrent.navEnabled) navCurrent.activate()
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
      var target = root.screenTarget
      var skin = root.engine.committedSkinFor(target)
      var name = skin ? skin.name : ""
      var label = ""
      if (target === "" && root.engine.usingThemeSkin) label = root.tr("meta.theme").arg(name)
      else if (root.engine.hasDraftFor(target)) label = root.tr("meta.custom").arg(name)
      else label = root.tr("meta.preset").arg(name)
      return target !== "" ? root.tr("meta.screen", "%1 · %2").arg(target).arg(label) : label
    }
    iconComponent: Component {
      BarcraftMark {
        width: Math.round(Style.font.display * 1.3)
        height: Math.round(width * 0.6)
        ink: root.fg
      }
    }
    trailingControl: Component {
      Row {
        spacing: Style.spacing.xs
        visible: !!root.engine

        ActionButton {
          navKey: "copyHero"
          inHeader: true
          navGrid: true
          readonly property bool isStandard: !!root.engine && (root.engine.revision, root.engine.standardFor(root.screenTarget))
          disabled: isStandard
          text: root.tr("action.copy", "Copy")
          iconText: "󰆏"
          tooltipText: isStandard
            ? root.tr("tooltip.copyStandard", "Switch off Omarchy standard to copy a skin")
            : root.tr("tooltip.copyToml", "Copy the active skin as [bar-skin] TOML")
          onTriggered: if (root.engine) root.engine.copyToml(root.screenTarget)
        }

        ActionButton {
          navKey: "pasteHero"
          inHeader: true
          navGrid: true
          text: root.tr("action.pasteShort", "Paste")
          iconText: "󰆒"
          tooltipText: root.tr("tooltip.pasteSkin", "Paste a [bar-skin] TOML snippet from the clipboard")
          onTriggered: if (root.engine) root.engine.importFromClipboard(root.screenTarget)
        }
      }
    }
  }

  NavItem {
    id: tabRow
    navKey: "tabs"
    inHeader: true
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

  // Target selector pinned across all five tabs when multiple monitors exist.
  Column {
    id: targetBar
    width: parent.width
    spacing: Style.spacing.xs
    visible: (root.screenNames.length > 1 || root.screenTarget !== "") && !!root.engine

    ChoiceRow {
      navKey: "screens"
      inHeader: true
      label: root.tr("label.editing", "Editing")
      value: root.screenTarget === "" ? "*main*" : root.screenTarget
      options: {
        var out = [{ value: "*main*", label: root.tr("screens.main", "Main skin") }]
        for (var i = 0; i < root.screenNames.length; i++) out.push({ value: root.screenNames[i], label: root.screenNames[i] })
        return out
      }
      onPicked: function(v) {
        root.selectScreenTarget(v === "*main*" ? "" : v)
      }
    }

    RowLayout {
      width: parent.width
      visible: root.screenTarget !== ""
      spacing: Style.spacing.md

      HintText {
        Layout.fillWidth: true
        text: root.tr("hint.screenSkin", "").arg(root.screenTarget)
      }

      ActionButton {
        navKey: "useMain"
        inHeader: true
        visible: !!root.engine && (root.engine.revision, root.engine.hasMonitorSkin(root.screenTarget))
        text: root.tr("action.useMain", "Use main skin")
        onTriggered: if (root.engine) root.engine.selectForScreen(root.screenTarget, "")
      }
    }
  }

  // ---- Body (scrolls) -------------------------------------------------------

  O.ScrollArea {
    id: body
    readonly property real chrome: hero.height + tabRow.height
      + (targetBar.visible ? targetBar.implicitHeight + root.spacing : 0)
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

      // Every skin in one grid: Omarchy's own bar first (the way back, a
      // click again leaves it), the theme's skin, the presets.
      Grid {
        width: parent.width
        columns: 4
        columnSpacing: Style.spacing.sm
        rowSpacing: Style.spacing.sm

        StudioSkinCard {
          studio: root
          visible: root.screenTarget === ""
          width: root.cardWidth
          cardId: "standard"
          standardTile: true
          title: root.tr("tile.standard", "Omarchy")
          subtitle: root.tr("label.standardHint", "")
        }

        StudioSkinCard {
          studio: root
          visible: !!root.engine && root.engine.themeSkin !== null
          width: root.cardWidth
          cardId: "theme"
          skinData: root.engine ? root.engine.themeSkin : null
          title: root.tr("card.theme", "Theme skin")
          subtitle: root.engine && root.engine.themeSkin ? root.engine.themeSkin.name : ""
        }

        Repeater {
          model: root.engine ? root.engine.builtinSkins : []

          StudioSkinCard {
            required property var modelData
            studio: root
            width: root.cardWidth
            cardId: modelData.id
            skinData: modelData
            title: modelData.name
            subtitle: root.skinDescription(modelData)
          }
        }
      }

      // One-line diagnostic hint when the active theme ships a [bar-skin] with
      // errors — visible even if the error prevented the theme skin from loading.
      Item {
        id: themeErrorHint
        visible: root.screenTarget === "" && root.themeSkinErrors.length > 0
        width: parent.width
        implicitHeight: themeErrorText.implicitHeight
        height: implicitHeight

        HoverHandler { id: themeErrorHover }

        Text {
          id: themeErrorText
          width: parent.width
          textFormat: Text.PlainText
          text: {
            var errs = root.themeSkinErrors
            if (errs.length === 0) return ""
            var first = errs[0].message || ""
            var total = Math.max(errs.length, root.themeSkinErrorCount)
            // %2 first: the message itself may contain "%2".
            return total > 1
              ? root.formatNotice(root.tr("hint.themeSkinErrorMore", "Theme [bar-skin]: %1 (+%2 more)")
                  .replace("%2", function() { return String(total - 1) }), first)
              : root.formatNotice(root.tr("hint.themeSkinError", "Theme [bar-skin]: %1"), first)
          }
          color: Kit.Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        O.PanelToolTip {
          visible: themeErrorHover.hovered && root.themeSkinErrors.length > 0
          delay: 300
          text: root.themeSkinErrors.map(function(e) { return e.message }).join("\n")
        }
      }

      // Saved skins (~/.config/omarchy/bar/skins/*.toml)
      O.PanelSectionHeader {
        visible: !!root.engine && root.engine.userSkins.length > 0
        width: parent.width
        foreground: root.fg
        text: root.tr("section.user", "Your skins")
      }

      Grid {
        width: parent.width
        columns: 4
        columnSpacing: Style.spacing.sm
        rowSpacing: Style.spacing.sm
        visible: !!root.engine && root.engine.userSkins.length > 0

        Repeater {
          model: root.engine ? root.engine.userSkins : []

          StudioSkinCard {
            required property var modelData
            studio: root
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
        value: targetLook.fill
        options: [
          { value: "solid", label: root.tr("fill.solid", "Solid") },
          { value: "gradient", label: root.tr("fill.gradient", "Gradient") }
        ]
        onPicked: function(v) {
          root.engine.updateField("fill", v, root.screenTarget)
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
          if (targetLook.fill === "gradient") out.push({ value: "gradient", label: root.tr("colorTarget.gradient", "Blend") })
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
        readonly property string value: root.colorTarget === "foreground" ? targetLook.customForeground
          : (root.colorTarget === "accent" ? targetLook.customAccent
            : (root.colorTarget === "gradient" ? targetLook.gradientTo : targetLook.customBackground))

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
            var hex = targetLook.resolveRef(colorNav.value)
            return hex !== "" ? Qt.color(hex) : fallbackColor
          }
          fallbackColor: {
            if (!root.engine) return Kit.Color.background
            if (root.colorTarget === "foreground") return targetLook.effectiveForeground
            if (root.colorTarget === "accent" || root.colorTarget === "gradient") return targetLook.resolvedAccent
            return targetLook.surfaceColor
          }
          onColorPicked: function(value) { root.engine.updateField(colorNav.field, value, root.screenTarget) }
        }
      }

      Section {
        title: root.tr("section.tone", "Tone")

        SliderRow {
          navKey: "surfaceTone"
          label: root.tr("label.surfaceTone", "Surface depth")
          valueText: root.percent(targetLook.surfaceTone)
          minimum: 0.5
          maximum: 1.5
          step: 0.05
          integer: false
          value: targetLook.surfaceTone
          onChangedValue: function(v) { root.engine.updateField("surfaceTone", v, root.screenTarget) }
        }

        SliderRow {
          navKey: "contrast"
          label: root.tr("label.contrast", "Text contrast")
          valueText: root.percent(targetLook.contrast)
          minimum: 0.5
          maximum: 1.5
          step: 0.05
          integer: false
          value: targetLook.contrast
          onChangedValue: function(v) { root.engine.updateField("contrast", v, root.screenTarget) }
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
        value: targetLook.mode
        options: [
          { value: "edge", label: root.tr("mode.edge", "Edge") },
          { value: "floating", label: root.tr("mode.floating", "Floating") },
          { value: "islands", label: root.tr("mode.islands", "Islands") }
        ]
        onPicked: function(v) { root.engine.updateField("mode", v, root.screenTarget) }
      }

      SliderRow {
        navKey: "height"
        label: root.tr("label.height", "Height")
        autoAvailable: true
        isAuto: targetLook.heightAuto
        valueText: isAuto ? root.num(targetLook.barSizePx) + " px"
          : root.num(targetLook.skinHeight) + " px"
        minimum: 22
        maximum: 56
        step: 1
        value: targetLook.skinHeight
        onChangedValue: function(v) { root.engine.updateField("height", Math.round(v), root.screenTarget) }
        onAutoToggled: root.engine.updateField("height", isAuto ? targetLook.skinHeight : "auto", root.screenTarget)
      }

      SliderRow {
        navKey: "edgeMargin"
        visible: targetLook.mode !== "edge"
        label: root.tr("label.edgeMargin", "Edge gap")
        autoAvailable: true
        isAuto: targetLook.edgeAuto
        valueText: isAuto ? root.num(targetLook.edgePx) + " px"
          : root.num(targetLook.edgeMargin) + " px"
        minimum: 0
        maximum: 24
        step: 1
        value: targetLook.edgeMargin
        onChangedValue: function(v) { root.engine.updateField("edgeMargin", Math.round(v), root.screenTarget) }
        onAutoToggled: root.engine.updateField("edgeMargin", isAuto ? targetLook.edgeMargin : "auto", root.screenTarget)
      }

      SliderRow {
        navKey: "sideMargin"
        visible: targetLook.mode !== "edge"
        label: root.tr("label.sideMargin", "Side margin")
        autoAvailable: true
        isAuto: targetLook.sideAuto
        valueText: isAuto ? root.num(targetLook.sidePx) + " px"
          : root.num(targetLook.sideMargin) + " px"
        minimum: 0
        maximum: 48
        step: 1
        value: targetLook.sideMargin
        onChangedValue: function(v) { root.engine.updateField("sideMargin", Math.round(v), root.screenTarget) }
        onAutoToggled: root.engine.updateField("sideMargin", isAuto ? targetLook.sideMargin : "auto", root.screenTarget)
      }

      SliderRow {
        navKey: "width"
        visible: targetLook.mode !== "edge"
        label: root.tr("label.width", "Width")
        valueText: root.num(targetLook.widthPercent) + "%"
        minimum: 30
        maximum: 100
        step: 5
        value: targetLook.widthPercent
        onChangedValue: function(v) { root.engine.updateField("width", Math.round(v), root.screenTarget) }
      }

      SliderRow {
        navKey: "radius"
        visible: targetLook.mode !== "edge"
        label: root.tr("label.radius", "Corners")
        autoAvailable: true
        isAuto: targetLook.radiusAuto
        valueText: isAuto ? root.num(targetLook.radiusPx) + " px"
          : root.num(targetLook.radius) + " px"
        minimum: 0
        maximum: 28
        step: 1
        value: targetLook.radius
        onChangedValue: function(v) { root.engine.updateField("radius", Math.round(v), root.screenTarget) }
        onAutoToggled: root.engine.updateField("radius", isAuto ? targetLook.radius : "auto", root.screenTarget)
      }

      SliderRow {
        navKey: "iconScale"
        label: root.sharedLabel(root.tr("label.iconScale", "Icon size"))
        valueText: root.percent(root.engine ? root.engine.look.iconScale : 1)
        minimum: 0.8
        maximum: 1.5
        step: 0.05
        integer: false
        value: root.engine ? root.engine.look.iconScale : 1
        onChangedValue: function(v) { root.engine.setSharedIconScale(v) }
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
        isAuto: targetLook.alphaAuto
        valueText: root.percent(targetLook.backgroundAlpha)
        minimum: 0
        maximum: 1.0
        step: 0.02
        integer: false
        value: targetLook.backgroundAlpha
        onChangedValue: function(v) { root.engine.updateField("backgroundAlpha", v, root.screenTarget) }
        onAutoToggled: root.engine.updateField("backgroundAlpha", isAuto ? targetLook.backgroundAlpha : "auto", root.screenTarget)
      }

      ChoiceRow {
        navKey: "border"
        label: root.tr("label.borderRole", "Border")
        value: targetLook.borderRole
        options: [
          { value: "none", label: root.tr("border.none", "None") },
          { value: "subtle", label: root.tr("border.subtle", "Subtle") },
          { value: "accent", label: root.tr("border.accent", "Accent") },
          { value: "hyprland", label: root.tr("border.hyprland", "Hyprland") }
        ]
        onPicked: function(v) {
          root.engine.updateField("border", v, root.screenTarget)
          if (v !== "none" && targetLook.borderWidth === 0) root.engine.updateField("borderWidth", 1, root.screenTarget)
        }
      }

      ChoiceRow {
        navKey: "widgetStyle"
        label: root.tr("label.widgetStyle", "Widgets")
        value: targetLook.widgetStyle
        options: [
          { value: "plain", label: root.tr("widgetStyle.plain", "Plain") },
          { value: "pills", label: root.tr("widgetStyle.pills", "Pills") },
          { value: "chips", label: root.tr("widgetStyle.chips", "Chips") }
        ]
        onPicked: function(v) { root.engine.updateField("widgetStyle", v, root.screenTarget) }
      }

      ToggleRow {
        navKey: "shadow"
        label: root.tr("label.shadow", "Shadow")
        hint: root.tr("label.shadowHint", "")
        checked: targetLook.shadow
        onToggled: root.engine.updateField("shadow", !targetLook.shadow, root.screenTarget)
      }

      SliderRow {
        navKey: "shadowStrength"
        visible: targetLook.shadow
        label: root.tr("label.shadowStrength", "Shadow depth")
        valueText: root.percent(targetLook.shadowStrength)
        minimum: 0.1
        maximum: 1.0
        step: 0.05
        integer: false
        value: targetLook.shadowStrength
        onChangedValue: function(v) { root.engine.updateField("shadowStrength", v, root.screenTarget) }
      }

      ToggleRow {
        navKey: "blur"
        label: root.sharedLabel(root.tr("label.blur", "Glass blur"))
        hint: root.tr("label.blurHint", "")
        checked: root.engine ? root.engine.blurActive : false
        onToggled: root.engine.setBlur(!root.engine.blurActive)
      }

      ChoiceRow {
        navKey: "bezel"
        label: root.tr("section.bezel", "Bezel")
        value: targetLook.bezel
        options: [
          { value: "none", label: root.tr("bezel.none", "Flat") },
          { value: "raised", label: root.tr("bezel.raised", "Raised") },
          { value: "inset", label: root.tr("bezel.inset", "Inset") },
          { value: "ridge", label: root.tr("bezel.ridge", "Ridge") },
          { value: "glass", label: root.tr("bezel.glass", "Glass") }
        ]
        onPicked: function(v) { root.engine.updateField("bezel", v, root.screenTarget) }
      }

      SliderRow {
        navKey: "bezelStrength"
        visible: targetLook.bezel !== "none"
        label: root.tr("label.bezelStrength", "Bezel depth")
        valueText: root.percent(targetLook.bezelStrength)
        minimum: 0.15
        maximum: 1.0
        step: 0.05
        integer: false
        value: targetLook.bezelStrength
        onChangedValue: function(v) { root.engine.updateField("bezelStrength", v, root.screenTarget) }
      }

      ChoiceRow {
        navKey: "art"
        label: root.tr("section.art", "Craft Art")
        value: targetLook.art
        options: [
          { value: "none", label: root.tr("art.none", "Clean") },
          { value: "matrix", label: root.tr("art.matrix", "Matrix") },
          { value: "runeforge", label: root.tr("art.runeforge", "Runeforge") },
          { value: "amiga", label: root.tr("art.amiga", "Amiga") }
        ]
        onPicked: function(v) { root.engine.updateField("art", v, root.screenTarget) }
      }

      ToggleRow {
        navKey: "themeTint"
        visible: targetLook.hasArt
        label: root.tr("label.themeTint", "Tint art with theme")
        hint: root.tr("label.themeTintHint", "")
        checked: targetLook.themeTint
        onToggled: root.engine.updateField("themeTint", !targetLook.themeTint, root.screenTarget)
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
        checked: targetLook.autoHide
        onToggled: root.engine.toggleAutoHide(root.screenTarget)
      }

      ChoiceRow {
        navKey: "autohideWhen"
        visible: targetLook.autoHide
        label: root.sharedLabel(root.tr("label.autohideWhen", "Hide"))
        value: root.engine ? root.engine.prefs.autohideWhen : "always"
        options: [
          { value: "always", label: root.tr("autohideWhen.always", "Always") },
          { value: "windows", label: root.tr("autohideWhen.windows", "Only with windows") }
        ]
        onPicked: function(v) { root.engine.setPref("autohideWhen", v) }
      }

      SliderRow {
        navKey: "autohideDelay"
        visible: targetLook.autoHide
        label: root.sharedLabel(root.tr("label.autohideDelay", "Hide after"))
        valueText: root.num(root.engine ? root.engine.prefs.autohideDelay : 320) + " ms"
        minimum: 100
        maximum: 3000
        step: 50
        value: root.engine ? root.engine.prefs.autohideDelay : 320
        onChangedValue: function(v) { root.engine.setPref("autohideDelay", Math.round(v)) }
      }

      ToggleRow {
        navKey: "revealOnWorkspace"
        visible: targetLook.autoHide
        label: root.sharedLabel(root.tr("label.revealOnWorkspace", "Peek on workspace switch"))
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

      Section {
        title: root.tr("section.about", "About")

        RowLayout {
          width: parent.width - Style.spacing.rowPaddingX * 2
          x: Style.spacing.rowPaddingX
          spacing: Style.spacing.sm

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.tr("about.meta", "Barcraft %1 · %2 · %3")
              .arg(root.engine && root.engine.pluginVersion ? root.engine.pluginVersion : "")
              .arg(root.engine ? root.engine.pluginLicense : "MIT")
              .arg(root.engine ? root.engine.pluginAuthor : "frueh")
            color: root.dimFg
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            visible: !!root.engine && root.engine.updateState !== "idle"
            textFormat: Text.PlainText
            text: {
              if (!root.engine) return ""
              var st = root.engine.updateState
              if (st === "checking") return root.tr("about.checking", "Checking…")
              if (st === "uptodate") return root.tr("about.upToDate", "Up to date")
              if (st === "available") return root.formatNotice(root.tr("about.updateAvailable", "v%1 available"), root.engine.remoteVersion)
              if (st === "ahead") return root.formatNotice(root.tr("about.ahead", "Ahead of main (%1)"), root.engine.remoteVersion)
              if (st === "error") return root.tr("about.checkFailed", "Check failed")
              return ""
            }
            color: root.engine && root.engine.updateState === "error" ? Kit.Color.urgent
              : (root.engine && root.engine.updateState === "available" ? Kit.Color.accent : root.dimFg)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: !!root.engine && root.engine.updateState === "available"
          }
        }

        Flow {
          width: parent.width - Style.spacing.rowPaddingX * 2
          x: Style.spacing.rowPaddingX
          topPadding: Style.spacing.xs
          spacing: Style.spacing.sm

          ActionButton {
            navKey: "updateAction"
            navGrid: true
            readonly property bool updateReady: !!root.engine && root.engine.updateState === "available"
            text: updateReady
              ? root.tr("action.updateNow", "Update")
              : (root.engine && root.engine.updateState === "checking"
                ? root.tr("about.checking", "Checking…")
                : root.tr("action.checkUpdates", "Check updates"))
            iconText: updateReady ? "󰇚" : "󰚰"
            selected: updateReady
            onTriggered: {
              if (!root.engine) return
              if (updateReady) root.engine.requestPluginUpdate()
              else root.engine.checkForUpdates()
            }
          }

          ActionButton {
            navKey: "shareSkins"
            navGrid: true
            text: root.tr("action.shareSkins", "Share skins")
            iconText: "󰌹"
            onTriggered: if (root.engine) root.engine.openShareSkins()
          }

          ActionButton {
            navKey: "openGithub"
            navGrid: true
            text: root.tr("action.github", "GitHub")
            iconText: "󰊤"
            onTriggered: if (root.engine) root.engine.openRepository()
          }

          ActionButton {
            navKey: "openIssues"
            navGrid: true
            text: root.tr("action.issues", "Issues")
            iconText: "󰗖"
            onTriggered: if (root.engine) root.engine.openIssues()
          }
        }
      }
    }
  }

  // ---- Contextual Draft Bar: appears on any tab while unsaved edits or a
  // pasted skin are active, so trying a skin and saving or undoing happen in
  // one place without cluttering clean tabs.

  Column {
    id: footer
    width: parent.width
    spacing: Style.spacing.sm
    visible: root.hasUnsavedDraft || root.hasOtherMainDraft

    O.PanelSeparator {
      width: parent.width
      foreground: root.fg
    }

    Column {
      id: draftControls
      width: parent.width
      spacing: Style.spacing.sm
      visible: root.hasUnsavedDraft
      onVisibleChanged: {
        if (!visible && nameField.activeFocus) {
          nameField.focus = false
          root.restoreKeys()
        }
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
          selected: nameField.text.trim().length > 0 || root.canUndoPasteHere
          onTriggered: root.saveSkin()
        }
      }

      RowLayout {
        width: parent.width
        spacing: Style.spacing.sm

        HintText {
          Layout.fillWidth: true
          text: root.canUndoPasteHere
            ? root.tr("hint.pastedDraft", "Pasted skin — save to keep it, or undo to go back")
            : root.tr("hint.editedDraft", "Unsaved edits — save as a skin, or reset")
        }

        ActionButton {
          navKey: "undoPaste"
          inFooter: true
          visible: root.canUndoPasteHere
          text: root.tr("action.undoPaste", "Undo paste")
          iconText: "󰕌"
          onTriggered: {
            if (nameField.activeFocus) {
              nameField.focus = false
              root.restoreKeys()
            }
            if (root.engine) root.engine.undoPaste(root.screenTarget)
          }
        }

        ActionButton {
          navKey: "reset"
          inFooter: true
          visible: !root.canUndoPasteHere
          text: root.tr("action.reset", "Reset")
          iconText: "󰜉"
          onTriggered: {
            if (nameField.activeFocus) {
              nameField.focus = false
              root.restoreKeys()
            }
            if (root.engine) root.engine.resetTarget(root.screenTarget)
          }
        }
      }
    }

    // Shown while editing a clean monitor when shared edits (Icon size, Glass
    // blur) or earlier changes left an unsaved draft on the Main skin.
    RowLayout {
      id: mainDraftNotice
      width: parent.width
      spacing: Style.spacing.sm
      visible: root.hasOtherMainDraft

      HintText {
        Layout.fillWidth: true
        text: root.tr("hint.mainDraftPending", "Main skin has unsaved edits")
      }

      ActionButton {
        navKey: "editMainDraft"
        inFooter: true
        text: root.tr("action.editMain", "Edit main")
        onTriggered: root.selectScreenTarget("")
      }

      ActionButton {
        navKey: "resetMainDraft"
        inFooter: true
        text: root.mainCanUndoPaste
          ? root.tr("action.undoPaste", "Undo paste")
          : root.tr("action.reset", "Reset")
        iconText: root.mainCanUndoPaste ? "󰕌" : "󰜉"
        onTriggered: {
          if (!root.engine) return
          if (root.mainCanUndoPaste) root.engine.undoPaste("")
          else root.engine.resetTarget("")
        }
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
    maximumLineCount: 3
    elide: Text.ElideRight
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
    property bool inHeader: false
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
    property string tooltipText: ""
    property bool selected: false
    property bool disabled: false
    signal triggered()

    navEnabled: !disabled
    implicitWidth: actionButton.implicitWidth
    implicitHeight: actionButton.implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    width: implicitWidth
    height: implicitHeight
    onActivate: if (!disabled) triggered()

    O.Button {
      id: actionButton
      anchors.fill: parent
      opacity: action.disabled ? 0.45 : 1
      text: action.text
      iconText: action.iconText
      tooltipText: action.disabled ? "" : action.tooltipText
      selected: !action.disabled && action.selected
      hasCursor: !action.disabled && action.navFocused
      bordered: true
      onClicked: if (!action.disabled) action.triggered()
    }

    MouseArea {
      id: disabledShield
      anchors.fill: parent
      visible: action.disabled
      hoverEnabled: true
      cursorShape: Qt.ArrowCursor
    }

    O.PanelToolTip {
      visible: action.disabled && disabledShield.containsMouse && action.tooltipText !== ""
      delay: 300
      text: action.tooltipText
    }
  }
}
