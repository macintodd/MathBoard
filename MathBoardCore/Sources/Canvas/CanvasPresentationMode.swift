//
//  CanvasPresentationMode.swift
//  MathBoardCore - Canvas module
//

public enum CanvasPresentationMode: Sendable, Equatable {
    /// Publish the full visible iPad canvas. The TV letterboxes this 4:3-ish frame.
    case mirror

    /// Publish the centered 16:9 viewfinder region. The TV fills with this frame.
    case present
}
