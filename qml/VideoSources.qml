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

import "js/Online.js" as Online

/*
 * The video servers the accounts give (org.webosports.service.videos):
 * Jellyfin, PeerTube, the UPnP/DLNA media servers on the network. Each is a
 * source: {sourceId, name, icon, provider, features}. The list is asked for
 * again on refresh() - at the start, on coming back to the app - as the
 * service has no subscription.
 *
 * Every call is one request and one reply: onReply(reply) with
 * returnValue true, else onError(reply) with errorCode and errorText (a
 * service that does not answer at all gives {} there).
 */
QtObject {
    id: sources

    // function(uri, json, onReply, onError) - the app's LunaService call;
    // the tests replace it. Replies are messages with a JSON payload.
    property var call: null

    property var list: []
    property bool loading: false
    property string errorText: ""
    // Bumped whenever the list is answered, for views that keep their place.
    property int generation: 0

    function _ask(method, args, onReply, onError) {
        if (!call) {
            if (onError)
                onError({});
            return;
        }
        call(Online.SERVICE + method, JSON.stringify(args || {}), function(message) {
            var reply = null;
            try {
                reply = JSON.parse(message.payload);
            } catch (e) {
                reply = null;
            }
            if (reply && reply.returnValue === true) {
                if (onReply)
                    onReply(reply);
            } else if (onError) {
                onError(reply || {});
            }
        }, function(message) {
            var reply = {};
            try {
                reply = JSON.parse(message.payload) || {};
            } catch (e) {
                reply = {};
            }
            if (onError)
                onError(reply);
        });
    }

    function refresh() {
        loading = true;
        _ask("listSources", {}, function(r) {
            list = Array.isArray(r.sources) ? r.sources : [];
            errorText = "";
            loading = false;
            generation++;
        }, function(r) {
            // No service (not installed) is no error to show: there are
            // just no servers.
            errorText = r.errorCode ? Online.errorText(r) : "";
            list = [];
            loading = false;
            generation++;
        });
    }

    function find(sourceId) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].sourceId === sourceId)
                return list[i];
        }
        return null;
    }

    function sections(sourceId, onReply, onError) {
        _ask("listSections", { sourceId: sourceId }, onReply, onError);
    }

    // where: {sectionId} or {parentId}
    function items(sourceId, where, cursor, onReply, onError) {
        var args = { sourceId: sourceId, limit: Online.PAGE_SIZE };
        if (where.sectionId)
            args.sectionId = where.sectionId;
        if (where.parentId)
            args.parentId = where.parentId;
        if (cursor)
            args.cursor = cursor;
        _ask("listItems", args, onReply, onError);
    }

    function item(sourceId, itemId, onReply, onError) {
        _ask("getItem", { sourceId: sourceId, itemId: itemId }, onReply, onError);
    }

    function search(sourceId, query, cursor, onReply, onError) {
        var args = { sourceId: sourceId, query: query, limit: Online.PAGE_SIZE };
        if (cursor)
            args.cursor = cursor;
        _ask("search", args, onReply, onError);
    }

    function resolve(sourceId, itemId, prefer, onReply, onError) {
        _ask("resolve", { sourceId: sourceId, itemId: itemId, prefer: prefer || {} }, onReply, onError);
    }

    function report(args) {
        _ask("reportProgress", args, null, null);
    }
}
