#include "Faces.h"

#include <QLocale>
#include <QFile>
#include <QFileInfo>
#include <QMetaObject>
#include <QUrl>

#include "Cover.h"
#include "Engine.h"

Faces::Faces() : QQuickImageProvider(QQuickImageProvider::Image) {}

QImage Faces::requestImage(const QString &id, QSize *size, const QSize &requested) {
    const QString path = QUrl::fromPercentEncoding(id.section('?', 0, 0).toUtf8());
    QFile f(path);
    const QString kind = f.open(QIODevice::ReadOnly) ? Engine::detectKind(f.read(1 << 16), QFileInfo(path).fileName()) : QString();
    f.close();
    const Face face = Cover::face(path, kind);
    {
        QMutexLocker held(&lock_);
        captions_[path] = QVariantMap{{"title", face.title}, {"author", face.author}, {"label", face.label},
                                      {"sizeText", QLocale().formattedDataSize(face.size, 1, QLocale::DataSizeSIFormat)}};
    }
    // Made on a loader thread; the caption's readers live on the main one.
    QMetaObject::invokeMethod(this, [this] { ++revision_; emit captionsChanged(); }, Qt::QueuedConnection);
    QImage image = face.image;
    if (image.isNull()) {                                          // a file that has gone: a quiet placeholder
        image = QImage(Cover::width * Cover::scale, Cover::height * Cover::scale, QImage::Format_ARGB32_Premultiplied);
        image.fill(QColor(128, 128, 128, 31));
    }
    if (requested.isValid() && !requested.isEmpty()) image = image.scaled(requested, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    *size = image.size();
    return image;
}

QVariantMap Faces::caption(const QString &path) const {
    QMutexLocker held(&lock_);
    return captions_.value(path);
}
