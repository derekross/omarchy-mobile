// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#include "backend.h"
#include "deviceinfocontroller.h"
#include "actionrunner.h"
#include <QGuiApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocale>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <cstdio>

int main(int argc, char **argv) {
    bool preview = false, check = false;
    QString page = "root";
    for (int i = 1; i < argc; ++i) {
        const auto argument = QString::fromLocal8Bit(argv[i]);
        if (argument == "--version") {
            std::puts("omamobile-settings " OMAMOBILE_SETTINGS_VERSION);
            return 0;
        }
        else if (argument == "--preview") preview = true;
        else if (argument == "--check") check = preview = true;
        else if (argument == "--page" && i + 1 < argc) page = QString::fromLocal8Bit(argv[++i]);
        else { std::fprintf(stderr, "Usage: omamobile-settings [--page PAGE] [--preview] [--check] [--version]\n"); return 2; }
    }
    if (check) qputenv("QT_QPA_PLATFORM", "offscreen");
    QLocale::setDefault(QLocale(QLocale::English, QLocale::UnitedStates));
    QGuiApplication app(argc, argv);
    app.setApplicationName("omamobile-settings");
    app.setApplicationVersion(QStringLiteral(OMAMOBILE_SETTINGS_VERSION));
    app.setDesktopFileName("org.omamobile.Settings");
    QQuickStyle::setStyle("Basic");
    Backend backend;
#ifdef OMAMOBILE_SETTINGS_TEST_DEVICE_INFO
    // Only the separately built test entrypoint fixes read-only model data.
    DeviceInfoController deviceInfo(true);
#else
    DeviceInfoController deviceInfo(preview);
#endif
    if (check) {
        const auto errors = backend.catalogProblems();
        std::puts(QJsonDocument(QJsonObject{{"ok", errors.isEmpty()}, {"errors", QJsonArray::fromStringList(errors)}}).toJson(QJsonDocument::Compact).constData());
        return errors.isEmpty() ? 0 : 1;
    }
    if (!backend.catalogProblems().isEmpty() || !backend.navigate(page)) return 2;
    if (!preview) {
        auto bus = QDBusConnection::sessionBus();
        if (!bus.isConnected()) return 1;
        if (!bus.registerService("org.omamobile.Settings")) {
            QDBusInterface existing("org.omamobile.Settings", "/Settings", "org.omamobile.Settings", bus);
            const auto reply = existing.call("Open", page);
            return reply.type() == QDBusMessage::ReplyMessage && reply.arguments().size() == 1
                && reply.arguments().first().metaType().id() == QMetaType::Bool
                && reply.arguments().first().toBool() ? 0 : 1;
        }
        if (!bus.registerObject("/Settings", &backend, QDBusConnection::ExportScriptableSlots
                                | QDBusConnection::ExportScriptableInvokables)) return 1;
    }
    ActionRunner actions;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.rootContext()->setContextProperty("deviceInfo", &deviceInfo);
    engine.rootContext()->setContextProperty("actions", &actions);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty()) return 1;
    return app.exec();
}
