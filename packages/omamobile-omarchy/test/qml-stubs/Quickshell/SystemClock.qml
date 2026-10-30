// SPDX-License-Identifier: MIT
import QtQuick

// Stand-in for Quickshell's SystemClock: the time when it was made, or what
// the test sets.
QtObject {
  enum Precision { Hours, Minutes, Seconds }
  property int precision: SystemClock.Seconds
  property date date: new Date()
}
