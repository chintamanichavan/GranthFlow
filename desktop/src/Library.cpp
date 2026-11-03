#include "Library.h"

#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <algorithm>

#include "Engine.h"
#include "ReadingSettings.h"

QString LibraryEntry::name() const { return QFileInfo(path).fileName(); }

QString LibraryEntry::stem() const {
    const QString base = QFileInfo(path).completeBaseName();
    return base.isEmpty() ? name() : base;
}

QString LibraryEntry::progressText() const {
    if (position < 0 || total <= 0) return {};
    if (kind == "epub") return position >= total ? QStringLiteral("Finished") : QStringLiteral("Chapter %1 of %2").arg(position).arg(total);
    if (kind == "pdf") return position + 1 >= total ? QStringLiteral("Finished") : QStringLiteral("Page %1 of %2").arg(position + 1).arg(total);
    return {};
}

double LibraryEntry::progress() const {
    if (position < 0 || total <= 0) return -1;
    return kind == "pdf" ? (position + 1.0) / total : double(position) / total;
}

Library::Library(const QString &file, QObject *parent)
    : QAbstractListModel(parent), file_(file), preferences_(QFileInfo(file).absolutePath() + "/preferences.ini", QSettings::IniFormat) {
    load();
    changed();
}

int Library::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : int(shown_.size()); }

QVariant Library::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= shown_.size()) return {};
    const LibraryEntry &e = shown_[index.row()];
    switch (role) {
    case PathRole: return e.path;
    case NameRole: return e.name();
    case StemRole: return e.stem();
    case KindRole: return e.kind;
    case ProgressRole: return e.progress();
    case ProgressTextRole: return e.progressText();
    case ModifiedRole: return QFileInfo(e.path).lastModified().toMSecsSinceEpoch();
    }
    return {};
}

QHash<int, QByteArray> Library::roleNames() const {
    return {{PathRole, "path"}, {NameRole, "name"}, {StemRole, "stem"}, {KindRole, "kind"},
            {ProgressRole, "progress"}, {ProgressTextRole, "progressText"}, {ModifiedRole, "modified"}};
}

const LibraryEntry *Library::entry(const QString &path) const {
    auto it = std::find_if(entries_.begin(), entries_.end(), [&](const LibraryEntry &e) { return e.path == path; });
    return it == entries_.end() ? nullptr : &*it;
}

int Library::position(const QString &path) const {
    const LibraryEntry *e = entry(path);
    return e ? e->position : -1;
}

QStringList Library::add(const QList<QUrl> &urls) {
    // The files among the urls, with folders walked for the files inside them; hidden ones are skipped.
    QStringList files;
    for (const QUrl &url : urls) {
        const QFileInfo info(url.toLocalFile());
        if (info.isFile()) files << info.absoluteFilePath();
        else if (info.isDir()) {
            QDirIterator walk(info.absoluteFilePath(), QDir::Files, QDirIterator::Subdirectories);
            while (walk.hasNext() && files.size() < mostFromOneDrop) files << walk.next();
        }
        if (files.size() >= mostFromOneDrop) break;
    }
    const QDateTime now = QDateTime::currentDateTimeUtc();
    QStringList added;
    for (const QString &path : files) {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly)) continue;
        // The first 64 KB is enough for magic bytes, an EPUB's mimetype entry and a look at whether it is text.
        const QString kind = Engine::detectKind(f.read(1 << 16), QFileInfo(path).fileName());
        auto it = std::find_if(entries_.begin(), entries_.end(), [&](const LibraryEntry &e) { return e.path == path; });
        if (it != entries_.end()) { it->opened = now; it->kind = kind; }
        else entries_.append({path, kind, now, -1, -1, true});
        added << path;
    }
    if (!added.isEmpty()) { save(); changed(); }
    return added;
}

