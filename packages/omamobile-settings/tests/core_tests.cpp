// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#include "backend.h"
#include "deviceinfocontroller.h"
#include "actionrunner.h"
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
            QFile sec(stubs(it.key()) + "/security.sh");
            QVERIFY(sec.open(QIODevice::WriteOnly));
            sec.write(it.key() == "on"
                ? "printf '{\"firewall\":\"off\",\"ssh_active\":\"active\",\"ssh_enabled\":\"enabled\",\"ssh_allowed\":[\"USB\"],\"usb_ssh_rule\":true,\"hotspot\":false,\"can_enable\":true,\"why\":\"\",\"args\":\"%s\"}\\n' \"$*\"\n"
                : "printf '%s\\n' '{\"firewall\":\"not installed\",\"ssh_active\":\"inactive\",\"ssh_enabled\":\"disabled\",\"ssh_allowed\":[],\"usb_ssh_rule\":false,\"hotspot\":false,\"can_enable\":false,\"why\":\"UFW is not installed.\"}'\n");
        }
    }
    void probeShowsTheBatteryRowOnlyWhenTheBackendSaysAvailable() {
        Backend on;
        on.setBackendDir(stubs("on"));
        QCOMPARE(on.rows().size(), 4);
        QTRY_COMPARE(on.rows().size(), 5);
        Backend off;
        off.setBackendDir(stubs("off"));
        off.setToolAvailable("charge", true);
        QTRY_COMPARE(off.rows().size(), 4); // the probe's answer clears it
    }
    void navigationRejectsUnknownAndHiddenActions() {
        Backend backend;
        backend.setBackendDir(stubs("off"));
        QVERIFY(backend.catalogProblems().isEmpty());
        QCOMPARE(backend.rows().size(), 4); // the Battery row waits for the charge backend, absent here
        backend.setToolAvailable("charge", true);
        QCOMPARE(backend.rows().size(), 5);
        backend.setToolAvailable("charge", false);
        QCOMPARE(backend.rows().size(), 4);
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
    void securityPageGoesBackToRoot() {
        Backend backend;
        backend.setBackendDir(stubs("off"));
        QVERIFY(backend.navigate("security"));
        QCOMPARE(backend.page(), QString("security"));
        backend.back();
        QCOMPARE(backend.page(), QString("root"));
        backend.search("firewall");
        QCOMPARE(backend.rows().size(), 1);
        QCOMPARE(backend.rows().first().toMap()["id"].toString(), QString("security"));
    }
    void runnerTakesTheFirewallSwitch() {
        ActionRunner runner;
        runner.setBackendDir(stubs("on"));
        QSignalSpy done(&runner, &ActionRunner::finished);
        const int ok = runner.run("security", {"set", "firewall", "on"});
        const int bad = runner.run("security", {"set", "firewall", "on;x"});
        QTRY_COMPARE(done.count(), 2);
        for (const auto &call : done) {
            if (call.at(2).toInt() == ok) QCOMPARE(call.at(1).toMap().value("args").toString(), QString("set firewall on"));
            else { QCOMPARE(call.at(2).toInt(), bad); QCOMPARE(call.at(1).toMap().value("error").toString(), QString("bad argument")); }
        }
    }
    void nfcPageLoadsAndStagesASound() {
        // the page compiles (QtQuick.Dialogs' FileDialog among its imports)
        ActionRunner runner;
        runner.setBackendDir(stubs("off"));
        Backend backend;
        backend.setBackendDir(stubs("off"));
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.rootContext()->setContextProperty("actions", &runner);
        QQmlComponent component(&engine, QUrl("qrc:/NfcPage.qml"));
        std::unique_ptr<QObject> page(component.create());
        QVERIFY2(page, qPrintable(component.errorString()));
        // stageSound: only a local, readable file of at most 2 MiB, copied to the config dir's sounds/.import
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile small(dir.filePath("a.wav"));
        QVERIFY(small.open(QIODevice::WriteOnly)); small.write("RIFF1234"); small.close();
        QVERIFY(!runner.stageSound(QUrl("https://example.org/a.wav")).isEmpty());
        QVERIFY(!runner.stageSound(QUrl::fromLocalFile(dir.filePath("missing.wav"))).isEmpty());
        QFile big(dir.filePath("big.wav"));
        QVERIFY(big.open(QIODevice::WriteOnly)); big.write(QByteArray(2 * 1024 * 1024 + 1, 0)); big.close();
        QVERIFY(!runner.stageSound(QUrl::fromLocalFile(big.fileName())).isEmpty());
        QCOMPARE(runner.stageSound(QUrl::fromLocalFile(small.fileName())), QString());
        QFile staged(qEnvironmentVariable("XDG_CONFIG_HOME") + "/omamobile/sounds/.import");
        QVERIFY(staged.open(QIODevice::ReadOnly));
        QCOMPARE(staged.readAll(), QByteArray("RIFF1234"));
        staged.remove();
    }
    void firewallPageShowsTheBackendAnswer_data() {
        QTest::addColumn<QString>("stub");
        QTest::newRow("installed") << "on";
        QTest::newRow("not installed") << "off";
    }
    void firewallPageShowsTheBackendAnswer() {
        QFETCH(QString, stub);
        ActionRunner runner;
        runner.setBackendDir(stubs(stub));
        Backend backend; // outlives the engine: the style singleton reads it until the engine goes
        backend.setBackendDir(stubs(stub));
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.rootContext()->setContextProperty("actions", &runner);
        QQmlComponent component(&engine, QUrl("qrc:/FirewallPage.qml"));
        std::unique_ptr<QObject> page(component.create());
        QVERIFY2(page, qPrintable(component.errorString()));
        // the page runs `security get` through the runner (the stub, not an installed backend) and shows its answer
        QTRY_VERIFY(!page->property("busy").toBool());
        if (stub == "off") {
            QCOMPARE(page->property("firewall").toString(), QString("not installed"));
            QVERIFY(!page->property("canEnable").toBool());
            QVERIFY(page->property("status").toString().contains("not installed"));
            return;
        }
        QCOMPARE(page->property("firewall").toString(), QString("off"));
        QVERIFY(page->property("canEnable").toBool());
        QCOMPARE(page->property("sshAllowed").toList().size(), 1);
        const QVariantMap on{{"firewall", "on"}, {"ssh_active", "active"}, {"ssh_enabled", "enabled"},
                             {"ssh_allowed", QVariantList{"USB", "Wi-Fi from 10.0.0.0/24"}}, {"usb_ssh_rule", true}, {"hotspot", false}, {"can_enable", true}, {"why", ""}};
        QMetaObject::invokeMethod(page.get(), "apply", QVariant(on));
        QCOMPARE(page->property("firewall").toString(), QString("on"));
        QCOMPARE(page->property("sshAllowed").toList().size(), 2);
        QCOMPARE(page->property("status").toString(), QString());
        // a refused set keeps the state and shows the reason; the confirm is not left armed
        page->setProperty("confirming", true);
        page->setProperty("setting", true);
        QMetaObject::invokeMethod(page.get(), "apply", QVariant(QVariantMap{{"error", "Stop the hotspot first"}}));
        QCOMPARE(page->property("firewall").toString(), QString("on"));
        QCOMPARE(page->property("status").toString(), QString("Stop the hotspot first"));
        QVERIFY(!page->property("confirming").toBool());
        // off with on refused: the reason is kept for the page's line
        auto off = on; off["firewall"] = "off"; off["can_enable"] = false; off["why"] = "Stop the hotspot first.";
        page->setProperty("setting", true);
        QMetaObject::invokeMethod(page.get(), "apply", QVariant(off));
        QCOMPARE(page->property("status").toString(), QString("The firewall is off."));
        QVERIFY(!page->property("canEnable").toBool());
        QCOMPARE(page->property("why").toString(), QString("Stop the hotspot first."));
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
        QVERIFY(backend.icon("pin").startsWith("data:image/svg+xml;base64,"));
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
    // Stand-ins for backends/charge.sh and backends/security.sh, so no test reads a backend installed on the host: "on"
    // answers like a phone with a declared charge limit and UFW (off, SSH allowed over USB), "off" like one with neither.
    QString stubs(const QString &name) const { return m_stubs.filePath(name); }
    QTemporaryDir m_stubs;
};
QTEST_MAIN(CoreTests)
#include "core_tests.moc"
