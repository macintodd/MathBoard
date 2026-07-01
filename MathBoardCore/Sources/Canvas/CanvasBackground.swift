//
//  CanvasBackground.swift
//  MathBoardCore - Canvas module
//

import Foundation

public struct CanvasBackground: Sendable, Equatable {
    public let pdfURL: URL
    public let pageIndex: Int

    public init(pdfURL: URL, pageIndex: Int) {
        self.pdfURL = pdfURL
        self.pageIndex = pageIndex
    }
}
