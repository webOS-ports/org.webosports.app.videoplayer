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
import QtMultimedia

import "js/Playback.js" as Playback

/*
 * One video playing: Qt Multimedia's MediaPlayer with its picture and
 * sound, behind the small interface the player view uses (the tests put a
 * stand-in with the same one in its place: tests/qml/mocks/FakeEngine.qml).
 *
 * Qt's GStreamer backend does its work on GStreamer's threads: loading,
 * playing, pausing, seeking and stopping only send it a request, so none of
 * them waits for a decoder that has stopped answering. Destroying a
 * MediaPlayer does wait for its pipeline to stop, which with a hung
 * decoder is for ever - so an engine that never started is not destroyed
 * but put aside (see PlayerView's engine host).
 */
Item {
    id: engine

    property url source
    // The picture over the whole area, cropped, rather than all of it.
    property bool fill: false
    property real rate: 1.0
    property int activeAudioTrack: 0
    property int activeSubtitleTrack: -1

    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property bool paused: player.playbackState === MediaPlayer.PausedState
    readonly property bool loading: player.mediaStatus === MediaPlayer.LoadingMedia
                                    || player.mediaStatus === MediaPlayer.StalledMedia
                                    || (player.mediaStatus === MediaPlayer.BufferingMedia && framesShown === 0)
    readonly property bool ended: player.mediaStatus === MediaPlayer.EndOfMedia
    property string errorText: ""
    readonly property bool hasVideo: player.hasVideo
    readonly property bool hasAudio: player.hasAudio
    readonly property int position: player.position
    readonly property int duration: player.duration
    readonly property bool seekable: player.seekable
    readonly property var audioTracks: _labels(player.audioTracks, MediaMetaData.AudioCodec)
    readonly property var subtitleTracks: _labels(player.subtitleTracks, -1)
    // Where the picture is drawn, and its size in pixels.
    readonly property rect contentRect: output.contentRect
    readonly property size videoSize: Qt.size(output.sourceRect.width, output.sourceRect.height)
    property int framesShown: 0
    // Count every frame (for the player's report), not only the first two.
    property bool countFrames: false
    // The text of the subtitle track playing now, as GStreamer gives it (an
    // ASS track's raw event line); the player cleans and draws it.
    property string subtitleText: ""

    function play() { player.play(); }
    function pause() { player.pause(); }
    function stop() { player.stop(); }
    function seek(ms) { player.position = ms; }

    // A picture of what is shown, saved to path at about size (aspect
    // kept); done(ok) is called after.
    function grabPicture(path, size, done) {
        var w = output.contentRect.width, h = output.contentRect.height;
        if (!(w > 0 && h > 0) || framesShown === 0) {
            done(false);
            return;
        }
        var scale = Math.min(size.width / w, size.height / h, 1);
        var ok = output.grabToImage(function(result) {
            done(result.saveToFile(path));
        }, Qt.size(Math.round(output.width * scale), Math.round(output.height * scale)));
        if (!ok)
            done(false);
    }

    function _labels(tracks, codecKey) {
        var out = [];
        for (var i = 0; i < tracks.length; i++) {
            var md = tracks[i];
            out.push(Playback.trackLabel(_text(md, MediaMetaData.Language), _text(md, MediaMetaData.Title),
                                         codecKey >= 0 ? _text(md, codecKey) : "", i));
        }
        return out;
    }

    function _text(md, key) {
        var v = md.stringValue(key);
        return v === undefined || v === null ? "" : String(v);
    }

    onSourceChanged: {
        framesShown = 0;
        errorText = "";
        subtitleText = "";
    }

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: engine.fill ? VideoOutput.PreserveAspectCrop : VideoOutput.PreserveAspectFit
    }

    MediaPlayer {
        id: player
        source: engine.source
        videoOutput: output
        audioOutput: AudioOutput { }
        playbackRate: engine.rate
        activeAudioTrack: engine.activeAudioTrack
        activeSubtitleTrack: engine.activeSubtitleTrack
        onErrorOccurred: function(error, errorString) {
            engine.errorText = errorString !== "" ? errorString : "This video cannot be played.";
        }
    }

    // The first picture is what tells that the video has started; after it
    // the frames are not counted, not to run script thirty times a second,
    // unless asked (countFrames).
    Connections {
        target: output.videoSink
        enabled: engine.framesShown < 2 || engine.countFrames
        function onVideoFrameChanged() { engine.framesShown++; }
    }

    /*
     * Qt draws a subtitle track's text itself, as it comes - for an ASS
     * track the whole raw event line, fields and override codes included -
     * at a size of its own. The player draws a cleaned copy at the size the
     * user picked, so Qt is given a zero-width space in its place: the
     * shortest text Qt still counts as something, so that the empty text
     * GStreamer sends when the subtitle should go is a change Qt passes on.
     * (Qt draws a sliver of shade for it, under the player's own text.)
     */
    readonly property string _placeholder: "​"

    Connections {
        target: output.videoSink
        function onSubtitleTextChanged(text) {
            if (text === engine._placeholder)
                return;
            engine.subtitleText = text;
            if (text !== "")
                output.videoSink.subtitleText = engine._placeholder;
        }
    }
}
