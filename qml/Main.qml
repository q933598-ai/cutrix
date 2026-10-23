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
                updated.push({ url: url, name: fileNameFromUrl(url) })
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

    MediaPlayer {
        id: mediaPlayer
        source: root.selectedMediaUrl
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
            if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)
                root.statusMessage = "Видео загружено: " + root.selectedMedia
            else if (mediaStatus === MediaPlayer.InvalidMedia)
                root.statusMessage = "Не удалось открыть видео. Проверь формат и кодеки."
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
                        projectSaveDialog.currentFile = "file://" + StandardPaths.writableLocation(StandardPaths.DocumentsLocation) + "/" + root.pendingProjectName.replace(/[^a-zA-Z0-9а-яА-Я _-]/g, "_") + ".cutrix"
                        projectSaveDialog.open()
                    }
                    palette.buttonText: theme.background
                    background: Rectangle { color: theme.accent; border.color: theme.accent; radius: 0 }
                }
            }
            }
        }
    }

    FileDialog {
        id: projectSaveDialog
        title: "Сохранить проект Cutrix"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Проект Cutrix (*.cutrix)"]
        onAccepted: {
            var path = selectedFile.toString()
            if (path.startsWith("file://")) path = decodeURIComponent(path.substring(7))
            if (!path.endsWith(".cutrix")) path += ".cutrix"
            if (projectStore.createProject(path, root.pendingProjectName, root.pendingResolution, root.pendingFps)) {
                root.openProject(path, root.pendingProjectName)
                newProjectDialog.close()
            } else root.statusMessage = projectStore.lastError()
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
                Layout.preferredWidth: 255
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
                        placeholderText: "Поиск медиа…"
                        color: theme.text
                        placeholderTextColor: theme.muted
                        background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                    }
                    Button {
                        text: "+ Импортировать"
                        Layout.fillWidth: true
                        onClicked: importDialog.open()
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.panelAlt; border.color: theme.accent; radius: 2 }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 7
                        rowSpacing: 7
                        Repeater {
                            model: root.mediaFiles
                            delegate: Rectangle {
                                id: mediaCard
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 118
                                color: theme.background
                                border.color: root.selectedMedia === modelData.name ? theme.accent : theme.border
                                Column {
                                    anchors.fill: parent
                                    spacing: 2
                                    Rectangle {
                                        width: parent.width
                                        height: 76
                                        color: theme.panelAlt
                                        clip: true
                                        Image {
                                            anchors.fill: parent
                                            source: /\.(png|jpe?g|webp|bmp|gif)$/i.test(mediaCard.modelData.name) ? mediaCard.modelData.url : ""
                                            fillMode: Image.PreserveAspectCrop
                                            visible: source.toString() !== ""
                                        }
                                        Canvas {
                                            anchors.fill: parent
                                            visible: /\.(mp3|wav|flac|ogg|m4a|aac)$/i.test(mediaCard.modelData.name)
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.clearRect(0,0,width,height)
                                                ctx.fillStyle = theme.panelAlt
                                                ctx.fillRect(0,0,width,height)
                                                ctx.fillStyle = theme.green
                                                for (var x=3; x<width-3; x+=5) {
                                                    var h = 5 + ((x*17 + mediaCard.modelData.name.length*13)%29)
                                                    ctx.fillRect(x,(height-h)/2,3,h)
                                                }
                                            }
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !/\.(png|jpe?g|webp|bmp|gif|mp3|wav|flac|ogg|m4a|aac)$/i.test(mediaCard.modelData.name)
                                            text: "▶"
                                            color: theme.accent
                                            font.pixelSize: 28
                                            font.family: "monospace"
                                        }
                                        Text {
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 4
                                            text: /\.(mp3|wav|flac|ogg|m4a|aac)$/i.test(mediaCard.modelData.name) ? "AUDIO" : /\.(png|jpe?g|webp|bmp|gif)$/i.test(mediaCard.modelData.name) ? "IMAGE" : "VIDEO"
                                            color: theme.text
                                            font.family: "monospace"
                                            font.pixelSize: 9
                                        }
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 4
                                        width: parent.width - 8
                                        text: mediaCard.modelData.name
                                        color: theme.text
                                        font.family: "monospace"
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 4
                                        text: mediaCard.modelData.missing ? "ФАЙЛ НЕ НАЙДЕН" : "ПЕРЕТАЩИ НА ДОРОЖКУ"
                                        color: mediaCard.modelData.missing ? "#ff6b6b" : theme.muted
                                        font.family: "monospace"
                                        font.pixelSize: 8
                                    }
                                }
                                Drag.active: dragMouse.drag.active
                                Drag.dragType: Drag.Automatic
                                Drag.mimeData: ({ "text/plain": mediaCard.modelData.url })
                                Drag.supportedActions: Qt.CopyAction
                                MouseArea {
                                    id: dragMouse
                                    anchors.fill: parent
                                    drag.target: mediaCard
                                    onPressed: root.selectedMedia = mediaCard.modelData.name
                                    onReleased: mediaCard.Drag.drop()
                                    onClicked: root.selectedMedia = mediaCard.modelData.name
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
                    Item { Layout.fillHeight: true }
                    Text { text: "Демо-элементы · не реальные файлы"; color: theme.muted; font.family: "monospace"; font.pixelSize: (13 * root.uiFontScale / 100); wrapMode: Text.WordWrap }
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

                        Canvas {
                            anchors.fill: parent
                            visible: !mediaPlayer.hasVideo
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                var sky = ctx.createLinearGradient(0, 0, 0, height)
                                sky.addColorStop(0, "#171c55")
                                sky.addColorStop(0.55, "#583e9c")
                                sky.addColorStop(1, "#152f59")
                                ctx.fillStyle = sky
                                ctx.fillRect(0, 0, width, height)
                                ctx.fillStyle = "#d9b8ff"
                                ctx.beginPath()
                                ctx.arc(width * 0.76, height * 0.22, Math.min(width, height) * 0.055, 0, Math.PI * 2)
                                ctx.fill()
                                for (var i = 0; i < 28; i++) {
                                    var bx = i * width / 27
                                    var bw = width / 35 + (i % 3) * 4
                                    var bh = height * (0.12 + ((i * 17) % 37) / 100)
                                    ctx.fillStyle = ["#18284f", "#223a70", "#2d3979"][i % 3]
                                    ctx.fillRect(bx, height * 0.76 - bh, bw, bh)
                                    ctx.fillStyle = "#ff9acb"
                                    for (var wy = height * 0.76 - bh + 7; wy < height * 0.76 - 3; wy += 10)
                                        if ((i + Math.floor(wy)) % 3 === 0) ctx.fillRect(bx + 4, wy, 3, 4)
                                }
                                ctx.fillStyle = "#0b1830"
                                ctx.fillRect(0, height * 0.82, width, height * 0.18)
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            visible: !mediaPlayer.hasVideo
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.selectedMedia === "" ? "CUTRIX" : root.selectedMedia
                                color: "#ffffff"
                                font.family: "monospace"
                                font.pixelSize: 18 * root.uiFontScale / 100
                                font.bold: true
                                elide: Text.ElideMiddle
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.selectedMedia === "" ? "Импортируй видео для предпросмотра" :
                                      mediaPlayer.errorString !== "" ? mediaPlayer.errorString :
                                      mediaPlayer.mediaStatus === MediaPlayer.LoadingMedia ? "Загружаю видео…" :
                                      mediaPlayer.mediaStatus === MediaPlayer.InvalidMedia ? "Не удалось прочитать файл" :
                                      mediaPlayer.hasVideo ? "" : "В файле не найден видеопоток"
                                color: "#d7e2ff"
                                font.family: "monospace"
                                font.pixelSize: 12 * root.uiFontScale / 100
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: mediaPlayer.position >= 0 ? Qt.formatTime(mediaPlayer.position / 1000, "mm:ss") + " / " + Qt.formatTime(mediaPlayer.duration / 1000, "mm:ss") : "00:00 / 00:00"; color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: mediaPlayer.playbackState === MediaPlayer.PlayingState ? "Ⅱ Пауза" : "▶ Воспроизвести"
                            enabled: root.selectedMediaUrl !== ""
                            onClicked: {
                                if (mediaPlayer.playbackState === MediaPlayer.PlayingState) mediaPlayer.pause()
                                else mediaPlayer.play()
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
            Layout.preferredHeight: 164
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
                        Layout.preferredWidth: 112
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
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
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
                                            text: "00:" + (index * 5).toString().padStart(2, "0")
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
                                    width: parent.width
                                    height: 25
                                    Rectangle { anchors.fill: parent; color: index % 2 === 0 ? theme.panel : theme.background; border.color: theme.border; opacity: 0.95 }
                                    Repeater {
                                        model: root.mediaFiles.filter(function(m) { return Number(m.track) === timelineTrack.index })
                                        delegate: Rectangle {
                                            required property var modelData
                                            x: Math.max(0, Number(modelData.start || 0) * 3)
                                            width: Math.max(90, Number(modelData.duration || 36) * 3)
                                            height: 21
                                            y: 2
                                            color: /\\.(mp3|wav|flac|ogg|m4a|aac)$/i.test(modelData.name) ? "#226d6c" : "#315b9b"
                                            border.color: theme.accent
                                            Text { anchors.fill: parent; anchors.leftMargin: 5; text: modelData.name; color: "#f0f2ff"; font.family: "monospace"; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                        }
                                    }
                                    DropArea {
                                        anchors.fill: parent
                                        onDropped: function(drop) {
                                            var url = drop.getDataAsString("text/plain")
                                            var updated = root.mediaFiles.slice()
                                            var found = false
                                            for (var i = 0; i < updated.length; ++i) {
                                                if (updated[i].url === url) {
                                                    updated[i] = Object.assign({}, updated[i], { track: timelineTrack.index, start: 0, duration: updated[i].duration || 36 })
                                                    found = true
                                                    break
                                                }
                                            }
                                            if (found) {
                                                root.mediaFiles = updated
                                                if (root.currentProjectPath !== "") projectStore.saveProjectMedia(root.currentProjectPath, updated)
                                                root.statusMessage = "Клип добавлен на " + timelineTrack.modelData
                                                drop.acceptProposedAction()
                                            }
                                        }
                                    }
                                }
                            }
                        Rectangle {
                            x: parent.width * 0.34
                            y: 20
                            width: 2
                            height: parent.height - 20
                            color: theme.accent
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
