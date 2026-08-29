import SwarmCore
import SwiftUI

// The sepia form controls: a field caption, the input chrome they share, and the
// three field kinds built on them (single line, notes, date).
//
// They were declared inside `OnboardingView` but are used from the add and edit
// sheets and the place picker, so a screen that happened to be written first owned
// the app's form vocabulary.

/// Field caption. 11pt with light tracking: the old 9.5pt tracked caps were below a
/// comfortable floor for an audience reading handwriting through this app.
struct SepiaFieldLabel: View {
    let text: String
    /// Hidden from VoiceOver when the control it captions carries the same name itself
    /// (a text field). A caption over a group of buttons is real content: pass `false`.
    let isDecorative: Bool

    init(_ text: String, isDecorative: Bool = true) {
        self.text = text
        self.isDecorative = isDecorative
    }

    var body: some View {
        Text(text)
            .font(SepiaType.label)
            .tracking(0.6)
            .foregroundColor(SepiaTheme.inkSoft)
            .accessibilityHidden(isDecorative)
    }
}

/// A sepia text input: our own fill, placeholder and focus ring. See `sepiaFieldChrome`
/// for why the system field plus a colour multiply was not good enough.
struct SepiaFieldInput: View {
    @Binding var text: String
    var placeholder: String = ""
    /// What VoiceOver should call this field. Without it the field announces its
    /// placeholder ("напр. Иванов") as its name.
    var label: String
    var height: CGFloat = 30
    var radius: CGFloat = 6
    var fontSize: CGFloat = 15
    /// Stable handle for UI tests. Labels repeat across this app's longer editors
    /// (НАЗВАНИЕ and ЗАМЕТКИ each caption more than one field in the person editor),
    /// which makes a label-based query ambiguous.
    var identifier: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(SepiaTheme.body(size: fontSize))
            .foregroundColor(SepiaTheme.ink)
            .focused($isFocused)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier ?? "")
            .sepiaFieldChrome(
                isFocused: isFocused,
                placeholder: placeholder,
                isEmpty: text.isEmpty,
                height: height,
                radius: radius,
                fontSize: fontSize
            )
    }
}

struct SepiaTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var height: CGFloat = 30
    var radius: CGFloat = 6
    var fontSize: CGFloat = 15
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SepiaFieldLabel(label)
            SepiaFieldInput(
                text: $text,
                placeholder: placeholder,
                label: label,
                height: height,
                radius: radius,
                fontSize: fontSize,
                identifier: identifier
            )
        }
    }
}

/// Multiline freeform notes field with a draggable bottom edge to resize vertically.
struct SepiaNotesField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    @State private var height: CGFloat = 90
    @State private var heightAtDragStart: CGFloat = 90
    @State private var isResizing = false
    @State private var isHoveringHandle = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SepiaFieldLabel(label)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(SepiaTheme.fieldBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isFocused ? SepiaTheme.accent : SepiaTheme.cardLine,
                                lineWidth: isFocused ? 2 : 1
                            )
                    )

                if text.isEmpty, !placeholder.isEmpty {
                    Text(placeholder)
                        .font(SepiaType.bodyLarge)
                        .foregroundColor(SepiaTheme.inkSoft)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                TextEditor(text: $text)
                    .font(SepiaType.bodyLarge)
                    .foregroundColor(SepiaTheme.ink)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .accessibilityLabel(label)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
            }
            .frame(height: height)
            .overlay(alignment: .bottom) {
                // Drag handle straddling the bottom edge
                Capsule()
                    .fill(SepiaTheme.inkSoft.opacity(isResizing || isHoveringHandle ? 0.7 : 0.35))
                    .frame(width: 34, height: 3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 16)
                    .contentShape(Rectangle())
                    .offset(y: 5)
                    .onHover { hovering in
                        isHoveringHandle = hovering
                        if hovering {
                            NSCursor.resizeUpDown.set()
                        } else if !isResizing {
                            NSCursor.arrow.set()
                        }
                    }
                    // Global space: the handle moves with the edge it resizes, so a local
                    // translation would cancel itself out and the drag would stall.
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if !isResizing {
                                    isResizing = true
                                    heightAtDragStart = height
                                    NSCursor.resizeUpDown.set()
                                }
                                height = min(420, max(60, heightAtDragStart + value.translation.height))
                            }
                            .onEnded { _ in
                                isResizing = false
                                heightAtDragStart = height
                                if !isHoveringHandle {
                                    NSCursor.arrow.set()
                                }
                            }
                    )
            }
        }
    }
}

/// Structured date editor. It validates real Gregorian dates and keeps GEDCOM
/// qualifiers/ranges explicit instead of encoding them into an ambiguous text field.
struct SepiaDateField: View {
    let label: String
    @Binding var text: String
    @Binding var qualifier: GenealogyDate.Qualifier
    @Binding var endText: String
    var placeholder: String = L10n.tr("ДД.ММ.ГГГГ")

    init(
        label: String,
        text: Binding<String>,
        qualifier: Binding<GenealogyDate.Qualifier> = .constant(.exact),
        endText: Binding<String> = .constant(""),
        placeholder: String = L10n.tr("ДД.ММ.ГГГГ")
    ) {
        self.label = label
        _text = text
        _qualifier = qualifier
        _endText = endText
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SepiaFieldLabel(label)
            HStack(spacing: 8) {
                Picker("", selection: $qualifier) {
                    ForEach(GenealogyDate.Qualifier.allCases, id: \.rawValue) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 145)
                .accessibilityLabel(L10n.tr("Уточнение даты"))

                SepiaFieldInput(text: $text, placeholder: placeholder, label: label)
                if isRange {
                    Text(qualifier == .between ? L10n.tr("и") : L10n.tr("по"))
                        .font(SepiaTheme.body(size: 12))
                        .foregroundColor(SepiaTheme.inkSoft)
                    SepiaFieldInput(
                        text: $endText,
                        placeholder: placeholder,
                        label: L10n.tr("\(label) — конец диапазона")
                    )
                }
            }
            if !text.isEmpty, !isValidDate {
                Text(L10n.tr("Введите существующую дату или полный диапазон: ДД.ММ.ГГГГ, ММ.ГГГГ или ГГГГ"))
                    .font(SepiaType.label)
                    .foregroundColor(SepiaTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isRange: Bool {
        qualifier == .between || qualifier == .fromTo
    }

    private var isValidDate: Bool {
        GenealogyDate(
            userInput: text,
            qualifier: qualifier,
            endValue: isRange ? endText : nil
        ).isValid
    }
}
