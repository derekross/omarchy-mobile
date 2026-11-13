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
void ActionRunner::post(const QString &tool, const QStringList &args, const QVariantMap &result, int id) {
    const QString verb = args.value(0);
    m_last.insert(key(tool, verb), result);
    QMetaObject::invokeMethod(this, [this, tool, verb, result, id] { emit finished(tool, result, id, verb); }, Qt::QueuedConnection);
}

// A run that was started has ended: it is no longer pending, and its result is kept for the page.
void ActionRunner::done(const QString &tool, const QStringList &args, const QVariantMap &result, int id) {
    const QString k = key(tool, args.value(0));
    if (m_pending.value(k) > 0 && --m_pending[k] <= 0) m_pending.remove(k);
    post(tool, args, result, id);
}

int ActionRunner::run(const QString &tool, const QStringList &args, const QString &input) {
    static const QRegularExpression word("\\A[a-z0-9]{1,16}\\z");
    static const QStringList tools = {"display", "pin"};
    const int id = ++m_next;
    auto fail = [this, &tool, &args, id](const QString &why) { post(tool, args, {{"error", why}}, id); return id; };
    if (!tools.contains(tool) || args.size() > 3) return fail("unknown action");
    for (const auto &a : args) if (!word.match(a).hasMatch()) return fail("bad argument");
    if (input.size() > 256) return fail("input too long");
    if (!input.isEmpty() && tool != "pin") return fail("unexpected input");
    const QString &dir = m_dir;
    m_pending[key(tool, args.value(0))]++;
    auto *p = new QProcess(this);
    // What bash would read from the environment before the script runs: a startup file, exported functions,
    // options. The tools the scripts call are found in /usr/bin only.
    auto env = QProcessEnvironment::systemEnvironment();
    for (const QString &name : env.keys())
        if (name.startsWith(QLatin1String("BASH_FUNC_"))) env.remove(name);
    for (const char *name : {"BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "CDPATH", "GLOBIGNORE"}) env.remove(QLatin1String(name));
    env.insert("PATH", "/usr/bin:/bin");
    p->setProcessEnvironment(env);
    p->setProgram("/usr/bin/bash");
    p->setArguments(QStringList{"-p", dir + "/" + tool + ".sh"} + args);
    connect(p, &QProcess::finished, this, [this, p, tool, args, id](int code, QProcess::ExitStatus st) {
        const auto raw = p->readAllStandardOutput().left(4096);
        p->readAllStandardError();
        auto obj = QJsonDocument::fromJson(raw).object();
        if (obj.isEmpty() || st != QProcess::NormalExit)
            obj = QJsonObject{{"error", QStringLiteral("the backend failed (exit %1)").arg(code)}};
        done(tool, args, obj.toVariantMap(), id);
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, tool, args, id](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) { done(tool, args, {{"error", "cannot start the backend"}}, id); p->deleteLater(); }
    });
    p->start();
    if (!input.isEmpty()) p->write(input.toUtf8());
    p->closeWriteChannel();
    QTimer::singleShot(20000, p, [p] { if (p->state() != QProcess::NotRunning) p->kill(); });
    return id;
}
