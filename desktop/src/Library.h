// What the library remembers: each file, when it was opened, and where reading stopped. Files stay
// where they are, as on the Mac; the shelf only refers to them. Kept as pretty-printed JSON with the
// same fields as the Mac, iPhone and Android apps' library.json.
#pragma once
#include <QAbstractListModel>
#include <QDateTime>
#include <QJsonObject>
#include <QSettings>
#include <QList>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

struct LibraryEntry {
    QString path;
    QString kind;
    QDateTime opened;
    /// Where reading stopped: a chapter number for EPUB, a page index for PDF; -1 when not yet known.
    int position = -1;
    int total = -1;
    /// On the shelf but not opened yet.
    bool unopened = false;
    /// How this book is set for reading; empty until the reader changes it.
    QJsonObject settings;

    QString name() const;
    /// The name without its extension, as a title for files that carry none.
    QString stem() const;
    /// "Chapter 4 of 135", "Page 3 of 12", "Finished", or empty when there is nothing to say.
    QString progressText() const;
    /// 0..1 through the file, or -1 when unknown.
    double progress() const;
};

class Library : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("The app makes the one library.")
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role { PathRole = Qt::UserRole + 1, NameRole, StemRole, KindRole, ProgressRole, ProgressTextRole, ModifiedRole };

    explicit Library(const QString &file, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /// Most recent first, leaving out files that have gone.
    const QList<LibraryEntry> &recent() const { return shown_; }
    const LibraryEntry *entry(const QString &path) const;

    /// Puts files on the shelf, walking folders for the files inside; returns the files' paths.
    /// Ones already there move to the front.
    Q_INVOKABLE QStringList add(const QList<QUrl> &urls);
    Q_INVOKABLE void recordOpened(const QString &path, const QString &kind);
    Q_INVOKABLE void recordPosition(const QString &path, int position, int total);
    /// Where reading stopped in the file, or -1.
    Q_INVOKABLE int position(const QString &path) const;
    /// How the book is set for reading (see ReadingSettings): its own settings, else the latest chosen for any book.
    Q_INVOKABLE QVariantMap settings(const QString &path) const;
    /// Keeps the book's new settings, and makes them the ones the next new book starts with; returns them normalized.
    Q_INVOKABLE QVariantMap recordSettings(const QString &path, const QVariantMap &settings);
    /// Takes a file off the shelf; the file itself stays where it is.
    Q_INVOKABLE void forget(const QString &path);

    /// A folder dropped by mistake on a whole disk should not fill the library; this is plenty for a real one.
    static constexpr int mostFromOneDrop = 500;

signals:
    void countChanged();

private:
    void changed();
    void load();
    void save() const;

    QString file_;
    /// Beside the library: the latest reading settings chosen.
    QSettings preferences_;
    QList<LibraryEntry> entries_;
    QList<LibraryEntry> shown_;
};
