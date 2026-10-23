#pragma once

#include <QObject>
#include <QVariantList>
#include <QString>

class ProjectStore final : public QObject
{
    Q_OBJECT
public:
    explicit ProjectStore(QObject *parent = nullptr);

    Q_INVOKABLE QString savedTheme() const;
    Q_INVOKABLE int savedFontScale() const;
    Q_INVOKABLE void saveAppearance(const QString &theme, int fontScale);
    Q_INVOKABLE QVariantList recentProjects() const;
    Q_INVOKABLE bool createProject(const QString &path, const QString &name,
                                   const QString &resolution, int fps);
    Q_INVOKABLE bool openProject(const QString &path);
    Q_INVOKABLE bool removeRecentProject(const QString &path);
    Q_INVOKABLE QString lastError() const;

private:
    QString m_lastError;
    void rememberProject(const QString &path, const QString &name);
};
