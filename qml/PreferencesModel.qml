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
import QtCore

/*
 * The app's preferences, in the app's settings file. Where each video was
 * left lives in ResumeStore.
 */
Settings {
    // Not a QSettings organisation/application pair: the QML runner is
    // shared by every QML app, so the file is named explicitly.
    location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)
              + "/org.webosports.app.videoplayer/preferences.ini"
    category: "player"

    // The library's order: "name", "date" or "size".
    property string sortOrder: "name"
    // How the picture fills the screen: "fit" (all of it, with bars) or
    // "fill" (the screen, cropped).
    property string fillMode: "fit"
    // Subtitle text size: "small", "medium" or "large".
    property string subtitleSize: "medium"
    // A landscape video on a portrait screen turned to fill it.
    property bool turnLandscape: true
    // The length of every video read in the background. Off by default:
    // on Halium images without the gst-droid audio rank fix, loading a
    // video with AAC sound ends the app.
    property bool readLengths: false
}
