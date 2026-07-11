//
//  SlidePDFExporter.swift
//  MathBoardCore - Slides module
//

import CoreGraphics
import CoreText
import Foundation
import PencilKit
import Presentation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SlidePDFExporter {
    @MainActor
    static func export(
        slides: [SlideMetadata],
        drawingURL: @MainActor (SlideMetadata) -> URL,
        backgroundURL: @MainActor (SlideBackground) -> URL,
        lessonName: String
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFileName(for: lessonName))

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let consumer = CGDataConsumer(url: outputURL as CFURL) else {
            throw SlidePDFExportError.couldNotCreatePDF
        }

        var defaultMediaBox = CGRect(origin: .zero, size: CGSize(width: 1920, height: 1080))
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultMediaBox, nil) else {
            throw SlidePDFExportError.couldNotCreatePDF
        }

        for slide in slides {
            let slideDrawingURL = drawingURL(slide)
            let drawing = loadDrawing(at: slideDrawingURL)
            let textObjects = loadTextObjects(forDrawingURL: slideDrawingURL)
            let imageObjects = loadImageObjects(forDrawingURL: slideDrawingURL)
            let geometryObjects = loadGeometryObjects(forDrawingURL: slideDrawingURL)
            let pageInfo = pageInfo(
                for: slide,
                drawing: drawing,
                textObjects: textObjects,
                imageObjects: imageObjects,
                geometryObjects: geometryObjects,
                backgroundURL: backgroundURL
            )
            drawPage(
                pageInfo,
                drawing: drawing,
                textObjects: textObjects,
                imageObjects: imageObjects,
                geometryObjects: geometryObjects,
                drawingURL: slideDrawingURL,
                in: context
            )
        }

        context.closePDF()
        return outputURL
    }

    private static func exportFileName(for lessonName: String) -> String {
        let sanitized = lessonName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let baseName = sanitized.isEmpty ? "MathBoard Export" : sanitized
        return "\(baseName)-\(UUID().uuidString).pdf"
    }

    private static func loadDrawing(at url: URL) -> PKDrawing {
        guard let data = try? Data(contentsOf: url),
              let drawing = try? PKDrawing(data: data) else {
            return PKDrawing()
        }
        return drawing
    }

    private static func loadTextObjects(forDrawingURL drawingURL: URL) -> [PresentationCanvasTextObject] {
        PresentationCanvasTextObject.load(
            from: PresentationCanvasTextObject.sidecarURL(forDrawingURL: drawingURL)
        )
    }

    private static func loadImageObjects(forDrawingURL drawingURL: URL) -> [PresentationCanvasImageObject] {
        PresentationCanvasImageObject.load(
            from: PresentationCanvasImageObject.sidecarURL(forDrawingURL: drawingURL)
        )
    }

    private static func loadGeometryObjects(forDrawingURL drawingURL: URL) -> [PresentationCanvasGeometryObject] {
        PresentationCanvasGeometryObject.load(
            from: PresentationCanvasGeometryObject.sidecarURL(forDrawingURL: drawingURL)
        )
    }

    private static func pageInfo(
        for slide: SlideMetadata,
        drawing: PKDrawing,
        textObjects: [PresentationCanvasTextObject],
        imageObjects: [PresentationCanvasImageObject],
        geometryObjects: [PresentationCanvasGeometryObject],
        backgroundURL: (SlideBackground) -> URL
    ) -> SlidePDFPageInfo {
        if let background = slide.background,
           let document = CGPDFDocument(backgroundURL(background) as CFURL),
           let page = document.page(at: background.pageIndex + 1) {
            let pageBounds = page.getBoxRect(.mediaBox)
            return SlidePDFPageInfo(
                pageRect: CGRect(origin: .zero, size: pageBounds.size),
                sourceRect: pageBounds,
                pdfPage: page
            )
        }

        let contentBounds = combinedContentBounds(
            drawing: drawing,
            textObjects: textObjects,
            imageObjects: imageObjects,
            geometryObjects: geometryObjects
        )
        if !contentBounds.isEmpty {
            let paddedBounds = contentBounds.insetBy(dx: -48, dy: -48)
            return SlidePDFPageInfo(
                pageRect: CGRect(origin: .zero, size: paddedBounds.size),
                sourceRect: paddedBounds,
                pdfPage: nil
            )
        }

        let fallbackRect = CGRect(origin: .zero, size: CGSize(width: 1920, height: 1080))
        return SlidePDFPageInfo(
            pageRect: fallbackRect,
            sourceRect: fallbackRect,
            pdfPage: nil
        )
    }

    private static func combinedContentBounds(
        drawing: PKDrawing,
        textObjects: [PresentationCanvasTextObject],
        imageObjects: [PresentationCanvasImageObject],
        geometryObjects: [PresentationCanvasGeometryObject]
    ) -> CGRect {
        var bounds = drawing.bounds
        for object in textObjects where !object.text.isEmpty {
            if bounds.isEmpty || bounds.isNull {
                bounds = object.frame
            } else {
                bounds = bounds.union(object.frame)
            }
        }
        for object in imageObjects {
            if bounds.isEmpty || bounds.isNull {
                bounds = object.renderedBounds
            } else {
                bounds = bounds.union(object.renderedBounds)
            }
        }
        for object in geometryObjects {
            let frame = object.renderedBounds
            if bounds.isEmpty || bounds.isNull {
                bounds = frame
            } else {
                bounds = bounds.union(frame)
            }
        }
        return bounds
    }

    private static func drawPage(
        _ pageInfo: SlidePDFPageInfo,
        drawing: PKDrawing,
        textObjects: [PresentationCanvasTextObject],
        imageObjects: [PresentationCanvasImageObject],
        geometryObjects: [PresentationCanvasGeometryObject],
        drawingURL: URL,
        in context: CGContext
    ) {
        let mediaBox = pageInfo.pageRect
        context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)

        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(mediaBox)
        context.restoreGState()

        if let pdfPage = pageInfo.pdfPage {
            context.saveGState()
            context.concatenate(
                pdfPage.getDrawingTransform(
                    .mediaBox,
                    rect: pageInfo.pageRect,
                    rotate: 0,
                    preserveAspectRatio: true
                )
            )
            context.drawPDFPage(pdfPage)
            context.restoreGState()
        }

        // Content object layers first, then handwriting ink on top, to match
        // the on-canvas and mirrored paint order.
        drawImageObjects(
            imageObjects,
            assetDirectoryURL: PresentationCanvasImageObject.assetDirectoryURL(forDrawingURL: drawingURL),
            from: pageInfo.sourceRect,
            into: pageInfo.pageRect,
            in: context
        )
        drawGeometryObjects(
            geometryObjects,
            from: pageInfo.sourceRect,
            into: pageInfo.pageRect,
            in: context
        )
        drawTextObjects(
            textObjects,
            from: pageInfo.sourceRect,
            into: pageInfo.pageRect,
            in: context
        )
        drawInk(drawing, from: pageInfo.sourceRect, into: pageInfo.pageRect, in: context)

        context.endPDFPage()
    }

    private static func drawInk(
        _ drawing: PKDrawing,
        from sourceRect: CGRect,
        into destinationRect: CGRect,
        in context: CGContext
    ) {
        guard !drawing.bounds.isEmpty else { return }

        let blackStrokes = drawing.strokes.filter(isBlackStroke)
        let nonBlackStrokes = drawing.strokes.filter { !isBlackStroke($0) }

        if !nonBlackStrokes.isEmpty,
           let cgImage = cgImage(from: PKDrawing(strokes: nonBlackStrokes).image(from: sourceRect, scale: 3)) {
            context.saveGState()
            context.draw(cgImage, in: destinationRect)
            context.restoreGState()
        }

        drawBlackInk(
            blackStrokes,
            from: sourceRect,
            into: destinationRect,
            in: context
        )
    }

    private static func drawBlackInk(
        _ strokes: [PKStroke],
        from sourceRect: CGRect,
        into destinationRect: CGRect,
        in context: CGContext
    ) {
        guard !strokes.isEmpty else { return }

        let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
        let scaleY = destinationRect.height / max(sourceRect.height, 0.001)

        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            let points = Array(stroke.path)
            guard let first = points.first else { continue }

            context.beginPath()
            context.move(to: exportPoint(
                first.location.applying(stroke.transform),
                sourceRect: sourceRect,
                destinationRect: destinationRect,
                scaleX: scaleX,
                scaleY: scaleY
            ))

            for point in points.dropFirst() {
                context.addLine(to: exportPoint(
                    point.location.applying(stroke.transform),
                    sourceRect: sourceRect,
                    destinationRect: destinationRect,
                    scaleX: scaleX,
                    scaleY: scaleY
                ))
            }

            let lineWidth = max(first.size.width * scaleX, first.size.height * scaleY, 1)
            context.setLineWidth(lineWidth)
            context.strokePath()
        }

        context.restoreGState()
    }

    private static func drawImageObjects(
        _ imageObjects: [PresentationCanvasImageObject],
        assetDirectoryURL: URL,
        from sourceRect: CGRect,
        into destinationRect: CGRect,
        in context: CGContext
    ) {
        guard !imageObjects.isEmpty else { return }

        let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
        let scaleY = destinationRect.height / max(sourceRect.height, 0.001)
        context.saveGState()
        context.clip(to: destinationRect)

        for object in imageObjects {
            let imageURL = assetDirectoryURL.appendingPathComponent(object.imageFileName)
            guard let cgImage = cgImage(fromImageAt: imageURL) else { continue }
            let imageRect = CGRect(
                x: destinationRect.minX + (object.x - sourceRect.minX) * scaleX,
                y: destinationRect.maxY - (object.y - sourceRect.minY + object.height) * scaleY,
                width: object.width * scaleX,
                height: object.height * scaleY
            )
            if object.rotation == 0 {
                context.draw(cgImage, in: imageRect)
            } else {
                context.saveGState()
                context.translateBy(x: imageRect.midX, y: imageRect.midY)
                context.rotate(by: -object.rotation)
                context.draw(
                    cgImage,
                    in: CGRect(
                        x: -imageRect.width / 2,
                        y: -imageRect.height / 2,
                        width: imageRect.width,
                        height: imageRect.height
                    )
                )
                context.restoreGState()
            }
        }

        context.restoreGState()
    }

    private static func drawGeometryObjects(
        _ geometryObjects: [PresentationCanvasGeometryObject],
        from sourceRect: CGRect,
        into destinationRect: CGRect,
        in context: CGContext
    ) {
        guard !geometryObjects.isEmpty else { return }

        let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
        let scaleY = destinationRect.height / max(sourceRect.height, 0.001)

        context.saveGState()
        context.clip(to: destinationRect)
        // The PDF context is y-up; flip within the page so the shared y-down
        // renderer draws shapes upright, matching the on-screen canvas.
        context.translateBy(x: 0, y: destinationRect.origin.y * 2 + destinationRect.height)
        context.scaleBy(x: 1, y: -1)

        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: destinationRect.minX + (x - sourceRect.minX) * scaleX,
                y: destinationRect.minY + (y - sourceRect.minY) * scaleY
            )
        }

        for object in geometryObjects {
            let normalized = object.normalizedFrame
            let topLeft = map(normalized.minX, normalized.minY)
            let boundingRect = CGRect(
                x: topLeft.x,
                y: topLeft.y,
                width: normalized.width * scaleX,
                height: normalized.height * scaleY
            )
            let start = map(object.x, object.y)
            let end = map(object.x + object.width, object.y + object.height)
            let pivot = map(object.pivot.x, object.pivot.y)
            PresentationGeometryRenderer.draw(
                object,
                boundingRect: boundingRect,
                start: start,
                end: end,
                lineWidthScale: scaleY,
                pivot: pivot,
                in: context
            )
        }

        context.restoreGState()
    }

    private static func exportPoint(
        _ point: CGPoint,
        sourceRect: CGRect,
        destinationRect: CGRect,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: destinationRect.minX + (point.x - sourceRect.minX) * scaleX,
            y: destinationRect.maxY - (point.y - sourceRect.minY) * scaleY
        )
    }

    private static func drawTextObjects(
        _ textObjects: [PresentationCanvasTextObject],
        from sourceRect: CGRect,
        into destinationRect: CGRect,
        in context: CGContext
    ) {
        guard !textObjects.isEmpty else { return }

        let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
        let scaleY = destinationRect.height / max(sourceRect.height, 0.001)
        context.saveGState()
        context.textMatrix = .identity
        context.clip(to: destinationRect)

        for object in textObjects where !object.text.isEmpty {
            let textRect = CGRect(
                x: destinationRect.minX + (object.x - sourceRect.minX) * scaleX,
                y: destinationRect.maxY - (object.y - sourceRect.minY + object.height) * scaleY,
                width: object.width * scaleX,
                height: object.height * scaleY
            )
            let path = CGMutablePath()
            path.addRect(textRect)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica" as CFString, object.fontSize * scaleY, nil),
                .foregroundColor: CGColor(
                    red: object.red,
                    green: object.green,
                    blue: object.blue,
                    alpha: object.alpha
                )
            ]
            let attributedString = NSAttributedString(string: object.text, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: attributedString.length),
                path,
                nil
            )
            CTFrameDraw(frame, context)
        }

        context.restoreGState()
    }

    #if canImport(UIKit)
    private static func cgImage(from image: UIImage) -> CGImage? {
        image.cgImage
    }

    private static func cgImage(fromImageAt url: URL) -> CGImage? {
        UIImage(contentsOfFile: url.path)?.cgImage
    }

    private static func isBlackStroke(_ stroke: PKStroke) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return false
        }
        return red < 0.08 && green < 0.08 && blue < 0.08 && alpha > 0.1
    }
    #elseif canImport(AppKit)
    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func cgImage(fromImageAt url: URL) -> CGImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func isBlackStroke(_ stroke: PKStroke) -> Bool {
        let color = stroke.ink.color.usingColorSpace(.deviceRGB) ?? stroke.ink.color
        return color.redComponent < 0.08
            && color.greenComponent < 0.08
            && color.blueComponent < 0.08
            && color.alphaComponent > 0.1
    }
    #endif

    private struct SlidePDFPageInfo {
        let pageRect: CGRect
        let sourceRect: CGRect
        let pdfPage: CGPDFPage?
    }
}

enum SlidePDFExportError: LocalizedError {
    case couldNotCreatePDF

    var errorDescription: String? {
        switch self {
        case .couldNotCreatePDF:
            return "The PDF export couldn't be created."
        }
    }
}
