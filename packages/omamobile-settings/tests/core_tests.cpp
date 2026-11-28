// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#include "backend.h"
#include "deviceinfocontroller.h"
#include <QQuickItem>
#include <QQuickWindow>
#include <functional>
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
        }
    }
    void probeShowsTheBatteryRowOnlyWhenTheBackendSaysAvailable() {
        Backend on;
        on.setBackendDir(stubs("on"));
        QCOMPARE(on.rows().size(), 2);
        QTRY_COMPARE(on.rows().size(), 3);
        Backend off;
        off.setBackendDir(stubs("off"));
        off.setToolAvailable("charge", true);
        QTRY_COMPARE(off.rows().size(), 2); // the probe's answer clears it
    }
    void navigationRejectsUnknownAndHiddenActions() {
        Backend backend;
        backend.setBackendDir(stubs("off"));
        QVERIFY(backend.catalogProblems().isEmpty());
        QCOMPARE(backend.rows().size(), 2); // the Battery row waits for the charge backend, absent here
        backend.setToolAvailable("charge", true);
        QCOMPARE(backend.rows().size(), 3);
        backend.setToolAvailable("charge", false);
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
        backend.search("credits");
        backend.activate("credits");
        QCOMPARE(backend.page(), QString("credits"));
        backend.search("disclaimer");
        backend.activate("disclaimer");
        QCOMPARE(backend.page(), QString("disclaimer"));
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
    void creditsFileFormat() {
        QString why;
        QCOMPARE(Backend::parseCredits(R"({"people":[{"login":"ab-1"},{"login":"C"}]})", &why).size(), 2);
        for (const char *bad : {"", "[]", R"({"people":[]})", R"({"people":[{"name":"A"}]})",
                R"({"people":[{"name":"A","login":"x"}]})", R"({"people":[{"login":"x","email":"a@b.c"}]})",
                R"({"people":[{"login":"bad login"}]})", R"({"people":[{"login":"x"},{"login":"X"}]})"}) {
            why.clear();
            QVERIFY2(Backend::parseCredits(bad, &why).isEmpty(), bad);
            QVERIFY2(!why.isEmpty(), bad);
        }
    }
    void bundledCreditsAndCreditsPage() {
        Backend backend;
        backend.setBackendDir(stubs("off"));
        backend.setHomeCommand({});
        const auto people = backend.credits();
        QVERIFY(people.size() > 5);
        for (const auto &p : people) {
            QVERIFY(!p.toMap()["login"].toString().isEmpty());
            QVERIFY(!p.toMap().contains("name"));
        }
        QVERIFY(backend.catalogProblems().isEmpty());
        QVERIFY(backend.navigate("about"));
        QVERIFY(backend.navigate("credits"));
        QCOMPARE(backend.title(), QString("Credits"));
        backend.back();
        QCOMPARE(backend.page(), QString("about"));
        QVERIFY(backend.navigate("disclaimer"));
        QCOMPARE(backend.title(), QString("Disclaimer"));
        backend.back();
        QCOMPARE(backend.page(), QString("about"));
        // The real window: the Credits page lists everyone, the About page has the row and the disclaimer.
        DeviceInfoController info(true);
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.rootContext()->setContextProperty("deviceInfo", &info);
        engine.load(QUrl("qrc:/Main.qml"));
        QCOMPARE(engine.rootObjects().size(), 1);
        auto *window = engine.rootObjects().first();
        QTRY_VERIFY(window->findChild<QObject *>("creditsRow"));
        QVERIFY(window->findChild<QObject *>("disclaimer"));
        {
            // Two columns, in order, and the kernel alone across both.
            // Repeater delegates are visual children, not QObject children, so walk the item tree.
            std::function<QQuickItem *(QQuickItem *, const QString &)> find = [&](QQuickItem *at, const QString &name) -> QQuickItem * {
                if (at->objectName() == name) return at;
                for (auto *child : at->childItems()) if (auto *hit = find(child, name)) return hit;
                return nullptr;
            };
            auto *root = qobject_cast<QQuickWindow *>(window)->contentItem();
            const auto item = [&](const char *key) { return find(root, QString("fact-") + key); };
            QTRY_VERIFY(item("kernel") && item("kernel")->width() > 0);
            const char *keys[] = {"manufacturer", "memory", "architecture", "omarchyVersion", "shellVersion", "settingsVersion"};
            for (int i = 0; i < 6; ++i) {
                QVERIFY2(item(keys[i]), keys[i]);
                QCOMPARE(item(keys[i])->x() > 1, i % 2 == 1);
                if (i > 1) QVERIFY(item(keys[i])->y() > item(keys[i - 2])->y());
                if (i % 2) QCOMPARE(item(keys[i])->y(), item(keys[i - 1])->y());
            }
            QVERIFY(item("kernel")->x() < 1);
            QVERIFY(item("kernel")->y() > item("shellVersion")->y());
            QVERIFY(item("kernel")->width() > item("memory")->x() + item("memory")->width() - 2);
        }
        QVERIFY(backend.navigate("credits"));
        QTRY_VERIFY(window->findChild<QObject *>("creditsList"));
        QCOMPARE(window->findChild<QObject *>("creditsList")->property("count").toInt(), int(people.size()));
        QVERIFY(window->findChild<QObject *>("creditsList")->property("atYBeginning").toBool());
        {
            // The intro is whole and above the list, not clipped in the list's header.
            auto *intro = window->findChild<QQuickItem *>("creditsIntro");
            auto *list = window->findChild<QQuickItem *>("creditsList");
            QVERIFY(intro && list);
            QTRY_VERIFY(intro->height() > 0 && list->height() > 0);
            QVERIFY(intro->y() >= 0);
            QCOMPARE(intro->parentItem(), list->parentItem());
            QVERIFY(list->y() >= intro->y() + intro->height());
            QCOMPARE(intro->height(), intro->implicitHeight());
            QVERIFY(intro->mapToScene(QPointF(0, 0)).y() >= 0);
            QVERIFY(intro->property("lineCount").toInt() > 1);
        }
        QVERIFY(QMetaObject::invokeMethod(window, "goBack"));
        QCOMPARE(backend.page(), QString("about"));
        QTRY_VERIFY(window->findChild<QObject *>("creditsRow"));
        QVERIFY(!window->findChild<QObject *>("creditsList") || !window->findChild<QObject *>("creditsList")->property("visible").toBool());
        // The About row opens the Disclaimer page; its four sections keep the sourced wording.
        QVERIFY(QMetaObject::invokeMethod(window->findChild<QObject *>("disclaimer"), "clicked"));
        QCOMPARE(backend.page(), QString("disclaimer"));
        QTRY_VERIFY(window->findChild<QObject *>("disclaimerPage"));
        {
            std::function<QString(QQuickItem *)> text = [&](QQuickItem *at) {
                QString all = at->property("text").toString() + "\n";
                for (auto *child : at->childItems()) all += text(child);
                return all;
            };
            std::function<int(QQuickItem *)> sections = [&](QQuickItem *at) {
                int n = at->objectName().startsWith("disclaimer-") ? 1 : 0;
                for (auto *child : at->childItems()) n += sections(child);
                return n;
            };
            auto *root = qobject_cast<QQuickWindow *>(window)->contentItem();
            QTRY_COMPARE(sections(root), 4);
            const QString all = text(root);
            QVERIFY(all.contains("It isn't an official Omarchy or Basecamp product."));
            QVERIFY(all.contains("On the Pixel 7 Pro the installer writes only slot B"));
            QVERIFY(all.contains("without warranty of any kind"));
        }
        QVERIFY(QMetaObject::invokeMethod(window, "goBack"));
        QCOMPARE(backend.page(), QString("about"));
    }
private:
    // Stand-ins for backends/charge.sh, so no test reads the backend installed on the host: "on" answers like a
    // phone with a declared charge limit, "off" like any other.
    QString stubs(const QString &name) const { return m_stubs.filePath(name); }
    QTemporaryDir m_stubs;
};
QTEST_MAIN(CoreTests)
#include "core_tests.moc"
