import XCTest
import AppKit
import SwiftUI
import Vision
@testable import ScreenInk

final class GestureTests: XCTestCase {
    func sample(_ ratio: Double = 0.8,_ x: Double = 0.5,_ y: Double = 0.5,palm: Bool = false) -> HandSample {
        HandSample(index:CGPoint(x:x,y:y),pinchRatio:ratio,openPalm:palm)
    }
    func testPinchRequiresReleaseAndStableClose() {
        var engine = HandGestureEngine()
        for i in 0...5 { XCTAssertFalse(engine.update(sample(0.1),at:Double(i)*0.04).began) }
        _ = engine.update(sample(),at:0.24); _ = engine.update(sample(),at:0.32)
        XCTAssertFalse(engine.update(sample(0.1),at:0.36).began)
        XCTAssertTrue(engine.update(sample(0.1),at:0.44).began)
        XCTAssertFalse(engine.update(sample(0.1),at:0.48).began)
        XCTAssertTrue(engine.update(sample(),at:0.52).ended)
        XCTAssertFalse(engine.update(sample(),at:0.56).ended)
    }
    func testLossEndsStrokeAndCannotResumeWhilePinched() {
        var engine = HandGestureEngine()
        _ = engine.update(sample(),at:0); _ = engine.update(sample(),at:0.08)
        _ = engine.update(sample(0.1),at:0.12); _ = engine.update(sample(0.1),at:0.2)
        XCTAssertTrue(engine.held)
        XCTAssertFalse(engine.update(nil,at:0.24).ended)
        XCTAssertTrue(engine.update(nil,at:0.45).ended)
        for i in 0...8 { XCTAssertFalse(engine.update(sample(0.1),at:0.48+Double(i)*0.02).held) }
        _ = engine.update(sample(),at:0.7); _ = engine.update(sample(),at:0.78)
        _ = engine.update(sample(0.1),at:0.82)
        XCTAssertTrue(engine.update(sample(0.1),at:0.9).began)
    }
    func testJitterDoesNotRepeatedlyTogglePinch() {
        var engine = HandGestureEngine()
        _ = engine.update(sample(),at:0); _ = engine.update(sample(),at:0.08)
        _ = engine.update(sample(0.1),at:0.12); _ = engine.update(sample(0.1),at:0.2)
        for i in 0...10 { let result = engine.update(sample(i%2 == 0 ? 0.32 : 0.43),at:0.24+Double(i)*0.03); XCTAssertTrue(result.held); XCTAssertFalse(result.began); XCTAssertFalse(result.ended) }
    }
    func testPalmDwellOnlyOpensOnceUntilHandChanges() {
        var engine = HandGestureEngine()
        var openings = 0
        for i in 0...50 { if engine.update(sample(palm:true),at:Double(i)*0.04).menu { openings += 1 } }
        XCTAssertEqual(openings,1)
        _ = engine.update(sample(),at:2.04)
        for i in 0...25 { if engine.update(sample(palm:true),at:2.08+Double(i)*0.04).menu { openings += 1 } }
        XCTAssertEqual(openings,2)
    }
    func testJumpStaleFrameAndInvalidInputDropTracking() {
        var engine = HandGestureEngine()
        _ = engine.update(sample(),at:0)
        XCTAssertNil(engine.update(sample(0.8,1,1),at:0.03).point)
        _ = engine.update(sample(),at:0.06)
        XCTAssertNil(engine.update(sample(),at:0.9).point)
        XCTAssertNil(engine.update(sample(0.8,.nan,0.5),at:0.44).point)
    }
    func testReachMapsComfortableAreaToScreenCorners() {
        var engine = HandGestureEngine()
        XCTAssertEqual(engine.update(sample(0.8,0.15,0.15),at:0).point,.zero)
        _ = engine.reset()
        XCTAssertEqual(engine.update(sample(0.8,0.85,0.85),at:0).point,CGPoint(x:1,y:1))
    }
    func fixture() -> (AppController,InkCanvas,GestureController) {
        _ = NSApplication.shared
        let owner = AppController(); owner.state.drawing = true; owner.state.fadeDelay = 0
        let canvas = InkCanvas(frame:CGRect(x:0,y:0,width:1000,height:700),state:owner.state,display:"test")
        canvas.timer?.invalidate(); owner.canvases = [canvas]
        let gesture = owner.gestures; gesture.running = true; gesture.mirrored = false; gesture.reach = 0; gesture.smoothing = 0.001
        return (owner,canvas,gesture)
    }
    func feed(_ gesture: GestureController,_ hand: HandSample?,_ time: inout Double,frames: Int = 4) {
        for _ in 0..<frames { time += 0.04; gesture.receive(hand,at:time,now:time) }
    }
    func testGestureDrawsThroughProductionCanvasAndUndoes() {
        let (owner,canvas,g) = fixture(); var time = 0.0
        feed(g,sample(0.8,0.3,0.4),&time); feed(g,sample(0.1,0.3,0.4),&time)
        XCTAssertNotNil(canvas.current)
        feed(g,sample(0.1,0.45,0.4),&time); feed(g,sample(0.8,0.45,0.4),&time)
        XCTAssertEqual(owner.state.history.strokes.count,1)
        XCTAssertGreaterThan(owner.state.history.strokes[0].points.count,2)
        g.perform("undo"); XCTAssertEqual(owner.state.history.strokes.count,0)
        g.perform("redo"); XCTAssertEqual(owner.state.history.strokes.count,1)
        g.running = false
    }
    func testMenuSelectionConsumesPinchWithoutDrawing() throws {
        let (owner,_,g) = fixture(); g.menuVisible = true; var time = 0.0
        let box = try XCTUnwrap(g.layout(in:g.target!.bounds).first(where:{$0.0.id == "arrow"})?.1)
        let x = box.midX/1000,y = box.midY/700
        feed(g,sample(0.8,x,y),&time); feed(g,sample(0.1,x,y),&time)
        XCTAssertEqual(owner.state.tool,.arrow); XCTAssertFalse(g.menuVisible)
        feed(g,sample(0.1,x+0.05,y),&time)
        XCTAssertNil(g.target?.current); XCTAssertTrue(owner.state.history.strokes.isEmpty)
        feed(g,sample(0.8,x,y),&time); feed(g,sample(0.1,x,y),&time)
        XCTAssertNotNil(g.target?.current)
        g.running = false
    }
    func testTrackingLossCommitsOnlyExistingStroke() {
        let (owner,canvas,g) = fixture(); var time = 0.0
        feed(g,sample(),&time); feed(g,sample(0.1),&time)
        feed(g,nil,&time,frames:7)
        XCTAssertNil(canvas.current); XCTAssertEqual(owner.state.history.strokes.count,1)
        feed(g,sample(0.1,0.6),&time); XCTAssertEqual(owner.state.history.strokes.count,1); XCTAssertNil(canvas.current)
        g.running = false
    }
    func testPauseAndClearConfirmation() {
        let (owner,canvas,g) = fixture(); var time = 0.0
        feed(g,sample(),&time); feed(g,sample(0.1),&time); feed(g,sample(),&time)
        g.perform("clear"); XCTAssertEqual(owner.state.history.strokes.count,1)
        g.perform("pageColour"); XCTAssertFalse(g.clearArmed)
        g.perform("clear"); g.perform("clear"); XCTAssertTrue(owner.state.history.strokes.isEmpty)
        g.perform("pause"); feed(g,sample(),&time); feed(g,sample(0.1),&time)
        XCTAssertNil(canvas.current)
        g.running = false
    }
    func testSelectionMoveAndEraserUseSharedCanvasInput() {
        let (owner,canvas,g) = fixture()
        canvas.pointerDown(at:CGPoint(x:100,y:100)); canvas.pointerDragged(to:CGPoint(x:200,y:100)); canvas.pointerUp()
        owner.state.tool = .select
        canvas.pointerDown(at:CGPoint(x:150,y:100)); canvas.pointerDragged(to:CGPoint(x:150,y:200)); canvas.pointerUp()
        XCTAssertEqual(owner.state.history.strokes[0].points.first?.y,200)
        owner.state.tool = .eraser
        canvas.pointerDown(at:CGPoint(x:150,y:200)); canvas.pointerUp()
        XCTAssertEqual(owner.state.history.strokes.count,2)
        owner.state.undo(); XCTAssertEqual(owner.state.history.strokes.count,1)
        g.running = false
    }
    func testRenderGestureMenuAndAllTargetsAreReachable() throws {
        let (owner,canvas,g) = fixture(); g.menuVisible = true
        for page in ["Tools","Colour","Actions"] {
            g.page = page
            for (item,rect) in g.layout(in:canvas.bounds) {
                XCTAssertTrue(canvas.bounds.contains(rect)); XCTAssertEqual(g.hit(CGPoint(x:rect.midX,y:rect.midY),in:canvas.bounds)?.id,item.id)
            }
        }
        g.page = "Tools"; g.pointer = CGPoint(x:500,y:350)
        canvas.gestureOverlay = { g.draw(on:$0) }
        let image = NSImage(size:canvas.bounds.size); image.lockFocusFlipped(true)
        NSColor(calibratedWhite:0.22,alpha:1).setFill(); canvas.bounds.fill(); g.draw(on:canvas)
        image.unlockFocus()
        let png = try InkExport.png(image)
        try png.write(to:URL(fileURLWithPath:"/tmp/screeninc-gesture-menu.png"))
        XCTAssertGreaterThan(png.count,10000)
        canvas.gestureOverlay = nil; g.running = false
        withExtendedLifetime(owner) {}
    }
    func testStaleCameraResultCannotCreateOrContinueStroke() {
        let (owner,canvas,g) = fixture(); var time = 0.0
        feed(g,sample(),&time); feed(g,sample(0.1),&time)
        g.receive(sample(0.1,0.6),at:time,now:time+0.9)
        XCTAssertNil(canvas.current); XCTAssertFalse(g.activeStroke)
        XCTAssertEqual(owner.state.history.strokes.count,1)
        g.running = false
    }
    func testVisionDetectsNoHandInBlankCameraFrame() throws {
        let request = HandCamera.makeRequest()
        let frame = CIImage(color:.black).cropped(to:CGRect(x:0,y:0,width:640,height:480))
        try VNImageRequestHandler(ciImage:frame,options:[:]).perform([request])
        XCTAssertTrue(request.results?.isEmpty ?? true)
    }
    @MainActor func testRenderCameraSettingsWithoutStartingCamera() throws {
        let (owner,_,g) = fixture(); g.running = false
        let host = NSHostingView(rootView:GestureSettings(gestures:g,controller:owner).environment(\.colorScheme,.light).background(Color.white))
        host.appearance = NSAppearance(named:.aqua)
        host.setFrameSize(host.fittingSize); host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.bounds.height,400)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/screeninc-gesture-settings.png"))
        XCTAssertFalse(g.camera.session.isRunning)
    }

    func testBriefMissFreezesThenContinuesSameStroke() {
        let (owner,canvas,g) = fixture(); var time = 0.0
        feed(g,sample(),&time); feed(g,sample(0.1),&time)
        let count = canvas.current?.points.count
        feed(g,nil,&time,frames:2)
        XCTAssertEqual(canvas.current?.points.count,count)
        XCTAssertTrue(owner.state.history.strokes.isEmpty)
        feed(g,sample(0.1,0.52),&time); feed(g,sample(),&time)
        XCTAssertEqual(owner.state.history.strokes.count,1)
        g.running = false
    }
    func testSlowerInferenceStillRecognisesPinch() {
        let (owner,canvas,g) = fixture()
        // Capture timestamps are 300 ms apart, arriving 300 ms after capture.
        for (time,ratio) in [(1.0,0.8),(1.3,0.8),(1.6,0.1),(1.9,0.1)] {
            g.receive(sample(ratio),at:time,now:time+0.3)
        }
        XCTAssertNotNil(canvas.current); XCTAssertTrue(g.activeStroke)
        g.running = false; withExtendedLifetime(owner) {}
    }
    func testStationaryHandNoiseDoesNotMovePointer() {
        var engine = HandGestureEngine(); engine.inset = 0
        _ = engine.update(sample(),at:0)
        for i in 1...30 { _ = engine.update(sample(0.8,0.5+(i%2 == 0 ? 0.0008 : -0.0008)),at:Double(i)*0.03) }
        XCTAssertEqual(engine.point!.x,0.5,accuracy:0.0001)
    }

}
