// AUBrowserCore/Types/SortOrder.swift

import Foundation

public enum SortOrder: String, CaseIterable, Identifiable {
    case name
    case manufacturer
    case type
    case installDate
    case favorites

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .name:         return "Name"
        case .manufacturer: return "Manufacturer"
        case .type:         return "Type"
        case .installDate:  return "Date"
        case .favorites:    return "Favorites"
        }
    }

    /// Column used in ORDER BY clauses.
    /// Note: .favorites requires a LEFT JOIN with the userData table.
    public var sqlColumn: String {
        switch self {
        case .name:         return "plugin.name"
        case .manufacturer: return "plugin.manufacturer"
        case .type:         return "plugin.type"
        case .installDate:  return "plugin.installDate"
        case .favorites:    return "userData.isFavorite"
        }
    }
}
