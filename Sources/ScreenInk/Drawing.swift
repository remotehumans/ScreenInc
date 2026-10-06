import AppKit
import SwiftUI

enum InkTool: String, Codable, CaseIterable {
    case pen, marker, arrow, line, rectangle, ellipse, text, eraser, laser, spotlight, select, triangle, badge, image
    var symbol: String {
        switch self {
        case .select: return "cursorarrow.and.square.on.square.dashed"
        case .triangle: return "triangle"
        case .badge: return "number.circle"
        case .image: return "photo"
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .eraser: return "eraser"
        case .laser: return "cursorarrow.rays"
        case .spotlight: return "flashlight.on.fill"
        }
    }
    var key: String {
        switch self {
        case .select: return "v"
        case .triangle: return "g"
        case .badge: return "n"
        case .image: return "i"
        case .pen: return "b"
        case .marker: return "h"
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .text: return "t"
        case .eraser: return "e"
        case .laser: return "x"
        case .spotlight: return "s"
        }
    }
    var label: String { rawValue.capitalized }
}
struct InkPoint: Codable, Equatable {
    var x: Double
    var y: Double
    init(_ point: CGPoint) { x = point.x; y = point.y }
    var cg: CGPoint { CGPoint(x: x, y: y) }
}
struct InkColor: Codable, Equatable {
    var red: Double; var green: Double; var blue: Double
    var ns: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var swift: Color { Color(nsColor: ns) }
    static let palette: [InkColor] = [
        .init(red: 0.88, green: 0.31, blue: 0.09), .init(red: 0.98, green: 0.77, blue: 0.18),
        .init(red: 0.23, green: 0.78, blue: 0.61), .init(red: 0.26, green: 0.63, blue: 1),
        .init(red: 0.90, green: 0.40, blue: 0.66), .init(red: 0.96, green: 0.95, blue: 0.91),
        .init(red: 0.08, green: 0.08, blue: 0.07)]
}
struct InkStroke: Codable, Identifiable {
    var id = UUID()
    var tool: InkTool
    var points: [InkPoint]
    var color: InkColor
    var width: Double
    var text = ""
    var created = Date()
    var display: String
    var fadeAfter: Double? = nil
    var style: InkStyle? = nil
    var group: UUID? = nil
    var pressures: [Double]? = nil
    var imageData: Data? = nil
    func opacity(at now: Date = Date()) -> Double {
        guard let delay = fadeAfter else { return 1 }
        let progress = min(1,max(0,(now.timeIntervalSince(created)-delay)/1.0))
        return 1-progress*progress*(3-2*progress)
    }
    var rect: CGRect {
        guard let first = points.first?.cg, let last = points.last?.cg else { return .zero }
        return CGRect(x: min(first.x,last.x), y: min(first.y,last.y), width: abs(last.x-first.x), height: abs(last.y-first.y))
    }
    func path() -> NSBezierPath {
        let p = NSBezierPath(); p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round
        guard let first = points.first?.cg else { return p }
        let last = points.last!.cg
        switch tool {
        case .triangle:
            p.move(to:CGPoint(x:rect.midX,y:rect.minY)); p.line(to:CGPoint(x:rect.maxX,y:rect.maxY)); p.line(to:CGPoint(x:rect.minX,y:rect.maxY)); p.close()
        case .rectangle: p.appendRect(rect)
        case .ellipse: p.appendOval(in: rect)
        case .arrow:
            p.move(to: first); p.line(to: last)
            let a = atan2(last.y-first.y,last.x-first.x), length = max(16, width*3)
            for offset in [-0.5, 0.5] {
                p.move(to: last); p.line(to: CGPoint(x:last.x-length*cos(a+offset), y:last.y-length*sin(a+offset)))
            }
        case .line: p.move(to: first); p.line(to: last)
        default:
            p.move(to: first)
            if points.count == 1 { p.line(to: CGPoint(x: first.x+0.01,y:first.y)) }
            if points.count < 3 { for point in points.dropFirst() { p.line(to:point.cg) } }
            else {
                var previous = first
                for index in 1..<points.count {
                    let control = points[index-1].cg, next = points[index].cg
                    let end = CGPoint(x:(control.x+next.x)/2,y:(control.y+next.y)/2)
                    p.curve(to:end,controlPoint1:CGPoint(x:previous.x+(control.x-previous.x)*2/3,y:previous.y+(control.y-previous.y)*2/3),controlPoint2:CGPoint(x:end.x+(control.x-end.x)*2/3,y:end.y+(control.y-end.y)*2/3))
                    previous = end
                }
                p.line(to:last)
            }
        }
        return p
    }
    func draw(opacity: Double = 1) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let appearance = style ?? InkStyle()
        let alpha = opacity * appearance.opacity * (tool == .marker ? 0.32 : 1)
        if appearance.shadow { let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.45); shadow.shadowBlurRadius = 5; shadow.shadowOffset = NSSize(width:1,height:-2); shadow.set() }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setAlpha(alpha)
        if appearance.shadow { context.beginTransparencyLayer(auxiliaryInfo:nil) }
        context.saveGState()
        defer { context.restoreGState(); if appearance.shadow { context.endTransparencyLayer() } }
        if tool == .image, let data = imageData, let image = NSImage(data:data) { context.clip(to:rect); image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil); return }
        if tool == .badge, let first = points.first?.cg {
            let radius = max(5,width*4.75)
            color.ns.setFill(); NSBezierPath(ovalIn:CGRect(x:first.x-radius,y:first.y-radius,width:radius*2,height:radius*2)).fill()
            let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.boldSystemFont(ofSize:max(6,width*5.5)),.foregroundColor:NSColor.white]
            let size = (text as NSString).size(withAttributes:attrs)
            (text as NSString).draw(at:CGPoint(x:first.x-size.width/2,y:first.y-size.height/2),withAttributes:attrs); return
        }
        if tool == .text, let first = points.first?.cg {
            (text as NSString).draw(at:first,withAttributes:[.font:NSFont.systemFont(ofSize:max(22,width*5),weight:.semibold),.foregroundColor:color.ns]); return
        }
        let outline = CGMutablePath()
        if let pressures = pressures, pressures.count == points.count, points.count > 1, [.pen,.marker].contains(tool) {
            for i in 1..<points.count {
                let segment = CGMutablePath(); segment.move(to:points[i-1].cg); segment.addLine(to:points[i].cg)
                outline.addPath(segment.copy(strokingWithWidth:width * max(0.12,(pressures[i-1]+pressures[i])/2),lineCap:.round,lineJoin:.round,miterLimit:10))
            }
        } else { outline.addPath(path().cgPath.copy(strokingWithWidth:width,lineCap:.round,lineJoin:.round,miterLimit:10)) }
        context.addPath(outline); context.clip()
        let colors = appearance.gradient ? [color.ns.cgColor,appearance.endColor.ns.cgColor] : [color.ns.cgColor,color.ns.cgColor]
        if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors as CFArray,locations:[0,1]) {
            let box = outline.boundingBoxOfPath
            context.drawLinearGradient(gradient,start:CGPoint(x:box.minX,y:box.minY),end:CGPoint(x:max(box.minX+1,box.maxX),y:box.maxY),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
        }
    }
    func hit(_ point: CGPoint) -> Bool {
        if tool == .image { return rect.contains(point) }
        if tool == .badge, let first = points.first?.cg { return hypot(point.x-first.x,point.y-first.y) < max(5,width*4.75)+5 }
        if tool == .text, let first = points.first?.cg {
            let size = (text as NSString).size(withAttributes: [.font:NSFont.systemFont(ofSize:max(22,width*5),weight:.semibold)])
            return CGRect(origin:first,size:size).insetBy(dx:-10,dy:-10).contains(point)
        }
        // Use a widened outline, so the empty centre of shapes does not erase them.
        let path = self.path().cgPath
        return path.copy(strokingWithWidth: max(width+16,24),lineCap:.round,lineJoin:.round,miterLimit:10).contains(point)
    }
}
extension NSBezierPath {
    var cgPath: CGPath {
        let result = CGMutablePath()
        var points = [NSPoint](repeating:.zero,count:3)
        for index in 0..<elementCount {
            switch element(at:index,associatedPoints:&points) {
            case .moveTo: result.move(to:points[0])
            case .lineTo: result.addLine(to:points[0])
            case .curveTo, .cubicCurveTo: result.addCurve(to:points[2],control1:points[0],control2:points[1])
            case .quadraticCurveTo: result.addQuadCurve(to:points[1],control:points[0])
            case .closePath: result.closeSubpath()
            @unknown default: break
            }
        }
        return result
    }
}
struct InkSnapshot: Codable { var version = 1; var strokes: [InkStroke] }
final class InkHistory {
    private(set) var strokes: [InkStroke] = []
    private var undoStack: [[InkStroke]] = []
    private var redoStack: [[InkStroke]] = []
    private var transaction = false
    private var transactionSaved = false
    func beginTransaction() { transaction = true; transactionSaved = false }
    func endTransaction() { transaction = false; transactionSaved = false }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func replace(_ next: [InkStroke]) {
        if !transaction || !transactionSaved { undoStack.append(strokes); if undoStack.count > 100 { undoStack.removeFirst() }; transactionSaved = true }
        redoStack.removeAll(); strokes = next
    }
    func pruneExpired(at date: Date = Date()) {
        strokes.removeAll { $0.opacity(at:date) == 0 }
        undoStack = undoStack.map { $0.filter { $0.opacity(at:date) > 0 } }
        redoStack = redoStack.map { $0.filter { $0.opacity(at:date) > 0 } }
    }
    func append(_ stroke: InkStroke) { pruneExpired(); replace(strokes + [stroke]) }
    func undo() { guard let last = undoStack.popLast() else { return }; redoStack.append(strokes); strokes = last }
    func redo() { guard let last = redoStack.popLast() else { return }; undoStack.append(strokes); strokes = last }
}
final class InkState: ObservableObject {
    @Published var preferences = InkPreferences()
    @Published var selection: Set<UUID> = []
    @Published var library: [SavedDrawing] = []
    @Published var libraryIndex = -1
    @Published var countdownEnd: Date?
    @Published var lowerThird = ""
    @Published var remoteAddress = "Remote is off"
    var nextBadge = 1
    var lastDrawing: InkStroke?
    var persistence: InkPersistence?
    @Published var tool: InkTool = .pen { didSet {
        preferences.toolColors[oldValue.rawValue] = color
        if let saved = preferences.toolColors[tool.rawValue] { color = saved }
    } }
    @Published var color: InkColor = .palette[0]
    @Published var width: Double = 4
    @Published var fadeDelay: Double = 2
    @Published var drawing = false
    @Published var whiteboard = false
    @Published var revision = 0
    @Published var message = "Ready when you are"
    let history = InkHistory()
    var refresh: (() -> Void)?
    func visibleStrokes() -> [InkStroke] { history.strokes.filter { $0.opacity() > 0 } }
    func changed() { revision += 1; refresh?(); persistence?.scheduleSave(self) }
    func undo() { history.undo(); changed() }
    func redo() { history.redo(); changed() }
    func clear() { if !history.strokes.isEmpty { history.replace([]) }; changed() }
}
