import AppKit

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
final class InkCanvas: NSView, NSTextViewDelegate {
    let state: InkState
    let display: String
    var gestureOverlay: ((InkCanvas) -> Void)?
    var current: InkStroke?
    var lasers: [InkStroke] = []
    var pointer: CGPoint?
    var editor: NSTextView?
    var editorOrigin: CGPoint?
    var editingStyle: (InkColor,Double)?
    var timer: Timer?
    var toggle: (() -> Void)?
    var selectionStart: CGPoint?
    var selectionRect: CGRect?
    var dragOriginal: [InkStroke]?
    var dragPreview: [InkStroke]?
    var resizing = false
    var tabletEraser = false
    var erasingGesture = false
    var clicks: [(CGPoint,Date)] = []
    var capturedScreen: NSImage?
    var region: CGRect?
    var regionSelecting = false
    var regionComplete: ((CGRect) -> Void)?
    var crossScreenMove: ((CGPoint, Set<UUID>) -> Void)?
    init(frame: CGRect, state: InkState, display: String) {
        self.state = state; self.display = display
        super.init(frame:frame)
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Drawing canvas")
        timer = Timer.scheduledTimer(withTimeInterval:1/30,repeats:true) { [weak self] _ in
            guard let self = self else { return }
            let fading = self.state.history.strokes.contains { $0.display == self.display && $0.fadeAfter != nil && Date().timeIntervalSince($0.created) < ($0.fadeAfter! + 1.2) }
            guard fading || !self.lasers.isEmpty || !self.clicks.isEmpty || self.state.countdownEnd != nil else { return }
            self.clicks.removeAll { Date().timeIntervalSince($0.1) > 0.6 }
            self.lasers.removeAll { Date().timeIntervalSince($0.created) > 1.2 }
            self.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds,cursor: state.drawing ? .crosshair : .arrow) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.mouseMoved,.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil))
    }
    override func draw(_ dirtyRect: NSRect) {
        defer { gestureOverlay?(self) }
        NSColor.clear.setFill(); bounds.fill(using:.copy)
        if state.drawing { NSColor.black.withAlphaComponent(0.001).setFill(); bounds.fill() }
        if state.whiteboard && state.drawing { state.preferences.boardColor.ns.setFill(); bounds.fill() }
        for stroke in dragPreview ?? state.history.strokes where stroke.display == display { stroke.draw(opacity:stroke.opacity()) }
        current?.draw()
        for laser in lasers { laser.draw(opacity:max(0,1-Date().timeIntervalSince(laser.created)/1.2)) }
        drawPresentation()
        for stroke in dragPreview ?? state.selected where state.drawing && state.tool == .select && state.selection.contains(stroke.id) && stroke.display == display {
            NSColor.controlAccentColor.setStroke(); let box = stroke.bounds.insetBy(dx:-5,dy:-5); let path = NSBezierPath(rect:box); path.setLineDash([4,3],count:2,phase:0); path.stroke()
            NSColor.controlAccentColor.setFill(); CGRect(x:box.maxX-4,y:box.maxY-4,width:8,height:8).fill()
        }
        if let selectionRect { NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); selectionRect.fill(); NSColor.controlAccentColor.setStroke(); NSBezierPath(rect:selectionRect).stroke() }
        if state.tool == .spotlight && state.drawing, let pointer = pointer {
            let radius = state.preferences.spotlightRadius
            let spot = region ?? CGRect(x:pointer.x-radius,y:pointer.y-radius,width:radius*2,height:radius*2)
            let shade = NSBezierPath(rect:bounds)
            if region == nil { shade.appendOval(in:spot) } else { shade.appendRect(spot) }; shade.windingRule = .evenOdd
            if state.preferences.magnify, let screen = capturedScreen {
                NSGraphicsContext.saveGraphicsState()
                let clip = region == nil ? NSBezierPath(ovalIn:spot) : NSBezierPath(rect:spot); clip.addClip()
                let zoom = state.preferences.magnification
                screen.draw(in:spot,from:CGRect(x:spot.midX-spot.width/zoom/2,y:screen.size.height-spot.midY-spot.height/zoom/2,width:spot.width/zoom,height:spot.height/zoom),operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                NSGraphicsContext.restoreGraphicsState()
            }
            NSColor.black.withAlphaComponent(0.62).setFill(); shade.fill()
        }
    }
    override func mouseMoved(with event: NSEvent) { pointer = convert(event.locationInWindow,from:nil); if state.tool == .spotlight || state.preferences.halo { needsDisplay = true } }
    override func mouseExited(with event: NSEvent) { pointer = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        pointerDown(at:convert(event.locationInWindow,from:nil),modifiers:event.modifierFlags,pressure:event.subtype == .tabletPoint ? Double(event.pressure) : nil)
    }
    func pointerDown(at point: CGPoint, modifiers: NSEvent.ModifierFlags = [], pressure: Double? = nil) {
        guard state.drawing else { return }
        if editor != nil { finishText(); return }
        pointer = point
        window?.makeFirstResponder(self)
        if state.preferences.clicks { clicks.append((point,Date())) }
        if regionSelecting { selectionStart = point; return }
        if state.tool == .select {
            selectionStart = point
            if let hit = state.visibleStrokes().last(where:{ $0.display == display && $0.hit(point) }) {
                if !state.selection.contains(hit.id) { state.selectObject(hit,additive:modifiers.contains(.shift)) }
            } else if !state.selected.contains(where:{ CGRect(x:$0.bounds.maxX-8,y:$0.bounds.maxY-8,width:20,height:20).contains(point) }) {
                if !modifiers.contains(.shift) { state.selection = [] }; selectionRect = CGRect(origin:point,size:.zero); return
            }
            resizing = state.selected.contains { CGRect(x:$0.bounds.maxX-8,y:$0.bounds.maxY-8,width:20,height:20).contains(point) }
            dragOriginal = state.visibleStrokes(); return
        }
        if state.tool == .text { beginText(at:point); return }
        if state.tool == .eraser || tabletEraser { state.history.beginTransaction(); erasingGesture = true; erase(at:point); return }
        if state.tool == .spotlight { needsDisplay = true; return }
        current = InkStroke(tool:state.tool,points:[InkPoint(point)],color:state.color,width:state.tool == .marker ? state.width*5 : state.width,display:display)
        current?.style = state.preferences.style
        if let pressure { current?.pressures = [pressure] }
        if state.tool == .badge { current?.text = String(state.nextBadge); state.nextBadge += 1 }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        pointerDragged(to:convert(event.locationInWindow,from:nil),modifiers:event.modifierFlags,pressure:Double(event.pressure))
    }
    func pointerDragged(to point: CGPoint, modifiers: NSEvent.ModifierFlags = [], pressure: Double = 1) {
        guard state.drawing else { return }
        pointer = point
        if let start = selectionStart {
            if regionSelecting || selectionRect != nil { selectionRect = CGRect(x:min(start.x,point.x),y:min(start.y,point.y),width:abs(point.x-start.x),height:abs(point.y-start.y)); needsDisplay = true; return }
            if let original = dragOriginal {
                let selected = original.filter { state.selection.contains($0.id) }
                let box = selected.reduce(CGRect.null) { $0.union($1.bounds) }
                dragPreview = original.map { item in var stroke = item
                    if state.selection.contains(item.id) {
                        if resizing { stroke.resize(around:box.origin,x:max(0.1,(box.width+point.x-start.x)/max(1,box.width)),y:max(0.1,(box.height+point.y-start.y)/max(1,box.height))) }
                        else { stroke.translate(CGPoint(x:point.x-start.x,y:point.y-start.y)) }
                    }; return stroke
                }; needsDisplay = true; return
            }
        }
        if state.tool == .eraser || tabletEraser { erase(at:point); return }
        guard var stroke = current else { needsDisplay = true; return }
        if [.pen,.marker,.laser].contains(stroke.tool) { stroke.points.append(InkPoint(point)); if stroke.pressures != nil { stroke.pressures?.append(pressure) } }
        else {
            var end = point
            if modifiers.contains(.shift), let first = stroke.points.first?.cg {
                let dx = point.x-first.x, dy = point.y-first.y
                if [.rectangle,.ellipse].contains(stroke.tool) { let side = max(abs(dx),abs(dy)); end = CGPoint(x:first.x+(dx<0 ? -side:side),y:first.y+(dy<0 ? -side:side)) }
                else { let length = hypot(dx,dy); let angle = (atan2(dy,dx) / (.pi/4)).rounded() * (.pi/4); end = CGPoint(x:first.x+length*cos(angle),y:first.y+length*sin(angle)) }
            }
            stroke.points = [stroke.points[0],InkPoint(end)]
        }
        current = stroke; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { pointerUp(screenPoint:NSEvent.mouseLocation) }
    func pointerUp(screenPoint: CGPoint? = nil) {
        if erasingGesture { state.history.endTransaction(); erasingGesture = false; return }
        if let rect = selectionRect {
            if regionSelecting { region = rect; regionSelecting = false; regionComplete?(rect) }
            else { state.selection.formUnion(state.visibleStrokes().filter { $0.display == display && rect.intersects($0.bounds) }.map(\.id)) }
        }
        if let preview = dragPreview { state.history.replace(preview); if let screenPoint { crossScreenMove?(screenPoint,state.selection) } }
        if selectionStart != nil { selectionStart = nil; selectionRect = nil; dragOriginal = nil; dragPreview = nil; state.changed(); return }
        guard var stroke = current else { return }
        stroke.created = Date(); stroke.fadeAfter = state.fadeDelay > 0 ? state.fadeDelay : nil
        if stroke.tool == .laser { lasers.append(stroke) } else { state.history.append(stroke); state.lastDrawing = stroke }
        current = nil; state.changed()
    }
    override func tabletProximity(with event: NSEvent) { tabletEraser = event.isEnteringProximity && event.pointingDeviceType == .eraser }
    override func scrollWheel(with event: NSEvent) {
        if state.tool == .spotlight { state.preferences.spotlightRadius = min(500,max(30,state.preferences.spotlightRadius+Double(event.scrollingDeltaY))) }
        else if state.tool == .eraser { state.width = min(80,max(2,state.width+Double(event.scrollingDeltaY))) }
        state.changed()
    }
    func erase(at point: CGPoint) {
        let all = state.visibleStrokes()
        guard let index = all.lastIndex(where: { $0.display == display && $0.path().cgPath.copy(strokingWithWidth:$0.width+max(24,state.width*4),lineCap:.round,lineJoin:.round,miterLimit:10).contains(point) || ($0.display == display && $0.hit(point)) }) else { return }
        var next = all
        let pieces = state.preferences.partialEraser ? all[index].erasing(at:point,radius:max(12,state.width*2)) : []
        next.replaceSubrange(index...index,with:pieces); state.history.replace(next); state.changed()
    }
    func drawPresentation() {
        if state.preferences.halo, let pointer {
            NSColor.systemYellow.withAlphaComponent(0.22).setFill(); NSBezierPath(ovalIn:CGRect(x:pointer.x-22,y:pointer.y-22,width:44,height:44)).fill()
        }
        for (point,date) in clicks {
            let progress = min(1,Date().timeIntervalSince(date)/0.6), radius = 12+progress*35
            NSColor.systemOrange.withAlphaComponent(1-progress).setStroke(); let path = NSBezierPath(ovalIn:CGRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2)); path.lineWidth = 3; path.stroke()
        }
        if let end = state.countdownEnd {
            let seconds = max(0,Int(ceil(end.timeIntervalSinceNow)))
            let text = String(format:"%02d:%02d",seconds/60,seconds%60)
            drawLabel(text,at:CGPoint(x:bounds.maxX-170,y:30),font:42)
        }
        if !state.lowerThird.isEmpty { drawLabel(state.lowerThird,at:CGPoint(x:40,y:bounds.maxY-100),font:28) }
    }
    func drawLabel(_ text: String, at point: CGPoint, font: Double) {
        let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize:font,weight:.semibold),.foregroundColor:NSColor.white]
        let size = (text as NSString).size(withAttributes:attrs)
        NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect:CGRect(x:point.x-12,y:point.y-8,width:size.width+24,height:size.height+16),xRadius:10,yRadius:10).fill()
        (text as NSString).draw(at:point,withAttributes:attrs)
    }
    func beginText(at point: CGPoint) {
        let x = min(point.x,max(0,bounds.width-260)), y = min(point.y,max(0,bounds.height-50))
        let field = NSTextView(frame:CGRect(x:x,y:y,width:min(500,bounds.width-x),height:min(200,bounds.height-y)))
        field.font = .systemFont(ofSize:max(22,state.width*5),weight:.semibold); field.textColor = state.color.ns
        field.backgroundColor = NSColor.windowBackgroundColor; field.isRichText = false; field.isVerticallyResizable = false
        field.setAccessibilityLabel("Drawing text. Return adds a line. Command Return finishes.")
        field.delegate = self; editorOrigin = CGPoint(x:x,y:y); editingStyle = (state.color,state.width); editor = field
        addSubview(field); window?.makeFirstResponder(field)
    }
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)), NSApp.currentEvent?.modifierFlags.contains(.command) == true { finishText(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { editor?.removeFromSuperview(); editor = nil; window?.makeFirstResponder(self); return true }
        return false
    }
    func finishText() {
        guard let editor = editor else { return }
        let text = editor.string.trimmingCharacters(in:.whitespacesAndNewlines)
        if !text.isEmpty, let point = editorOrigin, let style = editingStyle {
            var stroke = InkStroke(tool:.text,points:[InkPoint(point)],color:style.0,width:style.1,text:text,display:display,fadeAfter:state.fadeDelay > 0 ? state.fadeDelay : nil); stroke.style = state.preferences.style; state.history.append(stroke); state.lastDrawing = stroke
        }
        editor.removeFromSuperview(); self.editor = nil; window?.makeFirstResponder(self); state.changed()
    }
}
