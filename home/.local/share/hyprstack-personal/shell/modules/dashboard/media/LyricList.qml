pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    // Personal overlay: players such as SoundCloud clients report the uploader as the
    // artist and put "Artists — Song (Official Video)" in the title, so the lyrics search
    // found nothing. Take the artist and song from such a title before searching.
    function cleanTrack(artist: string, title: string): var {
        artist = (artist || "").trim();
        title = (title || "").trim();
        const junk = /\s*[\(\[](?:official\s+(?:music\s+)?(?:video|audio)|music\s+video|lyric(?:s)?\s+video|lyrics|audio|video|clip|hd|hq|4k|visuali[sz]er|премьера[^\)\]]*|клип|текст)[\)\]]/gi;
        title = title.replace(junk, "").trim();
        const parts = title.split(/\s+[—–-]\s+/);
        if (parts.length >= 2 && parts[0] && parts[1]) {
            const artists = parts[0].trim();
            title = parts.slice(1).join(" - ").trim();
            // main artist: the first one before &, ",", feat., ft., x
            artist = artists.split(/\s*(?:&|,|\bfeat\.?|\bft\.?|\s[xх]\s)\s*/i)[0].trim() || artists;
        }
        return {artist: artist, title: title};
    }

    // Funny binding hack to make lyrics update
    readonly property var _: {
        const p = Players.active;
        if (p)
        {
            const t = root.cleanTrack(p.trackArtist, p.trackTitle);
            Lyrics.setTrack(t.artist, t.title, p.trackAlbum, p.length);
        }
        else
            Lyrics.clearTrack();
    }

    // Personal overlay: a player with the org.gnova.Player interface (Gnova) hands
    // over the lyrics it shows itself; they win over the shell's own search, which
    // can miss a track the player found. Other players use the search as before.
    readonly property string busName: Players.active?.dbusName ?? ""
    property bool gnovaSupported: false
    property string gnovaStatus: ""
    property string gnovaTitle: ""
    property var gnovaLines: [] // [{time, text}], time < 0 for plain text
    property bool gnovaSynced: false
    property bool gnovaQueryAgain: false
    readonly property bool useGnova: gnovaSupported && gnovaStatus === "ready" && gnovaLines.length > 0
        && gnovaTitle === (Players.active?.trackTitle ?? "")
    readonly property bool gnovaLoading: gnovaSupported && gnovaStatus === "loading"

    function parseGnova(text: string): void {
        const stamp = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/g;
        const synced = [];
        const plain = [];
        for (const raw of text.split("\n")) {
            const line = raw.trim();
            const times = [];
            let m;
            stamp.lastIndex = 0;
            while ((m = stamp.exec(line)) !== null)
                times.push(parseInt(m[1]) * 60 + parseFloat(m[2].replace(":", ".")));
            const words = line.replace(stamp, "").trim();
            if (times.length > 0) {
                for (const t of times)
                    synced.push({time: t, text: words});
            } else if (line.length > 0) {
                plain.push({time: -1, text: line});
            }
        }
        synced.sort((a, b) => a.time - b.time);
        root.gnovaSynced = synced.length > 0;
        root.gnovaLines = synced.length > 0 ? synced : plain;
    }

    function refreshGnova(): void {
        if (!root.busName) {
            root.gnovaSupported = false;
            return;
        }
        if (gnovaQuery.running) {
            root.gnovaQueryAgain = true;
            return;
        }
        gnovaQuery.exec(["busctl", "--user", "--json=short", "call", root.busName, "/org/mpris/MediaPlayer2", "org.gnova.Player", "GetLyrics"]);
    }

    function indexForTime(time: real): int {
        if (!root.useGnova)
            return Lyrics.indexForTime(time);
        if (!root.gnovaSynced)
            return -1;
        const target = time + 0.1;
        let lo = 0;
        let hi = root.gnovaLines.length;
        while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (root.gnovaLines[mid].time <= target)
                lo = mid + 1;
            else
                hi = mid;
        }
        return lo - 1;
    }

    function timeForIndex(index: int): real {
        if (!root.useGnova)
            return Lyrics.timeForIndex(index);
        if (!root.gnovaSynced || index < 0 || index >= root.gnovaLines.length)
            return -1;
        return root.gnovaLines[index].time;
    }

    onBusNameChanged: refreshGnova()
    onVisibleChanged: if (visible) refreshGnova()
    Component.onCompleted: refreshGnova()

    Connections {
        target: Players.active
        ignoreUnknownSignals: true
        function onTrackTitleChanged(): void {
            root.refreshGnova();
        }
    }

    Process {
        id: gnovaQuery

        stdout: StdioCollector {
            onStreamFinished: {
                let reply = null;
                try {
                    reply = JSON.parse(text);
                } catch (e) {}
                const d = reply?.data;
                if (!Array.isArray(d) || d.length < 3) {
                    root.gnovaSupported = false;
                    return;
                }
                root.gnovaSupported = true;
                root.gnovaTitle = d[1];
                if (d[0] !== root.gnovaStatus || d[0] === "ready")
                    root.parseGnova(d[0] === "ready" ? d[2] : "");
                root.gnovaStatus = d[0];
            }
        }
        onExited: code => {
            if (code !== 0)
                root.gnovaSupported = false;
            if (root.gnovaQueryAgain) {
                root.gnovaQueryAgain = false;
                root.refreshGnova();
            }
        }
    }

    // the player may still be loading the text, or it was edited there
    Timer {
        running: root.visible && root.gnovaSupported
        interval: 1500
        repeat: true
        onTriggered: root.refreshGnova()
    }

    readonly property real fadeAmount: 0.1
    property list<string> lyricList: root.useGnova ? root.gnovaLines.map(l => l.text) : Lyrics.lyrics

    layer.enabled: true
    layer.effect: Mask {
        maskSource: mask

        Rectangle {
            id: mask

            layer.enabled: true
            visible: false
            implicitWidth: root.width
            implicitHeight: root.height

            gradient: Gradient {
                orientation: Gradient.Vertical

                GradientStop {
                    color: Qt.alpha("black", 0)
                    position: 0
                }
                GradientStop {
                    color: Qt.alpha("black", 1)
                    position: root.fadeAmount
                }
                GradientStop {
                    color: Qt.alpha("black", 1)
                    position: 1 - root.fadeAmount
                }
                GradientStop {
                    color: Qt.alpha("black", 0)
                    position: 1
                }
            }
        }
    }

    state: {
        if (root.useGnova || Lyrics.hasLyrics)
            return "hasLyrics";
        if (Lyrics.loading || root.gnovaLoading)
            return "loading";
        return "noLyrics";
    }

    states: [
        State {
            name: "loading"

            PropertyChanges {
                loadingIndicator.opacity: 1
                lyrics.opacity: 0
                noLyrics.opacity: 0
            }
        },
        State {
            name: "hasLyrics"

            PropertyChanges {
                loadingIndicator.opacity: 0
                lyrics.opacity: 1
                noLyrics.opacity: 0
            }
        },
        State {
            name: "noLyrics"

            PropertyChanges {
                loadingIndicator.opacity: 0
                lyrics.opacity: 0
                noLyrics.opacity: 1
            }
        }
    ]

    transitions: [
        Transition {
            from: "loading"

            SequentialAnimation {
                Anim {
                    target: loadingIndicator
                    property: "opacity"
                    type: Anim.DefaultEffects
                }
                Anim {
                    targets: [lyrics, noLyrics]
                    property: "opacity"
                    type: Anim.SlowEffects
                }
            }
        },
        Transition {
            from: "hasLyrics"

            SequentialAnimation {
                Anim {
                    target: lyrics
                    property: "opacity"
                    type: Anim.DefaultEffects
                }
                Anim {
                    targets: [loadingIndicator, noLyrics]
                    property: "opacity"
                    type: Anim.SlowEffects
                }
            }
        },
        Transition {
            from: "noLyrics"

            SequentialAnimation {
                Anim {
                    target: noLyrics
                    property: "opacity"
                    type: Anim.DefaultEffects
                }
                Anim {
                    targets: [loadingIndicator, lyrics]
                    property: "opacity"
                    type: Anim.SlowEffects
                }
            }
        }
    ]

    Loader {
        id: loadingIndicator

        anchors.centerIn: parent
        asynchronous: true
        active: opacity > 0
        opacity: 0

        sourceComponent: ColumnLayout {
            spacing: Tokens.spacing.large

            StyledRect {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: shape.implicitSize + Tokens.padding.medium * 2
                implicitHeight: shape.implicitSize + Tokens.padding.medium * 2
                color: Colours.palette.m3primaryContainer
                radius: Tokens.rounding.full

                LoadingIndicator {
                    id: shape

                    anchors.centerIn: parent
                    implicitSize: Math.round(Tokens.sizes.dashboard.mediaSectionWidth / 5)
                    containsIcon: true // This removes the pentagon, which is not centered
                }
            }

            StyledText {
                text: Tr.tr("Loading lyrics...")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.title.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: noLyrics

        anchors.centerIn: parent
        asynchronous: true
        active: opacity > 0
        opacity: 0

        sourceComponent: ColumnLayout {
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "sentiment_sad"
                fontStyle: Tokens.font.icon.builders.large.scale(2).build()
                color: Colours.palette.m3outline
            }

            StyledText {
                text: Tr.tr("No lyrics found")
                color: Colours.palette.m3outline
                font: Tokens.font.title.medium
            }
        }
    }

    StyledListView {
        id: lyrics

        anchors.fill: parent
        anchors.topMargin: parent.height * root.fadeAmount / 2
        anchors.bottomMargin: parent.height * root.fadeAmount / 2

        displayMarginBeginning: anchors.topMargin
        displayMarginEnd: anchors.bottomMargin

        model: root.lyricList
        Component.onCompleted: {
            currentIndex = Qt.binding(() => {
                model; // Force update when lyrics change
                return root.indexForTime(Players.active?.position ?? 0);
            });
            positionViewAtIndex(currentIndex, ListView.Center);
        }
        onModelChanged: Qt.callLater(() => positionViewAtIndex(currentIndex, ListView.Center))

        highlightRangeMode: ListView.ApplyRange
        highlightMoveDuration: Tokens.anim.durations.large
        highlightMoveVelocity: -1
        preferredHighlightBegin: (height - (currentItem?.implicitHeight ?? 0)) / 2
        preferredHighlightEnd: (height + (currentItem?.implicitHeight ?? 0)) / 2

        spacing: Tokens.spacing.small
        opacity: 0
        enabled: opacity > 0

        delegate: StyledText {
            id: lyric

            required property string modelData
            required property int index
            property real effectScale: ListView.isCurrentItem ? 1 : 0

            anchors.left: lyrics.contentItem.left
            anchors.right: lyrics.contentItem.right

            text: modelData || ". . ."
            color: ListView.isCurrentItem ? Colours.palette.m3primary : mouse.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3outline
            font: Tokens.font.body.medium
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere

            layer.enabled: Effects.uiShadowsEnabled && effectScale > 0
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Colours.palette.m3primary
                shadowOpacity: Effects.shadowOpacity * lyric.effectScale
                shadowBlur: 0.6 * lyric.effectScale
                blurMax: Math.max(1, Math.round(Effects.shadowSize * Tokens.scale))
                blur: 0.4 * lyric.effectScale
            }

            Behavior on effectScale {
                Anim {
                    type: Anim.SlowEffects
                }
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    const p = Players.active;
                    const t = root.timeForIndex(lyric.index);
                    if (p && t >= 0)
                        p.position = t;
                }
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Behavior on lyricList {
        SequentialAnimation {
            Anim {
                target: lyrics
                property: "opacity"
                to: 0
                type: Anim.DefaultEffects
            }
            PropertyAction {}
            Anim {
                target: lyrics
                property: "opacity"
                to: 1
                type: Anim.SlowEffects
            }
        }
    }
}
