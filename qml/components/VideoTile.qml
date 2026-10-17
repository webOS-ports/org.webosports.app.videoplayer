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
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1
import LuneOS.Forms 1.0

/*
 * A video in the library's grid, on a tablet: a large picture with its
 * length and progress on it, the name under it.
 */
ItemDelegate {
    id: tile

    property string path
    property string name
    property string details
    property string length
    property url thumbnail
    property real progress: -1

    signal held()

    padding: Units.gu(1)
    onPressAndHold: tile.held()

    background: Rectangle {
        radius: Units.gu(0.8)
        color: tile.pressed ? "#30000000" : "transparent"
    }

    contentItem: Column {
        spacing: Units.gu(0.6)

        Item {
            width: parent.width
            height: width * 9 / 16

            Rectangle {
                anchors.fill: parent
                color: "#262626"
                radius: Units.gu(0.5)
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
                source: tile.thumbnail
            }
            Label {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Units.gu(0.6)
                visible: text !== ""
                text: tile.length
                color: "white"
                font.pixelSize: FontUtils.sizeToPixels("small")
                leftPadding: Units.gu(0.5)
                rightPadding: Units.gu(0.5)
                background: Rectangle { color: "#b0000000"; radius: Units.gu(0.3) }
            }
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: Units.gu(0.6)
                width: parent.width * Math.max(0, Math.min(1, tile.progress))
                visible: tile.progress >= 0
                color: "#4a8fd8"
            }
        }

        Label {
            width: parent.width
            text: tile.name
            elide: Text.ElideRight
            font.pixelSize: FontUtils.sizeToPixels("medium")
            color: Colors.text
        }
        Label {
            width: parent.width
            text: tile.details
            visible: text !== ""
            elide: Text.ElideRight
            font.pixelSize: FontUtils.sizeToPixels("small")
            color: Colors.secondaryText
        }
    }
}
