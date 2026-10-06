import AppKit
import SwiftUI
import AVFoundation

struct GestureMenuItem {
    let id: String
    let title: String
    let symbol: String
    var colour: InkColor? = nil
}

final class GestureController: ObservableObject {
    weak var owner: AppController?
    let camera = HandCamera()
    @Published var running = false
    @Published var requesting = false
    @Published var status = "Camera is off"
    @Published var paused = false
    @Published var deviceID = ""
    @Published var mirrored = true
    @Published var reach = 0.15
    @Published var smoothing = 0.09
    @Published var pinchThreshold = 0.38
    @Published var gestureLabel = "Show your hand"
    @Published var frameDelay = 0
    @Published var trackingFPS = 0
    private var previousDelivery: TimeInterval?
    @Published var displayIndex = 0
    @Published var calibrationPoint: CGPoint?
    var engine = HandGestureEngine()
    var menuVisible = false
    var page = "Tools"
    var clearArmed = false
    var pointer: CGPoint?
    var palmProgress = 0.0
    var activeStroke = false
    weak var strokeCanvas: InkCanvas?
    var watchdog: Timer?
    var observers: [NSObjectProtocol] = []
    var lastSample: TimeInterval = 0
    var lastDelivery: TimeInterval = 0
    var generation = 0
    var wasDrawing = false
    var isPreview = false
    var target: InkCanvas? {
        guard let canvases = owner?.canvases, !canvases.isEmpty else { return nil }
        return canvases[min(max(0,displayIndex),canvases.count-1)]
    }
    init(owner: AppController) {
        self.owner = owner
        camera.sample = { [weak self] sample,time in self?.lastDelivery = ProcessInfo.processInfo.systemUptime; self?.receive(sample,at:time) }
        camera.failure = { [weak self] message in self?.stop(); self?.status = message }
        for name in [AVCaptureSession.runtimeErrorNotification,AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:camera.session,queue:.main) { [weak self] _ in
                self?.stop(); self?.status = "Camera interrupted. Check the camera, then start again."
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in self?.stop() })
    }
    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        watchdog?.invalidate(); camera.stop()
    }
    func start() {
        guard !running && !requesting else { return }
        requesting = true; generation += 1; let token = generation
        status = "Waiting for camera permission…"
        let begin: (Bool) -> Void = { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.requesting = false
                guard allowed else { self.status = "Camera access is off. Enable ScreenInc in System Settings → Privacy & Security → Camera."; return }
                self.wasDrawing = self.owner?.state.drawing ?? false
                self.owner?.select(.pen)
                self.owner?.featuresWindow?.orderOut(nil)
                self.owner?.overlays.forEach { $0.ignoresMouseEvents = true }
                self.running = true; self.paused = false; self.menuVisible = false
                self.owner?.gestureWindow?.makeKeyAndOrderFront(nil)
                self.resetInput(); self.status = "Show one hand, with thumb and finger apart"
                self.lastSample = ProcessInfo.processInfo.systemUptime; self.lastDelivery = self.lastSample
                self.camera.start(deviceID:self.deviceID)
                self.watchdog = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in
                    guard let self, self.running else { return }
                    if ProcessInfo.processInfo.systemUptime-self.lastDelivery > 8 {
                        self.stop(); self.status = "Camera tracking timed out. Check the camera and try again."; return
                    }
                    if ProcessInfo.processInfo.systemUptime-self.lastDelivery > 0.65 { self.receive(nil,at:ProcessInfo.processInfo.systemUptime) }
                }
            }
        }
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: begin(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for:.video,completionHandler:begin)
        default: begin(false)
        }
    }
    func stop() {
        generation += 1; requesting = false
        let restore = running
        running = false; isPreview = false; resetInput(); menuVisible = false
        watchdog?.invalidate(); watchdog = nil; camera.stop(); status = "Camera is off"
        if restore { owner?.setDrawing(wasDrawing) }
        owner?.state.changed()
    }
    func beginDrawing() {
        resetInput(); menuVisible = false
        owner?.featuresWindow?.orderOut(nil)
        owner?.gestureWindow?.orderOut(nil)
        if owner?.state.drawing == false { owner?.setDrawing(true) }
        status = "Ready · pinch to draw · release to stop"
    }
    func resetInput() {
        finishStroke(); _ = engine.reset(); pointer = nil; calibrationPoint = nil; palmProgress = 0
        owner?.canvases.forEach { $0.pointer = nil; $0.needsDisplay = true }
    }
    func finishStroke() {
        if activeStroke { strokeCanvas?.pointerUp() }
        activeStroke = false; strokeCanvas = nil
    }
    func receive(_ incoming: HandSample?, at time: TimeInterval, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard running, !isPreview else { return }
        // Ignore queued frames that predate a pause, or became stale during UI work.
        guard now-time >= 0, now-time < 0.65 else { resetInput(); return }
        if let previousDelivery, now > previousDelivery { trackingFPS = Int(1/(now-previousDelivery)) }
        previousDelivery = now; frameDelay = Int((now-time)*1000)
        lastSample = time
        var sample = incoming
        if mirrored, let value = sample { sample?.index.x = 1-value.index.x }
        engine.inset = reach; engine.smoothing = smoothing; engine.pinchThreshold = pinchThreshold
        let update = engine.update(sample,at:time)
        guard let canvas = target else { stop(); return }
        if update.ended { finishStroke() }
        pointer = update.point.map { CGPoint(x:$0.x*canvas.bounds.width,y:$0.y*canvas.bounds.height) }
        calibrationPoint = update.point; palmProgress = update.palmProgress
        gestureLabel = !update.tracking ? "Hand unclear · keep it in view" : update.held ? "Pinch detected" : engine.ready ? "Ready · pinch to draw" : "Separate thumb and index finger"
        if !update.tracking { canvas.pointer = nil; status = "Hand unclear · hold still with your palm facing the camera"; canvas.needsDisplay = true; return }
        if update.menu { finishStroke(); menuVisible = true; clearArmed = false }
        guard let pointer else { status = "Hand lost · release pinch to resume"; canvas.pointer = nil; canvas.needsDisplay = true; return }
        let blocked = owner?.gestureWindow?.isVisible == true || owner?.featuresWindow?.isVisible == true || NSApp.modalWindow != nil
        if menuVisible && !blocked {
            if update.began, let item = hit(pointer,in:canvas.bounds) { perform(item.id) }
        } else if !paused && !blocked && owner?.state.drawing == true {
            if update.began {
                guard ![InkTool.text,.image].contains(canvas.state.tool) else { menuVisible = true; status = "Choose a drawing tool"; canvas.needsDisplay = true; return }
                activeStroke = true; strokeCanvas = canvas; canvas.pointerDown(at:pointer)
            } else if update.held && activeStroke { canvas.pointerDragged(to:pointer) }
        } else { finishStroke() }
        canvas.pointer = menuVisible || paused || blocked ? nil : pointer
        status = blocked ? "Setup only · choose Start drawing below" : menuVisible ? "Point at a tile and pinch" : paused ? "Paused · hold an open palm for tools" : activeStroke ? "Drawing · release pinch to finish" : "Point to aim · pinch to draw · open palm for tools"
        canvas.needsDisplay = true
    }
    var items: [GestureMenuItem] {
        if page == "Tools" {
            return [InkTool.pen,.marker,.arrow,.line,.rectangle,.ellipse,.triangle,.badge,.eraser,.select,.laser,.spotlight].map { GestureMenuItem(id:$0.rawValue,title:$0.label,symbol:$0.symbol) }
        }
        if page == "Colour" {
            let names = ["Orange","Yellow","Mint","Blue","Pink","Paper","Ink"]
            return InkColor.palette.enumerated().map { GestureMenuItem(id:"colour\($0.offset)",title:names[$0.offset],symbol:"circle.fill",colour:$0.element) } + [
                GestureMenuItem(id:"gradient",title:owner?.state.preferences.style.gradient == true ? "Gradient on" : "Gradient off",symbol:"paintpalette"),
                GestureMenuItem(id:"gradientEnd",title:"Next end colour",symbol:"arrow.triangle.2.circlepath"),
                GestureMenuItem(id:"thinner",title:"Thinner",symbol:"minus"),GestureMenuItem(id:"thicker",title:"Thicker",symbol:"plus"),
                GestureMenuItem(id:"fade",title:owner?.state.fadeDelay == 0 ? "Keep ink" : "Fading ink",symbol:"timer")]
        }
        return [GestureMenuItem(id:"undo",title:"Undo",symbol:"arrow.uturn.backward"),GestureMenuItem(id:"redo",title:"Redo",symbol:"arrow.uturn.forward"),
                GestureMenuItem(id:"snapshot",title:"Save snapshot",symbol:"square.stack"),GestureMenuItem(id:"clear",title:clearArmed ? "Confirm clear" : "Clear ink",symbol:"trash"),
                GestureMenuItem(id:"duplicate",title:"Duplicate",symbol:"plus.square.on.square"),GestureMenuItem(id:"delete",title:"Delete selected",symbol:"delete.left"),
                GestureMenuItem(id:"recolour",title:"Recolour",symbol:"paintbrush"),GestureMenuItem(id:"board",title:"Whiteboard",symbol:"rectangle.fill"),
                GestureMenuItem(id:"display",title:"Next screen",symbol:"display"),GestureMenuItem(id:"pause",title:paused ? "Resume" : "Pause",symbol:paused ? "play.fill" : "pause.fill"),
                GestureMenuItem(id:"close",title:"Back to drawing",symbol:"checkmark"),GestureMenuItem(id:"stop",title:"Stop camera",symbol:"video.slash")]
    }
    func layout(in bounds: CGRect) -> [(GestureMenuItem,CGRect)] {
        let width = min(560,bounds.width-32), height: CGFloat = 370
        let x = (bounds.width-width)/2, y = max(16,(bounds.height-height)/2)
        let tabs = ["Tools","Colour","Actions"].enumerated().map { i,title in
            (GestureMenuItem(id:"page\(title)",title:title,symbol:""),CGRect(x:x+16+CGFloat(i)*(width-92)/3,y:y+53,width:(width-92)/3-6,height:34))
        }
        var result = tabs + [(GestureMenuItem(id:"close",title:"×",symbol:""),CGRect(x:x+width-56,y:y+53,width:40,height:34))]
        let cell = (width-44)/4
        for (i,item) in items.enumerated() { result.append((item,CGRect(x:x+16+CGFloat(i%4)*(cell+4),y:y+100+CGFloat(i/4)*78,width:cell,height:72))) }
        return result
    }
    func hit(_ point: CGPoint,in bounds: CGRect) -> GestureMenuItem? { layout(in:bounds).first(where:{$0.1.contains(point)})?.0 }
    func perform(_ id: String) {
        guard let owner else { return }
        finishStroke()
        if id != "clear" { clearArmed = false }
        if id.hasPrefix("page") { page = String(id.dropFirst(4)); return }
        if let tool = InkTool(rawValue:id) { owner.state.tool = tool; if !owner.state.drawing { owner.setDrawing(true) }; owner.overlays.forEach { $0.ignoresMouseEvents = true }; paused = false; menuVisible = false }
        else if id.hasPrefix("colour"), let index = Int(id.dropFirst(6)), InkColor.palette.indices.contains(index) { owner.state.color = InkColor.palette[index] }
        else {
            switch id {
            case "close": menuVisible = false
            case "gradient": owner.state.preferences.style.gradient.toggle()
            case "gradientEnd": let index = InkColor.palette.firstIndex(of:owner.state.preferences.style.endColor) ?? 0; owner.state.preferences.style.endColor = InkColor.palette[(index+1)%InkColor.palette.count]
            case "thinner": owner.state.width = max(2,owner.state.width-2)
            case "thicker": owner.state.width = min(40,owner.state.width+2)
            case "fade": owner.state.fadeDelay = owner.state.fadeDelay == 0 ? 2 : 0
            case "undo": owner.state.undo()
            case "redo": owner.state.redo()
            case "snapshot": if let canvas = target { owner.state.saveSnapshot(size:canvas.bounds.size) }
            case "clear": if clearArmed { owner.clear(); clearArmed = false } else { clearArmed = true }
            case "duplicate": owner.state.duplicateSelected()
            case "delete": owner.state.deleteSelected()
            case "recolour": owner.state.recolorSelected()
            case "board": owner.state.whiteboard.toggle()
            case "display": resetInput(); displayIndex = (displayIndex+1)%max(1,owner.canvases.count)
            case "pause": paused.toggle(); menuVisible = false; if !paused && !owner.state.drawing { owner.setDrawing(true); owner.overlays.forEach { $0.ignoresMouseEvents = true } }
            case "stop": stop()
            default: break
            }
        }
        owner.state.changed()
    }
    func draw(on canvas: InkCanvas) {
        guard running, canvas === target else { return }
        func label(_ text: String,rect: CGRect,size: CGFloat = 13,colour: NSColor = .white) {
            let style = NSMutableParagraphStyle(); style.alignment = .center
            (text as NSString).draw(in:rect,withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:colour,.paragraphStyle:style])
        }
        if menuVisible {
            let cells = layout(in:canvas.bounds)
            guard let first = cells.first?.1 else { return }
            let background = CGRect(x:first.minX-16,y:first.minY-53,width:min(560,canvas.bounds.width-32),height:370)
            NSColor(calibratedWhite:0.07,alpha:0.97).setFill(); NSBezierPath(roundedRect:background,xRadius:20,yRadius:20).fill()
            label("Hand tools",rect:CGRect(x:background.minX,y:background.minY+16,width:background.width,height:28),size:20)
            for (item,rect) in cells {
                let hovered = pointer.map(rect.contains) ?? false
                let selected = item.id == canvas.state.tool.rawValue || item.id == "page\(page)"
                (hovered ? NSColor.systemOrange.withAlphaComponent(0.5) : selected ? NSColor.white.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.07)).setFill()
                NSBezierPath(roundedRect:rect,xRadius:9,yRadius:9).fill()
                if !item.symbol.isEmpty {
                    if let colour = item.colour { colour.ns.setFill(); NSBezierPath(ovalIn:CGRect(x:rect.midX-10,y:rect.minY+10,width:20,height:20)).fill() }
                    else if let symbol = NSImage(systemSymbolName:item.symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:20,weight:.medium)) {
                        let image = NSImage(size:symbol.size); image.lockFocus(); NSColor.white.set(); symbol.draw(at:.zero,from:.zero,operation:.sourceOver,fraction:1); NSColor.white.setFill(); CGRect(origin:.zero,size:symbol.size).fill(using:.sourceAtop); image.unlockFocus()
                        image.draw(in:CGRect(x:rect.midX-11,y:rect.minY+10,width:22,height:22),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                    }
                    label(item.title,rect:CGRect(x:rect.minX+2,y:rect.minY+43,width:rect.width-4,height:23),size:12)
                } else { label(item.title,rect:rect.insetBy(dx:2,dy:8)) }
            }
            label("Point, then pinch · release between choices",rect:CGRect(x:background.minX,y:background.maxY-30,width:background.width,height:20),size:12,colour:.lightGray)
        }
        let hud = CGRect(x:24,y:canvas.bounds.height-76,width:min(440,canvas.bounds.width-48),height:50)
        NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect:hud,xRadius:12,yRadius:12).fill()
        label(isPreview ? "Menu preview · camera is off" : status,rect:hud.insetBy(dx:8,dy:15),size:12)
        if let pointer {
            let ring = NSBezierPath(ovalIn:CGRect(x:pointer.x-10,y:pointer.y-10,width:20,height:20))
            (activeStroke ? NSColor.systemOrange : NSColor.white).setStroke(); ring.lineWidth = 3; ring.stroke()
            NSColor.black.setStroke(); let outer = NSBezierPath(ovalIn:CGRect(x:pointer.x-13,y:pointer.y-13,width:26,height:26)); outer.lineWidth = 2; outer.stroke()
            if palmProgress > 0 {
                let arc = NSBezierPath(); arc.appendArc(withCenter:pointer,radius:18,startAngle:-90,endAngle:-90+360*palmProgress,clockwise:false); NSColor.systemOrange.setStroke(); arc.lineWidth = 4; arc.stroke()
            }
        }
    }
    /// Renders the real menu for inspection without asking for camera access.
    func preview() {
        stop(); wasDrawing = owner?.state.drawing ?? false; isPreview = true; running = true; menuVisible = true; page = "Tools"
        owner?.gestureWindow?.orderOut(nil); pointer = nil; owner?.state.changed()
    }
}

