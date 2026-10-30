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

.pragma library

/*
 * The player as a media session of com.webos.service.mediacontroller: what
 * is sent to it, and what its key events ask of the player. The service
 * hands a session the keys of a Bluetooth headset (and audiod's pause and
 * resume around calls) for as long as it is the one activated last.
 * The Music app's js/MediaSession.js, for one video instead of a queue.
 */

var SERVICE = "luna://com.webos.service.mediacontroller/";

// How far a headset's next and previous keys jump: a video has no next
// track, so they do what the player's own 10 s buttons do.
var JUMP_MS = 10000;

/* A session id of the app's own, different for each run, so a session the
 * service still remembers from a run that crashed is never taken for this
 * one. */
function sessionId(appId, now) {
    return appId + "-" + now.toString(36);
}

function registerPayload(mediaId, appId) {
    return { "mediaId": mediaId, "appId": appId, "subscribe": true };
}

/* What a key event asks of the player: "play", "pause", "forward",
 * "back", or "" for nothing. Play and pause are play and pause, never a
 * toggle: audiod sends "pause" when a call comes in and "play" when it is
 * over, and the app may already have done the same on its own. */
function actionForKey(keyEvent) {
    switch (keyEvent) {
    case "play":
        return "play";
    case "pause":
    case "stop":
        return "pause";
    case "next":
    case "fastForward":
        return "forward";
    case "previous":
    case "rewind":
        return "back";
    default:
        return "";
    }
}

/* The PLAYSTATE_ the service knows the player by. */
function playStatus(playing, open) {
    if (playing)
        return "PLAYSTATE_PLAYING";
    return open ? "PLAYSTATE_PAUSED" : "PLAYSTATE_STOPPED";
}

/* The service's mediaMetaData of a video: its title, and its length as
 * text (seconds) once it is known. */
function metaData(title, durationMs) {
    var meta = {};
    if (title)
        meta.title = String(title);
    if (durationMs > 0)
        meta.totalDuration = String(Math.round(durationMs / 1000));
    return meta;
}

/* A reply on the session's registerMediaSession call: { registered } for
 * the first, { keyEvent } for the keys after it, { failed } when the
 * service refused or dropped the session. */
function parseReply(payload, mediaId) {
    var reply;
    try {
        reply = typeof payload === "string" ? JSON.parse(payload) : payload;
    } catch (e) {
        return { "failed": "not JSON" };
    }
    if (!reply || reply.returnValue === false)
        return { "failed": reply && reply.errorText ? reply.errorText : "refused" };
    if (reply.keyEvent !== undefined) {
        // the service sends a session only its own keys; check all the same
        if (reply.mediaId !== undefined && reply.mediaId !== mediaId)
            return {};
        return { "keyEvent": String(reply.keyEvent) };
    }
    return { "registered": reply.subscribed === true };
}
