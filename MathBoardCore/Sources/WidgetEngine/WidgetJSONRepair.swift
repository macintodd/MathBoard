//
//  WidgetJSONRepair.swift
//  WidgetEngine
//
//  Small tolerance layer for AI-authored widget JSON.
//

import Foundation

enum WidgetJSONRepair {
    private static let latexCommands: Set<String> = [
        "cdot", "frac", "sqrt", "pi", "theta", "alpha", "beta",
        "left", "right", "times", "div", "pm", "le", "ge", "neq",
        "lt", "gt", "sin", "cos", "tan", "log", "ln"
    ]

    static func escapingUnescapedLaTeXCommands(in source: String) -> String {
        let characters = Array(source)
        var repaired = ""
        repaired.reserveCapacity(source.count)

        var isInsideString = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                repaired.append(character)
                isInsideString.toggle()
                index += 1
                continue
            }

            if isInsideString, character == "\\", index + 1 < characters.count {
                let nextIndex = index + 1
                let nextCharacter = characters[nextIndex]

                if nextCharacter == "\\" {
                    repaired.append(character)
                    repaired.append(nextCharacter)
                    index += 2
                    continue
                }

                if nextCharacter.isLetter {
                    var commandEnd = nextIndex
                    while commandEnd < characters.count, characters[commandEnd].isLetter {
                        commandEnd += 1
                    }

                    let command = String(characters[nextIndex..<commandEnd])
                    if latexCommands.contains(command) {
                        repaired.append("\\\\")
                        repaired.append(command)
                        index = commandEnd
                        continue
                    }
                }

                if nextCharacter == "\"" || nextCharacter == "/" || nextCharacter == "b" || nextCharacter == "f" || nextCharacter == "n" || nextCharacter == "r" || nextCharacter == "t" {
                    repaired.append(character)
                    repaired.append(nextCharacter)
                    index += 2
                    continue
                }
            }

            repaired.append(character)
            index += 1
        }

        return repaired
    }
}
