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
import QtQuick.Controls
import QtQuick.Controls.LuneOS 2.0
import Qt.labs.folderlistmodel

import LunaNext.Common 0.1

import "components"
import "js/Format.js" as Format
import "js/Library.js" as Library
import "js/Playback.js" as Playback
import "js/Subtitles.js" as Subtitles

/*
 * The player: the video over the whole card, with its bars shown by a tap
 * and gone again after a few seconds of playing; a double tap switches
 * between all of the picture (fit) and the screen filled (cropped).
 *
 * The bars: the name at the top; below, the time and seek bar, then the
 * audio track and subtitle pickers, back 10 s, play/pause, forward 10 s,
 * the speed, fullscreen in and out and, on a tall screen, turning the
 * picture.
 *
 * Starting is watched: a video that has not shown its first picture
 * Playback.loadTimeoutMs after it was asked to play is given up on with a
 * message, and its engine is set aside for a new one (see engineHost).
 */
FocusScope {
    id: view
    objectName: "playerView"

    // The engine type (VideoEngine.qml; the tests give a stand-in).
    property url engineSource: Qt.resolvedUrl("VideoEngine.qml")
    property var prefs: null
    property var resume: null
    property var cache: null

    readonly property var engine: engineHost.engine
    property string path: ""
    // {path, name, size, modified} from the library, when it knows the file.
    property var fileInfo: null
    readonly property bool isOpen: path !== ""
    onFileInfoChanged: {
        if (fileInfo && started && cache && engine && engine.duration > 0)
            cache.update(Library.cacheKey(fileInfo), { duration: engine.duration });
    }
    readonly property string title: Library.displayName(path)

    // Log what happens as "VIDEOPLAYER {json}" lines, for tools/test-device.sh.
    property bool report: false

    property bool wantPlay: false
    property double loadStartedAt: 0
    property bool started: false
    property string errorText: ""
    property int resumedFrom: 0
    property bool controlsShown: true
    property bool thumbnailDone: false

    // Subtitles: "off", "srt:<path>" or "track:<n>".
    property string subtitleChoice: "off"
    property var srtFiles: []
    property var srtCues: []
    property string srtEncoding: ""
    property bool srtListed: false
    property var savedEntry: null

    // Turning a landscape video on a tall screen: automatic (prefs), or as
    // the turn button last said for this video.
    property var turnOverride: null
    property int sensorRotation: orientationLoader.item ? orientationLoader.item.angle : -1
    readonly property bool tallScreen: height > width
    // Kept once known: the picture's size is gone again when the video ends
    // or stops, and the player should not turn back then.
    property bool landscapeVideo: false
    Connections {
        target: view.engine
        function onVideoSizeChanged() {
            var s = view.engine.videoSize;
            if (s.width > 0 && s.height > 0)
                view.landscapeVideo = s.width > s.height;
        }
    }
    readonly property bool turned: tallScreen && (turnOverride !== null ? turnOverride
                                                   : (prefs !== null && prefs.turnLandscape && landscapeVideo))
    property int turnAngle: 90

    signal closed()

    visible: isOpen

    // ---- opening and closing ------------------------------------------------

    // options: {position, subtitle ("off", "srt", "track:<n>"), audioTrack,
    // rate, report}, mostly for tests; without them the remembered state.
    function open(newPath, options) {
        options = options || {};
        if (isOpen)
            saveState();
        if (!engineHost.engine)
            engineHost.make();
        path = newPath;
        report = options.report === true;
        started = false;
        errorText = "";
        resumedFrom = 0;
        thumbnailDone = false;
        turnOverride = null;
        landscapeVideo = false;
        srtFiles = [];
        srtCues = [];
        srtEncoding = "";
        srtListed = false;
        sheet.hide();
        savedEntry = resume ? resume.entry(newPath) : null;
        pendingOptions = options;
        subtitleChoice = "off";

        var e = engineHost.engine;
        e.rate = options.rate > 0 ? options.rate : 1.0;
        e.activeSubtitleTrack = -1;
        e.activeAudioTrack = 0;
        e.countFrames = report;
        e.source = Library.fileUrl(newPath);
        play();
        showControls();
        srtFolder.folder = Library.fileUrl(newPath.substring(0, newPath.lastIndexOf("/")) || "/");
        log("open", {});
        view.forceActiveFocus();
    }
    property var pendingOptions: ({})

    function close() {
        if (!isOpen)
            return;
        saveState();
        log("close", { position: engine ? engine.position : 0 });
        if (engine)
            engine.stop();
        wantPlay = false;
        path = "";
        fileInfo = null;
        closed();
    }

    // The back gesture: a sheet first, then the player.
    function handleBack() {
        if (sheet.shown) {
            sheet.hide();
            return true;
        }
        if (isOpen) {
            close();
            return true;
        }
        return false;
    }

    // Commands from a launch, for driving the player from a test over the
    // bus: {"seek": ms, "rate": r, "audioTrack": n, "subtitle": "off" |
    // "srt" | "track:<n>", "pause": true, "play": true, "close": true,
    // "fullScreen": bool, "fill": bool}; the last two as the fullscreen
    // button and a double tap would leave them.
    function command(c) {
        if (!isOpen || !c)
            return;
        log("command", { command: c });
        if (typeof c.seek === "number" && engine)
            engine.seek(c.seek);
        if (typeof c.rate === "number" && c.rate > 0 && engine)
            engine.rate = c.rate;
        if (typeof c.audioTrack === "number" && engine)
            engine.activeAudioTrack = c.audioTrack;
        if (typeof c.subtitle === "string")
            chooseSubtitles(c.subtitle === "srt" ? (srtFiles.length ? "srt:" + srtFiles[0] : "off") : c.subtitle);
        if (typeof c.fullScreen === "boolean" && prefs && c.fullScreen !== prefs.fullScreen)
            toggleFullScreen();
        if (typeof c.fill === "boolean" && prefs && c.fill !== (prefs.fillMode === "fill"))
            toggleFill();
        if (c.pause === true)
            pause();
        if (c.play === true)
            play();
        if (c.close === true)
            close();
    }

    // ---- playing ------------------------------------------------------------

    function play() {
        if (!engine || errorText !== "")
            return;
        if (engine.ended)
            engine.seek(0);
        wantPlay = true;
        if (!started)
            loadStartedAt = Date.now();
        engine.play();
    }

    function pause() {
        wantPlay = false;
        if (!started)
            loadStartedAt = 0;
        if (engine)
            engine.pause();
        showControls();
        saveState();
    }

    function togglePlay() {
        if (wantPlay && engine && !engine.ended)
            pause();
        else
            play();
    }

    // Paused by something else (the card put away, a call): the bars shown,
    // and it stays paused.
    function interrupt(reason) {
        if (!isOpen || !wantPlay)
            return;
        log("interrupted", { reason: reason });
        pause();
    }

    function jump(deltaMs) {
        if (!engine || !engine.seekable)
            return;
        engine.seek(Playback.jumpTarget(engine.position, deltaMs, engine.duration));
        showControls();
    }

    function showControls() {
        controlsShown = true;
        hideTimer.restart();
    }

    // How long the bars stay up while playing.
    property int hideDelay: 5000

    Timer {
        id: hideTimer
        interval: view.hideDelay
        onTriggered: {
            if (view.engine && view.engine.playing && view.started && !sheet.shown)
                view.controlsShown = false;
        }
    }

    // ---- watching the start -------------------------------------------------

    Timer {
        id: watchdog
        interval: 250
        repeat: true
        running: view.isOpen && !view.started && view.errorText === ""
        onTriggered: {
            var e = view.engine;
            if (!e)
                return;
            if (e.errorText !== "") {
                view.fail(e.errorText);
            } else if (Playback.hasStarted(e.playing, e.framesShown, e.hasVideo, e.position)) {
                view.onStartedPlaying();
            } else if (view.wantPlay && Playback.loadTimedOut(view.loadStartedAt, Date.now(), false)) {
                view.log("timeout", { ms: Date.now() - view.loadStartedAt });
                view.fail("“" + view.title + "” did not start playing within "
                          + Math.round(Playback.loadTimeoutMs / 1000) + " seconds. This device may not be able "
                          + "to play this kind of video.");
                // Its pipeline may be stuck for good: never touched again.
                engineHost.setAside();
            }
        }
    }

    function fail(text) {
        errorText = text;
        wantPlay = false;
        controlsShown = true;
        log("error", { text: text });
    }

    Connections {
        target: view.engine
        function onErrorTextChanged() {
            if (view.isOpen && view.engine.errorText !== "" && view.errorText === "")
                view.fail(view.engine.errorText);
        }
        function onEndedChanged() {
            if (view.isOpen && view.engine.ended) {
                view.wantPlay = false;
                view.controlsShown = true;
                view.log("ended", {});
                view.saveState();
            }
        }
        function onPlayingChanged() {
            // Paused from outside (the sound system giving the speaker to a
            // call or an alarm pauses the stream): show where it stopped.
            if (view.isOpen && view.started && !view.engine.playing && view.wantPlay && !view.engine.ended) {
                view.wantPlay = false;
                view.controlsShown = true;
                view.saveState();
            }
            if (view.isOpen && view.engine.playing && view.started) {
                view.wantPlay = true;
                hideTimer.restart();
            }
        }
    }

    function onStartedPlaying() {
        started = true;
        var e = engine;
        var opts = pendingOptions || {};
        var at = opts.position !== undefined ? opts.position
                                             : (savedEntry && savedEntry.position > 0 ? savedEntry.position : 0);
        if (at > 0 && (e.duration <= 0 || at < e.duration - 1000)) {
            e.seek(at);
            resumedFrom = at;
            resumeNoticeTimer.restart();
        }
        var audio = opts.audioTrack !== undefined ? opts.audioTrack : (savedEntry ? savedEntry.audioTrack : undefined);
        if (audio !== undefined && audio > 0 && audio < e.audioTracks.length)
            e.activeAudioTrack = audio;
        applyDefaultSubtitles();
        hideTimer.restart();
        if (fileInfo && cache && e.duration > 0)
            cache.update(Library.cacheKey(fileInfo), { duration: e.duration });
        log("started", { ms: Date.now() - loadStartedAt, duration: e.duration, hasVideo: e.hasVideo,
                         audioTracks: e.audioTracks, subtitleTracks: e.subtitleTracks,
                         video: [e.videoSize.width, e.videoSize.height], resumedFrom: resumedFrom });
    }

    Timer {
        id: resumeNoticeTimer
        interval: 6000
    }

    // ---- remembering --------------------------------------------------------

    function saveState() {
        if (!isOpen || !started || !resume || !engine)
            return;
        resume.remember(path, {
            position: engine.ended ? 0 : engine.position,
            duration: engine.duration,
            audioTrack: engine.activeAudioTrack,
            subtitle: subtitleChoice
        });
    }

    // Now and then while playing, so a crash or a kill loses little.
    Timer {
        interval: 10000
        repeat: true
        running: view.isOpen && view.started && view.wantPlay
        onTriggered: view.saveState()
    }

    // A picture for the library, a few seconds in.
    Timer {
        interval: 500
        repeat: true
        running: view.isOpen && view.started && !view.thumbnailDone && view.fileInfo !== null && view.cache !== null
        onTriggered: {
            var e = view.engine;
            if (!e.hasVideo || e.framesShown === 0) {
                if (!e.hasVideo)
                    view.thumbnailDone = true;
                return;
            }
            if (e.position < Math.min(5000, e.duration * 0.2))
                return;
            view.thumbnailDone = true;
            var key = Library.cacheKey(view.fileInfo);
            var facts = view.cache.factsFor(key);
            if (facts && facts.thumb)
                return;
            view.cache.ensureFolder();
            var name = Qt.md5(key) + ".jpg";
            e.grabPicture(view.cache.folder + "/" + name, Qt.size(Units.gu(24), Units.gu(13.5)), function(ok) {
                if (ok)
                    view.cache.update(key, { thumb: name });
                view.log("thumbnail", { ok: ok });
            });
        }
    }

    // ---- subtitles ----------------------------------------------------------

    // The video's folder, for SubRip files named after it.
    FolderListModel {
        id: srtFolder
        showDirs: false
        showHidden: false
        caseSensitive: false
        nameFilters: ["*.srt"]
        onStatusChanged: {
            if (status === FolderListModel.Ready)
                Qt.callLater(view.readSrtListing);
        }
    }

    function readSrtListing() {
        if (!isOpen || srtListed)
            return;
        var names = [];
        for (var i = 0; i < srtFolder.count; i++)
            names.push(srtFolder.get(i, "fileName"));
        srtFiles = Library.subtitleCandidates(path, names);
        srtListed = true;
        if (started)
            applyDefaultSubtitles();
    }

    // What the subtitles start as: what was chosen for this video last
    // time, else the first SubRip file next to it, else none (a track
    // inside the video is chosen in the picker).
    function applyDefaultSubtitles() {
        if (!started || !srtListed)
            return;
        var opts = pendingOptions || {};
        var want = opts.subtitle !== undefined ? opts.subtitle : (savedEntry && savedEntry.subtitle ? savedEntry.subtitle : "");
        if (want === "srt")
            want = srtFiles.length > 0 ? "srt:" + srtFiles[0] : "off";
        if (want === "" )
            want = srtFiles.length > 0 ? "srt:" + srtFiles[0] : "off";
        if (want.indexOf("srt:") === 0 && srtFiles.indexOf(want.substr(4)) < 0)
            want = srtFiles.length > 0 ? "srt:" + srtFiles[0] : "off";
        if (want.indexOf("track:") === 0 && parseInt(want.substr(6), 10) >= engine.subtitleTracks.length)
            want = "off";
        chooseSubtitles(want);
    }

    function chooseSubtitles(choice) {
        subtitleChoice = choice;
        srtCues = [];
        srtEncoding = "";
        if (!engine)
            return;
        if (choice.indexOf("track:") === 0) {
            engine.activeSubtitleTrack = parseInt(choice.substr(6), 10);
        } else {
            engine.activeSubtitleTrack = -1;
            if (choice.indexOf("srt:") === 0)
                loadSrt(choice.substr(4));
        }
        log("subtitles", { choice: choice });
    }

    // Read as bytes, without waiting for the disk (the request is answered
    // later), and decoded by Subtitles.js.
    function loadSrt(srtPath) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Library.fileUrl(srtPath));
        xhr.responseType = "arraybuffer";
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (view.subtitleChoice !== "srt:" + srtPath)
                return;
            var bytes = xhr.response instanceof ArrayBuffer ? new Uint8Array(xhr.response) : null;
            if (!bytes || bytes.length === 0) {
                view.log("srt", { path: srtPath, error: "unreadable" });
                return;
            }
            var decoded = Subtitles.decode(bytes);
            view.srtCues = Subtitles.parseSrt(decoded.text);
            view.srtEncoding = decoded.encoding;
            view.log("srt", { path: srtPath, encoding: decoded.encoding, cues: view.srtCues.length });
        };
        xhr.send();
    }

    // What to show now, as StyledText.
    readonly property string subtitleShown: {
        if (!engine || subtitleChoice === "off")
            return "";
        if (subtitleChoice.indexOf("srt:") === 0)
            return Subtitles.toStyledText(Subtitles.cueAt(srtCues, engine.position));
        return Subtitles.toStyledText(Subtitles.cleanEventText(engine.subtitleText));
    }
    onSubtitleShownChanged: if (subtitleShown !== "") log("subtitle", { text: subtitleShown })

    readonly property real subtitlePixelSize: {
        var base = Math.min(stage.width, stage.height);
        var factor = prefs && prefs.subtitleSize === "small" ? 0.045 : prefs && prefs.subtitleSize === "large" ? 0.075 : 0.058;
        return Math.max(14, Math.round(base * factor));
    }

    // ---- pickers ------------------------------------------------------------

    function openAudioPicker() {
        var choices = [];
        var tracks = engine ? engine.audioTracks : [];
        for (var i = 0; i < tracks.length; i++)
            choices.push({ label: tracks[i], checked: engine.activeAudioTrack === i, key: "audio", value: i });
        if (choices.length === 0)
            choices.push({ label: "No sound", header: true });
        sheet.show("Audio", choices);
        showControls();
    }

    function openSubtitlePicker() {
        var choices = [{ label: "Off", checked: subtitleChoice === "off", key: "subtitle", value: "off" }];
        for (var i = 0; i < srtFiles.length; i++) {
            var lang = Library.subtitleLabel(path, srtFiles[i]);
            choices.push({ label: "From file" + (lang ? " (" + lang + ")" : ""),
                           checked: subtitleChoice === "srt:" + srtFiles[i], key: "subtitle", value: "srt:" + srtFiles[i] });
        }
        var tracks = engine ? engine.subtitleTracks : [];
        for (var t = 0; t < tracks.length; t++)
            choices.push({ label: tracks[t], checked: subtitleChoice === "track:" + t, key: "subtitle", value: "track:" + t });
        choices.push({ label: "Text size", header: true });
        [["small", "Small"], ["medium", "Medium"], ["large", "Large"]].forEach(function(s) {
            choices.push({ label: s[1], checked: prefs && prefs.subtitleSize === s[0], key: "size", value: s[0] });
        });
        sheet.show("Subtitles", choices);
        showControls();
    }

    function openSpeedPicker() {
        var choices = Playback.rates.map(function(r) {
            return { label: r === 1 ? "Normal" : Format.rate(r), checked: engine && Math.abs(engine.rate - r) < 0.01,
                     key: "rate", value: r };
        });
        sheet.show("Speed", choices);
        showControls();
    }

    function pick(choice) {
        if (choice.key === "audio") {
            engine.activeAudioTrack = choice.value;
            log("audio", { track: choice.value });
        } else if (choice.key === "subtitle") {
            chooseSubtitles(choice.value);
        } else if (choice.key === "size") {
            prefs.subtitleSize = choice.value;
        } else if (choice.key === "rate") {
            engine.rate = choice.value;
            log("rate", { rate: choice.value });
        }
        saveState();
        showControls();
    }

    function toggleFill() {
        prefs.fillMode = prefs.fillMode === "fill" ? "fit" : "fill";
        showControls();
    }

    function toggleFullScreen() {
        prefs.fullScreen = !prefs.fullScreen;
        showControls();
    }

    function toggleTurn() {
        turnOverride = !turned;
        if (turnOverride)
            turnAngle = Playback.turnAngle(sensorRotation);
        showControls();
    }

    onTurnedChanged: if (turned && turnOverride === null) turnAngle = Playback.turnAngle(sensorRotation)

    function log(event, data) {
        if (!report && event !== "error" && event !== "timeout")
            return;
        data.event = event;
        data.file = path;
        console.warn("VIDEOPLAYER " + JSON.stringify(data));
    }

    // A status line every two seconds while reporting.
    Timer {
        interval: 2000
        repeat: true
        running: view.report && view.isOpen
        onTriggered: {
            var e = view.engine;
            if (e)
                view.log("status", { position: e.position, duration: e.duration, playing: e.playing, rate: e.rate,
                                     audio: e.activeAudioTrack, subtitle: view.subtitleChoice, turned: view.turned,
                                     fill: e.fill, controls: view.controlsShown, frames: e.framesShown,
                                     active: Qt.application.state === Qt.ApplicationActive });
        }
    }

    Loader {
        id: orientationLoader
        // Only while turned or able to be: the sensor costs power.
        active: view.isOpen && view.tallScreen
        source: Qt.resolvedUrl("OrientationWatcher.qml")
    }

    // ---- what is drawn ------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // Everything turns together when the picture is turned.
    Item {
        id: stage
        objectName: "playerStage"
        anchors.centerIn: parent
        width: view.turned ? view.height : view.width
        height: view.turned ? view.width : view.height
        rotation: view.turned ? view.turnAngle : 0

        // Holds the engine. One that never started may hang its pipeline
        // for good; destroying it would wait for that pipeline and freeze
        // the app, so it is stopped, hidden and kept (setAside), and a new
        // one takes its place for the next video.
        Item {
            id: engineHost
            anchors.fill: parent

            property var engine: null
            property var setAsideEngines: []

            function make() {
                var component = Qt.createComponent(view.engineSource);
                if (component.status !== Component.Ready) {
                    console.warn("PlayerView: " + component.errorString());
                    return;
                }
                engine = component.createObject(engineHost, { "width": engineHost.width, "height": engineHost.height });
                engine.width = Qt.binding(function() { return engineHost.width; });
                engine.height = Qt.binding(function() { return engineHost.height; });
            }

            function setAside() {
                if (!engine)
                    return;
                var old = engine;
                engine = null;
                old.visible = false;
                setAsideEngines.push(old);
                make();
            }

            Component.onCompleted: make()
        }

        Binding {
            target: engineHost.engine
            property: "fill"
            value: view.prefs !== null && view.prefs.fillMode === "fill"
            when: engineHost.engine !== null
        }

        // A tap shows or hides the bars; a double tap switches between all
        // of the picture and the screen filled (cropped).
        MouseArea {
            anchors.fill: parent
            onDoubleClicked: view.toggleFill()
            onClicked: {
                if (view.controlsShown && view.started && !(view.engine && view.engine.ended))
                    view.controlsShown = false;
                else
                    view.showControls();
            }
        }

        Text {
            id: subtitle
            objectName: "subtitleText"
            readonly property rect picture: view.engine ? view.engine.contentRect : Qt.rect(0, 0, stage.width, stage.height)
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(stage.width, Math.max(picture.width, stage.width * 0.6)) * 0.92
            // At the foot of the picture, as Qt places its own, or above the
            // bars while they are up.
            y: Math.min(picture.y + picture.height, stage.height) - height - Math.max(picture.height / 20, Units.gu(1))
               - (view.controlsShown ? Math.max(0, bottomBar.height - (stage.height - picture.y - picture.height) + Units.gu(1)) : 0)
            visible: text !== ""
            text: view.subtitleShown
            textFormat: Text.StyledText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "white"
            style: Text.Outline
            styleColor: "black"
            font.pixelSize: view.subtitlePixelSize
        }

        // ---- the bars -------------------------------------------------------

        Item {
            id: topBar
            objectName: "topBar"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.max(Units.gu(7), 60)
            opacity: view.controlsShown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#c0000000" }
                    GradientStop { position: 1.0; color: "#00000000" }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: view.showControls() }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Units.gu(2)
                anchors.verticalCenter: parent.verticalCenter
                text: view.title
                color: "white"
                elide: Text.ElideMiddle
                font.pixelSize: FontUtils.sizeToPixels("medium")
                font.bold: true
            }
        }

        // "Resumed at 1:23 - Start over", for a few seconds.
        Rectangle {
            objectName: "resumeNotice"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: topBar.bottom
            width: resumeRow.width + Units.gu(2)
            height: Math.max(Units.gu(5), 48)
            radius: height / 2
            color: "#cc202020"
            visible: view.resumedFrom > 0 && resumeNoticeTimer.running && view.errorText === ""

            Row {
                id: resumeRow
                anchors.centerIn: parent
                spacing: Units.gu(1.5)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Resumed at " + Format.clock(view.resumedFrom)
                    color: "white"
                    font.pixelSize: FontUtils.sizeToPixels("small")
                }
                Button {
                    objectName: "startOverButton"
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Start over"
                    onClicked: {
                        view.engine.seek(0);
                        view.resumedFrom = 0;
                        view.showControls();
                    }
                }
            }
        }

        Item {
            id: bottomBar
            objectName: "bottomBar"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: seekRow.height + buttonRow.height + Units.gu(2)
            opacity: view.controlsShown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 0.35; color: "#b0000000" }
                    GradientStop { position: 1.0; color: "#e0000000" }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: view.showControls() }

            Item {
                id: seekRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: buttonRow.top
                anchors.leftMargin: Units.gu(1.5)
                anchors.rightMargin: Units.gu(1.5)
                height: Math.max(Units.gu(5), 48)

                Label {
                    id: elapsedLabel
                    objectName: "elapsedLabel"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(implicitWidth, remainingLabel.implicitWidth)
                    text: Format.elapsed(seekBar.pressed ? seekBar.value : (view.engine ? view.engine.position : 0),
                                         view.engine ? view.engine.duration : 0)
                    color: "white"
                    font.pixelSize: FontUtils.sizeToPixels("small")
                }

                Slider {
                    id: seekBar
                    objectName: "seekBar"
                    anchors.left: elapsedLabel.right
                    anchors.right: remainingLabel.left
                    anchors.leftMargin: Units.gu(1)
                    anchors.rightMargin: Units.gu(1)
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: Math.max(1, view.engine ? view.engine.duration : 1)
                    enabled: view.engine !== null && view.engine.seekable && view.started
                    focusPolicy: Qt.NoFocus
                    // Follows the video, except while held; the seek is made
                    // on letting go, one seek rather than one per move
                    // (software decoding has to work its way to each).
                    Binding on value {
                        when: !seekBar.pressed
                        value: view.engine ? view.engine.position : 0
                        restoreMode: Binding.RestoreNone
                    }
                    onPressedChanged: {
                        if (!pressed && view.engine) {
                            view.engine.seek(Math.round(value));
                            view.log("seek", { to: Math.round(value) });
                        }
                        view.showControls();
                    }
                }

                Label {
                    id: remainingLabel
                    objectName: "remainingLabel"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Format.remaining(seekBar.pressed ? seekBar.value : (view.engine ? view.engine.position : 0),
                                           view.engine ? view.engine.duration : 0)
                    color: "white"
                    font.pixelSize: FontUtils.sizeToPixels("small")
                }
            }

            Row {
                id: buttonRow
                objectName: "buttonRow"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Units.gu(1)
                // Narrow screens: the buttons share what there is.
                readonly property int buttons: view.tallScreen || view.turned ? 8 : 7
                readonly property real buttonWidth: Math.min(Math.max(Units.gu(6), 54),
                                                             (stage.width - Units.gu(2)) / buttons)
                spacing: 0

                IconButton {
                    objectName: "audioButton"
                    width: buttonRow.buttonWidth
                    image: "audio"
                    enabled: view.engine !== null && view.engine.audioTracks.length > 1
                    onClicked: view.openAudioPicker()
                }
                IconButton {
                    objectName: "subtitleButton"
                    width: buttonRow.buttonWidth
                    image: "subtitles"
                    checked: view.subtitleChoice !== "off"
                    onClicked: view.openSubtitlePicker()
                }
                IconButton {
                    objectName: "backButton"
                    width: buttonRow.buttonWidth
                    image: "back10"
                    enabled: view.engine !== null && view.engine.seekable && view.started
                    onClicked: view.jump(-10000)
                }
                IconButton {
                    objectName: "playButton"
                    width: buttonRow.buttonWidth
                    image: view.wantPlay ? "pause" : "play"
                    enabled: view.errorText === ""
                    iconSize: Units.gu(3.5)
                    onClicked: view.togglePlay()
                }
                IconButton {
                    objectName: "forwardButton"
                    width: buttonRow.buttonWidth
                    image: "fwd10"
                    enabled: view.engine !== null && view.engine.seekable && view.started
                    onClicked: view.jump(10000)
                }
                IconButton {
                    objectName: "speedButton"
                    width: buttonRow.buttonWidth
                    label: view.engine ? Format.rate(view.engine.rate) : "1×"
                    onClicked: view.openSpeedPicker()
                }
                IconButton {
                    objectName: "fullScreenButton"
                    width: buttonRow.buttonWidth
                    image: view.prefs && view.prefs.fullScreen ? "fullscreen-exit" : "fullscreen"
                    onClicked: view.toggleFullScreen()
                }
                IconButton {
                    objectName: "turnButton"
                    width: buttonRow.buttonWidth
                    visible: view.tallScreen
                    image: "turn"
                    checked: view.turned
                    onClicked: view.toggleTurn()
                }
            }
        }

        // ---- opening, and what went wrong ------------------------------------

        Column {
            objectName: "loadingIndicator"
            anchors.centerIn: parent
            spacing: Units.gu(1.5)
            visible: view.isOpen && !view.started && view.errorText === "" && view.wantPlay

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: parent.visible
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Opening…"
                color: "#dddddd"
                font.pixelSize: FontUtils.sizeToPixels("medium")
            }
        }

        Rectangle {
            id: errorPanel
            objectName: "errorPanel"
            anchors.centerIn: parent
            width: Math.min(stage.width - Units.gu(4), Units.gu(50))
            height: errorColumn.height + Units.gu(4)
            radius: Units.gu(1)
            color: "#e6202020"
            border.color: "#555555"
            visible: view.errorText !== ""

            MouseArea { anchors.fill: parent }

            Column {
                id: errorColumn
                anchors.centerIn: parent
                width: parent.width - Units.gu(4)
                spacing: Units.gu(2)

                Label {
                    objectName: "errorLabel"
                    width: parent.width
                    text: view.errorText
                    color: "white"
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: FontUtils.sizeToPixels("medium")
                }
                Button {
                    objectName: "errorCloseButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Close"
                    onClicked: view.close()
                }
            }
        }

        ChoiceSheet {
            id: sheet
            objectName: "choiceSheet"
            onChosen: function(choice) { view.pick(choice); }
        }
    }
}
