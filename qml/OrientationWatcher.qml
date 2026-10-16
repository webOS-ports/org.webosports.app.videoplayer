/*
 * Copyright (C) 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
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
