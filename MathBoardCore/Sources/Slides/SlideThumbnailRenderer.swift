//
//  SlideThumbnailRenderer.swift
//  MathBoardCore - Slides module
//

import CoreGraphics
import CoreText
import Foundation
import PDFKit
import PencilKit
import Presentation
import SwiftUI
import WidgetEngine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SlideThumbnailContent {
    let image: Image?
    let widgetKind: WidgetObjectActivityKind?

    var isWidgetOnly: Bool {
        image == nil && widgetKind != nil
    }
}

enum SlideThumbnailRenderer {
    static let pixelSize = CGSize(width: 232, height: 174)

    @MainActor
    static func content(
        for slide: SlideMetadata,
        drawingURL: URL,
        backgroundURL: (SlideBackground) -> URL
    ) -> SlideThumbnailContent {
        let widgets = WidgetObject.load(from: WidgetObject.sidecarURL(forDrawingURL: drawingURL))
        let widgetKind = widgets.first?.activityKind
        let image = renderedImage(for: slide, drawingURL: drawingURL, backgroundURL: backgroundURL)
        return SlideThumbnailContent(image: image, widgetKind: widgetKind)
    }

    @MainActor
    static func cacheKey(
        for slide: SlideMetadata,
        drawingURL: URL,
        backgroundURL: (SlideBackground) -> URL
    ) -> String {
        var pieces = [
            slide.id.uuidString,
            slide.background?.assetFileName ?? "no-background",
            String(slide.background?.pageIndex ?? -1)
        ]

        if let background = slide.background {
            pieces.append(fingerprint(for: backgroundURL(background)))
        }

        let relatedURLs = [
            drawingURL,
            PresentationCanvasTextObject.sidecarURL(forDrawingURL: drawingURL),
            PresentationCanvasImageObject.sidecarURL(forDrawingURL: drawingURL),
            PresentationCanvasLaTeXObject.sidecarURL(forDrawingURL: drawingURL),
            PresentationCanvasGeometryObject.sidecarURL(forDrawingURL: drawingURL),
            WidgetObject.sidecarURL(forDrawingURL: drawingURL)
        ]
        pieces.append(contentsOf: relatedURLs.map(fingerprint(for:)))
        return pieces.joined(separator: "|")
    }

    private static func renderedImage(
        for slide: SlideMetadata,
        drawingURL: URL,
        backgroundURL: (SlideBackground) -> URL
    ) -> Image? {
        let drawing = loadDrawing(at: drawingURL)
        let textObjects = PresentationCanvasTextObject.load(from: PresentationCanvasTextObject.sidecarURL(forDrawingURL: drawingURL))
        let imageObjects = PresentationCanvasImageObject.load(from: PresentationCanvasImageObject.sidecarURL(forDrawingURL: drawingURL))
        let geometryObjects = PresentationCanvasGeometryObject.load(from: PresentationCanvasGeometryObject.sidecarURL(forDrawingURL: drawingURL))

        guard hasRenderableContent(
            slide: slide,
            drawing: drawing,
            textObjects: textObjects,
            imageObjects: imageObjects,
            geometryObjects: geometryObjects
        ) else {
            return nil
        }

        let sourceRect = thumbnailSourceRect(
            for: slide,
            drawing: drawing,
            textObjects: textObjects,
            imageObjects: imageObjects,
            geometryObjects: geometryObjects,
            backgroundURL: backgroundURL
        )

        return makePlatformImage(size: pixelSize) { context in
            let destinationRect = CGRect(origin: .zero, size: pixelSize)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(destinationRect)

            if let background = slide.background,
               let document = CGPDFDocument(backgroundURL(background) as CFURL),
               let page = document.page(at: background.pageIndex + 1) {
                drawPDFPage(page, sourceRect: sourceRect, destinationRect: destinationRect, in: context)
            }

            drawImageObjects(
                imageObjects,
                assetDirectoryURL: PresentationCanvasImageObject.assetDirectoryURL(forDrawingURL: drawingURL),
                sourceRect: sourceRect,
                destinationRect: destinationRect,
                in: context
            )
            drawGeometryObjects(geometryObjects, sourceRect: sourceRect, destinationRect: destinationRect, in: context)
            drawTextObjects(textObjects, sourceRect: sourceRect, destinationRect: destinationRect, in: context)
            drawInk(drawing, sourceRect: sourceRect, destinationRect: destinationRect, in: context)
        }
    }

