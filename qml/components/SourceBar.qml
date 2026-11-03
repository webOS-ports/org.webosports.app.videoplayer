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
 * The libraries to pick from, as in Photos & Videos: this device first,
 * then each video server of the accounts. Shown only when there is a
 * server; a row of buttons that scrolls sideways.
 */
ListView {
    id: bar
    objectName: "sourceBar"

    // [{sourceId, name, icon}]
    property var sources: []
    property string current: ""
    signal picked(string sourceId)

    orientation: ListView.Horizontal
    spacing: Units.gu(0.8)
    clip: true
    implicitHeight: Units.gu(5)
    visible: sources.length > 0
    boundsBehavior: Flickable.StopAtBounds
    model: [{ sourceId: "", name: "This Device", icon: "" }].concat(sources)

    delegate: ItemDelegate {
        id: chip
        objectName: "source:" + modelData.sourceId
        readonly property bool selected: modelData.sourceId === bar.current
        height: bar.height
        leftPadding: Units.gu(1.2)
        rightPadding: Units.gu(1.2)
        focusPolicy: Qt.NoFocus

        background: Rectangle {
            radius: height / 2
            color: chip.selected ? "#4a8fd8" : (chip.pressed ? "#40000000" : "#20000000")
        }
        contentItem: Row {
            spacing: Units.gu(0.6)
            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: Units.gu(2.6)
                height: width
                visible: modelData.icon !== ""
                sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
                source: modelData.icon !== "" ? (modelData.icon.charAt(0) === "/" ? "file://" + modelData.icon : modelData.icon) : ""
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
                color: chip.selected ? "white" : Colors.text
                font.pixelSize: FontUtils.sizeToPixels("medium")
                font.bold: chip.selected
            }
        }
        onClicked: bar.picked(modelData.sourceId)
    }
}
