#include "ExportController.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QUrl>
#include <QVector>
#include <algorithm>
#include <cmath>

namespace {
QString localPath(const QString &value)
{
    const QUrl url(value);
    return url.isLocalFile() ? url.toLocalFile() : value;
}

QString number(double value)
{
    return QString::number(value, 'f', 3);
}

QString escapeFilterPath(QString path)
{
    path.replace(QStringLiteral("\\"), QStringLiteral("\\\\"));
    path.replace(QStringLiteral("'"), QStringLiteral("\\'"));
    path.replace(QStringLiteral(":"), QStringLiteral("\\:"));
    path.replace(QStringLiteral(","), QStringLiteral("\\,"));
    path.replace(QStringLiteral("["), QStringLiteral("\\["));
    path.replace(QStringLiteral("]"), QStringLiteral("\\]"));
    return path;
}

QString runTool(const QString &program, const QStringList &arguments, int timeoutMs = 8000)
{
    QProcess process;
    process.start(program, arguments);
    if (!process.waitForStarted(1500))
        return {};
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished();
        return {};
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
        return {};
    return QString::fromUtf8(process.readAllStandardOutput()).trimmed();
}

bool hasAudioStream(const QString &path)
{
    return !runTool(QStringLiteral("ffprobe"), {
        QStringLiteral("-v"), QStringLiteral("error"),
        QStringLiteral("-select_streams"), QStringLiteral("a:0"),
        QStringLiteral("-show_entries"), QStringLiteral("stream=index"),
        QStringLiteral("-of"), QStringLiteral("csv=p=0"), path
    }).isEmpty();
}

double clipDuration(const QVariantMap &item)
{
    bool ok = false;
    const double value = item.value(QStringLiteral("duration")).toDouble(&ok);
    if (ok && std::isfinite(value) && value > 0.0)
        return value;
    const QString kind = item.value(QStringLiteral("kind")).toString();
    return (kind == QStringLiteral("image") || kind == QStringLiteral("text")
            || kind == QStringLiteral("effect")) ? 5.0 : 36.0;
}

double boundedItemValue(const QVariantMap &item, const QString &key,
                        double fallback, double minimum, double maximum)
{
    bool ok = false;
    const double value = item.value(key).toDouble(&ok);
    if (!ok || !std::isfinite(value))
        return fallback;
    return qBound(minimum, value, maximum);
}

QString ffmpegFontColor(QString value)
{
    static const QRegularExpression valid(QStringLiteral("^#([0-9a-fA-F]{6})$"));
    const auto match = valid.match(value);
    return match.hasMatch() ? QStringLiteral("0x") + match.captured(1) : QStringLiteral("0xffffff");
}

QStringList encoderArguments(bool useGpu)
{
    if (useGpu) {
        return {
            QStringLiteral("-c:v"), QStringLiteral("h264_nvenc"),
            QStringLiteral("-preset"), QStringLiteral("p2"),
            QStringLiteral("-rc"), QStringLiteral("vbr"),
            QStringLiteral("-cq"), QStringLiteral("23"),
            QStringLiteral("-b:v"), QStringLiteral("0")
        };
    }
    return {
        QStringLiteral("-c:v"), QStringLiteral("libx264"),
        QStringLiteral("-preset"), QStringLiteral("veryfast"),
        QStringLiteral("-crf"), QStringLiteral("22")
    };
}
}

ExportController::ExportController(QObject *parent)
    : QObject(parent)
{
    connect(&m_process, &QProcess::readyReadStandardOutput,
            this, &ExportController::readProgressOutput);
    connect(&m_process, &QProcess::readyReadStandardError, this, [this]() {
        const QString chunk = QString::fromUtf8(m_process.readAllStandardError());
        m_lastError += chunk;
        if (m_lastError.size() > 24000)
            m_lastError = m_lastError.right(24000);
    });
    connect(&m_process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, &ExportController::handleFinished);
    connect(&m_process, &QProcess::errorOccurred,
            this, &ExportController::handleProcessError);
}

