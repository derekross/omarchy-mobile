// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#pragma once
#include <QObject>
#include <QVariantMap>
#include <QProcess>
#include <QTimer>

class DeviceInfoController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap info READ info NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
public:
    explicit DeviceInfoController(bool preview = false, QObject *parent = nullptr);
    ~DeviceInfoController() override;
    QVariantMap info() const { return m_info; }
    bool busy() const { return m_query.state()!=QProcess::NotRunning; }
    Q_INVOKABLE void refresh();
    static QString formatBytes(quint64 bytes);
signals:
    void changed();
private:
    friend class DeviceInfoLifetimeTests;
    bool m_preview;
    QVariantMap m_info;
    QProcess m_query;
    QTimer m_timeout;
};
