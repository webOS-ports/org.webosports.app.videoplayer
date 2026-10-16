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
import QtTest

import "../../qml/js/Playback.js" as Playback

/*
 * qml/js/Playback.js: resuming, giving up on a start, speeds, jumps,
 * track names.
 */
TestCase {
    name: "Playback"

    function test_worth_resuming() {
        verify(Playback.worthResuming(12000, 600000));
        verify(!Playback.worthResuming(1000, 600000), "just started");
        verify(!Playback.worthResuming(597000, 600000), "at the end");
        verify(Playback.worthResuming(10000, 30000), "a short clip half way");
        verify(!Playback.worthResuming(4000, 7000), "too short to bother");
    }

    function test_remember_and_resume() {
        var store = Playback.remember({}, "/a.mp4", { position: 12345.6, duration: 30000, at: 10,
                                                      audioTrack: 1, subtitle: "track:0" });
        compare(Playback.resumePosition(store, "/a.mp4"), 12345);
        compare(store["/a.mp4"].audioTrack, 1);
        compare(store["/a.mp4"].subtitle, "track:0");
        // Played to the end: the position goes, the choices stay.
        store = Playback.remember(store, "/a.mp4", { position: 29900, duration: 30000, at: 20 });
        compare(Playback.resumePosition(store, "/a.mp4"), 0);
        compare(store["/a.mp4"].audioTrack, 1);
        compare(store["/a.mp4"].subtitle, "track:0");
        compare(Playback.resumePosition(store, "/never.mp4"), 0);
        store = Playback.forget(store, "/a.mp4");
        compare(store["/a.mp4"], undefined);
    }

    function test_remember_does_not_change_the_old_store() {
        var old = {};
        var store = Playback.remember(old, "/a.mp4", { position: 10000, duration: 30000 });
        compare(Object.keys(old).length, 0);
        verify(store["/a.mp4"].at > 0, "stamped with the time");
    }

    function test_only_the_most_recent_are_kept() {
        var store = {};
        for (var i = 0; i < Playback.maxRemembered + 5; i++)
            store = Playback.remember(store, "/v" + i + ".mp4", { position: 10000, duration: 30000, at: 1000 + i });
        compare(Object.keys(store).length, Playback.maxRemembered);
        compare(store["/v0.mp4"], undefined, "the oldest went");
        verify(store["/v" + (Playback.maxRemembered + 4) + ".mp4"] !== undefined);
    }

    function test_continue_watching() {
        var store = {};
        store = Playback.remember(store, "/old.mp4", { position: 10000, duration: 30000, at: 100 });
        store = Playback.remember(store, "/new.mp4", { position: 15000, duration: 30000, at: 300 });
        store = Playback.remember(store, "/done.mp4", { position: 30000, duration: 30000, at: 400 });
        store = Playback.remember(store, "/gone.mp4", { position: 15000, duration: 30000, at: 200 });
        var list = Playback.continueWatching(store, function(p) { return p !== "/gone.mp4"; });
        compare(list.map(function(e) { return e.path; }), ["/new.mp4", "/old.mp4"]);
        compare(Playback.continueWatching(store, null, 1).length, 1);
    }

    function test_parse_store_survives_junk() {
        compare(Playback.parseStore("not json"), {});
        compare(Playback.parseStore("[1,2]"), {});
        compare(Playback.parseStore(""), {});
    }

    function test_started_means_a_picture() {
        verify(!Playback.hasStarted(true, 0, true, 500), "playing with no picture yet");
        verify(Playback.hasStarted(true, 1, true, 0));
        verify(!Playback.hasStarted(false, 1, true, 0), "not while it does not play");
        verify(Playback.hasStarted(true, 0, false, 40), "sound only: the clock moving");
        verify(!Playback.hasStarted(true, 0, false, 0));
    }

    function test_load_timeout() {
        verify(!Playback.loadTimedOut(1000, 1000 + Playback.loadTimeoutMs - 1, false));
        verify(Playback.loadTimedOut(1000, 1000 + Playback.loadTimeoutMs, false));
        verify(!Playback.loadTimedOut(1000, 1000 + Playback.loadTimeoutMs * 2, true), "it started");
        verify(!Playback.loadTimedOut(0, 999999, false), "not asked to play");
        compare(Playback.loadTimeoutMs, 15000);
    }

    function test_rates() {
        compare(Playback.nextRate(1.0), 1.25);
        compare(Playback.nextRate(2.0), 0.5);
        compare(Playback.nextRate(0.6), 0.75);
        verify(Playback.rates.indexOf(1.0) >= 0);
    }

    function test_jumps_stay_inside() {
        compare(Playback.jumpTarget(5000, -10000, 30000), 0);
        compare(Playback.jumpTarget(5000, 10000, 30000), 15000);
        compare(Playback.jumpTarget(25000, 10000, 30000), 29000, "not to the very end");
        compare(Playback.jumpTarget(25000, 10000, 0), 35000, "no length known");
    }

    function test_turn_follows_the_hand() {
        compare(Playback.turnAngle(90), 270, "left side up: the top to the left");
        compare(Playback.turnAngle(270), 90, "right side up: the top to the right");
        compare(Playback.turnAngle(-1), 90);
        compare(Playback.turnAngle(0), 90);
    }

    function test_track_labels() {
        compare(Playback.trackLabel("English", "440 Hz", "AAC", 0), "English – 440 Hz (AAC)");
        compare(Playback.trackLabel("Default", "", "AC3", 0), "Track 1 (AC3)");
        compare(Playback.trackLabel("", "", "", 2), "Track 3");
        compare(Playback.trackLabel("Dutch", "Dutch", "", 1), "Dutch");
    }
}
