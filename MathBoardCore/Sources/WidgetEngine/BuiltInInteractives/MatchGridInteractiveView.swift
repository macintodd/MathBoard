//
//  MatchGridInteractiveView.swift
//  WidgetEngine
//
//  Teacher-led classroom matching game exposed as a built-in catalog widget.
//

import Observation
import SwiftUI
import CoreGraphics
import CoreText
import UniformTypeIdentifiers

@MainActor
@Observable
final class MatchGridState {
    struct Card: Identifiable, Equatable {
        enum ContentKind: Equatable {
            case equation
            case solution
            case formula
            case name
        }

        let id: UUID
        let pairID: String
        let number: Int
        let content: String
        let kind: ContentKind
    }

    struct Pair: Identifiable, Equatable {
        let id: String
        let left: String
        let right: String
        let allPlayPrompt: String
        let allPlayAnswer: String
    }

    var cards: [Card] = []
    var selectedCardIDs: [Card.ID] = []
    var matchedPairIDs: Set<String> = []
    var turnCount = 0
    var showNotMatchPanel = false
    var showMatchCelebration = false
    var showAllPlay = false
    var allPlayRevealed = false
    var activeAllPlayPair: Pair?

    private(set) var pairs: [Pair] = MatchGridContent.defaultPairs

    init() {
        resetGame()
    }

    var isComplete: Bool {
        matchedPairIDs.count == pairs.count
    }

    var selectedCards: [Card] {
        selectedCardIDs.compactMap { id in cards.first { $0.id == id } }
    }

    var shouldShowAnswerSheet: Bool = false

    func resetGame() {
        pairs = MatchGridContent.defaultPairs
        let generatedCards = pairs.flatMap { pair in
            [
                Card(id: UUID(), pairID: pair.id, number: 0, content: pair.left, kind: contentKind(for: pair.left)),
                Card(id: UUID(), pairID: pair.id, number: 0, content: pair.right, kind: contentKind(for: pair.right))
            ]
        }
        cards = generatedCards.shuffled().enumerated().map { index, card in
            Card(
                id: card.id,
                pairID: card.pairID,
                number: index + 1,
                content: card.content,
                kind: card.kind
            )
        }
        selectedCardIDs = []
        matchedPairIDs = []
        turnCount = 0
        showNotMatchPanel = false
        showMatchCelebration = false
        showAllPlay = false
        allPlayRevealed = false
        activeAllPlayPair = nil
    }

    func flip(_ card: Card) {
        guard !matchedPairIDs.contains(card.pairID),
              !showNotMatchPanel,
              !showAllPlay,
              !selectedCardIDs.contains(card.id),
              selectedCardIDs.count < 2 else { return }

        selectedCardIDs.append(card.id)
        guard selectedCardIDs.count == 2 else { return }

        turnCount += 1
        let flipped = selectedCards
        if flipped.count == 2, flipped[0].pairID == flipped[1].pairID {
            matchedPairIDs.insert(flipped[0].pairID)
            showMatchCelebration = true
        } else {
            showNotMatchPanel = true
        }
    }

    func continueTurn() {
        let wasMatch = showMatchCelebration
        selectedCardIDs = []
        showNotMatchPanel = false
        showMatchCelebration = false
        // Defer auto All Play to the next run loop cycle so the Continue button's
        // tap interaction fully completes before the view hierarchy changes again.
        if wasMatch && !isComplete && Int.random(in: 0..<3) == 0 {
            Task { @MainActor in self.startAllPlay() }
        }
    }

    func startAllPlay() {
        activeAllPlayPair = pairs.randomElement()
        allPlayRevealed = false
        showAllPlay = true
    }

    func revealAllPlayAnswer() {
        allPlayRevealed = true
    }

    func continueAllPlay() {
        showAllPlay = false
        allPlayRevealed = false
        activeAllPlayPair = nil
    }

    func isFaceUp(_ card: Card) -> Bool {
        selectedCardIDs.contains(card.id) || matchedPairIDs.contains(card.pairID)
    }

