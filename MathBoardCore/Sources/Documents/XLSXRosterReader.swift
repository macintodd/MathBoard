//
//  XLSXRosterReader.swift
//  MathBoardCore — Documents module
//
//  Minimal read-only XLSX reader for classroom roster import.
//  Reads the first worksheet from an Excel .xlsx file and returns its cells
//  as [[String]], ready for the same header-detection and mapping pipeline
//  used by the CSV importer.
//
//  Format notes:
//    • .xlsx is a ZIP archive containing XML files (OOXML standard).
//    • Strings are typically stored in xl/sharedStrings.xml, referenced by
//      index from worksheet cells (t="s" attribute).
//    • Numbers and computed values are stored inline in the cell's <v> element.
//    • Apple's COMPRESSION_ZLIB processes raw DEFLATE data — the same format
//      ZIP method-8 entries use — so no zlib header manipulation is required.
//

import Foundation
import Compression

// MARK: - Public interface

enum XLSXRosterReader {

    enum ReadError: LocalizedError {
        case invalidFormat
        case sheetNotFound
        case decompressionFailed

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                "This file does not appear to be a valid Excel (.xlsx) file."
            case .sheetNotFound:
                "Could not find worksheet data inside the Excel file."
            case .decompressionFailed:
                "Could not decompress data inside the Excel file."
            }
        }
    }

    /// Reads the first worksheet and returns its cell values as a row-major [[String]].
    /// Empty cells within a row are represented as empty strings. The result feeds
    /// directly into `findHeaderRowIndex` and `expandCombinedNameColumns`.
    static func rows(from url: URL) throws -> [[String]] {
        let zipData = try Data(contentsOf: url)
        let entries = try ZIPIndex.build(from: zipData)

        // Shared strings table: most text values are stored here indexed by number.
        var sharedStrings: [String] = []
        if let ssEntry = entries.first(where: { $0.name == "xl/sharedStrings.xml" }) {
            let ssData = try ZIPIndex.extract(entry: ssEntry, from: zipData)
            sharedStrings = SharedStringsParser.parse(ssData)
        }

        // First worksheet (virtually all Excel exports use sheet1.xml).
        let sheetPath = resolveSheetPath(in: entries)
        guard let sheetEntry = entries.first(where: { $0.name == sheetPath }) else {
            throw ReadError.sheetNotFound
        }
        let sheetData = try ZIPIndex.extract(entry: sheetEntry, from: zipData)
        return SheetParser.parse(sheetData, sharedStrings: sharedStrings)
    }

    private static func resolveSheetPath(in entries: [ZIPIndex.Entry]) -> String {
        if entries.contains(where: { $0.name == "xl/worksheets/sheet1.xml" }) {
            return "xl/worksheets/sheet1.xml"
        }
        return entries.first(where: {
            $0.name.hasPrefix("xl/worksheets/") && $0.name.hasSuffix(".xml")
        })?.name ?? "xl/worksheets/sheet1.xml"
    }
}

// MARK: - Minimal ZIP Central Directory reader

private enum ZIPIndex {

