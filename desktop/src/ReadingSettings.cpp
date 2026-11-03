#include "ReadingSettings.h"

#include <QStringList>
#include <algorithm>

namespace ReadingSettings {

namespace {
QString oneOf(const QVariant &v, const QStringList &allowed) {
    const QString s = v.toString().toLower();
    return allowed.contains(s) ? s : QStringLiteral("normal");
}
}  // namespace

QVariantMap normalized(const QVariantMap &given) {
    bool ok = false;
    double size = given.value("size").toDouble(&ok);
    size = ok ? std::clamp(size, smallest, largest) : standard;
    const QString spacing = oneOf(given.value("spacing"), {"tight", "normal", "loose"});
    const QString width = oneOf(given.value("width"), {"narrow", "normal", "wide"});
    QString look = given.value("look").toString().toLower();
    if (!QStringList{"auto", "paper", "sepia", "night"}.contains(look)) look = "auto";
    const double lineHeight = spacing == "tight" ? 1.25 : spacing == "loose" ? 1.7 : 1.45;
    // The column grows with the text, so a line keeps about the same number of words.
    const double base = width == "narrow" ? 460 : width == "wide" ? 700 : 560;
    return {{"size", size}, {"spacing", spacing}, {"width", width}, {"look", look},
            {"lineHeight", lineHeight}, {"measure", base * size / standard}};
}

QJsonObject toJson(const QVariantMap &settings) {
    const QVariantMap s = normalized(settings);
    return {{"size", s["size"].toDouble()}, {"spacing", s["spacing"].toString()}, {"width", s["width"].toString()}, {"look", s["look"].toString()}};
}

}  // namespace ReadingSettings
