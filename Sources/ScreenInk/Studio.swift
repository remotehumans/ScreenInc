import SwiftUI
import AppKit
import Carbon

struct FeaturesView: View {
    @ObservedObject var state: InkState
    let controller: AppController
    @State var tab = 0
    @State var tourStep = 0
    @State var shortcutError = ""
    var body: some View {
        TabView(selection:$tab) {
            drawing.tabItem { Label("Drawing",systemImage:"pencil.tip") }.tag(0)
            snapshots.tabItem { Label("Snapshots",systemImage:"square.stack") }.tag(1)
            presentation.tabItem { Label("Present",systemImage:"play.rectangle") }.tag(2)
            shortcuts.tabItem { Label("Keys",systemImage:"keyboard") }.tag(3)
            remote.tabItem { Label("Remote",systemImage:"iphone") }.tag(4)
            tour.tabItem { Label("Guide",systemImage:"questionmark.circle") }.tag(5)
        }.padding(16).frame(minWidth:580,minHeight:560)
        .safeAreaInset(edge:.bottom) { Text(state.message).font(.caption).foregroundStyle(.secondary).padding(8) }
    }
    func color(_ title: String,_ binding: Binding<InkColor>) -> some View {
        ColorPicker(title,selection:Binding(get:{binding.wrappedValue.swift},set:{binding.wrappedValue = InkColor(NSColor($0)); state.changed()}),supportsOpacity:false)
    }
    var drawing: some View {
        Form {
            Section("Tools") {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:105))],spacing:10) {
                    ForEach(InkTool.allCases,id:\.self) { tool in Button { controller.select(tool) } label: { Label(tool.label,systemImage:tool.symbol).frame(maxWidth:.infinity) }.help("Select \(tool.label)") }
                }
            }
            Section("Appearance") {
                color("Colour",$state.color)
                Toggle("Gradient",isOn:$state.preferences.style.gradient)
                if state.preferences.style.gradient { color("Gradient end",$state.preferences.style.endColor) }
                HStack { Text("Opacity"); Slider(value:$state.preferences.style.opacity,in:0.05...1); Text("\(Int(state.preferences.style.opacity*100))%") }
                Toggle("Shadow",isOn:$state.preferences.style.shadow)
                color("Whiteboard colour",$state.preferences.boardColor)
                Toggle("Whiteboard",isOn:$state.whiteboard).onChange(of:state.whiteboard) { _,_ in state.changed() }
                HStack { Text("Fade delay"); Slider(value:$state.fadeDelay,in:0...120,step:1); Text(state.fadeDelay == 0 ? "Keep" : "\(Int(state.fadeDelay))s").frame(width:45) }
                Toggle("Partial stroke eraser",isOn:$state.preferences.partialEraser)
            }
            Section("Selected drawings · \(state.selected.count)") {
                Text("Choose Select, click a drawing, or drag a box. Shift adds to the selection. Drag to move; drag the bottom-right handle to resize.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Duplicate",action:state.duplicateSelected); Button("Recolour",action:state.recolorSelected); Button("Delete",action:state.deleteSelected) }.disabled(state.selection.isEmpty)
                HStack { Button("Group",action:state.groupSelected); Button("Ungroup",action:state.ungroupSelected); Button("To front") { state.reorderSelected(front:true) }; Button("To back") { state.reorderSelected(front:false) } }.disabled(state.selection.isEmpty)
                Menu("Move selection to screen") { ForEach(Array(controller.canvases.enumerated()),id:\.offset) { index,canvas in Button("Screen \(index+1)") { controller.moveSelection(to:canvas) } } }.disabled(state.selection.isEmpty)
                Button("Repeat last drawing",action:controller.repeatDrawing)
            }
            Section("Files") {
                HStack { Button("Import image…",action:controller.importImage); Button("Copy drawing",action:controller.copyDrawing) }
                HStack { ForEach(["png","pdf","psd"],id:\.self) { format in Button("Export \(format.uppercased())…") { controller.exportDrawing(format) } } }
                Text("PDF keeps vector paths. PSD is a flattened image with transparency. Save a snapshot to keep editable objects.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    var snapshots: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Button("Save snapshot",action:controller.snapshot); Button("Previous") { controller.cycleSnapshot(-1) }; Button("Next") { controller.cycleSnapshot(1) }; Spacer(); Button("Open file…",action:controller.load) }
            Text("Double-click to restore. Drag a preview into another app to export PNG. Snapshots and your session save automatically.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:180))],spacing:16) {
                    ForEach(Array(state.library.enumerated()),id:\.element.id) { index,item in
                        VStack(alignment:.leading) {
                            if let data = item.thumbnail, let image = NSImage(data:data) {
                                Image(nsImage:image).resizable().scaledToFit().frame(height:120).frame(maxWidth:.infinity).background(Color.gray.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius:8))
                                    .onTapGesture(count:2) { controller.restoreSnapshot(index) }
                                    .onDrag { NSItemProvider(item:data as NSData,typeIdentifier:"public.png") }
                            }
                            TextField("Snapshot name",text:Binding(get:{state.library.first(where:{$0.id == item.id})?.title ?? item.title},set:{ title in if let i = state.library.firstIndex(where:{$0.id == item.id}) { state.library[i].title = title; state.changed() } }))
                            HStack { Button("Restore") { controller.restoreSnapshot(index) }; Spacer(); Button(role:.destructive) { state.library.removeAll { $0.id == item.id }; state.libraryIndex = min(state.libraryIndex,state.library.count-1); state.changed() } label: { Image(systemName:"trash") } }
                        }.padding(10).background(RoundedRectangle(cornerRadius:10).stroke(Color.secondary.opacity(0.3)))
                    }
                }
                if state.library.isEmpty { ContentUnavailableView("No snapshots yet",systemImage:"square.stack",description:Text("Draw something, then save your first snapshot.")) }
            }
        }.padding()
    }
    var presentation: some View {
        Form {
            Section("Hand gestures") { Button("Camera controls…",action:controller.openGestures) }
            Section("Pointer") {
                Toggle("Cursor halo",isOn:$state.preferences.halo)
                Toggle("Click rings",isOn:$state.preferences.clicks)
                Button("Numbered badge tool") { controller.select(.badge) }
                Button("Restart numbering") { state.nextBadge = 1 }
            }
            Section("Spotlight") {
                Button("Use spotlight") { controller.select(.spotlight) }
                HStack { Text("Radius"); Slider(value:$state.preferences.spotlightRadius,in:30...500); Text("\(Int(state.preferences.spotlightRadius))") }
                Toggle("Magnify screen",isOn:$state.preferences.magnify).onChange(of:state.preferences.magnify) { _,_ in controller.startMagnifier() }
                HStack { Text("Zoom"); Slider(value:$state.preferences.magnification,in:1...5); Text(String(format:"%.1f×",state.preferences.magnification)) }
                HStack { Button("Select rectangle") { controller.selectRegion(copy:false) }; Button("Copy screen region") { controller.selectRegion(copy:true) }; Button("Reset region") { controller.canvases.forEach { $0.region = nil }; state.changed() } }
                Text("Magnification and screen-region copying use macOS Screen Recording permission. Scroll over the canvas to resize the spotlight.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Countdown") {
                HStack { Text("Seconds"); TextField("Seconds",value:$state.preferences.countdownSeconds,format:.number).frame(width:80) }
                HStack { Button("Start") { state.countdownEnd = Date().addingTimeInterval(max(1,state.preferences.countdownSeconds)); state.changed() }; Button("Hide") { state.countdownEnd = nil; state.changed() } }
            }
            Section("Lower-third title") {
                TextField("Title",text:$state.preferences.lowerThirdText)
                HStack { Button("Show") { state.lowerThird = state.preferences.lowerThirdText; state.changed() }; Button("Hide") { state.lowerThird = ""; state.changed() } }
            }
        }.formStyle(.grouped)
    }
    var shortcuts: some View {
        Form {
            Section("Presets") { HStack { Button("ScreenInc") { controller.setShortcutPreset(false) }; Button("Pen on P") { controller.setShortcutPreset(true) } } }
            Section("Global drawing switch · \(state.shortcutLabel)") {
                ShortcutRecorder(label:"Record shortcut",onRecord:{ event in
                    var modifiers: UInt32 = 0
                    if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
                    if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
                    if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
                    if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
                    guard modifiers != 0 else { shortcutError = "Include Control, Option, Command or Shift."; return }
                    state.preferences.toggleKey = UInt32(event.keyCode); state.preferences.toggleModifiers = modifiers; controller.registerHotKey(); state.changed(); shortcutError = "Global shortcut updated"
                }).frame(height:30)
                Toggle("Hold Fn / Globe to temporarily switch drawing mode",isOn:$state.preferences.holdToDraw)
                Text("Holding Fn while drawing lets clicks through. Holding it while browsing enables drawing until release. macOS may require Accessibility permission for keys outside ScreenInc.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Tool keys") {
                ForEach(InkTool.allCases,id:\.self) { tool in
                    HStack { Label(tool.label,systemImage:tool.symbol); Spacer(); TextField(tool.key,text:Binding(get:{state.preferences.shortcutKeys[tool.rawValue] ?? tool.key},set:{ key in
                        let value = String(key.lowercased().suffix(1))
                        guard !value.isEmpty, !["f","w","[","]",";"].contains(value), !InkTool.allCases.contains(where:{ $0 != tool && (state.preferences.shortcutKeys[$0.rawValue] ?? $0.key) == value }) else { shortcutError = "That key is already used."; return }
                        state.preferences.shortcutKeys[tool.rawValue] = value; shortcutError = ""
                    })).frame(width:45) }
                }
            }
            Text(shortcutError).foregroundStyle(.secondary)
            Text("Esc: click through · Tab: hide tools · Delete: delete selection\n⌘S: snapshot · [ / ]: previous / next snapshot · ;: repeat\n⌘D: duplicate · ⌘G: group · ⇧⌘G: ungroup\n⌘[ / ⌘]: send back / forward · ⌘C: copy drawing\n⌘Return: finish text · Return: new line").font(.caption)
        }.formStyle(.grouped)
    }
    var remote: some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            Text("Present from your iPhone or iPad").font(.title2.bold())
            Text("Connect both devices to the same Wi-Fi. Start the remote, then open the pairing address in Safari. You can add it to your Home Screen.")
            Button(controller.remote == nil ? "Start remote" : "Stop remote",action:controller.toggleRemote)
            Text(state.remoteAddress).font(.system(.body,design:.monospaced)).textSelection(.enabled)
            if state.remoteAddress.hasPrefix("http"), let qr = qrCode(state.remoteAddress) { Image(nsImage:qr).interpolation(.none).resizable().frame(width:190,height:190).padding(10).background(.white) }
            Text("The link controls this Mac for this session. Stop the remote to disconnect. The drawing pad uses the Mac’s colour, gradient, pressure and fade settings.").font(.caption).foregroundStyle(.secondary)
            Button("Enable slide-key control…") { let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary; _ = AXIsProcessTrustedWithOptions(options) }
            Text("Slide arrows control the last app you used. Snapshot arrows switch your saved drawings.").font(.caption)
            Spacer()
        }.padding(24) }
    }
    func qrCode(_ string: String) -> NSImage? {
        guard let filter = CIFilter(name:"CIQRCodeGenerator") else { return nil }; filter.setValue(Data(string.utf8),forKey:"inputMessage")
        guard let output = filter.outputImage?.transformed(by:CGAffineTransform(scaleX:8,y:8)), let cg = CIContext().createCGImage(output,from:output.extent) else { return nil }; return NSImage(cgImage:cg,size:output.extent.size)
    }
    let steps = [("Start drawing","Use the pencil button or your global shortcut. Escape returns control to the app beneath your ink."),("Ink that disappears","Choose a fade delay, or set Keep to leave drawings on screen. Each stroke has its own timer."),("Make it yours","Choose colours, enable gradients, and adjust opacity. Colours are remembered for each tool."),("Edit your drawings","Use Select to click objects or drag a selection box. Move, resize, duplicate and group from Drawing."),("Save a moment","Command-S saves a snapshot. Use [ and ] to cycle snapshots; double-click a preview to restore."),("Present clearly","Add a spotlight, cursor halo, numbered badges, timer or lower-third title. The Remote tab pairs a phone."),("Use a tablet","Pressure changes pen width. Flip a compatible stylus to erase. Keep ScreenInc’s palette at the screen edge.")]
    var tour: some View {
        VStack(alignment:.leading,spacing:24) {
            Text("\(tourStep+1) / \(steps.count)").font(.caption).foregroundStyle(.secondary)
            Image(systemName:["pencil.tip","timer","paintpalette","cursorarrow.and.square.on.square.dashed","square.stack","play.rectangle","pencil.and.scribble"][tourStep]).font(.system(size:54)).foregroundStyle(.orange)
            Text(steps[tourStep].0).font(.largeTitle.bold()); Text(steps[tourStep].1).font(.title3)
            HStack { Button("Back") { tourStep -= 1 }.disabled(tourStep == 0); Spacer(); Button(tourStep == steps.count-1 ? "Start drawing" : "Next") { if tourStep < steps.count-1 { tourStep += 1 } else { controller.featuresWindow?.orderOut(nil); controller.select(.pen) } }.buttonStyle(.borderedProminent) }
            Spacer()
        }.padding(30)
    }
}
struct ShortcutRecorder: NSViewRepresentable {
    var label: String
    var onRecord: (NSEvent) -> Void
    func makeNSView(context: Context) -> RecorderButton { let button = RecorderButton(title:label,target:nil,action:nil); button.bezelStyle = .rounded; button.record = onRecord; return button }
    func updateNSView(_ view: RecorderButton,context: Context) { view.record = onRecord }
}
final class RecorderButton: NSButton {
    var record: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); title = "Press a shortcut…" }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { title = "Record shortcut"; return }; record?(event); title = "Shortcut recorded"; window?.makeFirstResponder(nil) }
}
