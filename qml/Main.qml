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
            || ((selectedTimelineClip.kind === "video" || selectedTimelineClip.kind === "image")
                && (Number(selectedTimelineClip.track) === 0 || Number(selectedTimelineClip.track) === 1)))
    readonly property bool selectedClipCanColorCorrect: !!selectedTimelineClip
        && (selectedTimelineClip.kind === "image"
            || (selectedTimelineClip.kind === "video"
                && (Number(selectedTimelineClip.track) === 0 || Number(selectedTimelineClip.track) === 1)))
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
    property int timelineClipSerial: 0
    property string contextMenuClipId: ""
    property real contextMenuTimelinePosition: 0
    // Temporary transform values update the preview every frame and are saved
    // to the project only when the user releases a transform handle.
    property var transformPreviewOverride: ({})
    property var transformGesture: null

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

    // A stable ID distinguishes two instances of the same source file on the timeline.
    function createTimelineClipId() {
        timelineClipSerial += 1
        return "clip-" + Date.now() + "-" + timelineClipSerial
    }

    function timelineClipDuration(item) {
        var value = Number(item.duration)
        if (isFinite(value) && value > 0) return value
        if (item && (item.kind === "image" || item.kind === "text")) return 5
        return 36
    }

    function timelineTrackForKind(kind, requestedTrack) {
        var track = Math.max(0, Math.min(4, Number(requestedTrack)))
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

    function timelineTextAt(seconds) {
        var active = mediaFiles.filter(function(item) {
            return item.kind === "text" && Number(item.track) >= 0
                && Number(item.start || 0) <= seconds
                && Number(item.start || 0) + timelineClipDuration(item) > seconds
        })
        active.sort(function(a, b) { return Number(a.track) - Number(b.track) })
        return active.length ? active[active.length - 1] : null
    }

    function setSelectedClipProperty(key, value, persist) {
        var id = String(selectedTimelineClipId || "")
        if (id === "") return
        var updated = mediaFiles.slice()
        for (var i = 0; i < updated.length; ++i) {
            if (Number(updated[i].track) >= 0 && String(updated[i].clipId || "") === id) {
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
        setSelectedClipProperty(key, value, false)
        transformPreviewOverride = ({})
        saveTimelineMedia(mediaFiles)
        statusMessage = "Свойство клипа обновлено"
    }

    function previewHasSelectedTransformClip() {
        if (!selectedClipCanTransform || !timelinePreviewActive || timelinePlaybackTimer.running) return false
        if (selectedTimelineClip.kind === "text") {
            var title = timelineTextAt(timelinePosition)
            return !!title && String(title.clipId || "") === String(selectedTimelineClipId)
        }
        var visual = timelineVideoAt(timelinePosition)
        return !!visual && String(visual.clipId || "") === String(selectedTimelineClipId)
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
        if (g.mode === "move") {
            if (draft.x !== undefined) setSelectedClipProperty("x", draft.x, false)
            if (draft.y !== undefined) setSelectedClipProperty("y", draft.y, false)
        } else if (g.mode === "scale" && draft.scale !== undefined) {
            setSelectedClipProperty("scale", draft.scale, false)
        } else if (g.mode === "rotate" && draft.rotation !== undefined) {
            setSelectedClipProperty("rotation", draft.rotation, false)
        }
        transformGesture = null
        transformPreviewOverride = ({})
        saveTimelineMedia(mediaFiles)
        statusMessage = "Трансформация применена"
    }

    function resetSelectedClipTransform() {
        if (!selectedTimelineClip) return
        var defaults = {
            x: 0, y: 0, scale: 100, rotation: 0,
            opacity: 100, brightness: 0, contrast: 0, saturation: 0
        }
        for (var key in defaults)
            setSelectedClipProperty(key, defaults[key], false)
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
        original.duration = leftDuration
        updated[index] = original
        var rightClip = Object.assign({}, original, {
            clipId: createTimelineClipId(),
            start: cutAt,
            duration: rightDuration,
            sourceOffset: Math.max(0, Number(original.sourceOffset || 0)) + leftDuration
        })
        updated.splice(index + 1, 0, rightClip)
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
        mediaFiles = updated
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

        var url = String(clip.url || "")
        var clipId = String(clip.clipId || "")
        var clipStart = Number(clip.start || 0)
        var offset = Math.max(0, Number(clip.sourceOffset || 0) + seconds - clipStart)

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

            var footageUrl = String(footage.url || "")
            var footageId = String(footage.clipId || "")
            var footageStart = Number(footage.start || 0)
            var footageOffset = Math.max(0, Number(footage.sourceOffset || 0) + seconds - footageStart)
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

            if (currentClip) {
                var currentId = String(currentClip.clipId || "")
                var sameClip = currentId !== "" && currentId === String(root.timelinePreviewClipId)
                var sameSource = String(currentClip.url) === String(root.timelinePreviewUrl)
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
                : (timelinePlaybackTimer.running ? 0.0
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
                    if (timelinePlaybackTimer.running) mediaPlayer.play()
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
                                    else if (modelData[1] === "Текст") textClipDialog.open()
                                    else if (modelData[1] === "Аудио") importDialog.open()
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
                        id: mediaSearchField
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: mediaPanel.width - 18
                        placeholderText: "Поиск медиа…"
                        text: root.mediaSearch
                        onTextChanged: root.mediaSearch = text
                        color: theme.text
                        placeholderTextColor: theme.muted
                        background: Rectangle { color: theme.background; border.color: theme.border; radius: 2 }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        Button {
                            text: "+ Импорт"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: 34
                            leftPadding: 4
                            rightPadding: 4
                            font.family: "monospace"
                            font.pixelSize: 11
                            onClicked: importDialog.open()
                            palette.buttonText: theme.text
                            background: Rectangle { color: theme.panelAlt; border.color: theme.accent; radius: 2 }
                        }
                        Button {
                            text: "+ Текст"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: 34
                            font.family: "monospace"
                            font.pixelSize: 11
                            onClicked: textClipDialog.open()
                            palette.buttonText: theme.text
                            background: Rectangle { color: theme.panelAlt; border.color: theme.accent2; radius: 2 }
                        }
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

                        VideoOutput {
                            id: videoOutput
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectFit
                            visible: true
                            opacity: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "opacity", 100) / 100
                            transform: [
                                Scale {
                                    xScale: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "scale", 100) / 100
                                    yScale: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "scale", 100) / 100
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
                            layer.effect: MultiEffect {
                                brightness: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "brightness", 0)
                                contrast: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "contrast", 0)
                                saturation: root.timelineClipProperty(root.timelineFootageAt(root.timelinePosition), "saturation", 0)
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
                                return mediaTools.previewFrameAt(clip.url, elapsed)
                            }
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            visible: root.timelinePreviewActive
                                && !root.timelineImageActive
                                && root.timelineVideoAt(root.timelinePosition) !== null
                                && root.timelineVideoAt(root.timelinePosition).kind === "video"
                                && (!timelinePlaybackTimer.running
                                    || mediaPlayer.playbackState !== MediaPlayer.PlayingState)
                            opacity: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "opacity", 100) / 100
                            transform: [
                                Translate {
                                    x: root.timelinePreviewOffsetX(root.timelineVideoAt(root.timelinePosition), timelineVideoStillPreview.width)
                                    y: root.timelinePreviewOffsetY(root.timelineVideoAt(root.timelinePosition), timelineVideoStillPreview.height)
                                },
                                Scale {
                                    xScale: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "scale", 100) / 100
                                    yScale: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "scale", 100) / 100
                                    origin.x: timelineVideoStillPreview.width / 2
                                    origin.y: timelineVideoStillPreview.height / 2
                                },
                                Rotation {
                                    angle: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "rotation", 0)
                                    origin.x: timelineVideoStillPreview.width / 2
                                    origin.y: timelineVideoStillPreview.height / 2
                                }
                            ]
                            layer.enabled: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "brightness", 0) !== 0
                                || root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "contrast", 0) !== 0
                                || root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "saturation", 0) !== 0
                            layer.effect: MultiEffect {
                                brightness: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "brightness", 0)
                                contrast: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "contrast", 0)
                                saturation: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "saturation", 0)
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
                                    xScale: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "scale", 100) / 100
                                    yScale: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "scale", 100) / 100
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
                            layer.effect: MultiEffect {
                                brightness: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "brightness", 0)
                                contrast: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "contrast", 0)
                                saturation: root.timelineClipProperty(root.timelineVideoAt(root.timelinePosition), "saturation", 0)
                            }
                            z: 1
                        }

                        Text {
                            id: timelineTextOverlay
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * 0.86
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
                        Item {
                            id: transformOverlay
                            anchors.fill: parent
                            z: 20
                            visible: root.previewHasSelectedTransformClip()
                            property var targetClip: root.selectedTimelineClip
                            readonly property bool titleTarget: targetClip && targetClip.kind === "text"
                            readonly property real targetScale: root.timelineClipProperty(targetClip, "scale", 100) / 100
                            readonly property real baseWidth: titleTarget ? timelineTextOverlay.width : previewCanvas.width
                            readonly property real baseHeight: titleTarget ? Math.max(32, timelineTextOverlay.height) : previewCanvas.height

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
                                    property point targetPoint: transformBounds.mapToItem(
                                        transformOverlay,
                                        modelData.horizontal < 0 ? 0 : transformBounds.width,
                                        modelData.vertical < 0 ? 0 : transformBounds.height)
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
                                property point targetPoint: transformBounds.mapToItem(
                                    transformOverlay, transformBounds.width / 2, 0)
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
                        Item { width: parent.width; height: 22 }
                        Repeater {
                            model: ["V2 · ВИДЕО", "V1 · ВИДЕО", "A1 · АУДИО", "A2 · АУДИО", "V3 · ТЕКСТ"]
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
                                model: ["V2 · ВИДЕО", "V1 · ВИДЕО", "A1 · АУДИО", "A2 · АУДИО", "V3 · ТЕКСТ"]
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
                                            }
                                            function finishResize() {
                                                if (resizingEdge === "") return
                                                var newDuration = resizePreviewDuration
                                                var clipId = String(modelData.clipId || "")
                                                resizingEdge = ""
                                                var updated = root.mediaFiles.slice()
                                                for (var i = 0; i < updated.length; ++i) {
                                                    if (String(updated[i].clipId || "") === clipId) {
                                                        updated[i] = Object.assign({}, updated[i], { duration: newDuration })
                                                        break
                                                    }
                                                }
                                                root.mediaFiles = updated
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
                                            color: modelData.kind === "text" ? "#a36ac7"
                                                : modelData.kind === "audio" ? "#226d6c" : "#315b9b"
                                            border.color: theme.accent
                                            Row {
                                                anchors.fill: parent
                                                clip: true
                                                visible: timelineClip.modelData.kind !== "audio" && timelineClip.modelData.kind !== "text"
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
                                                text: modelData.kind === "text" ? "T · " + modelData.text : modelData.name
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
                                                    var previewX = Math.max(0, Math.min(timelineTrack.width - timelineClip.width,
                                                                                       dragStartClipX + dx))
                                                    var previewY = Math.max(-timelineClip.height - 2,
                                                                            Math.min(timelineTrack.height + 2,
                                                                                     dragStartClipY + dy))
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
                                                    dragOffsetX = 0
                                                    dragOffsetY = 0
                                                    if (!wasDragging) {
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
                                                    var requestedTrack = Math.max(0, Math.min(4, Math.floor((scenePos.y - 23.5) / 37)))
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
                                                    root.mediaFiles = updated
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
                                                         timelineClip.beginResize(mapToItem(timelineCanvas, mouse.x, mouse.y).x)
                                                     }
                                                     onPositionChanged: function(mouse) {
                                                         if (pressed) timelineClip.updateResize(mapToItem(timelineCanvas, mouse.x, mouse.y).x)
                                                     }
                                                     onReleased: timelineClip.finishResize()
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
