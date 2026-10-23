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

    // Ask Qt Multimedia's FFmpeg backend to prefer NVDEC/CUDA on NVIDIA,
    // then VA-API where available. Qt can still use software decoding when
    // a requested hardware backend or codec is unavailable. Users may override.
    if (qEnvironmentVariableIsEmpty("QT_FFMPEG_DECODING_HW_DEVICE_TYPES"))
        qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", "cuda,vaapi");

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
