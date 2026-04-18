import QtQuick
import QtQuick.Layouts
import md3.Core

Item {
    id: root
    anchors.fill: parent

    function readinessText() {
        return PhoenixBackend.ready ? "已就绪" : "不可用"
    }

    function runningIdsText() {
        if (!PhoenixBackend.runningIds || PhoenixBackend.runningIds.length === 0) {
            return "无"
        }
        return PhoenixBackend.runningIds.join(", ")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "状态组件"
                font.pixelSize: Theme.typography.displaySmall.size
                font.family: Theme.typography.displaySmall.family
                font.weight: Theme.typography.displaySmall.weight
                color: Theme.color.onSurfaceColor
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "后端 " + root.readinessText()
                color: PhoenixBackend.ready ? "#1b8f4b" : Theme.color.error
                font.pixelSize: Theme.typography.bodyLarge.size
                font.family: Theme.typography.bodyLarge.family
                font.weight: Font.Medium
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 12
            rowSpacing: 12

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 106
                padding: 14
                type: "filled"
                color: Theme.color.surfaceContainerLow

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6
                    Text { text: "总环境数"; color: Theme.color.onSurfaceVariantColor; font.pixelSize: 12 }
                    Text { text: String(PhoenixBackend.profileCount); color: Theme.color.onSurfaceColor; font.pixelSize: 28 }
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 106
                padding: 14
                type: "filled"
                color: Theme.color.surfaceContainerLow

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6
                    Text { text: "运行中"; color: Theme.color.onSurfaceVariantColor; font.pixelSize: 12 }
                    Text { text: String(PhoenixBackend.runningCount); color: "#1b8f4b"; font.pixelSize: 28 }
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 106
                padding: 14
                type: "filled"
                color: Theme.color.surfaceContainerLow

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6
                    Text { text: "桥接状态"; color: Theme.color.onSurfaceVariantColor; font.pixelSize: 12 }
                    Text {
                        text: root.readinessText()
                        color: PhoenixBackend.ready ? Theme.color.onSurfaceColor : Theme.color.error
                        font.pixelSize: 22
                    }
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 106
                padding: 14
                type: "filled"
                color: Theme.color.surfaceContainerLow

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6
                    Text { text: "日志行数"; color: Theme.color.onSurfaceVariantColor; font.pixelSize: 12 }
                    Text { text: String(PhoenixBackend.logsText.length > 0 ? PhoenixBackend.logsText.split("\n").length : 0); color: Theme.color.onSurfaceColor; font.pixelSize: 28 }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 84
            padding: 12
            type: "filled"
            color: Theme.color.surfaceContainerLow

            RowLayout {
                anchors.fill: parent
                spacing: 10

                Button {
                    text: "启动全部"
                    type: "filled"
                    enabled: PhoenixBackend.profileCount > 0
                    onClicked: PhoenixBackend.startAll()
                }

                Button {
                    text: "停止全部"
                    type: "outlined"
                    enabled: PhoenixBackend.runningCount > 0
                    onClicked: PhoenixBackend.stopAll()
                }

                Button {
                    text: "删除未运行"
                    type: "outlined"
                    enabled: PhoenixBackend.profileCount > 0
                    onClicked: PhoenixBackend.deleteStopped()
                }

                Button {
                    text: "清空日志"
                    type: "text"
                    onClicked: PhoenixBackend.clearLogs()
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "刷新环境"
                    type: "text"
                    onClicked: PhoenixBackend.reloadProfiles()
                }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 108
            padding: 12
            type: "filled"
            color: Theme.color.surfaceContainerLow

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                Text {
                    text: "运行中的 ID"
                    color: Theme.color.onSurfaceColor
                    font.pixelSize: Theme.typography.titleSmall.size
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: root.runningIdsText()
                        color: Theme.color.onSurfaceVariantColor
                        font.pixelSize: Theme.typography.bodyMedium.size
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "复制运行中 ID"
                        type: "text"
                        enabled: PhoenixBackend.runningCount > 0
                        onClicked: PhoenixBackend.copyIdsToClipboard(PhoenixBackend.runningIds)
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
