# SPDX-License-Identifier: MIT
QT += core gui qml quick quickcontrols2 dbus svg
CONFIG += c++17 release no_include_pwd
TEMPLATE = app
TARGET = settings-session-test-app
INCLUDEPATH += ../app
DEFINES += OMAMOBILE_SETTINGS_TEST_DEVICE_INFO
HEADERS += ../app/backend.h ../app/deviceinfocontroller.h ../app/actionrunner.h
SOURCES += ../app/main.cpp ../app/backend.cpp ../app/deviceinfocontroller.cpp ../app/actionrunner.cpp
RESOURCES += ../app/resources.qrc
include(../version.pri)
