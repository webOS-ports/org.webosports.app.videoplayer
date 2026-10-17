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
import QtTest

import "../../qml/js/Format.js" as Format

/*
 * qml/js/Format.js: times, lengths, sizes, dates, speeds.
 */
TestCase {
    name: "Format"

    function test_clock() {
        compare(Format.clock(0), "0:00");
        compare(Format.clock(7999), "0:07");
        compare(Format.clock(754000), "12:34");
        compare(Format.clock(3723000), "1:02:03");
        compare(Format.clock(5000, true), "0:00:05");
        compare(Format.clock(-5), "0:00");
        compare(Format.clock(NaN), "0:00");
        compare(Format.clock(undefined), "0:00");
    }

    function test_remaining_and_elapsed() {
        compare(Format.remaining(10000, 95000), "-1:25");
        compare(Format.remaining(99000, 95000), "-0:00");
        compare(Format.remaining(0, 3600000), "-1:00:00");
        compare(Format.elapsed(5000, 3600000), "0:00:05", "hours shown when the video has them");
        compare(Format.elapsed(5000, 60000), "0:05");
    }

    function test_duration() {
        compare(Format.duration(0), "");
        compare(Format.duration(-1), "");
        compare(Format.duration(45000), "45 s");
        compare(Format.duration(180000), "3 min");
        compare(Format.duration(3900000), "1 h 05 min");
    }

    function test_size() {
        compare(Format.size(512), "512 B");
        compare(Format.size(2048), "2.0 KB");
        compare(Format.size(23113203), "22 MB");
        compare(Format.size(5 * 1024 * 1024 * 1024), "5.0 GB");
        compare(Format.size(undefined), "");
    }

    function test_date() {
        var now = new Date(2026, 9, 16, 21, 0).getTime();
        compare(Format.date(new Date(2026, 9, 16, 1, 0).getTime(), now), "Today");
        compare(Format.date(new Date(2026, 9, 15, 23, 0).getTime(), now), "Yesterday");
        compare(Format.date(new Date(2026, 8, 3).getTime(), now), "3 Sep");
        compare(Format.date(new Date(2024, 0, 31).getTime(), now), "31 Jan 2024");
        compare(Format.date("not a date", now), "");
    }

    function test_rate() {
        compare(Format.rate(1), "1×");
        compare(Format.rate(1.25), "1.25×");
        compare(Format.rate(0.5), "0.5×");
    }
}
