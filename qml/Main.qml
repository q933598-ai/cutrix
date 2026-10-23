import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: root
    visible: true
    width: 1440
    height: 900
    minimumWidth: 1050
    minimumHeight: 680
    title: "Cutrix — Pixel Video Editor"
    color: theme.background

    property string currentTheme: "Tokyo Night"
    property string selectedMedia: "city.mp4"
    property bool isPlaying: false
    property bool settingsOpen: false
    property int uiFontScale: 100
    property string statusMessage: "Готово · UI-прототип · проект не сохранён"

    readonly property var palettes: ({
        "Tokyo Night": { background: "#101522", panel: "#171f32", panelAlt: "#1d2942", border: "#30466f", text: "#d7e2ff", muted: "#8299c9", accent: "#7aa2f7", accent2: "#bb9af7", green: "#9ece6a" },
        "Everforest": { background: "#232a2e", panel: "#2d353b", panelAlt: "#374247", border: "#4b565c", text: "#d3c6aa", muted: "#9da9a0", accent: "#a7c080", accent2: "#d699b6", green: "#83c092" },
        "Catppuccin": { background: "#181825", panel: "#1e1e2e", panelAlt: "#313244", border: "#45475a", text: "#cdd6f4", muted: "#a6adc8", accent: "#89b4fa", accent2: "#cba6f7", green: "#a6e3a1" },
        "Rosé Pine": { background: "#191724", panel: "#1f1d2e", panelAlt: "#26233a", border: "#403d52", text: "#e0def4", muted: "#908caa", accent: "#c4a7e7", accent2: "#ebbcba", green: "#9ccfd8" }
    })
    readonly property var theme: palettes[currentTheme]

    menuBar: MenuBar {
        Menu {
            title: "Файл"
            Action { text: "Импортировать медиа…"; onTriggered: importDialog.open() }
            Action { text: "Сохранить проект (скоро)"; onTriggered: root.statusMessage = "Сохранение проекта ещё не реализовано" }
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
            Action { text: root.isPlaying ? "Пауза" : "Воспроизвести"; onTriggered: root.isPlaying = !root.isPlaying }
        }
        Menu {
            title: "Справка"
            Action { text: "О Cutrix"; onTriggered: aboutDialog.open() }
        }
    }

    FileDialog {
        id: importDialog
        title: "Выбрать медиафайл"
        nameFilters: ["Медиафайлы (*.mp4 *.mov *.mkv *.webm *.mp3 *.wav *.png *.jpg)", "Все файлы (*)"]
        onAccepted: root.statusMessage = "Выбран файл: " + selectedFile + " · загрузка медиа пока не реализована"
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
                            model: [["▧", "city.mp4", "00:12", "#293d72"], ["▧", "mountains.mp4", "00:08", "#3d5472"], ["▧", "sunset.mp4", "00:10", "#754b78"], ["♫", "bg-music.mp3", "03:24", "#275c60"], ["▧", "forest.png", "IMAGE", "#42664b"], ["✿", "cat.png", "IMAGE", "#65528b"]]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 100
                                color: theme.background
                                border.color: root.selectedMedia === modelData[1] ? theme.accent : theme.border
                                Column {
                                    anchors.fill: parent
                                    spacing: 2
                                    Rectangle {
                                        width: parent.width
                                        height: 63
                                        color: modelData[3]
                                        Text { anchors.centerIn: parent; text: modelData[0]; color: "#e5e9ff"; font.pixelSize: (26 * root.uiFontScale / 100); font.family: "monospace" }
                                    }
                                    Text { anchors.left: parent.left; anchors.leftMargin: 4; text: modelData[1]; color: theme.text; font.family: "monospace"; font.pixelSize: (13 * root.uiFontScale / 100); elide: Text.ElideRight; width: parent.width - 8 }
                                    Text { anchors.left: parent.left; anchors.leftMargin: 4; text: modelData[2]; color: theme.muted; font.family: "monospace"; font.pixelSize: (13 * root.uiFontScale / 100) }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { root.selectedMedia = modelData[1]; root.statusMessage = modelData[1] + " выбран (демо)" }
                                }
                            }
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
                        Canvas {
                            anchors.fill: parent
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
                                ctx.fillStyle = "#1e4b7c"
                                for (var r = 0; r < 6; r++) ctx.fillRect(width * 0.2 + r * 9, height * 0.85 + r * 5, width * 0.55 - r * 18, 2)
                            }
                        }
                        Column {
                            anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "CUTRIX"; color: "#ffffff"; font.family: "monospace"; font.pixelSize: (22 * root.uiFontScale / 100); font.bold: true }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Предпросмотр появится здесь"; color: "#d7e2ff"; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "00:00:07:15 / 00:00:32:08"; color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: root.isPlaying ? "Ⅱ Пауза" : "▶ Воспроизвести"
                            onClicked: root.isPlaying = !root.isPlaying
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
                    Text { text: root.selectedMedia; color: theme.text; font.family: "monospace"; font.pixelSize: (13 * root.uiFontScale / 100) }
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
            Layout.preferredHeight: 238
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
                            model: ["◉ Видео 1", "◉ Видео 2", "T Текст", "♫ Аудио 1", "♫ Аудио 2"]
                            delegate: Rectangle {
                                required property string modelData
                                width: parent.width
                                height: 31
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
                                model: [
                                    [{x: 0.01, w: 0.43, t: "city.mp4", c: "#315b9b"}, {x: 0.44, w: 0.29, t: "mountains.mp4", c: "#347e80"}, {x: 0.74, w: 0.24, t: "sunset.mp4", c: "#89517d"}],
                                    [{x: 0.10, w: 0.25, t: "intro.mp4", c: "#51428c"}, {x: 0.57, w: 0.24, t: "room.mp4", c: "#51428c"}],
                                    [{x: 0.10, w: 0.36, t: "T Добро пожаловать!", c: "#6543a8"}, {x: 0.60, w: 0.30, t: "T Cutrix", c: "#6543a8"}],
                                    [{x: 0.01, w: 0.70, t: "♫ bg-music.mp3", c: "#226d6c"}],
                                    [{x: 0.48, w: 0.48, t: "♫ voice.wav", c: "#226d6c"}]
                                ]
                                delegate: Item {
                                    required property var modelData
                                    width: parent.width
                                    height: 31
                                    Repeater {
                                        model: parent.modelData
                                        delegate: Rectangle {
                                            required property var modelData
                                            x: modelData.x * parent.width
                                            width: modelData.w * parent.width
                                            height: 27
                                            color: modelData.c
                                            border.color: Qt.lighter(modelData.c, 1.25)
                                            radius: 2
                                            Text { anchors.fill: parent; anchors.leftMargin: 5; text: modelData.t; color: "#f0f2ff"; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100); verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
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
