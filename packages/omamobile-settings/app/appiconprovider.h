// SPDX-License-Identifier: MIT
#pragma once
#include <QIcon>
#include <QPixmap>
#include <QQuickImageProvider>
#include <QUrl>

// image://appicon/NAME: an app's themed icon (the Icon= name of its desktop entry), looked up only when an Apps
// page row or the app's detail shows it; the generic application icon when the theme has none, and
// Settings' own system icon when the theme lacks that too.
class AppIconProvider : public QQuickImageProvider {
public:
    AppIconProvider() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}
    QPixmap requestPixmap(const QString &encoded, QSize *size, const QSize &requested) override {
        // AppsPage encodes the name (encodeURIComponent)
        const QString id = QUrl::fromPercentEncoding(encoded.toUtf8());
        const int side = qBound(16, requested.width() > 0 ? requested.width() : 96, 256);
        QIcon icon = id.contains(QLatin1Char('/')) ? QIcon() : QIcon::fromTheme(id);
        if (icon.isNull()) icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
        if (icon.isNull()) icon = QIcon(QStringLiteral(":/icons/system.svg"));    // the theme has neither: Settings' own
        const QPixmap pixmap = icon.pixmap(side, side);
        if (size) *size = pixmap.size();
        return pixmap;
    }
};
