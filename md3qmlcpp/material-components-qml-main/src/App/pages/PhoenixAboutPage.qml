import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import md3.Core

Item {
    id: root

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 24

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 120
            Layout.preferredHeight: 120

            Image {
                id: sourceItem
                source: "https://avatars.githubusercontent.com/u/46568635?v=4"
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                fillMode: Image.PreserveAspectCrop
                visible: false
                asynchronous: true
                cache: true
            }

            MultiEffect {
                id: multiEffect
                source: sourceItem
                anchors.fill: sourceItem
                maskEnabled: true
                maskSource: mask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Item {
                id: mask
                width: sourceItem.width
                height: sourceItem.height
                layer.enabled: true
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "black"
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            Text {
                text: "SudoEvolve"
                font.family: Theme.typography.headlineMedium.family
                font.pixelSize: Theme.typography.headlineMedium.size
                color: Theme.color.onSurfaceColor
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Qt/QML 开发者"
                font.family: Theme.typography.bodyLarge.family
                font.pixelSize: Theme.typography.bodyLarge.size
                color: Theme.color.onSurfaceVariantColor
                Layout.alignment: Qt.AlignHCenter
            }
        }

        Text {
            text: "专注于使用 Qt Quick 与 Material Design 3 构建高质量、可维护的用户界面。"
            font.family: Theme.typography.bodyMedium.family
            font.pixelSize: Theme.typography.bodyMedium.size
            color: Theme.color.onSurfaceVariantColor
            horizontalAlignment: Text.AlignHCenter
            Layout.maximumWidth: 430
            wrapMode: Text.WordWrap
            Layout.alignment: Qt.AlignHCenter
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16

            Button {
                text: "GitHub"
                type: "tonal"
                icon: "code"
                onClicked: Qt.openUrlExternally("https://github.com/sudoevolve")
            }

            Button {
                text: "个人网站"
                type: "outlined"
                icon: "public"
                onClicked: Qt.openUrlExternally("https://sudoevolve.github.io/")
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            Layout.topMargin: 32

            Text {
                text: "许可证"
                font.family: Theme.typography.titleMedium.family
                font.pixelSize: Theme.typography.titleMedium.size
                color: Theme.color.onSurfaceColor
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Copyright @ 2026 SudoEvolve\nLicensed under GNU LGPLv3\n(GNU Lesser General Public License v3.0)"
                font.family: Theme.typography.bodySmall.family
                font.pixelSize: Theme.typography.bodySmall.size
                color: Theme.color.onSurfaceVariantColor
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "第三方组件"
                font.family: Theme.typography.titleSmall.family
                font.pixelSize: Theme.typography.titleSmall.size
                color: Theme.color.onSurfaceColor
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16
            }

            Text {
                text: "material-color-utilities\nCopyright 2022 Google LLC\nLicensed under Apache License 2.0"
                font.family: Theme.typography.bodySmall.family
                font.pixelSize: Theme.typography.bodySmall.size
                color: Theme.color.onSurfaceVariantColor
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
