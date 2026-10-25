#include "MediaTools.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMetaObject>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QMutexLocker>
#include <QRunnable>
#include <QStandardPaths>
#include <QTextStream>
#include <QUrl>
#include <cmath>

namespace {
QString localPath(const QString &value)
{
    const QUrl url(value);
    return url.isLocalFile() ? url.toLocalFile() : value;
}

QString runTool(const QString &program, const QStringList &args, int timeoutMs = 5000)
{
    QProcess process;
    process.start(program, args);
    if (!process.waitForStarted(1000)) return {};
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished();
        return {};
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
        return {};
    return QString::fromUtf8(process.readAllStandardOutput()).trimmed();
}
}

MediaTools::MediaTools(QObject *parent) : QObject(parent)
{
    m_thumbnailPool.setMaxThreadCount(2);
    m_thumbnailPool.setExpiryTimeout(30000);
    connect(&m_transcriptionProcess, &QProcess::finished, this,
            [this](int exitCode, QProcess::ExitStatus status) {
        handleTranscriptionFinished(exitCode, status);
    });
    connect(&m_transcriptionProcess, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart && m_transcriptionRunning)
            failTranscription(QStringLiteral("Не удалось запустить Whisper. Проверь установку whisper-cli."));
    });
    connect(&m_reversePreviewProcess, &QProcess::finished, this,
            [this](int exitCode, QProcess::ExitStatus status) {
        handleReversePreviewFinished(exitCode, status);
    });
    connect(&m_reversePreviewProcess, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart && m_reversePreviewRunning)
            failReversePreview(QStringLiteral("Не удалось запустить FFmpeg для реверса."));
    });
}

QVariantMap MediaTools::inspect(const QString &url) const
{
    const QString path = localPath(url);
    const QFileInfo info(path);
    QVariantMap result;
    result.insert("exists", info.exists() && info.isFile());
    result.insert("size", info.exists() ? info.size() : 0);
    result.insert("kind", "unknown");
    result.insert("duration", 0.0);
    if (!info.exists() || !info.isFile()) return result;

    const QString probeOutput = runTool("ffprobe", {
        "-v", "error", "-show_entries", "format=duration:stream=codec_type",
        "-of", "default=noprint_wrappers=1", path
    }, 12000);
    bool durationOk = false;
    bool hasVideo = false;
    bool hasAudio = false;
    bool sawStreamType = false;
    double duration = 0.0;
    const QStringList probeLines = probeOutput.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &line : probeLines) {
        if (line == QStringLiteral("codec_type=video")) {
            hasVideo = true;
            sawStreamType = true;
        } else if (line == QStringLiteral("codec_type=audio")) {
            hasAudio = true;
            sawStreamType = true;
        } else if (line.startsWith(QStringLiteral("duration="))) {
            duration = line.mid(QStringLiteral("duration=").size()).toDouble(&durationOk);
        }
    }
    if (durationOk && std::isfinite(duration) && duration >= 0.0)
        result.insert("duration", duration);
    // Do not mark a video as silent when ffprobe was unavailable or failed.
    // Only publish hasAudio when stream information was actually read.
    if (sawStreamType)
        result.insert("hasAudio", hasAudio);

    const QString suffix = info.suffix().toLower();
    if (QStringList{"png","jpg","jpeg","webp","bmp","gif","tif","tiff"}.contains(suffix))
        result.insert("kind", "image");
    else if (hasVideo)
        result.insert("kind", "video");
    else if (hasAudio)
        result.insert("kind", "audio");
    return result;
}

QString MediaTools::thumbnail(const QString &url)
{
    return thumbnailAt(url, 1.0);
}

QString MediaTools::thumbnailAt(const QString &url, double seconds)
{
    return thumbnailAtSize(url, seconds, 160);
}

QString MediaTools::previewFrameAt(const QString &url, double seconds)
{
    return thumbnailAtSize(url, seconds, 1280);
}

