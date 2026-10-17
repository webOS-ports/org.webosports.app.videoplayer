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

import LunaNext.Common 0.1

/*
 * A button with a picture from qml/images ("<image>.svg"), drawn at its
 * size, or a short text (the speed). On the player's dark bars; lit while
 * held or checked.
 *
 * At least 54 px across, the legacy guidelines' smallest touch target.
 */
ToolButton {
    id: button

    property string image
    property string label
    // The picture's share of the button.
    property real iconSize: Units.gu(3)
    property color labelColor: "white"

    implicitWidth: Math.max(Units.gu(6), 54)
    implicitHeight: Math.max(Units.gu(5.5), 54)
    padding: 0
    focusPolicy: Qt.NoFocus

    contentItem: Item {
        Image {
            anchors.centerIn: parent
            width: button.iconSize
            height: button.iconSize
            visible: button.image !== ""
            source: button.image !== "" ? Qt.resolvedUrl("../images/" + button.image + ".svg") : ""
            sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
            opacity: button.enabled ? 1.0 : 0.35
        }
        Text {
            anchors.centerIn: parent
            visible: button.image === ""
            text: button.label
            color: button.labelColor
            opacity: button.enabled ? 1.0 : 0.35
            font.pixelSize: FontUtils.sizeToPixels("medium")
            font.bold: true
        }
    }

    background: Rectangle {
        radius: Units.gu(0.6)
        color: button.pressed ? "#55ffffff" : (button.checked ? "#33ffffff" : "transparent")
    }
}
