// Covers for the shelf, made off the main thread as QML asks for "image://cover/<path>", and the
// title, author and kind each cover was made with, for the lines under it. A book's title comes
// from the book, so a caption is filled in once its cover has been made.
#pragma once
#include <QHash>
#include <QMutex>
#include <QQuickImageProvider>
#include <QtQml/qqmlregistration.h>

class Faces : public QQuickImageProvider {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("The app makes the one set of faces.")
    /// Rises each time a caption is filled in, so bindings that read captions read them again.
    Q_PROPERTY(int revision READ revision NOTIFY captionsChanged)

public:
    Faces();

    /// `id` is the file's path; anything after a "?" (the file's modified time) only makes a changed file's URL new.
    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override;

    /// { title, author, label, sizeText } for a file whose cover has been made; empty until then.
    Q_INVOKABLE QVariantMap caption(const QString &path) const;
    int revision() const { return revision_; }

signals:
    void captionsChanged();

private:
    mutable QMutex lock_;
    QHash<QString, QVariantMap> captions_;
    int revision_ = 0;
};
