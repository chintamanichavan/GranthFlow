#include "Engine.h"

#include "core/engine.hpp"

namespace Engine {

static std::string utf8(const QString &s) { return s.toStdString(); }

QString detectKind(const QByteArray &bytes, const QString &name) {
    return QString::fromStdString(anyfile::detectKind(bytes.toStdString(), utf8(name)));
}

Result run(const QString &command, const QStringList &args, const QByteArray &bytes, const QString &name, const QString &kind) {
    std::vector<std::string> argv;
    for (const QString &a : args) argv.push_back(utf8(a));
    const anyfile::RunResult r = anyfile::runOnBytes(utf8(command), argv, bytes.toStdString(), utf8(name), utf8(kind));
    const QByteArray out = QByteArray::fromStdString(r.output);
    return {r.status == anyfile::Status::Ok, QString::fromUtf8(out), out, QString::fromStdString(r.error)};
}

QString meta(const QString &field, const QString &output) {
    for (const QString &line : output.split('\n')) {
        const qsizetype colon = line.indexOf(':');
        if (colon > 0 && line.left(colon).trimmed().compare(field, Qt::CaseInsensitive) == 0) return line.mid(colon + 1).trimmed();
    }
    return {};
}

}  // namespace Engine