bool ExportController::startExport(const QVariantList &timelineItems, const QString &outputUrl,
                                   int width, int height, int fps)
{
    if (m_running || m_process.state() != QProcess::NotRunning) {
        emit statusChanged(QStringLiteral("Экспорт уже выполняется"));
        return false;
    }
    if (!m_temporaryDirectory.isValid()) {
        emit exportFailed(QStringLiteral("Не удалось создать временную папку для экспорта"));
        return false;
    }

    m_outputWidth = qBound(320, width > 0 ? width : 1920, 3840);
    m_outputHeight = qBound(240, height > 0 ? height : 1080, 3840);
    if (m_outputWidth % 2 != 0) --m_outputWidth;
    if (m_outputHeight % 2 != 0) --m_outputHeight;
    m_outputFps = qBound(1, fps > 0 ? fps : 30, 120);

    m_outputPath = localPath(outputUrl).trimmed();
    if (m_outputPath.isEmpty()) {
        emit exportFailed(QStringLiteral("Не указан путь для экспорта"));
        return false;
    }
    if (!m_outputPath.endsWith(QStringLiteral(".mp4"), Qt::CaseInsensitive))
        m_outputPath += QStringLiteral(".mp4");
    const QFileInfo outputInfo(m_outputPath);
    if (!outputInfo.dir().exists()) {
        emit exportFailed(QStringLiteral("Папка для экспорта не существует"));
        return false;
    }

    QVector<Clip> clips;
    QVector<Clip> inputClips;
    m_timelineDuration = 0.0;

    for (const QVariant &value : timelineItems) {
        const QVariantMap item = value.toMap();
        const int track = item.value(QStringLiteral("track"), -1).toInt();
        if (track < 0)
            continue;

        Clip clip;
        clip.kind = item.value(QStringLiteral("kind")).toString();
        clip.text = item.value(QStringLiteral("text")).toString();
        clip.track = track;
        clip.start = qMax(0.0, item.value(QStringLiteral("start")).toDouble());
        clip.duration = clipDuration(item);
        clip.sourceOffset = qMax(0.0, item.value(QStringLiteral("sourceOffset")).toDouble());
        clip.x = boundedItemValue(item, QStringLiteral("x"), 0.0, -7680.0, 7680.0);
        clip.y = boundedItemValue(item, QStringLiteral("y"), 0.0, -4320.0, 4320.0);
        clip.scale = boundedItemValue(item, QStringLiteral("scale"), 100.0, 10.0, 300.0);
        clip.zoomMode = item.value(QStringLiteral("zoomMode"), QStringLiteral("none")).toString();
        if (clip.zoomMode != QStringLiteral("in") && clip.zoomMode != QStringLiteral("out"))
            clip.zoomMode = QStringLiteral("none");
        clip.zoomAmount = boundedItemValue(item, QStringLiteral("zoomAmount"), 150.0, 110.0, 250.0);
        clip.reverse = item.value(QStringLiteral("reverse"), false).toBool();
        clip.transitionIn = boundedItemValue(item, QStringLiteral("transitionIn"), 0.0, 0.0, 30.0);
        clip.transitionOut = boundedItemValue(item, QStringLiteral("transitionOut"), 0.0, 0.0, 30.0);
        clip.rotation = boundedItemValue(item, QStringLiteral("rotation"), 0.0, -360.0, 360.0);
        clip.opacity = boundedItemValue(item, QStringLiteral("opacity"), 100.0, 0.0, 100.0);
        clip.volume = boundedItemValue(item, QStringLiteral("volume"), 100.0, 0.0, 200.0);
        clip.audioPan = boundedItemValue(item, QStringLiteral("audioPan"), 0.0, -100.0, 100.0);
        clip.audioFadeIn = boundedItemValue(item, QStringLiteral("audioFadeIn"), 0.0, 0.0, 60.0);
        clip.audioFadeOut = boundedItemValue(item, QStringLiteral("audioFadeOut"), 0.0, 0.0, 60.0);
        clip.audioMuted = item.value(QStringLiteral("audioMuted"), false).toBool();
        clip.audioNormalize = item.value(QStringLiteral("audioNormalize"), false).toBool();
        clip.audioCompressor = item.value(QStringLiteral("audioCompressor"), false).toBool();
        clip.audioDenoise = item.value(QStringLiteral("audioDenoise"), false).toBool();
        clip.audioLimiter = item.value(QStringLiteral("audioLimiter"), false).toBool();
        const int eqFrequencies[] = {31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};
        for (int frequency : eqFrequencies) {
            clip.equalizerBands.push_back(boundedItemValue(
                item, QStringLiteral("eq%1").arg(frequency), 0.0, -12.0, 12.0));
        }
        clip.brightness = boundedItemValue(item, QStringLiteral("brightness"), 0.0, -1.0, 1.0);
        clip.contrast = boundedItemValue(item, QStringLiteral("contrast"), 0.0, -1.0, 1.0);
        clip.saturation = boundedItemValue(item, QStringLiteral("saturation"), 0.0, -1.0, 1.0);
        clip.blur = boundedItemValue(item, QStringLiteral("blur"), 0.0, 0.0, 100.0);
        clip.fontSize = boundedItemValue(item, QStringLiteral("fontSize"), 42.0, 8.0, 180.0);
        const QString requestedFont = item.value(QStringLiteral("fontFamily"), QStringLiteral("Sans")).toString();
        const QStringList supportedFonts = { QStringLiteral("Sans"), QStringLiteral("Serif"),
            QStringLiteral("Monospace"), QStringLiteral("DejaVu Sans"), QStringLiteral("CozetteVector") };
        clip.fontFamily = supportedFonts.contains(requestedFont) ? requestedFont : QStringLiteral("Sans");
        clip.textColor = ffmpegFontColor(item.value(QStringLiteral("textColor"), QStringLiteral("#ffffff")).toString());
        if (!std::isfinite(clip.start) || !std::isfinite(clip.duration) || clip.duration <= 0.0)
            continue;

        m_timelineDuration = qMax(m_timelineDuration, clip.start + clip.duration);
        if (clip.kind == QStringLiteral("text") || clip.kind == QStringLiteral("effect")) {
            clips.push_back(clip);
            continue;
        }

        const bool visual = (clip.kind == QStringLiteral("video") || clip.kind == QStringLiteral("image"))
            && (track == 0 || track == 1);
        const bool audio = (clip.kind == QStringLiteral("audio") || clip.kind == QStringLiteral("video"))
            && (track == 2 || track == 3);
        if (!visual && !audio)
            continue;

        clip.path = localPath(item.value(QStringLiteral("url")).toString());
        if (clip.path.isEmpty() || !QFileInfo::exists(clip.path)) {
            emit exportFailed(QStringLiteral("Файл клипа не найден: ")
                              + item.value(QStringLiteral("name")).toString());
            return false;
        }
        clip.inputIndex = inputClips.size();
        inputClips.push_back(clip);
        clips.push_back(clip);
    }

    if (clips.isEmpty() || m_timelineDuration <= 0.0) {
        emit exportFailed(QStringLiteral("На таймлайне нет клипов для экспорта"));
        return false;
    }

    QHash<QString, bool> audioCache;
    for (Clip &clip : inputClips) {
        if (clip.kind != QStringLiteral("video"))
            continue;
        if (!audioCache.contains(clip.path))
            audioCache.insert(clip.path, hasAudioStream(clip.path));
        clip.hasAudio = audioCache.value(clip.path);
    }
    for (Clip &clip : clips) {
        if (clip.inputIndex >= 0 && clip.inputIndex < inputClips.size())
            clip.hasAudio = inputClips[clip.inputIndex].hasAudio;
    }

    m_baseArguments = {
        QStringLiteral("-hide_banner"),
        QStringLiteral("-y"),
        QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-nostats"),
        QStringLiteral("-progress"), QStringLiteral("pipe:1")
    };

    for (const Clip &clip : inputClips) {
        if (clip.kind == QStringLiteral("image")) {
            m_baseArguments << QStringLiteral("-loop") << QStringLiteral("1")
                            << QStringLiteral("-framerate") << QString::number(m_outputFps)
                            << QStringLiteral("-t") << number(clip.duration)
                            << QStringLiteral("-i") << clip.path;
        } else {
            if (clip.sourceOffset > 0.0)
                m_baseArguments << QStringLiteral("-ss") << number(clip.sourceOffset);
            m_baseArguments << QStringLiteral("-i") << clip.path;
        }
    }

    QStringList filters;
    filters << QStringLiteral("color=c=black:s=%1x%2:r=%3:d=%4,format=yuv420p[base0]")
                   .arg(m_outputWidth).arg(m_outputHeight).arg(m_outputFps)
                   .arg(number(m_timelineDuration));

    QVector<Clip> visuals;
    QVector<Clip> blurEffects;
    QVector<Clip> titles;
    QVector<Clip> audioClips;
    for (const Clip &clip : clips) {
        if ((clip.kind == QStringLiteral("video") || clip.kind == QStringLiteral("image"))
                && (clip.track == 0 || clip.track == 1))
            visuals.push_back(clip);
        else if (clip.kind == QStringLiteral("text"))
            titles.push_back(clip);
        else if (clip.kind == QStringLiteral("effect") && clip.blur > 0.0)
            blurEffects.push_back(clip);
        if ((clip.kind == QStringLiteral("audio") && (clip.track == 2 || clip.track == 3))
                || (clip.kind == QStringLiteral("video") && clip.hasAudio))
            audioClips.push_back(clip);
    }

    std::stable_sort(visuals.begin(), visuals.end(), [](const Clip &a, const Clip &b) {
        if (a.track != b.track)
            return a.track > b.track;
        return a.start < b.start;
    });

    QString currentVideo = QStringLiteral("base0");
    int visualSerial = 0;
    for (const Clip &clip : visuals) {
        const int scaledWidth = qMax(2, qRound(m_outputWidth * clip.scale / 100.0) & ~1);
        const int scaledHeight = qMax(2, qRound(m_outputHeight * clip.scale / 100.0) & ~1);
        const QString label = QStringLiteral("visual%1").arg(visualSerial);
        const QString angle = number(clip.rotation * 3.14159265358979323846 / 180.0);
        QString zoomFilter;
        if (clip.reverse)
            zoomFilter = QStringLiteral("reverse,");
        if (clip.zoomMode == QStringLiteral("in") || clip.zoomMode == QStringLiteral("out")) {
            const QString amount = number(clip.zoomAmount / 100.0);
            const QString progress = QStringLiteral("min(on/(%1*%2),1)")
                                         .arg(number(clip.duration), QString::number(m_outputFps));
            const QString zoomExpression = clip.zoomMode == QStringLiteral("in")
                ? QStringLiteral("1+(%1-1)*%2").arg(amount, progress)
                : QStringLiteral("%1-(%1-1)*%2").arg(amount, progress);
            zoomFilter += QStringLiteral("fps=%1,zoompan=z='%2':x='iw/2-(iw/zoom/2)':"
                                         "y='ih/2-(ih/zoom/2)':d=1:s=%3x%4:fps=%1,")
                              .arg(m_outputFps).arg(zoomExpression).arg(scaledWidth).arg(scaledHeight);
        }
        // Blur is stored as 0..100 in the editor and converted to a bounded
        // Gaussian sigma for the final-resolution FFmpeg export.
        if (clip.blur > 0.0)
            zoomFilter += QStringLiteral("gblur=sigma=%1:steps=2,").arg(number(clip.blur * 0.24));

        // Apply transitions after reverse/zoom/blur, then multiply the fade alpha
        // by the clip's own opacity. This keeps transition direction correct for
        // reversed clips and preserves the regular opacity setting.
        QString transitionFilter;
        const double fadeIn = qMin(clip.duration, clip.transitionIn);
        const double fadeOut = qMin(clip.duration, clip.transitionOut);
        if (fadeIn > 0.001)
            transitionFilter += QStringLiteral("fade=t=in:st=0:d=%1:alpha=1,").arg(number(fadeIn));
        if (fadeOut > 0.001)
            transitionFilter += QStringLiteral("fade=t=out:st=%1:d=%2:alpha=1,")
                                    .arg(number(qMax(0.0, clip.duration - fadeOut)), number(fadeOut));

        filters << QStringLiteral("[%1:v:0]setpts=PTS-STARTPTS,"
                                 "eq=brightness=%2:contrast=%3:saturation=%4,format=rgba,"
                                 "scale=%5:%6:force_original_aspect_ratio=decrease,"
                                 "pad=%5:%6:(ow-iw)/2:(oh-ih)/2:color=black@0,"
                                 "rotate=%7:ow=rotw(iw):oh=roth(ih):c=black@0,setsar=1,"
                                 "tpad=stop_mode=clone:stop_duration=%9,trim=duration=%9,%12%13"
                                 "colorchannelmixer=aa=%8,setpts=PTS-STARTPTS+%10/TB[%11]")
                       .arg(clip.inputIndex)
                       .arg(number(clip.brightness))
                       .arg(number(1.0 + clip.contrast))
                       .arg(number(1.0 + clip.saturation))
                       .arg(scaledWidth).arg(scaledHeight).arg(angle)
                       .arg(number(clip.opacity / 100.0))
                       .arg(number(clip.duration)).arg(number(clip.start)).arg(label)
                       .arg(zoomFilter).arg(transitionFilter);

        const QString merged = QStringLiteral("mix%1").arg(visualSerial);
        filters << QStringLiteral("[%1][%2]overlay=x='(W-w)/2+%3':y='(H-h)/2+%4':"
                                 "eof_action=pass:shortest=0:repeatlast=0:enable='between(t,%5,%6)'[%7]")
                       .arg(currentVideo, label, number(clip.x), number(clip.y),
                            number(clip.start), number(clip.start + clip.duration), merged);
        currentVideo = merged;
        ++visualSerial;
    }

    std::stable_sort(blurEffects.begin(), blurEffects.end(), [](const Clip &a, const Clip &b) {
        return a.start < b.start;
    });
    int blurEffectSerial = 0;
    for (const Clip &effect : blurEffects) {
        // FX clips use a transformable rectangle centered on the project frame.
        // Keep preview and export geometry in sync: 40% of frame width by 30%
        // of frame height at 100% scale, then apply the clip's x/y/scale/rotation.
        const int regionWidth = qMax(2, qRound(m_outputWidth * 0.40 * effect.scale / 100.0));
        const int regionHeight = qMax(2, qRound(m_outputHeight * 0.30 * effect.scale / 100.0));
        const double angle = effect.rotation * 3.14159265358979323846 / 180.0;
        const double offsetX = effect.x;
        const double offsetY = effect.y;
        // The mask rotates around the full frame's center. Pre-rotate its center
        // offset so the resulting rectangle stays at the chosen X/Y.
        const double maskCenterX = m_outputWidth / 2.0
            + offsetX * std::cos(angle) + offsetY * std::sin(angle);
        const double maskCenterY = m_outputHeight / 2.0
            - offsetX * std::sin(angle) + offsetY * std::cos(angle);
        const int maskX = qRound(maskCenterX - regionWidth / 2.0);
        const int maskY = qRound(maskCenterY - regionHeight / 2.0);

        const QString base = QStringLiteral("fxbase%1").arg(blurEffectSerial);
        const QString blurInput = QStringLiteral("fxsrc%1").arg(blurEffectSerial);
        const QString blurred = QStringLiteral("fxblurred%1").arg(blurEffectSerial);
        const QString mask = QStringLiteral("fxmask%1").arg(blurEffectSerial);
        const QString masked = QStringLiteral("fxmasked%1").arg(blurEffectSerial);
        const QString merged = QStringLiteral("fxout%1").arg(blurEffectSerial);

        filters << QStringLiteral("[%1]split[%2][%3]")
                       .arg(currentVideo, base, blurInput);
        filters << QStringLiteral("[%1]gblur=sigma=%2:steps=2[%3]")
                       .arg(blurInput, number(effect.blur * 0.24), blurred);

        QString maskFilter = QStringLiteral(
            "color=c=black:s=%1x%2:r=%3:d=%4,"
            "drawbox=x=%5:y=%6:w=%7:h=%8:color=white:t=fill,format=gray")
                .arg(m_outputWidth).arg(m_outputHeight).arg(m_outputFps)
                .arg(number(m_timelineDuration)).arg(maskX).arg(maskY)
                .arg(regionWidth).arg(regionHeight);
        if (qAbs(effect.rotation) > 0.001) {
            maskFilter += QStringLiteral(",rotate=%1:ow=%2:oh=%3:c=black")
                .arg(number(angle)).arg(m_outputWidth).arg(m_outputHeight);
        }
        filters << maskFilter + QStringLiteral("[%1]").arg(mask);
        filters << QStringLiteral("[%1][%2]alphamerge[%3]")
                       .arg(blurred, mask, masked);
        filters << QStringLiteral("[%1][%2]overlay=0:0:eof_action=pass:shortest=0:"
                                  "enable='between(t,%3,%4)'[%5]")
                       .arg(base, masked, number(effect.start),
                            number(effect.start + effect.duration), merged);
        currentVideo = merged;
        ++blurEffectSerial;
    }

    std::stable_sort(titles.begin(), titles.end(), [](const Clip &a, const Clip &b) {
        return a.start < b.start;
    });
    int titleSerial = 0;
    for (const Clip &clip : titles) {
        const QString textPath = m_temporaryDirectory.filePath(
            QStringLiteral("title-%1.txt").arg(titleSerial));
        QFile textFile(textPath);
        if (!textFile.open(QIODevice::WriteOnly)) {
            emit exportFailed(QStringLiteral("Не удалось сохранить временный текстовый файл для экспорта"));
            return false;
        }
        textFile.write(clip.text.toUtf8());
        textFile.close();

        // QML preview is roughly 360 px high; scale the user-facing font size
        // to the chosen export frame so the title keeps its on-screen proportions.
        const int scaledFontSize = qMax(8, qRound(clip.fontSize * clip.scale / 100.0
                                                   * m_outputHeight / 360.0));
        const QString angle = number(clip.rotation * 3.14159265358979323846 / 180.0);
        const QString label = QStringLiteral("title%1").arg(titleSerial);
        const QString titleSource = QStringLiteral("titlesrc%1").arg(titleSerial);
        filters << QStringLiteral("color=c=black@0:s=%1x%2:r=%3:d=%4,format=rgba,"
                                 "drawtext=textfile='%5':font='%6':fontcolor=%7:fontsize=%8:borderw=3:"
                                 "bordercolor=black:x=(w-text_w)/2:y=(h-text_h)/2:alpha=%9,"
                                 "rotate=%10:ow=rotw(iw):oh=roth(ih):c=black@0,"
                                 "setpts=PTS-STARTPTS+%11/TB[%12]")
                       .arg(m_outputWidth).arg(m_outputHeight).arg(m_outputFps)
                       .arg(number(clip.duration)).arg(escapeFilterPath(textPath))
                       .arg(clip.fontFamily).arg(clip.textColor).arg(scaledFontSize)
                       .arg(number(clip.opacity / 100.0))
                       .arg(angle).arg(number(clip.start)).arg(titleSource);
        filters << QStringLiteral("[%1][%2]overlay=x='(W-w)/2+%3':y='(H-h)/2+%4':"
                                 "eof_action=pass:shortest=0:repeatlast=0:enable='between(t,%5,%6)'[%7]")
                       .arg(currentVideo, titleSource, number(clip.x), number(clip.y),
                            number(clip.start), number(clip.start + clip.duration), label);
        currentVideo = label;
        ++titleSerial;
    }
    filters << QStringLiteral("[%1]format=yuv420p[vout]").arg(currentVideo);

    QStringList audioLabels;
    int audioSerial = 0;
    for (const Clip &clip : audioClips) {
        if (clip.kind == QStringLiteral("video") && !clip.hasAudio)
            continue;
        const QString label = QStringLiteral("audio%1").arg(audioSerial);
        const int delay = qMax(0, qRound(clip.start * 1000.0));
        QStringList audioChain;
        audioChain << QStringLiteral("atrim=duration=%1").arg(number(clip.duration))
                   << QStringLiteral("asetpts=PTS-STARTPTS");
        if (clip.reverse)
            audioChain << QStringLiteral("areverse");
        audioChain << QStringLiteral("aresample=48000")
                   << QStringLiteral("aformat=sample_fmts=fltp:channel_layouts=stereo");

        static const int eqFrequencies[] = {31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};
        for (int band = 0; band < clip.equalizerBands.size() && band < 10; ++band) {
            const double gain = clip.equalizerBands.at(band);
            if (std::abs(gain) < 0.01)
                continue;
            audioChain << QStringLiteral("equalizer=f=%1:t=o:w=1:g=%2")
                              .arg(eqFrequencies[band]).arg(number(gain));
        }
        if (clip.audioDenoise)
            audioChain << QStringLiteral("afftdn=nf=-25");
        if (clip.audioCompressor)
            audioChain << QStringLiteral("acompressor=threshold=0.125:ratio=3:attack=20:release=250");
        if (clip.audioNormalize)
            audioChain << QStringLiteral("loudnorm=I=-16:TP=-1.5:LRA=11");

        if (std::abs(clip.audioPan) > 0.01) {
            const double pan = clip.audioPan / 100.0;
            const double leftGain = pan > 0.0 ? 1.0 - pan : 1.0;
            const double rightGain = pan < 0.0 ? 1.0 + pan : 1.0;
            audioChain << QStringLiteral("pan=stereo|c0=%1*FL|c1=%2*FR")
                              .arg(number(leftGain), number(rightGain));
        }

        audioChain << QStringLiteral("volume=%1").arg(number(clip.audioMuted ? 0.0 : clip.volume / 100.0));
        const double fadeIn = qMin(clip.duration, clip.audioFadeIn);
        const double fadeOut = qMin(clip.duration, clip.audioFadeOut);
        if (fadeIn > 0.001)
            audioChain << QStringLiteral("afade=t=in:st=0:d=%1").arg(number(fadeIn));
        if (fadeOut > 0.001)
            audioChain << QStringLiteral("afade=t=out:st=%1:d=%2")
                              .arg(number(qMax(0.0, clip.duration - fadeOut)), number(fadeOut));
        if (clip.audioLimiter)
            audioChain << QStringLiteral("alimiter=limit=0.95");

        filters << QStringLiteral("[%1:a:0]%2,adelay=%3|%3[%4]")
                       .arg(clip.inputIndex)
                       .arg(audioChain.join(QLatin1Char(',')))
                       .arg(delay)
                       .arg(label);
        audioLabels << QStringLiteral("[%1]").arg(label);
        ++audioSerial;
    }

    if (audioLabels.isEmpty()) {
        filters << QStringLiteral("anullsrc=r=48000:cl=stereo,atrim=duration=%1[aout]")
                       .arg(number(m_timelineDuration));
    } else if (audioLabels.size() == 1) {
        filters << QStringLiteral("%1apad,atrim=duration=%2[aout]")
                       .arg(audioLabels.front()).arg(number(m_timelineDuration));
    } else {
        filters << QStringLiteral("%1amix=inputs=%2:duration=longest:dropout_transition=0:normalize=0,"
                                 "apad,atrim=duration=%3[aout]")
                       .arg(audioLabels.join(QString()))
                       .arg(audioLabels.size())
                       .arg(number(m_timelineDuration));
    }

    m_filterGraph = filters.join(QLatin1Char(';'));
    m_baseArguments << QStringLiteral("-filter_complex") << m_filterGraph
                    << QStringLiteral("-map") << QStringLiteral("[vout]")
                    << QStringLiteral("-map") << QStringLiteral("[aout]")
                    << QStringLiteral("-r") << QString::number(m_outputFps)
                    << QStringLiteral("-pix_fmt") << QStringLiteral("yuv420p")
                    << QStringLiteral("-t") << number(m_timelineDuration)
                    << QStringLiteral("-c:a") << QStringLiteral("aac")
                    << QStringLiteral("-b:a") << QStringLiteral("192k")
                    << QStringLiteral("-movflags") << QStringLiteral("+faststart");

    m_fallbackTried = false;
    m_processErrorHandled = false;
    setProgress(0.0);
    setRunning(true);
    startAttempt(true);
    return true;
}