QString MediaTools::thumbnailAtSize(const QString &url, double seconds, int maxWidth)
{
    const QString path = localPath(url);
    const QFileInfo info(path);
    if (!info.exists() || !info.isFile()) return {};
    const QString suffix = info.suffix().toLower();
    if (QStringList{"png","jpg","jpeg","webp","bmp","gif","tif","tiff"}.contains(suffix))
        return QUrl::fromLocalFile(path).toString();

    const double safeSeconds = qMax(0.0, seconds);
    const QString cacheRoot = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (cacheRoot.isEmpty()) return {};
    const QString cacheDir = cacheRoot + "/media-thumbnails";
    if (!QDir().mkpath(cacheDir)) return {};
    const QByteArray keyBytes = QCryptographicHash::hash(
        (QStringLiteral("cutrix-preview-v3|") + QString::number(maxWidth)
         + "|" + info.absoluteFilePath()
         + "|" + QString::number(info.lastModified().toSecsSinceEpoch())
         + "|" + QString::number(safeSeconds, 'f', 2))
            .toUtf8(), QCryptographicHash::Sha256).toHex();
    const QString key = QString::fromLatin1(keyBytes);
    const QString output = cacheDir + "/" + key + ".jpg";
    if (QFileInfo::exists(output) && QFileInfo(output).size() > 0)
        return QUrl::fromLocalFile(output).toString();

    // Never wait for ffmpeg from a QML property binding: that blocks the GUI
    // thread and can freeze both timeline interaction and video presentation.
    {
        QMutexLocker lock(&m_thumbnailMutex);
        if (m_pendingThumbnails.contains(key) || m_failedThumbnails.contains(key))
            return {};
        m_pendingThumbnails.insert(key);
    }

    const QString seek = QString::number(safeSeconds, 'f', 2);
    QPointer<MediaTools> guardedThis(this);
    m_thumbnailPool.start(QRunnable::create([guardedThis, path, output, key, seek, maxWidth]() {
        QFile::remove(output);
        runTool("ffmpeg", {
            "-hide_banner", "-loglevel", "error", "-threads", "1",
            "-ss", seek, "-i", path, "-frames:v", "1",
            "-vf", QStringLiteral("scale=%1:%2:force_original_aspect_ratio=decrease")
                .arg(maxWidth).arg(maxWidth * 9 / 16),
            "-q:v", "2", "-y", output
        }, 15000);

        const bool succeeded = QFileInfo::exists(output) && QFileInfo(output).size() > 0;
        if (!succeeded) QFile::remove(output);
        if (!guardedThis) return;

        QMetaObject::invokeMethod(guardedThis.data(), [guardedThis, key, succeeded]() {
            if (!guardedThis) return;
            {
                QMutexLocker lock(&guardedThis->m_thumbnailMutex);
                guardedThis->m_pendingThumbnails.remove(key);
                if (!succeeded)
                    guardedThis->m_failedThumbnails.insert(key);
            }
            if (succeeded) {
                ++guardedThis->m_thumbnailRevision;
                emit guardedThis->thumbnailRevisionChanged();
            }
        }, Qt::QueuedConnection);
    }));
    return {};
}