    private static func hasRenderableContent(
        slide: SlideMetadata,
        drawing: PKDrawing,
        textObjects: [PresentationCanvasTextObject],
        imageObjects: [PresentationCanvasImageObject],
        geometryObjects: [PresentationCanvasGeometryObject]
    ) -> Bool {
        slide.background != nil
            || !drawing.bounds.isEmpty
            || textObjects.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !imageObjects.isEmpty
            || !geometryObjects.isEmpty
    }

    private static func thumbnailSourceRect(
        for slide: SlideMetadata,
        drawing: PKDrawing,
        textObjects: [PresentationCanvasTextObject],
        imageObjects: [PresentationCanvasImageObject],
        geometryObjects: [PresentationCanvasGeometryObject],
        backgroundURL: (SlideBackground) -> URL
    ) -> CGRect {
        if let background = slide.background,
           let document = CGPDFDocument(backgroundURL(background) as CFURL),
           let page = document.page(at: background.pageIndex + 1) {
            return page.getBoxRect(.mediaBox)
        }

        var bounds = drawing.bounds
        for object in textObjects where !object.text.isEmpty {
            bounds = union(bounds, object.renderedBounds)
        }
        for object in imageObjects {
            bounds = union(bounds, object.renderedBounds)
        }
        for object in geometryObjects {
            bounds = union(bounds, object.renderedBounds)
        }

        let usableBounds = bounds.isEmpty || bounds.isNull
            ? CGRect(origin: .zero, size: PresentationCanvasBoardMetrics.defaultUsableSize)
            : bounds.insetBy(dx: -48, dy: -48)
        return fourByThreeRect(containing: usableBounds)
    }

    private static func fourByThreeRect(containing rect: CGRect) -> CGRect {
        let targetAspect: CGFloat = 4 / 3
        var result = rect.standardized
        let aspect = result.width / max(result.height, 0.001)
        if aspect > targetAspect {
            let newHeight = result.width / targetAspect
            result.origin.y -= (newHeight - result.height) / 2
            result.size.height = newHeight
        } else {
            let newWidth = result.height * targetAspect
            result.origin.x -= (newWidth - result.width) / 2
            result.size.width = newWidth
        }
        return result
    }

    private static func union(_ existing: CGRect, _ next: CGRect) -> CGRect {
        guard !next.isEmpty, !next.isNull else { return existing }
        guard !existing.isEmpty, !existing.isNull else { return next }
        return existing.union(next)
    }

    private static func loadDrawing(at url: URL) -> PKDrawing {
        guard let data = try? Data(contentsOf: url),
              let drawing = try? PKDrawing(data: data) else {
            return PKDrawing()
        }
        return drawing
    }

    private static func drawPDFPage(
        _ page: CGPDFPage,
        sourceRect: CGRect,
        destinationRect: CGRect,
        in context: CGContext
    ) {
        context.saveGState()
        context.clip(to: destinationRect)
        context.translateBy(x: 0, y: destinationRect.height)
        context.scaleBy(x: 1, y: -1)
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: destinationRect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        context.restoreGState()
    }

    private static func drawInk(
        _ drawing: PKDrawing,
        sourceRect: CGRect,
        destinationRect: CGRect,
        in context: CGContext
    ) {
        guard !drawing.bounds.isEmpty, let cgImage = cgImage(from: drawing.image(from: sourceRect, scale: 2)) else { return }
        context.saveGState()
        context.draw(cgImage, in: destinationRect)
        context.restoreGState()
    }

