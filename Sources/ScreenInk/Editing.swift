import AppKit

struct InkStyle: Codable, Equatable {
    var gradient = false
    var endColor = InkColor.palette[3]
    var opacity = 1.0
    var shadow = false
}
struct InkPreferences: Codable {
    var style = InkStyle()
    var boardColor = InkColor(red:0.949,green:0.941,blue:0.914)
    var toolColors: [String:InkColor] = [:]
    var partialEraser = true
    var halo = false
    var clicks = false
    var spotlightRadius = 110.0
    var magnification = 2.0
    var magnify = false
    var shortcutKeys: [String:String] = [:]
    var toggleKey: UInt32 = 2
    var toggleModifiers: UInt32 = 6144
    var holdToDraw = false
    var lowerThirdText = ""
    var countdownSeconds = 60.0
}
extension InkColor {
    init(_ color: NSColor) { let rgb = color.usingColorSpace(.sRGB) ?? .black; self.init(red:rgb.redComponent,green:rgb.greenComponent,blue:rgb.blueComponent) }
}
extension InkStroke {
    var bounds: CGRect {
        if tool == .text, let first = points.first?.cg { return CGRect(origin:first,size:(text as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:max(22,width*5),weight:.semibold)])) }
        if tool == .badge, let first = points.first?.cg { let radius = max(5,width*4.75); return CGRect(x:first.x-radius,y:first.y-radius,width:radius*2,height:radius*2) }
        return points.reduce(CGRect.null) { $0.union(CGRect(origin:$1.cg,size:CGSize(width:0.01,height:0.01))) }.insetBy(dx:-width/2,dy:-width/2)
    }
    mutating func translate(_ delta: CGPoint) { points = points.map { InkPoint(CGPoint(x:$0.x+delta.x,y:$0.y+delta.y)) } }
    mutating func resize(around origin: CGPoint, x: Double, y: Double) {
        points = points.map { InkPoint(CGPoint(x:origin.x+($0.x-origin.x)*x,y:origin.y+($0.y-origin.y)*y)) }
        if tool == .text || tool == .badge { width *= max(0.1,min(abs(x),abs(y))) }
    }
    func erasing(at center: CGPoint, radius: Double) -> [InkStroke] {
        guard [.pen,.marker,.laser].contains(tool), points.count > 1 else { return hit(center) ? [] : [self] }
        // Resample so a fast stroke with widely spaced input points still cuts at the eraser.
        var runs: [[InkPoint]] = []; var run: [InkPoint] = []
        var pressureRuns: [[Double]] = []; var pressureRun: [Double] = []
        for i in 1..<points.count {
            let a = points[i-1], b = points[i]; let steps = max(1,Int(ceil(hypot(b.x-a.x,b.y-a.y)/max(1,radius/3))))
            for j in (i == 1 ? 0 : 1)...steps {
                let t = Double(j)/Double(steps); let p = InkPoint(CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t))
                if hypot(p.x-center.x,p.y-center.y) <= radius+width/2 {
                    if !run.isEmpty { runs.append(run); pressureRuns.append(pressureRun); run = []; pressureRun = [] }
                } else { run.append(p); let values = pressures ?? []; pressureRun.append(values.count == points.count ? values[i-1]+(values[i]-values[i-1])*t : 1) }
            }
        }
        if !run.isEmpty { runs.append(run); pressureRuns.append(pressureRun) }
        if runs.count == 1, runs[0].count > 0, !path().cgPath.copy(strokingWithWidth:width+radius*2,lineCap:.round,lineJoin:.round,miterLimit:10).contains(center) { return [self] }
        return runs.enumerated().map { index, points in var copy = self; copy.id = UUID(); copy.points = points; copy.pressures = pressureRuns[index]; return copy }
    }
}
extension InkState {
    var selected: [InkStroke] { visibleStrokes().filter { selection.contains($0.id) } }
    func selectObject(_ stroke: InkStroke, additive: Bool) {
        if !additive { selection = [] }
        let ids = history.strokes.filter { $0.id == stroke.id || (stroke.group != nil && $0.group == stroke.group) }.map(\.id)
        selection.formUnion(ids); changed()
    }
    func changeSelection(_ transform: (inout InkStroke) -> Void) {
        guard !selection.isEmpty else { return }
        var strokes = visibleStrokes()
        for i in strokes.indices where selection.contains(strokes[i].id) { transform(&strokes[i]) }
        history.replace(strokes); changed()
    }
    func deleteSelected() { history.replace(visibleStrokes().filter { !selection.contains($0.id) }); selection = []; changed() }
    func duplicateSelected() {
        let groupMap = Dictionary(uniqueKeysWithValues:Set(selected.compactMap(\.group)).map { ($0,UUID()) })
        let copies = selected.map { item -> InkStroke in var copy = item; copy.id = UUID(); copy.group = item.group.flatMap { groupMap[$0] }; copy.translate(CGPoint(x:20,y:20)); copy.created = Date(); return copy }
        history.replace(visibleStrokes()+copies); selection = Set(copies.map(\.id)); changed()
    }
    func groupSelected() { let id = UUID(); changeSelection { $0.group = id } }
    func ungroupSelected() { changeSelection { $0.group = nil } }
    func recolorSelected() { let color = color, style = preferences.style; changeSelection { $0.color = color; $0.style = style } }
    func reorderSelected(front: Bool) {
        let all = visibleStrokes(), picked = selected, rest = all.filter { !selection.contains($0.id) }
        history.replace(front ? rest+picked : picked+rest); changed()
    }
    func repeatLast(on display: String) {
        guard var copy = lastDrawing else { return }; copy.id = UUID(); copy.created = Date(); copy.display = display; copy.translate(CGPoint(x:20,y:20)); history.append(copy); lastDrawing = copy; changed()
    }
}

extension InkState {
    var shortcutLabel: String {
        let codes: [UInt32:String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",49:"Space"]
        let flags = preferences.toggleModifiers
        return (flags & 4096 != 0 ? "⌃" : "") + (flags & 2048 != 0 ? "⌥" : "") + (flags & 512 != 0 ? "⇧" : "") + (flags & 256 != 0 ? "⌘" : "") + (codes[preferences.toggleKey] ?? "Key \(preferences.toggleKey)")
    }
}
