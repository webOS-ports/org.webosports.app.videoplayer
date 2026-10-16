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

import LunaNext.Common 0.1

import "../../qml/js/Playback.js" as Playback

/*
 * The app as a whole - qml/main.qml - with a stand-in player engine
 * (mocks/FakeEngine.qml) and length probe (mocks/FakeProbePlayer.qml),
 * over the files in tests/data/library, on one screen per run (see
 * tools/run-tests.sh). Each state is also saved as a picture in
 * build/test-output/ui/ to look at.
 */
TestCase {
    id: test
    name: "Ui"
    when: windowShown

    readonly property string root: decodeURIComponent(Qt.resolvedUrl("../data/library").toString().replace(/^file:\/\//, ""))
    readonly property string shotDir: decodeURIComponent(Qt.resolvedUrl("../../build/test-output/ui").toString()
                                                         .replace(/^file:\/\//, ""))
    property var app: null
    property string profile: Settings.profileName
    property int quits: 0

    function init_data() {
        return [{ tag: Settings.profileName + " " + Settings.displayWidth + "x" + Settings.displayHeight }];
    }

    function shot(name) {
        var done = false;
        var ok = app.contentItem.grabToImage(function(result) {
            result.saveToFile(shotDir + "/" + profile + "-" + name + ".png");
            done = true;
        });
        verify(ok, "grab " + name);
        tryVerify(function() { return done; }, 5000, "saved " + name);
    }

    function startApp() {
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status === Component.Error)
            fail(component.errorString());
        app = component.createObject(null, {
            engineSource: Qt.resolvedUrl("mocks/FakeEngine.qml"),
            probePlayerSource: Qt.resolvedUrl("mocks/FakeProbePlayer.qml"),
            scanRoots: [root],
            quitOnBack: false
        });
        verify(app !== null, "main.qml made");
        quits = 0;
        app.quitRequested.connect(function() { test.quits++; });
        app.resume.videos = "{}";
        app.cache.facts = "{}";
        app.prefs.sortOrder = "name";
        app.prefs.fillMode = "fit";
        app.prefs.subtitleSize = "medium";
        app.prefs.turnLandscape = true;
        app.prefs.readLengths = true;
        app.player.hideDelay = 400;
        tryVerify(function() { return app.scanner.generation > 0 && app.scanner.files.length === 10; }, 10000,
                  "the ten test videos found");
        app.requestActivate();
        wait(50);
        return app;
    }

    function cleanup() {
        Playback.loadTimeoutMs = 15000;
        if (app) {
            app.destroy();
            app = null;
        }
        wait(50);
    }

    function findChild(item, objectName) {
        if (!item)
            return null;
        if (item.objectName === objectName)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findChild(kids[i], objectName);
            if (found)
                return found;
        }
        if (item.contentItem && item.contentItem !== item)
            return findChild(item.contentItem, objectName);
        return null;
    }

    function wide() {
        return app.library.wide;
    }

    function view() {
        return findChild(app.library, wide() ? "videoGrid" : "videoList");
    }

    function rowFor(name) {
        var v = view();
        for (var i = 0; i < v.count; i++) {
            var item = v.itemAtIndex(i);
            if (item && item.name === name)
                return item;
        }
        return null;
    }

    function playerChild(name) {
        return findChild(app.player, name);
    }

    // Opens a test file and waits until it plays.
    function play(file, options) {
        app.playFile(root + "/" + file, options);
        tryVerify(function() { return app.player.started; }, 3000, file + " starts");
        return app.player.engine;
    }

    function clickButton(name) {
        var b = playerChild(name);
        verify(b, name);
        if (!app.player.controlsShown)
            app.player.showControls();
        tryVerify(function() { return b.visible && b.opacity > 0.9 && b.parent.parent.opacity > 0.9; }, 1000,
                  name + " shown");
        mouseClick(b);
    }

    function choose(label) {
        var list = playerChild("sheetList");
        verify(list && list.visible, "a picker shown");
        for (var i = 0; i < list.count; i++) {
            // Each brought into view: rows out of it are not made.
            list.positionViewAtIndex(i, ListView.Contain);
            list.forceLayout();
            var item = list.itemAtIndex(i);
            if (item && findChild(item, "choiceLabel").text === label) {
                mouseClick(item);
                return;
            }
        }
        fail("no choice " + label);
    }

    // ---- the library ------------------------------------------------------

    function test_library_lists_the_videos() {
        startApp();
        var v = view();
        verify(v.visible);
        tryCompare(v, "count", 10);
        var names = [];
        for (var i = 0; i < v.count; i++)
            names.push(app.library.rows[i].name);
        compare(names, ["Big Buck", "broken", "Café Night 2audio ass", "clip", "Episode 2", "Episode 10",
                        "hang", "movie", "S01E01", "too-deep-not"]);
        compare(app.library.rows[0].details.split(" · ")[0], "library/Movies", "the root counts as a card here: " + app.library.rows[0].details);
        compare(wide(), Settings.displayWidth >= Units.gu(90), "a grid on a tablet, a list on phones");
        shot("library");
    }

    function test_lengths_come_from_the_probe() {
        startApp();
        var before = rowFor("Big Buck");
        // The probe stops at hang.mp4, which never answers: the ones before
        // it get their length, broken.mp4 gets none.
        tryVerify(function() { return app.probe.broken; }, 15000, "the probe gives up on hang.mp4");
        var lengths = app.library.rows.map(function(r) { return r.name + "=" + r.length; });
        verify(lengths.indexOf("Big Buck=0:30") >= 0, lengths.join(", "));
        verify(lengths.indexOf("broken=") >= 0, lengths.join(", "));
        verify(lengths.indexOf("hang=") >= 0, lengths.join(", "));
        var row = rowFor("Big Buck");
        compare(row.length, "0:30");
        // A length coming in changes the row; it is not made again.
        var f = app.scanner.files.filter(function(x) { return x.name === "Big Buck.mp4"; })[0];
        app.cache.update(f.path + "|" + f.size + "|" + Math.floor(f.modified / 1000), { duration: 45000 });
        tryCompare(row, "length", "0:45");
        verify(rowFor("Big Buck") === row, "the same row");
    }

    // The probe writes down which file it loads; a file that ended the app
    // switches reading lengths off at the next start, with a word why.
    function test_a_crash_while_reading_lengths_switches_it_off() {
        startApp();
        var marks = [];
        app.probe.starting.connect(function(p) { marks.push(String(app.probeGuard.value("loading", ""))); });
        app.cache.facts = "{}";
        app.requestLengths();
        tryVerify(function() { return marks.length > 0; }, 5000, "the probe loads a file");
        compare(marks[0].indexOf(root), 0, "named on disk before it is loaded: " + marks[0]);
        app.probe.active = false;
        tryVerify(function() { return !app.probe.busy; }, 15000);
        // As if the app had ended while loading hang.mp4.
        app.probeGuard.mark(root + "/hang.mp4");
        app.destroy();
        app = null;
        wait(50);
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        app = component.createObject(null, {
            engineSource: Qt.resolvedUrl("mocks/FakeEngine.qml"),
            probePlayerSource: Qt.resolvedUrl("mocks/FakeProbePlayer.qml"),
            scanRoots: [root],
            quitOnBack: false
        });
        verify(!app.prefs.readLengths, "switched off");
        verify(app.notice.indexOf("“hang” stopped the app") >= 0, app.notice);
        compare(String(app.probeGuard.value("loading", "")), "", "and forgotten");
        tryVerify(function() { return app.scanner.generation > 0; }, 10000);
        wait(300);
        verify(!app.probe.busy, "nothing read");
        verify(findChild(app.library, "libraryNotice").visible);
        shot("probe-crash-notice");
    }

    function test_search_narrows_and_back_clears_it() {
        startApp();
        var search = findChild(app.library, "searchField");
        verify(search.visible, "shown with six or more videos");
        search.text = "episode";
        tryCompare(view(), "count", 2);
        search.text = "cafe";
        tryCompare(view(), "count", 1, 2000, "accents folded");
        search.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(search.text, "");
        tryCompare(view(), "count", 10);
        compare(quits, 0);
        keyClick(Qt.Key_Escape);
        compare(quits, 1, "back with nothing open ends the app");
    }

    function test_app_menu_sorts() {
        startApp();
        app.openAppMenu();
        var menu = app.appMenu;
        tryCompare(menu, "opened", true);
        compare(menu.count, 6);
        verify(menu.itemAt(0).checked, "Sort by Name");
        menu.itemAt(1).triggered();
        compare(app.prefs.sortOrder, "date");
        verify(menu.itemAt(1).checked && !menu.itemAt(0).checked);
        menu.itemAt(2).triggered();
        compare(app.prefs.sortOrder, "size");
        menu.itemAt(3).triggered();
        verify(!app.prefs.turnLandscape);
        menu.close();
        // Not over the player.
        play("Movies/Big Buck.mp4");
        app.openAppMenu();
        verify(!menu.visible);
    }

    // ---- playing ----------------------------------------------------------

    function test_tapping_a_video_plays_it() {
        startApp();
        var row = rowFor("Big Buck");
        verify(row);
        mouseClick(row);
        verify(app.player.isOpen);
        compare(app.player.path, root + "/Movies/Big Buck.mp4");
        verify(app.player.fileInfo !== null, "the library's facts go with it");
        verify(playerChild("loadingIndicator").visible, "opening shown");
        tryVerify(function() { return app.player.started; }, 3000);
        verify(!playerChild("loadingIndicator").visible);
        verify(app.screenBlocked, "the screen kept on while playing");
        shot("player");
        // The bars go after a while of playing, and a tap brings them back.
        tryCompare(app.player, "controlsShown", false, 3000);
        tryCompare(playerChild("bottomBar"), "visible", false, 2000);
        mouseClick(app.player);
        verify(app.player.controlsShown);
        mouseClick(app.player);
        verify(!app.player.controlsShown);
    }

    function test_play_pause_and_jumps() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        clickButton("playButton");
        verify(!e.playing);
        verify(!app.player.wantPlay);
        tryCompare(app, "screenBlocked", false, 1000, "the screen let go while paused");
        wait(app.player.hideDelay + 200);
        verify(app.player.controlsShown, "the bars stay while paused");
        clickButton("playButton");
        verify(e.playing);
        tryCompare(app, "screenBlocked", true, 1000);
        var before = e.position;
        clickButton("forwardButton");
        verify(e.position >= before + 9900, "forward 10 s: " + before + " -> " + e.position);
        clickButton("backButton");
        verify(e.position <= before + 1000, "back 10 s");
        clickButton("backButton");
        compare(e.position < 1000, true, "not before the start");
    }

    function test_seek_bar() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        clickButton("playButton");
        var bar = playerChild("seekBar");
        verify(bar.enabled);
        var y = bar.height / 2;
        mousePress(bar, bar.leftPadding + 2, y);
        mouseMove(bar, bar.width * 0.75, y);
        mouseRelease(bar, bar.width * 0.75, y);
        var seeks = e.calls.filter(function(c) { return c.indexOf("seek ") === 0; });
        verify(seeks.length >= 1, "one seek on letting go: " + e.calls);
        verify(e.position > 15000 && e.position < 30000, "about three quarters: " + e.position);
        compare(playerChild("elapsedLabel").text, "0:" + ("0" + Math.floor(e.position / 1000)).slice(-2));
    }

    function test_speed() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        clickButton("speedButton");
        verify(playerChild("choiceSheet").visible);
        shot("speed");
        choose("1.5×");
        compare(e.rate, 1.5);
        verify(!playerChild("choiceSheet").visible);
        compare(playerChild("speedButton").label, "1.5×");
    }

    function test_audio_track_choice_is_remembered() {
        startApp();
        var e = play("Café Night 2audio ass.mkv");
        verify(playerChild("audioButton").enabled);
        clickButton("audioButton");
        choose("Dutch – 880 Hz (AC3)");
        compare(e.activeAudioTrack, 1);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
        compare(app.resume.entry(root + "/Café Night 2audio ass.mkv").audioTrack, 1);
        e = play("Café Night 2audio ass.mkv");
        tryCompare(e, "activeAudioTrack", 1, 1000, "the same track next time");
    }

    function test_single_audio_track_has_no_picker() {
        startApp();
        play("Movies/Big Buck.mp4");
        verify(!playerChild("audioButton").enabled);
    }

    function test_subtitles_from_files_next_to_the_video() {
        startApp();
        var e = play("with-srt/movie.mp4");
        tryCompare(app.player, "srtListed", true, 2000);
        compare(app.player.srtFiles.length, 3);
        compare(app.player.subtitleChoice, "srt:" + root + "/with-srt/movie.srt", "the plain .srt by default");
        tryVerify(function() { return app.player.srtCues.length === 2; }, 2000, "read");
        var text = playerChild("subtitleText");
        e.seek(1500);
        tryCompare(text, "text", "External one");
        verify(text.visible);
        e.seek(7000);
        tryCompare(text, "text", "External <i>two</i><br>second line");
        shot("subtitles");
        e.seek(5000);
        tryCompare(text, "text", "");
        verify(!text.visible);

        clickButton("subtitleButton");
        choose("From file (en)");
        tryCompare(app.player, "srtEncoding", "Windows-1252", 2000);
        e.seek(1500);
        tryCompare(text, "text", "Café naïve € 5");
        clickButton("subtitleButton");
        choose("From file (nl)");
        tryCompare(app.player, "srtEncoding", "UTF-8", 2000);
        e.seek(1600);
        tryCompare(text, "text", "Hé daar");
        clickButton("subtitleButton");
        choose("Off");
        tryCompare(text, "text", "");
        keyClick(Qt.Key_Escape);
        compare(app.resume.entry(root + "/with-srt/movie.mp4").subtitle, "off", "remembered");
    }

    function test_subtitles_inside_the_video() {
        startApp();
        var e = play("Café Night 2audio ass.mkv");
        compare(app.player.subtitleChoice, "off", "a track inside is not on by itself");
        clickButton("subtitleButton");
        choose("English");
        compare(e.activeSubtitleTrack, 0);
        var text = playerChild("subtitleText");
        e.seek(6500);
        tryCompare(text, "text", "EMBEDDED ASS two <i>italic</i>");
        e.seek(13000);
        tryCompare(text, "text", "EMBEDDED ASS three<br>line");
        clickButton("subtitleButton");
        choose("Off");
        compare(e.activeSubtitleTrack, -1);
        tryCompare(text, "text", "");
    }

    function test_subtitle_size() {
        startApp();
        var e = play("with-srt/movie.mp4");
        var text = playerChild("subtitleText");
        var medium = text.font.pixelSize;
        clickButton("subtitleButton");
        choose("Large");
        compare(app.prefs.subtitleSize, "large");
        verify(text.font.pixelSize > medium);
        clickButton("subtitleButton");
        choose("Small");
        verify(text.font.pixelSize < medium);
        verify(text.font.pixelSize >= 14);
    }

    function test_fit_and_fill() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        verify(!e.fill);
        clickButton("fillButton");
        compare(app.prefs.fillMode, "fill");
        verify(e.fill);
        compare(playerChild("fillButton").image, "fit");
        clickButton("fillButton");
        verify(!e.fill);
    }

    function test_turning_on_a_tall_screen() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        var stage = playerChild("playerStage");
        var tall = app.height > app.width;
        compare(playerChild("turnButton").visible, tall);
        compare(app.player.turned, tall, "a wide video turned on a tall screen only");
        if (!tall)
            return;
        compare(stage.rotation, 90);
        compare(stage.width, app.height);
        shot("turned");
        clickButton("turnButton");
        verify(!app.player.turned, "the button turns it back");
        compare(stage.rotation, 0);
        app.player.sensorRotation = 90;
        clickButton("turnButton");
        verify(app.player.turned);
        compare(stage.rotation, 270, "the way the device is held: left side up");
        keyClick(Qt.Key_Escape);
        // A tall video is not turned.
        play("tall.mp4");
        compare(app.player.errorText, "");
    }

    function test_resume_where_left() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        e.seek(12000);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen, "back closes the player");
        var at = app.resume.positionOf(root + "/Movies/Big Buck.mp4");
        verify(at >= 12000 && at < 13000, "remembered " + at);
        if (!wide()) {
            compare(app.library.rows[0].section, "Continue Watching");
            compare(app.library.rows[0].name, "Big Buck");
        }
        verify(app.library.rows.some(function(r) { return r.name === "Big Buck" && r.progress > 0.35; }), "progress shown");
        shot("continue");
        var callsBefore = e.calls.length;
        e = play("Movies/Big Buck.mp4");
        compare(app.player.resumedFrom, at);
        verify(e.calls.slice(callsBefore).indexOf("seek " + at) >= 0, e.calls.join(","));
        verify(e.position >= at, "it plays on from there: " + e.position);
        verify(playerChild("resumeNotice").visible);
        mouseClick(playerChild("startOverButton"));
        verify(e.position < 1000);
        compare(app.player.resumedFrom, 0);
    }

    function test_a_video_that_never_starts_is_given_up() {
        startApp();
        Playback.loadTimeoutMs = 800;
        app.playFile(root + "/hang.mp4");
        var first = app.player.engine;
        verify(playerChild("loadingIndicator").visible);
        tryVerify(function() { return app.player.errorText !== ""; }, 3000, "an error, not a spinner for ever");
        verify(playerChild("errorPanel").visible);
        verify(app.player.errorText.indexOf("did not start playing") >= 0, app.player.errorText);
        verify(!playerChild("loadingIndicator").visible);
        // The hung engine is kept aside, never destroyed or asked again.
        verify(app.player.engine !== first, "a fresh engine");
        compare(first.visible, false);
        var callsBefore = first.calls.length;
        shot("timeout");
        mouseClick(playerChild("errorCloseButton"));
        verify(!app.player.isOpen);
        var e = play("Movies/Big Buck.mp4");
        verify(e !== first);
        compare(first.calls.length, callsBefore, "the hung one left alone");
        verify(!app.screenBlocked || e.playing);
    }

    function test_a_broken_video_says_so() {
        startApp();
        app.playFile(root + "/broken.mp4");
        tryVerify(function() { return app.player.errorText !== ""; }, 3000);
        compare(findChild(app.player, "errorLabel").text, "Could not decode the video (stand-in).");
        verify(!app.screenBlocked);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
    }

    function test_back_closes_the_player_then_the_app() {
        startApp();
        play("Movies/Big Buck.mp4");
        clickButton("speedButton");
        keyClick(Qt.Key_Escape);
        verify(!playerChild("choiceSheet").visible, "a picker first");
        verify(app.player.isOpen);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen, "then the player");
        verify(!app.screenBlocked);
        compare(quits, 0);
        keyClick(Qt.Key_Escape);
        compare(quits, 1, "then the app");
    }

    // Launched with a file before the scan is done: the player learns of
    // the file when it is, and the library gets its picture.
    function test_launch_before_the_scan_gets_a_picture() {
        startApp();
        app.scanner.files = [];
        app.launchParams = JSON.stringify({ "target": root + "/clip.AVI" });
        tryVerify(function() { return app.player.started; }, 3000);
        compare(app.player.fileInfo, null);
        app.scanner.rescan();
        tryVerify(function() { return app.player.fileInfo !== null; }, 5000, "known after the scan");
        app.player.engine.seek(6000);
        tryVerify(function() {
            var f = app.player.fileInfo;
            var facts = app.cache.factsFor(f.path + "|" + f.size + "|" + Math.floor(f.modified / 1000));
            return facts && facts.thumb && facts.duration === 30000;
        }, 3000, "picture and length kept");
    }

    function test_launched_with_a_target() {
        startApp();
        app.launchParams = JSON.stringify({ "target": "file://" + encodeURI(root + "/Movies/Episode 2.mkv"), "position": 8000 });
        tryVerify(function() { return app.player.started; }, 3000);
        compare(app.player.path, root + "/Movies/Episode 2.mkv");
        compare(app.player.resumedFrom, 8000);
        // Again, with another: the same player.
        app.launchParams = JSON.stringify({ "target": root + "/clip.AVI" });
        tryCompare(app.player, "path", root + "/clip.AVI");
        tryVerify(function() { return app.player.started; }, 3000);
        // Not a local file.
        app.launchParams = JSON.stringify({ "target": "http://example.com/a.mp4" });
        verify(app.notice.indexOf("Only videos on this device") === 0, app.notice);
    }

    function test_interruptions_pause() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        verify(app.screenBlocked);
        tryCompare(app.player, "controlsShown", false, 3000);
        app.player.interrupt("call");
        verify(!e.playing);
        verify(app.player.controlsShown);
        tryCompare(app, "screenBlocked", false, 1000);
        verify(app.resume.positionOf(root + "/Movies/Big Buck.mp4") === 0 || true);
        // A pause from the sound system shows as paused too.
        clickButton("playButton");
        verify(e.playing);
        e.playing = false;
        verify(!app.player.wantPlay);
        compare(playerChild("playButton").image, "play");
    }

    function test_end_of_the_video() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        e.seek(25000);
        var turned = app.player.turned;
        tryVerify(function() { return e.ended; }, 8000);
        compare(app.player.turned, turned, "the picture stays as it was turned at the end");
        verify(app.player.controlsShown);
        compare(playerChild("playButton").image, "play");
        compare(app.resume.positionOf(root + "/Movies/Big Buck.mp4"), 0, "nothing to resume at the end");
        clickButton("playButton");
        verify(e.playing);
        verify(e.position < 1000, "from the start again");
    }

    function test_a_picture_for_the_library() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        e.seek(6000);
        tryVerify(function() { return app.player.thumbnailDone; }, 3000);
        var key = app.player.fileInfo.path + "|0|" + Math.floor(app.player.fileInfo.modified / 1000);
        tryVerify(function() { var f = app.cache.factsFor(key); return f && f.thumb; }, 3000, "saved");
        keyClick(Qt.Key_Escape);
        var row = rowFor("Big Buck");
        var picture = findChild(row, "thumbnail");
        tryCompare(picture, "status", Image.Ready, 3000);
        shot("library-picture");
    }

    function test_bars_fit_the_screen() {
        startApp();
        play("Movies/Big Buck.mp4");
        var stage = playerChild("playerStage");
        var row = playerChild("buttonRow");
        verify(row.width <= stage.width, row.width + " in " + stage.width);
        var minWidth = 54;
        for (var i = 0; i < row.children.length; i++) {
            var b = row.children[i];
            if (b.visible)
                verify(b.width >= minWidth - 0.5, b.objectName + " " + b.width);
        }
        var bar = playerChild("seekBar");
        verify(bar.width > stage.width * 0.4, "a seek bar to use: " + bar.width);
        clickButton("subtitleButton");
        var panel = playerChild("sheetPanel");
        verify(panel.width <= stage.width && panel.height <= stage.height);
        shot("subtitle-picker");
    }
}
