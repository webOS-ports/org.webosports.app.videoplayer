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

import "../../qml/js/Online.js" as Online

/*
 * What Videos makes of the video service's answers (qml/js/Online.js).
 */
TestCase {
    name: "Online"

    readonly property var episode: ({ id: "e2", kind: "episode", title: "The Second", seriesTitle: "Test Show", season: 1, episode: 2,
                                      durationMs: 60000, progress: { positionMs: 15000, watched: false }, playable: true,
                                      artwork: { poster: "http://s/p.jpg", thumb: "http://s/t.jpg" } })

    function test_keys_name_the_source_and_item() {
        compare(Online.itemKey("acc|uuid-1", "64$0$1"), "videos:acc|uuid-1/64$0$1");
        compare(Online.parseKey("videos:acc|uuid-1/64$0$1/x"), { sourceId: "acc|uuid-1", itemId: "64$0$1/x" });
        compare(Online.parseKey("/media/internal/a.mp4"), null);
        compare(Online.parseKey("videos:acc"), null);
        compare(Online.parseKey("videos:/x"), null);
        compare(Online.parseKey("videos:acc/"), null);
    }

    function test_titles() {
        compare(Online.titleOf(episode), "Test Show S1E2 – The Second");
        compare(Online.titleOf({ kind: "episode", title: "Pilot" }), "Pilot", "no show known");
        compare(Online.titleOf({ kind: "movie", title: "Night Train" }), "Night Train");
        compare(Online.titleOf(null), "");
    }

    function test_the_stream_for_the_player() {
        var s = Online.playStreamFor("acc", episode, { url: "http://s/v.m3u8", startMs: 0, subtitles: [
            { url: "http://s/en.vtt", lang: "en", format: "vtt", default: true },
            { url: "file:///etc/passwd", label: "no" },
            { url: "https://s/nl.srt", label: "Dutch", format: "srt" }] });
        compare(s, { url: "http://s/v.m3u8", title: "Test Show S1E2 – The Second", key: "videos:acc/e2", startMs: 15000,
                     subtitles: [{ url: "http://s/en.vtt", label: "en", lang: "en", format: "vtt", default: true },
                                 { url: "https://s/nl.srt", label: "Dutch", lang: "", format: "srt", default: false }] });
        compare(Online.playStreamFor("acc", episode, { url: "http://s/v", startMs: 30000 }).startMs, 30000, "the stream's own wins");
        compare(Online.playStreamFor("acc", { id: "m", title: "M" }, { url: "http://s/v" }).startMs, 0);
        verify(Online.playStreamFor("acc", episode, { url: "http://s/v" }).live === undefined);
    }

    function test_a_channel_is_live_and_starts_now() {
        var ch = { id: "ch1", kind: "live", title: "Channel One", progress: { positionMs: 5000 } };
        compare(Online.playStreamFor("acc", ch, { url: "http://s/ch1.m3u8", startMs: 9000, subtitles: [] }),
                { url: "http://s/ch1.m3u8", title: "Channel One", key: "videos:acc/ch1", startMs: 0, subtitles: [], live: true });
    }

    function test_progress_reports() {
        compare(Online.progressArgs("a", "i", 1234.4, 60000, "paused", { s: 1 }),
                { sourceId: "a", itemId: "i", positionMs: 1234, durationMs: 60000, state: "paused", session: { s: 1 } });
        compare(Online.progressArgs("a", "i", 0, 60000, "ended", null).positionMs, 60000, "the end counts as watched");
        compare(Online.progressArgs("a", "i", -5, 0, "ended", null).positionMs, 0);
        verify(Online.progressArgs("a", "i", 1, 2, "playing", null).session === undefined);
    }

    function test_neighbours_skip_what_does_not_play() {
        var list = [{ id: "1", playable: true }, { id: "x", playable: false }, { id: "2", playable: true }];
        compare(Online.neighbour(list, "1", 1).id, "2");
        compare(Online.neighbour(list, "2", -1).id, "1");
        compare(Online.neighbour(list, "2", 1), null);
        compare(Online.neighbour(list, "1", -1), null);
        compare(Online.neighbour(list, "zz", 1), null);
        compare(Online.neighbour(null, "1", 1), null);
    }

    function test_tiles() {
        compare(Online.detailsOf({ subtitle: "Test Show", year: 2024 }), "Test Show");
        compare(Online.detailsOf({ year: 2024 }), "2024");
        compare(Online.detailsOf({}), "");
        compare(Online.progressOf(episode), 0.25);
        compare(Online.progressOf({ progress: { watched: true } }), 1);
        compare(Online.progressOf({ durationMs: 10, progress: { positionMs: 50 } }), 1);
        compare(Online.progressOf({ progress: { positionMs: 5 } }), -1, "no length, no bar");
        compare(Online.progressOf({}), -1);
        compare(Online.pictureOf(episode, true), "http://s/t.jpg");
        compare(Online.pictureOf(episode, false), "http://s/p.jpg");
        compare(Online.pictureOf({ artwork: { backdrop: "http://s/b.jpg" } }, true), "http://s/b.jpg");
        compare(Online.pictureOf({ artwork: { thumb: "http://s/t.jpg" } }, false), "http://s/t.jpg");
        compare(Online.pictureOf({}, true), "");
    }

    function test_error_texts() {
        verify(/Accounts/.test(Online.errorText({ errorCode: "AUTH_EXPIRED" })));
        verify(/protected/.test(Online.errorText({ errorCode: "DRM_REQUIRED" })));
        verify(/network/.test(Online.errorText({ errorCode: "SERVER_UNREACHABLE" })));
        compare(Online.errorText({ errorCode: "SERVER_ERROR", errorText: "The server answered with an error (500)." }),
                "The server answered with an error (500).");
        compare(Online.errorText({}), "The video service does not answer.");
        compare(Online.errorText(null), "The video service does not answer.");
        compare(Online.errorText({ errorCode: "ODD" }), "Something went wrong (ODD).");
        compare(Online.errorText({ errorCode: "ODD", errorText: "Odd." }), "Odd.");
        compare(Online.errorText({ errorCode: -1, errorText: "Unknown service" }), "The video service does not answer.");
    }

    function test_pages_add_on_without_repeats() {
        var a = [{ id: "1" }, { id: "2" }];
        compare(Online.appendPage(a, { items: [{ id: "2" }, { id: "3" }, { id: "3" }] }).map(function(x) { return x.id; }), ["1", "2", "3"]);
        compare(a.length, 2, "the old list is left as it was");
        compare(Online.appendPage(a, null).length, 2);
    }

    function test_home_entries() {
        compare(Online.homeEntries([{ id: "c", title: "Continue", layout: "row" }, { id: "v", title: "Movies", layout: "odd" }]),
                [{ id: "v", title: "Movies", layout: "grid" }, { id: "c", title: "Continue", layout: "row" }],
                "the libraries on top");
        compare(Online.homeEntries([{ id: "c", layout: "row" }, { id: "m", layout: "grid" }, { id: "r", layout: "row" },
                                    { id: "s", layout: "grid" }]).map(function(s) { return s.id; }),
                ["m", "s", "c", "r"], "each group in the server's order");
        compare(Online.homeEntries(undefined), []);
    }
}
