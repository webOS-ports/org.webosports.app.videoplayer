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
import "js/Format.js" as Format
import "js/Library.js" as Library

/*
 * The videos on the device: those to carry on with, then all of them - by
 * name, date or size - narrowed by the search field. A list on a phone, a
 * grid of pictures on a tablet.
 */
Item {
    id: page
    objectName: "libraryPage"

    readonly property var files: appWindow.scanner.files
    readonly property var roots: appWindow.scanner.activeRoots
    readonly property bool searching: searchField.text.trim() !== ""
    readonly property bool wide: width >= Units.gu(90)

    // What is shown: section, path, name, details, length, thumbnail,
    // progress.
    readonly property var rows: {
        // Read for the binding: played, forgotten, measured.
        var revisions = appWindow.resume.revision + appWindow.cache.revision;
        var facts = appWindow.cache.all();
        var known = {};
        var i;
        for (i = 0; i < files.length; ++i)
            known[files[i].path] = files[i];
        var result = [];

        function lengthOf(f, entry) {
            var fact = f ? facts[Library.cacheKey(f)] : null;
            var ms = fact && fact.duration > 0 ? fact.duration : (entry && entry.duration > 0 ? entry.duration : 0);
            return ms;
        }
        function pictureOf(f) {
            var fact = f ? facts[Library.cacheKey(f)] : null;
            return fact && fact.thumb ? "file://" + appWindow.cache.folder + "/" + fact.thumb : "";
        }

        if (!searching && !wide) {
            var carryOn = appWindow.resume.continueWatching(function(path) { return known[path] !== undefined; }, 5);
            for (var r = 0; r < carryOn.length; ++r) {
                var c = carryOn[r];
                var cf = known[c.path];
                var cl = lengthOf(cf, c);
                result.push({
                    section: "Continue Watching",
                    path: c.path,
                    name: Library.displayName(c.path),
                    details: cl > 0 ? Format.duration(cl - c.position) + " left" : "Stopped at " + Format.clock(c.position),
                    length: cl > 0 ? Format.clock(cl) : "",
                    thumbnail: pictureOf(cf),
                    progress: cl > 0 ? c.position / cl : -1
                });
            }
        }

        var shown = Library.sorted(Library.filter(files, searchField.text, roots), appWindow.prefs.sortOrder);
        var section = searching ? "Matches" : "All Videos";
        for (var j = 0; j < shown.length; ++j) {
            var f = shown[j];
            var entry = appWindow.resume.entry(f.path);
            var len = lengthOf(f, entry);
            var where = Library.volumeOf(f.path, roots);
            var folder = Library.folderOf(f.path, roots);
            result.push({
                section: section,
                path: f.path,
                name: Library.displayName(f.path),
                details: [where !== "" ? where + (folder ? "/" + folder : "") : folder,
                          Format.size(f.size), Format.date(f.modified, Date.now())]
                         .filter(function(s) { return s !== ""; }).join(" · "),
                length: len > 0 ? Format.clock(len) : "",
                thumbnail: pictureOf(f),
                progress: entry && entry.position > 0 && len > 0 ? entry.position / len : -1
            });
        }
        return result;
    }

    // Sections need a model with roles; the rows are copied in.
    ListModel {
        id: rowModel
    }

    // In place: a length or picture coming in changes its row, and the
    // list keeps its rows and where it was scrolled to.
    function syncRows() {
        var i;
        for (i = 0; i < rows.length; ++i) {
            if (i >= rowModel.count) {
                rowModel.append(rows[i]);
                continue;
            }
            var old = rowModel.get(i);
            var r = rows[i];
            if (old.path !== r.path || old.section !== r.section || old.name !== r.name || old.details !== r.details
                    || old.length !== r.length || String(old.thumbnail) !== String(r.thumbnail)
                    || Math.abs(old.progress - r.progress) > 0.0001)
                rowModel.set(i, r);
        }
        if (rowModel.count > rows.length)
            rowModel.remove(rows.length, rowModel.count - rows.length);
    }

    onRowsChanged: syncRows()
    Component.onCompleted: syncRows()

    function handleBack() {
        if (searchField.text !== "") {
            searchField.text = "";
            return true;
        }
        return false;
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.pageGradientTop }
            GradientStop { position: 1.0; color: Colors.pageGradientBottom }
        }
    }

    AppHeader {
        id: header
        objectName: "libraryHeader"

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: appWindow.headerHeight

        title: "Videos"
        icon: appWindow.appIcon
        compact: appWindow.compact
        actionComponent: ToolButton {
            objectName: "libraryMenuButton"
            implicitWidth: Math.max(Units.gu(6), 54)
            implicitHeight: Math.max(Units.gu(5), 54)
            focusPolicy: Qt.NoFocus
            contentItem: Item {
                Image {
                    anchors.centerIn: parent
                    width: Units.gu(3)
                    height: Units.gu(3)
                    sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
                    source: Qt.resolvedUrl("images/more-dark.svg")
                }
            }
            background: Rectangle {
                radius: Units.gu(0.6)
                color: parent.pressed ? "#30000000" : "transparent"
            }
            onClicked: appWindow.openAppMenu()
        }
    }

    ColumnLayout {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 0

        StatusNotice {
            objectName: "libraryNotice"
            Layout.fillWidth: true
            Layout.margins: Units.gu(1)
            Layout.bottomMargin: 0
            visible: text !== ""
            text: appWindow.notice
            onDismissed: appWindow.notice = ""
        }

        GroupBox {
            objectName: "videosGroup"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Units.gu(1)
            title: "Videos"

            ColumnLayout {
                anchors.fill: parent
                spacing: Units.gu(0.5)

                TextField {
                    id: searchField
                    objectName: "searchField"
                    Layout.fillWidth: true
                    visible: page.files.length >= 6 || text !== ""
                    placeholderText: "Search"
                    inputMethodHints: Qt.ImhNoPredictiveText
                }

                ListView {
                    id: list
                    objectName: "videoList"

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !page.wide
                    clip: true
                    model: page.wide ? null : rowModel

                    section.property: "section"
                    section.criteria: ViewSection.FullString
                    section.delegate: Item {
                        width: list.width
                        height: sectionLabel.implicitHeight + Units.gu(1.5)
                        Label {
                            id: sectionLabel
                            x: Units.gu(1)
                            y: Units.gu(1)
                            text: section
                            font.pixelSize: FontUtils.sizeToPixels("small")
                            font.bold: true
                            color: Colors.secondaryText
                        }
                    }

                    delegate: VideoRow {
                        width: list.width
                        path: model.path
                        name: model.name
                        details: model.details
                        length: model.length
                        thumbnail: model.thumbnail
                        progress: model.progress
                        index: model.index
                        count: list.count

                        onClicked: appWindow.playFile(model.path)
                        onHeld: {
                            videoMenu.row = { path: model.path, section: model.section };
                            videoMenu.popup();
                        }
                    }

                    ScrollIndicator.vertical: ScrollIndicator { }
                }

                GridView {
                    id: grid
                    objectName: "videoGrid"

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: page.wide
                    clip: true
                    model: page.wide ? rowModel : null
                    // Columns of a steady width, as many as fit.
                    readonly property int columns: Math.max(2, Math.floor(width / Units.gu(30)))
                    cellWidth: Math.floor(width / columns)
                    cellHeight: cellWidth * 9 / 16 + Units.gu(9)

                    delegate: VideoTile {
                        width: grid.cellWidth
                        height: grid.cellHeight
                        path: model.path
                        name: model.name
                        details: model.details
                        length: model.length
                        thumbnail: model.thumbnail
                        progress: model.progress

                        onClicked: appWindow.playFile(model.path)
                        onHeld: {
                            videoMenu.row = { path: model.path, section: model.section };
                            videoMenu.popup();
                        }
                    }

                    ScrollIndicator.vertical: ScrollIndicator { }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: rowModel.count === 0

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - Units.gu(4)
                        spacing: Units.gu(1)

                        BusyIndicator {
                            anchors.horizontalCenter: parent.horizontalCenter
                            running: appWindow.scanner.running
                            visible: running
                        }

                        Label {
                            objectName: "emptyLabel"
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            visible: !appWindow.scanner.running || page.searching
                            text: page.searching ? "No video matches “" + searchField.text.trim() + "”."
                                                 : "No videos on this device yet.\n\nCopy them over USB to the "
                                                   + "internal storage or put in a memory card; they are found in any folder."
                            color: Colors.secondaryText
                            font.pixelSize: FontUtils.sizeToPixels("medium")
                        }
                    }
                }
            }
        }
    }

    Menu {
        id: videoMenu
        objectName: "videoMenu"

        property var row: null

        MenuItem {
            text: "Play"
            onTriggered: appWindow.playFile(videoMenu.row.path)
        }
        MenuItem {
            text: "Play from the Start"
            onTriggered: appWindow.playFile(videoMenu.row.path, { position: 0 })
        }
        MenuItem {
            text: "Remove from Continue Watching"
            enabled: videoMenu.row !== null && appWindow.resume.positionOf(videoMenu.row.path) > 0
            height: enabled ? implicitHeight : 0
            onTriggered: appWindow.resume.forget(videoMenu.row.path)
        }
    }
}
