#pragma once

#include <QObject>
#include <QVariantMap>
#include <QString>

class MediaTools final : public QObject
{
    Q_OBJECT
public:
    explicit MediaTools(QObject *parent = nullptr);

    Q_INVOKABLE QVariantMap inspect(const QString &url) const;
    Q_INVOKABLE QString thumbnail(const QString &url) const;
    Q_INVOKABLE QString thumbnailAt(const QString &url, double seconds) const;
};
