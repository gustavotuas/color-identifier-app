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
                Section {
                    Button {
                        selection = .all
                        VendorSelectionStorage.save(selection)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: selection == .all ? "checkmark.circle.fill" : "circle")
                            Text("All Colors")    // 👈 antes decía All Vendors
                        }
                    }

                    Button {
                        selection = .genericOnly
                        VendorSelectionStorage.save(selection)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: selection == .genericOnly ? "checkmark.circle.fill" : "circle")
                            Text("Generic")
                        }
                    }
                }

                ForEach(grouped, id: \.key) { letter, items in
                    Section(letter) {
                        ForEach(items) { row in
                            Button {
                                selection = .vendor(row.id)
                                VendorSelectionStorage.save(selection)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: (selection == .vendor(row.id)) ? "checkmark.circle.fill" : "circle")
                                    Text(row.name).lineLimit(1)
                                    Spacer()
                                    if let c = row.count {
                                        Text("\(c)").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Paints")
            .navigationBarTitleDisplayMode(.inline) // compacto
        }
    }
}
