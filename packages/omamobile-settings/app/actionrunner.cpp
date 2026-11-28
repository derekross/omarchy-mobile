// SPDX-License-Identifier: MIT
#include "actionrunner.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>
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
    static const QStringList tools = {"display", "charge", "security", "nfc", "privacy"};
    const int id = ++m_next;
    auto fail = [this, &tool, id](const QString &why) { post(tool, {{"error", why}}, id); return id; };
    if (!tools.contains(tool) || args.size() > 3) return fail("unknown action");
    for (const auto &a : args) if (!word.match(a).hasMatch()) return fail("bad argument");
    auto *p = new QProcess(this);
    // bash would run a startup file named by these
    auto env = QProcessEnvironment::systemEnvironment();
    env.remove("BASH_ENV");
    env.remove("ENV");
    p->setProcessEnvironment(env);
    p->setProgram("/usr/bin/bash");
    p->setArguments(QStringList{m_dir + "/" + tool + ".sh"} + args);
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
    // the firewall switch: up to three reads (10 s each at worst) and systemctl start, which waits for the owner's PIN
    // (cut at 122 s: 60 s for the PIN and the unit's 60 s limit): 152 s, so 160 s
    // NFC on or off (nfc set nfc on|off) and microphone or camera access (privacy set mic|camera on|off) wait for the
    // PIN the same way: 122 s plus two reads (and a 5 s journal read on a failure), so 160 s as well
    const bool pinSet = (tool == "security" || tool == "nfc" || tool == "privacy") && args.value(0) == "set";
    QTimer::singleShot(pinSet ? 160000 : 20000, p, [p] { if (p->state() != QProcess::NotRunning) p->kill(); });
    return id;
}

// The NFC page's "Choose sound...": copy the file the dialog picked (a local file, at most 2 MiB) to
// ~/.config/omamobile/sounds/.import, where `nfc sound import` checks it and takes it. The path never goes through
// run()'s arguments. Returns "" or why it was refused.
QString ActionRunner::stageSound(const QUrl &picked) {
    if (!picked.isLocalFile()) return tr("Pick a file on the phone.");
    const QFileInfo src(picked.toLocalFile());
    if (!src.isFile() || !src.isReadable()) return tr("That file can't be read.");
    if (src.size() > 2 * 1024 * 1024) return tr("That file is too big for a tag sound.");
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/omamobile/sounds";
    if (!QDir().mkpath(dir)) return tr("Can't write to ~/.config/omamobile/sounds.");
    const QString dest = dir + "/.import";
    QFile::remove(dest);
    QFile in(src.absoluteFilePath()), out(dest);
    if (!in.open(QIODevice::ReadOnly) || !out.open(QIODevice::WriteOnly | QIODevice::NewOnly)) return tr("Can't copy that file.");
    const QByteArray bytes = in.read(2 * 1024 * 1024 + 1);
    if (bytes.size() > 2 * 1024 * 1024 || out.write(bytes) != bytes.size() || !out.flush()) { out.close(); QFile::remove(dest); return tr("Can't copy that file."); }
    return QString();
}
