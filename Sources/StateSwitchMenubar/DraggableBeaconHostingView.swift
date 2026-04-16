import AppKit
import SwiftUI

final class DraggableBeaconHostingView<Content: View>: NSHostingView<Content> {
    var onDragBegan: (() -> Void)?
    var onDragChanged: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }

        let startMouseLocation = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        var didBeginDrag = false

        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch nextEvent.type {
            case .leftMouseDragged:
                if !didBeginDrag {
                    didBeginDrag = true
                    onDragBegan?()
                }

                let location = NSEvent.mouseLocation
                let translatedOrigin = NSPoint(
                    x: startOrigin.x + location.x - startMouseLocation.x,
                    y: startOrigin.y + location.y - startMouseLocation.y
                )
                onDragChanged?(translatedOrigin)

            case .leftMouseUp:
                if didBeginDrag {
                    onDragEnded?()
                }
                return

            default:
                break
            }
        }

        if didBeginDrag {
            onDragEnded?()
        }
    }
}
