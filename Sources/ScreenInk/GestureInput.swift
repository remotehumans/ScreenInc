import Foundation
import CoreGraphics

/// Camera coordinates are normalised and top-left oriented before entering this layer.
struct HandSample {
    var index: CGPoint
    var pinchRatio: Double
    var openPalm: Bool
}
struct GestureUpdate {
    var point: CGPoint?
    var began = false
    var ended = false
    var held = false
    var menu = false
    var tracking = true
    var palmProgress: Double = 0
}

/// Gesture transitions require stable evidence and a release after any tracking interruption.
struct HandGestureEngine {
    private(set) var point: CGPoint?
    private(set) var held = false
    private(set) var ready = false
    private var candidateSince: TimeInterval?
    private var releaseSince: TimeInterval?
    private var palmSince: TimeInterval?
    private var palmLatched = false
    private var lastTime: TimeInterval?
    var inset = 0.15
    var smoothing = 0.09
    var pinchThreshold = 0.38

    mutating func reset() -> GestureUpdate {
        let ended = held
        self = HandGestureEngine(inset:inset,smoothing:smoothing,pinchThreshold:pinchThreshold)
        return GestureUpdate(ended:ended,tracking:false)
    }
    mutating func update(_ sample: HandSample?, at time: TimeInterval) -> GestureUpdate {
        guard let sample else {
            candidateSince = nil; releaseSince = nil; palmSince = nil
            // Freeze briefly without emitting input; one uncertain frame must not lift the pen.
            if let lastTime, time-lastTime <= 0.22 { return GestureUpdate(point:point,tracking:false) }
            return reset()
        }
        guard sample.index.x.isFinite, sample.index.y.isFinite,
              sample.pinchRatio.isFinite else { return reset() }
        if let lastTime, time-lastTime > 0.75 { return reset() }
        let dt = max(0.001,min(0.3,time-(lastTime ?? time-1/30)))
        lastTime = time
        let margin = min(0.3,max(0,inset))
        let mapped = CGPoint(x:min(1,max(0,(sample.index.x-margin)/(1-margin*2))),y:min(1,max(0,(sample.index.y-margin)/(1-margin*2))))
        // A different hand or a tracking jump must not draw a line across the screen.
        if let point, hypot(mapped.x-point.x,mapped.y-point.y) > 0.3 { return reset() }
        let alpha = 1-exp(-dt/max(0.001,smoothing))
        if let previous = point {
            let distance = hypot(mapped.x-previous.x,mapped.y-previous.y)
            let stabilised = max(0,distance-0.0015)/max(0.0015,distance)
            point = CGPoint(x:previous.x+(mapped.x-previous.x)*alpha*stabilised,y:previous.y+(mapped.y-previous.y)*alpha*stabilised)
        }
        else { point = mapped }
        var result = GestureUpdate(point:point)
        let closed = sample.pinchRatio < pinchThreshold
        let released = sample.pinchRatio > pinchThreshold+0.24
        if released {
            releaseSince = releaseSince ?? time
            if time-releaseSince! >= 0.06 { ready = true }
        } else { releaseSince = nil }
        if held && released { held = false; result.ended = true; candidateSince = nil }
        if !held && ready && closed {
            candidateSince = candidateSince ?? time
            if time-candidateSince! >= 0.06 { held = true; result.began = true; ready = false; candidateSince = nil }
        } else if !closed { candidateSince = nil }
        if sample.openPalm && !held && released {
            palmSince = palmSince ?? time
            result.palmProgress = min(1,(time-palmSince!)/0.7)
            if result.palmProgress >= 1 && !palmLatched { result.menu = true; palmLatched = true }
        } else { palmSince = nil; palmLatched = false }
        result.held = held
        return result
    }
}
