import AppKit
import Network
import Darwin

struct RemoteCommand: Codable {
    var action: String
    var points: [[Double]]?
}
final class InkRemote {
    private var listener: NWListener?
    private var connections: [UUID:NWConnection] = [:]
    let token = UUID().uuidString.replacingOccurrences(of:"-",with:"")
    var command: ((RemoteCommand) -> Void)?
    var status: ((String) -> Void)?
    func start() throws {
        let listener = try NWListener(using:.tcp,on:.any); self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state, let port = listener.port { self.status?("http://\(Self.localAddress()):\(port.rawValue)/\(self.token)") }
            if case .failed(let error) = state { self.status?("Remote failed: \(error.localizedDescription)"); self.stop() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.connections.count < 12 else { connection.cancel(); return }
            let id = UUID(); self.connections[id] = connection; connection.start(queue:.main)
            self.receive(connection,id:id,buffer:Data())
            DispatchQueue.main.asyncAfter(deadline:.now()+10) { [weak self] in self?.connections.removeValue(forKey:id)?.cancel() }
        }
        listener.start(queue:.main)
    }
    func stop() { listener?.cancel(); listener = nil; connections.values.forEach { $0.cancel() }; connections.removeAll() }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:65536) { [weak self] data,_,complete,error in
            guard let self else { return }
            var buffer = buffer; if let data { buffer.append(data) }
            guard buffer.count <= 65536, error == nil else { self.close(id); return }
            guard let separator = buffer.range(of:Data("\r\n\r\n".utf8)) else { if complete { self.close(id) } else { self.receive(connection,id:id,buffer:buffer) }; return }
            let header = String(decoding:buffer[..<separator.lowerBound],as:UTF8.self)
            let lines = header.components(separatedBy:"\r\n"), request = lines.first?.split(separator:" ") ?? []
            guard request.count == 3 else { self.close(id); return }
            let length = lines.dropFirst().first(where:{ $0.lowercased().hasPrefix("content-length:") }).flatMap { Int($0.split(separator:":",maxSplits:1).last!.trimmingCharacters(in:.whitespaces)) } ?? 0
            guard length >= 0, length <= 60000 else { self.close(id); return }
            let body = buffer[separator.upperBound...]
            if body.count < length { if complete { self.close(id) } else { self.receive(connection,id:id,buffer:buffer) }; return }
            var response = "Not found", code = "404 Not Found", type = "text/plain"
            if request[0] == "GET", request[1] == "/\(self.token)" {
                response = Self.page; code = "200 OK"; type = "text/html; charset=utf-8"
            } else if request[0] == "POST", request[1] == "/\(self.token)/command", let command = try? JSONDecoder().decode(RemoteCommand.self,from:Data(body.prefix(length))) {
                self.command?(command); response = "ok"; code = "200 OK"
            }
            let payload = Data(response.utf8)
            var result = Data("HTTP/1.1 \(code)\r\nContent-Type: \(type)\r\nContent-Length: \(payload.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'\r\nConnection: close\r\n\r\n".utf8); result.append(payload)
            connection.send(content:result,completion:.contentProcessed { [weak self] _ in self?.close(id) })
        }
    }
    private func close(_ id: UUID) { connections.removeValue(forKey:id)?.cancel() }
    static func localAddress() -> String {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return "localhost" }; defer { freeifaddrs(pointer) }
        var current = pointer
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), String(cString:item.pointee.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(address,socklen_t(address.pointee.sa_len),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST) == 0 { return String(cString:host) }
        }; return "localhost"
    }
    static let page = #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="apple-mobile-web-app-capable" content="yes"><title>ScreenInc Remote</title><style>
    body{background:#191919;color:#f4f1ea;font:17px -apple-system,sans-serif;margin:24px}h1{font-size:25px}button{font:inherit;color:inherit;background:#303030;border:1px solid #555;border-radius:12px;padding:16px;margin:4px}button:active{background:#a64d24}#pad{width:100%;height:42vh;touch-action:none;background:#262626;border:1px solid #777;border-radius:14px}p{color:#aaa;font-size:14px}#status{min-height:20px}</style></head><body><h1>ScreenInc</h1><p>Presentation remote · keep this tab open</p><div><button data-action="previousSlide">← Slide</button><button data-action="nextSlide">Slide →</button></div><div><button data-action="previous">← Snapshot</button><button data-action="next">Snapshot →</button></div><div><button data-action="undo">Undo</button><button data-action="clear">Clear</button><button data-action="timer">Timer</button><button data-action="toggle">Draw / click through</button></div><p>Drawing pad · ink uses the Mac’s current colour and fade settings</p><canvas id="pad"></canvas><p id="status">Connected to your Mac</p><script>
    const pad=document.querySelector('#pad'),ctx=pad.getContext('2d'),status=document.querySelector('#status');let points=[],busy=false;
    function resize(){pad.width=pad.clientWidth*devicePixelRatio;pad.height=pad.clientHeight*devicePixelRatio;}resize();
    async function send(action,points){try{let r=await fetch(location.pathname+'/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,points})});if(!r.ok)throw Error();status.textContent='Connected to your Mac';}catch{status.textContent='Connection lost. Check Wi-Fi and the Mac remote switch.';}}
    document.querySelectorAll('button').forEach(b=>b.onclick=()=>send(b.dataset.action));
    function point(e){let r=pad.getBoundingClientRect();return [Math.max(0,Math.min(1,(e.clientX-r.left)/r.width)),Math.max(0,Math.min(1,(e.clientY-r.top)/r.height)),e.pressure||0.5];}
    pad.onpointerdown=e=>{busy=true;pad.setPointerCapture(e.pointerId);points=[point(e)];ctx.clearRect(0,0,pad.width,pad.height);ctx.beginPath();ctx.moveTo(points[0][0]*pad.width,points[0][1]*pad.height);};
    pad.onpointermove=e=>{if(!busy)return;for(let sample of (e.getCoalescedEvents?e.getCoalescedEvents():[e])){let p=point(sample);if(points.length<2000)points.push(p);ctx.strokeStyle='#f67a39';ctx.lineWidth=4*devicePixelRatio;ctx.lineCap='round';ctx.lineTo(p[0]*pad.width,p[1]*pad.height);ctx.stroke();}};
    pad.onpointerup=()=>{if(busy){busy=false;send('draw',points);}};pad.onpointercancel=()=>{busy=false;points=[];};
    </script></body></html>
    """#
}
extension AppController {
    func toggleRemote() {
        if let remote { remote.stop(); self.remote = nil; state.remoteAddress = "Remote is off"; return }
        let remote = InkRemote(); self.remote = remote
        remote.status = { [weak self] in self?.state.remoteAddress = $0 }
        remote.command = { [weak self] in self?.remoteCommand($0) }
        do { try remote.start() } catch { state.remoteAddress = error.localizedDescription; self.remote = nil }
    }
    func remoteCommand(_ command: RemoteCommand) {
        switch command.action {
        case "next": cycleSnapshot(1)
        case "previous": cycleSnapshot(-1)
        case "undo": state.undo()
        case "clear": clear()
        case "toggle": toggleDrawing()
        case "timer": state.countdownEnd = Date().addingTimeInterval(state.preferences.countdownSeconds); state.changed()
        case "nextSlide", "previousSlide":
            guard AXIsProcessTrusted() else { state.message = "Enable ScreenInc in Accessibility settings to control slides"; return }
            let code: CGKeyCode = command.action == "nextSlide" ? 124 : 123
            setDrawing(false)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true)?.post(tap:.cghidEventTap); CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:false)?.post(tap:.cghidEventTap) }
        case "draw":
            guard let canvas = activeCanvas, let points = command.points, !points.isEmpty, points.count <= 2000, points.allSatisfy({ $0.count == 3 && $0.allSatisfy({ $0.isFinite && (0...1).contains($0) }) }) else { return }
            var stroke = InkStroke(tool:.pen,points:points.map { InkPoint(CGPoint(x:$0[0]*canvas.bounds.width,y:$0[1]*canvas.bounds.height)) },color:state.color,width:state.width,display:canvas.display,fadeAfter:state.fadeDelay > 0 ? state.fadeDelay : nil)
            stroke.style = state.preferences.style; stroke.pressures = points.map { max(0.15,$0[2]) }; state.history.append(stroke); state.lastDrawing = stroke; state.changed()
        default: break
        }
    }
}
