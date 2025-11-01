import SwiftUI

struct VendorRowModel: Identifiable {
    let id: CatalogID
    let name: String
    let count: Int?
    var initial: String { String(name.prefix(1)).uppercased() }
}

struct VendorListSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: CatalogSelection
    let candidates: [CatalogID]
    let catalogs: CatalogStore
    let isPro: Bool
    @EnvironmentObject var store: StoreVM

    private var rows: [VendorRowModel] {
        candidates
            .map { id in
                let count = catalogs.loaded[id]?.count
                return VendorRowModel(id: id, name: id.displayName, count: count)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var grouped: [(key: String, value: [VendorRowModel])] {
        Dictionary(grouping: rows, by: { $0.initial })
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - General (único default)
                Section {
                    Button {
                        selection = .genericOnly
                        VendorSelectionStorage.save(selection)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: selection == .genericOnly ? "checkmark.circle.fill" : "circle")
                            Text("general".localized)
                        }
                    }
                }

                // MARK: - Vendor Groups
                ForEach(grouped, id: \.key) { letter, items in
                    Section(letter) {
                        ForEach(items) { row in
                            Button {
                                if isPro {
                                    selection = .vendor(row.id)
                                    VendorSelectionStorage.save(selection)
                                    dismiss()
                                } else {
                                    withAnimation(.spring()) {
                                        store.showPaywall = true
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: (selection == .vendor(row.id)) ? "checkmark.circle.fill" : "circle")
                                    Text(row.name).lineLimit(1)
                                    Spacer()
                                    if let c = row.count {
                                        Text("\(c)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if !isPro {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("paints".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
