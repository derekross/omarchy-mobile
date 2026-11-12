// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#include "deviceinfocontroller.h"
#include <QFile>
#include <QStorageInfo>
#include <QSysInfo>
#include <QRegularExpression>
#include <QProcessEnvironment>
#include <cmath>
#include <QCoreApplication>
namespace {
QString readText(const QString &path,int limit=16384) {
    QFile file(path);if(!file.open(QIODevice::ReadOnly))return {};
    auto data=file.read(limit+1);if(data.size()>limit)return {};
    data.replace('\0',QByteArray());return QString::fromUtf8(data).trimmed();
}
QString osName() {
    const auto text=readText("/etc/os-release");
    const auto match=QRegularExpression("(?:^|\\n)PRETTY_NAME=(?:\"([^\"\\n]*)\"|([^\\n]*))(?:\\n|$)").match(text);
    return match.hasMatch()?(match.captured(1).isEmpty()?match.captured(2):match.captured(1)):QString();
}
}
QString DeviceInfoController::formatBytes(quint64 bytes) {
    if(!bytes)return {};
    const char *units[]={"B","KB","MB","GB","TB"};double value=double(bytes);int unit=0;
    while(value>=1000. && unit<4){value/=1000.;++unit;}
    return QString::number(value,'f',value>=100. || unit==0?0:1)+" "+units[unit];
}
DeviceInfoController::DeviceInfoController(bool preview,QObject *parent):QObject(parent),m_preview(preview) {
    m_timeout.setSingleShot(true);
    connect(&m_timeout,&QTimer::timeout,this,[this]{m_query.kill();});
    connect(&m_query,&QProcess::errorOccurred,this,[this](QProcess::ProcessError){m_timeout.stop();emit changed();});
    connect(&m_query,&QProcess::finished,this,[this](int code,QProcess::ExitStatus status){
        m_timeout.stop();const auto data=m_query.readAllStandardOutput();
        if((code==0 || code==1) && status==QProcess::NormalExit && data.size()<65536) {
            for(const auto &line:QString::fromUtf8(data).split('\n')) {
                const auto parts=line.split(' ',Qt::SkipEmptyParts);if(parts.size()!=2)continue;
                if(parts[0]=="omarchy")m_info["omarchyVersion"]=parts[1];
                else if(parts[0]=="omamobile-settings")m_info["settingsVersion"]=parts[1];
                else if(parts[0]=="omamobile-shell")m_info["shellVersion"]=parts[1];
            }
        }
        emit changed();
    });
}
DeviceInfoController::~DeviceInfoController() {
    // QProcess can emit finished while its destructor reaps a live query.
    // Disconnect before member teardown, while the timer and data still live.
    m_timeout.stop();
    m_query.disconnect(this);
    if (m_query.state() != QProcess::NotRunning) {
        m_query.kill();
        m_query.waitForFinished(1000);
    }
}
void DeviceInfoController::refresh() {
    if(busy())return;
    if(m_preview) {
        m_info={{"model","Mobile device"},{"manufacturer","Preview"},{"system","Arch Linux ARM"},
            {"omarchyVersion","Preview"},{"kernel","Linux · Preview"},{"architecture","aarch64"},
            {"memory","8.0 GB"},{"storageTotal","128 GB"},{"storageUsed","24.0 GB"},{"storageFree","104 GB"},
            {"storageFraction",.1875},{"storageKnown",true},{"settingsVersion",QCoreApplication::applicationVersion()},{"shellVersion","Preview"}};
        emit changed();return;
    }
    QString model=readText("/sys/firmware/devicetree/base/model",512);
    if(model.isEmpty())model=readText("/proc/device-tree/model",512);
    if(model.isEmpty())model=readText("/sys/devices/virtual/dmi/id/product_name",512);
    QString manufacturer=readText("/sys/devices/virtual/dmi/id/sys_vendor",256);
    if(manufacturer.isEmpty() && (model.startsWith("Google ") || model.startsWith("Pixel ")))manufacturer="Google";
    const auto memory=QRegularExpression("(?:^|\\n)MemTotal:\\s+([0-9]+) kB").match(readText("/proc/meminfo"));
    bool ok=false;const quint64 ram=memory.hasMatch()?memory.captured(1).toULongLong(&ok)*1024:0;
    m_info={{"model",model},{"manufacturer",manufacturer},{"system",osName()},
        {"kernel",QSysInfo::kernelVersion()},{"architecture",QSysInfo::currentCpuArchitecture()},
        {"memory",ok?formatBytes(ram):QString()},{"settingsVersion",QCoreApplication::applicationVersion()},{"storageKnown",false}};
    const QStorageInfo disk(QStringLiteral("/"));
    if(disk.isValid() && disk.isReady() && disk.bytesTotal()>0 && disk.bytesFree()>=0 && disk.bytesAvailable()>=0 && disk.bytesFree()<=disk.bytesTotal()) {
        const auto used=disk.bytesTotal()-disk.bytesFree();
        m_info["storageKnown"]=true;m_info["storageTotal"]=formatBytes(disk.bytesTotal());
        m_info["storageUsed"]=formatBytes(used);m_info["storageFree"]=formatBytes(disk.bytesAvailable());
        m_info["storageFraction"]=double(used)/double(disk.bytesTotal());
    }
    emit changed();auto env=QProcessEnvironment::systemEnvironment();env.insert("LC_ALL","C");
    m_query.setProcessEnvironment(env);m_query.start("/usr/bin/pacman",{"-Q","omarchy","omamobile-settings","omamobile-shell"});m_timeout.start(3500);emit changed();
}
