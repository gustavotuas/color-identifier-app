import SwiftUI
import UIKit

struct SettingScreen: View {
    @EnvironmentObject var store: StoreVM
    @EnvironmentObject var theme: ThemeManager   // 👈 Nuevo

    // 🔹 Lee la versión automáticamente desde Info.plist
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            // MARK: - Get Pro (solo si NO es Pro)
            if !store.isPro {
                Section {
                    Button {
                        Haptic.tap()
                        store.showPaywall = true
                    } label: {
                        HStack(spacing: 15) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.yellow.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "crown.fill")
                                    .foregroundColor(.yellow)
                                    .font(.system(size: 18))
                            }
                            Text("Get Pro")
                                .foregroundColor(.primary)
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.system(size: 13))
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }

            // MARK: - Appearance
            Section(header: Text("Appearance")) {
                Picker("Theme", selection: $theme.selectedTheme) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            // MARK: - About
            Section(header: Text("About")) {
                SettingRow(icon: "info.circle.fill",
                           iconColor: .gray,
                           text: "Version: \(appVersion)",
                           link: nil)
                SettingRow(icon: "star.fill",
                           iconColor: .orange,
                           text: "Rate the app",
                           link: "https://apps.apple.com/app/idXXXXXXXXX?action=write-review")
            }

            // MARK: - Help
            Section(header: Text("Help")) {
                SettingRow(icon: "envelope.fill",
                           iconColor: .blue,
                           text: "Send feedback",
                           link: "mailto:getscodes@gmail.com")
            }

            // MARK: - Footer (Versión centrada)
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Colorit")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text(appVersion)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Settings")
        .sheet(isPresented: $store.showPaywall) {
            PaywallView().environmentObject(store)
        }
    }
}

// MARK: - SettingRow
struct SettingRow: View {
    let icon: String
    let iconColor: Color
    let text: String
    let link: String?

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 16))
            }

            Text(text)
                .foregroundColor(.primary)

            Spacer()

            if let link = link {
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.system(size: 13))
                    .onTapGesture {
                        Haptic.tap()
                        openLink(link)
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.tap()
            if let link = link { openLink(link) }
        }
    }

    private func openLink(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
