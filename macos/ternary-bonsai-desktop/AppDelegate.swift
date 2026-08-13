import AppKit
import Foundation
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var stackController: StackController?
    private var stackURLs: StackURLs?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 960),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "zt-ui Ternary Bonsai"
        window.center()
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        self.window = window

        webView.loadHTMLString(Self.statusHTML(title: "Launching Ternary Bonsai", body: "Preparing the local stack…"), baseURL: nil)
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            await launchStack()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        stackController?.stop()
    }

    @MainActor
    private func launchStack() async {
        do {
            let controller = try StackController()
            self.stackController = controller

            let modelURL = try await controller.ensureModel { [weak self] message in
                Task { @MainActor in
                    self?.webView?.loadHTMLString(
                        Self.statusHTML(title: "Launching Ternary Bonsai", body: message),
                        baseURL: nil
                    )
                }
            }

            let urls = try controller.start(modelURL: modelURL) { [weak self] message in
                Task { @MainActor in
                    self?.webView?.loadHTMLString(
                        Self.statusHTML(title: "Launching Ternary Bonsai", body: message),
                        baseURL: nil
                    )
                }
            }
            self.stackURLs = urls

            try await controller.waitUntilReady { [weak self] message in
                Task { @MainActor in
                    self?.webView?.loadHTMLString(
                        Self.statusHTML(title: "Launching Ternary Bonsai", body: message),
                        baseURL: nil
                    )
                }
            }

            webView?.load(URLRequest(url: urls.bridge))
        } catch {
            let message = error.localizedDescription
            webView?.loadHTMLString(Self.statusHTML(title: "Launch failed", body: message), baseURL: nil)

            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Unable to launch Ternary Bonsai"
            alert.informativeText = message
            alert.runModal()
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit zt-ui Ternary Bonsai", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Bridge", action: #selector(showBridge), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "zt-ui Dashboard", action: #selector(showZtUI), keyEquivalent: "2")

        NSApp.mainMenu = mainMenu
    }

    @objc private func showBridge() {
        guard let url = stackURLs?.bridge else { return }
        webView?.load(URLRequest(url: url))
        window?.title = "zt-ui Ternary Bonsai"
    }

    @objc private func showZtUI() {
        guard let url = stackURLs?.ztUI else { return }
        webView?.load(URLRequest(url: url))
        window?.title = "zt-ui Dashboard"
    }

    private static func statusHTML(title: String, body: String) -> String {
        let escapedBody = body
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <style>
              :root {
                color-scheme: light;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                background: #f3efe6;
                color: #1c1914;
              }
              body {
                margin: 0;
                min-height: 100vh;
                display: grid;
                place-items: center;
                background:
                  radial-gradient(1200px 500px at 10% -10%, #d9e7df 0%, transparent 55%),
                  linear-gradient(160deg, #f3efe6, #e7e0d2);
              }
              main {
                width: min(560px, calc(100vw - 48px));
                padding: 28px 32px;
                border: 1px solid #c9bfad;
                background: rgba(255, 252, 246, 0.92);
              }
              h1 { margin: 0 0 12px; font-size: 1.7rem; letter-spacing: -0.02em; }
              p { margin: 0; line-height: 1.55; color: #5f574c; white-space: pre-wrap; }
            </style>
          </head>
          <body>
            <main>
              <h1>\(title)</h1>
              <p>\(escapedBody)</p>
            </main>
          </body>
        </html>
        """
    }
}
