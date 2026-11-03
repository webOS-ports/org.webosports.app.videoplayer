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

import "../js/Online.js" as Online
import LuneOS.Components 1.0 as LC

/*
 * An item from a server: its picture - a poster (2:3) for films and shows,
 * a frame (16:9) for videos and episodes - with how far it was watched,
 * and its title and a line under it. A folder shows a folder.
 */
ItemDelegate {
    id: tile

    property var item: ({})
    // 16:9 pictures, or 2:3 posters.
    property bool wide: true

    signal held()

    padding: Units.gu(0.6)
    onPressAndHold: tile.held()

    background: Rectangle {
        radius: Units.gu(0.8)
        color: tile.pressed ? "#30000000" : "transparent"
    }

    contentItem: Column {
        spacing: Units.gu(0.4)

        Item {
            width: parent.width
            height: tile.wide ? width * 9 / 16 : width * 3 / 2

            Rectangle {
                anchors.fill: parent
                color: "#262626"
                radius: Units.gu(0.5)
            }
            Image {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.5
                height: width
                sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
                source: Qt.resolvedUrl("../images/video.svg")
                visible: picture.status !== Image.Ready
                opacity: 0.6
            }
            Image {
                id: picture
                objectName: "picture"
                anchors.fill: parent
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                clip: true
                sourceSize.width: Math.ceil(width)
                source: Online.pictureOf(tile.item, tile.wide)
            }
            Label {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Units.gu(0.5)
                visible: text !== ""
                text: tile.item.durationMs > 0 && tile.item.playable ? LC.FileLists.formatClock(tile.item.durationMs) : ""
                color: "white"
                font.pixelSize: FontUtils.sizeToPixels("small")
                leftPadding: Units.gu(0.5)
                rightPadding: Units.gu(0.5)
                background: Rectangle { color: "#b0000000"; radius: Units.gu(0.3) }
            }
            Label {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Units.gu(0.5)
                visible: tile.item.hasChildren === true
                text: "›"
                color: "white"
                font.pixelSize: FontUtils.sizeToPixels("large")
                leftPadding: Units.gu(0.6)
                rightPadding: Units.gu(0.6)
                background: Rectangle { color: "#80000000"; radius: Units.gu(0.3) }
            }
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: Units.gu(0.5)
                width: parent.width * Math.max(0, Math.min(1, Online.progressOf(tile.item)))
                visible: Online.progressOf(tile.item) >= 0
                color: "#4a8fd8"
            }
        }

        Label {
            width: parent.width
            text: tile.item.title || ""
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            font.pixelSize: FontUtils.sizeToPixels("small")
            color: Colors.text
        }
        Label {
            width: parent.width
            text: Online.detailsOf(tile.item)
            visible: text !== ""
            elide: Text.ElideRight
            font.pixelSize: FontUtils.sizeToPixels("x-small")
            color: Colors.secondaryText
        }
    }
}
