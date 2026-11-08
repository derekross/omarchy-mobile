// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#include "backend.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSet>
#include <QTimer>
#include <utility>

Backend::Backend(QObject *parent) : QObject(parent) {
    QFile file(":/catalog.json");
    if (file.open(QIODevice::ReadOnly))
        m_catalog = QJsonDocument::fromJson(file.readAll()).object();
    m_themeFile = QDir::homePath() + "/.local/state/omarchy/current/theme/colors.toml";
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &Backend::reloadTheme);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &Backend::reloadTheme);
    connect(&m_roundingQuery, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        const auto raw = m_roundingQuery.readAllStandardOutput();
        m_roundingQuery.readAllStandardError();
        const auto value = QJsonDocument::fromJson(raw).object()["int"];
        if (code == 0 && status == QProcess::NormalExit && raw.size() <= 4096
            && value.isDouble() && value.toDouble() >= 0 && value.toDouble() == value.toInt()) {
            m_radius = value.toInt();
            emit themeChanged();
        }
    });
    reloadTheme();
    rebuild();
}
Backend::~Backend() {
    m_roundingQuery.disconnect(this);
    if (m_roundingQuery.state() != QProcess::NotRunning) {
        m_roundingQuery.kill();
        m_roundingQuery.waitForFinished(1000);
    }
}
QString Backend::title() const {
    return searching() ? tr("Search settings") : m_catalog[m_page].toObject()["title"].toString();
}
bool Backend::navigate(const QString &page) {
    if (!m_catalog.contains(page)) return false;
    if (page != m_page) m_history.append(m_page);
    m_page = page;
    m_query.clear();
    emit pageChanged();
    rebuild();
    return true;
}
bool Backend::Open(const QString &page) {
    if (!navigate(page)) return false;
    emit raiseRequested();
    return true;
}
void Backend::search(const QString &query) {
    m_query = query.trimmed().left(160);
    rebuild();
}
void Backend::back() {
    if (searching()) { search({}); return; }
    if (m_history.isEmpty()) { emit closeRequested(); return; }
    m_page = m_history.takeLast();
    emit pageChanged();
    rebuild();
}
void Backend::rebuild() {
    m_rows.clear();
    if (!searching()) {
        for (const auto &row : m_catalog[m_page].toObject()["rows"].toArray())
            m_rows.append(row.toObject().toVariantMap());
    } else {
        for (const auto &page : m_catalog) {
            for (const auto &value : page.toObject()["rows"].toArray()) {
                const auto row = value.toObject();
                if ((row["title"].toString() + " " + row["detail"].toString()).contains(m_query, Qt::CaseInsensitive))
                    m_rows.append(row.toVariantMap());
            }
        }
    }
    emit rowsChanged();
}
void Backend::activate(const QString &id) {
    // IDs resolve only through the currently displayed, source-owned catalog.
    for (const auto &value : std::as_const(m_rows)) {
        const auto row = value.toMap();
        if (row["id"].toString() == id) { navigate(row["page"].toString()); return; }
    }
}
QStringList Backend::catalogProblems() const {
    QStringList problems;
    if (!m_catalog.contains("root")) problems.append("Missing root page");
    for (auto page = m_catalog.begin(); page != m_catalog.end(); ++page) {
        QSet<QString> ids;
        for (const auto &value : page.value().toObject()["rows"].toArray()) {
            const auto row = value.toObject();
            const auto id = row["id"].toString();
            if (id.isEmpty() || ids.contains(id)) problems.append("Duplicate or empty row ID");
            ids.insert(id);
            if (row.contains("command") || row.contains("notice") || !m_catalog.contains(row["page"].toString()))
                problems.append("Unsupported route");
        }
    }
    return problems;
}
void Backend::reloadTheme() {
    QFile file(m_themeFile);
    if (file.open(QIODevice::ReadOnly) && file.size() <= 65536) {
        const auto content = QString::fromUtf8(file.readAll());
        auto color = [&content](const QString &key, QColor previous) {
            const auto match = QRegularExpression("(?:^|\\n)\\s*" + key + "\\s*=\\s*[\"'](#[0-9a-fA-F]{6})[\"']").match(content);
            return match.hasMatch() ? QColor(match.captured(1)) : previous;
        };
        m_background = color("background", m_background);
        m_foreground = color("foreground", m_foreground);
        m_accent = color("accent", m_accent);
        m_muted = QColor::fromRgbF(m_foreground.redF() * .78 + m_background.redF() * .22,
                                  m_foreground.greenF() * .78 + m_background.greenF() * .22,
                                  m_foreground.blueF() * .78 + m_background.blueF() * .22);
    }
    const auto existing = m_watcher.files() + m_watcher.directories();
    for (const auto &path : {m_themeFile, QFileInfo(m_themeFile).absolutePath(),
                            QDir::homePath() + "/.local/state/omarchy/current"})
        if (QFileInfo::exists(path) && !existing.contains(path)) m_watcher.addPath(path);
    if (m_roundingQuery.state() == QProcess::NotRunning) {
        const auto generation = ++m_roundingGeneration;
        m_roundingQuery.start("/usr/bin/hyprctl", {"-j", "getoption", "decoration:rounding"});
        QTimer::singleShot(1000, &m_roundingQuery, [this, generation] {
            if (generation == m_roundingGeneration && m_roundingQuery.state() != QProcess::NotRunning)
                m_roundingQuery.kill();
        });
    }
    emit themeChanged();
}
QString Backend::icon(const QString &name) const {
    if (!QRegularExpression("^[a-z-]{1,32}$").match(name).hasMatch()) return {};
    QFile file(":/icons/" + name + ".svg");
    if (!file.open(QIODevice::ReadOnly)) return {};
    auto svg = file.readAll();
    svg.replace("#9ece6a", m_accent.name().toUtf8());
    return "data:image/svg+xml;base64," + QString::fromLatin1(svg.toBase64());
}