    private func contentKind(for content: String) -> Card.ContentKind {
        if content.hasPrefix("Area") || content.hasPrefix("Circumference") || content.hasPrefix("Perimeter") {
            return .name
        }
        if content.contains("="), content.contains("x") {
            return .equation
        }
        if content.contains("=") {
            return .solution
        }
        return .formula
    }
}

@MainActor
enum MatchGridStateRegistry {
    private static var statesByWidgetID: [WidgetObject.ID: MatchGridState] = [:]

    static func state(for widgetID: WidgetObject.ID) -> MatchGridState {
        if let state = statesByWidgetID[widgetID] {
            return state
        }
        let state = MatchGridState()
        statesByWidgetID[widgetID] = state
        return state
    }

    static func removeState(for widgetID: WidgetObject.ID) {
        statesByWidgetID.removeValue(forKey: widgetID)
    }
}

struct MatchGridInteractiveView: View {
    @Bindable var state: MatchGridState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(spacing: 10) {
            cardGrid
                .overlay {
                    if state.showMatchCelebration {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.green.opacity(0.95), lineWidth: 8)
                            .shadow(color: .green.opacity(0.65), radius: 18)
                            .allowsHitTesting(false)
                    }
                }

            controlBar
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .contentShape(Rectangle())
        .clipped()
        .overlay {
            if state.showAllPlay {
                allPlayOverlay
            }
        }
        // NOTE: deliberately NOT using .sheet here — a .sheet inside a UIHostingController
        // installs UIKit pan gesture recognizers for interactive dismiss that conflict with
        // the widget container's drag/resize gestures, causing intermittent freezes.
        .overlay {
            if state.shouldShowAnswerSheet {
                MatchGridAnswerSheetView(
                    pairs: state.pairs,
                    cards: state.cards,
                    onDismiss: { state.shouldShowAnswerSheet = false }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                state.startAllPlay()
            } label: {
                Label("All Play", systemImage: "person.3.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                if state.isComplete {
                    performReset()
                } else {
                    performContinueTurn()
                }
            } label: {
                Label(continueButtonTitle, systemImage: continueButtonSystemImage)
                    .frame(minWidth: 112)
            }
            .buttonStyle(.borderedProminent)
            .tint(continueButtonTint)
            .disabled(!isContinueButtonEnabled)
            .accessibilityLabel(continueButtonTitle)

            Spacer(minLength: 0)

            Button {
                state.shouldShowAnswerSheet = true
            } label: {
                Label("Q&A Sheet", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)

            Button {
                performReset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Reset MatchGrid")
        }
        .font(.system(size: 13, weight: .semibold))
    }

    private var isContinueButtonEnabled: Bool {
        state.showNotMatchPanel || state.showMatchCelebration || state.isComplete
    }

    private var continueButtonTitle: String {
        state.isComplete ? "Reset" : "Continue"
    }

    private var continueButtonSystemImage: String {
        state.isComplete ? "arrow.counterclockwise" : "arrow.right.circle.fill"
    }

    private var continueButtonTint: Color {
        if state.isComplete { return .blue }
        if state.showMatchCelebration { return .green }
        if state.showNotMatchPanel { return .orange }
        return .gray
    }

    private var cardGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(state.cards) { card in
                MatchGridCardView(
                    card: card,
                    isFaceUp: state.isFaceUp(card),
                    isMatched: state.matchedPairIDs.contains(card.pairID)
                ) {
                    performFlip(card)
                }
            }
        }
        .padding(8)
        .background(Color(red: 0.94, green: 0.97, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var allPlayOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)

            VStack(spacing: 18) {
                Text("All Play")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.05, green: 0.18, blue: 0.35))

                if let pair = state.activeAllPlayPair {
                    VStack(spacing: 10) {
                        Text(pair.allPlayPrompt)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        WidgetMathTextView(
                            source: pair.left,
                            fontSize: 36,
                            foregroundColor: .black,
                            lineLimit: 3,
                            minimumScaleFactor: 0.45,
                            mathFontSizeMultiplier: 1.1
                        )
                        .frame(minHeight: 60)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.94, green: 0.97, blue: 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if state.allPlayRevealed {
                        VStack(spacing: 6) {
                            Text("Answer")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.secondary)
                            WidgetMathTextView(
                                source: pair.allPlayAnswer,
                                fontSize: 42,
                                foregroundColor: Color(red: 0.02, green: 0.11, blue: 0.24),
                                lineLimit: 2,
                                minimumScaleFactor: 0.55,
                                mathFontSizeMultiplier: 1.18
                            )
                            .frame(minHeight: 62)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        state.revealAllPlayAnswer()
                    } label: {
                        Label("Reveal Answer", systemImage: "eye.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        state.continueAllPlay()
                    } label: {
                        Label("Continue", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(28)
            .frame(width: 620)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.28), radius: 28, x: 0, y: 16)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func performFlip(_ card: MatchGridState.Card) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.flip(card)
        }
    }

    private func performContinueTurn() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.continueTurn()
        }
    }

