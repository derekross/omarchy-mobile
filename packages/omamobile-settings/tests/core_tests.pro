# SPDX-License-Identifier: MIT
QT += core gui testlib qml quick quickcontrols2 svg
CONFIG += testcase c++17 console no_include_pwd
TARGET = settings-core-tests
TEMPLATE = app
INCLUDEPATH += ../app
SOURCES += core_tests.cpp ../app/actionrunner.cpp ../app/backend.cpp ../app/deviceinfocontroller.cpp
HEADERS += ../app/actionrunner.h ../app/backend.h ../app/deviceinfocontroller.h
RESOURCES += ../app/resources.qrc
