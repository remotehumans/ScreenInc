import SwiftUI

struct InkToolbar: View {
    @ObservedObject var state: InkState
    let controller: AppController
    @State private var settings = false
    private let paper = Color(red:0.949,green:0.941,blue:0.914)
    var body: some View {
        VStack(spacing:3) {
            Capsule().fill(.white.opacity(0.3)).frame(width:16,height:3).padding(.top,7).padding(.bottom,5)
                .help("Drag to move ScreenInc")
            toolButton(state.drawing ? "cursorarrow" : "pencil.tip", label:state.drawing ? "Click through · Esc" : "Start drawing · \(state.shortcutLabel)",active:state.drawing,action:controller.toggleDrawing)
            Rectangle().fill(.white.opacity(0.12)).frame(height:1).padding(.horizontal,7).padding(.vertical,3)
            ForEach([InkTool.pen,.arrow,.rectangle,.text,.eraser,.laser],id:\.self) { tool in
                toolButton(tool.symbol,label:"\(tool.label) · \((state.preferences.shortcutKeys[tool.rawValue] ?? tool.key).uppercased())",active:state.tool == tool && state.drawing) { controller.select(tool) }
            }
            Button { settings.toggle() } label: {
                Circle().fill(state.color.swift).frame(width:17,height:17)
                    .overlay(Circle().stroke(.white.opacity(0.65),lineWidth:1)).frame(width:32,height:32)
            }.buttonStyle(.plain).help("Colour, size and more tools").accessibilityLabel("Drawing settings")
            .popover(isPresented:$settings,arrowEdge:.leading) { settingsView }
            toolButton(state.fadeDelay > 0 ? "timer" : "pin.fill",label:state.fadeDelay > 0 ? "Fading ink · F to keep" : "Keep ink · F to fade",active:state.fadeDelay == 0) { state.fadeDelay = state.fadeDelay == 0 ? 2 : 0 }
            toolButton("hand.raised",label:"Hand gestures · camera controls",action:controller.openGestures)
            toolButton("square.stack",label:"Studio · editing, snapshots and presentation",action:controller.openFeatures)
            toolButton("trash",label:"Clear drawings · ⌘⌫",action:controller.clear)
            toolButton("chevron.right",label:"Hide palette · Tab · restore with \(state.shortcutLabel)",action:controller.hide)
        }
        .padding(.horizontal,5).padding(.bottom,5).frame(width:44)
        .background(Color(red:0.075,green:0.075,blue:0.065))
        .foregroundStyle(paper).preferredColorScheme(.dark)
        .overlay(RoundedRectangle(cornerRadius:12).stroke(.white.opacity(0.16),lineWidth:1))
        .clipShape(RoundedRectangle(cornerRadius:12))
    }
    private func toolButton(_ symbol: String,label: String,active: Bool = false,action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Image(systemName:symbol).font(.system(size:15,weight:.medium)).frame(width:32,height:29)
                .foregroundStyle(active ? Color.orange : paper)
                .background(active ? Color.orange.opacity(0.14) : .clear,in:RoundedRectangle(cornerRadius:6))
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    private var settingsView: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("ScreenInc").font(.system(size:19,weight:.semibold,design:.serif))
                Spacer()
                Text(state.shortcutLabel).font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary)
            }
            HStack(spacing:11) {
                ForEach(Array(InkColor.palette.enumerated()),id:\.offset) { index,color in
                    Button { state.color = color } label: {
                        Circle().fill(color.swift).frame(width:22,height:22)
                            .overlay(Circle().stroke(state.color == color ? .white : .gray.opacity(0.3),lineWidth:state.color == color ? 2:0.5).padding(-2))
                    }.buttonStyle(.plain).help("Colour \(index+1)").accessibilityLabel("Colour \(index+1)")
                }
            }
            HStack { Text("Size").font(.caption); Slider(value:$state.width,in:2...16,step:1).tint(.orange); Text("\(Int(state.width))").font(.caption.monospacedDigit()).frame(width:20) }
            HStack {
                Text("Ink").font(.caption)
                Picker("Ink duration",selection:$state.fadeDelay) {
                    Text("Fade after 2 seconds").tag(2.0); Text("Fade after 5 seconds").tag(5.0); Text("Fade after 10 seconds").tag(10.0); Text("Fade after 30 seconds").tag(30.0); Text("Fade after 60 seconds").tag(60.0); Text("Keep ink").tag(0.0)
                }.labelsHidden()
            }
            HStack(spacing:10) {
                ForEach([InkTool.marker,.line,.ellipse,.spotlight],id:\.self) { tool in
                    Button { controller.select(tool); settings = false } label: { Image(systemName:tool.symbol).frame(width:37,height:28) }.help("\(tool.label) · \((state.preferences.shortcutKeys[tool.rawValue] ?? tool.key).uppercased())").accessibilityLabel(tool.label)
                }
            }
            Toggle("Gradient colours",isOn:$state.preferences.style.gradient)
            if state.preferences.style.gradient { ColorPicker("Second colour",selection:Binding(get:{state.preferences.style.endColor.swift},set:{state.preferences.style.endColor = InkColor(NSColor($0))}),supportsOpacity:false) }
            Button("All tools and settings…") { settings = false; controller.openFeatures() }
            Toggle("Whiteboard",isOn:$state.whiteboard).onChange(of:state.whiteboard) { _,_ in state.changed() }
            HStack {
                Button("Undo",action:state.undo).disabled(!state.history.canUndo)
                Button("Redo",action:state.redo).disabled(!state.history.canRedo)
                Spacer()
                Menu("Files") {
                    Button("Save drawings…") { settings = false; controller.save() }
                    Button("Open drawings…") { settings = false; controller.load() }
                    Button("Export ink as PNG…") { settings = false; controller.export() }
                }.frame(width:65)
            }
            Divider()
            Text("Esc · click through    Tab · hide tools\nF · fade / keep    W · whiteboard\n1–7 · colours    ⇧ drag · constrain shapes\n⌘Z · undo    ⇧⌘Z · redo    ⌘⌫ · clear")
                .font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).lineSpacing(4)
            Text("Share your entire screen to include your ink.").font(.caption2).foregroundStyle(.secondary)
            HStack { Text(state.message).font(.caption2).foregroundStyle(.secondary); Spacer(); Button("Quit",action:controller.quit).font(.caption2) }
        }.padding(18).frame(width:270).preferredColorScheme(.dark)
    }
}
