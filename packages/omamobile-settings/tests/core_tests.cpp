// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#include "backend.h"
#include "deviceinfocontroller.h"
#include <QtTest>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QSaveFile>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTemporaryDir>

class CoreTests : public QObject {
    Q_OBJECT
private slots:
    void initTestCase() { QCoreApplication::setApplicationVersion("0.1.0"); }
    void navigationRejectsUnknownAndHiddenActions() {
        Backend backend;
        QVERIFY(backend.catalogProblems().isEmpty());
        QCOMPARE(backend.rows().size(), 1);
        QVERIFY(!backend.navigate("recording"));
        backend.activate("arbitrary-command");
        QCOMPARE(backend.page(), QString("root"));
        backend.activate("about");
        QCOMPARE(backend.page(), QString("about"));
        backend.activate("about");
        QCOMPARE(backend.page(), QString("about"));
        backend.back();
        QCOMPARE(backend.page(), QString("root"));
    }
    void searchHasOnlyImplementedRoutesAndBackClearsIt() {
        Backend backend;
        backend.search("STORAGE");
        QCOMPARE(backend.rows().size(), 1);
        QVERIFY(backend.searching());
        backend.back();
        QVERIFY(!backend.searching());
        backend.search("nonexistent preference");
        QVERIFY(backend.rows().isEmpty());
        backend.activate("about");
        QCOMPARE(backend.page(), QString("root"));
        backend.search("About");
        backend.activate("about");
        QCOMPARE(backend.page(), QString("about"));
        QVERIFY(!backend.searching());
    }
    void iconNamesCannotEscapeResources() {
        Backend backend;
        QVERIFY(backend.icon("../catalog").isEmpty());
        QVERIFY(backend.icon("unknown").isEmpty());
        QVERIFY(backend.icon("system").startsWith("data:image/svg+xml;base64,"));
    }
    void atomicThemeReplacementIsObserved() {
        const auto directory = QDir::homePath() + "/.local/state/omarchy/current/theme";
        QVERIFY(QDir().mkpath(directory));
        const auto path = directory + "/colors.toml";
        auto save = [&path](const QByteArray &text) {
            QSaveFile file(path);
            return file.open(QIODevice::WriteOnly) && file.write(text) == text.size() && file.commit();
        };
        QVERIFY(save("background = '#112233'\nforeground = '#eeeeee'\naccent = '#66aa88'\n"));
        Backend backend;
        QCOMPARE(backend.background(), QColor("#112233"));
        QVERIFY(save("background = '#ddeeff'\nforeground = '#112233'\naccent = '#557799'\n"));
        QTRY_COMPARE(backend.background(), QColor("#ddeeff"));
        QCOMPARE(backend.accent(), QColor("#557799"));
        QVERIFY(save("background = 'not-a-color'\n"));
        QTest::qWait(100);
        QCOMPARE(backend.background(), QColor("#ddeeff"));
    }
    void officialFontAndControlTokensObserveAtomicChanges() {
        const auto directory=QDir::homePath()+"/.local/state/omarchy/current/theme";
        QVERIFY(QDir().mkpath(directory));
        const auto save=[](const QString &path,const QByteArray &bytes) {
            QSaveFile file(path);
            return file.open(QIODevice::WriteOnly) && file.write(bytes)==bytes.size() && file.commit();
        };
        QVERIFY(save(directory+"/colors.toml","background='#112233'\nforeground='#eeeeee'\naccent='#66aa88'\nmuted='#778899'\n"));
        QVERIFY(save(directory+"/shell.toml","[font]\nbase-size=12\n[controls]\nnormal-fill-alpha=0.04\n"));
        Backend backend;
        QCOMPARE(backend.themeTokens()["fontScale"].toDouble(),1.0);
        QCOMPARE(backend.muted(),QColor("#778899"));
        const auto page=backend.page();
        QVERIFY(save(directory+"/shell.toml","[font]\nbase-size=18\nbody=19\n[controls]\nnormal-color='accent'\nnormal-fill-alpha=0.2\nfocus-border-width=2\n"));
        QTRY_COMPARE(backend.themeTokens()["fontScale"].toDouble(),1.5);
        QCOMPARE(backend.themeTokens()["font.body"].toInt(),19);
        QCOMPARE(backend.themeTokens()["focusBorderWidth"].toInt(),2);
        QCOMPARE(backend.page(),page);
    }
    void neutralPreviewAndUnknownValues() {
        DeviceInfoController info(true);
        QSignalSpy changed(&info, &DeviceInfoController::changed);
        info.refresh();
        QCOMPARE(changed.size(), 1);
        QVERIFY(!info.busy());
        QCOMPARE(info.info()["settingsVersion"].toString(), QString("0.1.0"));
        QCOMPARE(info.info()["model"].toString(), QString("Mobile device"));
        QVERIFY(info.info()["storageKnown"].toBool());
        QVERIFY(DeviceInfoController::formatBytes(0).isEmpty());
        QCOMPARE(DeviceInfoController::formatBytes(1000000000), QString("1.0 GB"));
        for (const auto &key : {"serial", "imei", "hostname", "username", "address"})
            QVERIFY(!info.info().contains(key));
    }
    void actualWindowAndReadOnlyAbout() {
        Backend backend;
        DeviceInfoController info(true);
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.rootContext()->setContextProperty("deviceInfo", &info);
        engine.load(QUrl("qrc:/Main.qml"));
        QCOMPARE(engine.rootObjects().size(), 1);
        auto *window = engine.rootObjects().first();
        auto *search = window->findChild<QObject *>("settingsSearch");
        QVERIFY(search);
        search->setProperty("text", "Storage");
        backend.search("Storage");
        QVERIFY(QMetaObject::invokeMethod(window, "goBack"));
        QVERIFY(!backend.searching());
        QCOMPARE(search->property("text").toString(), QString());
        QVERIFY(backend.navigate("about"));
        QTRY_COMPARE(info.info()["model"].toString(), QString("Mobile device"));

    }
};
QTEST_MAIN(CoreTests)
#include "core_tests.moc"
