import SwiftUI
import PhotosUI
import UIKit

private struct SystemPhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var image: UIImage?
    let onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: SystemPhotoPicker
        init(_ parent: SystemPhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            defer { parent.isPresented = false }
            guard let provider = results.first?.itemProvider else { return }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let uiimg = object as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.image = uiimg
                            self.parent.onPicked(uiimg)
                        }
                    }
                }
            }
        }
    }
}

struct PhotosScreen: View {
    @EnvironmentObject var store: StoreVM
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore

    @State private var image: UIImage?
    @State private var palette: [RGB] = []
    @State private var matches: [MatchedSwatch] = []

    @State private var selection: CatalogSelection = .all
    @State private var showVendorSheet = false
    @State private var showSystemPicker = false

    @State private var showToast = false
    @State private var toastMessage = ""

    private var vendorIDs: [CatalogID] { CatalogID.allCases.filter { $0 != .generic } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if image != nil {
                        Button {
                            showSystemPicker = true
                        } label: {
                            Label("Change Photo", systemImage: "photo.on.rectangle")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(10)
                        }
                        .padding(.top, 12)
                    }

                    if selection.isFiltered {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(selection.filterSubtitle).lineLimit(1)
                            Spacer()
                            Button {
                                withAnimation(.easeInOut) {
                                    selection = .all
                                    VendorSelectionStorage.save(selection)
                                    rebuildMatches()
                                }
                            } label: {
                                Label("Clear", systemImage: "xmark.circle.fill")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                            .font(.caption.bold())
                        }
                        .font(.footnote)
                        .padding(10)
                        .background(Color.blue.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if !palette.isEmpty {
                        paletteCard
                        savePaletteButton
                    }

                    imageSection
                    Spacer(minLength: 60)
                }
                .padding(.top, 10)
            }
            .navigationTitle("Photo Colours")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button { showVendorSheet = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !store.isPro {
                        Button {
                            store.showPaywall = true
                        } label: {
                            Text("PRO")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(colors: [.purple, .pink],
                                                   startPoint: .topLeading,
                                                   endPoint: .bottomTrailing)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .shadow(radius: 2)
                        }
                    }
                }
            }
            .sheet(isPresented: $showVendorSheet) {
                VendorListSheet(
                    selection: $selection,
                    candidates: vendorIDs,
                    catalogs: catalogs
                )
                .presentationDetents([.medium, .large])
                .onDisappear {
                    preloadForSelection()
                    rebuildMatches()
                }
            }
            .sheet(isPresented: $store.showPaywall) {
                PaywallView().environmentObject(store)
            }
            .fullScreenCover(isPresented: $showSystemPicker) {
                SystemPhotoPicker(isPresented: $showSystemPicker, image: $image) { uiimg in
                    let rawPalette = KMeans.palette(from: uiimg, k: 10)
                    palette = Array(Set(rawPalette.map { $0.hex })).compactMap { hexToRGB($0) }
                    rebuildMatches()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .ignoresSafeArea()
            }
            .onAppear {
                if let saved = VendorSelectionStorage.load() { selection = saved }
                preloadForSelection()
            }
            .onReceive(catalogs.$loaded) { _ in rebuildMatches() }
            .onChange(of: selection) { _ in
                VendorSelectionStorage.save(selection)
                preloadForSelection()
                rebuildMatches()
            }
            .overlay(alignment: .top) {
                if showToast {
                    Text(toastMessage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showToast)
        }
    }

    private var imageSection: some View {
        VStack(spacing: 14) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 6)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .onTapGesture {
                        showSystemPicker = true
                    }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a photo to discover its colors")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                    Button {
                        showSystemPicker = true
                    } label: {
                        Text("Choose Photo")
                            .font(.headline)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    private var paletteCard: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Detected Palette")
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.top, 10)

        ZStack {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(matches, id: \.color.hex) { m in
                        Rectangle()
                            .fill(m.closest != nil ? Color(hexToRGB(m.closest!.hex).uiColor) : Color(m.color.uiColor))
                    }
                }
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                Text("\(palette.count) colors detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            if !store.isPro {
                VisualEffectBlur(style: .systemUltraThinMaterialLight)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .frame(height: 100)

                Button {
                    store.showPaywall = true
                } label: {
                    Label("Unlock Full Palette", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }
}


    private var savePaletteButton: some View {
        Group {
            if !palette.isEmpty {
                Button {
                    if store.isPro {
                        let finalColors = matches.map { $0.closest != nil ? hexToRGB($0.closest!.hex) : $0.color }
                        let vendorName: String
                        switch selection {
                        case .all:
                            vendorName = "All Colors Palette"
                        case .genericOnly:
                            vendorName = "Generic Colors"
                        case .vendor(let id):
                            vendorName = id.displayName
                        }
                        let uniqueColors = Array(Set(finalColors.map { $0.hex })).compactMap { hexToRGB($0) }
                        favs.addPalette(name: vendorName, colors: uniqueColors)
                        showToast("Palette saved")
                    } else {
                        store.showPaywall = true
                    }
                } label: {
                    Label("Save Palette", systemImage: store.isPro ? "heart.fill" : "heart")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private struct MatchedSwatch {
        let color: RGB
        let closest: NamedColor?
    }

    private func preloadForSelection() {
        switch selection {
        case .all:
            catalogs.load(.generic)
            vendorIDs.forEach { catalogs.load($0) }
        case .genericOnly:
            catalogs.load(.generic)
        case .vendor(let id):
            catalogs.load(id)
        }
    }

    private func rebuildMatches() {
        guard !palette.isEmpty else { matches = []; return }

        let pool: [NamedColor]
        switch selection {
        case .all:
            let generic = catalogs.loaded[.generic] ?? catalog.names
            let vendors = catalogs.colors(for: Set(vendorIDs))
            pool = generic + vendors
        case .genericOnly:
            pool = catalogs.loaded[.generic] ?? catalog.names
        case .vendor(let id):
            pool = catalogs.loaded[id] ?? []
        }

        matches = palette.map { rgb in
            let closest = pool.min(by: {
                hexToRGB($0.hex).distance(to: rgb) < hexToRGB($1.hex).distance(to: rgb)
            })
            return MatchedSwatch(color: rgb, closest: closest)
        }
    }

    private func showToast(_ msg: String) {
        toastMessage = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { showToast = false }
        }
    }
}

private struct VisualEffectBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
