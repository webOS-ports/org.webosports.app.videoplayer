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

import "js/MediaSession.js" as Session

/*
 * The player as a media session of com.webos.service.mediacontroller, so
 * that a Bluetooth headset's buttons work with the app in the background or
 * the screen off - not only with its window in front - and audiod can pause
 * the video for a call like any other player. The Music app's
 * MediaSession.qml, for one video at a time.
 *
 * The session exists while a video is open (active): it is registered when
 * one opens and ended when the player closes or the app goes, so the keys
 * never go to a player that is not there. It is activated whenever playing
 * starts or resumes, which makes it the one the headset's keys go to, and
 * the service is told the play status, the title and the length.
 *
 * Needs "mediacontroller.query".
 */
Item {
    id: session

    // A LunaService, or anything with its call() and subscribe().
    property var bus
    property string appId
    property bool active: false

    // What plays, as the player shows it.
    property bool playing: false
    property string title: ""
    property int durationMs: 0

    // A key asks for "play", "pause", "forward" or "back".
    signal actionRequested(string action)

    readonly property string mediaId: Session.sessionId(appId, Date.now())
    property bool registered: false

    // after a refusal or the service going, try again this much later
    property int retryInterval: 5000

    property var _call: null
    property string _sentStatus: ""
    property string _sentMeta: ""

    function register() {
        if (!bus || !appId || !active || _call)
            return;
        _call = bus.subscribe(Session.SERVICE + "registerMediaSession",
                              JSON.stringify(Session.registerPayload(mediaId, appId)),
                              _onReply, _onError);
    }

    function unregister() {
        retry.stop();
        if (_call && _call.cancel)
            _call.cancel();
        _call = null;
        registered = false;
        _sentStatus = "";
        _sentMeta = "";
    }

    function _onReply(message) {
        var reply = Session.parseReply(message.payload, mediaId);
        if (reply.failed !== undefined) {
            _onError(reply.failed);
        } else if (reply.keyEvent !== undefined) {
            var action = Session.actionForKey(reply.keyEvent);
            if (action !== "")
                actionRequested(action);
        } else if (reply.registered !== undefined && !registered) {
            registered = true;
            _report(true);
        }
    }

    function _onError(error) {
        console.warn("Videos: no media session: " + error);
        unregister();
        if (active)
            retry.restart();
    }

    function _send(method, payload) {
        bus.call(Session.SERVICE + method, JSON.stringify(payload), function() {},
                 function(error) { console.warn("Videos: " + method + ": " + error); });
    }

    // Tells the service what changed since it was last told; with "all",
    // everything, as after registering.
    function _report(all) {
        if (!registered)
            return;
        var status = Session.playStatus(playing, active);
        // playing again makes this the session the headset's keys go to
        if (playing && (all || _sentStatus !== status))
            _send("activateMediaSession", { "mediaId": mediaId });
        if (all || status !== _sentStatus) {
            _send("setMediaPlayStatus", { "mediaId": mediaId, "playStatus": status });
            _sentStatus = status;
        }
        var meta = Session.metaData(title, durationMs);
        var text = JSON.stringify(meta);
        if (all || text !== _sentMeta) {
            _send("setMediaMetaData", { "mediaId": mediaId, "mediaMetaData": meta });
            _sentMeta = text;
        }
    }

    onActiveChanged: active ? register() : unregister()
    onPlayingChanged: _report(false)
    onTitleChanged: _report(false)
    onDurationMsChanged: _report(false)

    Timer {
        id: retry
        interval: session.retryInterval
        onTriggered: session.register()
    }

    Component.onCompleted: register()
    Component.onDestruction: unregister()
}
