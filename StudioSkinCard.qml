import QtQuick
import QtQuick.Layouts
import "kit/Theme"
import "kit/Theme" as Kit
import "kit/Ui" as O

// A skin as a compact tile on the kit's cursor surface: its thumbnail and
// name, the description a tooltip; hovering or moving the keyboard cursor
// previews it live on the bar.
Item {
  id: card

  required property var studio
  property var skinData: null
  property string cardId: ""
  property string title: ""
  property string subtitle: ""
  property bool userSkin: false
  // The Omarchy tile: drawn as Omarchy's own bar.
  property bool standardTile: false

  // NavItem contract consumed by StudioContent's keyboard navigator.
  property string navKey: "card:" + cardId
  property bool navEnabled: true
  property bool inHeader: false
  property bool inFooter: false
  property bool navGrid: true
  property string navPreviewId: cardId
  readonly property bool navFocused: !!studio && studio.keyboardMode && studio.navCurrent === card

  readonly property bool chosen: !!studio && studio.chosenId() === cardId
  readonly property bool hot: cardHover.hovered || navFocused
  readonly property bool renaming: !!studio && studio.renamingId === cardId && userSkin
  readonly property bool confirmingDelete: !!studio && studio.confirmDeleteId === cardId

  signal adjust(int direction)
  signal activate()
  signal remove()
  signal textKey(string text)

  height: Style.space(52)

  Component.onCompleted: if (studio) studio.registerNav(card)
  Component.onDestruction: {
    if (!studio) return
    if (studio.renamingId === cardId) studio.finishRename(cardId, "", false)
    studio.unregisterNav(card)
  }

  onActivate: if (studio) studio.pickSkin(cardId, userSkin)
  onRemove: if (studio && userSkin) studio.requestDelete(cardId, title)
  onTextKey: function(t) { if (studio && userSkin && (t === "r" || t === "R")) studio.startRename(cardId) }

  HoverHandler {
    id: cardHover
    cursorShape: Qt.PointingHandCursor
    onHoveredChanged: if (card.studio) card.studio.hoverPreview(card.cardId, hovered)
  }

  O.CursorSurface {
    anchors.fill: parent
    hasCursor: card.hot
    current: card.chosen
    bordered: true
    foreground: card.studio ? card.studio.fg : Kit.Color.popups.text
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: {
      if (!card.studio) return
      card.studio.keyboardMode = false
      card.studio.navCurrent = card
      card.studio.pickSkin(card.cardId, card.userSkin)
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
      paletteMap: card.studio ? card.studio.palette : ({})
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(4)

      Text {
        visible: !card.renaming
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: card.title
        color: card.chosen ? Kit.Color.accent : (card.studio ? card.studio.fg : Kit.Color.popups.text)
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
                color: card.studio ? card.studio.fg : Kit.Color.popups.text
                selectionColor: Style.selectionFillFor(card.studio ? card.studio.fg : Kit.Color.popups.text, Kit.Color.accent)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Component.onCompleted: {
                  forceActiveFocus()
                  selectAll()
                }
                onPasteRequested: if (card.studio && card.studio.engine) card.studio.engine.pasteInto(renameField)
                onActiveFocusChanged: if (!activeFocus && card.studio) card.studio.finishRename(card.cardId, text, false)
                onKeyPressed: function(event) {
                  if (!card.studio) return
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    event.accepted = true
                    card.studio.finishRename(card.cardId, text, true)
                  } else if (event.key === Qt.Key_Escape) {
                    event.accepted = true
                    card.studio.finishRename(card.cardId, text, false)
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
        tip: card.studio ? card.studio.tr("card.rename", "Rename (R)") : "Rename (R)"
        onTriggered: if (card.studio) card.studio.startRename(card.cardId)
      }

      CardIcon {
        visible: card.userSkin && (card.hot || card.confirmingDelete) && !card.renaming
        glyph: "󰆴"
        danger: card.confirmingDelete
        tip: card.studio ? card.studio.tr("card.delete", "Delete (Del)") : "Delete (Del)"
        onTriggered: if (card.studio) card.studio.requestDelete(card.cardId, card.title)
      }
    }
  }

  O.PanelToolTip {
    visible: cardHover.hovered && card.subtitle !== "" && !card.renaming
    delay: 500
    text: card.subtitle
  }

  component CardIcon: Text {
    id: icon
    property string glyph: ""
    property string tip: ""
    property bool danger: false
    signal triggered()

    textFormat: Text.PlainText
    text: glyph
    color: danger ? Kit.Color.urgent : (iconMouse.containsMouse ? Kit.Color.accent : (card.studio ? card.studio.dimFg : Kit.Color.textDim))
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
