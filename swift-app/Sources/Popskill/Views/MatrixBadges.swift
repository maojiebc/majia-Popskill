import SwiftUI

struct MatrixBrokenLinkBadge: View {
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        Label(localization.string("matrix.row.brokenLinkBadge"), systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 9.5, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.popStatusError)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.popStatusError.opacity(0.13), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .help(localization.string("matrix.row.brokenLinkHelp"))
    }
}
