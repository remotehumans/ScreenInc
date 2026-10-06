import AppKit
import SwiftUI
import Carbon
import UniformTypeIdentifiers
import Combine

final class ToolPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppController: NSObject, NSApplicationDelegate {
    let state = InkState()
    lazy var gestures = GestureController(owner:self)
    var gestureWindow: NSWindow?
    var overlays: [OverlayWindow] = []
    var canvases: [InkCanvas] = []
    var toolbar: NSPanel!
    var status: NSStatusItem!
    var localMonitor: Any?
    var hotKey: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    var previousApp: NSRunningApplication?
    var featuresWindow: NSWindow?
    var subscriptions = Set<AnyCancellable>()
    var flagsMonitor: Any?
    var globalFlagsMonitor: Any?
    var pointerMonitor: Any?
    var heldDrawing: Bool?
    var remote: InkRemote?
    var captureTimer: Timer?
    var capturing = false
    var lastShortcutActivation: TimeInterval = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        previousApp = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(frontmostChanged(_:)),name:NSWorkspace.didActivateApplicationNotification,object:nil)
        NSApp.setActivationPolicy(.regular)
        let mainMenu = NSMenu(); let root = NSMenuItem(); mainMenu.addItem(root)
        let appMenu = NSMenu(); root.submenu = appMenu
        let quitItem = NSMenuItem(title:"Quit ScreenInc",action:#selector(quit),keyEquivalent:"q"); quitItem.target = self; appMenu.addItem(quitItem)
        let studioItem = NSMenuItem(title:"ScreenInc Studio…",action:#selector(openStudioMenu),keyEquivalent:","); studioItem.target = self; appMenu.insertItem(studioItem,at:0)
        let editItem = NSMenuItem(); mainMenu.addItem(editItem)
        let editMenu = NSMenu(title:"Edit"); editItem.submenu = editMenu
        for (title,selector,key) in [("Undo","undo:","z"),("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {
            editMenu.addItem(NSMenuItem(title:title,action:NSSelectorFromString(selector),keyEquivalent:key))
        }
        NSApp.mainMenu = mainMenu
        state.refresh = { [weak self] in guard let self else { return }; self.canvases.forEach { $0.needsDisplay = true }; self.status?.menu?.items.first(where:{ $0.action == #selector(self.toggleDrawing) })?.title = "Draw / click through (\(self.state.shortcutLabel))" }
        let persistence = InkPersistence(); state.persistence = persistence; persistence.load(state)
        state.$preferences.dropFirst().sink { [weak self] _ in self?.state.changed() }.store(in:&subscriptions)
        Publishers.CombineLatest4(state.$color,state.$width,state.$fadeDelay,state.$whiteboard).dropFirst().sink { [weak self] _ in if let self { self.state.persistence?.scheduleSave(self.state) } }.store(in:&subscriptions)
        rebuildScreens()
        toolbar = ToolPanel(contentRect:CGRect(x:0,y:0,width:44,height:380),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        toolbar.title = "ScreenInc tools"; toolbar.isFloatingPanel = true; toolbar.level = .init(rawValue:NSWindow.Level.floating.rawValue+1)
        toolbar.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; toolbar.isOpaque = false; toolbar.backgroundColor = .clear
        toolbar.hasShadow = true; toolbar.isMovableByWindowBackground = true; toolbar.hidesOnDeactivate = false
        let host = NSHostingView(rootView:InkToolbar(state:state,controller:self)); toolbar.contentView = host
        toolbar.setContentSize(host.fittingSize)
        if let screen = NSScreen.main { toolbar.setFrameOrigin(CGPoint(x:screen.visibleFrame.maxX-56,y:screen.visibleFrame.midY-toolbar.frame.height/2)) }
        toolbar.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName:"scribble.variable",accessibilityDescription:"ScreenInc")
        let menu = NSMenu()
        for (title,action) in [("Show tools",#selector(show)),("Draw / click through (⌃⌥D)",#selector(toggleDrawing)),("Clear drawings",#selector(clear)),("Quit ScreenInc",#selector(quit))] {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; menu.addItem(item)
        }
        status.menu = menu
        registerHotKey()
        installPresentationMonitors()
        if CommandLine.arguments.contains("--gesture-settings") { openGestures() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in self?.handle(event) == true ? nil : event }
        NotificationCenter.default.addObserver(self,selector:#selector(rebuildScreens),name:NSApplication.didChangeScreenParametersNotification,object:nil)
    }
    @objc func frontmostChanged(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = app }
    }
    @objc func rebuildScreens() {
        gestures.resetInput()
        canvases.forEach { $0.finishText(); $0.timer?.invalidate() }
        overlays.forEach { $0.close() }; overlays = []; canvases = []
        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
            let window = OverlayWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            window.title = "Drawing canvas"
            window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            window.ignoresMouseEvents = !state.drawing || gestures.running; window.acceptsMouseMovedEvents = true
            let canvas = InkCanvas(frame:CGRect(origin:.zero,size:screen.frame.size),state:state,display:id)
            canvas.gestureOverlay = { [weak self] canvas in self?.gestures.draw(on:canvas) }
            canvas.crossScreenMove = { [weak self, weak canvas] point, ids in self?.moveAcrossScreens(from:canvas,point:point,ids:ids) }
            window.contentView = canvas; window.orderFrontRegardless(); overlays.append(window); canvases.append(canvas)
        }
        if state.drawing { focusCanvas() }
    }
    func registerHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler); self.hotKeyHandler = nil }
        var type = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{ _,_,data in
            guard let data = data else { return noErr }
            let owner = Unmanaged<AppController>.fromOpaque(data).takeUnretainedValue()
            owner.activateDrawingShortcut(); return noErr
        },1,&type,Unmanaged.passUnretained(self).toOpaque(),&hotKeyHandler)
        let result = RegisterEventHotKey(state.preferences.toggleKey,state.preferences.toggleModifiers,EventHotKeyID(signature:0x53494E4B,id:1),GetApplicationEventTarget(),0,&hotKey)
        if result != noErr { state.message = "Shortcut busy · choose another or use the menu bar" } else { state.message = "Drawing shortcut: \(state.shortcutLabel)" }
    }
    func focusCanvas() {
        let mouse = NSEvent.mouseLocation
        let target = overlays.first(where: { $0.frame.contains(mouse) }) ?? overlays.first
        target?.makeKeyAndOrderFront(nil); target?.makeFirstResponder(target?.contentView)
        toolbar?.orderFrontRegardless()
    }
    @objc func openStudioMenu() { openFeatures() }
    @objc func show() { toolbar.orderFrontRegardless() }
    @objc func hide() { toolbar.orderOut(nil) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func toggleDrawing() { setDrawing(!state.drawing) }
    func activateDrawingShortcut() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastShortcutActivation > 0.15 else { return }
        lastShortcutActivation = now; toggleDrawing()
    }
    func setDrawing(_ value: Bool) {
        gestures.resetInput()
        canvases.forEach { $0.finishText(); $0.current = nil; $0.selectionStart = nil; $0.selectionRect = nil; $0.dragPreview = nil; $0.dragOriginal = nil; $0.erasingGesture = false }; state.history.endTransaction()
        if value && !state.drawing, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        state.drawing = value
        overlays.forEach { $0.ignoresMouseEvents = !value || gestures.running; $0.invalidateCursorRects(for:$0.contentView!) }
        if value { NSApp.activate(ignoringOtherApps:true); focusCanvas(); show() }
        else { previousApp?.activate(options:[]); canvases.forEach { $0.pointer = nil } }
        state.changed()
    }
    func select(_ tool: InkTool) { gestures.resetInput(); if tool == .image { importImage(); return }; canvases.forEach { $0.finishText() }; state.tool = tool; featuresWindow?.orderOut(nil); if !state.drawing { setDrawing(true) } else { focusCanvas() }; state.changed() }
    @objc func clear() { canvases.forEach { $0.editor?.removeFromSuperview(); $0.editor = nil; $0.current = nil; $0.lasers = [] }; state.clear() }
    func handle(_ event: NSEvent) -> Bool {
        if NSApp.modalWindow != nil || NSApp.keyWindow?.firstResponder is NSTextView { return false }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if UInt32(event.keyCode) == state.preferences.toggleKey, modifiers == state.preferences.toggleModifiers { activateDrawingShortcut(); return true }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," { openFeatures(); return true }

        guard state.drawing else { return false }
        if canvases.contains(where: { $0.editor != nil }) { return false }
        if featuresWindow?.isKeyWindow == true || gestureWindow?.isKeyWindow == true { return false }
        if event.keyCode == 48 { toolbar.isVisible ? hide() : show(); return true }
        if event.keyCode == 53 { setDrawing(false); return true }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            switch key {
            case "z": event.modifierFlags.contains(.shift) ? state.redo() : state.undo()
            case "s": event.modifierFlags.contains(.shift) ? save() : snapshot()
            case "c": copyDrawing()
            case "d": state.duplicateSelected()
            case "g": event.modifierFlags.contains(.shift) ? state.ungroupSelected() : state.groupSelected()
            case "a": state.selection = Set(state.visibleStrokes().map(\.id)); select(.select)
            case "[": state.reorderSelected(front:false)
            case "]": state.reorderSelected(front:true)
            case "o": load()
            case "\u{7f}": clear()
            default: return false
            }
            return true
        }
        if event.keyCode == 51 { state.deleteSelected(); return true }
        if key == "[" { cycleSnapshot(-1); return true }
        if key == "]" { cycleSnapshot(1); return true }
        if key == ";" { repeatDrawing(); return true }
        if let tool = InkTool.allCases.first(where: { (state.preferences.shortcutKeys[$0.rawValue] ?? $0.key) == key }) { select(tool); return true }
        if key == "f" { state.fadeDelay = state.fadeDelay == 0 ? 2 : 0; return true }
        if key == "w" { state.whiteboard.toggle(); state.changed(); return true }
        if let number = Int(key), (1...7).contains(number) { state.color = InkColor.palette[number-1]; return true }
        return false
    }
    func filePanel(_ action: () -> Void) {
        let wasDrawing = state.drawing
        setDrawing(false); toolbar.orderOut(nil); overlays.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps:true)
        action()
        overlays.forEach { $0.orderFrontRegardless() }; show(); if wasDrawing { setDrawing(true) }
    }
    func save() {
        canvases.forEach { $0.finishText() }
        let snapshot = InkSnapshot(strokes:state.visibleStrokes())
        filePanel {
            let panel = NSSavePanel(); panel.nameFieldStringValue = "ScreenInc.drawings.json"; panel.allowedContentTypes = [.json]
            if panel.runModal() == .OK, let url = panel.url {
                do { try JSONEncoder().encode(snapshot).write(to:url,options:.atomic); state.message = "Drawings saved" } catch { report(error) }
            }
        }
    }
    func load() {
        filePanel {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    let snapshot = try JSONDecoder().decode(InkSnapshot.self,from:Data(contentsOf:url))
                    guard snapshot.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                    var strokes = snapshot.strokes
                    let known = Set(canvases.map(\.display))
                    for index in strokes.indices {
                        if !known.contains(strokes[index].display), let display = canvases.first?.display { strokes[index].display = display }
                        strokes[index].created = Date(); strokes[index].fadeAfter = nil
                    }
                    state.history.replace(strokes); state.changed(); state.message = "Drawings restored · kept on screen"
                } catch { report(error) }
            }
        }
    }
    func export() {
        canvases.forEach { $0.finishText() }
        let canvas = canvases.first(where: { $0.window?.frame.contains(NSEvent.mouseLocation) == true }) ?? canvases.first
        guard let canvas = canvas else { return }
        let strokes = state.visibleStrokes().filter { $0.display == canvas.display }
        filePanel {
            let panel = NSSavePanel(); panel.nameFieldStringValue = "ScreenInc.png"; panel.allowedContentTypes = [.png]
            if panel.runModal() == .OK, let url = panel.url {
                let image = NSImage(size:canvas.bounds.size)
                image.lockFocusFlipped(true)
                if state.whiteboard { state.preferences.boardColor.ns.setFill(); canvas.bounds.fill() }
                strokes.forEach { $0.draw() }; image.unlockFocus()
                do {
                    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let data = bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
                    try data.write(to:url,options:.atomic); state.message = "PNG exported"
                } catch { report(error) }
            }
        }
    }
    func report(_ error: Error) { let alert = NSAlert(error:error); alert.runModal() }
    func applicationWillTerminate(_ notification: Notification) {
        gestures.stop(); state.persistence?.save(state); remote?.stop(); captureTimer?.invalidate()
        for monitor in [flagsMonitor,globalFlagsMonitor,pointerMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }
        if let handler = hotKeyHandler { RemoveEventHandler(handler) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        canvases.forEach { $0.timer?.invalidate() }
    }
}
@main struct ScreenInkApp {
    static func main() {
        let app = NSApplication.shared
        let controller = AppController(); app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
