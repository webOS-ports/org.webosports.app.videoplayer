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
import QtMultimedia

/*
 * A player with no picture or sound, for reading a file's length: Qt reads
 * it (GStreamer's discoverer, on a thread) when the source is set, without
 * playing anything. See DurationProbe.
 */
MediaPlayer {
    readonly property bool done: mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.InvalidMedia
                                 || error !== MediaPlayer.NoError
    readonly property bool failed: mediaStatus === MediaPlayer.InvalidMedia || error !== MediaPlayer.NoError
}
