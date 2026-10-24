#pragma once

#include <QObject>
#include <QProcess>
#include <QTemporaryDir>
#include <QVariantList>
#include <QStringList>

class ExportController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)

public:
    explicit ExportController(QObject *parent = nullptr);

    bool running() const { return m_running; }
    double progress() const { return m_progress; }

    Q_INVOKABLE bool startExport(const QVariantList &timelineItems, const QString &outputUrl,
                                int width, int height, int fps);
    Q_INVOKABLE void cancel();

signals:
    void runningChanged();
    void progressChanged();
    void statusChanged(const QString &message);
    void exportFinished(const QString &outputPath, bool usedHardwareEncoder);
    void exportFailed(const QString &message);

private:
    struct Clip {
        QString kind;
        QString path;
        QString text;
        int track = -1;
        int inputIndex = -1;
        double start = 0.0;
        double duration = 0.0;
        double x = 0.0;
        double y = 0.0;
        double scale = 100.0;
        double rotation = 0.0;
        double opacity = 100.0;
        double volume = 100.0;
        double fontSize = 42.0;
        QString textColor = QStringLiteral("#ffffff");
        bool hasAudio = false;
    };

    void startAttempt(bool useGpuEncoder);
    void readProgressOutput();
    void handleFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void handleProcessError(QProcess::ProcessError error);
    void setRunning(bool running);
    void setProgress(double progress);

    QProcess m_process;
    QTemporaryDir m_temporaryDirectory;
    QString m_outputPath;
    QString m_lastError;
    QStringList m_baseArguments;
    QString m_filterGraph;
    double m_timelineDuration = 0.0;
    int m_outputWidth = 1920;
    int m_outputHeight = 1080;
    int m_outputFps = 30;
    bool m_running = false;
    bool m_usingGpuEncoder = false;
    bool m_fallbackTried = false;
    bool m_processErrorHandled = false;
    double m_progress = 0.0;
};
