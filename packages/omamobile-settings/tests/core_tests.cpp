// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#include "actionrunner.h"
#include "backend.h"
#include "deviceinfocontroller.h"
#include "home_guard.h"
#include <QtTest>
#include <QQmlComponent>
#include <memory>
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
    void initTestCase() {
        QCoreApplication::setApplicationVersion("0.1.0");
        QVERIFY(m_stubs.isValid());
        const QMap<QString, QByteArray> answers{{"on", R"({"available":true,"limit":90})"}, {"off", R"({"available":false})"}};
        for (auto it = answers.begin(); it != answers.end(); ++it) {
            QVERIFY(QDir(m_stubs.path()).mkpath(it.key()));
            QFile f(stubs(it.key()) + "/charge.sh");
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write("printf '%s\\n' '" + it.value() + "'\n");
        }
    }
    void probeShowsTheBatteryRowOnlyWhenTheBackendSaysAvailable() {
        Backend on;
        on.setBackendDir(stubs("on"));
        QCOMPARE(on.rows().size(), 3);
        QTRY_COMPARE(on.rows().size(), 4);
        Backend off;
        off.setBackendDir(stubs("off"));
        off.setToolAvailable("charge", true);
        QTRY_COMPARE(off.rows().size(), 3); // the probe's answer clears it
    }
    void navigationRejectsUnknownAndHiddenActions() {
        Backend backend;
        backend.setBackendDir(stubs("off"));
        QVERIFY(backend.catalogProblems().isEmpty());
        QCOMPARE(backend.rows().size(), 3); // the Battery row waits for the charge backend, absent here
        backend.setToolAvailable("charge", true);
        QCOMPARE(backend.rows().size(), 4);
        backend.setToolAvailable("charge", false);
        QCOMPARE(backend.rows().size(), 3);
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
        backend.setBackendDir(stubs("off"));
        QVERIFY(backend.navigate("display"));
        QCOMPARE(backend.page(), QString("display"));
        backend.back();
        QCOMPARE(backend.page(), QString("root"));
    }
    void batteryPageGoesBackToRoot() {
        Backend backend;
        backend.setBackendDir(stubs("off"));
        QVERIFY(backend.navigate("battery"));
        QCOMPARE(backend.page(), QString("battery"));
        backend.back();
        QCOMPARE(backend.page(), QString("root"));
        backend.search("charge limit");
        QCOMPARE(backend.rows().size(), 0); // hidden from search too while the backend reports no limit
        backend.setToolAvailable("charge", true);
        backend.search("charge limit");
        QCOMPARE(backend.rows().size(), 1);
        QCOMPARE(backend.rows().first().toMap()["id"].toString(), QString("battery"));
    }
    void runnerKnowsChargeAndRejectsOthers() {
        ActionRunner runner;
        runner.setBackendDir(stubs("off"));
        QSignalSpy done(&runner, &ActionRunner::finished);
        const int bad = runner.run("nope", {"get"});
        const int badArg = runner.run("charge", {"set", "limit", "80;x"});
        const int charge = runner.run("charge", {"get"});
        QTRY_COMPARE(done.count(), 3);
        QMap<int, QString> errors;
        QMap<int, QVariantMap> answers;
        for (const auto &call : done) {
            errors[call.at(2).toInt()] = call.at(1).toMap()["error"].toString();
            answers[call.at(2).toInt()] = call.at(1).toMap();
        }
        QCOMPARE(errors[bad], QString("unknown action"));
        QCOMPARE(errors[badArg], QString("bad argument"));
        // the stub's own answer, so the runner ran the stub and not an installed charge.sh
        QCOMPARE(errors[charge], QString());
        QCOMPARE(answers[charge].value("available"), QVariant(false));
    }
    void batteryPageLoadsAndShowsTheBackendAnswer_data() {
        QTest::addColumn<QString>("stub");
        QTest::newRow("available") << "on";
        QTest::newRow("not available") << "off";
    }
    void batteryPageLoadsAndShowsTheBackendAnswer() {
        QFETCH(QString, stub);
        ActionRunner runner;
        runner.setBackendDir(stubs(stub));
        Backend backend; // outlives the engine: the style singleton reads it until the engine goes
        backend.setBackendDir(stubs(stub));
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.rootContext()->setContextProperty("actions", &runner);
        QQmlComponent component(&engine, QUrl("qrc:/BatteryPage.qml"));
        std::unique_ptr<QObject> page(component.create());
        QVERIFY2(page, qPrintable(component.errorString()));
        QCOMPARE(page->property("levels").toList().size(), 5);
        // the page runs `charge get` through the runner and leaves "busy" with the stub's answer
        QTRY_VERIFY(!page->property("busy").toBool());
        if (stub == "on") {
            QVERIFY(page->property("available").toBool());
            QCOMPARE(page->property("limit").toInt(), 90);
            QVERIFY(page->property("status").toString().startsWith("Stops charging at this level"));
        } else {
            QVERIFY(!page->property("available").toBool());
            QCOMPARE(page->property("status").toString(), QString("Settings cannot set a charge limit on this phone."));
        }
        QMetaObject::invokeMethod(page.get(), "apply", QVariant(QVariantMap{{"available", true}, {"limit", 85}}));
        QVERIFY(page->property("available").toBool());
        QCOMPARE(page->property("limit").toInt(), 85);
        QVERIFY(page->property("status").toString().startsWith("Stops charging at this level"));
        QMetaObject::invokeMethod(page.get(), "apply", QVariant(QVariantMap{{"available", false}}));
        QCOMPARE(page->property("status").toString(), QString("Settings cannot set a charge limit on this phone."));
    }
    void pinPageGoesBackToRoot() {
        Backend backend;
        backend.setBackendDir(stubs("off"));
        QVERIFY(backend.navigate("pin"));
        QCOMPARE(backend.page(), QString("pin"));
        backend.back();
        QCOMPARE(backend.page(), QString("root"));
    }
    // The PIN change finishes whether or not its page is still there: leaving the page while the stand-in for the
    // backend is still running (it hangs for a moment after reading its input), nobody listens for the result, and
    // the page that is opened again finds the outcome in the runner, once. A status request, which every page
    // instance makes, is a different request: it neither counts as the change nor takes its result.
    void aPinResultOutlivesThePage() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile f(dir.filePath("pin.sh"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("#!/bin/bash\ncase $1 in\nstatus) printf '{\"type\":\"pin\",\"hasPassword\":true}\\n' ;;\n"
                "change) read -r a; read -r b; read -r c; [[ $a == 5061 && $b == 7384 && $c == 7384 ]] || { printf '{\"error\":\"no input\"}\\n'; exit 0; }\n"
                "sleep 1.2; printf '{\"changed\":true}\\n' ;;\nesac\n");
        f.close();
        ActionRunner runner(nullptr, dir.path());
        QSignalSpy spy(&runner, &ActionRunner::finished);
        QVERIFY(!runner.pending("pin", "change"));
        runner.run("pin", {"change"}, "5061\n7384\n7384\n");
        QVERIFY(runner.pending("pin", "change"));
        // the page is left here: there is no listener, and the script is still running. The next page asks for the status.
        QVERIFY(runner.takeLastResult("pin", "change").isEmpty());
        runner.run("pin", {"status"});
        QTRY_VERIFY_WITH_TIMEOUT(!runner.pending("pin", "status"), 5000);
        QVERIFY(runner.pending("pin", "change"));
        QCOMPARE(runner.takeLastResult("pin", "status").value("type").toString(), QString("pin"));
        QVERIFY(runner.takeLastResult("pin", "change").isEmpty());
        QTRY_VERIFY_WITH_TIMEOUT(!runner.pending("pin", "change"), 5000);
        const QVariantMap r = runner.takeLastResult("pin", "change");
        QCOMPARE(r.value("changed").toBool(), true);
        QVERIFY(runner.takeLastResult("pin", "change").isEmpty());
        // the signal names the request: status first, change last
        QTRY_COMPARE(spy.count(), 2);
        QCOMPARE(spy.at(0).at(3).toString(), QString("status"));
        QCOMPARE(spy.at(1).at(3).toString(), QString("change"));
    }
    void inputIsForThePinToolOnly() {
        QTemporaryDir dir;
        ActionRunner runner(nullptr, dir.path());
        QSignalSpy spy(&runner, &ActionRunner::finished);
        runner.run("display", {"get"}, "secret\n");
        QTRY_COMPARE(spy.count(), 1);
        QCOMPARE(spy.at(0).at(1).toMap().value("error").toString(), QString("unexpected input"));
        QVERIFY(!runner.pending("display", "get"));
    }
    // A backend that is not there ends the request and clears it.
    void aMissingBackendIsNotLeftPending() {
        QTemporaryDir dir;
        ActionRunner runner(nullptr, dir.path());
        QSignalSpy spy(&runner, &ActionRunner::finished);
        runner.run("pin", {"status"});
        QVERIFY(runner.pending("pin", "status"));
        QTRY_COMPARE(spy.count(), 1);
        QVERIFY(!runner.pending("pin", "status"));
        QVERIFY(spy.at(0).at(1).toMap().contains("error"));
    }
    // What bash would read from the environment before the script runs is not read: BASH_ENV names a file that
    // would leave a marker, and the PATH the script sees is the system's.
    void theBackendDoesNotReadTheEnvironment() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString marker = dir.filePath("marker");
        QFile e(dir.filePath("env.sh"));
        QVERIFY(e.open(QIODevice::WriteOnly));
        e.write(("touch '" + marker + "'\n").toUtf8());
        e.close();
        QFile f(dir.filePath("pin.sh"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("#!/bin/bash\nprintf '{\"path\":\"%s\"}\\n' \"$PATH\"\n");
        f.close();
        const QByteArray oldPath = qgetenv("PATH");
        struct Restore { QByteArray path; ~Restore() { qunsetenv("BASH_ENV"); qputenv("PATH", path); } } restore{oldPath};
        qputenv("BASH_ENV", dir.filePath("env.sh").toUtf8());
        qputenv("PATH", "/tmp/not-the-system:/usr/bin");
        ActionRunner runner(nullptr, dir.path());
        QSignalSpy spy(&runner, &ActionRunner::finished);
        runner.run("pin", {"status"});
        QTRY_COMPARE(spy.count(), 1);
        QCOMPARE(spy.at(0).at(1).toMap().value("path").toString(), QString("/usr/bin:/bin:/usr/share/omarchy/bin"));
        QVERIFY(!QFile::exists(marker));
    }
    void searchHasOnlyImplementedRoutesAndBackClearsIt() {
        Backend backend;
        backend.setBackendDir(stubs("off"));
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
        backend.setBackendDir(stubs("off"));
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
        backend.setBackendDir(stubs("off"));
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
        backend.setBackendDir(stubs("off"));
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
        backend.setBackendDir(stubs("off"));
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
        backend.setBackendDir(stubs("off"));
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
private:
    // Stand-ins for backends/charge.sh, so no test reads the backend installed on the host: "on" answers like a
    // phone with a declared charge limit, "off" like any other.
    QString stubs(const QString &name) const { return m_stubs.filePath(name); }
    QTemporaryDir m_stubs;
};
QTEST_MAIN(CoreTests)
#include "core_tests.moc"
