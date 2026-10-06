import XCTest
import AppKit
@testable import ScreenInk
final class ScreenInkTests: XCTestCase {
    func stroke(_ tool: InkTool = .pen) -> InkStroke {
        InkStroke(tool:tool,points:[InkPoint(CGPoint(x:10,y:20)),InkPoint(CGPoint(x:110,y:120))],color:.palette[0],width:4,display:"test")
    }
    func testFadeHoldsThenSmoothlyDisappears() {
        var s = stroke(); s.created = Date(timeIntervalSince1970:100); s.fadeAfter = 2
        XCTAssertEqual(s.opacity(at:Date(timeIntervalSince1970:101)),1)
        XCTAssertEqual(s.opacity(at:Date(timeIntervalSince1970:102)),1)
        XCTAssertEqual(s.opacity(at:Date(timeIntervalSince1970:102.5)),0.5,accuracy:0.001)
        XCTAssertEqual(s.opacity(at:Date(timeIntervalSince1970:103)),0)
        XCTAssertEqual(s.opacity(at:Date(timeIntervalSince1970:900)),0)
    }
    func testFadeIsIndependentForEachStrokeAndKeepIsPermanent() {
        var first = stroke(), next = stroke(), kept = stroke()
        first.created = Date(timeIntervalSince1970:100); first.fadeAfter = 2
        next.created = Date(timeIntervalSince1970:102); next.fadeAfter = 2
        kept.created = Date(timeIntervalSince1970:100)
        let now = Date(timeIntervalSince1970:103)
        XCTAssertEqual(first.opacity(at:now),0); XCTAssertEqual(next.opacity(at:now),1)
        XCTAssertEqual(kept.opacity(at:Date(timeIntervalSince1970:9000)),1)
    }
    func testUndoRedoAndBranchAfterUndo() {
        let h = InkHistory(); let a = stroke(), b = stroke(.arrow)
        h.append(a); h.append(b); h.undo(); XCTAssertEqual(h.strokes.map(\.id),[a.id])
        h.redo(); XCTAssertEqual(h.strokes.map(\.id),[a.id,b.id])
        h.replace([]); h.undo(); XCTAssertEqual(h.strokes.count,2)
        h.undo(); h.append(stroke(.ellipse)); XCTAssertFalse(h.canRedo)
    }
    func testEraserHitsShapeOutlineNotEmptyCentre() {
        let box = stroke(.rectangle)
        XCTAssertTrue(box.hit(CGPoint(x:10,y:70)))
        XCTAssertFalse(box.hit(CGPoint(x:60,y:70)))
        XCTAssertFalse(box.hit(CGPoint(x:200,y:200)))
    }
    func testArrowHeadIsErasable() {
        let arrow = stroke(.arrow)
        XCTAssertTrue(arrow.hit(CGPoint(x:105,y:115)))
        XCTAssertFalse(arrow.hit(CGPoint(x:200,y:20)))
    }
    func testSnapshotRoundTripPreservesTextStylesAndTiming() throws {
        var s = stroke(.text); s.text = "Hello 👋"; s.fadeAfter = 5
        let data = try JSONEncoder().encode(InkSnapshot(strokes:[s]))
        let restored = try JSONDecoder().decode(InkSnapshot.self,from:data)
        XCTAssertEqual(restored.version,1); XCTAssertEqual(restored.strokes[0].text,s.text)
        XCTAssertEqual(restored.strokes[0].points,s.points); XCTAssertEqual(restored.strokes[0].fadeAfter,5)
    }
}

