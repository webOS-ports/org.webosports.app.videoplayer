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
