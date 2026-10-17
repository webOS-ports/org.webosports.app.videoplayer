/*
 * Copyright (C) 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1
import LuneOS.Components 1.0
import LuneOS.Forms 1.0

/*
 * A video in the library's list: its picture (once it has been played) or
 * a film frame, its length on it, its name, where it is and how big - and
 * how far it was watched, for one to carry on with.
 */
ItemDelegate {
    id: row

    property string path
    property string name
    property string details
    property string length
    property url thumbnail
    // 0 to 1, or less than 0 for no bar.
    property real progress: -1
    property int index: 0
    property int count: 0

    signal held()

    height: Units.gu(9)
    padding: 0

    onPressAndHold: row.held()

    contentItem: RowLayout {
        spacing: Units.gu(1.5)

        Item {
            Layout.leftMargin: Units.gu(1)
            Layout.preferredWidth: Units.gu(12)
            Layout.preferredHeight: Units.gu(6.75)

            Rectangle {
                anchors.fill: parent
                color: "#262626"
                radius: Units.gu(0.4)
            }
            Image {
                anchors.fill: parent
                sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
                source: Qt.resolvedUrl("../images/video.svg")
                visible: picture.status !== Image.Ready
            }
            Image {
                id: picture
                objectName: "thumbnail"
                anchors.fill: parent
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                clip: true
                source: row.thumbnail
            }
            Label {
                objectName: "lengthBadge"
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Units.gu(0.4)
                visible: text !== ""
                text: row.length
                color: "white"
                font.pixelSize: FontUtils.sizeToPixels("small")
                leftPadding: Units.gu(0.4)
                rightPadding: Units.gu(0.4)
                background: Rectangle { color: "#b0000000"; radius: Units.gu(0.3) }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.rightMargin: Units.gu(1.5)
            spacing: Units.gu(0.3)

            Label {
                Layout.fillWidth: true
                text: row.name
                elide: Text.ElideRight
                font.pixelSize: FontUtils.sizeToPixels("medium")
                color: Colors.text
            }

            Label {
                Layout.fillWidth: true
                text: row.details
                visible: text !== ""
                elide: Text.ElideMiddle
                font.pixelSize: FontUtils.sizeToPixels("small")
                color: Colors.secondaryText
            }

            Rectangle {
                objectName: "progressBar"
                Layout.fillWidth: true
                Layout.topMargin: Units.gu(0.3)
                Layout.preferredHeight: Units.gu(0.5)
                visible: row.progress >= 0
                radius: height / 2
                color: Colors.ruleDark

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, row.progress))
                    height: parent.height
                    radius: parent.radius
                    color: "#4a8fd8"
                }
            }
        }
    }

    ListDelegateSeparator {
        anchors.fill: parent
        index: row.index
        count: row.count
    }
}
