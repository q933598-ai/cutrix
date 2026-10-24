#pragma once

#include <QObject>
#include <QVariantMap>
#include <QString>
#include <QMutex>
#include <QSet>
#include <QThreadPool>

class MediaTools final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int thumbnailRevision READ thumbnailRevision NOTIFY thumbnailRevisionChanged)

public:
    explicit MediaTools(QObject *parent = nullptr);

    int thumbnailRevision() const { return m_thumbnailRevision; }

    Q_INVOKABLE QVariantMap inspect(const QString &url) const;
    Q_INVOKABLE QString thumbnail(const QString &url);
    Q_INVOKABLE QString thumbnailAt(const QString &url, double seconds);
    Q_INVOKABLE QString previewFrameAt(const QString &url, double seconds);

signals:
    void thumbnailRevisionChanged();

private:
    QString thumbnailAtSize(const QString &url, double seconds, int maxWidth);
    mutable QMutex m_thumbnailMutex;
    QSet<QString> m_pendingThumbnails;
    QSet<QString> m_failedThumbnails;
    int m_thumbnailRevision = 0;
    // Limit background ffmpeg thumbnail jobs so importing many clips does not
    // saturate every CPU core while the editor is open.
    QThreadPool m_thumbnailPool;
};