QString MediaTools::prepareReversePreview(const QString &mediaUrl, double sourceOffset,
                                          double duration, const QString &clipId)
{
    if (m_reversePreviewRunning)
        return QStringLiteral("busy");

    const QString inputPath = localPath(mediaUrl);
    const QFileInfo inputInfo(inputPath);
    if (!inputInfo.isFile())
        return QStringLiteral("error:Исходный видеофайл не найден.");
    if (!std::isfinite(sourceOffset) || sourceOffset < 0.0
            || !std::isfinite(duration) || duration <= 0.0)
        return QStringLiteral("error:Не удалось определить отрезок видео для реверса.");

    m_reversePreviewFfmpeg = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    if (m_reversePreviewFfmpeg.isEmpty())
        return QStringLiteral("error:Не найден FFmpeg.");

    const QString cacheRoot = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    const QString cacheDir = cacheRoot + QStringLiteral("/reverse-previews");
    if (cacheRoot.isEmpty() || !QDir().mkpath(cacheDir))
        return QStringLiteral("error:Не удалось создать кэш предпросмотра реверса.");

    const QByteArray key = QCryptographicHash::hash(
        (inputInfo.absoluteFilePath() + QLatin1Char('|')
         + QString::number(inputInfo.size()) + QLatin1Char('|')
         + QString::number(inputInfo.lastModified().toSecsSinceEpoch()) + QLatin1Char('|')
         + QString::number(sourceOffset, 'f', 3) + QLatin1Char('|')
         + QString::number(duration, 'f', 3)
         + QStringLiteral("|cutrix-reverse-preview-v1|960|24|x264-ultrafast"))
            .toUtf8(), QCryptographicHash::Sha256).toHex();
    const QString stem = cacheDir + QLatin1Char('/') + QString::fromLatin1(key);
    const QString outputPath = stem + QStringLiteral(".mp4");
    if (QFileInfo::exists(outputPath) && QFileInfo(outputPath).size() > 0)
        return QUrl::fromLocalFile(outputPath).toString();

    m_reversePreviewClipId = clipId;
    m_reversePreviewSourcePath = inputInfo.absoluteFilePath();
    m_reversePreviewOutputPath = outputPath;
    m_reversePreviewListPath = stem + QStringLiteral("-concat.txt");
    m_reversePreviewSourceOffset = sourceOffset;
    m_reversePreviewDuration = duration;
    m_reversePreviewChunkIndex = 0;
    // Reverse in small, independently encoded segments. FFmpeg's reverse
    // filter buffers each segment in RAM, so never buffer the entire source clip.
    constexpr double chunkSeconds = 8.0;
    m_reversePreviewChunkCount = qMax(1, static_cast<int>(std::ceil(duration / chunkSeconds)));
    m_reversePreviewChunkPaths.clear();
    QFile::remove(outputPath);
    QFile::remove(m_reversePreviewListPath);
    for (int i = 0; i < m_reversePreviewChunkCount; ++i) {
        QFile::remove(stem + QStringLiteral("-chunk-%1.mp4").arg(i, 5, 10, QLatin1Char('0')));
    }

    setReversePreviewRunning(true);
    startReversePreviewChunk();
    return QStringLiteral("pending");
}

void MediaTools::setReversePreviewRunning(bool running)
{
    if (m_reversePreviewRunning == running)
        return;
    m_reversePreviewRunning = running;
    emit reversePreviewRunningChanged();
}

void MediaTools::startReversePreviewChunk()
{
    if (!m_reversePreviewRunning)
        return;

    if (m_reversePreviewChunkIndex >= m_reversePreviewChunkCount) {
        startReversePreviewConcat();
        return;
    }

    constexpr double chunkSeconds = 8.0;
    // Process chunks from the end towards the start; reversing each chunk and
    // concatenating in this order yields a continuous reverse-playback proxy.
    const double segmentEnd = m_reversePreviewDuration
        - m_reversePreviewChunkIndex * chunkSeconds;
    const double segmentStart = qMax(0.0, segmentEnd - chunkSeconds);
    const double segmentDuration = segmentEnd - segmentStart;
    const double inputSeek = m_reversePreviewSourceOffset + segmentStart;
    const QFileInfo outputInfo(m_reversePreviewOutputPath);
    const QString stem = outputInfo.absolutePath() + QLatin1Char('/')
        + outputInfo.completeBaseName();
    const QString chunkPath = stem + QStringLiteral("-chunk-%1.mp4")
        .arg(m_reversePreviewChunkIndex, 5, 10, QLatin1Char('0'));
    QFile::remove(chunkPath);
    m_reversePreviewStage = QStringLiteral("chunk");

    m_reversePreviewProcess.setProgram(m_reversePreviewFfmpeg);
    m_reversePreviewProcess.setArguments({
        QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-y"), QStringLiteral("-threads"), QStringLiteral("2"),
        QStringLiteral("-ss"), QString::number(inputSeek, 'f', 3),
        QStringLiteral("-t"), QString::number(segmentDuration, 'f', 3),
        QStringLiteral("-i"), m_reversePreviewSourcePath,
        QStringLiteral("-an"),
        QStringLiteral("-vf"),
        QStringLiteral("scale='min(960\\,iw)':-2,fps=24,reverse,setpts=PTS-STARTPTS"),
        QStringLiteral("-c:v"), QStringLiteral("libx264"),
        QStringLiteral("-preset"), QStringLiteral("ultrafast"),
        QStringLiteral("-crf"), QStringLiteral("25"),
        QStringLiteral("-pix_fmt"), QStringLiteral("yuv420p"),
        QStringLiteral("-movflags"), QStringLiteral("+faststart"),
        chunkPath
    });
    m_reversePreviewProcess.start();
}

