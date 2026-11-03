// How a book is set for reading: text size, line spacing, column width and look, as on the Mac,
// iPhone and Android. Kept per book in the library with the other apps' field names; a book opened
// for the first time starts with the reader's latest choice. QML sees them as a map.
#pragma once
#include <QJsonObject>
#include <QVariantMap>

namespace ReadingSettings {

inline constexpr double smallest = 13, largest = 28, standard = 17;

/// size, spacing ("tight", "normal", "loose"), width ("narrow", "normal", "wide") and look ("auto",
/// "paper", "sepia", "night"), with anything missing or unknown at its default; and, worked out
/// from them, lineHeight (a multiple of the size) and measure (the column's widest, in pixels).
QVariantMap normalized(const QVariantMap &given);

/// The four chosen fields, as the other apps write them.
QJsonObject toJson(const QVariantMap &settings);

}  // namespace ReadingSettings
