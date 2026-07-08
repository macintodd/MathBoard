//
//  CalculatorStatistics.swift
//  MathBoardCore - Calculator module
//
//  Small statistical helpers for TI-style STAT CALC screens.
//

import Foundation

public struct CalculatorRegressionResult: Equatable, Sendable {
    public var model: CalculatorRegressionModel
    public var coefficients: [Double]
    public var rSquared: Double?

    public init(model: CalculatorRegressionModel, coefficients: [Double], rSquared: Double? = nil) {
        self.model = model
        self.coefficients = coefficients
        self.rSquared = rSquared
    }
}

public enum CalculatorRegressionModel: String, CaseIterable, Sendable {
    case linear
    case quadratic
    case cubic
    case quartic

    public var title: String {
        switch self {
        case .linear: return "LinReg(ax+b)"
        case .quadratic: return "QuadReg"
        case .cubic: return "CubicReg"
        case .quartic: return "QuartReg"
        }
    }

    public var degree: Int {
        switch self {
        case .linear: return 1
        case .quadratic: return 2
        case .cubic: return 3
        case .quartic: return 4
        }
    }

    public var coefficientNames: [String] {
        switch self {
        case .linear: return ["a", "b"]
        case .quadratic: return ["a", "b", "c"]
        case .cubic: return ["a", "b", "c", "d"]
        case .quartic: return ["a", "b", "c", "d", "e"]
        }
    }

    public func expression(coefficients: [Double]) -> String {
        guard coefficients.count == degree + 1 else { return "" }
        switch self {
        case .linear:
            return "\(CalculatorResultFormatter.string(for: coefficients[0]))x+\(CalculatorResultFormatter.string(for: coefficients[1]))"
        case .quadratic:
            return "\(CalculatorResultFormatter.string(for: coefficients[0]))x^2+\(CalculatorResultFormatter.string(for: coefficients[1]))x+\(CalculatorResultFormatter.string(for: coefficients[2]))"
        case .cubic:
            return "\(CalculatorResultFormatter.string(for: coefficients[0]))x^3+\(CalculatorResultFormatter.string(for: coefficients[1]))x^2+\(CalculatorResultFormatter.string(for: coefficients[2]))x+\(CalculatorResultFormatter.string(for: coefficients[3]))"
        case .quartic:
            return "\(CalculatorResultFormatter.string(for: coefficients[0]))x^4+\(CalculatorResultFormatter.string(for: coefficients[1]))x^3+\(CalculatorResultFormatter.string(for: coefficients[2]))x^2+\(CalculatorResultFormatter.string(for: coefficients[3]))x+\(CalculatorResultFormatter.string(for: coefficients[4]))"
        }
    }
}

public enum CalculatorStatistics {
    public static func regression(
        model: CalculatorRegressionModel,
        xValues: [Double],
        yValues: [Double]
    ) -> CalculatorRegressionResult? {
        let pairs = zip(xValues, yValues).filter { $0.0.isFinite && $0.1.isFinite }
        let requiredCount = model.degree + 1
        guard pairs.count >= requiredCount else { return nil }

        let coefficients = solveLeastSquares(
            degree: model.degree,
            xValues: pairs.map(\.0),
            yValues: pairs.map(\.1)
        )
        guard let coefficients else { return nil }

        let rSquared = coefficientOfDetermination(
            coefficients: coefficients,
            xValues: pairs.map(\.0),
            yValues: pairs.map(\.1)
        )
        return CalculatorRegressionResult(model: model, coefficients: coefficients, rSquared: rSquared)
    }

    public static func fractionString(for value: Double, maxDenominator: Int = 10_000) -> String? {
        guard value.isFinite else { return nil }
        if value == 0 { return "0" }

        let sign = value < 0 ? -1 : 1
        let target = abs(value)
        var lowerN = 0
        var lowerD = 1
        var upperN = 1
        var upperD = 0

        while true {
            let middleN = lowerN + upperN
            let middleD = lowerD + upperD
            if middleD > maxDenominator { break }

            let middle = Double(middleN) / Double(middleD)
            if abs(middle - target) < 1e-10 {
                return normalizedFraction(numerator: sign * middleN, denominator: middleD)
            } else if middle < target {
                lowerN = middleN
                lowerD = middleD
            } else {
                upperN = middleN
                upperD = middleD
            }
        }

        let lowerError = abs(Double(lowerN) / Double(lowerD) - target)
        let upperError = upperD == 0 ? Double.infinity : abs(Double(upperN) / Double(upperD) - target)
        if lowerError <= upperError {
            return normalizedFraction(numerator: sign * lowerN, denominator: lowerD)
        }
        return normalizedFraction(numerator: sign * upperN, denominator: upperD)
    }

    private static func normalizedFraction(numerator: Int, denominator: Int) -> String {
        if denominator == 1 { return "\(numerator)" }
        return "\(numerator)/\(denominator)"
    }

    private static func solveLeastSquares(degree: Int, xValues: [Double], yValues: [Double]) -> [Double]? {
        let count = degree + 1
        var matrix = Array(repeating: Array(repeating: 0.0, count: count + 1), count: count)

        for row in 0..<count {
            for column in 0..<count {
                matrix[row][column] = xValues.reduce(0) { $0 + pow($1, Double(row + column)) }
            }
            matrix[row][count] = zip(xValues, yValues).reduce(0) { $0 + $1.1 * pow($1.0, Double(row)) }
        }

        guard let ascending = gaussianElimination(matrix) else { return nil }
        return ascending.reversed()
    }

    private static func gaussianElimination(_ input: [[Double]]) -> [Double]? {
        var matrix = input
        let rowCount = matrix.count
        let columnCount = rowCount + 1

        for pivot in 0..<rowCount {
            var bestRow = pivot
            for row in pivot..<rowCount where abs(matrix[row][pivot]) > abs(matrix[bestRow][pivot]) {
                bestRow = row
            }
            guard abs(matrix[bestRow][pivot]) > 1e-12 else { return nil }
            if bestRow != pivot {
                matrix.swapAt(bestRow, pivot)
            }

            let divisor = matrix[pivot][pivot]
            for column in pivot..<columnCount {
                matrix[pivot][column] /= divisor
            }

            for row in 0..<rowCount where row != pivot {
                let factor = matrix[row][pivot]
                guard factor != 0 else { continue }
                for column in pivot..<columnCount {
                    matrix[row][column] -= factor * matrix[pivot][column]
                }
            }
        }

        return matrix.map { $0[columnCount - 1] }
    }

    private static func coefficientOfDetermination(
        coefficients: [Double],
        xValues: [Double],
        yValues: [Double]
    ) -> Double? {
        guard !yValues.isEmpty else { return nil }
        let mean = yValues.reduce(0, +) / Double(yValues.count)
        let total = yValues.reduce(0) { $0 + pow($1 - mean, 2) }
        guard total > 0 else { return nil }
        let residual = zip(xValues, yValues).reduce(0) { partial, pair in
            partial + pow(pair.1 - evaluatePolynomial(coefficients: coefficients, x: pair.0), 2)
        }
        return max(0, min(1, 1 - residual / total))
    }

    private static func evaluatePolynomial(coefficients: [Double], x: Double) -> Double {
        coefficients.reduce(0) { $0 * x + $1 }
    }
}
