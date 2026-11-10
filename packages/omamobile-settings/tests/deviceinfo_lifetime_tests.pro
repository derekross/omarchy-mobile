# SPDX-License-Identifier: MIT
QT += core testlib
CONFIG += testcase c++17 console no_include_pwd
TARGET = settings-deviceinfo-lifetime-tests
TEMPLATE = app
INCLUDEPATH += ../app
SOURCES += deviceinfo_lifetime_tests.cpp ../app/deviceinfocontroller.cpp
HEADERS += ../app/deviceinfocontroller.h