final class CanvasInteractionTests: XCTestCase {
    func testNativeMouseLifecycleAndClickThroughGuard() {
        _ = NSApplication.shared
        let state = InkState(); let window = OverlayWindow(contentRect:NSRect(x:0,y:0,width:600,height:400),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        let canvas = InkCanvas(frame:NSRect(x:0,y:0,width:600,height:400),state:state,display:"test")
        window.contentView = canvas
        func event(_ type: NSEvent.EventType,_ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        canvas.mouseDown(with:event(.leftMouseDown,CGPoint(x:20,y:30)))
        XCTAssertNil(canvas.current)
        state.drawing = true; state.tool = .rectangle
        canvas.mouseDown(with:event(.leftMouseDown,CGPoint(x:20,y:30)))
        canvas.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:180,y:160)))
        canvas.mouseUp(with:event(.leftMouseUp,CGPoint(x:180,y:160)))
        XCTAssertNil(canvas.current); XCTAssertEqual(state.history.strokes.count,1)
        XCTAssertEqual(state.history.strokes[0].rect.width,160)
        XCTAssertEqual(state.history.strokes[0].rect.height,130)
        XCTAssertEqual(state.history.strokes[0].fadeAfter,2)
        canvas.erase(at:state.history.strokes[0].points[0].cg)
        XCTAssertTrue(state.history.strokes.isEmpty)
        state.undo(); XCTAssertEqual(state.history.strokes.count,1)
        canvas.timer?.invalidate(); window.close()
    }
    func testTextCommitAndLaserDoNotMixWithPermanentInk() {
        _ = NSApplication.shared
        let state = InkState(); state.drawing = true; state.fadeDelay = 0
        let canvas = InkCanvas(frame:NSRect(x:0,y:0,width:600,height:400),state:state,display:"test")
        canvas.beginText(at:CGPoint(x:50,y:50)); canvas.editor?.string = "Explain this"; canvas.finishText()
        XCTAssertEqual(state.history.strokes.first?.text,"Explain this")
        XCTAssertNil(state.history.strokes.first?.fadeAfter)
        canvas.current = InkStroke(tool:.laser,points:[InkPoint(CGPoint(x:50,y:50))],color:.palette[0],width:4,display:"test")
        let event = NSEvent.mouseEvent(with:.leftMouseUp,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:0)!
        canvas.mouseUp(with:event)
        XCTAssertEqual(canvas.lasers.count,1); XCTAssertEqual(state.history.strokes.count,1)
        canvas.timer?.invalidate()
    }
    func testRenderVisualEvidence() throws {
        guard let output = ProcessInfo.processInfo.environment["SCREEN_INK_VISUAL_OUTPUT"] else { return }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath:output); try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let state = InkState(); state.drawing = true; state.whiteboard = true; state.fadeDelay = 0
        let canvas = InkCanvas(frame:NSRect(x:0,y:0,width:1000,height:600),state:state,display:"test")
        var pen = InkStroke(tool:.pen,points:(0...80).map { index in InkPoint(CGPoint(x:80+Double(index)*4,y:170+sin(Double(index)/10)*35)) },color:.palette[0],width:5,display:"test")
        state.history.append(pen)
        state.history.append(InkStroke(tool:.arrow,points:[InkPoint(CGPoint(x:520,y:130)),InkPoint(CGPoint(x:730,y:220))],color:.palette[3],width:5,display:"test"))
        state.history.append(InkStroke(tool:.rectangle,points:[InkPoint(CGPoint(x:80,y:280)),InkPoint(CGPoint(x:420,y:420))],color:.palette[2],width:4,display:"test"))
        state.history.append(InkStroke(tool:.ellipse,points:[InkPoint(CGPoint(x:530,y:280)),InkPoint(CGPoint(x:850,y:420))],color:.palette[4],width:4,display:"test"))
        state.history.append(InkStroke(tool:.text,points:[InkPoint(CGPoint(x:80,y:60))],color:.palette[6],width:6,text:"A little ink. A clearer point.",display:"test"))
        func capture(_ name: String) throws {
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds)!; canvas.cacheDisplay(in:canvas.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name))
        }
        try capture("drawing-tools.png")
        state.tool = .spotlight; canvas.pointer = CGPoint(x:680,y:340); try capture("spotlight.png")
        state.tool = .pen; state.history.replace([])
        pen.fadeAfter = 2
        // Render a deterministic four-second timeline using the production opacity and drawing code.
        for frame in 0..<120 {
            let image = NSImage(size:canvas.bounds.size); image.lockFocusFlipped(true)
            NSColor(srgbRed:0.949,green:0.941,blue:0.914,alpha:1).setFill(); canvas.bounds.fill()
            ("Stroke released · 2s hold · 1s fade" as NSString).draw(at:CGPoint(x:80,y:60),withAttributes:[.font:NSFont.systemFont(ofSize:28),.foregroundColor:NSColor.black])
            pen.draw(opacity:pen.opacity(at:pen.created.addingTimeInterval(Double(frame)/30)))
            image.unlockFocus()
            let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
            try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(String(format:"fade-%03d.png",frame)))
        }
        canvas.timer?.invalidate()
    }
}
