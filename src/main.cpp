#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QCoreApplication>
#include <QQmlContext>
#include "ProjectStore.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    QGuiApplication::setApplicationName("Cutrix");
    QGuiApplication::setApplicationVersion("0.1.0");
    QGuiApplication::setOrganizationName("Cutrix");

    QQuickStyle::setStyle("Basic");

    ProjectStore projectStore;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("projectStore", &projectStore);
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
