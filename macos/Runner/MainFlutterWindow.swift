import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController

    let autosaveName = NSWindow.FrameAutosaveName("meshcore_open.main_window")
    if !self.setFrameUsingName(autosaveName) {
      self.setFrame(windowFrame, display: true)
    }
    self.setFrameAutosaveName(autosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
