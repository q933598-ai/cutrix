#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QMutex>
#include <QSet>
#include <QThreadPool>

class MediaTools final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int thumbnailRevision READ thumbnailRevision NOTIFY thumbnailRevisionChanged)
    Q_PROPERTY(bool transcriptionRunning READ transcriptionRunning NOTIFY transcriptionRunningChanged)

public:
    explicit MediaTools(QObject *parent = nullptr);

    int thumbnailRevision() const { return m_thumbnailRevision; }
    bool transcriptionRunning() const { return m_transcriptionRunning; }

    Q_INVOKABLE bool startTranscription(const QString &mediaUrl, const QString &modelPath,
                                        double sourceOffset, double duration);

    Q_INVOKABLE QVariantMap inspect(const QString &url) const;
    Q_INVOKABLE QString thumbnail(const QString &url);
    Q_INVOKABLE QString thumbnailAt(const QString &url, double seconds);
    Q_INVOKABLE QString previewFrameAt(const QString &url, double seconds);

signals:
    void thumbnailRevisionChanged();
    void transcriptionRunningChanged();
    void transcriptionFinished(const QVariantList &segments);
    void transcriptionFailed(const QString &message);

private:
    QString thumbnailAtSize(const QString &url, double seconds, int maxWidth);
    mutable QMutex m_thumbnailMutex;
    QSet<QString> m_pendingThumbnails;
    QSet<QString> m_failedThumbnails;
    int m_thumbnailRevision = 0;
    // Limit background ffmpeg thumbnail jobs so importing many clips does not
    // saturate every CPU core while the editor is open.
    QThreadPool m_thumbnailPool;
    QProcess m_transcriptionProcess;
    bool m_transcriptionRunning = false;
    QString m_transcriptionStage;
    QString m_transcriptionWavPath;
    QString m_transcriptionSrtPath;
    QString m_transcriptionPrefix;
    QString m_transcriptionModelPath;
    QString m_transcriptionFfmpeg;
    double m_transcriptionSourceOffset = 0.0;
    double m_transcriptionDuration = 0.0;
    QString m_whisperExecutable;
    void setTranscriptionRunning(bool running);
    void failTranscription(const QString &message);
    void handleTranscriptionFinished(int exitCode, QProcess::ExitStatus status);
    void startWhisperProcess();
    void parseTranscriptionResult();
};
