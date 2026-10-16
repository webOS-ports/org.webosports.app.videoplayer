#!/bin/sh
# Runs every test on the build host: the logic in qml/js (tst_subtitles,
# tst_format, tst_library, tst_playback), the scan and the length probe
# (tst_scanner) and the app itself with a stand-in player (tst_ui), the
# last once per screen in PROFILES - by default the TouchPad, the
# mindphone and the Q25 - with luneos-components' desktop stand-ins.
#
#   tools/run-tests.sh [path to luneos-components [qmltestrunner arguments]]
#
# The stand-ins read their profile (and with it the grid unit) once, as they
# load, so each screen runs against a copy of LunaNext.Common whose default
# profile is that screen. Settings and pictures go to a throwaway folder;
# screenshots of each state go to build/test-output/ui/.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
[ $# -gt 0 ] && shift
PROFILES=${PROFILES:-tp mindphone q25}
CONF=$(mktemp -d)
trap 'rm -rf "$CONF"' EXIT
mkdir -p build/test-output/ui

run() {
    XDG_CONFIG_HOME=$CONF/config XDG_CACHE_HOME=$CONF/cache QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} \
    QML_XHR_ALLOW_FILE_READ=1 QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
        ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} \
        -import "$LC/modules" -import "$LC/test/imports" "$@"
}

status=0
for t in subtitles format library playback scanner; do
    rm -rf "$CONF/config" "$CONF/cache"
    run -input tests/qml/tst_$t.qml "$@" || status=1
done
for profile in $PROFILES; do
    common=$CONF/profile-$profile/LunaNext/Common
    mkdir -p "$common"
    cp "$LC"/test/imports/LunaNext/Common/* "$common/"
    sed -i "s/^var defaultProfile = .*/var defaultProfile = \"$profile\";/" "$common/SettingsStub.js"
    grep -q "^var defaultProfile = \"$profile\";" "$common/SettingsStub.js"
    rm -rf "$CONF/config" "$CONF/cache"
    run -import "$CONF/profile-$profile" -input tests/qml/tst_ui.qml "$@" || status=1
done
exit $status
