import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import QtCore

ApplicationWindow {
    id: root
    visible: true
    width: 1440
    height: 900
    minimumWidth: 1050
    minimumHeight: 680
    title: "Cutrix — Pixel Video Editor"
    color: theme.background

    property string currentTheme: projectStore.savedTheme()
    property string selectedMedia: ""
    property var mediaFiles: []
    property bool isPlaying: false
    property string playbackError: ""
    property url selectedMediaUrl: {
        for (var i = 0; i < mediaFiles.length; ++i)
            if (mediaFiles[i].name === selectedMedia) return mediaFiles[i].url
        return ""
    }
    property bool settingsOpen: false
    property int uiFontScale: projectStore.savedFontScale()
    property string currentProjectPath: ""
    property string currentProjectName: ""
    property string projectSearch: ""
    property string projectSort: "Последние"
    property var recentProjects: projectStore.recentProjects()
    property string statusMessage: "Готово · Cutrix Project Hub"
    property int mediaPanelWidth: 255
    property real timelinePosition: 0
    // Все элементы таймлайна используют один масштаб, чтобы линейка,
    // клипы и ползунок совпадали по времени.
    property real timelineDuration: {
        var end = 0
        for (var i = 0; i < mediaFiles.length; ++i) {
            if (Number(mediaFiles[i].track) >= 0)
                end = Math.max(end, Number(mediaFiles[i].start || 0) + Math.max(1, Number(mediaFiles[i].duration || 36)))
        }
        return end
    }
    property string timelinePreviewUrl: ""
    property real timelinePreviewClipStart: -1
    property bool timelinePreviewActive: false
    property real timelineSeekPending: -1

    function formatTime(seconds) {
        var value = Number(seconds)
        if (!isFinite(value) || value < 0) value = 0
        value = Math.floor(value)
        var minutes = Math.floor(value / 60)
        var remainingSeconds = value % 60
        return (minutes < 10 ? "0" : "") + minutes + ":" +
               (remainingSeconds < 10 ? "0" : "") + remainingSeconds
    }

    function saveTimelineMedia(items) {
        if (currentProjectPath !== "")
            projectStore.saveProjectMedia(currentProjectPath, items)
    }

    function timelineVideoAt(seconds) {
        var candidates = mediaFiles.filter(function(item) {
            return (Number(item.track) === 0 || Number(item.track) === 1)
                && item.kind !== "audio"
                && Number(item.start || 0) <= seconds
                && Number(item.start || 0) + Number(item.duration || 0) > seconds
        })
        if (candidates.length === 0) return null
        // V2 находится выше V1 и перекрывает его.
        candidates.sort(function(a, b) { return Number(a.track) - Number(b.track) })
        return candidates[0]
    }
    function selectMedia(name) {
        timelinePlaybackTimer.stop()
        mediaPlayer.pause()
        timelinePreviewActive = false
        timelinePreviewUrl = ""
        timelineSeekPending = -1
        selectedMedia = name
        statusMessage = "Выбран файл: " + name
    }

    function previewSelectedMedia() {
        if (selectedMediaUrl === "") return
        timelinePlaybackTimer.stop()
        timelinePreviewActive = false
        timelinePreviewUrl = ""
        timelineSeekPending = -1
        mediaPlayer.stop()
        // Источник задаётся binding-ом MediaPlayer.source выше; не разрываем его прямым присваиванием.
        mediaPlayer.play()
        statusMessage = "Предпросмотр файла: " + selectedMedia
    }

    function updateTimelinePreview(seconds) {
        var clip = timelineVideoAt(seconds)
        timelinePreviewActive = true
        if (!clip) {
            mediaPlayer.pause()
            timelinePreviewUrl = ""
            timelinePreviewClipStart = -1
            timelineSeekPending = -1
            return
        }
        var url = String(clip.url)
        var clipStart = Number(clip.start || 0)
        var offset = Math.max(0, seconds - clipStart)
        if (url !== String(timelinePreviewUrl)) {
            mediaPlayer.pause()
            timelinePreviewUrl = url
            timelinePreviewClipStart = clipStart
            timelineSeekPending = offset
        } else if (clipStart !== Number(timelinePreviewClipStart)) {
            // Same source, different timeline instance: pause and perform an explicit
            // seek before allowing the playback timer to advance the playhead.
            mediaPlayer.pause()
            timelinePreviewClipStart = clipStart
            timelineSeekPending = offset
        } else {
            var target = offset * 1000
            if (Math.abs(mediaPlayer.position - target) > 120) mediaPlayer.position = target
        }
    }

    readonly property var palettes: ({
        "Tokyo Night": { background: "#101522", panel: "#171f32", panelAlt: "#1d2942", border: "#30466f", text: "#d7e2ff", muted: "#8299c9", accent: "#7aa2f7", accent2: "#bb9af7", green: "#9ece6a" },
        "Everforest": { background: "#232a2e", panel: "#2d353b", panelAlt: "#374247", border: "#4b565c", text: "#d3c6aa", muted: "#9da9a0", accent: "#a7c080", accent2: "#d699b6", green: "#83c092" },
        "Catppuccin": { background: "#181825", panel: "#1e1e2e", panelAlt: "#313244", border: "#45475a", text: "#cdd6f4", muted: "#a6adc8", accent: "#89b4fa", accent2: "#cba6f7", green: "#a6e3a1" },
        "Rosé Pine": { background: "#191724", panel: "#1f1d2e", panelAlt: "#26233a", border: "#403d52", text: "#e0def4", muted: "#908caa", accent: "#c4a7e7", accent2: "#ebbcba", green: "#9ccfd8" }
    })
    readonly property var theme: palettes[currentTheme] || palettes["Tokyo Night"]

    function refreshProjects() { recentProjects = projectStore.recentProjects() }
    function openProject(path, name) {
        if (!projectStore.openProject(path)) { statusMessage = projectStore.lastError(); return }
        currentProjectPath = path
        currentProjectName = name || path.split("/").pop().replace(/\.cutrix$/, "")
        mediaFiles = projectStore.projectMedia(path)
        selectedMedia = mediaFiles.length > 0 ? mediaFiles[0].name : ""
        refreshProjects()
        statusMessage = "Открыт проект: " + currentProjectName
    }
    onCurrentThemeChanged: projectStore.saveAppearance(currentTheme, uiFontScale)
    onUiFontScaleChanged: projectStore.saveAppearance(currentTheme, uiFontScale)

    function fileNameFromUrl(url) {
        var value = String(url)
        var slash = value.lastIndexOf("/")
        return decodeURIComponent(value.substring(slash + 1))
    }

    function importSelectedFiles(urls) {
        var updated = root.mediaFiles.slice()
        var added = 0
        for (var i = 0; i < urls.length; ++i) {
            var url = urls[i].toString()
            var exists = false
            for (var j = 0; j < updated.length; ++j) {
                if (updated[j].url === url) { exists = true; break }
            }
            if (!exists) {
                var metadata = mediaTools.inspect(url)
                updated.push({
                    url: url,
                    name: fileNameFromUrl(url),
                    kind: metadata.kind || "unknown",
                    duration: metadata.duration || 0,
                    missing: !metadata.exists,
                    track: -1,
                    start: 0
                })
                ++added
            }
        }
        root.mediaFiles = updated
        if (root.currentProjectPath !== "")
            projectStore.saveProjectMedia(root.currentProjectPath, updated)
        if (updated.length > 0 && root.selectedMedia === "")
            root.selectedMedia = updated[0].name
        root.statusMessage = added > 0
            ? "Импортировано файлов: " + added + " · всего в медиатеке: " + updated.length
            : "Выбранные файлы уже есть в медиатеке"
    }

    // Pixel-style client title bar: Niri does not always provide native decorations.
    header: Rectangle {
        implicitHeight: 42
        color: theme.panel
        border.color: theme.border
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 5
            spacing: 8
            Text {
                text: "◆ CUTRIX"
                color: theme.accent
                font.family: "monospace"
                font.pixelSize: 15 * root.uiFontScale / 100
                font.bold: true
            }
            Text {
                text: "PIXEL VIDEO EDITOR / v0.1.0"
                color: theme.muted
                font.family: "monospace"
                font.pixelSize: 11 * root.uiFontScale / 100
                Layout.fillWidth: true
            }
            Repeater {
                model: [
                    { glyph: "—", tip: "Свернуть", action: 0 },
                    { glyph: "□", tip: "Развернуть", action: 1 },
                    { glyph: "×", tip: "Закрыть", action: 2 }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: 34
                    height: 30
                    color: titleButtonMouse.containsMouse
                           ? (modelData.action === 2 ? "#b94a58" : theme.panelAlt)
                           : "transparent"
                    border.color: titleButtonMouse.containsMouse ? theme.accent : theme.border
                    Text {
                        anchors.centerIn: parent
                        text: modelData.glyph
                        color: theme.text
                        font.family: "monospace"
                        font.pixelSize: 16 * root.uiFontScale / 100
                    }
                    MouseArea {
                        id: titleButtonMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.action === 0) root.showMinimized()
                            else if (modelData.action === 1)
                                root.visibility = root.visibility === Window.Maximized ? Window.Windowed : Window.Maximized
                            else root.close()
                        }
                    }
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton
            onPressed: root.startSystemMove()
        }
    }

    menuBar: MenuBar {
        palette.window: theme.panel
        palette.buttonText: theme.text
        palette.text: theme.text
        background: Rectangle {
            color: theme.panel
            border.color: theme.border
        }
        delegate: MenuBarItem {
            id: menuItem
            contentItem: Text {
                text: menuItem.text
                color: menuItem.highlighted ? theme.accent : theme.text
                font.family: "monospace"
                font.pixelSize: 12 * root.uiFontScale / 100
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
            }
            background: Rectangle {
                color: menuItem.highlighted ? theme.panelAlt : "transparent"
                border.color: menuItem.highlighted ? theme.accent : "transparent"
            }
        }
        Menu {
            title: "Файл"
            Action { text: "Импортировать медиа…"; onTriggered: importDialog.open() }
            Action { text: "Менеджер проектов"; onTriggered: { root.currentProjectPath = ""; root.refreshProjects() } }
            Action { text: "Закрыть проект"; onTriggered: { root.currentProjectPath = ""; root.refreshProjects() } }
            Action { text: "Сохранить проект"; onTriggered: { if (root.currentProjectPath !== "" && projectStore.saveProjectMedia(root.currentProjectPath, root.mediaFiles)) root.statusMessage = "Проект сохранён"; else root.statusMessage = projectStore.lastError() } }
            MenuSeparator {}
            Action { text: "Выход"; onTriggered: Qt.quit() }
        }
        Menu {
            title: "Правка"
            Action { text: "Отменить (скоро)"; onTriggered: root.statusMessage = "История действий появится позже" }
            Action { text: "Повторить (скоро)"; onTriggered: root.statusMessage = "История действий появится позже" }
        }
        Menu {
            title: "Воспроизведение"
            Action { text: mediaPlayer.playbackState === MediaPlayer.PlayingState ? "Пауза" : "Воспроизвести"; enabled: root.selectedMediaUrl !== ""; onTriggered: { if (mediaPlayer.playbackState === MediaPlayer.PlayingState) mediaPlayer.pause(); else mediaPlayer.play() } }
        }
        Menu {
            title: "Справка"
            Action { text: "О Cutrix"; onTriggered: aboutDialog.open() }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.currentProjectPath === ""
        color: theme.background
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 26
            spacing: 18
            RowLayout {
                Layout.fillWidth: true
                Text { text: "◆ CUTRIX"; color: theme.accent; font.family: "monospace"; font.bold: true; font.pixelSize: 30 }
                Text { text: "PROJECT HUB / v0.2"; color: theme.muted; font.family: "monospace"; font.pixelSize: 13; Layout.fillWidth: true }
                Button { text: "⚙ ТЕМА И ВИД"; onClicked: settingsDialog.open(); palette.buttonText: theme.text; background: Rectangle { color: theme.panel; border.color: theme.border; radius: 0 } }
            }
            Rectangle { Layout.fillWidth: true; height: 2; color: theme.accent }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "ПРОЕКТЫ"; color: theme.text; font.family: "monospace"; font.bold: true; font.pixelSize: 19 }
                Item { Layout.fillWidth: true }
                TextField { Layout.preferredWidth: 230; placeholderText: "⌕ Поиск проектов..."; text: root.projectSearch; onTextChanged: root.projectSearch = text; color: theme.text; placeholderTextColor: theme.muted; background: Rectangle { color: theme.panel; border.color: theme.border; radius: 0 } }
                ComboBox { model: ["Последние", "По названию"]; currentIndex: root.projectSort === "Последние" ? 0 : 1; onActivated: root.projectSort = currentText; palette.text: theme.text; background: Rectangle { color: theme.panel; border.color: theme.border; radius: 0 } }
            }
            RowLayout {
                Layout.fillWidth: true
                Button { text: "＋ НОВЫЙ ПРОЕКТ"; onClicked: { projectNameField.text = "Мой проект"; newProjectDialog.open() } palette.buttonText: theme.background; background: Rectangle { color: theme.accent; border.color: theme.accent; radius: 0 } }
                Button { text: "↗ ОТКРЫТЬ ПРОЕКТ"; onClicked: projectOpenDialog.open(); palette.buttonText: theme.text; background: Rectangle { color: theme.panel; border.color: theme.border; radius: 0 } }
                Item { Layout.fillWidth: true }
                Text { text: root.recentProjects.length + " ПРОЕКТОВ"; color: theme.muted; font.family: "monospace"; font.pixelSize: 12 }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: width; contentHeight: projectGrid.implicitHeight; clip: true
                GridLayout {
                    id: projectGrid
                    width: parent.width
                    columns: width > 900 ? 4 : width > 600 ? 3 : 2
                    columnSpacing: 14; rowSpacing: 14
                    Repeater {
                        model: {
                            var items = root.recentProjects.filter(function(p) { return p.name.toLowerCase().indexOf(root.projectSearch.toLowerCase()) !== -1 })
                            if (root.projectSort === "По названию") items.sort(function(a,b) { return a.name.localeCompare(b.name) })
                            return items
                        }
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; Layout.preferredHeight: 190
                            color: theme.panel; border.color: theme.border
                            ColumnLayout {
                                anchors.fill: parent; spacing: 0
                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: 112
                                    color: theme.panelAlt; border.color: theme.border
                                    Text { anchors.centerIn: parent; text: "▧"; color: theme.accent; font.family: "monospace"; font.pixelSize: 42 }
                                    Text { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8; text: modelData.resolution + " · " + modelData.fps + " FPS"; color: theme.muted; font.family: "monospace"; font.pixelSize: 10 }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 9; spacing: 4
                                    Text { Layout.fillWidth: true; text: modelData.name; color: theme.text; font.family: "monospace"; font.bold: true; elide: Text.ElideRight }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: modelData.modified; color: theme.muted; font.family: "monospace"; font.pixelSize: 10; elide: Text.ElideRight }
                                        Button { text: "ОТКРЫТЬ"; onClicked: root.openProject(modelData.path, modelData.name); palette.buttonText: theme.accent; background: Rectangle { color: theme.background; border.color: theme.border; radius: 0 } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Text { Layout.fillWidth: true; visible: root.recentProjects.length === 0; text: "ПОКА НЕТ ПРОЕКТОВ\n\nСоздай новый проект или открой файл .cutrix. Список недавних проектов сохранится между запусками."; color: theme.muted; font.family: "monospace"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter }
            Text { text: root.statusMessage; color: theme.muted; font.family: "monospace"; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
        }
    }

    Timer {
        id: timelinePlaybackTimer
        interval: 33
        repeat: true
        onTriggered: {
            if (root.timelineDuration <= 0) {
                stop()
                mediaPlayer.pause()
                return
            }
            var currentClip = root.timelineVideoAt(root.timelinePosition)
            if (currentClip) {
                // A seek can be pending even when the source URL did not change
                // (two timeline clips may reference the same file).
                if (root.timelineSeekPending >= 0
                        && String(currentClip.url) === String(root.timelinePreviewUrl)
                        && Number(currentClip.start || 0) === Number(root.timelinePreviewClipStart)
                        && (mediaPlayer.mediaStatus === MediaPlayer.LoadedMedia
                            || mediaPlayer.mediaStatus === MediaPlayer.BufferedMedia)) {
                    var seekTarget = root.timelineSeekPending * 1000
                    mediaPlayer.position = seekTarget
                    root.timelineSeekPending = -1
                    mediaPlayer.play()
                    return
                }
                // Do not advance the playhead while the decoder switches to this clip.
                // Otherwise the timeline can pass the entire clip before it starts playing.
                if (String(currentClip.url) !== String(root.timelinePreviewUrl)
                        || Number(currentClip.start || 0) !== Number(root.timelinePreviewClipStart)
                        || root.timelineSeekPending >= 0
                        || (mediaPlayer.mediaStatus !== MediaPlayer.LoadedMedia
                            && mediaPlayer.mediaStatus !== MediaPlayer.BufferedMedia)) {
                    root.updateTimelinePreview(root.timelinePosition)
                    return
                }
                if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
                    // The decoder is the clock while video is playing.
                    root.timelinePosition = Number(currentClip.start || 0) + mediaPlayer.position / 1000
                } else {
                    mediaPlayer.play()
                    return
                }
            } else {
                // Empty timeline gaps advance in timeline time, not decoder time.
                root.timelinePosition = Math.min(root.timelineDuration,
                                                 root.timelinePosition + interval / 1000)
            }
            if (root.timelinePosition >= root.timelineDuration) {
                root.timelinePosition = root.timelineDuration
                stop()
                mediaPlayer.pause()
                return
            }
            root.updateTimelinePreview(root.timelinePosition)
        }
    }

    MediaPlayer {
        id: mediaPlayer
        source: root.timelinePreviewActive ? root.timelinePreviewUrl : root.selectedMediaUrl
        videoOutput: videoOutput
        audioOutput: AudioOutput {}
        onPlaybackStateChanged: root.isPlaying = playbackState === MediaPlayer.PlayingState
        onErrorOccurred: function(error, errorString) {
            root.playbackError = errorString
            root.statusMessage = "Ошибка воспроизведения: " + errorString
        }
        onSourceChanged: {
            root.playbackError = ""
            root.isPlaying = false
            if (source.toString() !== "") root.statusMessage = "Загружаю видео: " + root.selectedMedia
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) {
                if (root.timelineSeekPending >= 0) {
                    mediaPlayer.position = root.timelineSeekPending * 1000
                    root.timelineSeekPending = -1
                    if (timelinePlaybackTimer.running) mediaPlayer.play()
                } else if (root.timelinePreviewUrl === "") {
                    root.statusMessage = "Видео загружено: " + root.selectedMedia
                }
            } else if (mediaStatus === MediaPlayer.InvalidMedia) {
                root.statusMessage = "Не удалось открыть видео. Проверь формат и кодеки."
            }
        }
    }

    property string pendingProjectName: ""
    property string pendingResolution: "1920×1080"
    property int pendingFps: 30

    Dialog {
        id: newProjectDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 430
        title: ""
        padding: 0
        standardButtons: Dialog.NoButton
        background: Rectangle { color: theme.background; border.color: theme.accent; border.width: 2; radius: 0 }
        contentItem: ColumnLayout {
            spacing: 0
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                color: theme.panelAlt
                border.color: theme.border
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "◆ НОВЫЙ ПРОЕКТ"
                    color: theme.accent
                    font.family: "monospace"
                    font.bold: true
                    font.pixelSize: 14
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                spacing: 8
                Text { text: "СОЗДАНИЕ ПРОЕКТА"; color: theme.muted; font.family: "monospace"; font.bold: true; font.pixelSize: 11 }
            TextField { id: projectNameField; Layout.fillWidth: true; placeholderText: "Название проекта"; text: "Мой проект"; color: theme.text; placeholderTextColor: theme.muted; background: Rectangle { color: theme.panel; border.color: theme.border; radius: 0 } }
            Text { text: "РАЗРЕШЕНИЕ"; color: theme.muted; font.family: "monospace" }
            ComboBox {
                id: resolutionBox
                Layout.fillWidth: true
                model: ["1920×1080", "2560×1440", "3840×2160", "1280×720"]
                currentIndex: 0
                palette.text: theme.text
                palette.window: theme.panel
                palette.base: theme.panel
                palette.highlight: theme.panelAlt
                palette.highlightedText: theme.accent
                contentItem: Text {
                    leftPadding: 8
                    rightPadding: 28
                    text: resolutionBox.displayText
                    color: theme.text
                    font.family: "monospace"
                    verticalAlignment: Text.AlignVCenter
                }
                indicator: Text {
                    x: resolutionBox.width - width - 10
                    y: (resolutionBox.height - height) / 2
                    text: "▼"
                    color: theme.accent
                    font.pixelSize: 10
                }
                background: Rectangle { color: theme.panel; border.color: theme.border; radius: 0 }
                delegate: ItemDelegate {
                    width: resolutionBox.width
                    contentItem: Text {
                        text: modelData
                        color: highlighted ? theme.accent : theme.text
                        font.family: "monospace"
                        verticalAlignment: Text.AlignVCenter
                    }
                    highlighted: resolutionBox.highlightedIndex === index
                    background: Rectangle {
                        color: parent.highlighted ? theme.panelAlt : theme.panel
                        border.color: parent.highlighted ? theme.accent : theme.border
                    }
                }
                popup: Popup {
                    y: resolutionBox.height
                    width: resolutionBox.width
                    padding: 1
                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: resolutionBox.delegateModel
                        currentIndex: resolutionBox.highlightedIndex
                    }
                    background: Rectangle { color: theme.panel; border.color: theme.accent; border.width: 1 }
                }
            }
            Text { text: "ЧАСТОТА КАДРОВ"; color: theme.muted; font.family: "monospace" }
            ComboBox {
                id: fpsBox
                Layout.fillWidth: true
                model: ["24 FPS", "25 FPS", "30 FPS", "50 FPS", "60 FPS"]
                currentIndex: 2
                palette.text: theme.text
                palette.window: theme.panel
                palette.base: theme.panel
                palette.highlight: theme.panelAlt
                palette.highlightedText: theme.accent
                contentItem: Text {
                    leftPadding: 8
                    rightPadding: 28
                    text: fpsBox.displayText
                    color: theme.text
                    font.family: "monospace"
                    verticalAlignment: Text.AlignVCenter
                }
                indicator: Text {
                    x: fpsBox.width - width - 10
                    y: (fpsBox.height - height) / 2
                    text: "▼"
                    color: theme.accent
                    font.pixelSize: 10
                }
                background: Rectangle { color: theme.panel; border.color: theme.border; radius: 0 }
                delegate: ItemDelegate {
                    width: fpsBox.width
                    contentItem: Text {
                        text: modelData
                        color: highlighted ? theme.accent : theme.text
                        font.family: "monospace"
                        verticalAlignment: Text.AlignVCenter
                    }
                    highlighted: fpsBox.highlightedIndex === index
                    background: Rectangle {
                        color: parent.highlighted ? theme.panelAlt : theme.panel
                        border.color: parent.highlighted ? theme.accent : theme.border
                    }
                }
                popup: Popup {
                    y: fpsBox.height
                    width: fpsBox.width
                    padding: 1
                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: fpsBox.delegateModel
                        currentIndex: fpsBox.highlightedIndex
                    }
                    background: Rectangle { color: theme.panel; border.color: theme.accent; border.width: 1 }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Button { text: "ОТМЕНА"; onClicked: newProjectDialog.close(); palette.buttonText: theme.text; background: Rectangle { color: theme.panel; border.color: theme.border; radius: 0 } }
                Item { Layout.fillWidth: true }
                Button {
                    text: "СОЗДАТЬ И СОХРАНИТЬ"
                    onClicked: {
                        if (projectNameField.text.trim() === "") { root.statusMessage = "Введи название проекта"; return }
                        root.pendingProjectName = projectNameField.text.trim()
                        root.pendingResolution = resolutionBox.currentText
                        root.pendingFps = parseInt(fpsBox.currentText)
                        var path = projectStore.chooseProjectSavePath(root.pendingProjectName)
                        if (path === "") return
                        if (!path.toLowerCase().endsWith(".cutrix")) path += ".cutrix"
                        if (projectStore.createProject(path, root.pendingProjectName, root.pendingResolution, root.pendingFps)) {
                            root.openProject(path, root.pendingProjectName)
                            newProjectDialog.close()
                        } else {
                            root.statusMessage = projectStore.lastError()
                        }
                    }
                    palette.buttonText: theme.background
                    background: Rectangle { color: theme.accent; border.color: theme.accent; radius: 0 }
                }
            }
            }
        }
    }

    FileDialog {
        id: projectOpenDialog
        title: "Открыть проект Cutrix"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Проект Cutrix (*.cutrix)", "Все файлы (*)"]
        onAccepted: {
            var path = selectedFile.toString()
            if (path.startsWith("file://")) path = decodeURIComponent(path.substring(7))
            root.openProject(path, "")
        }
    }

    FileDialog {
        id: importDialog
        title: "Импортировать медиа в Cutrix"
        fileMode: FileDialog.OpenFiles
        nameFilters: [
            "Медиафайлы (*.mp4 *.mov *.mkv *.webm *.avi *.mp3 *.wav *.flac *.ogg *.png *.jpg *.jpeg *.webp)",
            "Все файлы (*)"
        ]
        onAccepted: root.importSelectedFiles(selectedFiles)
    }

    Dialog {
        id: aboutDialog
        title: "О Cutrix"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Ok
        contentItem: Text {
            text: "Cutrix 0.1.0\nПиксельный видеоредактор для Linux.\nЭто UI-прототип; видеодвижок ещё не подключён."
            color: theme.text
            font.family: "monospace"
            wrapMode: Text.WordWrap
            padding: 12
        }
        background: Rectangle { color: theme.panel; border.color: theme.border }
    }

    Dialog {
        id: settingsDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 520
        height: 430
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: root.settingsOpen = true
        onClosed: root.settingsOpen = false

        background: Rectangle {
            color: theme.background
            border.color: theme.accent
            border.width: 2
            radius: 0
        }

        contentItem: ColumnLayout {
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                height: 44
                color: theme.panel
                border.color: theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 8
                    Text {
                        text: "◆ CUTRIX / НАСТРОЙКИ"
                        color: theme.accent
                        font.family: "monospace"
                        font.pixelSize: (15 * root.uiFontScale / 100)
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Button {
                        text: "×"
                        onClicked: settingsDialog.close()
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.panelAlt; border.color: theme.border; radius: 0 }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 18
                spacing: 14

                Text { text: "ВНЕШНИЙ ВИД"; color: theme.accent; font.family: "monospace"; font.pixelSize: (14 * root.uiFontScale / 100); font.bold: true }
                Text { text: "Цветовая тема"; color: theme.text; font.family: "monospace"; font.pixelSize: (13 * root.uiFontScale / 100) }
                ComboBox {
                    Layout.fillWidth: true
                    model: ["Tokyo Night", "Everforest", "Catppuccin", "Rosé Pine"]
                    currentIndex: model.indexOf(root.currentTheme)
                    onActivated: root.currentTheme = currentText
                    palette.text: theme.text
                    palette.buttonText: theme.text
                    background: Rectangle { color: theme.panel; border.color: theme.accent; radius: 0 }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                Text { text: "Размер текста интерфейса"; color: theme.text; font.family: "monospace"; font.pixelSize: (13 * root.uiFontScale / 100) }
                RowLayout {
                    Layout.fillWidth: true
                    Slider {
                        Layout.fillWidth: true
                        from: 100
                        to: 130
                        stepSize: 5
                        value: root.uiFontScale
                        onMoved: root.uiFontScale = value
                    }
                    Text { text: root.uiFontScale + "%"; color: theme.accent; font.family: "monospace"; font.pixelSize: (13 * root.uiFontScale / 100) }
                }
                Text {
                    text: "Пример: МЕДИАФАЙЛЫ · Настройки · city.mp4"
                    color: theme.muted
                    font.family: "monospace"
                    font.pixelSize: 12 * root.uiFontScale / 100
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillHeight: true }
                Text { text: "Изменения темы применяются сразу."; color: theme.muted; font.family: "monospace"; font.pixelSize: (11 * root.uiFontScale / 100) }
            }
        }
    }

    ColumnLayout {
        visible: root.currentProjectPath !== ""
        anchors.fill: parent
        anchors.margins: 8
        spacing: 7

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 7

            Rectangle {
                Layout.preferredWidth: 126
                Layout.fillHeight: true
                color: theme.panel
                border.color: theme.border
                Column {
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 5
                    Repeater {
                        model: [["▣", "Медиа"], ["✣", "Эффекты"], ["◈", "Переходы"], ["T", "Текст"], ["✿", "Стикеры"], ["♫", "Аудио"], ["⚙", "Настройки"]]
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 39
                            color: modelData[1] === "Медиа" || (modelData[1] === "Настройки" && root.settingsOpen) ? theme.panelAlt : "transparent"
                            border.color: modelData[1] === "Медиа" || (modelData[1] === "Настройки" && root.settingsOpen) ? theme.border : "transparent"
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                spacing: 8
                                Text { text: modelData[0]; color: theme.accent; font.family: "monospace"; font.pixelSize: (19 * root.uiFontScale / 100); anchors.verticalCenter: parent.verticalCenter }
                                Text { text: modelData[1]; color: theme.text; font.family: "monospace"; font.pixelSize: (13 * root.uiFontScale / 100); anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData[1] === "Настройки") settingsDialog.open()
                                    else root.statusMessage = modelData[1] + " — раздел пока в разработке"
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: mediaPanel
                Layout.preferredWidth: root.mediaPanelWidth
                Layout.minimumWidth: 180
                Layout.maximumWidth: 440
                Layout.fillHeight: true
                color: theme.panel
                border.color: theme.border
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 8
                    Text { text: "МЕДИАФАЙЛЫ"; color: theme.accent; font.family: "monospace"; font.bold: true }
                    TextField {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: mediaPanel.width - 18
                        placeholderText: "Поиск медиа…"
                        color: theme.text
                        placeholderTextColor: theme.muted
                        background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                    }
                    Button {
                        text: "+ Импортировать"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: mediaPanel.width - 18
                        Layout.preferredHeight: 34
                        leftPadding: 5
                        rightPadding: 5
                        font.family: "monospace"
                        font.pixelSize: 11
                        onClicked: importDialog.open()
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.panelAlt; border.color: theme.accent; radius: 2 }
                    }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: mediaGrid.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        GridLayout {
                            id: mediaGrid
                            width: Math.max(0, parent.width)
                            columns: width >= 300 ? 3 : width >= 190 ? 2 : 1
                            columnSpacing: 5
                            rowSpacing: 5
                            Repeater {
                                model: root.mediaFiles
                                delegate: Rectangle {
                                    id: mediaCard
                                    required property var modelData
                                    Layout.preferredWidth: Math.max(0, (mediaGrid.width - 10) / 3)
                                    Layout.maximumWidth: Math.max(0, (mediaGrid.width - 10) / 3)
                                    Layout.minimumWidth: 0
                                    Layout.preferredHeight: 68
                                clip: true
                                opacity: cardDrag.active ? 0.72 : 1.0
                                scale: cardDrag.active ? 0.96 : 1.0
                                color: cardDrag.active ? theme.panelAlt : theme.background
                                border.width: cardDrag.active ? 2 : 1
                                border.color: cardDrag.active ? theme.accent2 : (root.selectedMedia === modelData.name ? theme.accent : theme.border)

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        spacing: 2
                                        Rectangle {
                                            width: parent.width
                                            height: 48
                                        color: theme.panelAlt
                                        border.color: theme.border
                                        clip: true
                                        Image {
                                            id: mediaThumbnail
                                            anchors.fill: parent
                                            source: mediaCard.modelData.missing ? "" : mediaTools.thumbnail(mediaCard.modelData.url)
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: mediaThumbnail.status !== Image.Ready
                                            text: mediaCard.modelData.missing ? "!" :
                                                  mediaCard.modelData.kind === "audio" ? "♫" :
                                                  mediaCard.modelData.kind === "image" ? "▧" : "▶"
                                            color: theme.accent
                                            font.pixelSize: 20
                                            font.family: "monospace"
                                        }
                                        Text {
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 3
                                            text: (mediaCard.modelData.kind || "media").toUpperCase()
                                            color: theme.text
                                            font.family: "monospace"
                                            font.pixelSize: 8
                                        }
                                    }
                                    Text {
                                        width: parent.width
                                        text: mediaCard.modelData.name
                                        color: theme.text
                                        font.family: "monospace"
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                }

                                Drag.active: cardDrag.active
                                Drag.source: mediaCard
                                Drag.dragType: Drag.Automatic
                                Drag.mimeData: ({ "text/plain": String(mediaCard.modelData.url) })
                                Drag.supportedActions: Qt.CopyAction
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: width / 2
                                DragHandler {
                                    id: cardDrag
                                    target: null
                                    onActiveChanged: {
                                        if (active) {
                                            root.selectMedia(mediaCard.modelData.name)
                                            root.statusMessage = "Перетаскиваю: " + mediaCard.modelData.name
                                        } else {
                                            mediaCard.Drag.drop()
                                        }
                                    }
                                }
                                TapHandler {
                                    onTapped: root.selectMedia(mediaCard.modelData.name)
                                }
                            }
                        }
                            Text {
                                Layout.fillWidth: true
                                visible: root.mediaFiles.length === 0
                                text: "Медиатека пуста. Импортируй файлы, затем перетащи их на дорожку."
                                color: theme.muted
                                font.family: "monospace"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Text { text: "Миниатюры видео создаются через FFmpeg; для аудио показана карточка файла."; color: theme.muted; font.family: "monospace"; font.pixelSize: (11 * root.uiFontScale / 100); wrapMode: Text.WordWrap }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 300
                color: theme.panel
                border.color: theme.border
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "ПРЕДПРОСМОТР"; color: theme.accent; font.family: "monospace"; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Text { text: "16:9 · 1080p"; color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#10182d"
                        border.color: theme.border
                        clip: true

                        VideoOutput {
                            id: videoOutput
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectFit
                            visible: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: !mediaPlayer.hasVideo
                            color: theme.background
                            Column {
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "◆ CUTRIX"
                                    color: theme.accent
                                    font.family: "monospace"
                                    font.pixelSize: 22
                                    font.bold: true
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.selectedMedia === "" ? "ИМПОРТИРУЙ МЕДИА" :
                                          mediaPlayer.errorString !== "" ? mediaPlayer.errorString :
                                          mediaPlayer.mediaStatus === MediaPlayer.LoadingMedia ? "ЗАГРУЗКА МЕДИА…" :
                                          mediaPlayer.mediaStatus === MediaPlayer.InvalidMedia ? "НЕ УДАЛОСЬ ПРОЧИТАТЬ ФАЙЛ" :
                                          "НАЖМИ «ВОСПРОИЗВЕСТИ»"
                                    color: theme.muted
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: root.formatTime(mediaPlayer.position / 1000) + " / " + root.formatTime(mediaPlayer.duration / 1000); color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: "▶ Файл"
                            enabled: root.selectedMediaUrl !== ""
                            onClicked: root.previewSelectedMedia()
                            palette.buttonText: theme.text
                            background: Rectangle { color: theme.panelAlt; border.color: theme.border; radius: 2 }
                        }
                        Button {
                            text: timelinePlaybackTimer.running ? "Ⅱ Монтаж" : "▶ Монтаж"
                            enabled: root.timelineDuration > 0 || root.selectedMediaUrl !== ""
                            onClicked: {
                                if (timelinePlaybackTimer.running) {
                                    timelinePlaybackTimer.stop()
                                    mediaPlayer.pause()
                                } else if (root.timelineDuration > 0) {
                                    if (root.timelinePosition >= root.timelineDuration) root.timelinePosition = 0
                                    root.updateTimelinePreview(root.timelinePosition)
                                    timelinePlaybackTimer.start()
                                } else {
                                    root.timelinePreviewActive = false
                                    mediaPlayer.play()
                                }
                            }
                            palette.buttonText: theme.text
                            background: Rectangle { color: theme.panelAlt; border.color: theme.border; radius: 2 }
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 225
                Layout.fillHeight: true
                color: theme.panel
                border.color: theme.border
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 9
                    Text { text: "СВОЙСТВА"; color: theme.accent; font.family: "monospace"; font.bold: true }
                    Text { text: root.selectedMedia === "" ? "Файл не выбран" : root.selectedMedia; color: theme.text; font.family: "monospace"; font.pixelSize: (13 * root.uiFontScale / 100); wrapMode: Text.Wrap }
                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                    Text { text: "ПОЗИЦИЯ И МАСШТАБ"; color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                    Repeater {
                        model: [["X", "0.0"], ["Y", "0.0"], ["Масштаб", "100%"], ["Поворот", "0°"]]
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text { text: modelData[0]; color: theme.text; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100); Layout.fillWidth: true }
                            Text { text: modelData[1]; color: theme.accent; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                    Text { text: "ЦВЕТОКОРРЕКЦИЯ"; color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                    Repeater {
                        model: ["Яркость", "Контраст", "Насыщенность"]
                        delegate: ColumnLayout {
                            required property string modelData
                            Layout.fillWidth: true
                            Text { text: modelData; color: theme.text; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                            Slider { Layout.fillWidth: true; from: -1; to: 1; value: 0 }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                    Text { text: "ЭКСПОРТ"; color: theme.accent; font.family: "monospace"; font.bold: true }
                    Text { text: "MP4 · H.264 · 1920×1080"; color: theme.text; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100); wrapMode: Text.WordWrap }
                    Button {
                        text: "↗ Экспорт (скоро)"
                        Layout.fillWidth: true
                        onClicked: root.statusMessage = "Экспорт добавим после подключения FFmpeg"
                        palette.buttonText: "#101522"
                        background: Rectangle { color: theme.accent; border.color: theme.accent; radius: 2 }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 230
            Layout.minimumHeight: 230
            color: theme.panel
            border.color: theme.border
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "↶  ↷   ✂   ◫   ✦"; color: theme.accent; font.family: "monospace"; font.pixelSize: (18 * root.uiFontScale / 100) }
                    Item { Layout.fillWidth: true }
                    Text { text: "МАСШТАБ  − ━━━━━●━━ +"; color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0
                    Column {
                        Layout.preferredWidth: 150
                        Layout.fillHeight: true
                        spacing: 3
                        Repeater {
                            model: ["V2 · ВИДЕО", "V1 · ВИДЕО", "A1 · АУДИО", "A2 · АУДИО"]
                            delegate: Rectangle {
                                required property string modelData
                                width: parent.width
                                height: 25
                                color: theme.panelAlt
                                border.color: theme.border
                                Text { anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: theme.text; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                            }
                        }
                    }
                    Item {
                        id: timelineCanvas
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        // Подгоняем весь проект под видимую ширину. Линейка,
                        // клипы, перетаскивание и playhead используют этот масштаб.
                        property real timelineScale: width > 0
                            ? width / Math.max(root.timelineDuration, 35)
                            : 1
                        Column {
                            anchors.fill: parent
                            spacing: 3
                            Rectangle {
                                width: parent.width
                                height: 22
                                color: theme.background
                                Row {
                                    anchors.fill: parent
                                    Repeater {
                                        model: 7
                                        delegate: Text {
                                            required property int index
                                            width: parent.width / 7
                                            text: root.formatTime(root.timelineDuration * index / 6)
                                            color: theme.muted
                                            font.family: "monospace"
                                            font.pixelSize: (12 * root.uiFontScale / 100)
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                            Repeater {
                                model: ["V2", "V1", "A1", "A2"]
                                delegate: Item {
                                    id: timelineTrack
                                    required property string modelData
                                    required property int index
                                    property bool dropHover: false
                                    width: parent.width
                                    height: 34
                                    Rectangle {
                                        anchors.fill: parent
                                        color: timelineTrack.dropHover ? theme.accent2 : (index % 2 === 0 ? theme.panel : theme.background)
                                        border.color: timelineTrack.dropHover ? theme.accent : theme.border
                                        opacity: timelineTrack.dropHover ? 0.55 : 0.95
                                    }
                                    Repeater {
                                        model: root.mediaFiles.filter(function(m) { return Number(m.track) === timelineTrack.index })
                                        delegate: Rectangle {
                                            id: timelineClip
                                            required property var modelData
                                            x: Math.max(0, Number(modelData.start || 0) * timelineCanvas.timelineScale)
                                            width: Math.max(3, Number(modelData.duration || 36) * timelineCanvas.timelineScale)
                                            height: 30
                                            y: 2
                                            clip: true
                                            color: /\\.(mp3|wav|flac|ogg|m4a|aac)$/i.test(modelData.name) ? "#226d6c" : "#315b9b"
                                            border.color: theme.accent
                                            Row {
                                                anchors.fill: parent
                                                clip: true
                                                visible: !/\.(mp3|wav|flac|ogg|m4a|aac)$/i.test(timelineClip.modelData.name)
                                                Repeater {
                                                    model: Math.max(1, Math.ceil(timelineClip.width / 54))
                                                    delegate: Image {
                                                        required property int index
                                                        width: 54
                                                        height: parent.height
                                                        source: mediaTools.thumbnailAt(timelineClip.modelData.url,
                                                            Math.max(0, Number(timelineClip.modelData.start || 0) + index * (54 / Math.max(0.001, timelineCanvas.timelineScale))))
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        visible: !timelineClip.draggingClip
                                                        opacity: 0.7
                                                    }
                                                }
                                            }
                                            Text {
                                                anchors.fill: parent
                                                anchors.leftMargin: 5
                                                text: modelData.name
                                                color: "#f0f2ff"
                                                font.family: "monospace"
                                                font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                            property real dragStartX: 0
                                            property real dragStartY: 0
                                            property real dragStartTimeline: 0
                                            property real dragStartClipX: 0
                                            property real dragStartClipY: 2
                                            property bool draggingClip: false
                                            z: draggingClip ? 10 : 1
                                            MouseArea {
                                                anchors.fill: parent
                                                preventStealing: true
                                                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                                onPressed: function(mouse) {
                                                    var scenePos = mapToItem(timelineCanvas, mouse.x, mouse.y)
                                                    dragStartX = scenePos.x
                                                    dragStartY = scenePos.y
                                                    dragStartTimeline = Number(timelineClip.modelData.start || 0)
                                                    dragStartClipX = timelineClip.x
                                                    dragStartClipY = timelineClip.y
                                                    draggingClip = false
                                                }
                                                onPositionChanged: function(mouse) {
                                                    if (!pressed) return
                                                    var scenePos = mapToItem(timelineCanvas, mouse.x, mouse.y)
                                                    var dx = scenePos.x - dragStartX
                                                    var dy = scenePos.y - dragStartY
                                                    if (!draggingClip && Math.abs(dx) + Math.abs(dy) > 4)
                                                        draggingClip = true
                                                    if (!draggingClip) return
                                                    timelineClip.x = Math.max(0, Math.min(timelineTrack.width - timelineClip.width,
                                                                                          dragStartClipX + dx))
                                                    timelineClip.y = Math.max(-timelineClip.height - 2,
                                                                              Math.min(timelineTrack.height + 2,
                                                                                       dragStartClipY + dy))
                                                }
                                                onReleased: function(mouse) {
                                                    var wasDragging = draggingClip
                                                    var scenePos = mapToItem(timelineCanvas, mouse.x, mouse.y)
                                                    draggingClip = false
                                                    timelineClip.y = 2
                                                    if (!wasDragging) return

                                                    var updated = root.mediaFiles.slice()
                                                    var movingIndex = -1
                                                    for (var i = 0; i < updated.length; ++i) {
                                                        if (String(updated[i].url) === String(timelineClip.modelData.url)
                                                                && Number(updated[i].track) === Number(timelineClip.modelData.track)
                                                                && Number(updated[i].start || 0) === Number(timelineClip.modelData.start || 0)
                                                                && String(updated[i].name) === String(timelineClip.modelData.name)) {
                                                            movingIndex = i
                                                            break
                                                        }
                                                    }
                                                    if (movingIndex < 0) {
                                                        timelineClip.x = dragStartClipX
                                                        return
                                                    }

                                                    var duration = Math.max(1, Number(updated[movingIndex].duration || 36))
                                                    var desiredStart = Math.max(0, Math.round(timelineClip.x / Math.max(0.001, timelineCanvas.timelineScale)))
                                                    // Snap vertically to one of the four tracks using the pointer position
                                                    // in the fixed canvas, not the clip's temporary y coordinate.
                                                    var targetTrack = Math.max(0, Math.min(3, Math.round((scenePos.y - 42) / 37)))
                                                    var obstacles = updated.filter(function(item, index) {
                                                        return index !== movingIndex && Number(item.track) === targetTrack
                                                    })
                                                    var overlapsAt = function(start) {
                                                        return obstacles.some(function(item) {
                                                            var otherStart = Math.max(0, Number(item.start || 0))
                                                            var otherEnd = otherStart + Math.max(1, Number(item.duration || 36))
                                                            return start < otherEnd && start + duration > otherStart
                                                        })
                                                    }
                                                    // Moving to another track is an intentional overlay (for example,
                                                    // the same source clip on V1 and V2). Only prevent collisions
                                                    // when the clip stays on its current track.
                                                    if (targetTrack === Number(updated[movingIndex].track)
                                                            && overlapsAt(desiredStart)) {
                                                        var step = desiredStart >= dragStartTimeline ? 1 : -1
                                                        var candidate = desiredStart
                                                        var attempts = 0
                                                        while (candidate >= 0 && overlapsAt(candidate) && attempts < 10000) {
                                                            candidate += step
                                                            attempts++
                                                        }
                                                        if (candidate < 0 || attempts >= 10000) {
                                                            candidate = dragStartTimeline
                                                            targetTrack = Number(updated[movingIndex].track)
                                                            root.statusMessage = "Не удалось найти свободное место для клипа"
                                                        } else {
                                                            root.statusMessage = "Клип поставлен рядом с соседним"
                                                        }
                                                        desiredStart = candidate
                                                    } else {
                                                        root.statusMessage = targetTrack === Number(updated[movingIndex].track)
                                                            ? "Клип перемещён"
                                                            : "Клип перемещён на дорожку " + ["V2", "V1", "A1", "A2"][targetTrack]
                                                    }
                                                    updated[movingIndex] = Object.assign({}, updated[movingIndex], {
                                                        start: desiredStart,
                                                        track: targetTrack
                                                    })
                                                    root.mediaFiles = updated
                                                    root.saveTimelineMedia(updated)
                                                }
                                            }
                                        }
                                    }
                                    DropArea {
                                        anchors.fill: parent
                                        onEntered: function(drag) {
                                            timelineTrack.dropHover = true
                                            root.statusMessage = "Отпусти, чтобы добавить на " + timelineTrack.modelData
                                        }
                                        onExited: timelineTrack.dropHover = false
                                        onDropped: function(drop) {
                                            timelineTrack.dropHover = false
                                            // Prefer the actual drag source; MIME text can be empty on some Qt Quick setups.
                                            var url = ""
                                            if (drop.source && drop.source.modelData && drop.source.modelData.url)
                                                url = String(drop.source.modelData.url)
                                            if (url === "")
                                                url = String(drop.getDataAsString("text/plain") || "")
                                            var updated = root.mediaFiles.slice()
                                            var sourceIndex = -1
                                            for (var i = 0; i < updated.length; ++i) {
                                                if (String(updated[i].url) === url && Number(updated[i].track) < 0) {
                                                    sourceIndex = i
                                                    break
                                                }
                                            }
                                            // If the original media-bin entry isn't found by track state,
                                            // any matching source can still provide the clip metadata.
                                            if (sourceIndex < 0) {
                                                for (var j = 0; j < updated.length; ++j) {
                                                    if (String(updated[j].url) === url) {
                                                        sourceIndex = j
                                                        break
                                                    }
                                                }
                                            }
                                            if (sourceIndex < 0) {
                                                root.statusMessage = "Не удалось найти исходный медиафайл"
                                                return
                                            }

                                            // Each drop creates a separate timeline instance, even when
                                            // the same source file is used more than once.
                                            var source = updated[sourceIndex]
                                            var start = Math.max(0, Math.round(drop.x / Math.max(0.001, timelineCanvas.timelineScale)))
                                            var duration = Math.max(1, Number(source.duration || 36))
                                            var end = start + duration
                                            var collision = updated.some(function(item) {
                                                if (Number(item.track) !== timelineTrack.index) return false
                                                var otherStart = Math.max(0, Number(item.start || 0))
                                                var otherEnd = otherStart + Math.max(1, Number(item.duration || 36))
                                                return start < otherEnd && end > otherStart
                                            })
                                            if (collision) {
                                                root.statusMessage = "На этой дорожке уже есть клип в этом месте"
                                                return
                                            }

                                            var clip = Object.assign({}, source, {
                                                track: timelineTrack.index,
                                                start: start,
                                                duration: duration
                                            })
                                            updated.push(clip)
                                            root.mediaFiles = updated
                                            root.saveTimelineMedia(updated)
                                            root.timelinePosition = start
                                            root.statusMessage = "Клип добавлен на " + timelineTrack.modelData
                                            drop.acceptProposedAction()
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            id: timelinePlayhead
                            x: Math.max(0, Math.min(timelineCanvas.width - width, root.timelinePosition * timelineCanvas.timelineScale))
                            y: 20
                            width: 2
                            height: Math.max(0, timelineCanvas.height - 20)
                            color: theme.accent
                            z: 10
                        }
                        Rectangle {
                            x: Math.max(0, Math.min(timelineCanvas.width - width, timelinePlayhead.x - 6))
                            y: 17
                            width: 14
                            height: 14
                            color: theme.accent
                            border.color: theme.text
                            z: 11
                            Text { anchors.centerIn: parent; text: "▼"; color: theme.background; font.pixelSize: 9 }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.SizeHorCursor
                                onPressed: function(mouse) {
                                    var sceneX = mapToItem(timelineCanvas, mouse.x, mouse.y).x
                                    if (root.timelineDuration > 0 && timelineCanvas.width > 0) {
                                        root.timelinePosition = Math.max(0, Math.min(root.timelineDuration, sceneX / Math.max(0.001, timelineCanvas.timelineScale)))
                                        root.updateTimelinePreview(root.timelinePosition)
                                    }
                                }
                                onPositionChanged: function(mouse) {
                                    if (pressed && root.timelineDuration > 0 && timelineCanvas.width > 0) {
                                        var sceneX = mapToItem(timelineCanvas, mouse.x, mouse.y).x
                                        root.timelinePosition = Math.max(0, Math.min(root.timelineDuration, sceneX / Math.max(0.001, timelineCanvas.timelineScale)))
                                        root.updateTimelinePreview(root.timelinePosition)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    footer: Rectangle {
        visible: root.currentProjectPath !== ""
        implicitHeight: 26
        color: theme.background
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            Text { text: "●"; color: theme.green; font.pixelSize: (12 * root.uiFontScale / 100) }
            Text { text: root.statusMessage; color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100); Layout.fillWidth: true; elide: Text.ElideRight }
            Text { text: "Linux · Qt 6 · C++20"; color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
        }
    }
}
