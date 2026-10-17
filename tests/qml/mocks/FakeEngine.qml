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

/*
 * A stand-in for qml/VideoEngine.qml with the same interface, playing
 * nothing: a coloured picture, a clock that moves the position, tracks and
 * subtitle lines made up from the file name.
 *
 *   "hang"    never shows a picture (a decoder that hung)
 *   "broken"  fails with an error
 *   "2audio"  two audio tracks; "ass" one subtitle track whose text comes
 *             as ASS event lines, as GStreamer gives them
 *   "tall"    a portrait picture (480x854), else 854x480
 *
 * calls lists what the player asked of it.
 */
Item {
    id: engine

    property url source
    property bool fill: false
    property real rate: 1.0
    property int activeAudioTrack: 0
    property int activeSubtitleTrack: -1

    property bool playing: false
    property bool paused: false
    property bool loading: false
    property bool ended: false
    property string errorText: ""
    property bool hasVideo: false
    property bool hasAudio: false
    property int position: 0
    property int duration: 0
    property bool seekable: false
    property var audioTracks: []
    property var subtitleTracks: []
    property size videoSize: Qt.size(0, 0)
    readonly property rect contentRect: {
        if (!(videoSize.width > 0))
            return Qt.rect(0, 0, width, height);
        var s = fill ? Math.max(width / videoSize.width, height / videoSize.height)
                     : Math.min(width / videoSize.width, height / videoSize.height);
        var w = videoSize.width * s, h = videoSize.height * s;
        return Qt.rect((width - w) / 2, (height - h) / 2, w, h);
    }
    property int framesShown: 0
    property bool countFrames: false
    property string subtitleText: ""

    property var calls: []
    readonly property string name: String(source).split("/").pop()

    function _call(what) {
        var c = calls.slice();
        c.push(what);
        calls = c;
    }

    function play() {
        _call("play");
        if (errorText !== "")
            return;
        if (ended) {
            ended = false;
            position = 0;
        }
        playing = true;
        paused = false;
        if (!hasVideo && !hasAudio)
            loadTimer.restart();
    }
    function pause() {
        _call("pause");
        playing = false;
        paused = true;
    }
    function stop() {
        _call("stop");
        playing = false;
        paused = false;
        position = 0;
    }
    function seek(ms) {
        _call("seek " + ms);
        position = Math.max(0, Math.min(ms, duration));
    }

    function grabPicture(path, size, done) {
        if (framesShown === 0) {
            done(false);
            return;
        }
        var ok = picture.grabToImage(function(result) { done(result.saveToFile(path)); },
                                     Qt.size(Math.round(size.width), Math.round(size.height)));
        if (!ok)
            done(false);
    }

    onSourceChanged: {
        playing = false;
        paused = false;
        ended = false;
        errorText = "";
        hasVideo = false;
        hasAudio = false;
        position = 0;
        duration = 0;
        seekable = false;
        framesShown = 0;
        subtitleText = "";
        audioTracks = [];
        subtitleTracks = [];
        videoSize = Qt.size(0, 0);
        loading = String(source) !== "";
    }

    // Loading: the file is "read".
    Timer {
        id: loadTimer
        interval: 150
        onTriggered: {
            var n = engine.name;
            engine.loading = false;
            if (n.indexOf("broken") >= 0) {
                engine.playing = false;
                engine.errorText = "Could not decode the video (stand-in).";
                return;
            }
            engine.hasVideo = true;
            engine.hasAudio = true;
            engine.duration = 30000;
            engine.seekable = true;
            engine.videoSize = n.indexOf("tall") >= 0 ? Qt.size(480, 854) : Qt.size(854, 480);
            engine.audioTracks = n.indexOf("2audio") >= 0 ? ["English – 440 Hz (AAC)", "Dutch – 880 Hz (AC3)"]
                                                          : ["Track 1 (AAC)"];
            engine.subtitleTracks = n.indexOf("ass") >= 0 ? ["English"] : [];
            if (n.indexOf("hang") < 0 && engine.playing)
                engine.framesShown = 1;
        }
    }

    onPlayingChanged: {
        if (playing && hasVideo && name.indexOf("hang") < 0 && framesShown === 0)
            framesShown = 1;
    }

    // The clock: 100 ms of video per tick at rate 1.
    Timer {
        interval: 100
        repeat: true
        running: engine.playing && engine.framesShown > 0
        onTriggered: {
            engine.position = Math.min(engine.duration, engine.position + Math.round(100 * engine.rate));
            if (engine.position >= engine.duration) {
                engine.playing = false;
                engine.ended = true;
                // As Qt's: the picture's size goes when the stream stops.
                engine.videoSize = Qt.size(0, 0);
            }
        }
    }

    // An embedded ASS track's lines, Matroska style, while it is chosen.
    readonly property var assEvents: [
        { start: 1000, end: 5000, line: "1,0,Default,,0,0,0,,EMBEDDED ASS one" },
        { start: 6000, end: 10000, line: "2,0,Default,,0,0,0,,EMBEDDED ASS two {\\i1}italic{\\i0}" },
        { start: 12000, end: 20000, line: "3,0,Default,,0,0,0,,{\\pos(10,10)}EMBEDDED ASS three\\Nline" }
    ]
    onPositionChanged: {
        if (activeSubtitleTrack < 0 || subtitleTracks.length === 0) {
            subtitleText = "";
            return;
        }
        var t = "";
        for (var i = 0; i < assEvents.length; i++) {
            if (position >= assEvents[i].start && position < assEvents[i].end)
                t = assEvents[i].line;
        }
        subtitleText = t;
    }

    Rectangle {
        id: picture
        x: engine.contentRect.x
        y: engine.contentRect.y
        width: engine.contentRect.width
        height: engine.contentRect.height
        visible: engine.framesShown > 0
        gradient: Gradient {
            GradientStop { position: 0; color: "#3060a0" }
            GradientStop { position: 1; color: "#a06030" }
        }
    }
}
