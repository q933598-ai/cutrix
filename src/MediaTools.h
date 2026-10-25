#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QStringList>
#include <QMutex>
#include <QSet>
#include <QThreadPool>

class MediaTools final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int thumbnailRevision READ thumbnailRevision NOTIFY thumbnailRevisionChanged)
    Q_PROPERTY(bool transcriptionRunning READ transcriptionRunning NOTIFY transcriptionRunningChanged)
    Q_PROPERTY(bool reversePreviewRunning READ reversePreviewRunning NOTIFY reversePreviewRunningChanged)

public:
    explicit MediaTools(QObject *parent = nullptr);

    int thumbnailRevision() const { return m_thumbnailRevision; }
    bool transcriptionRunning() const { return m_transcriptionRunning; }
    bool reversePreviewRunning() const { return m_reversePreviewRunning; }

    Q_INVOKABLE bool startTranscription(const QString &mediaUrl, const QString &modelPath,
                                        double sourceOffset, double duration);
    // Prepare a cached, lower-resolution reverse-playback copy without blocking the UI.
    // Returns a cached URL, "pending" when work starts, or "error:..." on validation failure.
    Q_INVOKABLE QString prepareReversePreview(const QString &mediaUrl, double sourceOffset,
                                             double duration, const QString &clipId);

    Q_INVOKABLE QVariantMap inspect(const QString &url) const;
    Q_INVOKABLE QString thumbnail(const QString &url);
    Q_INVOKABLE QString thumbnailAt(const QString &url, double seconds);
    Q_INVOKABLE QString previewFrameAt(const QString &url, double seconds);

signals:
    void thumbnailRevisionChanged();
    void transcriptionRunningChanged();
    void transcriptionFinished(const QVariantList &segments);
    void transcriptionFailed(const QString &message);
    void reversePreviewRunningChanged();
    void reversePreviewReady(const QString &clipId, const QString &previewUrl);
    void reversePreviewFailed(const QString &clipId, const QString &message);

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
    QProcess m_reversePreviewProcess;
    bool m_transcriptionRunning = false;
    bool m_reversePreviewRunning = false;
    bool m_reversePreviewHasAudio = false;
    QString m_reversePreviewStage;
    QString m_reversePreviewClipId;
    QString m_reversePreviewSourcePath;
    QString m_reversePreviewOutputPath;
    QString m_reversePreviewListPath;
    QString m_reversePreviewFfmpeg;
    QStringList m_reversePreviewChunkPaths;
    double m_reversePreviewSourceOffset = 0.0;
    double m_reversePreviewDuration = 0.0;
    int m_reversePreviewChunkIndex = 0;
    int m_reversePreviewChunkCount = 0;
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
    void setReversePreviewRunning(bool running);
    void startReversePreviewChunk();
    void startReversePreviewConcat();
    void handleReversePreviewFinished(int exitCode, QProcess::ExitStatus status);
    void failReversePreview(const QString &message);
};
