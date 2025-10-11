import SwiftUI
import PhotosUI

struct PhotosScreen: View {
    @EnvironmentObject var store: StoreVM
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var palette:[RGB] = []
    var body: some View {
        ScrollView {
            VStack(spacing:12){
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:16)).frame(maxHeight:360)
                } else {
                    RoundedRectangle(cornerRadius:16).fill(Color.black.opacity(0.15)).frame(height:200).overlay(Text(NSLocalizedString("pick_photo", comment: "")))
                }
                PhotosPicker(selection: $item, matching: .images){ Text(NSLocalizedString("choose_photo", comment: "")) }
                if image != nil {
                    Button(NSLocalizedString("extract_palette", comment: "")){
                        if let img = image {
                            palette = KMeans.palette(from: img, k: 5)
                        }
                    }.buttonStyle(.borderedProminent)
                }
                if !palette.isEmpty {
                    HStack { ForEach(Array(palette.enumerated()), id: \.offset) { _, c in
                        SwatchView(c: c)
                    }
 }
                }
                Spacer(minLength:24)
            }.padding()
        }
        .onChange(of: item) { oldValue, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    image = img
                }
            }
        }

        .navigationTitle(NSLocalizedString("photos", comment: ""))
        .sheet(isPresented: $store.showPaywall){ PaywallView().environmentObject(store) }
    }
}
