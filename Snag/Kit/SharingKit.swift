//
//  The macOS share sheet, replacing Lowtech's wrapper.
//
//  SwiftUI's own `ShareLink` cannot anchor a picker to an arbitrary view the way this needs, so
//  `NSSharingServicePicker` is driven through a zero-size `NSViewRepresentable` that acts purely
//  as the anchor rect.
//

import AppKit
import SwiftUI

/// Holds the picker delegate alive for the lifetime of a presentation.
///
/// `NSSharingServicePicker` keeps only a weak reference to its delegate, so a delegate owned by
/// the SwiftUI view would be deallocated the moment the body re-evaluates and the sheet would
/// silently do nothing.
@MainActor
final class SharingManager: NSObject, NSSharingServicePickerDelegate {
    var onClose: (() -> Void)?

    func sharingServicePicker(
        _: NSSharingServicePicker,
        didChoose _: NSSharingService?
    ) {
        onClose?()
        onClose = nil
    }
}

/// Invisible anchor that presents the share sheet when `isPresented` becomes true.
struct SharingsPicker: NSViewRepresentable {
    @Binding var isPresented: Bool
    var sharingItems: [Any] = []

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented, !sharingItems.isEmpty else { return }

        // Deferred to the next turn: during updateNSView the view is not yet in a window, and a
        // picker with no window to anchor to does not appear at all.
        DispatchQueue.main.async {
            guard nsView.window != nil else {
                isPresented = false
                return
            }
            let picker = NSSharingServicePicker(items: sharingItems)
            picker.delegate = SHARING_MANAGER
            SHARING_MANAGER.onClose = { isPresented = false }
            picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
        }
    }
}
