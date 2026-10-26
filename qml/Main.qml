import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import QtCore
import QtQuick.Effects

ApplicationWindow {
    id: root
    visible: true
    width: 1440
    height: 900
    minimumWidth: 1050
    minimumHeight: 680
    title: "Cutrix — Pixel Video Editor"
    color: theme.background
    palette.window: theme.panel
    palette.windowText: theme.text
    palette.base: theme.background
    palette.alternateBase: theme.panelAlt
    palette.text: theme.text
    palette.button: theme.panelAlt
    palette.buttonText: theme.text
    palette.highlight: theme.accent
    palette.highlightedText: theme.background
    palette.placeholderText: theme.muted

    property string currentTheme: projectStore.savedTheme()
    property string selectedMedia: ""
    property string selectedTimelineClipId: ""
    readonly property var selectedTimelineClip: timelineClipById(selectedTimelineClipId)
    readonly property bool selectedClipCanTransform: !!selectedTimelineClip
        && (selectedTimelineClip.kind === "text"
            || selectedTimelineClip.kind === "effect"
            || ((selectedTimelineClip.kind === "video" || selectedTimelineClip.kind === "image")
                && (Number(selectedTimelineClip.track) === 0 || Number(selectedTimelineClip.track) === 1)))
    readonly property bool selectedClipCanColorCorrect: !!selectedTimelineClip
        && (selectedTimelineClip.kind === "image"
            || (selectedTimelineClip.kind === "video"
                && (Number(selectedTimelineClip.track) === 0 || Number(selectedTimelineClip.track) === 1)))
    readonly property bool selectedClipCanBlur: !!selectedTimelineClip
        && (selectedTimelineClip.kind === "effect" || selectedClipCanColorCorrect)
    readonly property bool selectedClipCanZoom: !!selectedTimelineClip
        && (selectedTimelineClip.kind === "video" || selectedTimelineClip.kind === "image")
        && (Number(selectedTimelineClip.track) === 0 || Number(selectedTimelineClip.track) === 1)
    readonly property bool selectedClipCanReverse: !!selectedTimelineClip
        && selectedTimelineClip.kind === "video"
        && (Number(selectedTimelineClip.track) === 0 || Number(selectedTimelineClip.track) === 1)
    readonly property bool selectedClipCanTranscribe: !!selectedTimelineClip
        && (selectedTimelineClip.kind === "video" || selectedTimelineClip.kind === "audio")
        && Number(selectedTimelineClip.track) >= 0
    readonly property bool selectedClipCanAudio: !!selectedTimelineClip
        && (selectedTimelineClip.kind === "audio" || selectedTimelineClip.kind === "video")
        && Number(selectedTimelineClip.track) >= 0
    property string activeSidebarSection: "Медиа"
    property string selectedWhisperModel: ""
    property string pendingSubtitleClipId: ""
    property var undoStack: []
    property var redoStack: []
    property bool historyApplying: false
    property string mediaSearch: ""
    property string exportErrorDetail: ""
    property string exportOutputPath: ""
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
    property string currentProjectResolution: "1920×1080"
    property int currentProjectFps: 30
    property string projectSearch: ""
    property string projectSort: "Последние"
    property var recentProjects: projectStore.recentProjects()
    property string statusMessage: "Готово · Cutrix Project Hub"
    property int mediaPanelWidth: 255
    property real timelinePosition: 0
    // Timeline zoom is measured in screen pixels per second. The available
    // editing horizon starts at 20 minutes and doubles as clips move further out.
    property real timelineZoom: 4
    property real timelineDragHorizon: 0
    // Kept between scroll gestures: reaching the right edge should reveal
    // another block of workspace even when the user isn't dragging a clip.
    property real timelineWorkspaceDemand: 0
    property int timelineAutoScrollDirection: 0
    property real timelineAutoScrollVelocity: 0
    property bool timelinePlayheadDragging: false
    readonly property real timelineWorkspaceDuration:
        timelineWorkspaceForDuration(Math.max(timelineDuration, timelineDragHorizon, timelineWorkspaceDemand))
    // Все элементы таймлайна используют один масштаб, чтобы линейка,
    // клипы и ползунок совпадали по времени.
    property real timelineDuration: {
        var end = 0
        for (var i = 0; i < mediaFiles.length; ++i) {
            if (Number(mediaFiles[i].track) >= 0)
                end = Math.max(end, Number(mediaFiles[i].start || 0) + Math.max(0.25, timelineClipDuration(mediaFiles[i])))
        }
        return end
    }
    property string timelinePreviewUrl: ""
    property string timelinePreviewClipId: ""
    property real timelinePreviewClipStart: -1
    property bool timelinePreviewActive: false
    property string timelineImageUrl: ""
    property string timelineImageClipId: ""
    property bool timelineImageActive: false
    property real timelineSeekPending: -1
    // Cached reverse clips play forward from a local proxy instead of seeking the
    // original compressed stream backwards on every timer tick.
    property var reversePreviewCache: ({})
    property var reversePreviewRequests: ({})
    property int timelineClipSerial: 0
    property string contextMenuClipId: ""
    property real contextMenuTimelinePosition: 0
    // Temporary transform values update the preview every frame and are saved
    // to the project only when the user releases a transform handle.
    property var transformPreviewOverride: ({})
    property var transformGesture: null

    function timelineWorkspaceForDuration(seconds) {
        var duration = Number(seconds)
        if (!isFinite(duration) || duration < 0) duration = 0
        var horizon = 20 * 60
        while (horizon < duration) horizon *= 2
        return horizon
    }

    function setTimelineZoom(value) {
        var requestedZoom = Number(value)
        if (!isFinite(requestedZoom)) requestedZoom = timelineZoom
        var nextZoom = Math.max(0.05, Math.min(40, requestedZoom))
        var anchorTime = 0
        if (timelineViewport && timelineViewport.width > 0 && timelineZoom > 0)
            anchorTime = (timelineViewport.contentX + timelineViewport.width / 2) / timelineZoom
        timelineZoom = nextZoom
        Qt.callLater(function() {
            var maxX = Math.max(0, timelineCanvas.width - timelineViewport.width)
            timelineViewport.contentX = Math.max(0, Math.min(maxX,
                anchorTime * timelineZoom - timelineViewport.width / 2))
        })
    }

    function fitTimelineToProject() {
        var duration = Math.max(1, timelineDuration)
        var fitZoom = Math.max(0.05, Math.min(40, Math.max(1, timelineViewport.width) / duration))
        timelineZoom = fitZoom
        Qt.callLater(function() { timelineViewport.contentX = 0 })
    }

    function setPlayheadFromPointer(mouseArea, mouse) {
        var canvasPoint = mouseArea.mapToItem(timelineCanvas, mouse.x, mouse.y)
        var viewportPoint = mouseArea.mapToItem(timelineViewport, mouse.x, mouse.y)
        var direction = 0
        if (viewportPoint.x >= timelineViewport.width - 32)
            direction = 1
        else if (viewportPoint.x <= 32 && timelineViewport.contentX > 0)
            direction = -1
        if (direction === 0 || direction !== timelineAutoScrollDirection)
            timelineAutoScrollVelocity = 0
        timelineAutoScrollDirection = direction
        var seconds = canvasPoint.x / Math.max(0.001, timelineZoom)
        if (direction > 0) {
            seconds = Math.max(seconds,
                (timelineViewport.contentX + timelineViewport.width - 20) / Math.max(0.001, timelineZoom))
            timelineDragHorizon = Math.max(timelineDragHorizon, seconds + 120)
        } else if (direction < 0) {
            seconds = Math.min(seconds,
                (timelineViewport.contentX + 20) / Math.max(0.001, timelineZoom))
        }
        timelinePosition = Math.max(0, Math.min(timelineWorkspaceDuration, seconds))
        updateTimelinePreview(timelinePosition)
    }

    function keepTimelinePlayheadVisible() {
        if (!timelinePlaybackTimer.running || !timelineViewport || timelineViewport.width <= 0)
            return
        var playheadX = timelinePosition * timelineZoom
        var left = timelineViewport.contentX
        var right = left + timelineViewport.width
        if (playheadX < left + 12)
            timelineViewport.contentX = Math.max(0, playheadX - 24)
        else if (playheadX > right - 60)
            timelineViewport.contentX = Math.max(0, Math.min(timelineCanvas.width - timelineViewport.width,
                playheadX - timelineViewport.width * 0.78))
    }

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

    function cloneTimelineItems(items) {
        return JSON.parse(JSON.stringify(items || []))
    }

    function recordTimelineHistory(label) {
        if (historyApplying || currentProjectPath === "") return
        var stack = undoStack.slice()
        stack.push({
            items: cloneTimelineItems(mediaFiles),
            selectedClipId: String(selectedTimelineClipId || ""),
            position: Number(timelinePosition || 0),
            label: String(label || "Изменение")
        })
        if (stack.length > 80) stack.shift()
        undoStack = stack
        redoStack = []
    }

    function currentHistorySnapshot(label) {
        return {
            items: cloneTimelineItems(mediaFiles),
            selectedClipId: String(selectedTimelineClipId || ""),
            position: Number(timelinePosition || 0),
            label: String(label || "Изменение")
        }
    }

    function restoreHistorySnapshot(snapshot) {
        if (!snapshot) return
        historyApplying = true
        mediaFiles = cloneTimelineItems(snapshot.items)
        selectedTimelineClipId = String(snapshot.selectedClipId || "")
        timelinePosition = Math.max(0, Math.min(timelineDuration, Number(snapshot.position || 0)))
        transformPreviewOverride = ({})
        transformGesture = null
        saveTimelineMedia(mediaFiles)
        updateTimelinePreview(timelinePosition)
        historyApplying = false
    }

    function undoTimelineAction() {
        if (undoStack.length === 0) {
            statusMessage = "Нечего отменять"
            return
        }
        var stack = undoStack.slice()
        var snapshot = stack.pop()
        undoStack = stack
        redoStack = redoStack.concat([currentHistorySnapshot(snapshot.label)])
        restoreHistorySnapshot(snapshot)
        statusMessage = "Отменено: " + snapshot.label
    }

    function redoTimelineAction() {
        if (redoStack.length === 0) {
            statusMessage = "Нечего повторять"
            return
        }
        var stack = redoStack.slice()
        var snapshot = stack.pop()
        redoStack = stack
        undoStack = undoStack.concat([currentHistorySnapshot(snapshot.label)])
        restoreHistorySnapshot(snapshot)
        statusMessage = "Повторено: " + snapshot.label
    }

    function setSelectedClipProperties(changes, label, persist) {
        var id = String(selectedTimelineClipId || "")
        if (id === "" || !changes) return
        var updated = mediaFiles.slice()
        for (var i = 0; i < updated.length; ++i) {
            if (Number(updated[i].track) < 0 || String(updated[i].clipId || "") !== id)
                continue
            var item = Object.assign({}, updated[i])
            var changed = false
            for (var key in changes) {
                if (item[key] !== changes[key]) {
                    item[key] = changes[key]
                    changed = true
                }
            }
            if (!changed) return
            recordTimelineHistory(label || "Изменить клип")
            updated[i] = item
            mediaFiles = updated
            transformPreviewOverride = ({})
            if (persist !== false) saveTimelineMedia(updated)
            updateTimelinePreview(timelinePosition)
            statusMessage = label || "Свойства клипа обновлены"
            return
        }
    }

    function applyStaticZoom(scale) {
        if (!selectedClipCanZoom) {
            statusMessage = "Выбери видео или изображение на дорожке"
            return
        }
        setSelectedClipProperties({
            scale: scale,
            zoomMode: "none",
            zoomAmount: 150
        }, scale > 100 ? "Эффект «Приближение»" : scale < 100
            ? "Эффект «Отдаление»" : "Сброс масштаба")
    }

    function applyColorPreset(preset) {
        if (!selectedClipCanColorCorrect) {
            statusMessage = "Выбери видео или изображение на таймлайне"
            return
        }
        var values = { brightness: 0, contrast: 0, saturation: 0 }
        var label = "Обычные цвета"
        if (preset === "bw") {
            values = { brightness: 0.02, contrast: 0.16, saturation: -1 }
            label = "Чёрно-белый"
        } else if (preset === "film") {
            values = { brightness: 0.06, contrast: -0.12, saturation: -0.28 }
            label = "Плёнка"
        } else if (preset === "punch") {
            values = { brightness: 0, contrast: 0.32, saturation: 0.16 }
            label = "Контраст"
        } else if (preset === "fade") {
            values = { brightness: 0.08, contrast: -0.28, saturation: -0.18 }
            label = "Выцветание"
        }
        setSelectedClipProperties(values, "Эффект «" + label + "»")
    }

    function applyAudioPreset(preset) {
        if (!selectedClipCanAudio) {
            statusMessage = "Выбери аудио- или видеоклип на таймлайне"
            return
        }
        var keys = ["eq31", "eq62", "eq125", "eq250", "eq500",
                    "eq1000", "eq2000", "eq4000", "eq8000", "eq16000"]
        var profiles = {
            flat:   [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            bass:   [5, 4, 3, 2, 0, 0, 0, 0, 1, 1],
            voice:  [-3, -2, -1, 0, 3, 4, 3, 1, 0, -1],
            treble: [-2, -1, 0, 0, 0, 0, 2, 3, 4, 4],
            rock:   [4, 3, 1, -1, -2, 1, 3, 4, 3, 2]
        }
        var labels = {
            flat: "Ровный", bass: "Басы", voice: "Речь",
            treble: "Высокие", rock: "Рок"
        }
        var gains = profiles[preset] || profiles.flat
        var changes = ({})
        for (var i = 0; i < keys.length; ++i)
            changes[keys[i]] = gains[i]
        setSelectedClipProperties(changes, "Эквалайзер · " + (labels[preset] || labels.flat))
    }

    function resetAudioSettings() {
        if (!selectedClipCanAudio) {
            statusMessage = "Выбери аудио- или видеоклип на таймлайне"
            return
        }
        var changes = {
            volume: 100, audioMuted: false, audioPan: 0,
            audioFadeIn: 0, audioFadeOut: 0,
            audioCompressor: false, audioDenoise: false,
            audioNormalize: false, audioLimiter: false
        }
        var keys = ["eq31", "eq62", "eq125", "eq250", "eq500",
                    "eq1000", "eq2000", "eq4000", "eq8000", "eq16000"]
        for (var i = 0; i < keys.length; ++i)
            changes[keys[i]] = 0
        setSelectedClipProperties(changes, "Сбросить настройки аудио")
    }

    function addBlurEffect() {
        var source = selectedTimelineClip
        var start = Math.max(0, Number(timelinePosition || 0))
        var duration = 5

        // When a video/image clip is selected, place the effect directly over
        // its interval. Otherwise make a short effect at the playhead.
        if (source && (source.kind === "video" || source.kind === "image")
                && (Number(source.track) === 0 || Number(source.track) === 1)) {
            start = Math.max(0, Number(source.start || 0))
            duration = timelineClipDuration(source)
        } else {
            var activeClip = timelineVideoAt(start)
            if (activeClip) {
                var remaining = Number(activeClip.start || 0)
                    + timelineClipDuration(activeClip) - start
                duration = Math.max(0.5, Math.min(5, remaining))
            }
        }

        start = findFreeTimelineStart(5, start, duration, "")
        var effect = {
            clipId: createTimelineClipId(),
            name: "Размытие",
            text: "",
            url: "",
            kind: "effect",
            effectType: "blur",
            track: 5,
            start: start,
            duration: duration,
            x: 0,
            y: 0,
            scale: 100,
            rotation: 0,
            blur: 55
        }
        var updated = mediaFiles.slice()
        updated.push(effect)
        recordTimelineHistory("Добавить эффект «Размытие»")
        mediaFiles = updated
        selectedTimelineClipId = String(effect.clipId)
        timelinePosition = start
        saveTimelineMedia(updated)
        updateTimelinePreview(start)
        activeSidebarSection = "Эффекты"
        statusMessage = "Эффект «Размытие» добавлен на FX-дорожку"
    }

    function addPixelSticker(preset) {
        if (!preset) return
        var duration = 5
        var start = findFreeTimelineStart(4, Math.max(0, timelinePosition), duration, "")
        var sticker = {
            clipId: createTimelineClipId(),
            name: "Стикер: " + String(preset.name || preset.glyph || "8-bit"),
            text: String(preset.art || preset.glyph || "★"),
            url: "",
            kind: "text",
            sticker: true,
            track: 4,
            start: start,
            duration: duration,
            x: 0, y: 0, scale: 100,
            zoomMode: "none", zoomAmount: 150, reverse: false,
            rotation: 0, opacity: 100, volume: 100,
            fontSize: preset.art ? 22 : (String(preset.glyph || "").length > 3 ? 40 : 58),
            fontFamily: "Monospace",
            textColor: String(preset.color || "#f6c177")
        }
        var updated = mediaFiles.slice()
        updated.push(sticker)
        recordTimelineHistory("Добавить пиксельный стикер")
        mediaFiles = updated
        selectedTimelineClipId = String(sticker.clipId)
        timelinePosition = start
        saveTimelineMedia(updated)
        updateTimelinePreview(start)
        activeSidebarSection = "Медиа"
        statusMessage = "Пиксельный стикер добавлен · 5 секунд"
    }

    function toggleSelectedClipReverse() {
        if (!selectedClipCanReverse) {
            statusMessage = "Реверс доступен для видеоклипа на V1/V2"
            return
        }
        var enabling = !Boolean(selectedTimelineClip.reverse)
        var clipId = String(selectedTimelineClip.clipId || "")
        setSelectedClipProperties({ reverse: enabling },
            enabling ? "Эффект «Реверс»" : "Отключить реверс")
        if (enabling) {
            var reverseClip = timelineClipById(clipId)
            if (reverseClip) requestReversePreview(reverseClip)
        }
    }

    function requestAutoSubtitles() {
        if (!selectedClipCanTranscribe) {
            statusMessage = "Выбери видеоклип или аудиоклип на таймлайне"
            return
        }
        pendingSubtitleClipId = String(selectedTimelineClip.clipId || "")
        if (selectedWhisperModel === "") {
            whisperModelDialog.open()
            return
        }
        startSubtitleGeneration()
    }

    function startSubtitleGeneration() {
        var clip = timelineClipById(pendingSubtitleClipId)
        if (!clip || Number(clip.track) < 0) {
            statusMessage = "Исходный клип для субтитров больше не найден"
            return
        }
        mediaTools.startTranscription(String(clip.url || ""), selectedWhisperModel,
            Math.max(0, Number(clip.sourceOffset || 0)), timelineClipDuration(clip))
    }

    function insertGeneratedSubtitles(segments) {
        var sourceClip = timelineClipById(pendingSubtitleClipId)
        if (!sourceClip) {
            statusMessage = "Клип удалён до завершения распознавания"
            return
        }
        var sourceStart = Number(sourceClip.start || 0)
        var sourceDuration = timelineClipDuration(sourceClip)
        var updated = mediaFiles.slice()
        var added = 0
        var firstCaptionId = ""
        for (var i = 0; i < segments.length; ++i) {
            var segment = segments[i]
            var relativeStart = Math.max(0, Number(segment.start || 0))
            var relativeEnd = Math.min(sourceDuration, Number(segment.end || 0))
            if (!isFinite(relativeStart) || !isFinite(relativeEnd) || relativeEnd <= relativeStart)
                continue
            if (i + 1 < segments.length) {
                var nextStart = Number(segments[i + 1].start)
                if (isFinite(nextStart) && nextStart > relativeStart)
                    relativeEnd = Math.min(relativeEnd, nextStart)
            }
            if (relativeEnd - relativeStart < 0.08) continue
            var captionText = String(segment.text || "").trim()
            if (captionText === "") continue
            var caption = {
                clipId: createTimelineClipId(),
                name: "Субтитр: " + captionText.substring(0, 24),
                text: captionText,
                url: "",
                kind: "text",
                track: 4,
                start: sourceStart + relativeStart,
                duration: relativeEnd - relativeStart,
                x: 0, y: 0, scale: 100,
                zoomMode: "none", zoomAmount: 150, reverse: false,
                rotation: 0, opacity: 100, volume: 100,
                fontSize: 30, fontFamily: "Sans", textColor: "#ffffff"
            }
            if (firstCaptionId === "") firstCaptionId = String(caption.clipId)
            updated.push(caption)
            added += 1
        }
        if (added === 0) {
            statusMessage = "Не удалось создать субтитры для этого фрагмента"
            return
        }
        recordTimelineHistory("Автоматические субтитры")
        mediaFiles = updated
        selectedTimelineClipId = firstCaptionId
        timelinePosition = sourceStart
        saveTimelineMedia(updated)
        updateTimelinePreview(timelinePosition)
        statusMessage = "Создано субтитров: " + added
        activeSidebarSection = "Медиа"
    }

    // A stable ID distinguishes two instances of the same source file on the timeline.
    function createTimelineClipId() {
        timelineClipSerial += 1
        return "clip-" + Date.now() + "-" + timelineClipSerial
    }

    function timelineClipDuration(item) {
        var value = Number(item.duration)
        if (isFinite(value) && value > 0) return value
        if (item && (item.kind === "image" || item.kind === "text" || item.kind === "effect")) return 5
        return 36
    }

    function timelineTrackForKind(kind, requestedTrack) {
        var track = Math.max(0, Math.min(5, Number(requestedTrack)))
        if (kind === "effect") return 5
        if (kind === "audio") return track === 3 ? 3 : 2
        if (kind === "text") return 4
        if (kind === "video" && (track === 2 || track === 3)) return track
        return track === 0 || track === 1 ? track : 1
    }

    function timelineClipProperty(item, key, fallback) {
        if (item && String(item.clipId || "") !== ""
                && String(item.clipId) === String(selectedTimelineClipId || "")
                && transformPreviewOverride && transformPreviewOverride[key] !== undefined) {
            var previewValue = Number(transformPreviewOverride[key])
            if (isFinite(previewValue)) return previewValue
        }
        if (!item || item[key] === undefined || item[key] === null || item[key] === "")
            return fallback
        var value = Number(item[key])
        return isFinite(value) ? value : fallback
    }

    // The original blur slider stays attached to a media clip. Separate FX
    // clips are rendered as a masked, transformable region over the preview.
    function timelineBlurAt(item, seconds) {
        if (!item) return 0
        return Math.max(0, Math.min(100, timelineClipProperty(item, "blur", 0)))
    }

    function timelineBlurEffectAt(seconds) {
        var time = Number(seconds)
        if (!isFinite(time)) return null
        var active = mediaFiles.filter(function(item) {
            return item.kind === "effect" && item.effectType === "blur"
                && Number(item.track) >= 0
                && Number(item.start || 0) <= time
                && Number(item.start || 0) + timelineClipDuration(item) > time
        })
        active.sort(function(a, b) { return Number(a.start || 0) - Number(b.start || 0) })
        return active.length ? active[active.length - 1] : null
    }

    function previewBlurEffect() {
        var active = timelineBlurEffectAt(timelinePosition)
        if (active) return active
        if (!timelinePlaybackTimer.running && selectedTimelineClip
                && selectedTimelineClip.kind === "effect"
                && timelineVideoAt(timelinePosition))
            return selectedTimelineClip
        return null
    }

    // Animated zoom is evaluated against the clip's local timeline time.
    // Legacy projects without zoomMode keep their original static scale.
    function timelineClipScaleAt(item, seconds) {
        var baseScale = timelineClipProperty(item, "scale", 100)
        if (!item) return baseScale
        var mode = String(item.zoomMode || "none")
        if (mode !== "in" && mode !== "out") return baseScale
        var amount = Number(item.zoomAmount)
        if (!isFinite(amount)) amount = 150
        amount = Math.max(110, Math.min(250, amount)) / 100
        var duration = Math.max(0.001, timelineClipDuration(item))
        var progress = (Number(seconds) - Number(item.start || 0)) / duration
        progress = Math.max(0, Math.min(1, progress))
        var factor = mode === "in"
            ? 1 + (amount - 1) * progress
            : amount - (amount - 1) * progress
        return baseScale * factor
    }

    function projectFrameWidth() {
        var parts = String(currentProjectResolution || "1920×1080").replace("×", "x").split("x")
        return Math.max(1, parseInt(parts[0]) || 1920)
    }

    function projectFrameHeight() {
        var parts = String(currentProjectResolution || "1920×1080").replace("×", "x").split("x")
        return Math.max(1, parseInt(parts[1]) || 1080)
    }

    function projectAspectLabel() {
        var frameWidth = projectFrameWidth()
        var frameHeight = projectFrameHeight()
        var a = frameWidth
        var b = frameHeight
        while (b !== 0) {
            var remainder = a % b
            a = b
            b = remainder
        }
        var divisor = Math.max(1, a)
        return (frameWidth / divisor) + ":" + (frameHeight / divisor)
            + " · " + frameWidth + "×" + frameHeight
    }

    function timelinePreviewOffsetX(item, previewWidth) {
        return timelineClipProperty(item, "x", 0) * previewWidth / projectFrameWidth()
    }

    function timelinePreviewOffsetY(item, previewHeight) {
        return timelineClipProperty(item, "y", 0) * previewHeight / projectFrameHeight()
    }

    // Use the actually painted media rectangle rather than the whole project
    // canvas, so transform handles line up when a landscape clip is fitted
    // inside a vertical Shorts project (and vice versa).
    function previewVisualBaseWidth(item) {
        if (item && item.kind === "effect") return previewCanvas.width * 0.40
        if (item && item.kind === "image") {
            var imageSize = timelineImagePreview.sourceSize
            if (imageSize.width > 0 && imageSize.height > 0)
                return imageSize.width * Math.min(previewCanvas.width / imageSize.width,
                                                  previewCanvas.height / imageSize.height)
        } else if (item && item.kind === "video") {
            var videoRect = videoOutput.contentRect
            if (videoRect.width > 0 && videoRect.height > 0)
                return videoRect.width
        }
        return previewCanvas.width
    }

    function previewVisualBaseHeight(item) {
        if (item && item.kind === "effect") return previewCanvas.height * 0.30
        if (item && item.kind === "image") {
            var imageSize = timelineImagePreview.sourceSize
            if (imageSize.width > 0 && imageSize.height > 0)
                return imageSize.height * Math.min(previewCanvas.width / imageSize.width,
                                                   previewCanvas.height / imageSize.height)
        } else if (item && item.kind === "video") {
            var videoRect = videoOutput.contentRect
            if (videoRect.width > 0 && videoRect.height > 0)
                return videoRect.height
        }
        return previewCanvas.height
    }

    function timelineTextAt(seconds) {
        var active = mediaFiles.filter(function(item) {
            return item.kind === "text" && Number(item.track) >= 0
                && Number(item.start || 0) <= seconds
                && Number(item.start || 0) + timelineClipDuration(item) > seconds
        })
        active.sort(function(a, b) { return Number(a.track) - Number(b.track) })
        return active.length ? active[active.length - 1] : null
    }

    function setSelectedClipProperty(key, value, persist, shouldRecordHistory) {
        var id = String(selectedTimelineClipId || "")
        if (id === "") return
        var updated = mediaFiles.slice()
        for (var i = 0; i < updated.length; ++i) {
            if (Number(updated[i].track) >= 0 && String(updated[i].clipId || "") === id) {
                if (updated[i][key] === value) return
                if (shouldRecordHistory !== false)
                    recordTimelineHistory("Изменить свойство клипа")
                updated[i] = Object.assign({}, updated[i])
                updated[i][key] = value
                mediaFiles = updated
                if (persist !== false) {
                    saveTimelineMedia(updated)
                    statusMessage = "Свойство клипа обновлено"
                }
                return
            }
        }
    }

    function previewSelectedClipProperty(key, value) {
        if (!selectedTimelineClip) return
        var draft = Object.assign({}, transformPreviewOverride)
        draft[key] = value
        transformPreviewOverride = draft
    }

    function commitSelectedClipPreviewProperty(key) {
        if (!selectedTimelineClip || !transformPreviewOverride
                || transformPreviewOverride[key] === undefined)
            return
        var value = transformPreviewOverride[key]
        if (selectedTimelineClip[key] !== value) {
            var historyLabel = key === "blur" ? "Размытие клипа"
                : key === "opacity" ? "Изменить прозрачность"
                : "Цветокоррекция клипа"
            recordTimelineHistory(historyLabel)
        }
        setSelectedClipProperty(key, value, false, false)
        transformPreviewOverride = ({})
        saveTimelineMedia(mediaFiles)
        statusMessage = key === "blur" ? "Размытие применено" : "Свойство клипа обновлено"
    }

    function previewHasSelectedTransformClip() {
        if (!selectedClipCanTransform || !timelinePreviewActive || timelinePlaybackTimer.running) return false
        if (selectedTimelineClip.kind === "effect")
            return !!timelineVideoAt(timelinePosition)
        if (selectedTimelineClip.kind === "text") {
            var title = timelineTextAt(timelinePosition)
            return !!title && String(title.clipId || "") === String(selectedTimelineClipId)
        }
        var visual = timelineVideoAt(timelinePosition)
        return !!visual && String(visual.clipId || "") === String(selectedTimelineClipId)
    }

    function pointInsidePreviewClip(item, sceneX, sceneY) {
        if (!item || !previewCanvas || previewCanvas.width <= 0 || previewCanvas.height <= 0)
            return false
        var textTarget = item.kind === "text"
        var baseWidth = textTarget ? timelineTextOverlay.width : previewVisualBaseWidth(item)
        var baseHeight = textTarget ? Math.max(32, timelineTextOverlay.height) : previewVisualBaseHeight(item)
        var scale = (textTarget
            ? timelineClipProperty(item, "scale", 100)
            : timelineClipScaleAt(item, timelinePosition)) / 100
        if (!isFinite(scale) || scale <= 0) return false
        var centerX = previewCanvas.width / 2 + timelinePreviewOffsetX(item, previewCanvas.width)
        var centerY = previewCanvas.height / 2 + timelinePreviewOffsetY(item, previewCanvas.height)
        var dx = sceneX - centerX
        var dy = sceneY - centerY
        var radians = -timelineClipProperty(item, "rotation", 0) * Math.PI / 180
        var localX = (dx * Math.cos(radians) - dy * Math.sin(radians)) / scale
        var localY = (dx * Math.sin(radians) + dy * Math.cos(radians)) / scale
        return Math.abs(localX) <= baseWidth / 2 && Math.abs(localY) <= baseHeight / 2
    }

    function previewElementAt(sceneX, sceneY) {
        if (!timelinePreviewActive || timelinePlaybackTimer.running) return ""
        var effect = previewBlurEffect()
        if (effect && pointInsidePreviewClip(effect, sceneX, sceneY))
            return String(effect.clipId || "")
        var title = timelineTextAt(timelinePosition)
        if (title && pointInsidePreviewClip(title, sceneX, sceneY))
            return String(title.clipId || "")
        var visual = timelineVideoAt(timelinePosition)
        if (visual && pointInsidePreviewClip(visual, sceneX, sceneY))
            return String(visual.clipId || "")
        return ""
    }

    function selectPreviewElementAt(sceneX, sceneY) {
        var hitId = previewElementAt(sceneX, sceneY)
        if (hitId !== "") {
            selectedTimelineClipId = hitId
            transformPreviewOverride = ({})
            transformGesture = null
            statusMessage = "Выбран элемент в предпросмотре"
        } else {
            selectedTimelineClipId = ""
        }
    }

    function beginTransformGesture(mode, sceneX, sceneY) {
        var clip = selectedTimelineClip
        if (!clip || previewCanvas.width <= 0 || previewCanvas.height <= 0) return
        var centerX = previewCanvas.width / 2
            + timelinePreviewOffsetX(clip, previewCanvas.width)
        var centerY = previewCanvas.height / 2
            + timelinePreviewOffsetY(clip, previewCanvas.height)
        var dx = sceneX - centerX
        var dy = sceneY - centerY
        transformGesture = {
            mode: mode,
            startX: sceneX,
            startY: sceneY,
            clipX: timelineClipProperty(clip, "x", 0),
            clipY: timelineClipProperty(clip, "y", 0),
            scale: timelineClipProperty(clip, "scale", 100),
            rotation: timelineClipProperty(clip, "rotation", 0),
            centerX: centerX,
            centerY: centerY,
            startDistance: Math.max(1, Math.sqrt(dx * dx + dy * dy)),
            startAngle: Math.atan2(dy, dx)
        }
        transformPreviewOverride = ({})
    }

    function updateTransformGesture(mode, sceneX, sceneY) {
        if (!transformGesture || transformGesture.mode !== mode) return
        var g = transformGesture
        var draft = Object.assign({}, transformPreviewOverride)
        if (mode === "move") {
            draft.x = Math.round(g.clipX
                + (sceneX - g.startX) * projectFrameWidth() / Math.max(1, previewCanvas.width))
            draft.y = Math.round(g.clipY
                + (sceneY - g.startY) * projectFrameHeight() / Math.max(1, previewCanvas.height))
        } else if (mode === "scale") {
            var dx = sceneX - g.centerX
            var dy = sceneY - g.centerY
            var distance = Math.sqrt(dx * dx + dy * dy)
            draft.scale = Math.round(Math.max(10, Math.min(300,
                g.scale * distance / g.startDistance)))
        } else if (mode === "rotate") {
            var angle = Math.atan2(sceneY - g.centerY, sceneX - g.centerX)
            var delta = angle - g.startAngle
            while (delta > Math.PI) delta -= Math.PI * 2
            while (delta < -Math.PI) delta += Math.PI * 2
            draft.rotation = Math.max(-180, Math.min(180,
                Math.round(g.rotation + delta * 180 / Math.PI)))
        }
        transformPreviewOverride = draft
    }

    function commitTransformGesture() {
        if (!transformGesture) return
        var g = transformGesture
        var draft = Object.assign({}, transformPreviewOverride)
        if (Object.keys(draft).length > 0) recordTimelineHistory("Трансформация клипа")
        if (g.mode === "move") {
            if (draft.x !== undefined) setSelectedClipProperty("x", draft.x, false, false)
            if (draft.y !== undefined) setSelectedClipProperty("y", draft.y, false, false)
        } else if (g.mode === "scale" && draft.scale !== undefined) {
            setSelectedClipProperty("scale", draft.scale, false, false)
        } else if (g.mode === "rotate" && draft.rotation !== undefined) {
            setSelectedClipProperty("rotation", draft.rotation, false, false)
        }
        transformGesture = null
        transformPreviewOverride = ({})
        saveTimelineMedia(mediaFiles)
        statusMessage = "Трансформация применена"
    }

    function resetSelectedClipTransform() {
        if (!selectedTimelineClip) return
        var defaults = selectedTimelineClip.kind === "effect"
            ? { x: 0, y: 0, scale: 100, rotation: 0 }
            : {
                x: 0, y: 0, scale: 100, zoomMode: "none", zoomAmount: 150, reverse: false,
                rotation: 0, opacity: 100, brightness: 0, contrast: 0, saturation: 0, blur: 0
            }
        recordTimelineHistory("Сброс трансформации")
        for (var key in defaults)
            setSelectedClipProperty(key, defaults[key], false, false)
        transformPreviewOverride = ({})
        saveTimelineMedia(mediaFiles)
        statusMessage = "Трансформация и цветокоррекция сброшены"
    }

    function timelineClipById(id) {
        if (String(id || "") === "") return null
        for (var i = 0; i < mediaFiles.length; ++i) {
            if (Number(mediaFiles[i].track) >= 0
                    && String(mediaFiles[i].clipId || "") === String(id))
                return mediaFiles[i]
        }
        return null
    }

    // Migrate old projects, assign IDs, and repair any already-overlapping clips.
    // Intervals are [start, end), so clips can touch without overlapping.
    function normalizeTimelineMedia(items) {
        var result = []
        var usedIds = ({})
        for (var i = 0; i < items.length; ++i) {
            var item = Object.assign({}, items[i])
            if (Number(item.track) >= 0) {
                var id = String(item.clipId || "")
                if (id === "" || usedIds[id]) id = createTimelineClipId()
                item.clipId = id
                usedIds[id] = true
                var rawStart = Number(item.start)
                item.start = isFinite(rawStart) ? Math.max(0, rawStart) : 0
                item.duration = timelineClipDuration(item)
            }
            result.push(item)
        }

        var order = []
        for (var j = 0; j < result.length; ++j) {
            if (Number(result[j].track) >= 0) order.push(j)
        }
        order.sort(function(a, b) {
            var trackDifference = Number(result[a].track) - Number(result[b].track)
            if (trackDifference !== 0) return trackDifference
            var startDifference = Number(result[a].start) - Number(result[b].start)
            return startDifference !== 0 ? startDifference : a - b
        })

        var placed = []
        for (var k = 0; k < order.length; ++k) {
            var index = order[k]
            var clip = result[index]
            var start = Number(clip.start)
            var duration = timelineClipDuration(clip)
            var blockers = placed.filter(function(other) {
                return Number(other.track) === Number(clip.track)
            })
            blockers.sort(function(a, b) { return Number(a.start) - Number(b.start) })
            for (var b = 0; b < blockers.length; ++b) {
                var otherStart = Number(blockers[b].start)
                var otherEnd = otherStart + timelineClipDuration(blockers[b])
                if (start < otherEnd && start + duration > otherStart)
                    start = otherEnd
            }
            clip.start = start
            clip.duration = duration
            result[index] = clip
            placed.push(clip)
        }
        return result
    }

    // Shared by drag-and-drop and clip movement so neither path can place
    // two clips over each other on the same track.
    function findFreeTimelineStart(track, desiredStart, duration, excludedClipId) {
        var requested = Number(desiredStart)
        var start = isFinite(requested) ? Math.max(0, requested) : 0
        var clipDuration = Number(duration)
        if (!isFinite(clipDuration) || clipDuration <= 0) clipDuration = 36
        var blockers = []
        for (var i = 0; i < mediaFiles.length; ++i) {
            var item = mediaFiles[i]
            if (Number(item.track) !== Number(track)) continue
            if (String(excludedClipId || "") !== ""
                    && String(item.clipId || "") === String(excludedClipId))
                continue
            var otherStartValue = Number(item.start)
            var otherStart = isFinite(otherStartValue) ? Math.max(0, otherStartValue) : 0
            blockers.push({
                start: otherStart,
                end: otherStart + timelineClipDuration(item)
            })
        }
        blockers.sort(function(a, b) { return a.start - b.start })

        // Magnetic edge snapping: within 12 screen pixels, align the dragged
        // clip's start/end exactly with a neighboring clip's end/start.
        var tolerance = 12 / Math.max(0.001, timelineCanvas.timelineScale)
        var nearest = start
        var nearestDistance = tolerance + 1
        for (var j = 0; j < blockers.length; ++j) {
            var edges = [blockers[j].start - clipDuration, blockers[j].end]
            for (var e = 0; e < edges.length; ++e) {
                var candidate = Math.max(0, edges[e])
                var distance = Math.abs(candidate - start)
                if (distance <= tolerance && distance < nearestDistance) {
                    nearest = candidate
                    nearestDistance = distance
                }
            }
        }
        start = nearest

        // If the proposed interval overlaps, move it to a free edge.
        var changed = true
        while (changed) {
            changed = false
            for (var k = 0; k < blockers.length; ++k) {
                if (start < blockers[k].end && start + clipDuration > blockers[k].start) {
                    var left = blockers[k].start - clipDuration
                    var right = blockers[k].end
                    start = left >= 0 && Math.abs(left - start) < Math.abs(right - start) ? left : right
                    changed = true
                    break
                }
            }
        }
        return Math.max(0, start)
    }

    function timelineVideoAt(seconds) {
        var candidates = mediaFiles.filter(function(item) {
            return (Number(item.track) === 0 || Number(item.track) === 1)
                && item.kind !== "audio" && item.kind !== "text"
                && Number(item.start || 0) <= seconds
                && Number(item.start || 0) + timelineClipDuration(item) > seconds
        })
        if (candidates.length === 0) return null
        // V2 находится выше V1 и перекрывает его.
        candidates.sort(function(a, b) { return Number(a.track) - Number(b.track) })
        return candidates[0]
    }
    function timelineFootageAt(seconds) {
        var candidates = mediaFiles.filter(function(item) {
            return (Number(item.track) === 0 || Number(item.track) === 1)
                && item.kind === "video"
                && Number(item.start || 0) <= seconds
                && Number(item.start || 0) + timelineClipDuration(item) > seconds
        })
        if (candidates.length === 0) return null
        candidates.sort(function(a, b) { return Number(a.track) - Number(b.track) })
        return candidates[0]
    }

    function splitSelectedTimelineClip() {
        var id = String(selectedTimelineClipId || "")
        if (id === "") {
            statusMessage = "Сначала выбери клип на таймлайне"
            return
        }
        var updated = mediaFiles.slice()
        var index = -1
        for (var i = 0; i < updated.length; ++i) {
            if (Number(updated[i].track) >= 0 && String(updated[i].clipId || "") === id) {
                index = i
                break
            }
        }
        if (index < 0) {
            statusMessage = "Выбранный клип не найден"
            return
        }
        var original = Object.assign({}, updated[index])
        var start = Math.max(0, Number(original.start || 0))
        var duration = timelineClipDuration(original)
        var end = start + duration
        var cutAt = Number(timelinePosition)
        if (!isFinite(cutAt) || cutAt <= start + 0.05 || cutAt >= end - 0.05) {
            statusMessage = "Поставь курсор внутрь клипа, чтобы разрезать его"
            return
        }
        var leftDuration = cutAt - start
        var rightDuration = end - cutAt
        var baseSourceOffset = Math.max(0, Number(original.sourceOffset || 0))
        original.duration = leftDuration
        var rightClip
        if (original.kind === "video" && original.reverse) {
            // A reversed clip plays its source from the end toward the start.
            // The left timeline half therefore references the source's later segment.
            original.sourceOffset = baseSourceOffset + rightDuration
            updated[index] = original
            rightClip = Object.assign({}, original, {
                clipId: createTimelineClipId(),
                start: cutAt,
                duration: rightDuration,
                sourceOffset: baseSourceOffset
            })
        } else {
            updated[index] = original
            rightClip = Object.assign({}, original, {
                clipId: createTimelineClipId(),
                start: cutAt,
                duration: rightDuration,
                sourceOffset: baseSourceOffset + leftDuration
            })
        }
        updated.splice(index + 1, 0, rightClip)
        recordTimelineHistory("Разрезать клип")
        mediaFiles = updated
        selectedTimelineClipId = String(rightClip.clipId)
        saveTimelineMedia(updated)
        updateTimelinePreview(timelinePosition)
        statusMessage = "Клип разрезан по курсору"
    }

    function removeTimelineClip(clipId) {
        var id = String(clipId || "")
        if (id === "") return
        var updated = mediaFiles.filter(function(item) {
            return Number(item.track) < 0 || String(item.clipId || "") !== id
        })
        if (updated.length === mediaFiles.length) {
            statusMessage = "Клип уже удалён"
            return
        }
        recordTimelineHistory("Удалить клип")
        mediaFiles = updated
        if (selectedTimelineClipId === id) selectedTimelineClipId = ""
        saveTimelineMedia(updated)
        contextMenuClipId = ""
        updateTimelinePreview(timelinePosition)
        statusMessage = "Клип удалён с дорожки; исходник остался в медиатеке"
    }

    function selectMedia(name) {
        selectedTimelineClipId = ""
        timelinePlaybackTimer.stop()
        mediaPlayer.pause()
        timelinePreviewActive = false
        timelinePreviewUrl = ""
        timelinePreviewClipId = ""
        timelinePreviewClipStart = -1
        timelineSeekPending = -1
        selectedMedia = name
        statusMessage = "Выбран файл: " + name
    }

    function previewSelectedMedia() {
        if (selectedMediaUrl === "") return
        timelinePlaybackTimer.stop()
        timelinePreviewActive = false
        timelinePreviewUrl = ""
        timelinePreviewClipId = ""
        timelinePreviewClipStart = -1
        timelineSeekPending = -1
        mediaPlayer.stop()
        // Источник задаётся binding-ом MediaPlayer.source выше; не разрываем его прямым присваиванием.
        mediaPlayer.play()
        statusMessage = "Предпросмотр файла: " + selectedMedia
    }

    function reversePreviewSignature(clip) {
        if (!clip) return ""
        return String(clip.url || "") + "|"
            + Number(clip.sourceOffset || 0).toFixed(3) + "|"
            + Number(timelineClipDuration(clip)).toFixed(3)
    }

    function hasTimelineReversePreview(clip) {
        if (!clip || clip.kind !== "video" || !clip.reverse) return false
        var id = String(clip.clipId || "")
        var entry = reversePreviewCache[id]
        return !!entry && entry.signature === reversePreviewSignature(clip)
            && String(entry.url || "") !== ""
    }

    function timelinePlaybackUrl(clip) {
        if (!clip) return ""
        if (hasTimelineReversePreview(clip))
            return String(reversePreviewCache[String(clip.clipId || "")].url)
        return String(clip.url || "")
    }

    function requestReversePreview(clip) {
        if (!clip || clip.kind !== "video" || !clip.reverse) return false
        var id = String(clip.clipId || "")
        if (id === "") return false
        var signature = reversePreviewSignature(clip)
        if (hasTimelineReversePreview(clip)) return true
        var existing = reversePreviewRequests[id]
        if (existing && existing.signature === signature
                && (existing.status === "pending" || existing.status === "failed"))
            return false
        if (mediaTools.reversePreviewRunning) return false

        var result = String(mediaTools.prepareReversePreview(String(clip.url || ""),
            Number(clip.sourceOffset || 0), timelineClipDuration(clip), id) || "")
        if (result === "pending") {
            var pending = Object.assign({}, reversePreviewRequests)
            pending[id] = { signature: signature, status: "pending" }
            reversePreviewRequests = pending
            statusMessage = "Готовлю плавный предпросмотр реверса…"
            return false
        }
        if (result === "busy") return false
        if (result.indexOf("error:") === 0) {
            var failed = Object.assign({}, reversePreviewRequests)
            failed[id] = { signature: signature, status: "failed" }
            reversePreviewRequests = failed
            statusMessage = "Реверс: " + result.substring(6)
            return false
        }
        if (result !== "") {
            var cache = Object.assign({}, reversePreviewCache)
            cache[id] = { signature: signature, url: result }
            reversePreviewCache = cache
            var requests = Object.assign({}, reversePreviewRequests)
            delete requests[id]
            reversePreviewRequests = requests
            updateTimelinePreview(timelinePosition)
            statusMessage = "Кэш реверса готов"
            return true
        }
        return false
    }

    function updateTimelinePreview(seconds) {
        var clip = timelineVideoAt(seconds)
        timelinePreviewActive = true
        if (!clip) {
            timelineImageActive = false
            timelineImageUrl = ""
            timelineImageClipId = ""
            mediaPlayer.pause()
            timelinePreviewUrl = ""
            timelinePreviewClipId = ""
            timelinePreviewClipStart = -1
            timelineSeekPending = -1
            return
        }

        var url = root.timelinePlaybackUrl(clip)
        var clipId = String(clip.clipId || "")
        var clipStart = Number(clip.start || 0)
        var reverseProxyReady = root.hasTimelineReversePreview(clip)
        var offset = reverseProxyReady
                ? Math.max(0, seconds - clipStart)
                : (clip.reverse && clip.kind === "video"
                    ? Math.max(Number(clip.sourceOffset || 0), Number(clip.sourceOffset || 0)
                        + timelineClipDuration(clip) - Math.max(0, seconds - clipStart) - 0.04)
                    : Math.max(0, Number(clip.sourceOffset || 0) + seconds - clipStart))

        // A still image on the upper track overlays the lower video, but must
        // not replace its decoder: otherwise the underlying video's audio dies.
        if (clip.kind === "image") {
            timelineImageActive = true
            timelineImageUrl = url
            timelineImageClipId = clipId
            var footage = timelineFootageAt(seconds)
            if (!footage) {
                mediaPlayer.pause()
                timelinePreviewUrl = ""
                timelinePreviewClipId = ""
                timelinePreviewClipStart = -1
                timelineSeekPending = -1
                return
            }

            var footageUrl = root.timelinePlaybackUrl(footage)
            var footageId = String(footage.clipId || "")
            var footageStart = Number(footage.start || 0)
            var footageHasReverseProxy = root.hasTimelineReversePreview(footage)
            var footageOffset = footageHasReverseProxy
                ? Math.max(0, seconds - footageStart)
                : (footage.reverse
                    ? Math.max(Number(footage.sourceOffset || 0), Number(footage.sourceOffset || 0)
                        + timelineClipDuration(footage) - Math.max(0, seconds - footageStart) - 0.04)
                    : Math.max(0, Number(footage.sourceOffset || 0) + seconds - footageStart))
            if (footageUrl !== String(timelinePreviewUrl)
                    || footageId !== String(timelinePreviewClipId)
                    || footageStart !== timelinePreviewClipStart) {
                mediaPlayer.pause()
                timelinePreviewUrl = footageUrl
                timelinePreviewClipId = footageId
                timelinePreviewClipStart = footageStart
                timelineSeekPending = footageOffset
            } else {
                var footageTarget = footageOffset * 1000
                if (mediaPlayer.mediaStatus === MediaPlayer.LoadedMedia
                        || mediaPlayer.mediaStatus === MediaPlayer.BufferedMedia) {
                    if (Math.abs(mediaPlayer.position - footageTarget) > 350)
                        mediaPlayer.position = footageTarget
                    if (timelinePlaybackTimer.running
                            && mediaPlayer.playbackState !== MediaPlayer.PlayingState)
                        mediaPlayer.play()
                }
            }
            return
        }

        timelineImageActive = false
        timelineImageUrl = ""
        timelineImageClipId = ""
        if (url !== String(timelinePreviewUrl) || clipId !== String(timelinePreviewClipId)
                || clipStart !== timelinePreviewClipStart) {
            mediaPlayer.pause()
            timelinePreviewUrl = url
            timelinePreviewClipId = clipId
            timelinePreviewClipStart = clipStart
            timelineSeekPending = offset
        } else {
            var target = offset * 1000
            if (Math.abs(mediaPlayer.position - target) > 120)
                mediaPlayer.position = target
        }
    }
    function handleTimelineEndOfMedia() {
        if (!timelinePlaybackTimer.running || timelineImageActive) return

        // EndOfMedia is a real transition, not a normal stopped state. Move
        // to the end of the clip that actually finished, even if the timer's
        // playhead is a few milliseconds behind the decoder.
        var endedClip = timelineClipById(timelinePreviewClipId)
        if (endedClip) {
            var clipEnd = Number(endedClip.start || 0) + timelineClipDuration(endedClip)
            if (timelinePosition < clipEnd)
                timelinePosition = clipEnd
        }

        if (timelinePosition >= timelineDuration) {
            timelinePosition = timelineDuration
            timelinePlaybackTimer.stop()
            mediaPlayer.pause()
            return
        }
        updateTimelinePreview(timelinePosition)
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
        undoStack = []
        redoStack = []
        selectedTimelineClipId = ""
        currentProjectName = name || path.split("/").pop().replace(/\.cutrix$/, "")
        var savedMedia = projectStore.projectMedia(path)

        // Repair legacy projects that stored hasAudio=false when ffprobe output
        // was parsed incorrectly. Probe each affected source only once.
        var probedAudioByUrl = ({})
        savedMedia = savedMedia.map(function(rawItem) {
            var item = Object.assign({}, rawItem)
            if (item.kind !== "video" || item.hasAudio !== false)
                return item
            var key = normalizedMediaUrl(item.url)
            if (key === "")
                return item
            if (probedAudioByUrl[key] === undefined)
                probedAudioByUrl[key] = mediaTools.inspect(item.url)
            var metadata = probedAudioByUrl[key]
            if (metadata.hasAudio !== undefined)
                item.hasAudio = Boolean(metadata.hasAudio)
            else
                delete item.hasAudio
            return item
        })
        mediaFiles = normalizeTimelineMedia(savedMedia)
        if (JSON.stringify(mediaFiles) !== JSON.stringify(savedMedia))
            projectStore.saveProjectMedia(path, mediaFiles)
        selectedMedia = mediaFiles.length > 0 ? mediaFiles[0].name : ""
        refreshProjects()
        var projectInfo = recentProjects.filter(function(item) {
            return String(item.path) === String(path)
        })[0]
        if (projectInfo) {
            currentProjectResolution = String(projectInfo.resolution || "1920×1080")
            currentProjectFps = Number(projectInfo.fps) || 30
        }
        statusMessage = "Открыт проект: " + currentProjectName
    }
    onCurrentThemeChanged: projectStore.saveAppearance(currentTheme, uiFontScale)
    onUiFontScaleChanged: projectStore.saveAppearance(currentTheme, uiFontScale)

    function normalizedMediaUrl(value) {
        var url = String(value || "").trim()
        if (url.indexOf("file://") === 0) {
            url = url.substring(7)
            try { url = decodeURIComponent(url) } catch (e) {}
            return url
        }
        try { return decodeURIComponent(url) } catch (e) { return url }
    }

    function fileNameFromUrl(url) {
        var value = normalizedMediaUrl(url)
        return value.substring(value.lastIndexOf("/") + 1)
    }

    function mediaKindFromUrl(url) {
        var name = fileNameFromUrl(url).toLowerCase()
        var dot = name.lastIndexOf(".")
        var ext = dot >= 0 ? name.substring(dot + 1) : ""
        if (["png","jpg","jpeg","webp","bmp","gif","tif","tiff"].indexOf(ext) >= 0) return "image"
        if (["mp3","wav","flac","ogg","opus","m4a","aac","aiff","aif","wma"].indexOf(ext) >= 0) return "audio"
        if (["mp4","mov","mkv","webm","avi","m4v","mpeg","mpg","ts","mts"].indexOf(ext) >= 0) return "video"
        return "unknown"
    }

    function importSelectedFiles(urls) {
        var updated = root.mediaFiles.slice()
        var added = 0
        var duplicates = 0
        var firstImportedName = ""
        for (var i = 0; i < urls.length; ++i) {
            var url = urls[i].toString()
            var normalizedUrl = normalizedMediaUrl(url)
            var sourceIndex = -1
            var anyMatchIndex = -1
            for (var j = 0; j < updated.length; ++j) {
                if (normalizedMediaUrl(updated[j].url) !== normalizedUrl) continue
                if (anyMatchIndex < 0) anyMatchIndex = j
                if (updated[j].track === undefined || Number(updated[j].track) < 0) { sourceIndex = j; break }
            }
            if (sourceIndex >= 0) {
                duplicates += 1
                if (firstImportedName === "") firstImportedName = String(updated[sourceIndex].name || fileNameFromUrl(url))
                continue
            }
            var metadata = mediaTools.inspect(url)
            var source = anyMatchIndex >= 0 ? Object.assign({}, updated[anyMatchIndex]) : {}
            source.url = url
            source.name = fileNameFromUrl(url)
            source.kind = metadata.kind && metadata.kind !== "unknown"
                ? metadata.kind : (source.kind && source.kind !== "unknown" ? source.kind : root.mediaKindFromUrl(url))
            if (metadata.hasAudio !== undefined) {
                source.hasAudio = Boolean(metadata.hasAudio)
            } else if (source.kind === "audio") {
                source.hasAudio = true
            } else {
                // Missing ffprobe data means "unknown", not "silent".
                delete source.hasAudio
            }
            source.duration = Number(metadata.duration) > 0 ? Number(metadata.duration) : Number(source.duration || 0)
            source.missing = !metadata.exists && anyMatchIndex < 0
            source.track = -1
            source.start = 0
            delete source.clipId
            delete source.x
            delete source.y
            delete source.scale
            delete source.rotation
            delete source.opacity
            delete source.fontSize
            delete source.textColor
            updated.push(source)
            added += 1
            if (firstImportedName === "") firstImportedName = source.name
        }
        if (added > 0) root.recordTimelineHistory("Импорт медиа")
        root.mediaFiles = updated
        root.selectedTimelineClipId = ""
        if (root.currentProjectPath !== "") projectStore.saveProjectMedia(root.currentProjectPath, updated)
        root.mediaSearch = ""
        if (firstImportedName !== "") root.selectedMedia = firstImportedName
        mediaFlickable.contentY = 0
        var count = root.mediaFiles.filter(function(item) {
            return item.track === undefined || Number(item.track) < 0
        }).length
        root.statusMessage = added > 0
            ? "Импортировано: " + added + (duplicates > 0 ? " · уже были: " + duplicates : "") + " · в медиатеке: " + count
            : "Все выбранные файлы уже есть в медиатеке"
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
            Action { text: "Добавить текстовый клип…"; enabled: root.currentProjectPath !== ""; onTriggered: textClipDialog.open() }
            Action { text: "Экспортировать MP4…"; enabled: root.currentProjectPath !== "" && root.timelineDuration > 0 && !exportController.running; onTriggered: exportDialog.open() }
            MenuSeparator {}
            Action { text: "Выход"; onTriggered: Qt.quit() }
        }
        Menu {
            title: "Правка"
            Action { text: "Разрезать клип по курсору"; enabled: !!root.selectedTimelineClip; onTriggered: root.splitSelectedTimelineClip() }
            Action { text: "Отменить  Ctrl+Z"; enabled: root.undoStack.length > 0; onTriggered: root.undoTimelineAction() }
            Action { text: "Повторить  Ctrl+Shift+Z"; enabled: root.redoStack.length > 0; onTriggered: root.redoTimelineAction() }
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

    Shortcut { sequence: "Ctrl+Z"; context: Qt.WindowShortcut; onActivated: root.undoTimelineAction() }
    Shortcut { sequence: "Ctrl+Shift+Z"; context: Qt.WindowShortcut; onActivated: root.redoTimelineAction() }
    Shortcut { sequence: "Ctrl+Y"; context: Qt.WindowShortcut; onActivated: root.redoTimelineAction() }

    Menu {
        id: timelineClipContextMenu
        MenuItem {
            text: "Разрезать по курсору"
            onTriggered: {
                // Use the playhead position captured before the context menu opened.
                root.timelinePosition = root.contextMenuTimelinePosition
                root.updateTimelinePreview(root.timelinePosition)
                root.selectedTimelineClipId = root.contextMenuClipId
                root.splitSelectedTimelineClip()
            }
        }
        MenuItem {
            text: "Сбросить позицию, масштаб и поворот"
            onTriggered: {
                root.selectedTimelineClipId = root.contextMenuClipId
                root.setSelectedClipProperties({
                    x: 0, y: 0, scale: 100, rotation: 0
                }, "Сбросить трансформацию")
            }
        }
        MenuItem {
            text: "Удалить клип с дорожки"
            onTriggered: root.removeTimelineClip(root.contextMenuClipId)
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

            for (var audioIndex = 0; audioIndex < timelineAudioPlayers.count; ++audioIndex) {
                var audioPlayer = timelineAudioPlayers.objectAt(audioIndex)
                if (audioPlayer) audioPlayer.syncToTimeline()
            }
            var currentClip = root.timelineVideoAt(root.timelinePosition)
            var reverseClipToPrepare = currentClip && currentClip.kind === "image"
                ? root.timelineFootageAt(root.timelinePosition) : currentClip
            if (reverseClipToPrepare && reverseClipToPrepare.kind === "video"
                    && reverseClipToPrepare.reverse
                    && !root.hasTimelineReversePreview(reverseClipToPrepare)
                    && (!root.reversePreviewRequests[String(reverseClipToPrepare.clipId || "")]
                        || root.reversePreviewRequests[String(reverseClipToPrepare.clipId || "")].status !== "failed")) {
                if (!mediaTools.reversePreviewRunning)
                    root.requestReversePreview(reverseClipToPrepare)
                mediaPlayer.pause()
                return
            }
            if (currentClip && currentClip.kind === "image") {
                var imageClipId = String(currentClip.clipId || "")
                if (!root.timelineImageActive
                        || imageClipId !== String(root.timelineImageClipId)
                        || String(currentClip.url || "") !== String(root.timelineImageUrl)) {
                    root.updateTimelinePreview(root.timelinePosition)
                    return
                }

                // Keep the lower video's audio/decoder running underneath the still.
                if (String(root.timelinePreviewClipId || "") !== "") {
                    var backgroundReady = mediaPlayer.mediaStatus === MediaPlayer.LoadedMedia
                        || mediaPlayer.mediaStatus === MediaPlayer.BufferedMedia
                        || mediaPlayer.mediaStatus === MediaPlayer.EndOfMedia
                    if (backgroundReady && root.timelineSeekPending >= 0) {
                        mediaPlayer.position = root.timelineSeekPending * 1000
                        root.timelineSeekPending = -1
                        mediaPlayer.play()
                    } else if (backgroundReady) {
                        var backgroundTarget = Math.max(0, root.timelinePosition
                            - root.timelinePreviewClipStart) * 1000
                        if (Math.abs(mediaPlayer.position - backgroundTarget) > 400)
                            mediaPlayer.position = backgroundTarget
                        if (mediaPlayer.playbackState !== MediaPlayer.PlayingState)
                            mediaPlayer.play()
                    }
                }

                // A still image has no decoder clock; the montage timer advances it.
                root.timelinePosition = Math.min(root.timelineDuration,
                                                 root.timelinePosition + interval / 1000)
                if (root.timelinePosition >= root.timelineDuration) {
                    root.timelinePosition = root.timelineDuration
                    stop()
                    mediaPlayer.pause()
                    root.updateTimelinePreview(root.timelinePosition)
                    return
                }
                root.updateTimelinePreview(root.timelinePosition)
                return
            }

            if (currentClip && currentClip.kind === "video" && currentClip.reverse
                    && !root.hasTimelineReversePreview(currentClip)) {
                var reverseId = String(currentClip.clipId || "")
                var reverseSameClip = reverseId !== "" && reverseId === String(root.timelinePreviewClipId)
                    && String(currentClip.url) === String(root.timelinePreviewUrl)
                if (!reverseSameClip) {
                    root.updateTimelinePreview(root.timelinePosition)
                    return
                }
                var reverseDecoderReady = mediaPlayer.mediaStatus === MediaPlayer.LoadedMedia
                    || mediaPlayer.mediaStatus === MediaPlayer.BufferedMedia
                    || mediaPlayer.mediaStatus === MediaPlayer.EndOfMedia
                if (!reverseDecoderReady) return
                mediaPlayer.pause()
                if (root.timelineSeekPending >= 0) {
                    mediaPlayer.position = root.timelineSeekPending * 1000
                    root.timelineSeekPending = -1
                    return
                }
                var reverseElapsed = Math.max(0, root.timelinePosition - Number(currentClip.start || 0))
                var reverseTarget = Math.max(Number(currentClip.sourceOffset || 0),
                    Number(currentClip.sourceOffset || 0) + root.timelineClipDuration(currentClip)
                        - reverseElapsed - interval / 1000 - 0.04)
                mediaPlayer.position = reverseTarget * 1000
                root.timelinePosition = Math.min(root.timelineDuration,
                    root.timelinePosition + interval / 1000)
                if (root.timelinePosition >= root.timelineDuration) {
                    root.timelinePosition = root.timelineDuration
                    stop()
                    mediaPlayer.pause()
                    root.updateTimelinePreview(root.timelinePosition)
                    return
                }
                root.updateTimelinePreview(root.timelinePosition)
                return
            }

            if (currentClip) {
                var currentId = String(currentClip.clipId || "")
                var sameClip = currentId !== "" && currentId === String(root.timelinePreviewClipId)
                var sameSource = root.timelinePlaybackUrl(currentClip) === String(root.timelinePreviewUrl)
                if (!sameClip || !sameSource) {
                    root.updateTimelinePreview(root.timelinePosition)
                    return
                }

                var decoderReady = mediaPlayer.mediaStatus === MediaPlayer.LoadedMedia
                    || mediaPlayer.mediaStatus === MediaPlayer.BufferedMedia
                    || (mediaPlayer.mediaStatus === MediaPlayer.EndOfMedia && sameSource)

                if (root.timelineSeekPending >= 0) {
                    // EndOfMedia is seekable when the next timeline instance uses
                    // the same source file; otherwise wait for source loading.
                    if (decoderReady) {
                        mediaPlayer.position = root.timelineSeekPending * 1000
                        root.timelineSeekPending = -1
                        mediaPlayer.play()
                    }
                    return
                }

                if (mediaPlayer.mediaStatus === MediaPlayer.EndOfMedia) {
                    root.handleTimelineEndOfMedia()
                    return
                }
                if (!decoderReady) return
                if (mediaPlayer.playbackState !== MediaPlayer.PlayingState) {
                    mediaPlayer.play()
                    return
                }

                root.timelinePosition = Math.min(root.timelineDuration,
                                                 root.timelinePosition + interval / 1000)
            } else {
                // Empty gaps still consume timeline time; the playhead must not
                // depend on the last decoded frame's position.
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

    Instantiator {
        id: timelineAudioPlayers
        model: root.mediaFiles.filter(function(item) {
            var track = Number(item.track)
            return (item.kind === "audio" && (track === 2 || track === 3))
                || (item.kind === "video" && track >= 0 && track <= 3 && item.hasAudio !== false)
        })
        delegate: MediaPlayer {
            required property var modelData
            source: modelData.url
            audioOutput: AudioOutput { volume: root.timelineClipProperty(modelData, "volume", 100) / 100 }
            property bool timelineAudioActive: timelinePlaybackTimer.running
                && Number(modelData.start || 0) <= root.timelinePosition
                && Number(modelData.start || 0) + root.timelineClipDuration(modelData) > root.timelinePosition
            function syncToTimeline() {
                if (modelData.kind === "video" && modelData.reverse) {
                    pause()
                    return
                }
                if (!timelineAudioActive || !timelinePlaybackTimer.running) {
                    pause()
                    return
                }
                var target = Math.max(0, root.timelinePosition - Number(modelData.start || 0)) * 1000
                if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) {
                    if (Math.abs(position - target) > 350) position = target
                    if (playbackState !== MediaPlayer.PlayingState) play()
                }
            }
            onTimelineAudioActiveChanged: syncToTimeline()
            onMediaStatusChanged: syncToTimeline()
        }
    }

    // MediaPlayer is a non-visual QtObject and cannot contain Connections
    // as child objects. Keep the Connections beside the Instantiator instead.
    Connections {
        target: root
        function onTimelinePositionChanged() {
            for (var i = 0; i < timelineAudioPlayers.count; ++i) {
                var player = timelineAudioPlayers.objectAt(i)
                if (player) player.syncToTimeline()
            }
        }
    }
    Connections {
        target: timelinePlaybackTimer
        function onRunningChanged() {
            for (var i = 0; i < timelineAudioPlayers.count; ++i) {
                var player = timelineAudioPlayers.objectAt(i)
                if (player) player.syncToTimeline()
            }
        }
        function onTriggered() {
            for (var i = 0; i < timelineAudioPlayers.count; ++i) {
                var player = timelineAudioPlayers.objectAt(i)
                if (player) player.syncToTimeline()
            }
        }
    }

    MediaPlayer {
        id: mediaPlayer
        source: root.timelinePreviewActive ? root.timelinePreviewUrl : root.selectedMediaUrl
        videoOutput: videoOutput
        audioOutput: AudioOutput {
            volume: !root.timelinePreviewActive ? 1.0
                : (timelinePlaybackTimer.running
                    ? (root.hasTimelineReversePreview(root.timelineFootageAt(root.timelinePosition))
                        ? root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "volume", 100) / 100
                        : 0.0)
                    : root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "volume", 100) / 100)
        }
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
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                root.handleTimelineEndOfMedia()
            } else if (mediaStatus === MediaPlayer.LoadedMedia
                    || mediaStatus === MediaPlayer.BufferedMedia) {
                if (root.timelineSeekPending >= 0) {
                    mediaPlayer.position = root.timelineSeekPending * 1000
                    root.timelineSeekPending = -1
                    var activeClip = root.timelineVideoAt(root.timelinePosition)
                    var activeHasReverseProxy = activeClip && activeClip.reverse
                        && root.hasTimelineReversePreview(activeClip)
                    if (timelinePlaybackTimer.running && (!(activeClip && activeClip.reverse)
                            || activeHasReverseProxy))
                        mediaPlayer.play()
                    else if (activeClip && activeClip.reverse && !activeHasReverseProxy)
                        mediaPlayer.pause()
                } else if (root.timelinePreviewUrl === "") {
                    root.statusMessage = "Видео загружено: " + root.selectedMedia
                }
            } else if (mediaStatus === MediaPlayer.InvalidMedia) {
                root.statusMessage = "Не удалось открыть видео. Проверь формат и кодеки."
            }
        }
    }

    ColorDialog {
        id: textColorDialog
        title: "Цвет текста"
        onAccepted: {
            var value = String(selectedColor).toLowerCase()
            if (/^#[0-9a-f]{6}$/.test(value))
                root.setSelectedClipProperty("textColor", value)
            else
                root.statusMessage = "Не удалось прочитать выбранный цвет"
        }
    }

    Dialog {
        id: textClipDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 440
        title: "Добавить текстовый клип"
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            var value = textClipInput.text.trim()
            if (value === "") {
                root.statusMessage = "Текстовый клип не может быть пустым"
                return
            }
            var updated = root.mediaFiles.slice()
            var start = Math.max(0, root.timelinePosition)
            var duration = 5
            // Titles live on V2, above V1 footage.
            start = root.findFreeTimelineStart(4, start, duration, "")
            updated.push({
                clipId: root.createTimelineClipId(),
                name: "Текст: " + value.substring(0, 24),
                text: value,
                url: "",
                kind: "text",
                track: 4,
                start: start,
                duration: duration,
                x: 0, y: 0, scale: 100,
                rotation: 0, opacity: 100, volume: 100,
                fontSize: 30, fontFamily: "Sans", textColor: "#ffffff"
            })
            root.selectedTimelineClipId = String(updated[updated.length - 1].clipId)
            root.recordTimelineHistory("Добавить текстовый клип")
            root.mediaFiles = updated
            root.saveTimelineMedia(updated)
            root.timelinePosition = start
            root.updateTimelinePreview(start)
            root.statusMessage = "Добавлен текстовый клип на 5 секунд"
        }
        contentItem: ColumnLayout {
            spacing: 8
            Label { text: "ТЕКСТ НА ВИДЕО"; color: theme.accent }
            TextArea {
                id: textClipInput
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                placeholderText: "Введи текст титра…"
                wrapMode: TextEdit.Wrap
            }
            Label { text: "Длительность: 5 секунд · отдельная дорожка V3"; color: theme.muted }
        }
    }

    Dialog {
        id: stickerDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: Math.min(590, root.width - 40)
        title: "Пиксельные стикеры"
        standardButtons: Dialog.Cancel
        contentItem: ColumnLayout {
            spacing: 10
            Label {
                Layout.fillWidth: true
                text: "Выбирай по крупному превью и названию. Стикер добавится на дорожку V3 на 5 секунд."
                color: theme.muted
                wrapMode: Text.WordWrap
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 8
                columnSpacing: 8
                Repeater {
                    model: [
                        { glyph: "★", name: "Звезда", color: "#f6c177",
                          art: "  ■  \n ■■■ \n■■■■■\n ■■■ \n  ■  " },
                        { glyph: "♥", name: "Сердце", color: "#eb6f92",
                          art: " ■ ■ \n■■■■■\n■■■■■\n ■■■ \n  ■  " },
                        { glyph: "⚡", name: "Молния", color: "#f6c177",
                          art: "   ■ \n  ■■ \n ■■■■\n   ■ \n  ■  \n ■■  " },
                        { glyph: "GG", name: "GG", color: "#9ccfd8" },
                        { glyph: "LOL", name: "LOL", color: "#c4a7e7" },
                        { glyph: "+100", name: "+100", color: "#9ccfd8" },
                        { glyph: "☠", name: "Череп", color: "#e0def4",
                          art: " ■■■ \n■ ■ ■\n■■■■■\n ■■■ \n  ■  " },
                        { glyph: "◆", name: "Алмаз", color: "#9ccfd8",
                          art: "  ■  \n ■■■ \n■■■■■\n ■■■ \n  ■  " },
                        { glyph: "8-BIT", name: "8-BIT", color: "#f6c177" },
                        { glyph: "WIN", name: "Победа", color: "#a3be8c" },
                        { glyph: "!!!", name: "Вау", color: "#eb6f92" },
                        { glyph: "xD", name: "Смех", color: "#c4a7e7" }
                    ]
                    delegate: Button {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredHeight: 100
                        font.family: "monospace"
                        onClicked: {
                            root.addPixelSticker(modelData)
                            stickerDialog.close()
                        }
                        contentItem: Column {
                            anchors.fill: parent
                            anchors.margins: 5
                            spacing: 3
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                width: parent.width
                                height: 65
                                text: modelData.art ? modelData.art : modelData.glyph
                                color: modelData.color
                                font.family: "monospace"
                                font.pixelSize: modelData.art ? 12 : (String(modelData.glyph).length > 3 ? 22 : 30)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                wrapMode: Text.NoWrap
                            }
                            Text {
                                width: parent.width
                                text: modelData.name
                                color: theme.text
                                font.family: "monospace"
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                        background: Rectangle {
                            color: theme.panelAlt
                            border.color: modelData.color
                            radius: 2
                        }
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                text: "После добавления выбери стикер на V3. Перетаскивай его в предпросмотре; размер и поворот можно менять там же."
                color: theme.muted
                wrapMode: Text.WordWrap
            }
        }
        background: Rectangle { color: theme.panel; border.color: theme.accent; radius: 0 }
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
                textRole: "label"
                valueRole: "resolution"
                property int lastValidIndex: 1
                model: [
                    { label: "── ГОРИЗОНТАЛЬНЫЕ ──", resolution: "__landscape_header__", category: true },
                    { label: "1920×1080 (16:9)", resolution: "1920×1080", category: false },
                    { label: "2560×1440 (16:9)", resolution: "2560×1440", category: false },
                    { label: "3840×2160 (16:9)", resolution: "3840×2160", category: false },
                    { label: "1280×720 (16:9)", resolution: "1280×720", category: false },
                    { label: "── ВЕРТИКАЛЬНЫЕ / ТЕЛЕФОН ──", resolution: "__portrait_header__", category: true },
                    { label: "1080×1920 (9:16)", resolution: "1080×1920", category: false },
                    { label: "720×1280 (9:16)", resolution: "720×1280", category: false },
                    { label: "1440×2560 (9:16)", resolution: "1440×2560", category: false },
                    { label: "1080×2340 (9:19.5)", resolution: "1080×2340", category: false }
                ]
                currentIndex: 1
                onActivated: function(index) {
                    if (model[index].category) {
                        currentIndex = lastValidIndex
                        return
                    }
                    lastValidIndex = index
                }
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
                    id: resolutionDelegate
                    required property string label
                    required property string resolution
                    required property bool category
                    width: resolutionBox.width
                    enabled: !category
                    contentItem: Text {
                        text: resolutionDelegate.label
                        color: resolutionDelegate.category ? theme.muted
                            : (resolutionDelegate.highlighted ? theme.accent : theme.text)
                        font.family: "monospace"
                        font.bold: resolutionDelegate.category
                        font.pixelSize: resolutionDelegate.category ? 10 : 12
                        verticalAlignment: Text.AlignVCenter
                    }
                    highlighted: resolutionBox.highlightedIndex === index
                    background: Rectangle {
                        color: resolutionDelegate.category ? theme.background
                            : (resolutionDelegate.highlighted ? theme.panelAlt : theme.panel)
                        border.color: resolutionDelegate.highlighted && !resolutionDelegate.category
                            ? theme.accent : theme.border
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
            Text {
                text: "Для телефона / Shorts / Reels: 1080×1920 (вертикально, 9:16)"
                color: theme.muted
                font.family: "monospace"
                font.pixelSize: 10 * root.uiFontScale / 100
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
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
                        root.pendingResolution = resolutionBox.currentValue
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
            "Медиафайлы (*.mp4 *.mov *.mkv *.webm *.avi *.m4v *.mpeg *.mpg *.ts *.mts *.mp3 *.wav *.flac *.ogg *.opus *.m4a *.aac *.aiff *.aif *.wma *.png *.jpg *.jpeg *.webp *.bmp *.tif *.tiff)",
            "Все файлы (*)"
        ]
        onAccepted: root.importSelectedFiles(selectedFiles)
    }

    FileDialog {
        id: whisperModelDialog
        title: "Выбрать локальную модель Whisper"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Модель Whisper (*.bin)", "Все файлы (*)"]
        onAccepted: {
            root.selectedWhisperModel = selectedFile.toString()
            root.startSubtitleGeneration()
        }
    }

    Connections {
        target: mediaTools
        function onReversePreviewReady(clipId, previewUrl) {
            var id = String(clipId || "")
            var request = root.reversePreviewRequests[id]
            var clip = root.timelineClipById(id)
            var signature = request && request.signature
                ? request.signature : (clip ? root.reversePreviewSignature(clip) : "")
            var cache = Object.assign({}, root.reversePreviewCache)
            cache[id] = { signature: signature, url: String(previewUrl || "") }
            root.reversePreviewCache = cache
            var requests = Object.assign({}, root.reversePreviewRequests)
            delete requests[id]
            root.reversePreviewRequests = requests
            if (clip && String(previewUrl || "") !== "") {
                var active = root.timelineVideoAt(root.timelinePosition)
                var footage = root.timelineFootageAt(root.timelinePosition)
                if ((active && String(active.clipId || "") === id)
                        || (active && active.kind === "image" && footage
                            && String(footage.clipId || "") === id))
                    root.updateTimelinePreview(root.timelinePosition)
                root.statusMessage = "Предпросмотр реверса готов · " + String(clip.name || "клип")
            }
        }
        function onReversePreviewFailed(clipId, message) {
            var id = String(clipId || "")
            var clip = root.timelineClipById(id)
            var request = root.reversePreviewRequests[id]
            var signature = request && request.signature
                ? request.signature : (clip ? root.reversePreviewSignature(clip) : "")
            var requests = Object.assign({}, root.reversePreviewRequests)
            requests[id] = { signature: signature, status: "failed" }
            root.reversePreviewRequests = requests
            root.statusMessage = "Реверс без кэша (медленнее): " + String(message || "ошибка FFmpeg")
        }
        function onTranscriptionRunningChanged() {
            if (mediaTools.transcriptionRunning)
                root.statusMessage = "Распознаю речь локально…"
        }
        function onTranscriptionFinished(segments) {
            root.insertGeneratedSubtitles(segments)
        }
        function onTranscriptionFailed(message) {
            root.statusMessage = String(message || "Не удалось распознать речь")
        }
    }

    FileDialog {
        id: exportDialog
        title: "Экспортировать видео"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "mp4"
        nameFilters: ["Видео MP4 (*.mp4)", "Все файлы (*)"]
        onAccepted: {
            var dimensions = root.currentProjectResolution.replace("×", "x").split("x")
            var outputWidth = parseInt(dimensions[0]) || 1920
            var outputHeight = parseInt(dimensions[1]) || 1080
            exportController.startExport(root.mediaFiles, selectedFile.toString(),
                                         outputWidth, outputHeight, root.currentProjectFps)
        }
    }

    Connections {
        target: exportController
        function onStatusChanged(message) {
            root.statusMessage = message
        }
        function onProgressChanged() {
            root.statusMessage = "Экспорт: " + Math.round(exportController.progress * 100) + "%"
        }
        function onExportFinished(outputPath, usedHardwareEncoder) {
            root.exportOutputPath = String(outputPath || "")
            root.statusMessage = usedHardwareEncoder
                ? "Экспорт готов · NVIDIA NVENC"
                : "Экспорт готов · CPU (libx264)"
            exportCompleteDialog.open()
        }
        function onExportFailed(message) {
            root.exportErrorDetail = String(message || "Неизвестная ошибка FFmpeg")
            root.statusMessage = "Экспорт не удался — подробности в окне ошибки"
            exportErrorDialog.open()
        }
    }

    Dialog {
        id: exportErrorDialog
        title: "Ошибка экспорта MP4"
        modal: true
        anchors.centerIn: parent
        width: Math.min(720, root.width - 48)
        height: Math.min(420, root.height - 48)
        standardButtons: Dialog.Ok
        contentItem: ScrollView {
            clip: true
            TextArea {
                text: root.exportErrorDetail
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: theme.text
                background: Rectangle { color: theme.background; border.color: theme.border }
            }
        }
        background: Rectangle { color: theme.panel; border.color: theme.accent; radius: 0 }
    }

    Dialog {
        id: exportCompleteDialog
        title: "Экспорт завершён"
        modal: true
        anchors.centerIn: parent
        width: Math.min(620, root.width - 48)
        standardButtons: Dialog.Ok
        contentItem: ColumnLayout {
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: "Видео сохранено в:"
                color: theme.text
                font.family: "monospace"
            }
            TextArea {
                Layout.fillWidth: true
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                text: root.exportOutputPath
                color: theme.text
                background: Rectangle { color: theme.background; border.color: theme.border }
            }
        }
        background: Rectangle { color: theme.panel; border.color: theme.accent; radius: 0 }
    }

    Dialog {
        id: aboutDialog
        title: "О Cutrix"
        modal: true
        anchors.centerIn: parent
        width: 390
        standardButtons: Dialog.Ok
        // Keep a fixed content width so wrapped text does not feed back into
        // Dialog.implicitWidth and trigger a QML binding loop.
        contentItem: Item {
            implicitWidth: 360
            implicitHeight: aboutText.implicitHeight + 24
            Text {
                id: aboutText
                anchors.fill: parent
                anchors.margins: 12
                text: "Cutrix 0.1.0\\nПиксельный видеоредактор для Linux.\\nЭкспорт MP4 через FFmpeg; некоторые функции монтажа ещё в разработке."
                color: theme.text
                font.family: "monospace"
                wrapMode: Text.WordWrap
            }
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
                            color: modelData[1] === root.activeSidebarSection || (modelData[1] === "Настройки" && root.settingsOpen) ? theme.panelAlt : "transparent"
                            border.color: modelData[1] === root.activeSidebarSection || (modelData[1] === "Настройки" && root.settingsOpen) ? theme.border : "transparent"
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
                                    else if (modelData[1] === "Медиа" || modelData[1] === "Эффекты") {
                                        root.activeSidebarSection = modelData[1]
                                    } else if (modelData[1] === "Текст") {
                                        root.activeSidebarSection = "Медиа"
                                        textClipDialog.open()
                                    } else if (modelData[1] === "Стикеры") {
                                        root.activeSidebarSection = "Стикеры"
                                        stickerDialog.open()
                                    } else if (modelData[1] === "Аудио") {
                                        root.activeSidebarSection = "Аудио"
                                    } else {
                                        root.statusMessage = modelData[1] + " — раздел пока в разработке"
                                    }
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
                    id: mediaContentLayout
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 8
                    visible: root.activeSidebarSection !== "Эффекты" && root.activeSidebarSection !== "Аудио"
                    Text { text: "МЕДИАФАЙЛЫ"; color: theme.accent; font.family: "monospace"; font.bold: true }
                    TextField {
                        id: mediaSearchField
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: mediaContentLayout.width
                        Layout.maximumWidth: mediaContentLayout.width
                        placeholderText: "Поиск медиа…"
                        text: root.mediaSearch
                        onTextChanged: root.mediaSearch = text
                        color: theme.text
                        placeholderTextColor: theme.muted
                        background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                    }
                    Button {
                        id: importMediaButton
                        text: root.mediaPanelWidth < 245 ? "＋ Импорт" : "＋ Импортировать медиа"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: mediaContentLayout.width
                        Layout.maximumWidth: mediaContentLayout.width
                        Layout.preferredHeight: 34
                        leftPadding: 4
                        rightPadding: 4
                        font.family: "monospace"
                        font.pixelSize: 11
                        onClicked: importDialog.open()
                        palette.buttonText: theme.text
                        contentItem: Text {
                            text: importMediaButton.text
                            font: importMediaButton.font
                            color: importMediaButton.palette.buttonText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        background: Rectangle { color: theme.panelAlt; border.color: theme.accent; radius: 2 }
                    }
                    Flickable {
                        id: mediaFlickable
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
                                model: root.mediaFiles.filter(function(item) {
                                    return (item.track === undefined || Number(item.track) < 0)
                                        && String(item.name || "").toLowerCase().indexOf(root.mediaSearch.toLowerCase()) !== -1
                                })
                                delegate: Rectangle {
                                    id: mediaCard
                                    required property var modelData
                                    Layout.preferredWidth: Math.max(1, (mediaGrid.width - (mediaGrid.columns - 1) * mediaGrid.columnSpacing) / mediaGrid.columns)
                                    Layout.maximumWidth: Math.max(1, (mediaGrid.width - (mediaGrid.columns - 1) * mediaGrid.columnSpacing) / mediaGrid.columns)
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
                                            source: {
                                                // Refresh when a background thumbnail finishes.
                                                var revision = mediaTools.thumbnailRevision
                                                return mediaCard.modelData.missing ? "" : mediaTools.thumbnail(mediaCard.modelData.url)
                                            }
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
                                visible: root.mediaFiles.filter(function(item) {
                                    return (item.track === undefined || Number(item.track) < 0)
                                        && String(item.name || "").toLowerCase().indexOf(root.mediaSearch.toLowerCase()) !== -1
                                }).length === 0
                                text: root.mediaSearch === "" ? "Медиатека пуста. Импортируй файлы, затем перетащи их на дорожку." : "По запросу ничего не найдено."
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

                ScrollView {
                    id: effectsScroll
                    anchors.fill: parent
                    visible: root.activeSidebarSection === "Эффекты"
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ColumnLayout {
                        id: effectsColumnLayout
                        x: 9
                        width: Math.max(1, effectsScroll.availableWidth - 18)
                        spacing: 10
                    Text {
                        text: "ЭФФЕКТЫ КЛИПА"
                        color: theme.accent
                        font.family: "monospace"
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.selectedTimelineClip ? String(root.selectedTimelineClip.name || "Клип выбран")
                            : "Выбери клип на таймлайне, затем примени эффект."
                        color: theme.text
                        font.family: "monospace"
                        wrapMode: Text.WordWrap
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                    Text {
                        text: "МАСШТАБ"
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: 10 * root.uiFontScale / 100
                    }
                    Button {
                        id: effectZoomInButton
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: effectsColumnLayout.width
                        Layout.maximumWidth: effectsColumnLayout.width
                        text: "⌕ Приближение · 150%"
                        contentItem: Text {
                            text: effectZoomInButton.text
                            font: effectZoomInButton.font
                            color: effectZoomInButton.enabled ? effectZoomInButton.palette.buttonText : theme.muted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        enabled: root.selectedClipCanZoom
                        onClicked: root.applyStaticZoom(150)
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.panelAlt; border.color: theme.accent; radius: 2 }
                    }
                    Button {
                        id: effectZoomOutButton
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: effectsColumnLayout.width
                        Layout.maximumWidth: effectsColumnLayout.width
                        text: "⌕ Отдаление · 80%"
                        contentItem: Text {
                            text: effectZoomOutButton.text
                            font: effectZoomOutButton.font
                            color: effectZoomOutButton.enabled ? effectZoomOutButton.palette.buttonText : theme.muted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        enabled: root.selectedClipCanZoom
                        onClicked: root.applyStaticZoom(80)
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.panelAlt; border.color: theme.border; radius: 2 }
                    }
                    Button {
                        id: effectZoomResetButton
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: effectsColumnLayout.width
                        Layout.maximumWidth: effectsColumnLayout.width
                        text: "↺ Обычный масштаб · 100%"
                        contentItem: Text {
                            text: effectZoomResetButton.text
                            font: effectZoomResetButton.font
                            color: effectZoomResetButton.enabled ? effectZoomResetButton.palette.buttonText : theme.muted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        enabled: root.selectedClipCanZoom
                        onClicked: root.applyStaticZoom(100)
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                    }
                    Text {
                        text: "ЦВЕТОВЫЕ ПРЕСЕТЫ"
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: 10 * root.uiFontScale / 100
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        columns: effectsColumnLayout.width < 250 ? 1 : 2
                        columnSpacing: 4
                        rowSpacing: 4
                        Repeater {
                            model: [
                                { label: "◐ Ч/Б", preset: "bw" },
                                { label: "▧ Плёнка", preset: "film" },
                                { label: "✦ Контраст", preset: "punch" },
                                { label: "▤ Выцветание", preset: "fade" }
                            ]
                            delegate: Button {
                                id: effectPresetButton
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredHeight: 32
                                text: modelData.label
                                contentItem: Text {
                                    text: effectPresetButton.text
                                    font: effectPresetButton.font
                                    color: effectPresetButton.enabled ? effectPresetButton.palette.buttonText : theme.muted
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                }
                                enabled: root.selectedClipCanColorCorrect
                                font.family: "monospace"
                                font.pixelSize: 10
                                onClicked: root.applyColorPreset(modelData.preset)
                                palette.buttonText: theme.text
                                background: Rectangle {
                                    color: theme.panelAlt
                                    border.color: theme.border
                                    radius: 2
                                }
                            }
                        }
                    }
                    Button {
                        id: effectColorResetButton
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: effectsColumnLayout.width
                        Layout.maximumWidth: effectsColumnLayout.width
                        text: "Сбросить цветовой эффект"
                        contentItem: Text {
                            text: effectColorResetButton.text
                            font: effectColorResetButton.font
                            color: effectColorResetButton.enabled ? effectColorResetButton.palette.buttonText : theme.muted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        enabled: root.selectedClipCanColorCorrect
                        onClicked: root.applyColorPreset("none")
                        font.family: "monospace"
                        font.pixelSize: 10
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                    }
                    Text {
                        text: "РАЗМЫТИЕ"
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: 10 * root.uiFontScale / 100
                    }
                    Button {
                        id: addBlurEffectButton
                        text: "＋ Добавить размытие на FX-дорожку"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: effectsColumnLayout.width
                        Layout.maximumWidth: effectsColumnLayout.width
                        enabled: root.currentProjectPath !== ""
                        onClicked: root.addBlurEffect()
                        font.family: "monospace"
                        font.pixelSize: 11
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.panelAlt; border.color: theme.accent; radius: 2 }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Сила"
                            color: theme.text
                            font.family: "monospace"
                            font.pixelSize: 10 * root.uiFontScale / 100
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(root.timelineClipProperty(root.selectedTimelineClip, "blur", 0)) + "%"
                            color: theme.accent
                            font.family: "monospace"
                            font.pixelSize: 10 * root.uiFontScale / 100
                        }
                    }
                    Slider {
                        id: blurEffectSlider
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        stepSize: 5
                        value: root.timelineClipProperty(root.selectedTimelineClip, "blur", 0)
                        enabled: root.selectedClipCanBlur
                        onPressedChanged: {
                            if (pressed) root.transformPreviewOverride = ({})
                            else root.commitSelectedClipPreviewProperty("blur")
                        }
                        onMoved: root.previewSelectedClipProperty("blur", Math.round(value))
                        background: Rectangle {
                            x: blurEffectSlider.leftPadding
                            y: blurEffectSlider.topPadding + blurEffectSlider.availableHeight / 2 - height / 2
                            width: blurEffectSlider.availableWidth
                            height: 4
                            radius: 2
                            color: theme.background
                            border.color: theme.border
                            Rectangle {
                                width: blurEffectSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: theme.accent
                            }
                        }
                        handle: Rectangle {
                            x: blurEffectSlider.leftPadding + blurEffectSlider.visualPosition
                                * (blurEffectSlider.availableWidth - width)
                            y: blurEffectSlider.topPadding + blurEffectSlider.availableHeight / 2 - height / 2
                            width: 12
                            height: 12
                            radius: 6
                            color: blurEffectSlider.pressed ? theme.accent : theme.text
                            border.color: theme.accent
                        }
                    }
                    Button {
                        id: effectBlurResetButton
                        Layout.fillWidth: true
                        text: "↺ Сбросить размытие"
                        enabled: root.selectedClipCanBlur
                        onClicked: root.setSelectedClipProperties({ blur: 0 }, "Сброс размытия")
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                    Text {
                        text: "СКОРОСТЬ И НАПРАВЛЕНИЕ"
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: 10 * root.uiFontScale / 100
                    }
                    Button {
                        id: effectReverseButton
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: effectsColumnLayout.width
                        Layout.maximumWidth: effectsColumnLayout.width
                        text: root.selectedTimelineClip && root.selectedTimelineClip.reverse
                            ? "↶ Отключить реверс" : "↶ Реверс видео + звука"
                        enabled: root.selectedClipCanReverse
                        onClicked: root.toggleSelectedClipReverse()
                        contentItem: Text {
                            text: effectReverseButton.text
                            font: effectReverseButton.font
                            color: effectReverseButton.enabled ? effectReverseButton.palette.buttonText : theme.muted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        palette.buttonText: theme.text
                        background: Rectangle {
                            color: root.selectedTimelineClip && root.selectedTimelineClip.reverse
                                ? theme.accent2 : theme.panelAlt
                            border.color: theme.border
                            radius: 2
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Реверс воспроизводит выбранный видеоклип назад. В предпросмотре звук временно приглушается; экспорт разворачивает видео и аудио."
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: 9 * root.uiFontScale / 100
                        wrapMode: Text.WordWrap
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                    Text {
                        text: "АВТОСУБТИТРЫ"
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: 10 * root.uiFontScale / 100
                    }
                    Button {
                        id: effectSubtitlesButton
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: effectsColumnLayout.width
                        Layout.maximumWidth: effectsColumnLayout.width
                        text: mediaTools.transcriptionRunning ? "Распознавание…"
                            : (root.mediaPanelWidth < 255 ? "♫ Создать субтитры" : "♫ Создать субтитры из речи")
                        contentItem: Text {
                            text: effectSubtitlesButton.text
                            font: effectSubtitlesButton.font
                            color: effectSubtitlesButton.enabled ? effectSubtitlesButton.palette.buttonText : theme.muted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        enabled: root.selectedClipCanTranscribe && !mediaTools.transcriptionRunning
                        onClicked: root.requestAutoSubtitles()
                        palette.buttonText: theme.background
                        background: Rectangle { color: theme.accent; border.color: theme.accent; radius: 2 }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.selectedWhisperModel === ""
                            ? "Модель Whisper не выбрана."
                            : "Модель: " + root.fileNameFromUrl(root.selectedWhisperModel)
                        color: theme.text
                        font.family: "monospace"
                        font.pixelSize: 9 * root.uiFontScale / 100
                        wrapMode: Text.WordWrap
                    }
                    Button {
                        id: effectChooseModelButton
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: effectsColumnLayout.width
                        Layout.maximumWidth: effectsColumnLayout.width
                        text: root.mediaPanelWidth < 255 ? "Выбрать модель Whisper…" : "Выбрать модель Whisper (.bin)"
                        contentItem: Text {
                            text: effectChooseModelButton.text
                            font: effectChooseModelButton.font
                            color: effectChooseModelButton.enabled ? effectChooseModelButton.palette.buttonText : theme.muted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        enabled: !mediaTools.transcriptionRunning
                        onClicked: {
                            root.pendingSubtitleClipId = String(root.selectedTimelineClipId || "")
                            whisperModelDialog.open()
                        }
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Работает локально через whisper-cli + FFmpeg. Модель Whisper нужно скачать отдельно один раз."
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: 9 * root.uiFontScale / 100
                        wrapMode: Text.WordWrap
                    }
                    Item { Layout.fillHeight: true }
                    }
                }
                ScrollView {
                    id: audioScroll
                    anchors.fill: parent
                    visible: root.activeSidebarSection === "Аудио"
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    ColumnLayout {
                        id: audioColumnLayout
                        x: 9
                        width: Math.max(1, audioScroll.availableWidth - 18)
                        spacing: 9

                        Text {
                            text: "АУДИО КЛИПА"
                            color: theme.accent
                            font.family: "monospace"
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.selectedClipCanAudio
                                ? String(root.selectedTimelineClip.name || "Выбранный клип")
                                : "Выбери аудиоклип или видеоклип на таймлайне, чтобы редактировать его звук."
                            color: root.selectedClipCanAudio ? theme.text : theme.muted
                            font.family: "monospace"
                            font.pixelSize: 11 * root.uiFontScale / 100
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }

                        Text {
                            text: "ГРОМКОСТЬ И ПАНОРАМА"
                            color: theme.muted
                            font.family: "monospace"
                            font.pixelSize: 10 * root.uiFontScale / 100
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Громкость"; color: theme.text; font.family: "monospace"; font.pixelSize: 10; Layout.preferredWidth: 65 }
                            Slider {
                                Layout.fillWidth: true
                                from: 0; to: 200; stepSize: 1
                                enabled: root.selectedClipCanAudio
                                value: root.timelineClipProperty(root.selectedTimelineClip, "volume", 100)
                                onPressedChanged: if (pressed) root.recordTimelineHistory("Настройки аудио")
                                onMoved: root.setSelectedClipProperty("volume", value, true, false)
                            }
                            Text {
                                text: Math.round(root.timelineClipProperty(root.selectedTimelineClip, "volume", 100)) + "%"
                                color: theme.accent; font.family: "monospace"; font.pixelSize: 10
                                Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Панорама"; color: theme.text; font.family: "monospace"; font.pixelSize: 10; Layout.preferredWidth: 65 }
                            Slider {
                                Layout.fillWidth: true
                                from: -100; to: 100; stepSize: 1
                                enabled: root.selectedClipCanAudio
                                value: root.timelineClipProperty(root.selectedTimelineClip, "audioPan", 0)
                                onPressedChanged: if (pressed) root.recordTimelineHistory("Панорама звука")
                                onMoved: root.setSelectedClipProperty("audioPan", value, true, false)
                            }
                            Text {
                                text: {
                                    var pan = Math.round(root.timelineClipProperty(root.selectedTimelineClip, "audioPan", 0))
                                    return pan < -3 ? "L " + Math.abs(pan) : pan > 3 ? "R " + pan : "C"
                                }
                                color: theme.accent; font.family: "monospace"; font.pixelSize: 10
                                Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Появление"; color: theme.text; font.family: "monospace"; font.pixelSize: 10; Layout.preferredWidth: 65 }
                            Slider {
                                Layout.fillWidth: true
                                from: 0; to: 10; stepSize: 0.1
                                enabled: root.selectedClipCanAudio
                                value: root.timelineClipProperty(root.selectedTimelineClip, "audioFadeIn", 0)
                                onPressedChanged: if (pressed) root.recordTimelineHistory("Появление звука")
                                onMoved: root.setSelectedClipProperty("audioFadeIn", value, true, false)
                            }
                            Text {
                                text: Number(root.timelineClipProperty(root.selectedTimelineClip, "audioFadeIn", 0)).toFixed(1) + "с"
                                color: theme.accent; font.family: "monospace"; font.pixelSize: 10
                                Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Затухание"; color: theme.text; font.family: "monospace"; font.pixelSize: 10; Layout.preferredWidth: 65 }
                            Slider {
                                Layout.fillWidth: true
                                from: 0; to: 10; stepSize: 0.1
                                enabled: root.selectedClipCanAudio
                                value: root.timelineClipProperty(root.selectedTimelineClip, "audioFadeOut", 0)
                                onPressedChanged: if (pressed) root.recordTimelineHistory("Затухание звука")
                                onMoved: root.setSelectedClipProperty("audioFadeOut", value, true, false)
                            }
                            Text {
                                text: Number(root.timelineClipProperty(root.selectedTimelineClip, "audioFadeOut", 0)).toFixed(1) + "с"
                                color: theme.accent; font.family: "monospace"; font.pixelSize: 10
                                Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight
                            }
                        }
                        CheckBox {
                            text: "Отключить звук клипа"
                            enabled: root.selectedClipCanAudio
                            checked: Boolean(root.selectedTimelineClip && root.selectedTimelineClip.audioMuted)
                            onToggled: root.setSelectedClipProperties({ audioMuted: checked },
                                checked ? "Отключить звук клипа" : "Включить звук клипа")
                            palette.text: theme.text
                            font.family: "monospace"
                            font.pixelSize: 10 * root.uiFontScale / 100
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                        Text {
                            text: "10-ПОЛОСНЫЙ ЭКВАЛАЙЗЕР · ±12 dB"
                            color: theme.muted
                            font.family: "monospace"
                            font.pixelSize: 10 * root.uiFontScale / 100
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            columns: audioColumnLayout.width < 250 ? 1 : 2
                            columnSpacing: 4
                            rowSpacing: 4
                            Repeater {
                                model: [
                                    { label: "Ровный", preset: "flat" },
                                    { label: "Басы", preset: "bass" },
                                    { label: "Речь", preset: "voice" },
                                    { label: "Высокие", preset: "treble" },
                                    { label: "Рок", preset: "rock" }
                                ]
                                delegate: Button {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.preferredHeight: 30
                                    enabled: root.selectedClipCanAudio
                                    text: modelData.label
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                    onClicked: root.applyAudioPreset(modelData.preset)
                                    palette.buttonText: theme.text
                                    background: Rectangle { color: theme.panelAlt; border.color: theme.border; radius: 2 }
                                }
                            }
                        }
                        Repeater {
                            model: [
                                { label: "31 Hz", key: "eq31" },
                                { label: "62 Hz", key: "eq62" },
                                { label: "125 Hz", key: "eq125" },
                                { label: "250 Hz", key: "eq250" },
                                { label: "500 Hz", key: "eq500" },
                                { label: "1 kHz", key: "eq1000" },
                                { label: "2 kHz", key: "eq2000" },
                                { label: "4 kHz", key: "eq4000" },
                                { label: "8 kHz", key: "eq8000" },
                                { label: "16 kHz", key: "eq16000" }
                            ]
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: modelData.label
                                    color: theme.text
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                    Layout.preferredWidth: 43
                                }
                                Slider {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    from: -12; to: 12; stepSize: 1
                                    enabled: root.selectedClipCanAudio
                                    value: root.timelineClipProperty(root.selectedTimelineClip, modelData.key, 0)
                                    onPressedChanged: if (pressed) root.recordTimelineHistory("Эквалайзер")
                                    onMoved: root.setSelectedClipProperty(modelData.key, value, true, false)
                                }
                                Text {
                                    text: {
                                        var gain = Math.round(root.timelineClipProperty(root.selectedTimelineClip, modelData.key, 0))
                                        return (gain > 0 ? "+" : "") + gain + " dB"
                                    }
                                    color: theme.accent
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                    Layout.preferredWidth: 34
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                        Text {
                            text: "ОБРАБОТКА ЗВУКА"
                            color: theme.muted
                            font.family: "monospace"
                            font.pixelSize: 10 * root.uiFontScale / 100
                        }
                        CheckBox {
                            text: "Нормализация громкости"
                            enabled: root.selectedClipCanAudio
                            checked: Boolean(root.selectedTimelineClip && root.selectedTimelineClip.audioNormalize)
                            onToggled: root.setSelectedClipProperties({ audioNormalize: checked },
                                "Нормализация громкости")
                            palette.text: theme.text
                            font.family: "monospace"
                            font.pixelSize: 10 * root.uiFontScale / 100
                        }
                        CheckBox {
                            text: "Компрессор"
                            enabled: root.selectedClipCanAudio
                            checked: Boolean(root.selectedTimelineClip && root.selectedTimelineClip.audioCompressor)
                            onToggled: root.setSelectedClipProperties({ audioCompressor: checked },
                                "Компрессор аудио")
                            palette.text: theme.text
                            font.family: "monospace"
                            font.pixelSize: 10 * root.uiFontScale / 100
                        }
                        CheckBox {
                            text: "Шумоподавление"
                            enabled: root.selectedClipCanAudio
                            checked: Boolean(root.selectedTimelineClip && root.selectedTimelineClip.audioDenoise)
                            onToggled: root.setSelectedClipProperties({ audioDenoise: checked },
                                "Шумоподавление аудио")
                            palette.text: theme.text
                            font.family: "monospace"
                            font.pixelSize: 10 * root.uiFontScale / 100
                        }
                        CheckBox {
                            text: "Лимитер пиков"
                            enabled: root.selectedClipCanAudio
                            checked: Boolean(root.selectedTimelineClip && root.selectedTimelineClip.audioLimiter)
                            onToggled: root.setSelectedClipProperties({ audioLimiter: checked },
                                "Лимитер аудио")
                            palette.text: theme.text
                            font.family: "monospace"
                            font.pixelSize: 10 * root.uiFontScale / 100
                        }
                        Button {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            enabled: root.selectedClipCanAudio
                            text: "↺ Сбросить настройки звука"
                            font.family: "monospace"
                            font.pixelSize: 10
                            onClicked: root.resetAudioSettings()
                            palette.buttonText: theme.text
                            background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Настройки сохраняются в проекте и применяются при экспорте. Предпрослушивание EQ в реальном времени пока не подключено."
                            color: theme.muted
                            font.family: "monospace"
                            font.pixelSize: 9 * root.uiFontScale / 100
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            Rectangle {
                id: mediaPanelSplitter
                property real dragStartScreenX: 0
                property int dragStartPanelWidth: 0
                Layout.preferredWidth: 6
                Layout.minimumWidth: 6
                Layout.maximumWidth: 6
                Layout.fillHeight: true
                color: splitterMouseArea.containsMouse || splitterMouseArea.pressed ? theme.accent : theme.border
                MouseArea {
                    id: splitterMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.SizeHorCursor
                    onPressed: function(mouse) {
                        mediaPanelSplitter.dragStartScreenX = mapToItem(root.contentItem, mouse.x, mouse.y).x
                        mediaPanelSplitter.dragStartPanelWidth = root.mediaPanelWidth
                    }
                    onPositionChanged: function(mouse) {
                        if (!pressed) return
                        var currentX = mapToItem(root.contentItem, mouse.x, mouse.y).x
                        root.mediaPanelWidth = Math.max(180, Math.min(440,
                            Math.round(mediaPanelSplitter.dragStartPanelWidth
                                + currentX - mediaPanelSplitter.dragStartScreenX)))
                    }
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
                        Text { text: root.projectAspectLabel(); color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 220
                        clip: true
                        Rectangle {
                            anchors.fill: parent
                            color: theme.panel
                        }
                        Rectangle {
                            id: previewCanvas
                            width: Math.max(1, Math.min(parent.width,
                                parent.height * root.projectFrameWidth() / root.projectFrameHeight()))
                            height: Math.max(1, Math.min(parent.height,
                                parent.width * root.projectFrameHeight() / root.projectFrameWidth()))
                            anchors.centerIn: parent
                            color: theme.background
                            border.color: theme.border
                            clip: true

                        // Flatten the actual base preview into one full-size texture.
                        // FX blur must sample the composited frame in canvas coordinates,
                        // not a transformed VideoOutput's local rectangle.
                        Item {
                            id: timelineBasePreviewLayer
                            anchors.fill: parent
                            clip: true
                            layer.enabled: true

                            // Keep the captured texture opaque where the source video
                            // doesn't cover the canvas (letterboxing / transparent gaps).
                            // Otherwise MultiEffect can show those pixels as a white block.
                            Rectangle {
                                anchors.fill: parent
                                color: theme.background
                                z: -1
                            }

                        VideoOutput {
                            id: videoOutput
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectFit
                            visible: !root.timelinePreviewActive
                                || (root.timelineImageActive
                                    && root.timelineFootageAt(root.timelinePosition) !== null)
                                // Keep the video surface available while paused too. The still
                                // thumbnail is layered above it, but if frame extraction fails,
                                // VideoOutput can still show the decoder's last rendered frame.
                                || mediaPlayer.hasVideo
                            opacity: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "opacity", 100) / 100
                            transform: [
                                Scale {
                                    xScale: root.timelineClipScaleAt(root.timelineFootageAt(root.timelinePosition), root.timelinePosition) / 100
                                    yScale: root.timelineClipScaleAt(root.timelineFootageAt(root.timelinePosition), root.timelinePosition) / 100
                                    origin.x: videoOutput.width / 2
                                    origin.y: videoOutput.height / 2
                                },
                                Rotation {
                                    angle: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "rotation", 0)
                                    origin.x: videoOutput.width / 2
                                    origin.y: videoOutput.height / 2
                                },
                                Translate {
                                    x: root.timelinePreviewOffsetX(root.timelineFootageAt(root.timelinePosition), previewCanvas.width)
                                    y: root.timelinePreviewOffsetY(root.timelineFootageAt(root.timelinePosition), previewCanvas.height)
                                }
                            ]
                            layer.enabled: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "brightness", 0) !== 0
                                || root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "contrast", 0) !== 0
                                || root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "saturation", 0) !== 0
                                || root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "blur", 0) > 0
                            layer.effect: MultiEffect {
                                brightness: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "brightness", 0)
                                contrast: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "contrast", 0)
                                saturation: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "saturation", 0)
                                blurEnabled: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "blur", 0) > 0
                                blur: Math.max(0, Math.min(1,
                                    root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "blur", 0) / 100))
                                blurMax: 32
                                autoPaddingEnabled: false
                            }
                            z: 0
                        }

                        // Qt Multimedia may not expose a paused frame until playback
                        // starts. Show an FFmpeg thumbnail while paused/loading so a
                        // freshly placed clip is never represented by an empty canvas.
                        Image {
                            id: timelineVideoStillPreview
                            anchors.fill: parent
                            source: {
                                var revision = mediaTools.thumbnailRevision
                                var clip = root.timelineVideoAt(root.timelinePosition)
                                if (!root.timelinePreviewActive || !clip || clip.kind !== "video")
                                    return ""
                                if (timelinePlaybackTimer.running
                                        && mediaPlayer.playbackState === MediaPlayer.PlayingState)
                                    return ""
                                var elapsed = Math.max(0, Number(root.timelinePosition)
                                    - Number(clip.start || 0))
                                elapsed = Math.floor(elapsed * 2) / 2
                                var hasReverseProxy = root.hasTimelineReversePreview(clip)
                                var frameUrl = root.timelinePlaybackUrl(clip)
                                var frameTime = hasReverseProxy
                                    ? elapsed
                                    : (clip.reverse
                                        ? Math.max(Number(clip.sourceOffset || 0),
                                            Number(clip.sourceOffset || 0)
                                                + root.timelineClipDuration(clip) - elapsed - 0.04)
                                        : Math.max(0, Number(clip.sourceOffset || 0) + elapsed))
                                frameTime = Math.max(0, frameTime)
                                return mediaTools.previewFrameAt(frameUrl, frameTime)
                            }
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            visible: root.timelinePreviewActive
                                && !root.timelineImageActive
                                && root.timelineVideoAt(root.timelinePosition) !== null
                                && root.timelineVideoAt(root.timelinePosition).kind === "video"
                                && !timelinePlaybackTimer.running
                            opacity: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "opacity", 100) / 100
                            transform: [
                                Scale {
                                    xScale: root.timelineClipScaleAt(root.timelineVideoAt(root.timelinePosition), root.timelinePosition) / 100
                                    yScale: root.timelineClipScaleAt(root.timelineVideoAt(root.timelinePosition), root.timelinePosition) / 100
                                    origin.x: timelineVideoStillPreview.width / 2
                                    origin.y: timelineVideoStillPreview.height / 2
                                },
                                Rotation {
                                    angle: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "rotation", 0)
                                    origin.x: timelineVideoStillPreview.width / 2
                                    origin.y: timelineVideoStillPreview.height / 2
                                },
                                Translate {
                                    x: root.timelinePreviewOffsetX(root.timelineVideoAt(root.timelinePosition), timelineVideoStillPreview.width)
                                    y: root.timelinePreviewOffsetY(root.timelineVideoAt(root.timelinePosition), timelineVideoStillPreview.height)
                                }
                            ]
                            layer.enabled: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "brightness", 0) !== 0
                                || root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "contrast", 0) !== 0
                                || root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "saturation", 0) !== 0
                                || root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "blur", 0) > 0
                            layer.effect: MultiEffect {
                                brightness: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "brightness", 0)
                                contrast: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "contrast", 0)
                                saturation: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "saturation", 0)
                                blurEnabled: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "blur", 0) > 0
                                blur: Math.max(0, Math.min(1,
                                    root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "blur", 0) / 100))
                                blurMax: 32
                                autoPaddingEnabled: false
                            }
                            z: 0.5
                        }

                        Image {
                            id: timelineImagePreview
                            anchors.fill: parent
                            source: root.timelineImageActive && root.timelinePreviewActive
                                    ? root.timelineImageUrl : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            visible: root.timelineImageActive && root.timelinePreviewActive
                            opacity: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "opacity", 100) / 100
                            transform: [
                                Scale {
                                    xScale: root.timelineClipScaleAt(root.timelineVideoAt(root.timelinePosition), root.timelinePosition) / 100
                                    yScale: root.timelineClipScaleAt(root.timelineVideoAt(root.timelinePosition), root.timelinePosition) / 100
                                    origin.x: timelineImagePreview.width / 2
                                    origin.y: timelineImagePreview.height / 2
                                },
                                Rotation {
                                    angle: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "rotation", 0)
                                    origin.x: timelineImagePreview.width / 2
                                    origin.y: timelineImagePreview.height / 2
                                },
                                Translate {
                                    x: root.timelinePreviewOffsetX(root.timelineVideoAt(root.timelinePosition), previewCanvas.width)
                                    y: root.timelinePreviewOffsetY(root.timelineVideoAt(root.timelinePosition), previewCanvas.height)
                                }
                            ]
                            layer.enabled: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "brightness", 0) !== 0
                                || root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "contrast", 0) !== 0
                                || root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "saturation", 0) !== 0
                                || root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "blur", 0) > 0
                            layer.effect: MultiEffect {
                                brightness: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "brightness", 0)
                                contrast: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "contrast", 0)
                                saturation: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "saturation", 0)
                                blurEnabled: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "blur", 0) > 0
                                blur: Math.max(0, Math.min(1,
                                    root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "blur", 0) / 100))
                                blurMax: 32
                                autoPaddingEnabled: false
                            }
                            z: 1
                        }
                        }

                        // Apply blur to the flattened full-size frame, clipped by the FX mask.
                        Item {
                            id: timelineBlurPreviewMaskShape
                            anchors.fill: parent
                            // Keep the texture transparent outside the blur rectangle.
                            // A plain ShaderEffectSource root can make an otherwise
                            // transparent canvas behave like an opaque mask.
                            layer.enabled: true
                            property var effectClip: root.previewBlurEffect()
                            Rectangle {
                                visible: timelineBlurPreviewMaskShape.effectClip !== null
                                width: timelineBlurPreviewMaskShape.effectClip
                                    ? root.previewVisualBaseWidth(timelineBlurPreviewMaskShape.effectClip)
                                        * root.timelineClipProperty(timelineBlurPreviewMaskShape.effectClip, "scale", 100) / 100 : 0
                                height: timelineBlurPreviewMaskShape.effectClip
                                    ? root.previewVisualBaseHeight(timelineBlurPreviewMaskShape.effectClip)
                                        * root.timelineClipProperty(timelineBlurPreviewMaskShape.effectClip, "scale", 100) / 100 : 0
                                x: parent.width / 2
                                    + (timelineBlurPreviewMaskShape.effectClip
                                        ? root.timelinePreviewOffsetX(timelineBlurPreviewMaskShape.effectClip, parent.width) : 0)
                                    - width / 2
                                y: parent.height / 2
                                    + (timelineBlurPreviewMaskShape.effectClip
                                        ? root.timelinePreviewOffsetY(timelineBlurPreviewMaskShape.effectClip, parent.height) : 0)
                                    - height / 2
                                rotation: timelineBlurPreviewMaskShape.effectClip
                                    ? root.timelineClipProperty(timelineBlurPreviewMaskShape.effectClip, "rotation", 0) : 0
                                color: "white"
                                antialiasing: false
                            }
                        }
                        MultiEffect {
                            id: timelineBlurPreviewEffect
                            anchors.fill: timelineBasePreviewLayer
                            z: 2
                            source: timelineBasePreviewLayer
                            visible: root.timelinePreviewActive
                                && root.previewBlurEffect() !== null
                                && root.timelineVideoAt(root.timelinePosition) !== null
                            blurEnabled: visible
                            blur: root.previewBlurEffect()
                                ? Math.max(0, Math.min(1,
                                    root.timelineClipProperty(root.previewBlurEffect(), "blur", 55) / 100)) : 0
                            blurMax: 32
                            maskEnabled: true
                            maskSource: timelineBlurPreviewMaskShape
                            autoPaddingEnabled: false
                        }

                        Text {
                            id: timelineTextOverlay
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(parent.width * 0.86, Math.max(40, implicitWidth))
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            color: root.timelineTextAt(root.timelinePosition)
                                ? String(root.timelineTextAt(root.timelinePosition).textColor || "#ffffff") : "#ffffff"
                            style: Text.Outline
                            styleColor: "#111111"
                            font.bold: true
                            font.family: root.timelineTextAt(root.timelinePosition)
                                ? String(root.timelineTextAt(root.timelinePosition).fontFamily || "Sans") : "Sans"
                            font.pixelSize: root.timelineClipProperty(root.timelineTextAt(root.timelinePosition), "fontSize", 30)
                            opacity: root.timelineClipProperty(root.timelineTextAt(root.timelinePosition), "opacity", 100) / 100
                            transform: [
                                Scale {
                                    xScale: root.timelineClipProperty(root.timelineTextAt(root.timelinePosition), "scale", 100) / 100
                                    yScale: root.timelineClipProperty(root.timelineTextAt(root.timelinePosition), "scale", 100) / 100
                                    origin.x: timelineTextOverlay.width / 2
                                    origin.y: timelineTextOverlay.height / 2
                                },
                                Rotation {
                                    angle: root.timelineClipProperty(root.timelineTextAt(root.timelinePosition), "rotation", 0)
                                    origin.x: timelineTextOverlay.width / 2
                                    origin.y: timelineTextOverlay.height / 2
                                },
                                Translate {
                                    x: root.timelinePreviewOffsetX(root.timelineTextAt(root.timelinePosition), previewCanvas.width)
                                    y: root.timelinePreviewOffsetY(root.timelineTextAt(root.timelinePosition), previewCanvas.height)
                                }
                            ]
                            z: 5
                            text: root.timelineTextAt(root.timelinePosition)
                                ? String(root.timelineTextAt(root.timelinePosition).text || "") : ""
                            visible: text !== "" && root.timelinePreviewActive
                        }
                        MouseArea {
                            id: previewSelectionArea
                            anchors.fill: parent
                            z: 10
                            visible: root.timelinePreviewActive && !timelinePlaybackTimer.running
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    var hitId = root.previewElementAt(mouse.x, mouse.y)
                                    if (hitId === "") return
                                    root.contextMenuClipId = hitId
                                    root.contextMenuTimelinePosition = root.timelinePosition
                                    root.selectedTimelineClipId = hitId
                                    timelineClipContextMenu.popup(previewSelectionArea, mouse.x, mouse.y)
                                } else {
                                    root.selectPreviewElementAt(mouse.x, mouse.y)
                                }
                            }
                        }

                        Item {
                            id: transformOverlay
                            anchors.fill: parent
                            z: 20
                            visible: root.previewHasSelectedTransformClip()
                            property var targetClip: root.selectedTimelineClip
                            readonly property bool titleTarget: targetClip && targetClip.kind === "text"
                            readonly property real targetScale: root.timelineClipScaleAt(targetClip, root.timelinePosition) / 100
                            readonly property real baseWidth: titleTarget ? timelineTextOverlay.width : root.previewVisualBaseWidth(targetClip)
                            readonly property real baseHeight: titleTarget ? Math.max(32, timelineTextOverlay.height) : root.previewVisualBaseHeight(targetClip)

                            Item {
                                id: transformBounds
                                width: transformOverlay.baseWidth * transformOverlay.targetScale
                                height: transformOverlay.baseHeight * transformOverlay.targetScale
                                x: previewCanvas.width / 2
                                    + root.timelinePreviewOffsetX(transformOverlay.targetClip, previewCanvas.width)
                                    - width / 2
                                y: previewCanvas.height / 2
                                    + root.timelinePreviewOffsetY(transformOverlay.targetClip, previewCanvas.height)
                                    - height / 2
                                rotation: root.timelineClipProperty(transformOverlay.targetClip, "rotation", 0)
                                transformOrigin: Item.Center

                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.color: theme.accent
                                    border.width: 1
                                    antialiasing: false
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.SizeAllCursor
                                    onPressed: function(mouse) {
                                        var point = mapToItem(previewCanvas, mouse.x, mouse.y)
                                        var hitId = root.previewElementAt(point.x, point.y)
                                        if (hitId !== "" && hitId !== String(root.selectedTimelineClipId)) {
                                            root.selectedTimelineClipId = hitId
                                            root.transformPreviewOverride = ({})
                                            root.transformGesture = null
                                            return
                                        }
                                        root.beginTransformGesture("move", point.x, point.y)
                                    }
                                    onPositionChanged: function(mouse) {
                                        if (!pressed) return
                                        var point = mapToItem(previewCanvas, mouse.x, mouse.y)
                                        root.updateTransformGesture("move", point.x, point.y)
                                    }
                                    onReleased: root.commitTransformGesture()
                                    onCanceled: root.commitTransformGesture()
                                }

                            }

                            // Viewport-pinned handles remain reachable at high zoom.
                            Repeater {
                                model: [
                                    { horizontal: -1, vertical: -1 },
                                    { horizontal:  1, vertical: -1 },
                                    { horizontal: -1, vertical:  1 },
                                    { horizontal:  1, vertical:  1 }
                                ]
                                delegate: Rectangle {
                                    id: viewportScaleHandle
                                    required property var modelData
                                    // Compute the transformed corner directly from properties.
                                    // mapToItem() in a binding may not invalidate when only the
                                    // referenced item's transform changes, leaving handles behind.
                                    readonly property real angleRad: transformBounds.rotation * Math.PI / 180
                                    readonly property real cornerX: modelData.horizontal * transformBounds.width / 2
                                    readonly property real cornerY: modelData.vertical * transformBounds.height / 2
                                    property point targetPoint: Qt.point(
                                        transformBounds.x + transformBounds.width / 2
                                            + cornerX * Math.cos(angleRad) - cornerY * Math.sin(angleRad),
                                        transformBounds.y + transformBounds.height / 2
                                            + cornerX * Math.sin(angleRad) + cornerY * Math.cos(angleRad))
                                    width: 14
                                    height: 14
                                    radius: 2
                                    x: Math.max(0, Math.min(parent.width - width, targetPoint.x - width / 2))
                                    y: Math.max(0, Math.min(parent.height - height, targetPoint.y - height / 2))
                                    color: theme.text
                                    border.color: theme.accent
                                    z: 6
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: viewportScaleHandle.modelData.horizontal
                                            === viewportScaleHandle.modelData.vertical
                                            ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                                        onPressed: function(mouse) {
                                            var point = mapToItem(previewCanvas, mouse.x, mouse.y)
                                            root.beginTransformGesture("scale", point.x, point.y)
                                        }
                                        onPositionChanged: function(mouse) {
                                            if (!pressed) return
                                            var point = mapToItem(previewCanvas, mouse.x, mouse.y)
                                            root.updateTransformGesture("scale", point.x, point.y)
                                        }
                                        onReleased: root.commitTransformGesture()
                                        onCanceled: root.commitTransformGesture()
                                    }
                                }
                            }
                            Rectangle {
                                id: viewportRotateHandle
                                // The rotation grip follows the transformed top-center point.
                                readonly property real angleRad: transformBounds.rotation * Math.PI / 180
                                property point targetPoint: Qt.point(
                                    transformBounds.x + transformBounds.width / 2
                                        + transformBounds.height / 2 * Math.sin(angleRad),
                                    transformBounds.y + transformBounds.height / 2
                                        - transformBounds.height / 2 * Math.cos(angleRad))
                                width: 12
                                height: 22
                                x: Math.max(0, Math.min(parent.width - width, targetPoint.x - width / 2))
                                y: Math.max(4, Math.min(parent.height - height, targetPoint.y - height - 6))
                                color: theme.accent
                                border.color: theme.background
                                radius: 2
                                z: 7
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.CrossCursor
                                    onPressed: function(mouse) {
                                        var point = mapToItem(previewCanvas, mouse.x, mouse.y)
                                        root.beginTransformGesture("rotate", point.x, point.y)
                                    }
                                    onPositionChanged: function(mouse) {
                                        if (!pressed) return
                                        var point = mapToItem(previewCanvas, mouse.x, mouse.y)
                                        root.updateTransformGesture("rotate", point.x, point.y)
                                    }
                                    onReleased: root.commitTransformGesture()
                                    onCanceled: root.commitTransformGesture()
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: !mediaPlayer.hasVideo && !root.timelineImageActive
                            color: theme.background
                            z: 0
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
                Flickable {
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: inspectorColumn.implicitHeight + 18
                    ColumnLayout {
                        id: inspectorColumn
                        width: parent.width - 18
                        x: 9
                        y: 9
                        spacing: 9
                    Text { text: "СВОЙСТВА"; color: theme.accent; font.family: "monospace"; font.bold: true }
                    Text { text: root.selectedMedia === "" ? "Файл не выбран" : root.selectedMedia; color: theme.text; font.family: "monospace"; font.pixelSize: (13 * root.uiFontScale / 100); wrapMode: Text.Wrap }
                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                    Text { text: "ПОЗИЦИЯ · МАСШТАБ · ПОВОРОТ"; color: theme.muted; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                    Text { text: root.selectedTimelineClip ? root.selectedTimelineClip.name : "Выбери клип на таймлайне"; color: theme.text; font.family: "monospace"; font.pixelSize: 11; wrapMode: Text.WordWrap }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 6
                        rowSpacing: 4
                        Text { text: "X"; color: theme.text; font.family: "monospace" }
                        SpinBox {
                            Layout.fillWidth: true
                            from: -1920; to: 1920; editable: true
                            palette.text: theme.text
                            background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                            contentItem: TextInput {
                                text: parent.displayText
                                color: theme.text
                                selectionColor: theme.accent
                                selectedTextColor: theme.background
                                horizontalAlignment: Qt.AlignHCenter
                                verticalAlignment: Qt.AlignVCenter
                                font.family: "monospace"
                                readOnly: !parent.editable
                                validator: parent.validator
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                            }
                            value: Math.round(root.timelineClipProperty(root.selectedTimelineClip, "x", 0))
                            enabled: root.selectedClipCanTransform
                            onValueModified: root.setSelectedClipProperty("x", value)
                        }
                        Text { text: "Y"; color: theme.text; font.family: "monospace" }
                        SpinBox {
                            Layout.fillWidth: true
                            from: -1080; to: 1080; editable: true
                            palette.text: theme.text
                            background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                            contentItem: TextInput {
                                text: parent.displayText
                                color: theme.text
                                selectionColor: theme.accent
                                selectedTextColor: theme.background
                                horizontalAlignment: Qt.AlignHCenter
                                verticalAlignment: Qt.AlignVCenter
                                font.family: "monospace"
                                readOnly: !parent.editable
                                validator: parent.validator
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                            }
                            value: Math.round(root.timelineClipProperty(root.selectedTimelineClip, "y", 0))
                            enabled: root.selectedClipCanTransform
                            onValueModified: root.setSelectedClipProperty("y", value)
                        }
                        Text { text: "Масштаб %"; color: theme.text; font.family: "monospace" }
                        SpinBox {
                            Layout.fillWidth: true
                            from: 10; to: 300; editable: true
                            palette.text: theme.text
                            background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                            contentItem: TextInput {
                                text: parent.displayText
                                color: theme.text
                                selectionColor: theme.accent
                                selectedTextColor: theme.background
                                horizontalAlignment: Qt.AlignHCenter
                                verticalAlignment: Qt.AlignVCenter
                                font.family: "monospace"
                                readOnly: !parent.editable
                                validator: parent.validator
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                            }
                            value: Math.round(root.timelineClipProperty(root.selectedTimelineClip, "scale", 100))
                            enabled: root.selectedClipCanTransform
                            onValueModified: root.setSelectedClipProperty("scale", value)
                        }
                        Text { text: "Поворот °"; color: theme.text; font.family: "monospace" }
                        SpinBox {
                            Layout.fillWidth: true
                            from: -180; to: 180; editable: true
                            palette.text: theme.text
                            background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                            contentItem: TextInput {
                                text: parent.displayText
                                color: theme.text
                                selectionColor: theme.accent
                                selectedTextColor: theme.background
                                horizontalAlignment: Qt.AlignHCenter
                                verticalAlignment: Qt.AlignVCenter
                                font.family: "monospace"
                                readOnly: !parent.editable
                                validator: parent.validator
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                            }
                            value: Math.round(root.timelineClipProperty(root.selectedTimelineClip, "rotation", 0))
                            enabled: root.selectedClipCanTransform
                            onValueModified: root.setSelectedClipProperty("rotation", value)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            text: "↺ Сброс"
                            enabled: !!root.selectedTimelineClip
                            onClicked: root.resetSelectedClipTransform()
                            palette.buttonText: theme.text
                            background: Rectangle { color: theme.panelAlt; border.color: theme.border; radius: 2 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Рамку тяни · углы = масштаб · ручка сверху = поворот"
                            color: theme.muted
                            wrapMode: Text.WordWrap
                            font.family: "monospace"
                            font.pixelSize: 9
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Непрозрачность"; color: theme.text; font.family: "monospace"; font.pixelSize: 10 }
                        Slider {
                            id: opacitySlider
                            Layout.fillWidth: true
                            from: 0; to: 100; stepSize: 5
                            value: root.timelineClipProperty(root.selectedTimelineClip, "opacity", 100)
                            enabled: root.selectedClipCanTransform
                                && root.selectedTimelineClip.kind !== "effect"
                            onPressedChanged: {
                                if (pressed) root.transformPreviewOverride = ({})
                                else root.commitSelectedClipPreviewProperty("opacity")
                            }
                            onMoved: root.previewSelectedClipProperty("opacity", Math.round(value))
                            background: Rectangle {
                                x: opacitySlider.leftPadding
                                y: opacitySlider.topPadding + opacitySlider.availableHeight / 2 - height / 2
                                width: opacitySlider.availableWidth
                                height: 4
                                radius: 2
                                color: theme.background
                                border.color: theme.border
                                Rectangle {
                                    width: opacitySlider.visualPosition * parent.width
                                    height: parent.height
                                    radius: 2
                                    color: theme.accent
                                }
                            }
                            handle: Rectangle {
                                x: opacitySlider.leftPadding + opacitySlider.visualPosition * (opacitySlider.availableWidth - width)
                                y: opacitySlider.topPadding + opacitySlider.availableHeight / 2 - height / 2
                                width: 12; height: 12; radius: 6
                                color: opacitySlider.pressed ? theme.accent : theme.text
                                border.color: theme.accent
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!root.selectedTimelineClip
                        Text { text: "Громкость %"; color: theme.text; font.family: "monospace"; font.pixelSize: 10 }
                        Slider {
                            id: volumeSlider
                            Layout.fillWidth: true
                            from: 0; to: 100; stepSize: 5
                            value: root.timelineClipProperty(root.selectedTimelineClip, "volume", 100)
                            enabled: !!root.selectedTimelineClip
                                && (root.selectedTimelineClip.kind === "audio" || root.selectedTimelineClip.kind === "video")
                            onPressedChanged: {
                                if (pressed) root.transformPreviewOverride = ({})
                                else root.commitSelectedClipPreviewProperty("volume")
                            }
                            onMoved: root.previewSelectedClipProperty("volume", Math.round(value))
                            background: Rectangle {
                                x: volumeSlider.leftPadding
                                y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                width: volumeSlider.availableWidth
                                height: 4
                                radius: 2
                                color: theme.background
                                border.color: theme.border
                                Rectangle {
                                    width: volumeSlider.visualPosition * parent.width
                                    height: parent.height
                                    radius: 2
                                    color: theme.accent
                                }
                            }
                            handle: Rectangle {
                                x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                width: 12; height: 12; radius: 6
                                color: volumeSlider.pressed ? theme.accent : theme.text
                                border.color: theme.accent
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !!root.selectedTimelineClip && root.selectedTimelineClip.kind === "text"
                        Text { text: "ТЕКСТ · ОФОРМЛЕНИЕ"; color: theme.muted; font.family: "monospace"; font.pixelSize: 11 }
                        TextField {
                            Layout.fillWidth: true
                            text: root.selectedTimelineClip && root.selectedTimelineClip.kind === "text"
                                ? String(root.selectedTimelineClip.text || "") : ""
                            placeholderText: "Текст титра"
                            color: theme.text
                            selectionColor: theme.accent
                            selectedTextColor: theme.background
                            placeholderTextColor: theme.muted
                            background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                            onEditingFinished: root.setSelectedClipProperty("text", text)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Размер"; color: theme.text; font.family: "monospace"; font.pixelSize: 10 }
                            SpinBox {
                                from: 8; to: 180; editable: true
                                palette.text: theme.text
                                background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                                contentItem: TextInput {
                                    text: parent.displayText
                                    color: theme.text
                                    selectionColor: theme.accent
                                    selectedTextColor: theme.background
                                    horizontalAlignment: Qt.AlignHCenter
                                    verticalAlignment: Qt.AlignVCenter
                                    font.family: "monospace"
                                    readOnly: !parent.editable
                                    validator: parent.validator
                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                }
                                value: Math.round(root.timelineClipProperty(root.selectedTimelineClip, "fontSize", 30))
                                onValueModified: root.setSelectedClipProperty("fontSize", value)
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Шрифт"; color: theme.text; font.family: "monospace"; font.pixelSize: 10 }
                            ComboBox {
                                Layout.fillWidth: true
                                model: ["Sans", "Serif", "Monospace", "DejaVu Sans", "CozetteVector"]
                                currentIndex: Math.max(0, model.indexOf(String(root.selectedTimelineClip && root.selectedTimelineClip.fontFamily || "Sans")))
                                palette.text: theme.text
                                background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                                onActivated: root.setSelectedClipProperty("fontFamily", currentText)
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Button {
                                text: "Выбрать цвет…"
                                onClicked: {
                                    textColorDialog.selectedColor = root.selectedTimelineClip
                                        ? String(root.selectedTimelineClip.textColor || "#ffffff") : "#ffffff"
                                    textColorDialog.open()
                                }
                            }
                            Rectangle {
                                width: 24; height: 24
                                color: root.selectedTimelineClip ? String(root.selectedTimelineClip.textColor || "#ffffff") : "#ffffff"
                                border.color: theme.border
                            }
                        }
                        TextField {
                            Layout.fillWidth: true
                            text: root.selectedTimelineClip && root.selectedTimelineClip.kind === "text"
                                ? String(root.selectedTimelineClip.textColor || "#ffffff") : "#ffffff"
                            placeholderText: "Цвет, например #ffffff"
                            color: theme.text
                            selectionColor: theme.accent
                            selectedTextColor: theme.background
                            placeholderTextColor: theme.muted
                            background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                            onEditingFinished: {
                                if (/^#[0-9a-fA-F]{6}$/.test(text))
                                    root.setSelectedClipProperty("textColor", text)
                                else
                                    root.statusMessage = "Цвет укажи в формате #RRGGBB"
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                    Text {
                        text: "ЦВЕТОКОРРЕКЦИЯ"
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: (12 * root.uiFontScale / 100)
                    }
                    Text {
                        visible: !root.selectedClipCanColorCorrect
                        text: "Выбери видео или изображение на таймлайне"
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: [
                            { label: "Яркость", key: "brightness" },
                            { label: "Контраст", key: "contrast" },
                            { label: "Насыщенность", key: "saturation" }
                        ]
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: theme.text
                                    font.family: "monospace"
                                    font.pixelSize: (11 * root.uiFontScale / 100)
                                }
                                Text {
                                    text: (root.timelineClipProperty(root.selectedTimelineClip, modelData.key, 0) > 0 ? "+" : "")
                                        + Number(root.timelineClipProperty(root.selectedTimelineClip, modelData.key, 0)).toFixed(2)
                                    color: theme.accent
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                }
                            }
                            Slider {
                                id: correctionSlider
                                Layout.fillWidth: true
                                from: -1
                                to: 1
                                stepSize: 0.05
                                value: root.timelineClipProperty(root.selectedTimelineClip, modelData.key, 0)
                                enabled: root.selectedClipCanColorCorrect
                                onPressedChanged: {
                                    if (pressed) root.transformPreviewOverride = ({})
                                    else root.commitSelectedClipPreviewProperty(modelData.key)
                                }
                                onMoved: root.previewSelectedClipProperty(modelData.key, Math.round(value * 100) / 100)
                                background: Rectangle {
                                    x: correctionSlider.leftPadding
                                    y: correctionSlider.topPadding + correctionSlider.availableHeight / 2 - height / 2
                                    width: correctionSlider.availableWidth
                                    height: 4
                                    radius: 2
                                    color: theme.background
                                    border.color: theme.border
                                    Rectangle {
                                        width: correctionSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color: theme.accent
                                    }
                                }
                                handle: Rectangle {
                                    x: correctionSlider.leftPadding + correctionSlider.visualPosition
                                        * (correctionSlider.availableWidth - width)
                                    y: correctionSlider.topPadding + correctionSlider.availableHeight / 2 - height / 2
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: correctionSlider.pressed ? theme.accent : theme.text
                                    border.color: theme.accent
                                }
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 8 }
                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
                    Text { text: "ЭКСПОРТ"; color: theme.accent; font.family: "monospace"; font.bold: true }
                    Text { text: "MP4 · H.264 · " + root.currentProjectResolution + " · " + root.currentProjectFps + " FPS"; color: theme.text; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100); wrapMode: Text.WordWrap }
                    Button {
                        text: exportController.running
                            ? "Экспорт · " + Math.round(exportController.progress * 100) + "%"
                            : "↗ Экспортировать MP4"
                        Layout.fillWidth: true
                        enabled: root.timelineDuration > 0 && !exportController.running
                        onClicked: exportDialog.open()
                        palette.buttonText: "#101522"
                        background: Rectangle { color: theme.accent; border.color: theme.accent; radius: 2 }
                    }
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
                    spacing: 5
                    Text {
                        text: "МАСШТАБ"
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: 10 * root.uiFontScale / 100
                    }
                    Button {
                        text: "−"
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 26
                        onClicked: root.setTimelineZoom(root.timelineZoom / 1.15)
                        palette.buttonText: theme.text
                        background: Rectangle { color: theme.panelAlt; border.color: theme.border; radius: 2 }
                    }
                    Slider {
                        id: timelineZoomSlider
                        Layout.preferredWidth: 210
                        Layout.minimumWidth: 95
                        Layout.maximumWidth: 270
                        from: 0
                        to: 100
                        stepSize: 0.5
                        value: 100 * Math.log(Math.max(0.05, root.timelineZoom) / 0.05) / Math.log(40 / 0.05)
                        onMoved: root.setTimelineZoom(0.05 * Math.pow(40 / 0.05, value / 100))
                        background: Rectangle {
                            x: timelineZoomSlider.leftPadding
                            y: timelineZoomSlider.topPadding + timelineZoomSlider.availableHeight / 2 - height / 2
                            width: timelineZoomSlider.availableWidth
                            height: 4
                            radius: 2
                            color: theme.background
                            border.color: theme.border
                            Rectangle {
                                width: timelineZoomSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: theme.accent
                            }
                        }
                        handle: Rectangle {
                            x: timelineZoomSlider.leftPadding + timelineZoomSlider.visualPosition
                                * (timelineZoomSlider.availableWidth - width)
                            y: timelineZoomSlider.topPadding + timelineZoomSlider.availableHeight / 2 - height / 2
                            width: 12
                            height: 12
                            radius: 6
                            color: timelineZoomSlider.pressed ? theme.accent : theme.text
                            border.color: theme.accent
                        }
                    }
                    Text {
                        text: (root.timelineZoom / 4).toFixed(2) + "×"
                        Layout.preferredWidth: 48
                        horizontalAlignment: Text.AlignHCenter
                        color: theme.accent
                        font.family: "monospace"
                        font.pixelSize: 11 * root.uiFontScale / 100
                    }
                    Button {
                        text: "Вписать"
                        Layout.preferredHeight: 26
                        onClicked: root.fitTimelineToProject()
                        palette.buttonText: theme.accent
                        background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.formatTime(root.timelinePosition) + " / " + root.formatTime(root.timelineDuration)
                            + " · область " + root.formatTime(root.timelineWorkspaceDuration)
                        color: theme.muted
                        font.family: "monospace"
                        font.pixelSize: 10 * root.uiFontScale / 100
                        elide: Text.ElideLeft
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0
                    Flickable {
                        id: timelineTrackLabelsViewport
                        Layout.preferredWidth: 150
                        Layout.minimumWidth: 120
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: timelineCanvas.height
                        contentY: timelineViewport.contentY
                        interactive: false
                        Column {
                            width: timelineTrackLabelsViewport.width
                            height: timelineCanvas.height
                            spacing: 3
                            Item { width: parent.width; height: 22 }
                            Repeater {
                                model: ["V2 · ВИДЕО", "V1 · ВИДЕО", "A1 · АУДИО", "A2 · АУДИО", "V3 · ТЕКСТ", "FX · РАЗМЫТИЕ"]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: parent.width
                                    height: 34
                                    color: theme.panelAlt
                                    border.color: theme.border
                                    Text { anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: theme.text; font.family: "monospace"; font.pixelSize: (12 * root.uiFontScale / 100) }
                                }
                            }
                        }
                    }
                    Flickable {
                        id: timelineViewport
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: timelineCanvas.width
                        contentHeight: timelineCanvas.height
                        flickableDirection: Flickable.HorizontalAndVerticalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        onContentXChanged: {
                            if (width <= 0 || root.timelineZoom <= 0) return
                            var maxX = Math.max(0, timelineCanvas.width - width)
                            if (contentX >= maxX - Math.max(24, width * 0.02)) {
                                var edgeTime = (contentX + width) / root.timelineZoom
                                root.timelineWorkspaceDemand = Math.max(root.timelineWorkspaceDemand, edgeTime + 120)
                            }
                        }
                        ScrollBar.horizontal: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }
                        WheelHandler {
                            target: null
                            onWheel: function(event) {
                                if (event.modifiers & Qt.ControlModifier) {
                                    root.setTimelineZoom(root.timelineZoom * (event.angleDelta.y > 0 ? 1.12 : 1 / 1.12))
                                } else if (Math.abs(event.angleDelta.x) > 0
                                               || (event.modifiers & Qt.ShiftModifier)) {
                                    var deltaX = Math.abs(event.angleDelta.x) > 0
                                        ? event.angleDelta.x : event.angleDelta.y
                                    var maxX = Math.max(0, timelineCanvas.width - timelineViewport.width)
                                    timelineViewport.contentX = Math.max(0, Math.min(maxX,
                                        timelineViewport.contentX - deltaX * 0.5))
                                } else {
                                    var maxY = Math.max(0, timelineCanvas.height - timelineViewport.height)
                                    timelineViewport.contentY = Math.max(0, Math.min(maxY,
                                        timelineViewport.contentY - event.angleDelta.y * 0.5))
                                }
                                event.accepted = true
                            }
                        }
                        Item {
                            id: timelineCanvas
                            width: Math.max(timelineViewport.width,
                                root.timelineWorkspaceDuration * timelineScale)
                            height: Math.max(timelineViewport.height, 22 + 6 * 37 + 8)
                            clip: true
                            // One stable scale is shared by ruler, clip geometry,
                            // dragging, resizing, drop positions and the playhead.
                            property real timelineScale: root.timelineZoom
                            readonly property real rulerStep: {
                                var raw = 100 / Math.max(0.5, timelineScale)
                                var power = Math.pow(10, Math.floor(Math.log10(raw)))
                                var normalized = raw / power
                                var factor = normalized <= 1 ? 1 : (normalized <= 2 ? 2 : (normalized <= 5 ? 5 : 10))
                                return Math.max(1, factor * power)
                            }
                            Column {
                                anchors.fill: parent
                                spacing: 3
                                Rectangle {
                                    width: parent.width
                                    height: 22
                                    color: theme.background
                                    clip: true
                                    Row {
                                        anchors.fill: parent
                                        Repeater {
                                            model: Math.ceil(root.timelineWorkspaceDuration / timelineCanvas.rulerStep) + 1
                                            delegate: Text {
                                                required property int index
                                                width: timelineCanvas.rulerStep * timelineCanvas.timelineScale
                                                text: root.formatTime(index * timelineCanvas.rulerStep)
                                                color: theme.muted
                                                font.family: "monospace"
                                                font.pixelSize: (12 * root.uiFontScale / 100)
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                    }
                                }
                            Repeater {
                                model: ["V2 · ВИДЕО", "V1 · ВИДЕО", "A1 · АУДИО", "A2 · АУДИО", "V3 · ТЕКСТ", "FX · РАЗМЫТИЕ"]
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
                                            property real dragOffsetX: 0
                                            property real dragOffsetY: 0
                                            property real dragStartX: 0
                                            property real dragStartY: 0
                                            property real dragStartClipX: 0
                                            property real dragStartClipY: 2
                                            property bool draggingClip: false

                                            property string resizingEdge: ""
                                            property real resizeAnchorX: 0
                                            property real resizeOriginalStart: 0
                                            property real resizeOriginalDuration: 1
                                            property real resizePreviewDuration: 1
                                            function beginResize(sceneX) {
                                                resizingEdge = "right"
                                                resizeAnchorX = sceneX
                                                resizeOriginalStart = Number(modelData.start || 0)
                                                resizeOriginalDuration = root.timelineClipDuration(modelData)
                                                resizePreviewDuration = resizeOriginalDuration
                                                draggingClip = false
                                            }
                                            function updateResize(sceneX) {
                                                var delta = (sceneX - resizeAnchorX) / Math.max(0.001, timelineCanvas.timelineScale)
                                                var maxDuration = 1000000
                                                var originalEnd = resizeOriginalStart + resizeOriginalDuration
                                                for (var i = 0; i < root.mediaFiles.length; ++i) {
                                                    var other = root.mediaFiles[i]
                                                    if (String(other.clipId || "") === String(modelData.clipId || "")
                                                            || Number(other.track) !== Number(modelData.track))
                                                        continue
                                                    var otherStart = Number(other.start || 0)
                                                    if (otherStart >= originalEnd - 0.001)
                                                        maxDuration = Math.min(maxDuration, otherStart - resizeOriginalStart)
                                                }
                                                resizePreviewDuration = Math.max(0.5, Math.min(maxDuration,
                                                    Math.round((resizeOriginalDuration + delta) * 10) / 10))
                                                root.timelineDragHorizon = Math.max(root.timelineDragHorizon,
                                                    resizeOriginalStart + resizePreviewDuration)
                                            }
                                            function finishResize() {
                                                if (resizingEdge === "") return
                                                var newDuration = resizePreviewDuration
                                                var clipId = String(modelData.clipId || "")
                                                resizingEdge = ""
                                                root.timelineAutoScrollDirection = 0
                                                var updated = root.mediaFiles.slice()
                                                for (var i = 0; i < updated.length; ++i) {
                                                    if (String(updated[i].clipId || "") === clipId) {
                                                        updated[i] = Object.assign({}, updated[i], { duration: newDuration })
                                                        break
                                                    }
                                                }
                                                root.recordTimelineHistory("Изменить длительность клипа")
                                                root.mediaFiles = updated
                                                root.timelineDragHorizon = 0
                                                root.saveTimelineMedia(updated)
                                                root.statusMessage = "Длина клипа изменена"
                                            } 
                                             x: Math.max(0, Number(modelData.start || 0) * timelineCanvas.timelineScale)
                                               + (draggingClip ? dragOffsetX : 0)
                                            width: Math.max(3, (resizingEdge !== "" ? resizePreviewDuration : root.timelineClipDuration(modelData))
                                                            * timelineCanvas.timelineScale)
                                            height: 30
                                            y: 2 + (draggingClip ? dragOffsetY : 0)
                                            clip: true
                                            color: modelData.kind === "effect" ? theme.accent
                                                : modelData.kind === "text" ? "#a36ac7"
                                                : modelData.kind === "audio" ? "#226d6c" : "#315b9b"
                                            border.color: theme.accent
                                            Row {
                                                anchors.fill: parent
                                                clip: true
                                                visible: timelineClip.modelData.kind !== "audio"
                                                    && timelineClip.modelData.kind !== "text"
                                                    && timelineClip.modelData.kind !== "effect"
                                                Repeater {
                                                    model: Math.max(1, Math.ceil(timelineClip.width / 54))
                                                    delegate: Image {
                                                        required property int index
                                                        width: 54
                                                        height: parent.height
                                                        source: {
                                                            // Reading this property creates a dependency so Image rechecks
                                                            // the cache when its async ffmpeg job finishes.
                                                            var revision = mediaTools.thumbnailRevision
                                                            return mediaTools.thumbnailAt(timelineClip.modelData.url,
                                                                Math.max(0, Number(timelineClip.modelData.start || 0) + index * (54 / Math.max(0.001, timelineCanvas.timelineScale))))
                                                        }
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
                                                text: modelData.kind === "text" ? "T · " + modelData.text
                                                    : modelData.kind === "effect" ? "FX · Размытие · " + Math.round(Number(modelData.blur || 0)) + "%"
                                                    : modelData.name
                                                color: "#f0f2ff"
                                                font.family: "monospace"
                                                font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                            z: draggingClip ? 10 : 1
                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton
                                                preventStealing: true
                                                cursorShape: pressed && mouseButtons === Qt.LeftButton
                                                    ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                                onPressed: function(mouse) {
                                                    root.timelineAutoScrollDirection = 0
                                                    root.timelineDragHorizon = 0
                                                    var scenePos = mapToItem(timelineCanvas, mouse.x, mouse.y)
                                                    dragOffsetX = 0
                                                    dragOffsetY = 0
                                                    draggingClip = false
                                                    dragStartX = scenePos.x
                                                    dragStartY = scenePos.y
                                                    dragStartClipX = timelineClip.x
                                                    dragStartClipY = timelineClip.y
                                                }
                                                onPositionChanged: function(mouse) {
                                                    if (!pressed) return
                                                    var scenePos = mapToItem(timelineCanvas, mouse.x, mouse.y)
                                                    var dx = scenePos.x - dragStartX
                                                    var dy = scenePos.y - dragStartY
                                                    if (!draggingClip && Math.abs(dx) + Math.abs(dy) > 4)
                                                        draggingClip = true
                                                    if (!draggingClip) return
                                                    var previewX = Math.max(0, dragStartClipX + dx)
                                                    var previewY = Math.max(-timelineClip.height - 2,
                                                                            Math.min(timelineTrack.height + 2,
                                                                                     dragStartClipY + dy))
                                                    var proposedEnd = previewX / Math.max(0.001, timelineCanvas.timelineScale)
                                                        + root.timelineClipDuration(timelineClip.modelData)
                                                    root.timelineDragHorizon = Math.max(root.timelineDragHorizon, proposedEnd)
                                                    var viewportPoint = mapToItem(timelineViewport, mouse.x, mouse.y)
                                                    if (viewportPoint.x > timelineViewport.width - 36)
                                                        root.timelineAutoScrollDirection = 1
                                                    else if (viewportPoint.x < 36 && timelineViewport.contentX > 0)
                                                        root.timelineAutoScrollDirection = -1
                                                    else
                                                        root.timelineAutoScrollDirection = 0
                                                    var modelX = Math.max(0, Number(timelineClip.modelData.start || 0)
                                                                             * timelineCanvas.timelineScale)
                                                    // Do not assign directly to x/y: that would permanently break
                                                    // QML's model-position bindings after the drag is finished.
                                                    timelineClip.dragOffsetX = previewX - modelX
                                                    timelineClip.dragOffsetY = previewY - 2
                                                }
                                                onReleased: function(mouse) {
                                                    var wasDragging = draggingClip
                                                    var scenePos = mapToItem(timelineCanvas, mouse.x, mouse.y)
                                                    var draggedX = timelineClip.x
                                                    draggingClip = false
                                                    root.timelineAutoScrollDirection = 0
                                                    dragOffsetX = 0
                                                    dragOffsetY = 0
                                                    if (!wasDragging) {
                                                        root.timelineDragHorizon = 0
                                                        root.selectedTimelineClipId = String(timelineClip.modelData.clipId || "")
                                                        root.selectedMedia = String(timelineClip.modelData.name || "")
                                                        // Selecting a clip must not seek the playhead to its start.
                                                        return
                                                    }

                                                    var updated = root.mediaFiles.slice()
                                                    var movingIndex = -1
                                                    for (var i = 0; i < updated.length; ++i) {
                                                        if (String(updated[i].clipId || "") !== ""
                                                                && String(updated[i].clipId) === String(timelineClip.modelData.clipId)) {
                                                            movingIndex = i
                                                            break
                                                        }
                                                    }
                                                    if (movingIndex < 0) return

                                                    var duration = root.timelineClipDuration(updated[movingIndex])
                                                    var desiredStart = Math.max(0, Math.round(draggedX / Math.max(0.001, timelineCanvas.timelineScale)))
                                                    // The track rows start at y=25 and repeat every 37 pixels.
                                                    var requestedTrack = Math.max(0, Math.min(5, Math.floor((scenePos.y - 23.5) / 37)))
                                                     var targetTrack = root.timelineTrackForKind(updated[movingIndex].kind, requestedTrack)
                                                    var clipId = String(updated[movingIndex].clipId || "")
                                                    var placedStart = root.findFreeTimelineStart(targetTrack, desiredStart, duration, clipId)
                                                    var didSnap = Math.abs(placedStart - desiredStart) > 0.001
                                                    updated[movingIndex] = Object.assign({}, updated[movingIndex], {
                                                        start: placedStart,
                                                        track: targetTrack
                                                    })
                                                    if (didSnap) {
                                                        root.statusMessage = "Клип сдвинут на свободное место"
                                                    } else {
                                                        root.statusMessage = targetTrack === Number(timelineClip.modelData.track)
                                                            ? "Клип перемещён"
                                                            : "Клип перемещён на дорожку " + ["V2", "V1", "A1", "A2", "V3"][targetTrack]
                                                    }
                                                    root.recordTimelineHistory("Переместить клип")
                                                    root.mediaFiles = updated
                                                    root.timelineDragHorizon = 0
                                                    if (root.currentProjectPath !== "")
                                                        projectStore.saveProjectMedia(root.currentProjectPath, updated)
                                                }
                                            }
                                            // Handle right-click separately from the left-button drag/select area.
                                            // This prevents context-menu clicks from entering the clip's seek/drag handler.
                                            MouseArea {
                                                anchors.fill: parent
                                                z: 20
                                                acceptedButtons: Qt.RightButton
                                                preventStealing: true
                                                onClicked: {
                                                    root.contextMenuClipId = String(timelineClip.modelData.clipId || "")
                                                    root.contextMenuTimelinePosition = root.timelinePosition
                                                    root.selectedTimelineClipId = root.contextMenuClipId
                                                    timelineClipContextMenu.popup()
                                                }
                                            }
                                             Rectangle {
                                                 anchors.right: parent.right
                                                 anchors.top: parent.top
                                                 anchors.bottom: parent.bottom
                                                 width: 7
                                                 color: "#dce5ff"
                                                 opacity: 0.9
                                                 visible: !timelineClip.draggingClip
                                                 z: 30
                                                 MouseArea {
                                                     anchors.fill: parent
                                                     cursorShape: Qt.SizeHorCursor
                                                     onPressed: function(mouse) {
                                                         root.timelineAutoScrollDirection = 0
                                                         timelineClip.beginResize(mapToItem(timelineCanvas, mouse.x, mouse.y).x)
                                                     }
                                                     onPositionChanged: function(mouse) {
                                                         if (!pressed) return
                                                         timelineClip.updateResize(mapToItem(timelineCanvas, mouse.x, mouse.y).x)
                                                         var viewportPoint = mapToItem(timelineViewport, mouse.x, mouse.y)
                                                         if (viewportPoint.x > timelineViewport.width - 36)
                                                             root.timelineAutoScrollDirection = 1
                                                         else if (viewportPoint.x < 36 && timelineViewport.contentX > 0)
                                                             root.timelineAutoScrollDirection = -1
                                                         else
                                                             root.timelineAutoScrollDirection = 0
                                                     }
                                                     onReleased: timelineClip.finishResize()
                                                     onCanceled: timelineClip.finishResize()
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
                                                if (root.normalizedMediaUrl(updated[i].url) === root.normalizedMediaUrl(url) && Number(updated[i].track) < 0) {
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
                                            var requestedStart = Math.max(0, Math.round(drop.x / Math.max(0.001, timelineCanvas.timelineScale)))
                                             var targetTrack = root.timelineTrackForKind(source.kind, timelineTrack.index)
                                             var duration = root.timelineClipDuration(source)
                                             var start = root.findFreeTimelineStart(targetTrack, requestedStart, duration, "")
                                            var didSnap = Math.abs(start - requestedStart) > 0.001

                                            var clip = Object.assign({}, source, {
                                                 clipId: root.createTimelineClipId(),
                                                 track: targetTrack,
                                                 start: start,
                                                 duration: duration,
                                                 x: 0, y: 0, scale: 100,
                                                 rotation: 0, opacity: 100, volume: 100,
                                                 fontSize: 30, textColor: "#ffffff"
                                             })
                                             updated.push(clip)
                                             root.selectedTimelineClipId = String(clip.clipId)
                                             root.selectedMedia = String(clip.name || "")
                                              root.recordTimelineHistory("Добавить клип на таймлайн")
                                             root.mediaFiles = updated
                                            root.saveTimelineMedia(updated)
                                            root.timelinePosition = start
                                             root.updateTimelinePreview(start)
                                            var actualTrackName = ["V2 · ВИДЕО", "V1 · ВИДЕО", "A1 · АУДИО", "A2 · АУДИО", "V3 · ТЕКСТ"][targetTrack]
                                             root.statusMessage = didSnap
                                                 ? "Клип размещён рядом на " + actualTrackName
                                                 : "Клип добавлен на " + actualTrackName
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
                        MouseArea {
                            id: playheadLineDragArea
                            x: Math.max(0, Math.min(timelineCanvas.width - width, timelinePlayhead.x - width / 2))
                            y: 32
                            width: 12
                            height: Math.max(0, timelineCanvas.height - y)
                            z: 9
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true
                            cursorShape: pressed ? Qt.SizeHorCursor : Qt.OpenHandCursor
                            onPressed: function(mouse) {
                                root.timelinePlayheadDragging = true
                                timelineViewport.interactive = false
                                root.timelineDragHorizon = 0
                                root.setPlayheadFromPointer(playheadLineDragArea, mouse)
                            }
                            onPositionChanged: function(mouse) {
                                if (pressed)
                                    root.setPlayheadFromPointer(playheadLineDragArea, mouse)
                            }
                            onReleased: {
                                root.timelinePlayheadDragging = false
                                timelineViewport.interactive = true
                                root.timelineAutoScrollDirection = 0
                                root.timelineAutoScrollVelocity = 0
                                root.timelineDragHorizon = 0
                            }
                            onCanceled: {
                                root.timelinePlayheadDragging = false
                                timelineViewport.interactive = true
                                root.timelineAutoScrollDirection = 0
                                root.timelineAutoScrollVelocity = 0
                                root.timelineDragHorizon = 0
                            }
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
                        }
                        MouseArea {
                            id: playheadDragArea
                            x: Math.max(0, Math.min(timelineCanvas.width - width, timelinePlayhead.x - width / 2))
                            y: 0
                            width: 26
                            height: 32
                            z: 12
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true
                            cursorShape: pressed ? Qt.SizeHorCursor : Qt.OpenHandCursor
                            onPressed: function(mouse) {
                                root.timelinePlayheadDragging = true
                                timelineViewport.interactive = false
                                root.timelineDragHorizon = 0
                                root.setPlayheadFromPointer(playheadDragArea, mouse)
                            }
                            onPositionChanged: function(mouse) {
                                if (pressed)
                                    root.setPlayheadFromPointer(playheadDragArea, mouse)
                            }
                            onReleased: {
                                root.timelinePlayheadDragging = false
                                timelineViewport.interactive = true
                                root.timelineAutoScrollDirection = 0
                                root.timelineAutoScrollVelocity = 0
                                root.timelineDragHorizon = 0
                            }
                            onCanceled: {
                                root.timelinePlayheadDragging = false
                                timelineViewport.interactive = true
                                root.timelineAutoScrollDirection = 0
                                root.timelineAutoScrollVelocity = 0
                                root.timelineDragHorizon = 0
                            }
                        }
                    }
                    }
                }
            }
        }
    }

    Timer {
        id: timelineAutoScrollTimer
        interval: 16
        repeat: true
        running: root.timelineAutoScrollDirection !== 0 && root.currentProjectPath !== ""
        onTriggered: {
            var maxX = Math.max(0, timelineCanvas.width - timelineViewport.width)
            if (root.timelineAutoScrollDirection > 0
                    && timelineViewport.contentX >= maxX - 100) {
                var edgeTime = (timelineViewport.contentX + timelineViewport.width) / root.timelineZoom
                root.timelineDragHorizon = Math.max(root.timelineDragHorizon, edgeTime + 120)
            }
            var step = 12
            if (root.timelinePlayheadDragging) {
                var zoomForSpeed = Math.max(0.1, root.timelineZoom)
                var maxStep = Math.max(1, Math.min(80, zoomForSpeed * 2.0))
                root.timelineAutoScrollVelocity = Math.min(maxStep,
                    Math.max(zoomForSpeed * 0.3,
                        root.timelineAutoScrollVelocity + Math.max(0.08, zoomForSpeed * 0.05)))
                step = root.timelineAutoScrollVelocity
            } else {
                root.timelineAutoScrollVelocity = 0
            }
            timelineViewport.contentX = Math.max(0, Math.min(
                Math.max(0, timelineCanvas.width - timelineViewport.width),
                timelineViewport.contentX + root.timelineAutoScrollDirection * step))
            if (root.timelinePlayheadDragging) {
                var edgeX = timelineViewport.contentX
                    + (root.timelineAutoScrollDirection > 0 ? timelineViewport.width - 20 : 20)
                var targetSeconds = edgeX / Math.max(0.001, root.timelineZoom)
                root.timelineDragHorizon = Math.max(root.timelineDragHorizon,
                    targetSeconds + (root.timelineAutoScrollDirection > 0 ? 120 : 0))
                root.timelinePosition = Math.max(0, Math.min(root.timelineWorkspaceDuration, targetSeconds))
                root.updateTimelinePreview(root.timelinePosition)
            }
        }
    }

    onTimelinePositionChanged: {
        if (timelinePlaybackTimer.running)
            Qt.callLater(root.keepTimelinePlayheadVisible)
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
