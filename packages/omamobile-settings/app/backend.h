// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#pragma once
#include <QObject>
#include <QColor>
#include <QJsonObject>
#include <QVariantList>
#include <QFileSystemWatcher>
#include <QPointer>
#include <QWindow>
#include <QProcess>

class Backend : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.omamobile.Settings")
    Q_PROPERTY(QVariantList rows READ rows NOTIFY rowsChanged)
    Q_PROPERTY(QString page READ page NOTIFY rowsChanged)
    Q_PROPERTY(QString title READ title NOTIFY rowsChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY rowsChanged)
    Q_PROPERTY(QColor background READ background NOTIFY themeChanged)
    Q_PROPERTY(QColor foreground READ foreground NOTIFY themeChanged)
    Q_PROPERTY(QColor accent READ accent NOTIFY themeChanged)
    Q_PROPERTY(QColor muted READ muted NOTIFY themeChanged)
    Q_PROPERTY(int radius READ radius NOTIFY themeChanged)
public:
    explicit Backend(QObject *parent = nullptr);
    ~Backend() override;
    QVariantList rows() const { return m_rows; }
    QString page() const { return m_page; }
    QString title() const;
    bool searching() const { return !m_query.isEmpty(); }
    QColor background() const { return m_background; }
    QColor foreground() const { return m_foreground; }
    QColor accent() const { return m_accent; }
    QColor muted() const { return m_muted; }
    int radius() const { return m_radius; }
    Q_INVOKABLE bool navigate(const QString &page);
    Q_INVOKABLE void search(const QString &query);
    Q_INVOKABLE void activate(const QString &id);
    Q_INVOKABLE void back();
    Q_INVOKABLE QString icon(const QString &name) const;
    Q_INVOKABLE QStringList catalogProblems() const;
    Q_SCRIPTABLE bool Open(const QString &page);
    Q_SCRIPTABLE QString SurfacePalette() const;
    void setSurfaceWindow(QWindow *window) { m_window = window; }
signals:
    void rowsChanged();
    void pageChanged();
    void themeChanged();
    void closeRequested();
    void raiseRequested();
private:
    void rebuild();
    void reloadTheme();
    QJsonObject m_catalog;
    QVariantList m_rows;
    QString m_page = "root", m_query, m_themeFile;
    QStringList m_history;
    QFileSystemWatcher m_watcher;
    QPointer<QWindow> m_window;
    QProcess m_roundingQuery;
    quint64 m_roundingGeneration = 0;
    int m_radius = 0;
    QColor m_background = QColor("#1a1b26"), m_foreground = QColor("#c0caf5"),
           m_accent = QColor("#9ece6a"), m_muted = QColor("#8b93b8");
};