void MediaTools::startReversePreviewConcat()
{
    QFile listFile(m_reversePreviewListPath);
    if (!listFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        failReversePreview(QStringLiteral("Не удалось создать список сегментов реверса."));
        return;
    }
    QTextStream stream(&listFile);
    for (const QString &path : std::as_const(m_reversePreviewChunkPaths)) {
        QString escaped = path;
        escaped.replace(QStringLiteral("\\"), QStringLiteral("\\\\"));
        escaped.replace(QStringLiteral("'"), QStringLiteral("\\'"));
        stream << QStringLiteral("file '") << escaped << QStringLiteral("'\n");
    }
    listFile.close();

    m_reversePreviewStage = QStringLiteral("concat");
    m_reversePreviewProcess.setProgram(m_reversePreviewFfmpeg);
    m_reversePreviewProcess.setArguments({
        QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-y"), QStringLiteral("-f"), QStringLiteral("concat"),
        QStringLiteral("-safe"), QStringLiteral("0"),
        QStringLiteral("-i"), m_reversePreviewListPath,
        QStringLiteral("-c"), QStringLiteral("copy"),
        QStringLiteral("-movflags"), QStringLiteral("+faststart"),
        m_reversePreviewOutputPath
    });
    m_reversePreviewProcess.start();
}

void MediaTools::handleReversePreviewFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_reversePreviewRunning)
        return;

    const QString details = QString::fromLocal8Bit(
        m_reversePreviewProcess.readAllStandardError()).trimmed();
    if (status != QProcess::NormalExit || exitCode != 0) {
        failReversePreview(details.isEmpty()
            ? QStringLiteral("FFmpeg не смог подготовить предпросмотр реверса.")
            : details.left(400));
        return;
    }

    if (m_reversePreviewStage == QStringLiteral("chunk")) {
        const QFileInfo outputInfo(m_reversePreviewOutputPath);
        const QString stem = outputInfo.absolutePath() + QLatin1Char('/')
            + outputInfo.completeBaseName();
        const QString chunkPath = stem + QStringLiteral("-chunk-%1.mp4")
            .arg(m_reversePreviewChunkIndex, 5, 10, QLatin1Char('0'));
        if (!QFileInfo::exists(chunkPath) || QFileInfo(chunkPath).size() == 0) {
            failReversePreview(QStringLiteral("FFmpeg создал пустой сегмент реверса."));
            return;
        }
        m_reversePreviewChunkPaths.push_back(chunkPath);
        ++m_reversePreviewChunkIndex;
        startReversePreviewChunk();
        return;
    }

    if (m_reversePreviewStage == QStringLiteral("concat")) {
        if (!QFileInfo::exists(m_reversePreviewOutputPath)
                || QFileInfo(m_reversePreviewOutputPath).size() == 0) {
            failReversePreview(QStringLiteral("Не удалось собрать предпросмотр реверса."));
            return;
        }

        const QString clipId = m_reversePreviewClipId;
        const QString previewUrl = QUrl::fromLocalFile(m_reversePreviewOutputPath).toString();
        QFile::remove(m_reversePreviewListPath);
        for (const QString &path : std::as_const(m_reversePreviewChunkPaths))
            QFile::remove(path);
        m_reversePreviewChunkPaths.clear();
        m_reversePreviewStage.clear();
        setReversePreviewRunning(false);
        emit reversePreviewReady(clipId, previewUrl);
        m_reversePreviewClipId.clear();
        return;
    }

    failReversePreview(QStringLiteral("Неизвестное состояние предпросмотра реверса."));
}

void MediaTools::failReversePreview(const QString &message)
{
    if (!m_reversePreviewRunning)
        return;
    const QString clipId = m_reversePreviewClipId;
    QFile::remove(m_reversePreviewOutputPath);
    QFile::remove(m_reversePreviewListPath);
    const QFileInfo outputInfo(m_reversePreviewOutputPath);
    const QString stem = outputInfo.absolutePath() + QLatin1Char('/')
        + outputInfo.completeBaseName();
    for (int i = 0; i < m_reversePreviewChunkCount; ++i)
        QFile::remove(stem + QStringLiteral("-chunk-%1.mp4").arg(i, 5, 10, QLatin1Char('0')));
    m_reversePreviewChunkPaths.clear();
    m_reversePreviewStage.clear();
    setReversePreviewRunning(false);
    emit reversePreviewFailed(clipId, message);
    m_reversePreviewClipId.clear();
}


