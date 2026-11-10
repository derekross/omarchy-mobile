// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
#pragma once
#include <QColor>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QVariantMap>
#include <QStringList>
#include <cmath>

// Pure Qt adapter for Omarchy colors.toml and shell.toml scalar theme tokens.
// Navigation, touch targets and physical safe areas are not theme inputs.
namespace SettingsTheme {
inline QVariantMap scalars(const QByteArray &bytes) {
    QVariantMap values;
    if (bytes.size() > 262144 || bytes.contains('\0')) return values;
    QString section;
    for (QString line : QString::fromUtf8(bytes).split('\n')) {
        // A TOML comment begins outside a quoted scalar, never inside a color.
        QChar quote;
        bool escaped = false;
        for (int i = 0; i < line.size(); ++i) {
            const auto ch = line[i];
            if (escaped) { escaped = false; continue; }
            if (!quote.isNull() && quote == '"' && ch == '\\') { escaped = true; continue; }
            if (ch == quote) quote = QChar();
            else if (quote.isNull() && (ch == '"' || ch == '\'')) quote = ch;
            else if (quote.isNull() && ch == '#') { line.truncate(i); break; }
        }
        line = line.trimmed();
        if (line.isEmpty()) continue;
        const auto group = QRegularExpression("^\\[([A-Za-z0-9_-]+)\\]$").match(line);
        if (group.hasMatch()) { section = group.captured(1); continue; }
        const auto assignment = QRegularExpression("^([A-Za-z0-9_-]+)\\s*=\\s*(.+)$").match(line);
        if (!assignment.hasMatch()) continue;
        const auto key = (section.isEmpty() ? QString() : section + '.') + assignment.captured(1);
        const auto raw = assignment.captured(2).trimmed();
        QVariant value;
        if (raw.startsWith('"')) {
            const auto parsed = QJsonDocument::fromJson(('[' + raw + ']').toUtf8());
            if (parsed.isArray() && parsed.array().size() == 1 && parsed.array()[0].isString())
                value = parsed.array()[0].toString();
        } else if (raw.size() >= 2 && raw.startsWith('\'') && raw.endsWith('\'')) {
            value = raw.mid(1, raw.size() - 2);
        } else if (raw == "true" || raw == "false") value = raw == "true";
        else if (QRegularExpression("^[+-]?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)$").match(raw).hasMatch()) {
            bool ok = false;
            const auto number = raw.toDouble(&ok);
            if (ok && std::isfinite(number)) value = number;
        }
        if (value.isValid()) values.insert(key, value);
    }
    return values;
}
inline double number(const QVariantMap &values, const QString &key, double fallback,
                     double minimum, double maximum) {
    const auto value = values.value(key);
    if (value.metaType().id() != QMetaType::Double) return fallback;
    const auto result = value.toDouble();
    return std::isfinite(result) && result >= minimum && result <= maximum ? result : fallback;
}
inline QColor color(const QVariantMap &values, QString key, const QColor &fallback) {
    QStringList seen;
    for (int i = 0; i < 12; ++i) {
        if (seen.contains(key)) return fallback;
        seen.append(key);
        const auto value = values.value(key);
        if (value.metaType().id() != QMetaType::QString) return fallback;
        const auto text = value.toString().trimmed();
        if (QRegularExpression("^#[0-9a-fA-F]{6}$").match(text).hasMatch()) return QColor(text);
        // References use the same role/section.key vocabulary as shell.toml.
        key = text == "text" ? QStringLiteral("foreground") : text;
    }
    return fallback;
}
inline QColor alpha(QColor color, double opacity) { color.setAlphaF(opacity); return color; }
inline QColor mix(const QColor &a, const QColor &b, double amount) {
    return QColor::fromRgbF(a.redF() * amount + b.redF() * (1 - amount),
                           a.greenF() * amount + b.greenF() * (1 - amount),
                           a.blueF() * amount + b.blueF() * (1 - amount));
}
inline QColor knownColor(const QVariantMap &previous, const QString &key, const QColor &fallback) {
    const auto value=previous.value(key);
    return value.metaType().id()==QMetaType::QColor && value.value<QColor>().isValid()
        ? value.value<QColor>() : fallback;
}
inline QVariantMap tokens(const QByteArray &colors, const QByteArray &shell,
                          const QString &systemFamily = QStringLiteral("monospace"),
                          const QVariantMap &previous = {}) {
    auto values = scalars(colors);
    const auto overrides = scalars(shell);
    for (auto it = overrides.begin(); it != overrides.end(); ++it) values[it.key()] = it.value();
    const QColor background = alpha(color(values, "menu.background", color(values, "background", knownColor(previous,"background",QColor("#101315")))),
                                    number(values, "menu.background-alpha", 1, 0, 1));
    const QColor foreground = color(values, "menu.text", color(values, "foreground", knownColor(previous,"foreground",QColor("#cacccc"))));
    const QColor accent = color(values, "accent", knownColor(previous,"accent",foreground));
    const QColor muted = mix(foreground, background, .64);
    QVariantMap out{{"background", background}, {"foreground", foreground}, {"accent", accent},
                    {"muted", color(values, "muted", color(values, "color8", muted))},
                    {"error", color(values, "red", QColor("#a55555"))},
                    {"warning", color(values, "yellow", accent)},
                    {"success", color(values, "green", accent)},
                    {"surface", color(values, "lighter_background", mix(foreground, background, .045))},
                    {"raisedSurface", color(values, "popups.background", background)},
                    {"separator", alpha(foreground, .10)},
                    {"scrim", alpha(color(values, "menu.scrim", background), number(values, "menu.scrim-alpha", .5, 0, 1))},
                    {"disabledForeground", mix(foreground, background, .38)}};
    // Omarchy resolves the system monospace fontconfig alias and optional
    // OMARCHY_MENU_FONT override; [font] supplies size roles, not a new family.
    out["fontFamily"] = systemFamily;
    out["fontScale"] = number(values, "font.base-size", 12, 1, 96) / 12.0;
    // Optional explicit type-role pins use Omarchy's existing [font] names.
    for (const QString &role : {QStringLiteral("caption"), QStringLiteral("body-small"), QStringLiteral("body"),
                               QStringLiteral("subtitle"), QStringLiteral("title"), QStringLiteral("heading"),
                               QStringLiteral("display"), QStringLiteral("display-large")})
        out["font." + role] = number(values, "font." + role, 0, 1, 192);
    const QStringList states{"normal", "hover-cursor", "focus", "selected", "pressed"};
    const QList<double> fills{.04, .08, .08, .18, .22};
    for (int i = 0; i < states.size(); ++i) {
        const auto state = states[i];
        const auto prefix = "controls." + state;
        const auto fill = color(values, prefix + "-color", foreground);
        out[state + "Fill"] = alpha(fill, number(values, prefix + "-fill-alpha", fills[i], 0, 1));
        out[state + "Border"] = alpha(color(values, prefix + "-border", foreground),
                                       number(values, prefix + "-border-alpha", i == 0 ? .4 : .25, 0, 1));
        out[state + "BorderWidth"] = number(values, prefix + "-border-width", i == 3 ? 0 : 1, 0, 4);
    }
    out["selection"] = alpha(color(values, "controls.selection-color", accent),
                              number(values, "controls.selection-fill-alpha", .35, 0, 1));
    return out;
}
}