void ExportController::startAttempt(bool useGpuEncoder)
{
    m_usingGpuEncoder = useGpuEncoder;
    m_lastError.clear();
    m_processErrorHandled = false;
    QFile::remove(m_outputPath);

    QStringList arguments = m_baseArguments;
    arguments.append(encoderArguments(useGpuEncoder));
    arguments << m_outputPath;

    emit statusChanged(useGpuEncoder
        ? QStringLiteral("Экспорт через NVIDIA NVENC…")
        : QStringLiteral("Экспорт через CPU (libx264)…"));

    m_process.setProgram(QStringLiteral("ffmpeg"));
    m_process.setArguments(arguments);
    m_process.start();
}

void ExportController::readProgressOutput()
{
    const QString output = QString::fromUtf8(m_process.readAllStandardOutput());
    const QStringList lines = output.split(QLatin1Char('\n'));
    for (const QString &line : lines) {
        if (!line.startsWith(QStringLiteral("out_time=")))
            continue;
        const QString value = line.mid(9).trimmed();
        const QStringList parts = value.split(QLatin1Char(':'));
        if (parts.size() != 3)
            continue;
        bool hoursOk = false;
        bool minutesOk = false;
        bool secondsOk = false;
        const double hours = parts[0].toDouble(&hoursOk);
        const double minutes = parts[1].toDouble(&minutesOk);
        const double seconds = parts[2].toDouble(&secondsOk);
        if (!hoursOk || !minutesOk || !secondsOk)
            continue;
        const double current = hours * 3600.0 + minutes * 60.0 + seconds;
        if (m_timelineDuration > 0.0)
            setProgress(qBound(0.0, current / m_timelineDuration, 0.99));
    }
}

