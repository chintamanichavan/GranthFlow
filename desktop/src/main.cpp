// GranthFlow on the desktop: the library and the readers are QML (qml/); the library, the engine and
// the typesetting are C++ (src/). Files named on the command line open, as "Open with" passes them.
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QStandardPaths>
#include <QUrl>

#include "Library.h"

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName("GranthFlow");
    QGuiApplication::setApplicationName("GranthFlow");
    QQuickStyle::setStyle("Fusion");                       // the same look on Windows, Linux and macOS

    Library library(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/library.json");
    QList<QUrl> named;
    for (const QString &arg : app.arguments().mid(1)) named << QUrl::fromLocalFile(arg);
    const QStringList opened = library.add(named);

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{"library", QVariant::fromValue(&library)}, {"openPath", opened.value(0)}});
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("GranthFlow", "Main");
    return app.exec();
}
