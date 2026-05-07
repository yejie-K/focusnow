import AppKit
import SwiftUI

struct IMETextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 13, weight: .medium)
    var textColor: NSColor = .labelColor
    var placeholderColor: NSColor = .placeholderTextColor
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let textField = ActivatingTextField(string: text)
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyStyle(to: textField)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        applyStyle(to: textField)

        guard (textField.currentEditor() as? NSTextView)?.hasMarkedText() != true else {
            return
        }

        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func applyStyle(to textField: NSTextField) {
        textField.font = font
        textField.textColor = textColor
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: font
            ]
        )
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: IMETextField

        init(parent: IMETextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            NSApp.activate(ignoringOtherApps: true)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }
            parent.text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            guard !textView.hasMarkedText() else {
                return false
            }

            if let textField = control as? NSTextField {
                parent.text = textField.stringValue
            }
            parent.onSubmit?()
            return true
        }
    }
}

private final class ActivatingTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        return super.becomeFirstResponder()
    }
}
