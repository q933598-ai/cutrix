#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QCoreApplication>
#include <QQmlContext>
#include "ProjectStore.h"
#include "MediaTools.h"
#include "ExportController.h"

int main(int argc, char *argv[])
{
    // Qt Quick uses the GPU-backed RHI renderer. OpenGL is the stable default
    // for desktop Linux; respect an explicit user override when debugging.
    if (qEnvironmentVariableIsEmpty("QSG_RHI_BACKEND"))
        qputenv("QSG_RHI_BACKEND", "opengl");

    // Qt Multimedia's FFmpeg backend can fail to fall back to software
    // decoding for AV1 when CUDA/NVDEC is selected on GPUs without AV1 decode
    // support (for example, NVIDIA GeForce RTX 20-series). Use software
    // decoding by default for reliable playback. Users can explicitly opt in
    // to hardware decoding with QT_FFMPEG_DECODING_HW_DEVICE_TYPES=cuda,vaapi.
    // This does not affect FFmpeg export encoding (NVENC remains available).
    if (qEnvironmentVariableIsEmpty("QT_FFMPEG_DECODING_HW_DEVICE_TYPES"))
        qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", ",");

    QApplication app(argc, argv);

    QGuiApplication::setApplicationName("Cutrix");
    QGuiApplication::setApplicationVersion("0.1.0");
    QGuiApplication::setOrganizationName("Cutrix");

    QQuickStyle::setStyle("Basic");

    ProjectStore projectStore;
    MediaTools mediaTools;
    ExportController exportController;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("projectStore", &projectStore);
    engine.rootContext()->setContextProperty("mediaTools", &mediaTools);
    engine.rootContext()->setContextProperty("exportController", &exportController);
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        [] { QCoreApplication::exit(EXIT_FAILURE); },
        Qt::QueuedConnection
    );

    engine.loadFromModule("Cutrix", "Main");
    return app.exec();
}
