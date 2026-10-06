import XCTest
import AppKit
import PDFKit
@testable import ScreenInk

final class FeatureTests: XCTestCase {
    func line(_ display: String = "test") -> InkStroke { InkStroke(tool:.pen,points:[InkPoint(CGPoint(x:20,y:60)),InkPoint(CGPoint(x:220,y:60))],color:.palette[0],width:8,display:display) }
    func testPartialEraseSplitsSparseSegmentAndUndoRestores() {
        let stroke = line(); let pieces = stroke.erasing(at:CGPoint(x:120,y:60),radius:15)
        XCTAssertEqual(pieces.count,2)
        XCTAssertLessThan(pieces[0].points.last!.x,105); XCTAssertGreaterThan(pieces[1].points.first!.x,135)
        XCTAssertTrue(pieces.allSatisfy { $0.group == stroke.group && $0.color == stroke.color })
        let state = InkState(); state.history.append(stroke); state.history.replace(pieces); state.undo(); XCTAssertEqual(state.history.strokes.first?.id,stroke.id)
    }
    func testGroupDuplicateRecolorReorderResizeAndDelete() {
        let state = InkState(); var a = line(), b = line(); b.translate(CGPoint(x:0,y:70)); a.fadeAfter = nil
        state.history.replace([a,b]); state.selection = [a.id,b.id]; state.groupSelected()
        let group = state.selected[0].group; XCTAssertNotNil(group); XCTAssertEqual(state.selected[1].group,group)
        state.selection = []; state.selectObject(state.history.strokes[0],additive:false); XCTAssertEqual(state.selected.count,2)
        state.duplicateSelected(); XCTAssertEqual(state.history.strokes.count,4); XCTAssertNotEqual(state.selected[0].group,group)
        state.color = .palette[3]; state.preferences.style.gradient = true; state.recolorSelected(); XCTAssertTrue(state.selected.allSatisfy { $0.style?.gradient == true && $0.color == .palette[3] })
        state.changeSelection { $0.resize(around:.zero,x:2,y:2); $0.display = "other" }
        XCTAssertEqual(state.selected.first?.display,"other"); XCTAssertEqual(state.selected.first?.points.first?.x,80)
        state.reorderSelected(front:false); XCTAssertTrue(state.selection.contains(state.history.strokes[0].id))
        state.ungroupSelected(); XCTAssertNil(state.selected.first?.group)
        state.deleteSelected(); XCTAssertEqual(state.history.strokes.count,2); state.undo(); XCTAssertEqual(state.history.strokes.count,4)
    }
    func testSnapshotRecoveryStylesAndToolColorMemory() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let state = InkState(); state.color = .palette[4]; state.tool = .arrow; state.color = .palette[2]; state.tool = .pen
        XCTAssertEqual(state.color,.palette[4]); state.preferences.style.gradient = true; state.preferences.style.opacity = 0.4; state.fadeDelay = 60
        var stroke = line(); stroke.style = state.preferences.style; state.history.append(stroke)
        state.saveSnapshot(size:CGSize(width:300,height:200)); XCTAssertEqual(state.library.count,1)
        state.tool = .arrow; state.color = .palette[1]
        let persistence = InkPersistence(directory:directory); persistence.save(state)
        let restored = InkState(); persistence.load(restored)
        XCTAssertEqual(restored.tool,.arrow); XCTAssertEqual(restored.color,.palette[1]); restored.tool = .pen; XCTAssertEqual(restored.color,.palette[4])
        XCTAssertEqual(restored.library.count,1); XCTAssertEqual(restored.fadeDelay,60); XCTAssertTrue(restored.preferences.style.gradient)
        restored.restoreSnapshot(0,display:"new",knownDisplays:["new"])
        XCTAssertEqual(restored.history.strokes[0].display,"new"); XCTAssertNil(restored.history.strokes[0].fadeAfter)
        XCTAssertEqual(restored.history.strokes[0].style?.opacity,0.4)
    }
    func testLegacySnapshotWithoutNewFieldsDecodes() throws {
        let data = try JSONEncoder().encode(InkSnapshot(strokes:[line()]))
        let restored = try JSONDecoder().decode(InkSnapshot.self,from:data)
        XCTAssertNil(restored.strokes[0].style); XCTAssertNil(restored.strokes[0].pressures)
    }
    func testPNGAndPDFAndPSDOpenWithCorrectDimensions() throws {
        _ = NSApplication.shared
        let size = CGSize(width:300,height:200), stroke = line()
        let image = InkExport.image(strokes:[stroke],size:size)
        let png = try InkExport.png(image), pdf = try InkExport.pdf(strokes:[stroke],size:size,background:nil), psd = try InkExport.psd(image)
        XCTAssertNotNil(NSImage(data:png)); let document = PDFDocument(data:pdf); XCTAssertEqual(document?.pageCount,1); XCTAssertEqual(document?.page(at:0)?.bounds(for:.mediaBox).size,size)
        XCTAssertEqual(String(data:psd.prefix(4),encoding:.ascii),"8BPS")
        let decoded = try XCTUnwrap(NSBitmapImageRep(data:psd)); let original = try XCTUnwrap(NSBitmapImageRep(data:png))
        XCTAssertEqual(decoded.pixelsWide,original.pixelsWide); XCTAssertEqual(decoded.pixelsHigh,original.pixelsHigh)
        XCTAssertEqual(decoded.colorAt(x:0,y:0)?.alphaComponent,0)
        let scale = Double(original.pixelsWide)/300
        // PSD explicitly encodes sRGB; compare stored components to the source ink.
        let pixel = decoded.colorAt(x:Int(100*scale),y:Int(60*scale))!
        XCTAssertEqual(pixel.redComponent,stroke.color.red,accuracy:0.01)
        XCTAssertEqual(pixel.greenComponent,stroke.color.green,accuracy:0.01)
        XCTAssertEqual(pixel.blueComponent,stroke.color.blue,accuracy:0.01)
        XCTAssertEqual(decoded.colorSpace.localizedName,NSColorSpace.sRGB.localizedName)
    }
    func testGradientAndPressureRenderDifferently() throws {
        _ = NSApplication.shared
        var gradient = line(); gradient.style = InkStyle(gradient:true,endColor:.palette[3],opacity:1,shadow:false)
        let image = InkExport.image(strokes:[gradient],size:CGSize(width:300,height:150)); let rep = try XCTUnwrap(NSBitmapImageRep(data:try InkExport.png(image)))
        let scale = Double(rep.pixelsWide)/300
        let start = try XCTUnwrap(rep.colorAt(x:Int(35*scale),y:Int(60*scale))?.usingColorSpace(.sRGB)), end = try XCTUnwrap(rep.colorAt(x:Int(205*scale),y:Int(60*scale))?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(start.redComponent,end.redComponent); XCTAssertGreaterThan(end.blueComponent,start.blueComponent)
        var pressure = line(); pressure.points = [InkPoint(CGPoint(x:20,y:60)),InkPoint(CGPoint(x:120,y:60)),InkPoint(CGPoint(x:220,y:60))]; pressure.width = 30; pressure.pressures = [0.1,0.1,1]
        let pressureImage = InkExport.image(strokes:[pressure],size:CGSize(width:300,height:150)); let pressureRep = try XCTUnwrap(NSBitmapImageRep(data:try InkExport.png(pressureImage)))
        XCTAssertLessThan(pressureRep.colorAt(x:Int(40*scale),y:Int(66*scale))!.alphaComponent,0.1)
        XCTAssertGreaterThan(pressureRep.colorAt(x:Int(200*scale),y:Int(66*scale))!.alphaComponent,0.8)
    }
    func testImportedImageDoesNotClearOtherDrawings() throws {
        _ = NSApplication.shared
        let state = InkState(); state.drawing = true; state.whiteboard = true
        let canvas = InkCanvas(frame:CGRect(x:0,y:0,width:300,height:200),state:state,display:"test"); defer { canvas.timer?.invalidate() }
        var imported = InkStroke(tool:.image,points:[InkPoint(CGPoint(x:10,y:100)),InkPoint(CGPoint(x:60,y:150))],color:.palette[0],width:1,display:"test")
        imported.imageData = try InkExport.png(InkExport.image(strokes:[],size:CGSize(width:50,height:50),background:.palette[3]))
        var underlying = line(); underlying.style = InkStyle(gradient:true,endColor:.palette[3],opacity:1,shadow:false); underlying.pressures = [0.5,0.5]
        state.history.replace([underlying,imported])
        let bitmap = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds)); canvas.cacheDisplay(in:canvas.bounds,to:bitmap)
        let scale = Double(bitmap.pixelsWide)/300
        let ink = bitmap.colorAt(x:Int(100*scale),y:Int(60*scale))!
        XCTAssertGreaterThan(ink.alphaComponent,0.9); XCTAssertLessThan(ink.greenComponent,0.8)
        XCTAssertGreaterThan(bitmap.colorAt(x:Int(25*scale),y:Int(125*scale))!.blueComponent,0.8)
    }
    func testShadowExtendsOutsideGradientStroke() throws {
        _ = NSApplication.shared
        var stroke = line(); stroke.style = InkStyle(gradient:true,endColor:.palette[3],opacity:0.5,shadow:true)
        let rep = try XCTUnwrap(NSBitmapImageRep(data:InkExport.png(InkExport.image(strokes:[stroke],size:CGSize(width:300,height:150)))))
        let scale = Double(rep.pixelsWide)/300
        let outside = rep.colorAt(x:Int(100*scale),y:Int(67*scale))!.alphaComponent
        XCTAssertGreaterThan(outside,0.005)
        XCTAssertLessThan(rep.colorAt(x:Int(100*scale),y:Int(60*scale))!.alphaComponent,0.6)
    }
    func testSelectionDragAndMultilineText() {
        _ = NSApplication.shared
        let state = InkState(); state.drawing = true; state.fadeDelay = 0
        let window = OverlayWindow(contentRect:CGRect(x:0,y:0,width:500,height:400),styleMask:.borderless,backing:.buffered,defer:false); window.isReleasedWhenClosed = false
        let canvas = InkCanvas(frame:CGRect(x:0,y:0,width:500,height:400),state:state,display:"test"); window.contentView = canvas
        defer { canvas.timer?.invalidate(); window.close() }
        let stroke = line(); state.history.append(stroke); state.tool = .select
        func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent { NSEvent.mouseEvent(with:type,location:CGPoint(x:p.x,y:400-p.y),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)! }
        canvas.mouseDown(with:event(.leftMouseDown,CGPoint(x:50,y:60))); canvas.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:100,y:100))); canvas.mouseUp(with:event(.leftMouseUp,CGPoint(x:100,y:100)))
        XCTAssertEqual(state.history.strokes[0].points[0].x,70); XCTAssertEqual(state.history.strokes[0].points[0].y,100)
        state.undo(); XCTAssertEqual(state.history.strokes[0].points[0].x,20)
        canvas.beginText(at:CGPoint(x:30,y:150)); canvas.editor?.string = "First line\nSecond line"; canvas.finishText()
        XCTAssertEqual(state.history.strokes.last?.text,"First line\nSecond line")
    }
    func testRemoteValidationAndDrawUsesCurrentStyle() {
        _ = NSApplication.shared
        let app = AppController(); let canvas = InkCanvas(frame:CGRect(x:0,y:0,width:400,height:300),state:app.state,display:"test"); app.canvases = [canvas]; defer { canvas.timer?.invalidate() }
        app.state.preferences.style.gradient = true
        app.remoteCommand(RemoteCommand(action:"draw",points:[[0.1,0.2,0.5],[0.8,0.7,1]]))
        XCTAssertEqual(app.state.history.strokes.count,1); XCTAssertEqual(app.state.history.strokes[0].points[0].x,40); XCTAssertTrue(app.state.history.strokes[0].style!.gradient)
        app.remoteCommand(RemoteCommand(action:"draw",points:[[2,0,0]])); XCTAssertEqual(app.state.history.strokes.count,1)
        app.remoteCommand(RemoteCommand(action:"undo")); XCTAssertEqual(app.state.history.strokes.count,0)
    }
    func testAreaSelectionDeleteResizeAndEraserGestureUndo() {
        _ = NSApplication.shared
        let state = InkState(); state.drawing = true; state.fadeDelay = 0
        let window = OverlayWindow(contentRect:CGRect(x:0,y:0,width:500,height:400),styleMask:.borderless,backing:.buffered,defer:false); window.isReleasedWhenClosed = false
        let canvas = InkCanvas(frame:CGRect(x:0,y:0,width:500,height:400),state:state,display:"test"); window.contentView = canvas
        defer { canvas.timer?.invalidate(); window.close() }
        func event(_ type: NSEvent.EventType,_ x: Double,_ y: Double) -> NSEvent { NSEvent.mouseEvent(with:type,location:CGPoint(x:x,y:400-y),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)! }
        let stroke = line(); state.history.append(stroke); state.tool = .select
        canvas.mouseDown(with:event(.leftMouseDown,0,0)); canvas.mouseDragged(with:event(.leftMouseDragged,250,90)); canvas.mouseUp(with:event(.leftMouseUp,250,90))
        XCTAssertEqual(state.selection,[stroke.id]); state.deleteSelected(); XCTAssertTrue(state.history.strokes.isEmpty); state.undo()
        state.selection = [stroke.id]
        let handle = stroke.bounds
        canvas.mouseDown(with:event(.leftMouseDown,handle.maxX+5,handle.maxY+5)); canvas.mouseDragged(with:event(.leftMouseDragged,handle.maxX+100,handle.maxY+50)); canvas.mouseUp(with:event(.leftMouseUp,handle.maxX+100,handle.maxY+50))
        XCTAssertGreaterThan(state.history.strokes[0].bounds.width,stroke.bounds.width); state.undo()
        state.tool = .eraser
        canvas.mouseDown(with:event(.leftMouseDown,80,60)); canvas.mouseDragged(with:event(.leftMouseDragged,160,60)); canvas.mouseUp(with:event(.leftMouseUp,160,60))
        XCTAssertGreaterThan(state.history.strokes.count,1); state.undo(); XCTAssertEqual(state.history.strokes.count,1); XCTAssertEqual(state.history.strokes[0].id,stroke.id)
    }
    func testRegionSelectionBadgeSequenceAndRepeat() {
        _ = NSApplication.shared
        let state = InkState(); state.drawing = true; state.fadeDelay = 0
        let window = OverlayWindow(contentRect:CGRect(x:0,y:0,width:500,height:400),styleMask:.borderless,backing:.buffered,defer:false); window.isReleasedWhenClosed = false
        let canvas = InkCanvas(frame:CGRect(x:0,y:0,width:500,height:400),state:state,display:"test"); window.contentView = canvas
        defer { canvas.timer?.invalidate(); window.close() }
        func event(_ type: NSEvent.EventType,_ x: Double,_ y: Double) -> NSEvent { NSEvent.mouseEvent(with:type,location:CGPoint(x:x,y:400-y),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)! }
        var result: CGRect?; canvas.regionSelecting = true; canvas.regionComplete = { result = $0 }
        canvas.mouseDown(with:event(.leftMouseDown,30,40)); canvas.mouseDragged(with:event(.leftMouseDragged,230,180)); canvas.mouseUp(with:event(.leftMouseUp,230,180))
        XCTAssertEqual(result,CGRect(x:30,y:40,width:200,height:140)); XCTAssertFalse(canvas.regionSelecting)
        state.tool = .badge
        for x in [50.0,100.0] { canvas.mouseDown(with:event(.leftMouseDown,x,200)); canvas.mouseUp(with:event(.leftMouseUp,x,200)) }
        XCTAssertEqual(state.history.strokes.map(\.text),["1","2"])
        state.repeatLast(on:"other"); XCTAssertEqual(state.history.strokes.last?.text,"2"); XCTAssertEqual(state.history.strokes.last?.display,"other")
    }
    func testCrossScreenCoordinateConversion() {
        _ = NSApplication.shared
        let controller = AppController(); let state = controller.state; state.history.append(line("one")); state.selection = [state.history.strokes[0].id]
        let first = OverlayWindow(contentRect:CGRect(x:-500,y:100,width:500,height:400),styleMask:.borderless,backing:.buffered,defer:false)
        let second = OverlayWindow(contentRect:CGRect(x:0,y:0,width:600,height:500),styleMask:.borderless,backing:.buffered,defer:false)
        first.isReleasedWhenClosed = false; second.isReleasedWhenClosed = false
        let a = InkCanvas(frame:CGRect(x:0,y:0,width:500,height:400),state:state,display:"one"), b = InkCanvas(frame:CGRect(x:0,y:0,width:600,height:500),state:state,display:"two")
        first.contentView = a; second.contentView = b; controller.canvases = [a,b]
        controller.moveAcrossScreens(from:a,point:CGPoint(x:50,y:300),ids:state.selection)
        XCTAssertEqual(state.history.strokes[0].display,"two"); XCTAssertEqual(state.history.strokes[0].points[0].x,-480); XCTAssertEqual(state.history.strokes[0].points[0].y,60)
        a.timer?.invalidate(); b.timer?.invalidate(); first.close(); second.close()
    }
    func testMagnifierMaskPresentationAndExportEvidence() throws {
        _ = NSApplication.shared
        let state = InkState(); state.drawing = true; state.whiteboard = true; state.tool = .spotlight; state.preferences.magnify = true; state.preferences.spotlightRadius = 70
        let canvas = InkCanvas(frame:CGRect(x:0,y:0,width:700,height:450),state:state,display:"test"); defer { canvas.timer?.invalidate() }
        canvas.capturedScreen = InkExport.image(strokes:[],size:canvas.bounds.size,background:.palette[3]); canvas.pointer = CGPoint(x:350,y:230)
        let bitmap = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds)); canvas.cacheDisplay(in:canvas.bounds,to:bitmap)
        let scale = Double(bitmap.pixelsWide)/700
        XCTAssertGreaterThan(bitmap.colorAt(x:Int(350*scale),y:Int(230*scale))!.blueComponent,0.8)
        XCTAssertLessThan(bitmap.colorAt(x:Int(20*scale),y:Int(20*scale))!.blueComponent,0.5)
        state.tool = .pen; state.preferences.magnify = false
        var pen = line(); pen.points = (0...80).map { InkPoint(CGPoint(x:60+Double($0)*5,y:140+sin(Double($0)/9)*28)) }; pen.width = 12; pen.style = InkStyle(gradient:true,endColor:.palette[3],opacity:1,shadow:true)
        let arrow = InkStroke(tool:.arrow,points:[InkPoint(CGPoint(x:80,y:240)),InkPoint(CGPoint(x:250,y:310))],color:.palette[2],width:5,display:"test")
        var badge = InkStroke(tool:.badge,points:[InkPoint(CGPoint(x:520,y:250))],color:.palette[0],width:5,text:"1",display:"test"); badge.fadeAfter = nil
        state.history.replace([pen,arrow,badge]); state.lowerThird = "ScreenInc · make your point"; state.countdownEnd = Date().addingTimeInterval(90)
        canvas.cacheDisplay(in:canvas.bounds,to:bitmap)
        XCTAssertGreaterThan(bitmap.colorAt(x:Int(25*scale),y:Int(350*scale))!.alphaComponent,0.9)
        if let output = ProcessInfo.processInfo.environment["SCREEN_INK_FEATURE_OUTPUT"] {
            let url = URL(fileURLWithPath:output); try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
            try bitmap.representation(using:.png,properties:[:])!.write(to:url.appendingPathComponent("gradient-presentation-render.png"))
            try JSONEncoder().encode(InkSnapshot(strokes:state.visibleStrokes())).write(to:url.appendingPathComponent("feature-demo.drawings.json"))
        }
    }
    @MainActor func testRemoteHTTPPairingRejectsWrongTokenAndAcceptsCommand() async throws {
        let remote = InkRemote(); let ready = expectation(description:"Listener ready"), command = expectation(description:"Command received")
        var address = ""
        remote.status = { value in address = value; ready.fulfill() }; remote.command = { value in XCTAssertEqual(value.action,"next"); command.fulfill() }
        try remote.start()
        await fulfillment(of:[ready],timeout:5)
        let paired = try XCTUnwrap(URL(string:address)); var parts = URLComponents(url:paired,resolvingAgainstBaseURL:false)!; parts.host = "127.0.0.1"
        let url = parts.url!
        let (html,response) = try await URLSession.shared.data(from:url); XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200); XCTAssertTrue(String(decoding:html,as:UTF8.self).contains("Drawing pad"))
        let (_,rejected) = try await URLSession.shared.data(from:url.deletingLastPathComponent().appendingPathComponent("wrong")); XCTAssertEqual((rejected as? HTTPURLResponse)?.statusCode,404)
        var request = URLRequest(url:url.appendingPathComponent("command")); request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(RemoteCommand(action:"next")); request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (_,accepted) = try await URLSession.shared.data(for:request); XCTAssertEqual((accepted as? HTTPURLResponse)?.statusCode,200)
        await fulfillment(of:[command],timeout:5); remote.stop()
    }
}
