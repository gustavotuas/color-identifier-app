import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct MagicReplaceStub: View {
    @State private var intensity: Double = 0.8
    var body: some View {
        VStack(alignment:.leading, spacing:12){
            Text("Magic Replace").font(.title2).bold()
            Text("Tap area recolor (stub). In production, use Vision to segment and CIColorMatrix to recolor.")
            HStack{
                Text("Intensity")
                Slider(value: $intensity, in: 0...1)
            }
            RoundedRectangle(cornerRadius:12).fill(.gray.opacity(0.2)).frame(height:200)
        }.padding()
    }
}
