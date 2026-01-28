import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Set minimum and initial window size
    let initialSize = NSSize(width: 1000, height: 768)
    self.minSize = initialSize
    
    // Set initial window frame centered on screen
    if let screen = NSScreen.main {
      let screenRect = screen.visibleFrame
      let originX = (screenRect.width - initialSize.width) / 2 + screenRect.origin.x
      let originY = (screenRect.height - initialSize.height) / 2 + screenRect.origin.y
      let windowFrame = NSRect(x: originX, y: originY, width: initialSize.width, height: initialSize.height)
      self.setFrame(windowFrame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
