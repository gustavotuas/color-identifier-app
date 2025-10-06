import SwiftUI

struct DiscoverScreen: View {
    var body: some View {
        ScrollView{
            VStack(alignment:.leading, spacing:12){
                Text(NSLocalizedString("discover", comment: "")).font(.largeTitle).bold()
                GroupBox(NSLocalizedString("pro_tips", comment: "")){
                    VStack(alignment:.leading){
                        Label(NSLocalizedString("tip_natural_light", comment: ""), systemImage:"sun.max")
                        Label(NSLocalizedString("tip_avoid_glare", comment: ""), systemImage:"sparkles")
                        Label(NSLocalizedString("tip_contrast", comment: ""), systemImage:"circle.lefthalf.filled")
                    }
                }
                ARPreviewStub()
                MagicReplaceStub()
                NavigationLink(NSLocalizedString("contrast", comment: "")) { ContrastTool() }
            }.padding()
        }
    }
}
