// The desktop app's face of the C++ engine, as engine_jni.cpp is Android's and AFEngine.mm the
// Mac's: bytes and Qt strings in, Qt strings out. The work is in anyfile::detectKind and runOnBytes.
#pragma once
#include <QByteArray>
#include <QString>
#include <QStringList>

namespace Engine {

struct Result {
    bool ok = false;
    QString output;
    QString error;
};

/// "pdf", "epub", "markdown", "text" or "binary".
QString detectKind(const QByteArray &bytes, const QString &name);

Result run(const QString &command, const QStringList &args, const QByteArray &bytes, const QString &name, const QString &kind);

/// A field from the `meta` command's "Field: value" lines, such as "Title" or "Language"; empty when absent.
QString meta(const QString &field, const QString &output);

}  // namespace Engine
