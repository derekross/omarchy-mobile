// SPDX-License-Identifier: MIT
#include "actionrunner.h"
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QTimer>

// finished() is always emitted from the event loop, never before run() has returned its id.
void ActionRunner::post(const QString &tool, const QVariantMap &result, int id) {
    QMetaObject::invokeMethod(this, [this, tool, result, id] { emit finished(tool, result, id); }, Qt::QueuedConnection);
}

int ActionRunner::run(const QString &tool, const QStringList &args) {
    static const QRegularExpression word("\\A[a-z0-9]{1,16}\\z");
    // an app's desktop ID (org.foo.Bar, foo-bar): no slash, no leading dot or dash, no ".." (the backend checks it again
    // and only matches it against the IDs it scans; it never builds a path from it)
    static const QRegularExpression appId("\\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\z");
    static const QStringList tools = {"display", "charge", "apps", "appmgr"};
    const int id = ++m_next;
    auto fail = [this, &tool, id](const QString &why) { post(tool, {{"error", why}}, id); return id; };
    if (!tools.contains(tool) || args.size() > (tool == "apps" ? 2 : 3)) return fail("unknown action");
    for (qsizetype i = 0; i < args.size(); ++i) {
        const QString &a = args.at(i);
        // apps, appmgr: the verb is a word, the second argument a desktop ID (appmgr's third: a policy word or a 16-digit hash)
        const bool ok = ((tool == "apps" || tool == "appmgr") && i == 1) ? appId.match(a).hasMatch() && !a.contains(QLatin1String("..")) : word.match(a).hasMatch();
        if (!ok) return fail("bad argument");
    }
    auto *p = new QProcess(this);
    // bash would run a startup file named by these
    auto env = QProcessEnvironment::systemEnvironment();
    env.remove("BASH_ENV");
    env.remove("ENV");
    p->setProcessEnvironment(env);
    p->setProgram("/usr/bin/bash");
    p->setArguments(QStringList{m_dir + "/" + tool + ".sh"} + args);
    connect(p, &QProcess::finished, this, [this, p, tool, id](int code, QProcess::ExitStatus st) {
        // the Apps list can be up to 64 KiB (backends/apps.sh cuts it below that); every other answer is small
        const auto raw = p->readAllStandardOutput().left((tool == "apps" || tool == "appmgr") ? 65536 : 4096);
        p->readAllStandardError();
        auto obj = QJsonDocument::fromJson(raw).object();
        if (obj.isEmpty() || st != QProcess::NormalExit)
            obj = QJsonObject{{"error", QStringLiteral("the backend failed (exit %1)").arg(code)}};
        post(tool, obj.toVariantMap(), id);
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, tool, id](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) { post(tool, {{"error", "cannot start the backend"}}, id); p->deleteLater(); }
    });
    p->start();
    p->closeWriteChannel();
    // an uninstall: checks before (apps.sh info, app-guard: up to about 60 s), the root unit (TimeoutStartSec 320, cut at 330), checks after: 420 s
    const bool appRemove = tool == "appmgr" && args.value(0) == "remove";
    // state runs pacman's dry run and reads its database a few times; stop waits for the app's units to end
    const bool appSlow = tool == "appmgr" && (args.value(0) == "state" || args.value(0) == "stop");
    QTimer::singleShot(appRemove ? 420000 : appSlow ? 60000 : 20000, p, [p] { if (p->state() != QProcess::NotRunning) p->kill(); });
    return id;
}
