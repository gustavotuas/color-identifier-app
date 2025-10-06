import SwiftUI

struct BrowseScreen: View {
    @EnvironmentObject var catalog: Catalog
    @State private var query = ""
    var body: some View {
        List(filtered){ c in
            HStack{
                RoundedRectangle(cornerRadius:8).fill(Color(hexToRGB(c.hex).uiColor)).frame(width:28, height:28)
                VStack(alignment:.leading){
                    Text(c.name)
                    Text(c.hex).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle(NSLocalizedString("browse", comment: ""))
    }
    var filtered:[NamedColor] {
        if query.isEmpty { return catalog.names }
        return catalog.names.filter{ $0.name.lowercased().contains(query.lowercased()) }
    }
}
