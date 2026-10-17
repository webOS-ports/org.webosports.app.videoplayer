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
import QtSensors

/*
 * Which way up the device is held, from the orientation sensor: 0, 90
 * (left side up), 180, 270 (right side up), or -1 when it cannot tell
 * (lying flat). Loaded through a Loader: without Qt Sensors the player
 * turns the one default way.
 */
Item {
    readonly property int angle: {
        var o = sensor.reading ? sensor.reading.orientation : 0;
        switch (o) {
        case OrientationReading.TopUp: return 0;
        case OrientationReading.LeftUp: return 90;
        case OrientationReading.TopDown: return 180;
        case OrientationReading.RightUp: return 270;
        default: return -1;
        }
    }
    property alias active: sensor.active

    OrientationSensor {
        id: sensor
        active: true
    }
}
