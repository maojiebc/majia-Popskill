import Foundation

/// The 8 top-level destinations in the v0.3 sidebar. Organized into 3 sections
/// (操控台 / 来源 / 维护) plus a Settings entry at the bottom — mirroring the
/// HTML prototype's IA decision: separate "content surface" (matrix) from
/// "tooling" (maintenance) from "preferences" (settings).
enum SidebarSelection: String, Hashable, CaseIterable {
    case matrix
    case sources
    case updates
    case backups
    case idle
    case insights
    case health
    case settings

    var titleKey: String {
        switch self {
        case .matrix:   return "sidebar.matrix"
        case .sources:  return "sidebar.sources"
        case .updates:  return "sidebar.updates"
        case .backups:  return "sidebar.backups"
        case .idle:     return "sidebar.idle"
        case .insights: return "sidebar.insights"
        case .health:   return "sidebar.health"
        case .settings: return "sidebar.settings"
        }
    }

    var symbolName: String {
        switch self {
        case .matrix:   return "square.grid.3x3.fill"
        case .sources:  return "shippingbox"
        case .updates:  return "arrow.down.circle"
        case .backups:  return "clock.arrow.circlepath"
        case .idle:     return "pause.circle"
        case .insights: return "chart.bar"
        case .health:   return "checkmark.shield"
        case .settings: return "gearshape"
        }
    }

    /// Group the sidebar entry belongs to: control / sources / maintenance.
    /// Settings is its own singleton row pinned to the bottom.
    var group: SidebarGroup {
        switch self {
        case .matrix: return .control
        case .sources: return .sources
        case .updates, .backups, .idle, .insights, .health: return .maintenance
        case .settings: return .pinned
        }
    }
}

enum SidebarGroup: String, CaseIterable {
    case control
    case sources
    case maintenance
    case pinned

    var titleKey: String? {
        switch self {
        case .control:     return "sidebar.section.control"
        case .sources:     return "sidebar.section.sources"
        case .maintenance: return "sidebar.section.maintenance"
        case .pinned:      return nil
        }
    }
}
