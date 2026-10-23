#include "ProjectStore.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>

ProjectStore::ProjectStore(QObject *parent) : QObject(parent) {}

QString ProjectStore::savedTheme() const
{
    QSettings settings;
    return settings.value("appearance/theme", "Tokyo Night").toString();
}

int ProjectStore::savedFontScale() const
{
    QSettings settings;
    return settings.value("appearance/fontScale", 100).toInt();
}

void ProjectStore::saveAppearance(const QString &theme, int fontScale)
{
    QSettings settings;
    settings.setValue("appearance/theme", theme);
    settings.setValue("appearance/fontScale", qBound(100, fontScale, 130));
    settings.sync();
}

QVariantList ProjectStore::recentProjects() const
{
    QSettings settings;
    const QStringList paths = settings.value("projects/recent").toStringList();
    QVariantList result;
    for (const QString &path : paths) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) continue;
        const QJsonObject project = QJsonDocument::fromJson(file.readAll()).object();
        if (project.value("format").toString() != "cutrix-project") continue;
        QVariantMap item;
        item.insert("path", path);
        item.insert("name", project.value("name").toString(QFileInfo(path).completeBaseName()));
        item.insert("resolution", project.value("resolution").toString("1920×1080"));
        item.insert("fps", project.value("fps").toInt(30));
        item.insert("modified", QFileInfo(path).lastModified().toString("yyyy-MM-dd HH:mm"));
        result.append(item);
    }
    return result;
}

bool ProjectStore::createProject(const QString &path, const QString &name,
                                 const QString &resolution, int fps)
{
    m_lastError.clear();
    if (path.trimmed().isEmpty() || name.trimmed().isEmpty()) {
        m_lastError = "Укажи имя проекта и путь сохранения.";
        return false;
    }
    const QFileInfo info(path);
    if (!QDir().mkpath(info.absolutePath())) {
        m_lastError = "Не удалось создать папку проекта.";
        return false;
    }
    QJsonObject project;
    project.insert("format", "cutrix-project");
    project.insert("version", 1);
    project.insert("name", name.trimmed());
    project.insert("resolution", resolution);
    project.insert("fps", fps);
    project.insert("created", QDateTime::currentDateTime().toString(Qt::ISODate));
    project.insert("media", QJsonArray{});
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        m_lastError = file.errorString();
        return false;
    }
    if (file.write(QJsonDocument(project).toJson(QJsonDocument::Indented)) < 0) {
        m_lastError = file.errorString();
        file.close();
        return false;
    }
    file.close();
    rememberProject(path, name.trimmed());
    return true;
}

bool ProjectStore::openProject(const QString &path)
{
    m_lastError.clear();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        m_lastError = file.errorString();
        return false;
    }
    const QJsonObject project = QJsonDocument::fromJson(file.readAll()).object();
    if (project.value("format").toString() != "cutrix-project") {
        m_lastError = "Этот файл не является проектом Cutrix.";
        return false;
    }
    rememberProject(path, project.value("name").toString(QFileInfo(path).completeBaseName()));
    return true;
}

QVariantList ProjectStore::projectMedia(const QString &path) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return {};
    const QJsonObject project = QJsonDocument::fromJson(file.readAll()).object();
    QVariantList result;
    const QJsonArray media = project.value("media").toArray();
    for (const QJsonValue &entry : media) {
        if (entry.isObject()) result.append(entry.toObject().toVariantMap());
    }
    return result;
}

bool ProjectStore::saveProjectMedia(const QString &path, const QVariantList &media)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        m_lastError = file.errorString();
        return false;
    }
    QJsonObject project = QJsonDocument::fromJson(file.readAll()).object();
    file.close();
    if (project.value("format").toString() != "cutrix-project") {
        m_lastError = "Этот файл не является проектом Cutrix.";
        return false;
    }
    QJsonArray array;
    for (const QVariant &item : media) array.append(QJsonObject::fromVariantMap(item.toMap()));
    project.insert("media", array);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        m_lastError = file.errorString();
        return false;
    }
    if (file.write(QJsonDocument(project).toJson(QJsonDocument::Indented)) < 0) {
        m_lastError = file.errorString();
        file.close();
        return false;
    }
    file.close();
    return true;
}

bool ProjectStore::removeRecentProject(const QString &path)
{
    QSettings settings;
    QStringList paths = settings.value("projects/recent").toStringList();
    paths.removeAll(path);
    settings.setValue("projects/recent", paths);
    settings.sync();
    return true;
}

QString ProjectStore::lastError() const { return m_lastError; }

void ProjectStore::rememberProject(const QString &path, const QString &name)
{
    Q_UNUSED(name);
    QSettings settings;
    QStringList paths = settings.value("projects/recent").toStringList();
    paths.removeAll(path);
    paths.prepend(path);
    while (paths.size() > 30) paths.removeLast();
    settings.setValue("projects/recent", paths);
    settings.sync();
}
