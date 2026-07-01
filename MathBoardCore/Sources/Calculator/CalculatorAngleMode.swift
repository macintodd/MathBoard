//
//  CalculatorAngleMode.swift
//  MathBoardCore — Calculator module
//
//  Angle units for trig functions. The evaluator converts degrees to
//  radians on the way into `sin/cos/tan/...` and converts the result
//  of `asin/acos/atan` back to the active angle mode.
//

import Foundation

public enum CalculatorAngleMode: String, Codable, Sendable, CaseIterable, Hashable {
    case degrees
    case radians

    public var displayName: String {
        switch self {
        case .degrees: return "DEG"
        case .radians: return "RAD"
        }
    }
}
