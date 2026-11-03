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
import QtQuick.Layouts
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1
import LuneOS.Forms 1.0

import "components"
import "js/Online.js" as Online

/*
 * A video server's library (Jellyfin, PeerTube, a UPnP/DLNA media server),
 * from org.webosports.service.videos. Its home is the server's sections:
 * rows (Continue Watching, Next Up, Recently Added) show their videos in
 * place; libraries (Movies, Shows, a media server's folders) open as a grid.
 * A show opens on its seasons and their episodes. The search field searches
 * the server. Back goes up a level, and from the home to this device.
 *
 * Each level is an entry on `stack`, which keeps what it loaded - going
 * back shows it again as it was, without asking the server again.
 */
Item {
    id: page
    objectName: "browsePage"

    property string sourceId: ""
    readonly property var source: appWindow.sources.find(sourceId)
    readonly property bool canSearch: source !== null && source.features && source.features.search === true

    // [{kind: "home"|"list"|"show", title, ...what it loaded}]
    property var stack: []
    readonly property var current: stack.length > 0 ? stack[stack.length - 1] : null
    // Bumped when an entry on the stack has more (a page came in).
    property int revision: 0
    property string errorText: ""

    // A fresh start whenever another source is picked.
    onSourceIdChanged: reset()
    function reset() {
        errorText = "";
        searchField.text = "";
        stack = sourceId !== "" ? [{ kind: "home", title: "", sections: null, rows: {} }] : [];
        if (sourceId !== "")
            loadHome(stack[0]);
    }

    function push(entry) {
        var s = stack.slice();
        s.push(entry);
        stack = s;
    }

    function pop() {
        if (stack.length <= 1)
            return false;
        var s = stack.slice();
        s.pop();
        stack = s;
        errorText = "";
        return true;
    }

    // The back gesture: the search, then up a level, then to this device.
    function handleBack() {
        if (searchField.text !== "" && (current === null || current.kind !== "list" || current.query === undefined)) {
            searchField.text = "";
            return true;
        }
        if (pop())
            return true;
        if (sourceId !== "") {
            appWindow.showSource("");
            return true;
        }
        return false;
    }

    function fail(reply) {
        errorText = Online.errorText(reply);
    }

    // ---- loading ------------------------------------------------------------

    function loadHome(entry) {
        entry.loading = true;
        appWindow.sources.sections(sourceId, function(r) {
            entry.loading = false;
            entry.sections = Online.homeEntries(r.sections);
            entry.sections.forEach(function(s) {
                if (s.layout === "row")
                    loadRow(entry, s.id);
            });
            revision++;
        }, function(r) {
            entry.loading = false;
            entry.sections = [];
            fail(r);
            revision++;
        });
    }

    function loadRow(entry, sectionId) {
        var sid = sourceId;
        appWindow.sources.items(sid, { sectionId: sectionId }, null, function(r) {
            if (sid !== sourceId)
                return;
            entry.rows[sectionId] = r.items || [];
            revision++;
        }, function(r) {
            entry.rows[sectionId] = [];
            revision++;
        });
    }

    // A list: of a section, of a folder (parentId), or what a search found.
    function openList(title, where, query) {
        var entry = { kind: "list", title: title, where: where, query: query, items: [], cursor: null, done: false,
                      loading: false };
        push(entry);
        loadMore(entry);
    }

    function loadMore(entry) {
        if (entry.loading || entry.done)
            return;
        entry.loading = true;
        revision++;
        var sid = sourceId;
        var got = function(r) {
            if (sid !== sourceId)
                return;
            entry.loading = false;
            entry.items = Online.appendPage(entry.items, r);
            entry.cursor = r.nextCursor || null;
            entry.done = !entry.cursor;
            revision++;
        };
        var failed = function(r) {
            entry.loading = false;
            entry.done = true;
            fail(r);
            revision++;
        };
        if (entry.query !== undefined)
            appWindow.sources.search(sid, entry.query, entry.cursor, got, failed);
        else
            appWindow.sources.items(sid, entry.where, entry.cursor, got, failed);
    }

    function openShow(item) {
        var entry = { kind: "show", title: item.title, item: item, seasons: null, season: null, episodes: null, loading: true };
        push(entry);
        appWindow.sources.item(sourceId, item.id, function(r) {
            entry.loading = false;
            var it = r.item || {};
            entry.item = it;
            entry.seasons = it.seasons || [];
            if (entry.seasons.length > 0)
                pickSeason(entry, entry.seasons[0]);
            revision++;
        }, function(r) {
            entry.loading = false;
            entry.seasons = [];
            fail(r);
            revision++;
        });
    }

    function pickSeason(entry, season) {
        entry.season = season;
        entry.episodes = null;
        revision++;
        appWindow.sources.item(sourceId, season.id, function(r) {
            if (entry.season !== season)
                return;
            entry.episodes = (r.item && r.item.children) || [];
            revision++;
        }, function(r) {
            entry.episodes = [];
            fail(r);
            revision++;
        });
    }

    // An item tapped: a video plays; a show opens on its seasons; a folder
    // (a collection, a season) opens as a list.
    function activate(item, siblings) {
        if (item.playable) {
            appWindow.playOnline(sourceId, item, siblings || []);
        } else if (item.kind === "show") {
            openShow(item);
        } else if (item.hasChildren) {
            openList(item.title, { parentId: item.id });
        }
    }

    // ---- the page -----------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.pageGradientTop }
            GradientStop { position: 1.0; color: Colors.pageGradientBottom }
        }
    }

    AppHeader {
        id: header
        objectName: "browseHeader"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: appWindow.headerHeight
        title: page.source ? page.source.name : "Videos"
        icon: appWindow.appIcon
        compact: appWindow.compact
    }

    ColumnLayout {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 0

        SourceBar {
            Layout.fillWidth: true
            Layout.margins: Units.gu(1)
            Layout.bottomMargin: 0
            Layout.preferredHeight: Units.gu(5)
            sources: appWindow.sources.list
            current: page.sourceId
            onPicked: function(id) { appWindow.showSource(id); }
        }

        StatusNotice {
            objectName: "browseNotice"
            Layout.fillWidth: true
            Layout.margins: Units.gu(1)
            Layout.bottomMargin: 0
            visible: text !== ""
            text: page.errorText !== "" ? page.errorText : appWindow.notice
            onDismissed: {
                page.errorText = "";
                appWindow.notice = "";
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Units.gu(1)
            Layout.rightMargin: Units.gu(1)
            Layout.topMargin: Units.gu(1)
            visible: page.stack.length > 1 || page.canSearch
            spacing: Units.gu(1)

            Button {
                objectName: "upButton"
                visible: page.stack.length > 1
                text: "‹ Back"
                flat: true
                onClicked: page.pop()
            }
            Label {
                objectName: "levelTitle"
                Layout.fillWidth: true
                visible: page.stack.length > 1
                text: page.current ? (page.current.query !== undefined ? "Search: “" + page.current.query + "”" : page.current.title) : ""
                elide: Text.ElideRight
                font.bold: true
                font.pixelSize: FontUtils.sizeToPixels("medium")
                color: Colors.text
            }
            TextField {
                id: searchField
                objectName: "browseSearch"
                Layout.fillWidth: page.stack.length <= 1
                Layout.preferredWidth: page.stack.length > 1 ? Units.gu(18) : -1
                visible: page.canSearch
                placeholderText: "Search " + (page.source ? page.source.name : "")
                inputMethodHints: Qt.ImhNoPredictiveText
                onAccepted: {
                    var q = text.trim();
                    if (q === "")
                        return;
                    // A new search replaces the last one rather than piling up.
                    if (page.current && page.current.kind === "list" && page.current.query !== undefined)
                        page.pop();
                    page.openList("", null, q);
                }
            }
        }

        Loader {
            id: level
            objectName: "level"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Units.gu(1)
            sourceComponent: page.current === null ? null
                             : page.current.kind === "home" ? homeView
                             : page.current.kind === "show" ? showView : listView
        }
    }

    // ---- the home: rows and libraries ---------------------------------------

    Component {
        id: homeView

        ListView {
            id: home
            objectName: "homeView"
            readonly property var entry: page.current
            clip: true
            spacing: Units.gu(1)
            model: (page.revision, entry && entry.sections ? entry.sections : [])

            delegate: Loader {
                width: home.width
                sourceComponent: modelData.layout === "row" ? rowSection : librarySection
                property var section: modelData
                property var entry: home.entry
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: (page.revision, home.entry !== null && home.entry.loading === true)
                visible: running
            }
            Label {
                objectName: "homeEmpty"
                anchors.centerIn: parent
                width: parent.width - Units.gu(4)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: (page.revision, home.entry !== null) && home.entry.loading !== true && home.entry.sections !== null
                         && home.entry.sections.length === 0 && page.errorText === ""
                text: "This server has nothing to show."
                color: Colors.secondaryText
            }
            ScrollIndicator.vertical: ScrollIndicator { }
        }
    }

    Component {
        id: rowSection

        Column {
            id: rowCol
            objectName: "row:" + section.id
            readonly property var items: (page.revision, entry.rows[section.id] || [])
            readonly property bool wideTiles: items.length === 0 || items[0].kind === "episode" || items[0].kind === "video"
                                              || items[0].kind === "live"
            width: parent ? parent.width : 0
            spacing: Units.gu(0.5)
            visible: items.length > 0
            height: visible ? implicitHeight : 0

            Label {
                text: section.title
                font.bold: true
                font.pixelSize: FontUtils.sizeToPixels("small")
                color: Colors.secondaryText
                leftPadding: Units.gu(0.5)
            }
            ListView {
                id: strip
                width: rowCol.width
                readonly property real tileWidth: rowCol.wideTiles ? Units.gu(24) : Units.gu(14)
                height: (rowCol.wideTiles ? tileWidth * 9 / 16 : tileWidth * 3 / 2) + Units.gu(7)
                orientation: ListView.Horizontal
                clip: true
                spacing: Units.gu(0.5)
                model: rowCol.items
                delegate: OnlineTile {
                    objectName: "tile:" + modelData.id
                    width: strip.tileWidth
                    height: strip.height
                    item: modelData
                    wide: rowCol.wideTiles
                    onClicked: page.activate(modelData, rowCol.items)
                }
            }
        }
    }

    Component {
        id: librarySection

        ItemDelegate {
            objectName: "library:" + section.id
            width: parent ? parent.width : 0
            text: section.title
            font.pixelSize: FontUtils.sizeToPixels("medium")
            contentItem: RowLayout {
                Label {
                    Layout.fillWidth: true
                    text: section.title
                    color: Colors.text
                    font.pixelSize: FontUtils.sizeToPixels("medium")
                    elide: Text.ElideRight
                }
                Label {
                    text: "›"
                    color: Colors.secondaryText
                    font.pixelSize: FontUtils.sizeToPixels("large")
                }
            }
            background: Rectangle {
                radius: Units.gu(0.6)
                color: parent.pressed ? "#30000000" : "#14000000"
            }
            onClicked: page.openList(section.title, { sectionId: section.id })
        }
    }

    // ---- a list: a library, a folder, a search --------------------------------

    Component {
        id: listView

        GridView {
            id: grid
            objectName: "listView"
            readonly property var entry: page.current
            readonly property var items: (page.revision, entry && entry.items ? entry.items : [])
            // Pictures 16:9 when the list is mostly videos and episodes,
            // else 2:3 posters (films, shows) - folders count for neither.
            readonly property bool wideTiles: {
                var wide = 0, tall = 0;
                for (var i = 0; i < items.length; i++) {
                    var k = items[i].kind;
                    if (k === "movie" || k === "show")
                        tall++;
                    else if (k !== "collection" && k !== "season")
                        wide++;
                }
                return wide >= tall;
            }
            readonly property int columns: Math.max(2, Math.floor(width / (wideTiles ? Units.gu(26) : Units.gu(16))))
            clip: true
            cellWidth: Math.floor(width / columns)
            cellHeight: (wideTiles ? cellWidth * 9 / 16 : cellWidth * 3 / 2) + Units.gu(7)
            model: items
            delegate: OnlineTile {
                objectName: "tile:" + modelData.id
                width: grid.cellWidth
                height: grid.cellHeight
                item: modelData
                wide: grid.wideTiles
                onClicked: page.activate(modelData, grid.items)
            }
            // The next page as the end comes into view.
            onAtYEndChanged: {
                if (atYEnd && entry)
                    page.loadMore(entry);
            }
            footer: Item {
                width: grid.width
                height: Units.gu(6)
                BusyIndicator {
                    anchors.centerIn: parent
                    running: (page.revision, grid.entry !== null && grid.entry.loading === true)
                    visible: running
                }
            }
            Label {
                objectName: "listEmpty"
                anchors.centerIn: parent
                width: parent.width - Units.gu(4)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: (page.revision, grid.entry !== null) && grid.entry.done === true && grid.items.length === 0 && page.errorText === ""
                text: grid.entry && grid.entry.query !== undefined ? "Nothing on this server matches “" + grid.entry.query + "”."
                                                                   : "Nothing here."
                color: Colors.secondaryText
            }
            ScrollIndicator.vertical: ScrollIndicator { }
        }
    }

    // ---- a show: its seasons and their episodes -------------------------------

    Component {
        id: showView

        ColumnLayout {
            id: show
            objectName: "showView"
            readonly property var entry: page.current
            readonly property var seasons: (page.revision, entry && entry.seasons ? entry.seasons : [])
            readonly property var episodes: (page.revision, entry && entry.episodes ? entry.episodes : [])
            spacing: Units.gu(1)

            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: (page.revision, show.entry && show.entry.item && show.entry.item.description) ? show.entry.item.description : ""
                wrapMode: Text.WordWrap
                maximumLineCount: 4
                elide: Text.ElideRight
                color: Colors.secondaryText
                font.pixelSize: FontUtils.sizeToPixels("small")
            }

            ListView {
                id: seasonBar
                objectName: "seasonBar"
                Layout.fillWidth: true
                Layout.preferredHeight: Units.gu(4.5)
                visible: show.seasons.length > 1
                orientation: ListView.Horizontal
                spacing: Units.gu(0.6)
                clip: true
                model: show.seasons
                delegate: ItemDelegate {
                    objectName: "season:" + modelData.id
                    readonly property bool selected: (page.revision, show.entry && show.entry.season && show.entry.season.id === modelData.id)
                    height: seasonBar.height
                    leftPadding: Units.gu(1.2)
                    rightPadding: Units.gu(1.2)
                    background: Rectangle {
                        radius: height / 2
                        color: parent.selected ? "#4a8fd8" : "#20000000"
                    }
                    contentItem: Label {
                        text: modelData.title
                        color: parent.selected ? "white" : Colors.text
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: page.pickSeason(show.entry, modelData)
                }
            }

            ListView {
                id: episodeList
                objectName: "episodeList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Units.gu(0.5)
                model: show.episodes
                delegate: ItemDelegate {
                    objectName: "episode:" + modelData.id
                    width: episodeList.width
                    padding: Units.gu(0.5)
                    background: Rectangle {
                        radius: Units.gu(0.6)
                        color: parent.pressed ? "#30000000" : "transparent"
                    }
                    contentItem: RowLayout {
                        spacing: Units.gu(1)
                        OnlineTile {
                            Layout.preferredWidth: Units.gu(16)
                            Layout.preferredHeight: Units.gu(16) * 9 / 16 + Units.gu(1.2)
                            item: ({ id: modelData.id, artwork: modelData.artwork, durationMs: modelData.durationMs,
                                     progress: modelData.progress, playable: true, title: "" })
                            wide: true
                            enabled: false
                        }
                        Column {
                            Layout.fillWidth: true
                            spacing: Units.gu(0.3)
                            Label {
                                width: parent.width
                                text: (modelData.episode !== undefined ? modelData.episode + ". " : "") + modelData.title
                                elide: Text.ElideRight
                                color: Colors.text
                                font.pixelSize: FontUtils.sizeToPixels("medium")
                            }
                            Label {
                                width: parent.width
                                text: modelData.description || ""
                                visible: text !== ""
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: Colors.secondaryText
                                font.pixelSize: FontUtils.sizeToPixels("x-small")
                            }
                        }
                    }
                    onClicked: page.activate(modelData, show.episodes)
                }
                BusyIndicator {
                    anchors.centerIn: parent
                    running: (page.revision, show.entry !== null) && (show.entry.loading === true || (show.entry.season !== null && show.entry.episodes === null))
                    visible: running
                }
                ScrollIndicator.vertical: ScrollIndicator { }
            }
        }
    }
}
