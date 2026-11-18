// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick
QtObject {
    readonly property var tokens: typeof backend === "undefined" ? ({}) : backend.themeTokens
    function token(name, fallback) { return tokens[name] === undefined ? fallback : tokens[name] }
    readonly property color background: token("background", "#101315")
    readonly property color foreground: token("foreground", "#cacccc")
    readonly property color accent: token("accent", foreground)
    readonly property color muted: token("muted", "#8c9090")
    readonly property color error: token("error", "#a55555")
    readonly property color warning: token("warning", accent)
    readonly property color success: token("success", accent)
    readonly property color surface: token("surface", Qt.rgba(foreground.r, foreground.g, foreground.b, .045))
    readonly property color raisedSurface: token("raisedSurface", background)
    readonly property color separator: token("separator", Qt.rgba(foreground.r, foreground.g, foreground.b, .10))
    readonly property color scrim: token("scrim", Qt.rgba(background.r, background.g, background.b, .5))
    readonly property color disabledForeground: token("disabledForeground", muted)
    readonly property color selection: token("selection", Qt.rgba(accent.r, accent.g, accent.b, .35))
    readonly property string fontFamily: token("fontFamily", "monospace")
    readonly property real cornerRadius: typeof backend === "undefined" ? 0 : backend.radius
    function radius(width, height) { return Math.min(Math.max(0, cornerRadius), width / 2, height / 2) }
    function fontPx(reference) {
        const roles = ({10:"caption", 12:"body-small", 14:"body-small", 15:"body", 16:"subtitle", 18:"title", 22:"heading", 24:"display", 34:"display-large"})
        const pinned = token("font." + roles[reference], 0)
        return Math.max(1, Math.round(pinned > 0 ? pinned : reference * token("fontScale", 1)))
    }
    function fill(state) {
        const alpha = ({normal:.04, "hover-cursor":.08, focus:.08, selected:.18, pressed:.22})
        return token(state + "Fill", Qt.rgba(foreground.r, foreground.g, foreground.b, alpha[state] || .04))
    }
    function border(state) { return token(state + "Border", Qt.rgba(foreground.r, foreground.g, foreground.b, .4)) }
    function borderWidth(state) { return token(state + "BorderWidth", state === "selected" ? 0 : 1) }
}