void MediaTools::setTranscriptionRunning(bool running)
{
    if (m_transcriptionRunning == running) return;
    m_transcriptionRunning = running;
    emit transcriptionRunningChanged();
}

void MediaTools::failTranscription(const QString &message)
{
    m_transcriptionStage.clear();
    setTranscriptionRunning(false);
    emit transcriptionFailed(message);
}

bool MediaTools::startTranscription(const QString &mediaUrl, const QString &modelPath,
                                    double sourceOffset, double duration)
{
    if (m_transcriptionRunning) {
        emit transcriptionFailed(QStringLiteral("Распознавание уже выполняется."));
        return false;
    }

    const QString ffmpeg = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    m_whisperExecutable = QStandardPaths::findExecutable(QStringLiteral("whisper-cli"));
    if (m_whisperExecutable.isEmpty()) {
        emit transcriptionFailed(QStringLiteral("Не найден whisper-cli. Установи whisper.cpp и повтори попытку."));
        return false;
    }
    if (ffmpeg.isEmpty()) {
        emit transcriptionFailed(QStringLiteral("Для подготовки аудио нужен FFmpeg (команда ffmpeg)."));
        return false;
    }

    const QString inputPath = localPath(mediaUrl);
    const QString resolvedModelPath = localPath(modelPath);
    if (!QFileInfo(inputPath).isFile()) {
        emit transcriptionFailed(QStringLiteral("Исходный аудио- или видеофайл не найден."));
        return false;
    }
    if (!QFileInfo(resolvedModelPath).isFile()) {
        emit transcriptionFailed(QStringLiteral("Файл модели Whisper не найден. Выбери модель .bin."));
        return false;
    }
    if (!std::isfinite(sourceOffset) || sourceOffset < 0.0
            || !std::isfinite(duration) || duration <= 0.0) {
        emit transcriptionFailed(QStringLiteral("Не удалось определить длительность выбранного клипа."));
        return false;
    }

    const QString cacheRoot = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    const QString cacheDir = cacheRoot + QStringLiteral("/transcription");
    if (cacheRoot.isEmpty() || !QDir().mkpath(cacheDir)) {
        emit transcriptionFailed(QStringLiteral("Не удалось создать папку для временного аудио."));
        return false;
    }

    const QFileInfo inputInfo(inputPath);
    const QByteArray cacheKey = QCryptographicHash::hash(
        (inputInfo.absoluteFilePath() + QLatin1Char('|')
         + QString::number(inputInfo.lastModified().toSecsSinceEpoch()) + QLatin1Char('|')
         + QString::number(sourceOffset, 'f', 3) + QLatin1Char('|')
         + QString::number(duration, 'f', 3) + QLatin1Char('|')
         + resolvedModelPath).toUtf8(), QCryptographicHash::Sha256).toHex();
    const QString stem = cacheDir + QLatin1Char('/') + QString::fromLatin1(cacheKey);
    m_transcriptionWavPath = stem + QStringLiteral(".wav");
    m_transcriptionSrtPath = stem + QStringLiteral(".srt");
    QFile::remove(m_transcriptionWavPath);
    QFile::remove(m_transcriptionSrtPath);
    m_transcriptionModelPath = resolvedModelPath;
    m_transcriptionPrefix = stem;
    m_transcriptionStage = QStringLiteral("extract");
    m_transcriptionFfmpeg = ffmpeg;
    m_transcriptionSourceOffset = sourceOffset;
    m_transcriptionDuration = duration;

    m_transcriptionProcess.setProgram(ffmpeg);
    m_transcriptionProcess.setArguments({
        QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-y"), QStringLiteral("-ss"), QString::number(sourceOffset, 'f', 3),
        QStringLiteral("-i"), inputPath, QStringLiteral("-t"), QString::number(duration, 'f', 3),
        QStringLiteral("-vn"), QStringLiteral("-ac"), QStringLiteral("1"),
        QStringLiteral("-ar"), QStringLiteral("16000"), QStringLiteral("-c:a"),
        QStringLiteral("pcm_s16le"), m_transcriptionWavPath
    });
    setTranscriptionRunning(true);
    m_transcriptionProcess.start();
    return true;
}

