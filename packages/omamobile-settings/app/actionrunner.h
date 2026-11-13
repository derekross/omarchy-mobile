// SPDX-License-Identifier: MIT
#pragma once
#include <QObject>
#include <QVariantMap>
#include <QStringList>
#include <QHash>

// Runs the source-owned backend scripts (display, pin) with a fixed argument list and no shell. Pages call run();
// the JSON the script prints comes back through finished(), always from the event loop and never before run()
// has returned its id. The PIN page passes its input on stdin only; it is never an argument and never logged.
class ActionRunner : public QObject {
    Q_OBJECT
public:
    // The backend directory is fixed in the program; a test passes its own through the constructor.
    explicit ActionRunner(QObject *parent = nullptr, const QString &dir = QStringLiteral("/usr/lib/omamobile-settings/backends"))
        : QObject(parent), m_dir(dir) {}
    // input is for the pin tool only: its three lines go to the script's stdin.
    Q_INVOKABLE int run(const QString &tool, const QStringList &args, const QString &input = {});
    // A tool still running, and the last result nobody took: a page that was left while its action ran (the PIN
    // change finishes either way) finds the outcome here when it is opened again. Taking clears it.
    Q_INVOKABLE bool pending(const QString &tool, const QString &verb) const { return m_pending.value(key(tool, verb)) > 0; }
    Q_INVOKABLE QVariantMap takeLastResult(const QString &tool, const QString &verb) { return m_last.take(key(tool, verb)); }
signals:
    // verb is the first argument (get, set, change, status): a page told apart its own requests by id only,
    // and an old page's request finishing under a new page was taken for the new page's.
    void finished(const QString &tool, const QVariantMap &result, int id, const QString &verb);
private:
    static QString key(const QString &tool, const QString &verb) { return tool + QLatin1Char(':') + verb; }
    void post(const QString &tool, const QStringList &args, const QVariantMap &result, int id);
    void done(const QString &tool, const QStringList &args, const QVariantMap &result, int id);
    int m_next = 0;
    QString m_dir;
    QHash<QString, int> m_pending;
    QHash<QString, QVariantMap> m_last;
};
