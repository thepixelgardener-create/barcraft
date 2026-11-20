import QtQuick
import QtTest
import ".."

Item {
  width: 300
  height: 100

  Item {
    id: viewport
    width: 40
    height: 30
    clip: true

    Loader {
      id: loader
      width: parent.width
      sourceComponent: Item {
        implicitHeight: field.implicitHeight
        property alias editor: field

        LineField {
          id: field
          maximumLength: 40
          takesPaste: true
        }
      }
    }
  }

  TestCase {
    name: "StudioLineField"
    when: windowShown
    readonly property var field: loader.item.editor

    function init() {
      field.maximumLength = 40
      field.text = ""
      field.forceActiveFocus()
    }

    function test_pasteReplacesSelectedName() {
      field.text = "0123456789012345678901234567890123456789"
      field.selectAll()
      field.insertPastedText("A new\r\nname")
      compare(field.text, "A new name")
      compare(field.cursorPosition, field.length)
    }

    function test_pasteFitsSelection() {
      field.maximumLength = 6
      field.text = "abcdef"
      field.select(2, 4)
      field.insertPastedText("🦊abc")
      compare(field.text, "ab🦊ef")
      compare(field.cursorPosition, 4)
    }

    function test_pastePreservesSelectionForEmptyInput() {
      field.text = "old name"
      field.selectAll()
      field.insertPastedText("")
      compare(field.selectedText, "old name")
    }

    function test_pasteDoesNotSplitSurrogatePair() {
      field.maximumLength = 3
      field.text = "ab"
      field.cursorPosition = 1
      field.insertPastedText("🦊")
      compare(field.text, "ab")
      field.insertPastedText("c")
      compare(field.text, "acb")
    }

    function test_shortcutUsesPasteSignal() {
      const spy = createTemporaryObject(pasteSpy, this, { target: field })
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(spy.count, 1)
    }

    function test_longLineKeepsCaretInsideViewport() {
      field.text = "A rather long name for this field"
      field.cursorPosition = field.length
      verify(field.width > loader.width)
      verify(field.x < 0)
      verify(field.x + field.cursorRectangle.x + field.cursorRectangle.width <= viewport.width)
    }
  }

  Component {
    id: pasteSpy
    SignalSpy { signalName: "pasteRequested" }
  }
}