void MediaTools::handleTranscriptionFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_transcriptionRunning) return;
    if (status != QProcess::NormalExit || exitCode != 0) {
        const QString details = QString::fromLocal8Bit(m_transcriptionProcess.readAllStandardError()).trimmed();
        failTranscription(details.isEmpty()
            ? QStringLiteral("Не удалось обработать аудио. Проверь FFmpeg и формат файла.")
            : QStringLiteral("Ошибка распознавания: ") + details.left(500));
        return;
    }

    if (m_transcriptionStage == QStringLiteral("extract")) {
        if (!QFileInfo::exists(m_transcriptionWavPath)
                || QFileInfo(m_transcriptionWavPath).size() <= 44) {
            failTranscription(QStringLiteral("В выбранном фрагменте не удалось извлечь аудио."));
            return;
        }
        startWhisperProcess();
        return;
    }

    if (m_transcriptionStage == QStringLiteral("recognize")) {
        parseTranscriptionResult();
        return;
    }

    failTranscription(QStringLiteral("Неизвестное состояние распознавания."));
}

void MediaTools::startWhisperProcess()
{
    m_transcriptionStage = QStringLiteral("recognize");
    QFile::remove(m_transcriptionSrtPath);
    m_transcriptionProcess.setProgram(m_whisperExecutable);
    m_transcriptionProcess.setArguments({
        QStringLiteral("-m"), m_transcriptionModelPath,
        QStringLiteral("-f"), m_transcriptionWavPath,
        QStringLiteral("-osrt"),
        QStringLiteral("-of"), m_transcriptionPrefix
    });
    m_transcriptionProcess.start();
}

void MediaTools::parseTranscriptionResult()
{
    QFile file(m_transcriptionSrtPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        failTranscription(QStringLiteral("Whisper завершился без SRT-файла. Проверь выбранную модель."));
        return;
    }
    const QString contents = QString::fromUtf8(file.readAll());
    file.close();

    const QRegularExpression blockSeparator(QStringLiteral("\\r?\\n\\s*\\r?\\n"));
    const QRegularExpression timestamp(
        QStringLiteral(R"((\d{2,}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2,}):(\d{2}):(\d{2})[,.](\d{3}))"));
    const QRegularExpression tags(QStringLiteral("<[^>]*>"));
    QVariantList segments;
    const QStringList blocks = contents.split(blockSeparator, Qt::SkipEmptyParts);

    auto toSeconds = [](const QRegularExpressionMatch &match, int offset) {
        return match.captured(offset).toDouble() * 3600.0
            + match.captured(offset + 1).toDouble() * 60.0
            + match.captured(offset + 2).toDouble()
            + match.captured(offset + 3).toDouble() / 1000.0;
    };

    for (const QString &block : blocks) {
        const QStringList lines = block.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        int timestampLine = -1;
        QRegularExpressionMatch match;
        for (int i = 0; i < lines.size(); ++i) {
            const auto candidate = timestamp.match(lines.at(i).trimmed());
            if (candidate.hasMatch()) {
                timestampLine = i;
                match = candidate;
                break;
            }
        }
        if (timestampLine < 0) continue;
        QStringList textLines;
        for (int i = timestampLine + 1; i < lines.size(); ++i) {
            QString line = lines.at(i).trimmed();
            line.remove(tags);
            if (!line.isEmpty()) textLines.push_back(line);
        }
        const QString text = textLines.join(QLatin1Char(' ')).simplified();
        const double start = toSeconds(match, 1);
        const double end = toSeconds(match, 5);
        if (text.isEmpty() || !std::isfinite(start) || !std::isfinite(end) || end <= start)
            continue;
        QVariantMap item;
        item.insert(QStringLiteral("start"), start);
        item.insert(QStringLiteral("end"), end);
        item.insert(QStringLiteral("text"), text);
        segments.push_back(item);
    }

    QFile::remove(m_transcriptionWavPath);
    if (segments.isEmpty()) {
        failTranscription(QStringLiteral("Whisper не распознал речь в выбранном клипе."));
        return;
    }
    m_transcriptionStage.clear();
    setTranscriptionRunning(false);
    emit transcriptionFinished(segments);
}
