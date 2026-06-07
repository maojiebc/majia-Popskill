import Foundation

/// The 6 top-level destinations, mirroring the HTML prototype's information
/// architecture: 视图 (矩阵 / 修复中心) · 获取 (源·更新) · 创建 (新建能力 /
/// 组装套装) · 系统 (设置). Earlier maintenance-only screens (updates / backups
/// / idle / insights) folded away — pending updates now surface on 源·更新,
/// link health became 修复中心, and usage lives in the matrix + inspector.
enum SidebarSelection: String, Hashable, CaseIterable {
    case matrix
    case fix
    case sources
    case create
    case compose
    case settings

    var titleKey: String {
        switch self {
        case .matrix:   return "sidebar.matrix"
        case .fix:      return "sidebar.fix"
        case .sources:  return "sidebar.sources"
        case .create:   return "sidebar.create"
        case .compose:  return "sidebar.compose"
        case .settings: return "sidebar.settings"
        }
    }

    var symbolName: String {
        switch self {
        case .matrix:   return "square.grid.3x3.fill"
        case .fix:      return "wrench.and.screwdriver"
        case .sources:  return "shippingbox"
        case .create:   return "square.and.pencil"
        case .compose:  return "cube.box"
        case .settings: return "gearshape"
        }
    }

    /// Group the sidebar entry belongs to: 视图 / 获取 / 创建. Settings is its
    /// own singleton row pinned to the bottom.
    var group: SidebarGroup {
        switch self {
        case .matrix, .fix:     return .view
        case .sources:          return .acquire
        case .create, .compose: return .create
        case .settings:         return .pinned
        }
    }
}

enum SidebarGroup: String, CaseIterable {
    case view
    case acquire
    case create
    case pinned

    var titleKey: String? {
        switch self {
        case .view:    return "sidebar.section.view"
        case .acquire: return "sidebar.section.acquire"
        case .create:  return "sidebar.section.create"
        case .pinned:  return nil
        }
    }
}
