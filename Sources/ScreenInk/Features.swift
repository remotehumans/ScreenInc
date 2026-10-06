import AppKit
import SwiftUI
import ScreenCaptureKit
import Carbon

extension AppController {
    var activeCanvas: InkCanvas? { canvases.first(where:{ $0.window?.frame.contains(NSEvent.mouseLocation) == true }) ?? canvases.first }
    func openFeatures() {
        if featuresWindow == nil {
            let window = NSWindow(contentRect:CGRect(x:0,y:0,width:640,height:650),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window.title = "ScreenInc Studio"; window.isReleasedWhenClosed = false; window.level = .floating
            window.contentView = NSHostingView(rootView:FeaturesView(state:state,controller:self)); window.center(); featuresWindow = window
        }
        featuresWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func snapshot() { canvases.forEach { $0.finishText() }; state.saveSnapshot(size:activeCanvas?.bounds.size ?? CGSize(width:1440,height:900)) }
    func cycleSnapshot(_ direction: Int) {
        guard !state.library.isEmpty else { state.message = "Save a snapshot first"; return }
        restoreSnapshot((state.libraryIndex+direction+state.library.count)%state.library.count)
    }
    func restoreSnapshot(_ index: Int) {
        guard let canvas = activeCanvas else { return }
        state.restoreSnapshot(index,display:canvas.display,knownDisplays:Set(canvases.map(\.display)))
    }
    func repeatDrawing() { if let canvas = activeCanvas { state.repeatLast(on:canvas.display) } }
    func moveAcrossScreens(from source: InkCanvas?, point: CGPoint, ids: Set<UUID>) {
        guard let source, let sourceWindow = source.window, let target = canvases.first(where:{ $0.window?.frame.contains(point) == true }), target !== source, let targetWindow = target.window else { return }
        state.selection = ids
        state.changeSelection { stroke in
            stroke.translate(CGPoint(x:sourceWindow.frame.minX-targetWindow.frame.minX,y:targetWindow.frame.maxY-sourceWindow.frame.maxY)); stroke.display = target.display
        }
    }
    func moveSelection(to target: InkCanvas) {
        guard let source = canvases.first(where:{ $0.display == state.selected.first?.display }) else { return }
        let sx = target.bounds.width/max(1,source.bounds.width), sy = target.bounds.height/max(1,source.bounds.height)
        state.changeSelection { $0.resize(around:.zero,x:sx,y:sy); $0.display = target.display }
    }
    func copyDrawing() {
        guard let canvas = activeCanvas else { return }; canvases.forEach { $0.finishText() }
        let strokes = state.visibleStrokes().filter { $0.display == canvas.display }
        let image = InkExport.image(strokes:strokes,size:canvas.bounds.size,background:state.whiteboard ? state.preferences.boardColor : nil)
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]); state.message = "Drawing copied"
    }
    func exportDrawing(_ format: String) {
        canvases.forEach { $0.finishText() }; guard let canvas = activeCanvas else { return }
        let strokes = state.visibleStrokes().filter { $0.display == canvas.display }; let background = state.whiteboard ? state.preferences.boardColor : nil
        filePanel {
            let panel = NSSavePanel(); panel.nameFieldStringValue = "ScreenInc.\(format)"
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    let data: Data
                    if format == "pdf" { data = try InkExport.pdf(strokes:strokes,size:canvas.bounds.size,background:background) }
                    else { let image = InkExport.image(strokes:strokes,size:canvas.bounds.size,background:background); data = try format == "psd" ? InkExport.psd(image) : InkExport.png(image) }
                    try data.write(to:url,options:.atomic); state.message = "\(format.uppercased()) exported"
                } catch { report(error) }
            }
        }
    }
    func importImage() {
        guard let canvas = activeCanvas else { return }
        filePanel {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.tiff]; panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    let data = try Data(contentsOf:url); guard let image = NSImage(data:data), image.size.width > 0 else { throw CocoaError(.fileReadCorruptFile) }
                    let width = min(500,canvas.bounds.width*0.6), height = width*image.size.height/image.size.width
                    var stroke = InkStroke(tool:.image,points:[InkPoint(CGPoint(x:80,y:80)),InkPoint(CGPoint(x:80+width,y:80+height))],color:state.color,width:1,display:canvas.display)
                    stroke.imageData = data; state.history.append(stroke); state.selection = [stroke.id]; state.tool = .select; state.changed()
                } catch { report(error) }
            }
        }
    }
    func installPresentationMonitors() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching:.flagsChanged) { [weak self] event in self?.holdFlags(event); return event }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching:.flagsChanged) { [weak self] event in self?.holdFlags(event) }
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.mouseMoved,.leftMouseDown,.rightMouseDown]) { [weak self] event in
            guard let self, self.state.preferences.halo || self.state.preferences.clicks else { return }
            let point = NSEvent.mouseLocation
            for canvas in self.canvases {
                guard let window = canvas.window else { continue }
                canvas.pointer = window.frame.contains(point) ? CGPoint(x:point.x-window.frame.minX,y:window.frame.maxY-point.y) : nil
                if self.state.preferences.clicks, event.type != .mouseMoved, let pointer = canvas.pointer { canvas.clicks.append((pointer,Date())) }
                canvas.needsDisplay = true
            }
        }
    }
    func holdFlags(_ event: NSEvent) {
        guard state.preferences.holdToDraw else { return }
        let down = event.modifierFlags.contains(.function)
        if down, heldDrawing == nil { heldDrawing = state.drawing; setDrawing(!state.drawing) }
        if !down, let previous = heldDrawing { heldDrawing = nil; setDrawing(previous) }
    }
    func startMagnifier() {
        captureTimer?.invalidate(); captureTimer = nil
        guard state.preferences.magnify else { canvases.forEach { $0.capturedScreen = nil }; state.changed(); return }
        captureScreen()
        captureTimer = Timer.scheduledTimer(withTimeInterval:0.15,repeats:true) { [weak self] _ in self?.captureScreen() }
    }
    func captureScreen(completion: (() -> Void)? = nil) {
        guard !capturing else {
            if let completion { DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { [weak self] in self?.captureScreen(completion:completion) } }; return
        }; capturing = true
        Task { @MainActor in
            defer { capturing = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                let excluded = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
                for canvas in canvases {
                    guard let display = content.displays.first(where:{ String($0.displayID) == canvas.display }) else { continue }
                    let filter = SCContentFilter(display:display,excludingWindows:excluded)
                    let configuration = SCStreamConfiguration(); configuration.width = display.width; configuration.height = display.height; configuration.showsCursor = false
                    let cg = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:configuration)
                    canvas.capturedScreen = NSImage(cgImage:cg,size:canvas.bounds.size); canvas.needsDisplay = true
                }; completion?()
            } catch { state.message = "Screen capture unavailable: \(error.localizedDescription)"; captureTimer?.invalidate(); captureTimer = nil; state.preferences.magnify = false }
        }
    }
    func selectRegion(copy: Bool) {
        featuresWindow?.orderOut(nil); select(.spotlight)
        for canvas in canvases {
            canvas.regionSelecting = true
            canvas.regionComplete = { [weak self, weak canvas] rect in
                guard let self, let canvas else { return }
                self.canvases.forEach { $0.regionSelecting = false }
                guard copy, rect.width > 1, rect.height > 1 else { return }
                self.captureScreen { [weak self, weak canvas] in
                    guard let self, let canvas, let source = canvas.capturedScreen else { return }
                    let image = NSImage(size:rect.size); image.lockFocusFlipped(true)
                    source.draw(in:CGRect(origin:.zero,size:rect.size),from:CGRect(x:rect.minX,y:source.size.height-rect.maxY,width:rect.width,height:rect.height),operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                    image.unlockFocus(); NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]); self.state.message = "Screen region copied"
                }
            }
        }
    }
    func setShortcutPreset(_ alternate: Bool) {
        state.preferences.shortcutKeys = alternate ? ["pen":"p","select":"v","marker":"h","arrow":"a","rectangle":"r","ellipse":"o","line":"l","text":"t","eraser":"e","laser":"x","spotlight":"s","triangle":"g","badge":"n","image":"i"] : [:]
        state.preferences.toggleKey = alternate ? UInt32(kVK_ANSI_B) : UInt32(kVK_ANSI_D)
        state.preferences.toggleModifiers = UInt32(controlKey|optionKey); registerHotKey(); state.changed()
    }
}