    private static func drawImageObjects(
        _ imageObjects: [PresentationCanvasImageObject],
        assetDirectoryURL: URL,
        sourceRect: CGRect,
        destinationRect: CGRect,
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
            let rect = CGRect(
                x: destinationRect.minX + (object.x - sourceRect.minX) * scaleX,
                y: destinationRect.minY + (object.y - sourceRect.minY) * scaleY,
                width: object.width * scaleX,
                height: object.height * scaleY
            )
            context.saveGState()
            if object.rotation != 0 {
                context.translateBy(x: rect.midX, y: rect.midY)
                context.rotate(by: object.rotation)
                context.translateBy(x: -rect.midX, y: -rect.midY)
            }
            context.draw(cgImage, in: rect)
            context.restoreGState()
        }
        context.restoreGState()
    }

    private static func drawGeometryObjects(
        _ geometryObjects: [PresentationCanvasGeometryObject],
        sourceRect: CGRect,
        destinationRect: CGRect,
        in context: CGContext
    ) {
        guard !geometryObjects.isEmpty else { return }
        let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
        let scaleY = destinationRect.height / max(sourceRect.height, 0.001)

        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: destinationRect.minX + (point.x - sourceRect.minX) * scaleX,
                y: destinationRect.minY + (point.y - sourceRect.minY) * scaleY
            )
        }

        context.saveGState()
        context.clip(to: destinationRect)
        for object in geometryObjects {
            let normalized = object.normalizedFrame
            let topLeft = map(CGPoint(x: normalized.minX, y: normalized.minY))
            let boundingRect = CGRect(
                x: topLeft.x,
                y: topLeft.y,
                width: normalized.width * scaleX,
                height: normalized.height * scaleY
            )
            PresentationGeometryRenderer.draw(
                object,
                boundingRect: boundingRect,
                start: map(CGPoint(x: object.x, y: object.y)),
                end: map(CGPoint(x: object.x + object.width, y: object.y + object.height)),
                lineWidthScale: min(scaleX, scaleY),
                pivot: map(object.pivot),
                in: context
            )
        }
        context.restoreGState()
    }

    private static func drawTextObjects(
        _ textObjects: [PresentationCanvasTextObject],
        sourceRect: CGRect,
        destinationRect: CGRect,
        in context: CGContext
    ) {
        guard !textObjects.isEmpty else { return }
        let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
        let scaleY = destinationRect.height / max(sourceRect.height, 0.001)

        context.saveGState()
        context.clip(to: destinationRect)
        context.textMatrix = .identity
        for object in textObjects where !object.text.isEmpty {
            let textRect = CGRect(
                x: destinationRect.minX + (object.x - sourceRect.minX) * scaleX,
                y: destinationRect.minY + (object.y - sourceRect.minY) * scaleY,
                width: object.width * scaleX,
                height: object.height * scaleY
            )
            let path = CGMutablePath()
            path.addRect(textRect)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName((object.fontName ?? "Helvetica") as CFString, max(object.fontSize * scaleY, 4), nil),
                .foregroundColor: CGColor(red: object.red, green: object.green, blue: object.blue, alpha: object.alpha)
            ]
            let attributedString = NSAttributedString(string: object.text, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributedString.length), path, nil)
            CTFrameDraw(frame, context)
        }
        context.restoreGState()
    }

    private static func fingerprint(for url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return "missing:\(url.lastPathComponent)"
        }
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values.fileSize ?? 0
        return "\(url.lastPathComponent):\(modified):\(size)"
    }

    #if canImport(UIKit)
    private static func makePlatformImage(size: CGSize, draw: (CGContext) -> Void) -> Image? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            draw(rendererContext.cgContext)
        }
        return Image(uiImage: image)
    }

    private static func cgImage(from image: UIImage) -> CGImage? {
        image.cgImage
    }

    private static func cgImage(fromImageAt url: URL) -> CGImage? {
        UIImage(contentsOfFile: url.path)?.cgImage
    }
    #elseif canImport(AppKit)
    private static func makePlatformImage(size: CGSize, draw: (CGContext) -> Void) -> Image? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width.rounded(.up)),
            pixelsHigh: Int(size.height.rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        representation.size = size
        NSGraphicsContext.saveGraphicsState()
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = graphicsContext
        draw(graphicsContext.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return Image(nsImage: image)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func cgImage(fromImageAt url: URL) -> CGImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
    #endif
}
