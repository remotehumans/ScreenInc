import AVFoundation
import Vision
import ImageIO
import CoreML

/// Capture and inference have separate queues so a slow model cannot block camera shutdown.
final class HandCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label:"co.remotehumans.screeninc.hand-camera",qos:.userInitiated)
    private let inferenceQueue = DispatchQueue(label:"co.remotehumans.screeninc.hand-inference",qos:.userInitiated)
    private let request = HandCamera.makeRequest()
    private var processing = false
    private var epoch = 0
    var sample: ((HandSample?, TimeInterval) -> Void)?
    var failure: ((String) -> Void)?
    private var lastFrame: TimeInterval = 0
    private var wanted = false
    static func makeRequest() -> VNDetectHumanHandPoseRequest {
        let request = VNDetectHumanHandPoseRequest(); request.maximumHandCount = 1
        // Prefer GPU for interactive throughput; avoid the Neural Engine cold-start stall.
        let devices = MLComputeDevice.allComputeDevices
        let gpu = devices.first { if case .gpu = $0 { return true }; return false }
        let cpu = devices.first { if case .cpu = $0 { return true }; return false }
        request.setComputeDevice(gpu ?? cpu,for:.main)
        return request
    }
    static var devices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera,.external,.continuityCamera],mediaType:.video,position:.unspecified).devices
    }
    func start(deviceID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.wanted = true; self.epoch += 1
            do {
                let device = Self.devices.first(where:{$0.uniqueID == deviceID}) ?? AVCaptureDevice.default(for:.video)
                guard let device else { throw CameraError.unavailable }
                self.session.beginConfiguration()
                self.session.inputs.forEach(self.session.removeInput)
                self.session.outputs.forEach(self.session.removeOutput)
                self.session.sessionPreset = .vga640x480
                do {
                    let input = try AVCaptureDeviceInput(device:device)
                    guard self.session.canAddInput(input) else { throw CameraError.unavailable }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self,queue:self.queue)
                    guard self.session.canAddOutput(output) else { throw CameraError.unavailable }
                    self.session.addOutput(output)
                    if let connection = output.connection(with:.video), connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false
                    }
                    self.session.commitConfiguration()
                } catch { self.session.commitConfiguration(); throw error }
                self.lastFrame = 0
                self.session.startRunning()
                if !self.session.isRunning { self.fail("Camera could not start. Check whether another app is using it.") }
            } catch { self.fail(error.localizedDescription) }
        }
    }
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.wanted = false; self.epoch += 1; self.session.stopRunning()
            self.session.beginConfiguration()
            self.session.inputs.forEach(self.session.removeInput)
            self.session.outputs.forEach(self.session.removeOutput)
            self.session.commitConfiguration()
        }
    }
    private func fail(_ message: String) { DispatchQueue.main.async { [weak self] in self?.failure?(message) } }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard wanted, !processing, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastFrame >= 1/40 else { return }; lastFrame = now
        processing = true; let token = epoch
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            var value: HandSample?
            var problem: String?
            do {
                try VNImageRequestHandler(cvPixelBuffer:pixelBuffer,orientation:.up,options:[:]).perform([self.request])
                value = try self.request.results?.first.flatMap { try Self.decode($0,aspect:Double(CVPixelBufferGetWidth(pixelBuffer))/Double(CVPixelBufferGetHeight(pixelBuffer))) }
            } catch { problem = "Hand tracking unavailable: \(error.localizedDescription)" }
            let result = value, errorMessage = problem
            self.queue.async { [weak self] in
                guard let self else { return }; self.processing = false
                guard self.wanted, self.epoch == token else { return }
                DispatchQueue.main.async { [weak self] in
                    if let errorMessage { self?.failure?(errorMessage) }
                    else { self?.sample?(result,now) }
                }
            }
        }
    }
    static func decode(_ hand: VNHumanHandPoseObservation, aspect: Double = 4.0/3.0) throws -> HandSample? {
        let points = try hand.recognizedPoints(.all)
        let required: [VNHumanHandPoseObservation.JointName] = [.indexTip,.thumbTip,.wrist,.middleMCP]
        guard required.allSatisfy({ (points[$0]?.confidence ?? 0) >= 0.3 }) else { return nil }
        func p(_ joint: VNHumanHandPoseObservation.JointName) -> CGPoint { points[joint]!.location }
        func distance(_ a: CGPoint,_ b: CGPoint) -> Double { hypot((a.x-b.x)*aspect,a.y-b.y) }
        let scale = distance(p(.wrist),p(.middleMCP))
        guard scale > 0.035 else { return nil }
        let fingers: [(VNHumanHandPoseObservation.JointName,VNHumanHandPoseObservation.JointName)] = [(.indexTip,.indexPIP),(.middleTip,.middlePIP),(.ringTip,.ringPIP),(.littleTip,.littlePIP)]
        let extended = fingers.filter {
            guard let tip = points[$0.0], let joint = points[$0.1], tip.confidence >= 0.3, joint.confidence >= 0.3 else { return false }
            return distance(tip.location,p(.wrist)) > distance(joint.location,p(.wrist))*1.2
        }
        return HandSample(index:CGPoint(x:p(.indexTip).x,y:1-p(.indexTip).y),pinchRatio:distance(p(.indexTip),p(.thumbTip))/scale,openPalm:extended.count >= 3)
    }
    enum CameraError: LocalizedError {
        case unavailable
        var errorDescription: String? { "No usable camera found. Connect a camera and try again." }
    }
}
