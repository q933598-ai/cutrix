#include "MediaTools.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>

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

MediaTools::MediaTools(QObject *parent) : QObject(parent) {}

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

    const QString output = runTool("ffprobe", {
        "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", path
    });
    bool ok = false;
    const double duration = output.toDouble(&ok);
    if (ok && duration >= 0) result.insert("duration", duration);

    const QString streams = runTool("ffprobe", {
        "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=codec_type", "-of", "csv=p=0", path
    });
    const QString suffix = info.suffix().toLower();
    if (QStringList{"png","jpg","jpeg","webp","bmp","gif","tif","tiff"}.contains(suffix))
        result.insert("kind", "image");
    else if (!streams.isEmpty())
        result.insert("kind", "video");
    else if (ok)
        result.insert("kind", "audio");
    return result;
}

QString MediaTools::thumbnail(const QString &url) const
{
    return thumbnailAt(url, 1.0);
}

QString MediaTools::thumbnailAt(const QString &url, double seconds) const
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
    const QByteArray key = QCryptographicHash::hash(
        (info.absoluteFilePath() + "|" + QString::number(info.lastModified().toSecsSinceEpoch())
         + "|" + QString::number(safeSeconds, 'f', 2))
            .toUtf8(), QCryptographicHash::Sha256).toHex();
    const QString output = cacheDir + "/" + QString::fromLatin1(key) + ".jpg";
    if (QFileInfo::exists(output)) return QUrl::fromLocalFile(output).toString();

    const QString seek = QString::number(safeSeconds, 'f', 2);
    const QString generated = runTool("ffmpeg", {
        "-hide_banner", "-loglevel", "error", "-ss", seek, "-i", path,
        "-frames:v", "1", "-vf", "scale=160:90:force_original_aspect_ratio=decrease",
        "-y", output
    }, 15000);
    Q_UNUSED(generated);
    if (QFileInfo::exists(output) && QFileInfo(output).size() > 0)
        return QUrl::fromLocalFile(output).toString();
    QFile::remove(output);
    return {};
}
