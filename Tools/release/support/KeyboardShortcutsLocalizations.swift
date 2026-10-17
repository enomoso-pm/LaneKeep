import Foundation

// Added by LaneKeep's Tools/release/support/patch_keyboardshortcuts.py in place of SwiftPM's Bundle.module.
extension Bundle {
	/// The localized strings of KeyboardShortcuts. build_app.sh copies them into the app at
	/// Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle, where an Xcode build has them too.
	/// Without them the strings show their keys instead of stopping the app.
	static let keyboardShortcutsLocalizations: Bundle = {
		let name = "KeyboardShortcuts_KeyboardShortcuts.bundle"
		for case let folder? in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
			if let bundle = Bundle(url: folder.appendingPathComponent(name)) {
				return bundle
			}
		}
		return .main
	}()
}
