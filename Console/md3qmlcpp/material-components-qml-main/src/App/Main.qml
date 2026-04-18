import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import md3.Core

Window {
    id: shellWindow
    width: 1280
    height: 800
    minimumWidth: 980
    minimumHeight: 620
    visible: true
    title: "Console"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    property bool transitionToMaximized: false

    function applyWindowToggle() {
        if (shellWindow.visibility === Window.Maximized || shellWindow.visibility === Window.FullScreen) {
            shellWindow.showNormal()
        } else {
            shellWindow.showMaximized()
        }
    }

    function toggleWindowStateAnimated() {
        if (windowStateAnim.running) {
            return
        }
        transitionToMaximized = !(shellWindow.visibility === Window.Maximized || shellWindow.visibility === Window.FullScreen)
        windowStateAnim.start()
    }

    component WindowControlButton: Rectangle {
        id: btn
        property string icon: ""
        property bool destructive: false
        property color baseColor: Theme.color.surfaceContainerLow
        property color hoverColor: destructive ? "#F6D4D7" : Theme.color.secondaryContainer
        property color pressColor: destructive ? "#F1B8BD" : Theme.color.surfaceContainerHighest
        property color holdColor: destructive ? "#EAA8AF" : Theme.color.primaryContainer
        property color iconColor: destructive ? "#B3261E" : Theme.color.onSurfaceVariantColor
        property bool longPressed: false
        signal clicked()

        width: 42
        height: 30
        radius: 10
        antialiasing: true
        clip: true
        color: longPressed
               ? holdColor
               : (mouseArea.pressed
                  ? pressColor
                  : (mouseArea.containsMouse ? hoverColor : baseColor))
        scale: longPressed ? 0.95 : (mouseArea.pressed ? 0.97 : 1.0)
        border.width: mouseArea.containsMouse ? 1 : 0
        border.color: mouseArea.containsMouse
                  ? (destructive ? "#C84F58" : Theme.color.outlineVariant)
                  : (destructive ? "#E9C5C8" : Theme.color.surfaceContainerHigh)

        Behavior on border.width {
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Behavior on border.color {
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Timer {
            id: holdTimer
            interval: 340
            repeat: false
            onTriggered: btn.longPressed = true
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onPressed: {
                btn.longPressed = false
                holdTimer.restart()
            }
            onReleased: {
                holdTimer.stop()
                btn.longPressed = false
            }
            onCanceled: {
                holdTimer.stop()
                btn.longPressed = false
            }
            onClicked: btn.clicked()
        }

        Text {
            anchors.centerIn: parent
            text: btn.icon
            font.family: Theme.iconFont.name
            font.pixelSize: 18
            font.weight: Font.DemiBold
            color: btn.iconColor
        }
    }

    Rectangle {
        id: appChrome
        anchors.fill: parent
        radius: (shellWindow.visibility === Window.Maximized || shellWindow.visibility === Window.FullScreen) ? 0 : 10
        antialiasing: true
        clip: true
        color: Theme.color.background
        border.width: 1
        border.color: Theme.color.outlineVariant
        scale: 1
        opacity: 1
        transformOrigin: Item.Center

        Behavior on radius {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: windowStateOverlay
            anchors.fill: parent
            color: Theme.color.surfaceContainerHigh
            opacity: 0
            visible: opacity > 0.001
            z: 9
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: embeddedTitleBar
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                color: Theme.color.surfaceContainerLow
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 8
                    z: 2

                    Item {
                        id: dragHost
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.ArrowCursor

                            property real pressX: 0
                            property real pressY: 0

                            onPressed: {
                                pressX = mouse.x
                                pressY = mouse.y
                            }

                            onPositionChanged: {
                                if (!(mouse.buttons & Qt.LeftButton)) {
                                    return
                                }
                                if (shellWindow.visibility === Window.Maximized || shellWindow.visibility === Window.FullScreen) {
                                    return
                                }
                                shellWindow.x += mouse.x - pressX
                                shellWindow.y += mouse.y - pressY
                            }

                            onDoubleClicked: shellWindow.toggleWindowStateAnimated()
                        }
                    }

                    RowLayout {
                        id: titleButtons
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 6
                        z: 3

                        WindowControlButton {
                            icon: "remove"
                            onClicked: shellWindow.showMinimized()
                        }

                        WindowControlButton {
                            icon: shellWindow.visibility === Window.Maximized ? "filter_none" : "crop_square"
                            onClicked: shellWindow.toggleWindowStateAnimated()
                        }

                        WindowControlButton {
                            icon: "close"
                            destructive: true
                            onClicked: shellWindow.close()
                        }
                    }
                }

            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                source: "AppRoot.qml"
            }
        }
    }

    SequentialAnimation {
        id: windowStateAnim

        ParallelAnimation {
            ColorAnimation {
                target: embeddedTitleBar
                property: "color"
                to: Theme.color.surfaceContainerHighest
                duration: 170
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: appChrome
                property: "scale"
                to: shellWindow.transitionToMaximized ? 0.972 : 1.015
                duration: 170
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: appChrome
                property: "opacity"
                to: 0.9
                duration: 170
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: windowStateOverlay
                property: "opacity"
                to: 0.14
                duration: 170
                easing.type: Easing.OutCubic
            }
        }

        ScriptAction {
            script: {
                shellWindow.applyWindowToggle()
                if (shellWindow.transitionToMaximized) {
                    appChrome.scale = 0.9
                    appChrome.opacity = 0.84
                    windowStateOverlay.opacity = 0.26
                } else {
                    appChrome.scale = 1.05
                    appChrome.opacity = 0.88
                    windowStateOverlay.opacity = 0.22
                }
            }
        }

        PauseAnimation { duration: 36 }

        ParallelAnimation {
            ColorAnimation {
                target: embeddedTitleBar
                property: "color"
                to: Theme.color.surfaceContainerLow
                duration: 420
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: appChrome
                property: "scale"
                to: 1
                duration: 420
                easing.type: Easing.OutQuart
            }

            NumberAnimation {
                target: appChrome
                property: "opacity"
                to: 1
                duration: 420
                easing.type: Easing.OutQuart
            }

            NumberAnimation {
                target: windowStateOverlay
                property: "opacity"
                to: 0
                duration: 420
                easing.type: Easing.OutQuart
            }
        }
    }
}
