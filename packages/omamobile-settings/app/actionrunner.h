// SPDX-License-Identifier: MIT
#pragma once
#include <QObject>
#include <QVariantMap>
#include <QStringList>

// Runs the source-owned backend scripts (display, charge) with a fixed argument list and no shell. Pages call run();
// the JSON the script prints comes back through finished(), always from the event loop and never before run()
// has returned its id.
class ActionRunner : public QObject {
    Q_OBJECT
public:
    explicit ActionRunner(QObject *parent = nullptr) : QObject(parent) {}
    Q_INVOKABLE int run(const QString &tool, const QStringList &args);
    // Where the backend scripts live; tests point it at stubs so they don't depend on the host's install.
    void setBackendDir(const QString &dir) { m_dir = dir; }
signals:
    void finished(const QString &tool, const QVariantMap &result, int id);
private:
    void post(const QString &tool, const QVariantMap &result, int id);
    int m_next = 0;
    QString m_dir = QStringLiteral("/usr/lib/omamobile-settings/backends");
};
