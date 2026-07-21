//
//  WidgetScratchpad.swift
//  WidgetEngine
//
//  Temporary local scratchpad for testing AI-generated MathBoard Widget JSON.
//  Paste only the widget JSON between the raw string delimiters below.
//

import Foundation
import SwiftUI

enum WidgetScratchpad {
    static let widgetJSON = #"""
{
  "schemaVersion": 1,
  "widgetId": "order-ops-notation-level-1",
  "activity": "multipleChoice",
  "title": "First Move",
  "description": "Recognize multiplication and division written in different forms before adding or subtracting.",
  "learningObjective": "Students identify the first operation in expressions such as a + bc, bc + a, a + b/c, and b/c + a.",
  "difficulty": "easy",
  "presentation": {
    "preferredTheme": "paperArcade",
    "preferredExperience": "arcadeChoiceChallenge"
  },
  "rules": {
    "scoreMode": "correctOutOfAttempted",
    "advanceMode": "manual",
    "allowRetry": true,
    "shuffleQuestions": false,
    "shuffleChoices": false,
    "maxAttemptsPerQuestion": 2,
    "calculatorAllowed": false
  },
  "feedback": {
    "defaultCorrect": "Correct. You found the operation that must happen first.",
    "defaultIncorrect": "Not yet. Look for multiplication or division before addition or subtraction.",
    "defaultEncouragement": "Try again. The notation may look different, but the order of operations has not changed."
  },
  "questions": [
    {
      "id": "a",
      "prompt": "What is the first step?",
      "expression": "3 + 4(5)",
      "choices": [
        { "id": "a", "label": "Add 3 and 4", "isCorrect": false },
        { "id": "b", "label": "Multiply 4 and 5", "isCorrect": true },
        { "id": "c", "label": "Add 3 and 5", "isCorrect": false },
        { "id": "d", "label": "Subtract 4 from 5", "isCorrect": false }
      ],
      "hints": [
        "A number next to parentheses means multiplication.",
        "Multiplication happens before addition."
      ],
      "correctFeedback": "Yes. 4(5) means 4 times 5, so multiply before adding 3.",
      "incorrectFeedback": "Not yet. The parentheses show multiplication, and multiplication comes before addition."
    },
    {
      "id": "b",
      "prompt": "After the first step, what does the expression become?",
      "expression": "6(2) + 9",
      "choices": [
        { "id": "a", "label": "12 + 9", "isCorrect": true },
        { "id": "b", "label": "6 + 11", "isCorrect": false },
        { "id": "c", "label": "8 + 9", "isCorrect": false },
        { "id": "d", "label": "6(11)", "isCorrect": false }
      ],
      "hints": [
        "Do the multiplication part first.",
        "6(2) equals 12."
      ],
      "correctFeedback": "Correct. The multiplication 6(2) becomes 12, leaving 12 + 9.",
      "incorrectFeedback": "Check only the multiplication first. Do not add 9 yet."
    },
    {
      "id": "c",
      "prompt": "What is the first step?",
      "expression": "8 + (3)(4)",
      "choices": [
        { "id": "a", "label": "Add 8 and 3", "isCorrect": false },
        { "id": "b", "label": "Multiply 3 and 4", "isCorrect": true },
        { "id": "c", "label": "Add 8 and 4", "isCorrect": false },
        { "id": "d", "label": "Multiply 8 and 3", "isCorrect": false }
      ],
      "hints": [
        "Parentheses around both factors still mean multiplication.",
        "(3)(4) is the multiplication part."
      ],
      "correctFeedback": "Right. (3)(4) means 3 times 4.",
      "incorrectFeedback": "Look again at the two parenthesis groups. They are factors being multiplied."
    },
    {
      "id": "d",
      "prompt": "After the first step, what does the expression become?",
      "expression": "9 + \\frac{12}{3}",
      "choices": [
        { "id": "a", "label": "\\frac{21}{3}", "isCorrect": false },
        { "id": "b", "label": "9 + 4", "isCorrect": true },
        { "id": "c", "label": "12", "isCorrect": false },
        { "id": "d", "label": "3 + 3", "isCorrect": false }
      ],
      "hints": [
        "Division happens before addition.",
        "12 / 3 equals 4."
      ],
      "correctFeedback": "Exactly. Divide 12 by 3 first, so the expression becomes 9 + 4.",
      "incorrectFeedback": "Do the division before adding 9."
    },
    {
      "id": "e",
      "prompt": "What is the first step?",
      "expression": "\\frac{10}{2} + 6",
      "choices": [
        { "id": "a", "label": "Add 2 and 6", "isCorrect": false },
        { "id": "b", "label": "Divide 10 by 2", "isCorrect": true },
        { "id": "c", "label": "Add 10 and 6", "isCorrect": false },
        { "id": "d", "label": "Divide 2 by 6", "isCorrect": false }
      ],
      "hints": [
        "The slash is a division sign.",
        "Division comes before addition."
      ],
      "correctFeedback": "Yes. The slash means divide 10 by 2 first.",
      "incorrectFeedback": "The slash is the key. It tells you there is division to do before addition."
    },
    {
      "id": "f",
      "prompt": "After the first step, what does the expression become?",
      "expression": "4 \\cdot 3 - 5",
      "choices": [
        { "id": "a", "label": "12 - 5", "isCorrect": true },
        { "id": "b", "label": "4 \\cdot -2", "isCorrect": false },
        { "id": "c", "label": "7 - 5", "isCorrect": false },
        { "id": "d", "label": "4 - 15", "isCorrect": false }
      ],
      "hints": [
        "The star symbol is being used for multiplication.",
        "4 * 3 equals 12."
      ],
      "correctFeedback": "Correct. Multiply 4 and 3 first, leaving 12 - 5.",
      "incorrectFeedback": "The star symbol means multiplication, and multiplication happens before subtraction."
    }
  ]
}
"""#
}

#Preview("Widget Scratchpad") {
    WidgetActivityValidationView(source: WidgetScratchpad.widgetJSON)
        .padding()
}
