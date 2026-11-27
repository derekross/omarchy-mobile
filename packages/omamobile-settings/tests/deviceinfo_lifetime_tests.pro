# SPDX-License-Identifier: MIT
QT += core testlib
CONFIG += testcase c++17 console no_include_pwd
TARGET = settings-deviceinfo-lifetime-tests
TEMPLATE = app
INCLUDEPATH += ../app
SOURCES += home_guard.cpp deviceinfo_lifetime_tests.cpp ../app/deviceinfocontroller.cpp
HEADERS += home_guard.h ../app/deviceinfocontroller.h
