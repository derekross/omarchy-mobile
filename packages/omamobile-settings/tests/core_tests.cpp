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
        QCOMPARE(backend.rows().size(), 2);
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
    void displayPageGoesBackToRoot() {
        Backend backend;
        QVERIFY(backend.navigate("display"));
        QCOMPARE(backend.page(), QString("display"));
        backend.back();
        QCOMPARE(backend.page(), QString("root"));
    }
    void searchHasOnlyImplementedRoutesAndBackClearsIt() {
        Backend backend;
        backend.search("STORAGE");
        QCOMPARE(backend.rows().size(), 1);
        backend.search("brightness");
        QCOMPARE(backend.rows().size(), 1);
        QCOMPARE(backend.rows().first().toMap()["id"].toString(), QString("display"));
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
    void backGoesUpOneLevelAndTheTopLevelGoesHome() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const auto marker = dir.filePath("home");
        const auto command = dir.filePath("omamobile-home");
        {
            QFile script(command);
            QVERIFY(script.open(QIODevice::WriteOnly));
            script.write("#!/bin/sh\necho home >>\"$1\"\n");
        }
        QVERIFY(QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        Backend backend;
        backend.setHomeCommand({command, marker});
        QSignalSpy home(&backend, &Backend::homeRequested);
        // A page and a search on it: Back leaves the search, then the page.
        backend.activate("about");
        backend.search("storage");
        backend.back();
        QVERIFY(!backend.searching());
        QCOMPARE(backend.page(), QString("about"));
        backend.back();
        QCOMPARE(backend.page(), QString("root"));
        QCOMPARE(home.count(), 0);
        QVERIFY(!QFile::exists(marker));
        // The top level: the home screen, and Settings stays as it is.
        backend.back();
        QCOMPARE(home.count(), 1);
        QCOMPARE(backend.page(), QString("root"));
        QTRY_VERIFY(QFile::exists(marker));
        // A search at the top level is a level of its own.
        backend.search("about");
        backend.back();
        QVERIFY(!backend.searching());
        QCOMPARE(home.count(), 1);
        // Opened at the root again from outside (the launcher) with a page
        // open: the root is the top level, not a page with About behind it.
        backend.activate("about");
        QVERIFY(backend.Open("root"));
        backend.back();
        QCOMPARE(backend.page(), QString("root"));
        QCOMPARE(home.count(), 2);
        // Opened on a page: Back goes to the root first.
        QVERIFY(backend.Open("about"));
        backend.back();
        QCOMPARE(backend.page(), QString("root"));
        QCOMPARE(home.count(), 2);
        // No command (no shell): still no close and no error.
        backend.setHomeCommand({});
        backend.back();
        QCOMPARE(home.count(), 3);
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
        backend.setHomeCommand({});
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
        // Escape (the shell's Back) at the top level asks for the home screen
        // and leaves the window open; it used to close the app.
        QSignalSpy home(&backend, &Backend::homeRequested);
        QVERIFY(QMetaObject::invokeMethod(window, "goBack"));
        QCOMPARE(home.count(), 1);
        QVERIFY(window->property("visible").toBool());
        QVERIFY(backend.navigate("about"));
        QTRY_COMPARE(info.info()["model"].toString(), QString("Mobile device"));

    }
};
QTEST_MAIN(CoreTests)
#include "core_tests.moc"
