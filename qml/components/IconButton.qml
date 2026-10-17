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

import LunaNext.Common 0.1
import LuneOS.Forms 1.0 as Forms

/*
 * LuneOS.Forms' toolbar key with a picture from qml/images ("<image>.svg"),
 * or a short text (the speed), on the player's dark bars: lit while held or
 * checked.
 */
Forms.IconToolButton {
    imageFolder: Qt.resolvedUrl("../images/")
    appearance: "overlay"
    implicitHeight: Math.max(Units.gu(5.5), 54)
}