void ExportController::handleFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (!m_running || m_processErrorHandled)
        return;
    if (exitStatus == QProcess::NormalExit && exitCode == 0
            && QFileInfo::exists(m_outputPath) && QFileInfo(m_outputPath).size() > 0) {
        setProgress(1.0);
        setRunning(false);
        emit statusChanged(QStringLiteral("Экспорт завершён"));
        emit exportFinished(QUrl::fromLocalFile(m_outputPath).toString(), m_usingGpuEncoder);
        return;
    }

    if (m_usingGpuEncoder && !m_fallbackTried) {
        m_fallbackTried = true;
        emit statusChanged(QStringLiteral("NVENC не сработал — повторяю экспорт через CPU"));
        startAttempt(false);
        return;
    }

    setRunning(false);
    QString message = m_lastError.trimmed();
    if (message.isEmpty())
        message = QStringLiteral("FFmpeg завершился с кодом %1").arg(exitCode);
    emit exportFailed(message);
}

void ExportController::handleProcessError(QProcess::ProcessError error)
{
    if (error != QProcess::FailedToStart || !m_running || m_processErrorHandled)
        return;
    m_processErrorHandled = true;
    if (m_usingGpuEncoder && !m_fallbackTried) {
        m_fallbackTried = true;
        m_processErrorHandled = false;
        emit statusChanged(QStringLiteral("Не удалось запустить NVENC-экспорт — пробую CPU"));
        startAttempt(false);
        return;
    }
    setRunning(false);
    emit exportFailed(QStringLiteral("Не удалось запустить ffmpeg. Установи пакет ffmpeg."));
}

void ExportController::setRunning(bool running)
{
    if (m_running == running)
        return;
    m_running = running;
    emit runningChanged();
}

void ExportController::setProgress(double progress)
{
    const double bounded = qBound(0.0, progress, 1.0);
    if (qFuzzyCompare(m_progress + 1.0, bounded + 1.0))
        return;
    m_progress = bounded;
    emit progressChanged();
}

void ExportController::cancel()
{
    if (!m_running)
        return;
    m_processErrorHandled = true;
    m_process.kill();
    m_process.waitForFinished(1000);
    setRunning(false);
    emit statusChanged(QStringLiteral("Экспорт отменён"));
}
