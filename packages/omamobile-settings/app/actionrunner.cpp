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
    static const QStringList tools = {"display"};
    const int id = ++m_next;
    auto fail = [this, &tool, id](const QString &why) { post(tool, {{"error", why}}, id); return id; };
    if (!tools.contains(tool) || args.size() > 3) return fail("unknown action");
    for (const auto &a : args) if (!word.match(a).hasMatch()) return fail("bad argument");
    const QString dir = "/usr/lib/omamobile-settings/backends";
    auto *p = new QProcess(this);
    // bash would run a startup file named by these
    auto env = QProcessEnvironment::systemEnvironment();
    env.remove("BASH_ENV");
    env.remove("ENV");
    p->setProcessEnvironment(env);
    p->setProgram("/usr/bin/bash");
    p->setArguments(QStringList{dir + "/" + tool + ".sh"} + args);
    connect(p, &QProcess::finished, this, [this, p, tool, id](int code, QProcess::ExitStatus st) {
        const auto raw = p->readAllStandardOutput().left(4096);
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
    QTimer::singleShot(20000, p, [p] { if (p->state() != QProcess::NotRunning) p->kill(); });
    return id;
}
