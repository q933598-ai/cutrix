#include "MediaTools.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMetaObject>
#include <QPointer>
#include <QProcess>
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
