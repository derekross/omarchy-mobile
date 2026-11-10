# SPDX-License-Identifier: MIT
SETTINGS_VERSION = $$cat($$PWD/version, lines)
isEmpty(SETTINGS_VERSION): error(Missing Settings package version)
DEFINES += OMAMOBILE_SETTINGS_VERSION=\\\"$$SETTINGS_VERSION\\\"
