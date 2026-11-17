import SwiftUI
import WebKit

/// Tiny loopback HTTP server that serves the YouTube embed page.
/// The IFrame API needs a real http(s) origin — it rejects about:blank and file://.
private final class LocalHTTPServer {
    static let shared = LocalHTTPServer()

    let port: UInt16 = 48733
    private var html = ""
    private var started = false
    private let lock = NSLock()

    func start() {
        guard !started else { return }
        started = true

        let serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { NSLog("Workout: YouTube server socket() failed"); return }

        var yes: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            NSLog("Workout: YouTube server bind() failed: \(errno)")
            close(serverSocket)
            return
        }
        listen(serverSocket, 5)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let client = accept(serverSocket, nil, nil)
                guard client >= 0 else { continue }
                self?.handle(client)
            }
        }
    }

    func setHTML(_ html: String) {
        lock.lock(); self.html = html; lock.unlock()
    }

    private func handle(_ client: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        _ = read(client, &buffer, buffer.count)
        lock.lock(); let body = html; lock.unlock()
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let bytes = Array(response.utf8)
        _ = bytes.withUnsafeBufferPointer { write(client, $0.baseAddress, bytes.count) }
        close(client)
    }
}

struct YouTubePlayerView: NSViewRepresentable {
    let videoID: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let volume: Int
    let isPaused: Bool
    var onEnded: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "ytEvent")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 14
        webView.layer?.masksToBounds = true

        let coord = context.coordinator
        coord.webView = webView
        coord.onEnded = onEnded
        coord.endTime = endTime
        coord.volume = volume

        let server = LocalHTTPServer.shared
        server.start()
        server.setHTML(buildHTML(port: server.port))
        if let url = URL(string: "http://127.0.0.1:\(server.port)/youtube.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        coord.onEnded = onEnded
        guard coord.playerReady else { return }

        if isPaused != coord.wasPaused {
            coord.wasPaused = isPaused
            webView.evaluateJavaScript(isPaused
                ? "if(player&&player.pauseVideo)player.pauseVideo()"
                : "if(player&&player.playVideo)player.playVideo()")
        }
        if volume != coord.volume {
            coord.volume = volume
            webView.evaluateJavaScript(volume == 0
                ? "if(player&&player.mute)player.mute()"
                : "if(player&&player.unMute){player.unMute();player.setVolume(\(volume))}")
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cleanup()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil) // unloading the page is the reliable way to kill audio
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onEnded: (() -> Void)?
        var endTime: TimeInterval = 0
        var volume = 0
        var wasPaused = false
        var playerReady = false
        var hasEnded = false
        private var pollTimer: Timer?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "ytEvent", let body = message.body as? String else { return }
            if body == "ready" {
                playerReady = true
                if endTime > 0 { startEndTimePolling() }
            } else if body == "ended" {
                finish()
            } else if body.hasPrefix("error:") {
                NSLog("Workout: YouTube player \(body)")
            }
        }

        private func startEndTimePolling() {
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self, let webView = self.webView, !self.hasEnded else {
                    self?.pollTimer?.invalidate()
                    return
                }
                webView.evaluateJavaScript("(player && player.getCurrentTime) ? player.getCurrentTime() : 0") { [weak self] result, _ in
                    guard let self, let time = result as? Double, time >= self.endTime else { return }
                    webView.evaluateJavaScript("if(player)player.pauseVideo()")
                    self.finish()
                }
            }
        }

        private func finish() {
            guard !hasEnded else { return }
            hasEnded = true
            pollTimer?.invalidate()
            pollTimer = nil
            DispatchQueue.main.async { [weak self] in self?.onEnded?() }
        }

        func cleanup() {
            pollTimer?.invalidate()
            pollTimer = nil
            onEnded = nil
            playerReady = false
            hasEnded = true
        }

        deinit { pollTimer?.invalidate() }
    }

    private func buildHTML(port: UInt16) -> String {
        """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        *{margin:0;padding:0;overflow:hidden}
        html,body{background:#000;height:100%}
        #player{position:absolute;inset:0;width:100%;height:100%}
        </style>
        </head><body>
        <div id="player"></div>
        <script>
        var tag=document.createElement('script');
        tag.src='https://www.youtube.com/iframe_api';
        document.head.appendChild(tag);
        var player;
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('player',{
            videoId:'\(videoID)',
            playerVars:{autoplay:1,start:\(Int(startTime)),controls:1,modestbranding:1,rel:0,playsinline:1,
                        origin:'http://127.0.0.1:\(port)'},
            events:{
              onReady:function(e){
                \(volume == 0 ? "e.target.mute();" : "e.target.unMute();e.target.setVolume(\(volume));")
                e.target.playVideo();
                window.webkit.messageHandlers.ytEvent.postMessage('ready');
              },
              onStateChange:function(e){
                if(e.data===YT.PlayerState.ENDED){window.webkit.messageHandlers.ytEvent.postMessage('ended');}
              },
              onError:function(e){window.webkit.messageHandlers.ytEvent.postMessage('error:'+e.data);}
            }
          });
        }
        </script>
        </body></html>
        """
    }
}
