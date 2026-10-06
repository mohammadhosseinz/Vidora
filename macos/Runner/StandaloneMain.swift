// Command Line Tools runner used by scripts/build_macos_cli.py.
// The Xcode target continues to use AppDelegate and MainFlutterWindow.
import Cocoa
import FlutterMacOS

class StandaloneAppDelegate: FlutterAppDelegate {
  private var window: NSWindow?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = FlutterViewController()
    let mainWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1080, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    // Flutter's view starts without a size; AppKit adopts it when attaching
    // the controller. Restore the window frame, as the Xcode runner does.
    let windowFrame = mainWindow.frame
    mainWindow.contentViewController = controller
    mainWindow.setFrame(windowFrame, display: true)
    mainWindow.minSize = NSSize(width: 640, height: 500)
    mainWindow.title = "Vidora"
    mainWindow.isReleasedWhenClosed = false
    window = mainWindow
    mainFlutterWindow = mainWindow
    RegisterStandalonePlugins(registry: controller)
    mainWindow.center()
    mainWindow.makeKeyAndOrderFront(nil)
    super.applicationDidFinishLaunching(notification)
    NSApp.activate(ignoringOtherApps: true)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if let window = mainFlutterWindow, window.isVisible {
      window.performClose(nil)
      return .terminateCancel
    }
    return .terminateNow
  }
}

let application = NSApplication.shared
let delegate = StandaloneAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
let menuBar = NSMenu()
let appMenu = NSMenu(title: "Vidora")
let appItem = NSMenuItem()
appItem.submenu = appMenu
menuBar.addItem(appItem)
appMenu.addItem(withTitle: "About Vidora", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "Hide Vidora", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
appMenu.addItem(withTitle: "Quit Vidora", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
let editMenu = NSMenu(title: "Edit")
let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
editItem.submenu = editMenu
menuBar.addItem(editItem)
for (title, action, key) in [
  ("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
  ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")
] {
  editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
}
application.mainMenu = menuBar
delegate.applicationMenu = appMenu
// Native smoke test exercises Quit through Flutter's asynchronous close handler.
if CommandLine.arguments.contains("--smoke-test-close") {
  DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    guard let window = delegate.mainFlutterWindow,
          let contentView = window.contentView else {
      fputs("No application window was created\n", stderr)
      exit(1)
    }
    let size = contentView.bounds.size
    print("Window content: \(Int(size.width))x\(Int(size.height))")
    guard window.isVisible, size.width >= 640, size.height >= 500 else {
      fputs("Application window is hidden or too small\n", stderr)
      exit(1)
    }
    application.terminate(nil)
  }
}
application.run()
