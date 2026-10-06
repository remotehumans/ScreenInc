import AppKit

struct SavedDrawing: Codable, Identifiable {
    var id = UUID()
    var title: String
    var date = Date()
    var strokes: [InkStroke]
    var thumbnail: Data?
}
struct Recovery: Codable {
    var strokes: [InkStroke]
    var preferences: InkPreferences
    var color: InkColor
    var width: Double
    var fadeDelay: Double
    var whiteboard: Bool
    var tool: InkTool? = nil
}
final class InkPersistence {
    let directory: URL
    private var pending: DispatchWorkItem?
    init(directory: URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ScreenInc")) { self.directory = directory }
    func load(_ state: InkState) {
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let url = directory.appendingPathComponent("recovery.json")
            if FileManager.default.fileExists(atPath:url.path) {
                let saved = try JSONDecoder().decode(Recovery.self,from:Data(contentsOf:url))
                state.tool = saved.tool ?? .pen; state.preferences = saved.preferences; state.preferences.magnify = false; state.color = saved.color; state.width = saved.width; state.fadeDelay = saved.fadeDelay; state.whiteboard = saved.whiteboard
                state.history.replace(saved.strokes.filter { $0.opacity() > 0 }); state.lastDrawing = state.history.strokes.last; state.message = "Previous session recovered"
            }
            let libraryURL = directory.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath:libraryURL.path) { state.library = try JSONDecoder().decode([SavedDrawing].self,from:Data(contentsOf:libraryURL)) }
        } catch { state.message = "Could not restore saved data: \(error.localizedDescription)" }
    }
    func scheduleSave(_ state: InkState) {
        pending?.cancel(); let work = DispatchWorkItem { [weak self, weak state] in if let self, let state { self.save(state) } }; pending = work; DispatchQueue.main.asyncAfter(deadline:.now()+0.3,execute:work)
    }
    func save(_ state: InkState) {
        pending?.cancel()
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            var preferences = state.preferences; preferences.toolColors[state.tool.rawValue] = state.color
            let recovery = Recovery(strokes:state.visibleStrokes(),preferences:preferences,color:state.color,width:state.width,fadeDelay:state.fadeDelay,whiteboard:state.whiteboard,tool:state.tool)
            try JSONEncoder().encode(recovery).write(to:directory.appendingPathComponent("recovery.json"),options:.atomic)
            try JSONEncoder().encode(state.library).write(to:directory.appendingPathComponent("library.json"),options:.atomic)
        } catch { state.message = "Save failed: \(error.localizedDescription)" }
    }
}
enum InkExport {
    static func image(strokes: [InkStroke], size: CGSize, background: InkColor? = nil) -> NSImage {
        let image = NSImage(size:size); image.lockFocusFlipped(true)
        if let background { background.ns.setFill(); CGRect(origin:.zero,size:size).fill() }
        strokes.forEach { $0.draw() }; image.unlockFocus(); return image
    }
    static func png(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let data = bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }; return data
    }
    static func pdf(strokes: [InkStroke], size: CGSize, background: InkColor?) throws -> Data {
        let data = NSMutableData(); var box = CGRect(origin:.zero,size:size)
        guard let consumer = CGDataConsumer(data:data), let context = CGContext(consumer:consumer,mediaBox:&box,nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil); context.translateBy(x:0,y:size.height); context.scaleBy(x:1,y:-1)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:true)
        if let background { background.ns.setFill(); box.fill() }; strokes.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState(); context.endPDFPage(); context.closePDF(); return data as Data
    }
    // PSD v1: uncompressed, flattened RGB with an alpha channel. PDF retains vectors.
    static func psd(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff) else { throw CocoaError(.fileWriteUnknown) }
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
        guard w > 0, h > 0, w <= 30000, h <= 30000 else { throw CocoaError(.fileWriteUnknown) }
        var data = Data("8BPS".utf8)
        func u16(_ value: UInt16) { var v = value.bigEndian; withUnsafeBytes(of:&v) { data.append(contentsOf:$0) } }
        func u32(_ value: UInt32) { var v = value.bigEndian; withUnsafeBytes(of:&v) { data.append(contentsOf:$0) } }
        u16(1); data.append(Data(repeating:0,count:6)); u16(4); u32(UInt32(h)); u32(UInt32(w)); u16(8); u16(3)
        u32(0)
        let profile = NSColorSpace.sRGB.iccProfileData ?? Data()
        u32(UInt32(12+profile.count+(profile.count%2)))
        data.append(Data("8BIM".utf8)); u16(1039); u16(0); u32(UInt32(profile.count)); data.append(profile)
        if profile.count%2 != 0 { data.append(0) }
        u32(0); u16(0)
        var rgba = [UInt8](repeating:0,count:w*h*4)
        guard let cg = bitmap.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data:bytes.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h)); return true
        }
        guard rendered else { throw CocoaError(.fileWriteUnknown) }
        var channels = [[UInt8]](repeating:[UInt8](repeating:0,count:w*h),count:4)
        for i in 0..<(w*h) {
            let alpha = Int(rgba[i*4+3]); channels[3][i] = UInt8(alpha)
            for c in 0..<3 { channels[c][i] = alpha == 0 ? 0 : UInt8(min(255,(Int(rgba[i*4+c])*255+alpha/2)/alpha)) }
        }
        channels.forEach { data.append(contentsOf:$0) }; return data
    }
}
extension InkState {
    func saveSnapshot(size: CGSize) {
        var strokes = visibleStrokes(); for i in strokes.indices { strokes[i].fadeAfter = nil }
        let image = InkExport.image(strokes:strokes,size:size,background:whiteboard ? preferences.boardColor : nil)
        library.append(SavedDrawing(title:"Drawing \(library.count+1)",strokes:strokes,thumbnail:try? InkExport.png(image)))
        libraryIndex = library.count-1; message = "Snapshot saved"; changed()
    }
    func restoreSnapshot(_ index: Int, display: String, knownDisplays: Set<String>) {
        guard library.indices.contains(index) else { return }
        var strokes = library[index].strokes
        for i in strokes.indices { strokes[i].created = Date(); strokes[i].fadeAfter = nil; if !knownDisplays.contains(strokes[i].display) { strokes[i].display = display } }
        history.replace(strokes); selection = []; libraryIndex = index; message = library[index].title; changed()
    }
}