extension AppController {
    func openGestures() {
        gestures.resetInput()
        if gestures.isPreview { gestures.stop() }
        if gestureWindow == nil {
            let window = NSWindow(contentRect:CGRect(x:0,y:0,width:480,height:580),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            window.title = "ScreenInc Hand Gestures"; window.isReleasedWhenClosed = false; window.level = .init(rawValue:NSWindow.Level.floating.rawValue+2)
            let host = NSHostingView(rootView:GestureSettings(gestures:gestures,controller:self)); window.contentView = host; window.setContentSize(host.fittingSize); window.center(); gestureWindow = window
        }
        gestureWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
}
struct GestureSettings: View {
    @ObservedObject var gestures: GestureController
    let controller: AppController
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Label("1. Check your hand",systemImage:"hand.draw").font(.title2.bold())
            Text("Point to aim. Pinch thumb and index finger to draw. Release to lift the pen. Hold an open palm to choose tools.").fixedSize(horizontal:false,vertical:true)
            Text("Camera processing stays on this Mac. Nothing is recorded or uploaded.").font(.caption).foregroundStyle(.secondary)
            Picker("Camera",selection:$gestures.deviceID) {
                Text("Default camera").tag("")
                ForEach(HandCamera.devices,id:\.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
            }.disabled(gestures.running || gestures.requesting)
            Picker("Screen",selection:$gestures.displayIndex) {
                ForEach(Array(controller.canvases.enumerated()),id:\.offset) { index,canvas in Text("Screen \(index+1) · \(Int(canvas.bounds.width)) × \(Int(canvas.bounds.height))").tag(index) }
            }.onChange(of:gestures.displayIndex) { _,_ in gestures.resetInput() }
            Toggle("Mirror hand movement",isOn:$gestures.mirrored).onChange(of:gestures.mirrored) { _,_ in gestures.resetInput() }
            HStack { Text("Smaller hand travel"); Slider(value:$gestures.reach,in:0...0.3).onChange(of:gestures.reach) { _,_ in gestures.resetInput() } }
            HStack { Text("Smoothing"); Slider(value:$gestures.smoothing,in:0.03...0.18) }
            HStack { Text("Pinch sensitivity"); Slider(value:$gestures.pinchThreshold,in:0.22...0.55).onChange(of:gestures.pinchThreshold) { _,_ in gestures.resetInput() } }
            if gestures.running && !gestures.isPreview {
                CameraPreview(session:gestures.camera.session,mirrored:gestures.mirrored).frame(height:130).clipShape(RoundedRectangle(cornerRadius:10))
                HStack { Text(gestures.gestureLabel).fontWeight(.semibold); Spacer(); Text("\(gestures.trackingFPS) fps · \(gestures.frameDelay) ms").foregroundStyle(.secondary) }.font(.caption)
            }
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius:10).fill(.gray.opacity(0.1))
                    Text(gestures.calibrationPoint == nil ? "Keep one hand visible, facing the camera" : "Move the pointer to each corner to check your reach").font(.caption).foregroundStyle(.secondary)
                    if let point = gestures.calibrationPoint { Circle().fill(.orange).frame(width:14,height:14).position(x:point.x*geometry.size.width,y:point.y*geometry.size.height) }
                }
            }.frame(height:50)
            Text(gestures.running ? "This window is for setup. Choose Start drawing to close it and draw on your screen." : gestures.status).font(.caption).foregroundStyle(gestures.running ? .primary : .secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button(gestures.running || gestures.requesting ? "Stop camera" : "Start camera") { gestures.running || gestures.requesting ? gestures.stop() : gestures.start() }.buttonStyle(.borderedProminent)
                if gestures.running { Button("2. Start drawing",action:gestures.beginDrawing).buttonStyle(.borderedProminent) }
                Spacer()
                Button("Preview menu") { gestures.preview() }.disabled(gestures.requesting)
            }
            Text("Tools include shapes, eraser, selection, laser and spotlight. Text entry and image import still use the normal controls. If tracking is lost, separate thumb and finger before drawing again.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(24).frame(width:480)
        .onChange(of:gestures.running) { _,_ in
            if let host = controller.gestureWindow?.contentView { host.layoutSubtreeIfNeeded(); controller.gestureWindow?.setContentSize(host.fittingSize) }
        }
    }
}

/// Local camera preview only. This layer does not retain or upload camera frames.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    func makeNSView(context: Context) -> CameraPreviewView { let view = CameraPreviewView(); view.preview.session = session; return view }
    func updateNSView(_ view: CameraPreviewView,context: Context) {
        if let connection = view.preview.connection, connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = mirrored }
    }
}
final class CameraPreviewView: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame: CGRect) { super.init(frame:frame); wantsLayer = true; preview.videoGravity = .resizeAspect; layer?.addSublayer(preview) }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); preview.frame = bounds }
}
