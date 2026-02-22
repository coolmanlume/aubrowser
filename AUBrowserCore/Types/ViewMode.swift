// AUBrowserCore/Types/ViewMode.swift

import Foundation

public enum ViewMode: String, CaseIterable, Identifiable {
    case grid
    case list

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}