    struct Entry {
        let name: String
        let method: UInt16            // 0 = STORED, 8 = DEFLATE
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    /// Builds an index by reading the ZIP Central Directory (more reliable than scanning
    /// local headers, which can have spurious signature bytes inside compressed data).
    static func build(from data: Data) throws -> [Entry] {
        guard let eocd = findEOCD(in: data) else {
            throw XLSXRosterReader.ReadError.invalidFormat
        }
        var pos = Int(eocd.cdOffset)
        var entries: [Entry] = []

        while pos + 46 <= data.count {
            guard data.u32LE(at: pos) == 0x02014B50 else { break } // central-dir signature

            let method           = data.u16LE(at: pos + 10)
            let compressedSize   = data.u32LE(at: pos + 20)
            let uncompressedSize = data.u32LE(at: pos + 24)
            let nameLen          = Int(data.u16LE(at: pos + 28))
            let extraLen         = Int(data.u16LE(at: pos + 30))
            let commentLen       = Int(data.u16LE(at: pos + 32))
            let localOffset      = data.u32LE(at: pos + 42)

            let nameEnd = pos + 46 + nameLen
            if nameLen > 0, nameEnd <= data.count,
               let name = String(data: data[(pos + 46) ..< nameEnd], encoding: .utf8) {
                entries.append(Entry(
                    name: name,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset
                ))
            }
            pos += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    static func extract(entry: Entry, from zipData: Data) throws -> Data {
        let lhOffset = Int(entry.localHeaderOffset)
        guard lhOffset + 30 <= zipData.count,
              zipData.u32LE(at: lhOffset) == 0x04034B50 else { // local file header signature
            throw XLSXRosterReader.ReadError.invalidFormat
        }
        let lhNameLen  = Int(zipData.u16LE(at: lhOffset + 26))
        let lhExtraLen = Int(zipData.u16LE(at: lhOffset + 28))
        let dataStart  = lhOffset + 30 + lhNameLen + lhExtraLen
        let dataEnd    = dataStart + Int(entry.compressedSize)
        guard dataEnd <= zipData.count else {
            throw XLSXRosterReader.ReadError.invalidFormat
        }

        let compressed = Data(zipData[dataStart ..< dataEnd])
        switch entry.method {
        case 0:  return compressed  // STORED — no compression
        case 8:  return try deflateDecompress(compressed, outputSize: Int(entry.uncompressedSize))
        default: throw XLSXRosterReader.ReadError.decompressionFailed
        }
    }

    // Apple's COMPRESSION_ZLIB operates on raw DEFLATE data, which is exactly what
    // ZIP method-8 entries store. No zlib header/trailer wrapping is needed.
    private static func deflateDecompress(_ data: Data, outputSize: Int) throws -> Data {
        guard outputSize > 0 else { return Data() }
        var buf = [UInt8](repeating: 0, count: outputSize)
        let n = data.withUnsafeBytes { src -> Int in
            guard let p = src.baseAddress else { return 0 }
            return compression_decode_buffer(
                &buf, outputSize,
                p.assumingMemoryBound(to: UInt8.self), data.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard n > 0 else { throw XLSXRosterReader.ReadError.decompressionFailed }
        return Data(buf.prefix(n))
    }

    private struct EOCD { let cdOffset: UInt32; let cdSize: UInt32 }

    // Scans backwards from end-of-file to find the End of Central Directory record.
    // Maximum ZIP comment size is 65535 bytes, so we only scan the last 65557 bytes.
    private static func findEOCD(in data: Data) -> EOCD? {
        let minOffset = max(0, data.count - 65557)
        var i = data.count - 22
        while i >= minOffset {
            if data.u32LE(at: i) == 0x06054B50 {  // EOCD signature
                return EOCD(cdOffset: data.u32LE(at: i + 16), cdSize: data.u32LE(at: i + 12))
            }
            i -= 1
        }
        return nil
    }
}

// MARK: - Data integer helpers

// Byte-shift helpers avoid alignment faults when reading from arbitrary offsets in
// a ZIP archive (ZIP fields are not guaranteed to be naturally aligned in memory).
private extension Data {
    func u16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func u32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

// MARK: - xl/sharedStrings.xml parser

/// Collects all shared-string values in document order.
/// Handles both simple strings (<si><t>text</t></si>) and rich-text strings
/// (<si><r><t>part</t></r><r><t>part</t></r></si>) by joining all <t> fragments.
private final class SharedStringsParser: NSObject, XMLParserDelegate {

    private(set) var strings: [String] = []
    private var parts: [String] = []
    private var inSI = false
    private var inT  = false
    private var buf  = ""

    static func parse(_ data: Data) -> [String] {
        let p = SharedStringsParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.parse()
        return p.strings
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "si": inSI = true; parts = []
        case "t":  inT = true;  buf = ""
        default:   break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT { buf += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch name {
        case "t":  inT = false; parts.append(buf)
        case "si": inSI = false; strings.append(parts.joined())
        default:   break
        }
    }
}

// MARK: - xl/worksheets/sheet*.xml parser

/// Parses a worksheet XML into a dense [[String]] grid.
/// Cells are sparse in the XML (missing columns become ""). Empty rows between
/// populated rows are represented as []; the caller's findHeaderRowIndex skips them.
private final class SheetParser: NSObject, XMLParserDelegate {

    private let shared: [String]
    private var cellsByRow: [Int: [Int: String]] = [:]
    private var curRow   = -1
    private var curCol   = -1
    private var cellType = ""
    private var valBuf   = ""
    private var inV      = false
    private var inIS     = false

    private init(shared: [String]) { self.shared = shared }

    static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
        let p = SheetParser(shared: sharedStrings)
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.parse()

        guard !p.cellsByRow.isEmpty, let maxRow = p.cellsByRow.keys.max() else { return [] }
        return (0...maxRow).map { r -> [String] in
            guard let cols = p.cellsByRow[r], let maxCol = cols.keys.max() else { return [] }
            return (0...maxCol).map { c in cols[c] ?? "" }
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "row":
            curRow = (Int(a["r"] ?? "0") ?? 0) - 1
        case "c":
            if let ref = a["r"] { curCol = colIndex(ref) }
            cellType = a["t"] ?? ""
            valBuf   = ""
        case "v":
            inV = true; valBuf = ""
        case "is":
            // Inline string — text accumulates through nested <t> elements.
            inIS = true; valBuf = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if inV || inIS { valBuf += s }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch name {
        case "v":
            inV = false
            if curRow >= 0, curCol >= 0 {
                cellsByRow[curRow, default: [:]][curCol] = resolvedValue()
            }
        case "is":
            inIS = false
            if curRow >= 0, curCol >= 0 {
                cellsByRow[curRow, default: [:]][curCol] = valBuf
            }
        default:
            break
        }
    }

    private func resolvedValue() -> String {
        switch cellType {
        case "s":   // shared string — value is a 0-based index
            let idx = Int(valBuf) ?? 0
            return idx < shared.count ? shared[idx] : ""
        case "b":   // boolean
            return valBuf == "1" ? "TRUE" : "FALSE"
        default:    // number, formula result, or direct string
            return valBuf
        }
    }

    /// Converts a cell reference ("A1", "B3", "AA5") to a 0-based column index.
    private func colIndex(_ ref: String) -> Int {
        var col = 0
        for c in ref {
            guard c.isLetter else { break }
            col = col * 26 + Int(c.uppercased().unicodeScalars.first!.value) - 64
        }
        return max(col - 1, 0)
    }
}
