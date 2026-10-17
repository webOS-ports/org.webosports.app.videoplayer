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

import "../../qml/js/Subtitles.js" as Subtitles

/*
 * qml/js/Subtitles.js: decoding, SubRip, ASS event lines, what is shown.
 */
TestCase {
    name: "Subtitles"

    function bytes(list) {
        return new Uint8Array(list);
    }

    function utf8(s) {
        var out = [];
        var e = unescape(encodeURIComponent(s));
        for (var i = 0; i < e.length; i++)
            out.push(e.charCodeAt(i));
        return new Uint8Array(out);
    }

    // ---- decoding ----

    function test_utf8_is_read_as_utf8() {
        var d = Subtitles.decode(utf8("Café € 😀"));
        compare(d.encoding, "UTF-8");
        compare(d.text, "Café € 😀");
    }

    function test_utf8_byte_order_mark_is_dropped() {
        var d = Subtitles.decode(bytes([0xef, 0xbb, 0xbf, 0x48, 0xc3, 0xa9]));
        compare(d.encoding, "UTF-8");
        compare(d.text, "Hé");
    }

    function test_latin1_falls_back_to_windows_1252() {
        // "Café naïve €" in Windows-1252: é e9, ï ef, € 80.
        var d = Subtitles.decode(bytes([0x43, 0x61, 0x66, 0xe9, 0x20, 0x6e, 0x61, 0xef, 0x76, 0x65, 0x20, 0x80]));
        compare(d.encoding, "Windows-1252");
        compare(d.text, "Café naïve €");
    }

    function test_invalid_utf8_forms_are_not_utf8() {
        // Overlong "/", a lone continuation byte, a surrogate, a cut-off
        // sequence: each makes the text single-byte.
        compare(Subtitles.decodeUtf8OrNull(bytes([0xc0, 0xaf])), null);
        compare(Subtitles.decodeUtf8OrNull(bytes([0x41, 0x80])), null);
        compare(Subtitles.decodeUtf8OrNull(bytes([0xed, 0xa0, 0x80])), null);
        compare(Subtitles.decodeUtf8OrNull(bytes([0x41, 0xe2, 0x82])), null);
        compare(Subtitles.decodeUtf8OrNull(bytes([0xf4, 0x90, 0x80, 0x80])), null);
        compare(Subtitles.decodeUtf8OrNull(bytes([0xe2, 0x82, 0xac])), "€");
    }

    function test_utf16_with_byte_order_mark() {
        compare(Subtitles.decode(bytes([0xff, 0xfe, 0x48, 0x00, 0xe9, 0x00])).text, "Hé");
        compare(Subtitles.decode(bytes([0xfe, 0xff, 0x00, 0x48, 0x20, 0xac])).text, "H€");
    }

    function test_empty_decodes_to_nothing() {
        compare(Subtitles.decode(bytes([])).text, "");
        compare(Subtitles.decode(null).text, "");
    }

    // ---- SubRip ----

    function test_timestamps() {
        compare(Subtitles.parseTimestamp("00:00:01,000"), 1000);
        compare(Subtitles.parseTimestamp(" 01:02:03,456 "), 3723456);
        compare(Subtitles.parseTimestamp("00:00:02.5"), 2500);
        compare(Subtitles.parseTimestamp("00:00:02"), 2000);
        compare(Subtitles.parseTimestamp("nonsense"), -1);
    }

    function test_srt_cues() {
        var cues = Subtitles.parseSrt("1\r\n00:00:01,000 --> 00:00:04,000\r\nOne\r\n\r\n"
                                      + "2\r\n00:00:06,500 --> 00:00:09,000 X1:10 X2:20\r\nTwo\r\nsecond line\r\n\r\n");
        compare(cues.length, 2);
        compare(cues[0].start, 1000);
        compare(cues[0].end, 4000);
        compare(cues[0].text, "One");
        compare(cues[1].start, 6500);
        compare(cues[1].text, "Two\nsecond line");
    }

    function test_srt_tolerates_mess() {
        // No counters, no final blank line, a block without a time, a
        // backwards cue, an empty cue, cues out of order.
        var cues = Subtitles.parseSrt("00:00:05,000 --> 00:00:06,000\nLater\n\n"
                                      + "garbage\n\n"
                                      + "3\n00:00:09,000 --> 00:00:08,000\nBackwards\n\n"
                                      + "4\n00:00:10,000 --> 00:00:11,000\n\n\n"
                                      + "00:00:01,000 --> 00:00:02,000\nFirst");
        compare(cues.length, 2);
        compare(cues[0].text, "First");
        compare(cues[1].text, "Later");
    }

    function test_cue_at_a_time() {
        var cues = Subtitles.parseSrt("1\n00:00:01,000 --> 00:00:04,000\nA\n\n2\n00:00:03,000 --> 00:00:05,000\nB\n\n"
                                      + "3\n00:00:10,000 --> 00:00:12,000\nC\n");
        compare(Subtitles.cueAt(cues, 999), "");
        compare(Subtitles.cueAt(cues, 1000), "A");
        compare(Subtitles.cueAt(cues, 3500), "A\nB", "overlapping cues both show");
        compare(Subtitles.cueAt(cues, 4000), "B", "a cue ends at its end time");
        compare(Subtitles.cueAt(cues, 7000), "");
        compare(Subtitles.cueAt(cues, 11999), "C");
        compare(Subtitles.cueAt([], 5), "");
    }

    // ---- ASS ----

    function test_matroska_ass_line_loses_its_fields() {
        compare(Subtitles.cleanEventText("1,0,Default,,0,0,0,,EMBEDDED ASS one"), "EMBEDDED ASS one");
        // A comma in the text stays.
        compare(Subtitles.cleanEventText("7,0,Default,Bob,0,0,0,,Well, hello"), "Well, hello");
    }

    function test_dialogue_line_loses_its_fields() {
        compare(Subtitles.cleanEventText("Dialogue: 0,0:00:01.00,0:00:05.00,Default,,0,0,0,,Hello, you"), "Hello, you");
    }

    function test_ass_overrides() {
        compare(Subtitles.cleanEventText("2,0,Default,,0,0,0,,EMBEDDED ASS two {\\i1}italic{\\i0}"),
                "EMBEDDED ASS two <i>italic</i>");
        compare(Subtitles.cleanEventText("3,0,Default,,0,0,0,,{\\pos(10,10)\\fad(200,200)}Top\\Nline\\hhere"),
                "Top\nline here");
        compare(Subtitles.cleanEventText("4,0,Default,,0,0,0,,{\\b700}Bold{\\b0} {\\u1}under"), "<b>Bold</b> <u>under</u>");
        // An italic left open is closed.
        compare(Subtitles.cleanEventText("5,0,Default,,0,0,0,,{\\i1}open"), "<i>open</i>");
        // {\r} resets.
        compare(Subtitles.cleanEventText("6,0,Default,,0,0,0,,{\\i1}a{\\r}b"), "<i>a</i>b");
    }

    function test_ass_drawings_are_dropped() {
        compare(Subtitles.cleanEventText("1,0,Default,,0,0,0,,{\\p1}m 0 0 l 100 0 100 100{\\p0}Text"), "Text");
    }

    function test_other_text_passes() {
        compare(Subtitles.cleanEventText("Plain subtitle"), "Plain subtitle");
        compare(Subtitles.cleanEventText("<i>SubRip</i> inside"), "<i>SubRip</i> inside");
        compare(Subtitles.cleanEventText(""), "");
    }

    // ---- shown ----

    function test_only_simple_markup_reaches_the_screen() {
        compare(Subtitles.toStyledText("<i>yes</i> <B>bold</B>"), "<i>yes</i> <b>bold</b>");
        compare(Subtitles.toStyledText("<font color=\"#ff0000\">red</font>"), "red");
        compare(Subtitles.toStyledText("<img src=x> & <a href=y>link</a>"),
                "&lt;img src=x&gt; &amp; &lt;a href=y&gt;link&lt;/a&gt;");
        compare(Subtitles.toStyledText("one\ntwo"), "one<br>two");
        compare(Subtitles.toStyledText(undefined), "");
    }
}
