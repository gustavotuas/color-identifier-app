
import SwiftUI
import PhotosUI

struct PhotosScreen: View {
    @EnvironmentObject var store: StoreVM
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var palette: [RGB] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxHeight: 360)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.12))
                        .frame(height: 200)
                        .overlay(Text("Pick a photo"))
                }

                PhotosPicker(selection: $item, matching: .images) { Text("Choose photo") }

                if image != nil {
                    Button {
                        if let img = image {
                            palette = KMeans.palette(from: img, k: 5)
                        }
                    } label: {
                        Label("Extract palette", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !palette.isEmpty {
                    HStack {
                        ForEach(Array(palette.enumerated()), id: \.offset) { _, c in SwatchView(c: c) }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Photos")
        .onChange(of: item) { new in
            Task {
                if let data = try? await new?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    image = img
                }
            }
        }
        .sheet(isPresented: $store.showPaywall) { PaywallView().environmentObject(store) }
    }
}
