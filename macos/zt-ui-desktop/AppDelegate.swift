import AppKit
import Foundation
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var serverController: ServerController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 960),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "zt-ui Desktop"
        window.center()
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        self.window = window

        webView.loadHTMLString(Self.loadingHTML, baseURL: nil)
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            await launchStage()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        serverController?.stop()
    }

    @MainActor
    private func launchStage() async {
        do {
            let controller = try ServerController()
            self.serverController = controller

            let stageURL = try controller.start()
            try await controller.waitUntilReady()

            let request = URLRequest(url: stageURL)
            webView?.load(request)
        } catch {
            let message = error.localizedDescription
            webView?.loadHTMLString(Self.failureHTML(message: message), baseURL: nil)

            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Unable to launch zt-ui"
            alert.informativeText = message
            alert.runModal()
        }
    }

    private static let loadingHTML = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <style>
          :root {
            color-scheme: dark;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            background: #0d110b;
            color: #f2eee4;
          }
          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            background:
              radial-gradient(circle at top right, rgba(151, 171, 103, 0.18), transparent 28%),
              radial-gradient(circle at bottom left, rgba(141, 109, 73, 0.16), transparent 34%),
              linear-gradient(180deg, #1b2116 0%, #0d110b 52%, #090c08 100%);
          }
          main {
            width: min(520px, calc(100vw - 48px));
            padding: 28px 32px;
            border-radius: 24px;
            border: 1px solid rgba(166, 147, 108, 0.22);
            background: rgba(20, 24, 18, 0.9);
            box-shadow: 0 26px 72px rgba(0, 0, 0, 0.42);
          }
          h1 {
            margin: 0 0 12px;
            font-size: 1.8rem;
          }
          p {
            margin: 0;
            line-height: 1.6;
            color: #b8b19b;
          }
        </style>
      </head>
      <body>
        <main>
          <h1>Launching zt-ui Desktop</h1>
          <p>The local stage server is starting and the native shell will attach as soon as it responds.</p>
        </main>
      </body>
    </html>
    """

    private static func failureHTML(message: String) -> String {
        """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <style>
              :root {
                color-scheme: dark;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                background: #0d110b;
                color: #f2eee4;
              }
              body {
                margin: 0;
                min-height: 100vh;
                display: grid;
                place-items: center;
                background:
                  radial-gradient(circle at top right, rgba(151, 171, 103, 0.18), transparent 28%),
                  radial-gradient(circle at bottom left, rgba(141, 109, 73, 0.16), transparent 34%),
                  linear-gradient(180deg, #1b2116 0%, #0d110b 52%, #090c08 100%);
              }
              main {
                width: min(620px, calc(100vw - 48px));
                padding: 28px 32px;
                border-radius: 24px;
                border: 1px solid rgba(166, 147, 108, 0.22);
                background: rgba(20, 24, 18, 0.9);
                box-shadow: 0 26px 72px rgba(0, 0, 0, 0.42);
              }
              h1 {
                margin: 0 0 12px;
                font-size: 1.8rem;
              }
              p {
                margin: 0;
                line-height: 1.6;
                color: #b8b19b;
                white-space: pre-wrap;
              }
            </style>
          </head>
          <body>
            <main>
              <h1>zt-ui Desktop failed to launch</h1>
              <p>\(message)</p>
            </main>
          </body>
        </html>
        """
    }
}