    private func performReset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.resetGame()
        }
    }
}

private struct MatchGridCardView: View {
    let card: MatchGridState.Card
    let isFaceUp: Bool
    let isMatched: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(isFaceUp ? Color.white : Color(red: 0.13, green: 0.33, blue: 0.62))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isMatched ? .green : Color(red: 0.05, green: 0.18, blue: 0.35), lineWidth: isMatched ? 3 : 1)
                }

            if isFaceUp {
                Text(MatchGridCardTextFormatter.displayText(for: card.content))
                    .font(.system(size: displayFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.35)
                    .padding(6)
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 0.35, y: 0)
            } else {
                Text("\(card.number)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .aspectRatio(1.55, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture {
            guard !isMatched else { return }
            action()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFaceUp ? "Card \(card.number), \(card.content)" : "Card \(card.number)")
        .accessibilityAddTraits(isMatched ? [] : .isButton)
    }

    private var displayFontSize: CGFloat {
        switch card.kind {
        case .equation: return 20
        case .solution: return 22
        case .formula: return 21
        case .name: return 17
        }
    }
}

private enum MatchGridCardTextFormatter {
    static func displayText(for text: String) -> String {
        text
            .replacingOccurrences(of: "\\frac{1}{2}", with: "1/2")
            .replacingOccurrences(of: "\\frac{2}{3}", with: "2/3")
            .replacingOccurrences(of: "\\frac{3}{4}", with: "3/4")
            .replacingOccurrences(of: "\\frac{5}{6}", with: "5/6")
            .replacingOccurrences(of: "\\frac{5}{2}", with: "5/2")
            .replacingOccurrences(of: "\\frac{13}{6}", with: "13/6")
            .replacingOccurrences(of: "\\frac{11}{3}", with: "11/3")
            .replacingOccurrences(of: "\\frac{16}{5}", with: "16/5")
            .replacingOccurrences(of: "\\pi", with: "π")
            .replacingOccurrences(of: "^2", with: "²")
    }
}

private struct MatchGridAnswerSheetView: View {
    let pairs: [MatchGridState.Pair]
    let cards: [MatchGridState.Card]
    let onDismiss: () -> Void

