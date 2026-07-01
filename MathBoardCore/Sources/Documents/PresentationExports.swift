//
//  PresentationExports.swift
//  MathBoardCore — Documents module
//
//  Re-exports the modules below Documents in the dependency chain so
//  callers that `import Documents` also get their public types
//  (`DisplayBroker`, `ExternalCanvasView`, `SlidesView`, etc.) without
//  having to link multiple libraries. Keeps the app target's link line
//  to just `Documents`.
//

@_exported import Presentation
@_exported import Slides
