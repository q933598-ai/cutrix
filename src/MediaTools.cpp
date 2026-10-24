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

    const QRegularExpression blockSeparator(QStringLiteral("\\\\r?\\\\n\\\\s*\\\\r?\\\\n"));
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
