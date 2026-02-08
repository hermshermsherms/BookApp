import SwiftUI

// MARK: - View Extensions

extension View {
    func bookishCard() -> some View {
        self
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cornerRadiusMedium)
            .shadow(color: Theme.espresso.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    func primaryButtonStyle() -> some View {
        self
            .font(Theme.body(16).bold())
            .foregroundColor(.white)
            .padding(.horizontal, Theme.paddingLarge)
            .padding(.vertical, Theme.paddingMedium)
            .background(Theme.accent)
            .cornerRadius(Theme.cornerRadiusMedium)
    }
}

// MARK: - String Extensions

extension String {
    var truncated: String {
        if self.count > 150 {
            return String(self.prefix(147)) + "..."
        }
        return self
    }
}

// MARK: - Date Extensions

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
