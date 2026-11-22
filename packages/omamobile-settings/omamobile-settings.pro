# SPDX-License-Identifier: MIT
QT += core gui qml quick quickcontrols2 dbus svg
CONFIG += c++17 release no_include_pwd
TEMPLATE = app
TARGET = omamobile-settings
INCLUDEPATH += $$PWD/app
HEADERS += app/backend.h app/deviceinfocontroller.h app/actionrunner.h
SOURCES += app/main.cpp app/backend.cpp app/deviceinfocontroller.cpp app/actionrunner.cpp
RESOURCES += app/resources.qrc
include(version.pri)

HEADERS += app/themetokens.h