    @State private var selectedSheet = 0  // 0=student, 1=answers, 2=allplay
    @State private var isShowingPDFExporter = false
    @State private var pdfDocument = MatchGridPDFDocument(data: Data())

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("MatchGrid Q&A Sheet")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    pdfDocument = MatchGridPDFDocument(data: MatchGridPDFExporter.export(pairs: pairs, cards: cards))
                    isShowingPDFExporter = true
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Sheet", selection: $selectedSheet) {
                        Text("Student Sheet").tag(0)
                        Text("Answer Key").tag(1)
                        Text("All Play").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch selectedSheet {
                    case 1: answerKey
                    case 2: allPlaySheet
                    default: studentSheet
                    }
                }
                .padding(20)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .padding(12)
        .fileExporter(
            isPresented: $isShowingPDFExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "MatchGrid-QA-Sheets"
        ) { _ in }
    }

    private var studentSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Student Tracking Sheet")
                .font(.title3.weight(.bold))
            Text("Write what appears under each card number so your group can track possible matches.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(1...36, id: \.self) { number in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(number)")
                            .font(.caption.weight(.bold))
                        Spacer()
                    }
                    .padding(6)
                    .frame(minHeight: 72)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.35), lineWidth: 1)
                    }
                }
            }
        }
    }

    private var answerKey: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Answer Key")
                .font(.title3.weight(.bold))

            ForEach(pairs) { pair in
                let matchingCards = cards.filter { $0.pairID == pair.id }.sorted { $0.number < $1.number }
                HStack(alignment: .top, spacing: 10) {
                    Text(matchingCards.map { "\($0.number)" }.joined(separator: " & "))
                        .font(.headline.monospacedDigit())
                        .frame(width: 70, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(MatchGridCardTextFormatter.displayText(for: pair.left))
                            .font(.subheadline.weight(.semibold))
                        Text(MatchGridCardTextFormatter.displayText(for: pair.right))
                            .font(.subheadline)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var allPlaySheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All Play Questions")
                .font(.title3.weight(.bold))
            Text("These prompts are shown to the whole class during the game.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1).")
                        .font(.headline.monospacedDigit())
                        .frame(width: 30, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pair.allPlayPrompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(MatchGridCardTextFormatter.displayText(for: pair.left))
                            .font(.subheadline.weight(.semibold))
                        Text("Answer: \(MatchGridCardTextFormatter.displayText(for: pair.allPlayAnswer))")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct MatchGridPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum MatchGridPDFExporter {
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 36
    private static let black = CGColor(gray: 0, alpha: 1)
    private static let gray = CGColor(gray: 0.55, alpha: 1)

    static func export(pairs: [MatchGridState.Pair], cards: [MatchGridState.Card]) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        context.beginPDFPage(nil)
        drawStudentSheet(in: context)
        context.endPDFPage()

        context.beginPDFPage(nil)
        drawAnswerKey(in: context, pairs: pairs, cards: cards)
        context.endPDFPage()

        context.beginPDFPage(nil)
        drawAllPlay(in: context, pairs: pairs)
        context.endPDFPage()

        context.closePDF()
        return data as Data
    }

    private static func drawStudentSheet(in context: CGContext) {
        drawText(
            "MatchGrid Student Tracking Sheet",
            in: context,
            at: CGPoint(x: margin, y: 34),
            size: 22,
            isBold: true
        )
        drawText(
            "Write what appears under each card number so your group can track possible matches.",
            in: context,
            at: CGPoint(x: margin, y: 62),
            size: 11
        )

        let spacing: CGFloat = 6
        let columns = 6
        let cellWidth = (pageSize.width - (margin * 2) - (CGFloat(columns - 1) * spacing)) / CGFloat(columns)
        let cellHeight: CGFloat = 92
        let top: CGFloat = 92

        for index in 0..<36 {
            let row = index / columns
            let column = index % columns
            let rect = CGRect(
                x: margin + CGFloat(column) * (cellWidth + spacing),
                y: top + CGFloat(row) * (cellHeight + spacing),
                width: cellWidth,
                height: cellHeight
            )
            drawRect(rect, in: context, stroke: black, lineWidth: 0.8)
            drawText("\(index + 1)", in: context, at: CGPoint(x: rect.minX + 6, y: rect.minY + 6), size: 11, isBold: true)
        }
    }

    private static func drawAnswerKey(
        in context: CGContext,
        pairs: [MatchGridState.Pair],
        cards: [MatchGridState.Card]
    ) {
        drawText("MatchGrid Answer Key", in: context, at: CGPoint(x: margin, y: 34), size: 22, isBold: true)
        drawText("Matching card numbers are listed beside each pair.", in: context, at: CGPoint(x: margin, y: 62), size: 11)

        let columnWidth = (pageSize.width - (margin * 2) - 18) / 2
        let rowHeight: CGFloat = 64
        let top: CGFloat = 92

        for (index, pair) in pairs.enumerated() {
            let column = index / 9
            let row = index % 9
            let x = margin + CGFloat(column) * (columnWidth + 18)
            let y = top + CGFloat(row) * rowHeight
            let matchingCards = cards
                .filter { $0.pairID == pair.id }
                .sorted { $0.number < $1.number }
                .map { "\($0.number)" }
                .joined(separator: " & ")

            drawRect(CGRect(x: x, y: y, width: columnWidth, height: rowHeight - 8), in: context, stroke: gray, lineWidth: 0.7)
            drawText(matchingCards, in: context, at: CGPoint(x: x + 8, y: y + 7), size: 12, isBold: true)
            drawText(cleanMathText(pair.left), in: context, at: CGPoint(x: x + 8, y: y + 26), size: 10, maxWidth: columnWidth - 16)
            drawText(cleanMathText(pair.right), in: context, at: CGPoint(x: x + 8, y: y + 42), size: 10, isBold: true, maxWidth: columnWidth - 16)
        }
    }

    private static func drawAllPlay(in context: CGContext, pairs: [MatchGridState.Pair]) {
        drawText("MatchGrid All Play Questions", in: context, at: CGPoint(x: margin, y: 34), size: 22, isBold: true)
        drawText("Whole-class review prompts shown during the game. Show the question, let students respond, then reveal the answer.", in: context, at: CGPoint(x: margin, y: 62), size: 11)

        let rowsPerColumn = Int(ceil(Double(pairs.count) / 2.0))
        let columnWidth = (pageSize.width - (margin * 2) - 18) / 2
        let rowHeight: CGFloat = 74
        let top: CGFloat = 92

        for (index, pair) in pairs.enumerated() {
            let column = index / rowsPerColumn
            let row = index % rowsPerColumn
            let x = margin + CGFloat(column) * (columnWidth + 18)
            let y = top + CGFloat(row) * rowHeight

            drawRect(CGRect(x: x, y: y, width: columnWidth, height: rowHeight - 6), in: context, stroke: gray, lineWidth: 0.7)
            drawText("\(index + 1). \(pair.allPlayPrompt)", in: context, at: CGPoint(x: x + 8, y: y + 7), size: 9, maxWidth: columnWidth - 16)
            drawText(cleanMathText(pair.left), in: context, at: CGPoint(x: x + 8, y: y + 22), size: 11, isBold: true, maxWidth: columnWidth - 16)
            drawText("Answer: \(cleanMathText(pair.allPlayAnswer))", in: context, at: CGPoint(x: x + 8, y: y + 42), size: 10, maxWidth: columnWidth - 16)
        }
    }

    private static func drawRect(_ rect: CGRect, in context: CGContext, stroke color: CGColor, lineWidth: CGFloat) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.stroke(CGRect(x: rect.minX, y: pageSize.height - rect.maxY, width: rect.width, height: rect.height))
        context.restoreGState()
    }

    private static func drawText(
        _ text: String,
        in context: CGContext,
        at point: CGPoint,
        size: CGFloat,
        isBold: Bool = false,
        maxWidth: CGFloat = pageSize.width - (margin * 2)
    ) {
        let fontName = isBold ? "Helvetica-Bold" : "Helvetica"
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: black
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let height = max(size + 6, suggestedTextHeight(for: attributed, width: maxWidth))
        let path = CGPath(rect: CGRect(x: point.x, y: pageSize.height - point.y - height, width: maxWidth, height: height), transform: nil)

        context.saveGState()
        context.textMatrix = .identity
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func suggestedTextHeight(for attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        )
        return ceil(size.height) + 4
    }

    private static func cleanMathText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\frac{1}{2}", with: "1/2")
            .replacingOccurrences(of: "\\frac{2}{3}", with: "2/3")
            .replacingOccurrences(of: "\\frac{3}{4}", with: "3/4")
            .replacingOccurrences(of: "\\frac{5}{6}", with: "5/6")
            .replacingOccurrences(of: "\\frac{5}{2}", with: "5/2")
            .replacingOccurrences(of: "\\frac{13}{6}", with: "13/6")
            .replacingOccurrences(of: "\\frac{11}{3}", with: "11/3")
            .replacingOccurrences(of: "\\frac{16}{5}", with: "16/5")
            .replacingOccurrences(of: "\\pi", with: "π")
            .replacingOccurrences(of: "^2", with: "²")
    }
}

private enum MatchGridContent {
    static let defaultPairs: [MatchGridState.Pair] = [
        .init(
            id: "eq-1",
            left: "3x + 7 = 22",
            right: "x = 5",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = 5"
        ),
        .init(
            id: "eq-2",
            left: "5x - 4 = 2x + 14",
            right: "x = 6",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = 6"
        ),
        .init(
            id: "eq-3",
            left: "\\frac{1}{2}x + 3 = 9",
            right: "x = 12",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = 12"
        ),
        .init(
            id: "eq-4",
            left: "0.4x + 1.6 = 4.4",
            right: "x = 7",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = 7"
        ),
        .init(
            id: "eq-5",
            left: "7x - 2x + 4 = 44",
            right: "x = 8",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = 8"
        ),
        .init(
            id: "eq-6",
            left: "\\frac{3}{4}x - 2 = 4.75",
            right: "x = 9",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = 9"
        ),
        .init(
            id: "eq-7",
            left: "9x + 1 = 4x + 56",
            right: "x = 11",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = 11"
        ),
        .init(
            id: "eq-8",
            left: "2.5x - 3 = 29.5",
            right: "x = 13",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = 13"
        ),
        .init(
            id: "eq-9",
            left: "\\frac{2}{3}x + \\frac{1}{2} = \\frac{13}{6}",
            right: "x = \\frac{5}{2}",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = \\frac{5}{2}"
        ),
        .init(
            id: "eq-10",
            left: "4x + 8 = x - 7",
            right: "x = -5",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = -5"
        ),
        .init(
            id: "eq-11",
            left: "6x - 3x - 10 = 2",
            right: "x = 4",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = 4"
        ),
        .init(
            id: "eq-12",
            left: "\\frac{5}{6}x + 1 = \\frac{11}{3}",
            right: "x = \\frac{16}{5}",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = \\frac{16}{5}"
        ),
        .init(
            id: "eq-13",
            left: "8x - 13 = 3x + 57",
            right: "x = 14",
            allPlayPrompt: "Solve the equation.",
            allPlayAnswer: "x = 14"
        ),
        .init(
            id: "formula-1",
            left: "A = \\frac{1}{2}bh",
            right: "Area of a Triangle",
            allPlayPrompt: "Name the formula.",
            allPlayAnswer: "Area of a Triangle"
        ),
        .init(
            id: "formula-2",
            left: "C = 2\\pi r",
            right: "Circumference of a Circle",
            allPlayPrompt: "Name the formula.",
            allPlayAnswer: "Circumference of a Circle"
        ),
        .init(
            id: "formula-3",
            left: "A = \\pi r^2",
            right: "Area of a Circle",
            allPlayPrompt: "Name the formula.",
            allPlayAnswer: "Area of a Circle"
        ),
        .init(
            id: "formula-4",
            left: "A = lw",
            right: "Area of a Rectangle",
            allPlayPrompt: "Name the formula.",
            allPlayAnswer: "Area of a Rectangle"
        ),
        .init(
            id: "formula-5",
            left: "P = 2l + 2w",
            right: "Perimeter of a Rectangle",
            allPlayPrompt: "Name the formula.",
            allPlayAnswer: "Perimeter of a Rectangle"
        )
    ]
}
