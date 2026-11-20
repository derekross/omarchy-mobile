// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#include "deviceinfocontroller.h"
#include <QtTest>
#include <QElapsedTimer>
#include <cerrno>
#include <signal.h>

class DeviceInfoLifetimeTests : public QObject {
    Q_OBJECT
private slots:
    void activeQueryIsReapedBeforeTimerDestruction() {
        QObject observer;
        bool timerDestroyed = false;
        bool finishedAfterTimerDestroyed = false;
        int finished = 0;
        auto *controller = new DeviceInfoController(true);
        QSignalSpy changed(controller, &DeviceInfoController::changed);
        connect(&controller->m_timeout, &QObject::destroyed, &observer, [&] {
            timerDestroyed = true;
        });
        connect(&controller->m_query, &QProcess::finished, &observer, [&] {
            ++finished;
            finishedAfterTimerDestroyed = timerDestroyed;
        });
        // No controller refresh: the owned child is harmless fixture work.
        controller->m_query.start("/usr/bin/python3", {"-c", "import time; time.sleep(5)"});
        QVERIFY(controller->m_query.waitForStarted(1000));
        const auto pid = controller->m_query.processId();
        QVERIFY(pid > 0);
        controller->m_timeout.start(3500);
        QElapsedTimer elapsed;
        elapsed.start();
        delete controller;
        QVERIFY(elapsed.elapsed() < 2000);
        QVERIFY(timerDestroyed);
        QCOMPARE(finished, 1);
        QVERIFY(!finishedAfterTimerDestroyed);
        QCOMPARE(changed.size(), 0);
        errno = 0;
        QCOMPARE(::kill(static_cast<pid_t>(pid), 0), -1);
        QCOMPARE(errno, ESRCH);
    }
};
QTEST_GUILESS_MAIN(DeviceInfoLifetimeTests)
#include "deviceinfo_lifetime_tests.moc"