void Library::recordOpened(const QString &path, const QString &kind) {
    auto it = std::find_if(entries_.begin(), entries_.end(), [&](const LibraryEntry &e) { return e.path == path; });
    if (it == entries_.end()) entries_.append({path, kind, QDateTime::currentDateTimeUtc()});
    else { it->opened = QDateTime::currentDateTimeUtc(); it->kind = kind; it->unopened = false; }
    save();
    changed();
}

void Library::recordPosition(const QString &path, int position, int total) {
    auto it = std::find_if(entries_.begin(), entries_.end(), [&](const LibraryEntry &e) { return e.path == path; });
    if (it == entries_.end() || (it->position == position && it->total == total)) return;
    it->position = position;
    it->total = total;
    save();
    // The order is unchanged: only this row's progress moves.
    for (int i = 0; i < shown_.size(); ++i) {
        if (shown_[i].path != path) continue;
        shown_[i] = *it;
        emit dataChanged(index(i), index(i), {ProgressRole, ProgressTextRole});
    }
}

QVariantMap Library::settings(const QString &path) const {
    const LibraryEntry *e = entry(path);
    if (e && !e->settings.isEmpty()) return ReadingSettings::normalized(e->settings.toVariantMap());
    return ReadingSettings::normalized(preferences_.value("readingSettings").toMap());
}

QVariantMap Library::recordSettings(const QString &path, const QVariantMap &settings) {
    const QJsonObject kept = ReadingSettings::toJson(settings);
    preferences_.setValue("readingSettings", kept.toVariantMap());
    auto it = std::find_if(entries_.begin(), entries_.end(), [&](const LibraryEntry &e) { return e.path == path; });
    if (it != entries_.end() && it->settings != kept) {
        it->settings = kept;
        save();
    }
    return ReadingSettings::normalized(kept.toVariantMap());
}

void Library::forget(const QString &path) {
    entries_.removeIf([&](const LibraryEntry &e) { return e.path == path; });
    save();
    changed();
}

void Library::changed() {
    const int before = int(shown_.size());
    beginResetModel();
    shown_.clear();
    for (const LibraryEntry &e : entries_) if (QFileInfo::exists(e.path)) shown_ << e;
    std::stable_sort(shown_.begin(), shown_.end(), [](const LibraryEntry &a, const LibraryEntry &b) { return a.opened > b.opened; });
    endResetModel();
    if (shown_.size() != before) emit countChanged();
}

void Library::load() {
    QFile f(file_);
    if (!f.open(QIODevice::ReadOnly)) return;
    for (const QJsonValue &v : QJsonDocument::fromJson(f.readAll()).array()) {
        const QJsonObject o = v.toObject();
        LibraryEntry e{o["path"].toString(), o["kind"].toString(), QDateTime::fromString(o["opened"].toString(), Qt::ISODate)};
        if (e.path.isEmpty() || !e.opened.isValid()) continue;
        e.position = o.contains("position") ? o["position"].toInt() : -1;
        e.total = o.contains("total") ? o["total"].toInt() : -1;
        e.unopened = o["unopened"].toBool();
        e.settings = o["settings"].toObject();
        entries_ << e;
    }
}

void Library::save() const {
    QList<LibraryEntry> sorted = entries_;
    std::sort(sorted.begin(), sorted.end(), [](const LibraryEntry &a, const LibraryEntry &b) { return a.path < b.path; });
    QJsonArray array;
    for (const LibraryEntry &e : sorted) {
        QJsonObject o{{"path", e.path}, {"kind", e.kind}, {"opened", e.opened.toUTC().toString(Qt::ISODate)}};
        if (e.position >= 0) o["position"] = e.position;
        if (e.total >= 0) o["total"] = e.total;
        if (e.unopened) o["unopened"] = true;
        if (!e.settings.isEmpty()) o["settings"] = e.settings;
        array << o;
    }
    QDir().mkpath(QFileInfo(file_).absolutePath());
    QSaveFile out(file_);                                   // written whole, then moved into place
    if (!out.open(QIODevice::WriteOnly)) return;
    out.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    out.commit();
}
