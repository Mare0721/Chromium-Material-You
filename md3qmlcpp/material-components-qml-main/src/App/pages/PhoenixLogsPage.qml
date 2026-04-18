import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import md3.Core

Item {
    id: root
    anchors.fill: parent

    function runningText() {
        if (!PhoenixBackend.runningIds || PhoenixBackend.runningIds.length === 0) {
            return "无"
        }
        return PhoenixBackend.runningIds.join(", ")
    }

    function scrollToBottom() {
        var maxY = logFlick.contentHeight - logFlick.height
        logFlick.contentY = maxY > 0 ? maxY : 0
    }

    Connections {
        target: PhoenixBackend

        function onLogsChanged() {
            Qt.callLater(function() {
                root.scrollToBottom()
            })
        }
    }

    Component.onCompleted: Qt.callLater(root.scrollToBottom)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "运行日志"
                font.pixelSize: Theme.typography.displaySmall.size
                font.family: Theme.typography.displaySmall.family
                font.weight: Theme.typography.displaySmall.weight
                color: Theme.color.onSurfaceColor
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "运行中的 ID: " + root.runningText()
                font.pixelSize: Theme.typography.bodyLarge.size
                font.family: Theme.typography.bodyLarge.family
                font.weight: Font.Medium
                color: Theme.color.onSurfaceVariantColor
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Button {
                text: "清空日志"
                type: "outlined"
                onClicked: PhoenixBackend.clearLogs()
            }

            Button {
                text: "复制全部"
                type: "text"
                onClicked: {
                    logsEditor.selectAll()
                    logsEditor.copy()
                    logsEditor.select(0, 0)
                }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 12
            type: "filled"
            color: Theme.color.surfaceContainerLow

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                Text {
                    visible: !PhoenixBackend.ready
                    text: "后端桥接不可用：" + PhoenixBackend.bridgeError
                    color: Theme.color.error
                    font.pixelSize: Theme.typography.bodySmall.size
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Theme.color.surfaceContainerHighest
                    border.width: 1
                    border.color: Theme.color.outlineVariant

                    Flickable {
                        id: logFlick
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 20
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        clip: true
                        contentWidth: width
                        contentHeight: Math.max(height, logsEditor.contentHeight + 8)

                        TextEdit {
                            id: logsEditor
                            width: logFlick.width
                            readOnly: true
                            text: PhoenixBackend.logsText
                            color: Theme.color.onSurfaceColor
                            wrapMode: TextEdit.WrapAnywhere
                            selectByMouse: true
                            font.family: "Consolas"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                    }

                    ScrollBar {
                        target: logFlick
                        orientation: Qt.Vertical
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 6
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                    }
                }
            }
        }
    }
}
