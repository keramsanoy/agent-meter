import AppKit
import Foundation
import WebKit

@MainActor
final class ProviderBrowser: NSObject, WKNavigationDelegate {
    let provider: AgentProvider
    private let webView: WKWebView
    private var browserWindow: BrowserWindow?
    private var backgroundWindow: NSWindow?
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var shouldFocusAfterNavigation = false

    init(provider: AgentProvider) {
        self.provider = provider
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func fetchUsage() async throws -> UsageSnapshot {
        shouldFocusAfterNavigation = false
        attachBackgroundHostIfNeeded()
        try await load(url: provider.usageURL)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let text = try await pageText()
        if isSignInPage(text) { throw UsageParseError.needsSignIn(provider.displayName) }
        return try UsageParsers.parse(provider: provider, text: text, fetchedAt: Date())
    }

    func openInteractiveBrowser() {
        let window = browserWindow ?? makeBrowserWindow()
        browserWindow = window
        attachWebView(to: window.contentViewController as? BrowserViewController)
        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        focusWebView()
        if webView.url == nil {
            shouldFocusAfterNavigation = true
            webView.load(URLRequest(url: provider.usageURL))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
        if shouldFocusAfterNavigation { focusWebView() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    private func load(url: URL) async throws {
        loadContinuation?.resume(throwing: CancellationError())
        loadContinuation = nil
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    private func pageText() async throws -> String {
        let result = try await webView.evaluateJavaScript("""
        (() => {
          const root = document.body || document.documentElement;
          return root ? root.innerText : "";
        })()
        """)
        guard let text = result as? String, !text.isEmpty else { throw UsageParseError.emptyPageText }
        return text
    }

    private func isSignInPage(_ text: String) -> Bool {
        let lower = text.lowercased()
        switch provider {
        case .claude:
            return lower.contains("sign in") && !lower.contains("plan usage limits")
        case .copilot:
            return lower.contains("sign in") && !lower.contains("copilot")
        case .codex:
            return (lower.contains("log in") || lower.contains("sign in")) && !lower.contains("usage")
        }
    }

    private func focusWebView() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.browserWindow?.makeKeyAndOrderFront(nil)
            self.browserWindow?.makeFirstResponder(self.webView)
            self.webView.window?.makeFirstResponder(self.webView)
            self.webView.evaluateJavaScript("""
            (() => {
              const input = document.querySelector('input[type="email"], input[name*="login" i], input[name*="email" i], input[autocomplete="username"], input[type="text"], textarea, [contenteditable="true"]');
              if (input && document.activeElement !== input) input.focus();
            })()
            """, completionHandler: nil)
        }
    }

    private func makeBrowserWindow() -> BrowserWindow {
        let viewController = BrowserViewController(webView: webView, hint: "Sign in to \(provider.displayName), then close this window. Usage will refresh in the background.")
        let window = BrowserWindow(contentViewController: viewController)
        window.title = "\(provider.displayName) Browser"
        window.setContentSize(NSSize(width: 1100, height: 760))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        return window
    }


    private func attachBackgroundHostIfNeeded() {
        guard browserWindow?.isVisible != true else { return }
        if backgroundWindow == nil {
            let viewController = BrowserViewController(webView: webView, showsToolbar: false)
            let window = NSWindow(contentViewController: viewController)
            window.title = "\(provider.displayName) Background Browser"
            window.setFrame(NSRect(x: 0, y: 0, width: 1024, height: 768), display: false)
            window.styleMask = [.borderless]
            window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
            window.isExcludedFromWindowsMenu = true
            window.isReleasedWhenClosed = false
            backgroundWindow = window
        }
        _ = backgroundWindow?.contentViewController?.view
    }

    private func attachWebView(to viewController: BrowserViewController?) { viewController?.attachBrowserView() }
}

final class BrowserWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class BrowserViewController: NSViewController {
    private let browserView: WKWebView
    private let showsToolbar: Bool
    private let toolbar = NSStackView()
    private let hintLabel: NSTextField

    init(webView: WKWebView, showsToolbar: Bool = true, hint: String = "Sign in, then close this window. Usage will refresh in the background.") {
        self.browserView = webView
        self.showsToolbar = showsToolbar
        self.hintLabel = NSTextField(labelWithString: hint)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        attachBrowserView()
    }

    func attachBrowserView() {
        if browserView.superview === view { return }
        browserView.removeFromSuperview()
        toolbar.removeFromSuperview()
        if showsToolbar { view.addSubview(toolbar) }
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 10
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        hintLabel.textColor = .secondaryLabelColor
        toolbar.addArrangedSubview(hintLabel)
        browserView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browserView)
        var constraints = [
            browserView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browserView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browserView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        if showsToolbar {
            constraints += [
                toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                toolbar.topAnchor.constraint(equalTo: view.topAnchor),
                toolbar.heightAnchor.constraint(equalToConstant: 38),
                browserView.topAnchor.constraint(equalTo: toolbar.bottomAnchor)
            ]
        } else {
            constraints.append(browserView.topAnchor.constraint(equalTo: view.topAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if showsToolbar {
            NSApp.activate(ignoringOtherApps: true)
            view.window?.makeFirstResponder(browserView)
        }
    }
}
