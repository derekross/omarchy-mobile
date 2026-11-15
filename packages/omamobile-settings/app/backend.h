// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#pragma once
#include <QObject>
#include <QColor>
#include <QJsonObject>
#include <QVariantList>
#include <QFileSystemWatcher>
#include <QProcess>
#include "themetokens.h"

class Backend : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.omamobile.Settings")
    Q_PROPERTY(QVariantList rows READ rows NOTIFY rowsChanged)
    Q_PROPERTY(QString page READ page NOTIFY rowsChanged)
    Q_PROPERTY(QString title READ title NOTIFY rowsChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY rowsChanged)
    Q_PROPERTY(QVariantMap themeTokens READ themeTokens NOTIFY themeChanged)
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
    QVariantMap themeTokens() const { return m_themeTokens; }
    QColor background() const { return m_background; }
    QColor foreground() const { return m_foreground; }
    QColor accent() const { return m_accent; }
    QColor muted() const { return m_muted; }
    int radius() const { return m_radius; }
    Q_INVOKABLE bool navigate(const QString &page);
    Q_INVOKABLE void search(const QString &query);
    Q_INVOKABLE void activate(const QString &id);
    // Back, as the shell's edge swipe sends it (Escape): out of a search,
    // then up one page, and at the top level the home screen.
    Q_INVOKABLE void back();
    // The command that shows the home screen (omamobile-shell's); the tests
    // name a stand-in, or nothing.
    void setHomeCommand(const QStringList &command) { m_homeCommand = command; }
    Q_INVOKABLE QString icon(const QString &name) const;
    Q_INVOKABLE QStringList catalogProblems() const;
    Q_SCRIPTABLE bool Open(const QString &page);
signals:
    void rowsChanged();
    void pageChanged();
    void themeChanged();
    void homeRequested();
    void raiseRequested();
private:
    void rebuild();
    void reloadTheme();
    QJsonObject m_catalog;
    QVariantList m_rows;
    QString m_page = "root", m_query, m_themeFile;
    QStringList m_history;
    QStringList m_homeCommand{"omamobile-home"};
    QFileSystemWatcher m_watcher;
    QProcess m_roundingQuery;
    quint64 m_roundingGeneration = 0;
    int m_radius = 0;
    QVariantMap m_themeTokens = SettingsTheme::tokens({}, {});
    QColor m_background = m_themeTokens["background"].value<QColor>(),
           m_foreground = m_themeTokens["foreground"].value<QColor>(),
           m_accent = m_themeTokens["accent"].value<QColor>(),
           m_muted = m_themeTokens["muted"].value<QColor>();
};
