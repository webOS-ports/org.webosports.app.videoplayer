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

.pragma library
.import LuneOS.Components 1.0 as LC

/*
 * Times and lengths as only this app shows them. Clocks, sizes and days are
 * LuneOS.Components' FileLists (formatClock, formatSize, formatDay), as in
 * the other apps.
 */

// The time left, as the legacy player showed it: "-1:23".
function remaining(positionMs, durationMs) {
    var left = Math.max(0, (durationMs || 0) - (positionMs || 0));
    return "-" + LC.FileLists.formatClock(left, durationMs >= 3600000);
}

// Elapsed and total for the seek bar's labels, with hours on both when the
// video has them.
function elapsed(positionMs, durationMs) {
    return LC.FileLists.formatClock(positionMs, durationMs >= 3600000);
}

// A video's length in the library: "45 s", "3 min", "1 h 05 min". Unknown
// (0 or less) is "".
function duration(ms) {
    if (!(ms > 0))
        return "";
    var s = Math.round(ms / 1000);
    if (s < 60)
        return s + " s";
    var min = Math.round(s / 60);
    if (min < 60)
        return min + " min";
    return Math.floor(min / 60) + " h " + LC.FileLists.pad2(min % 60) + " min";
}

// A playback rate as the speed button shows it: "1×", "1.25×", "0.5×".
function rate(r) {
    return (Math.round(r * 100) / 100) + "×";
}
