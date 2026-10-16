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

.pragma library

/*
 * Times, lengths, sizes and dates as the app shows them.
 */

function pad2(n) {
    return n < 10 ? "0" + n : String(n);
}

// A position as a clock: "0:07", "12:34", "1:02:03". With hours true the
// hours are always shown, so a column of times lines up for a long video.
// Negative and non-numbers count as 0; parts of a second are dropped.
function clock(ms, hours) {
    var total = Math.floor((isFinite(ms) && ms > 0 ? ms : 0) / 1000);
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    if (h > 0 || hours)
        return h + ":" + pad2(m) + ":" + pad2(s);
    return m + ":" + pad2(s);
}

// The time left, as the legacy player showed it: "-1:23".
function remaining(positionMs, durationMs) {
    var left = Math.max(0, (durationMs || 0) - (positionMs || 0));
    return "-" + clock(left, durationMs >= 3600000);
}

// Elapsed and total for the seek bar's labels, with hours on both when the
// video has them.
function elapsed(positionMs, durationMs) {
    return clock(positionMs, durationMs >= 3600000);
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
    return Math.floor(min / 60) + " h " + pad2(min % 60) + " min";
}

function size(bytes) {
    if (!(bytes >= 0))
        return "";
    if (bytes < 1024)
        return bytes + " B";
    var units = ["KB", "MB", "GB", "TB"];
    var v = bytes / 1024;
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
        v /= 1024;
        u++;
    }
    return (v < 10 ? v.toFixed(1) : Math.round(v)) + " " + units[u];
}

var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// When a file was changed: "Today", "Yesterday", "12 Oct", or with the year
// when it is not this one. now is passed in for the tests.
function date(when, now) {
    var d = when instanceof Date ? when : new Date(when);
    if (isNaN(d.getTime()))
        return "";
    var n = new Date(now);
    var day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    var today = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime();
    var days = Math.round((today - day) / 86400000);
    if (days === 0)
        return "Today";
    if (days === 1)
        return "Yesterday";
    var text = d.getDate() + " " + months[d.getMonth()];
    return d.getFullYear() === n.getFullYear() ? text : text + " " + d.getFullYear();
}

// A playback rate as the speed button shows it: "1×", "1.25×", "0.5×".
function rate(r) {
    return (Math.round(r * 100) / 100) + "×";
}
