//
//  WidgetSamples.swift
//  WidgetEngine
//
//  Bundled prompts and sample MathBoard Widget JSON documents used by previews
//  and the standalone editor.
//

import Foundation

enum WidgetSamples {
    static let activityAuthoringInstructions = """
    You are creating a MathBoard Activity Widget.

    Return only valid JSON. Do not include Markdown, comments, prose, or a code fence.

    Create activity JSON, not low-level UI layout JSON. MathBoard owns the native SwiftUI presentation, spacing, colors, typography, animations, and button layout. Your job is to create strong educational content.

    Required top-level shape:
    {
      "schemaVersion": 1,
      "widgetId": "short-stable-id",
      "activity": "multipleChoice",
      "title": "Widget title",
      "description": "Short teacher-facing description",
      "learningObjective": "What students will practice",
      "difficulty": "easy" | "medium" | "hard",
      "presentation": {
        "preferredTheme": "cleanClassroom" | "neonMath" | "paperArcade" | "chalkboard" | "sportsCourt",
        "preferredExperience": "arcadeChoiceChallenge" | "paperQuiz" | "sportsArena" | "mysteryReveal" | "bossBattle"
      },
      "rules": {
        "scoreMode": "correctOutOfAttempted" | "correctOutOfTotal" | "streak",
        "advanceMode": "manual",
        "allowRetry": true,
        "shuffleQuestions": false,
        "shuffleChoices": false,
        "maxAttemptsPerQuestion": 2,
        "calculatorAllowed": false
      },
      "feedback": {
        "defaultCorrect": "Default success message",
        "defaultIncorrect": "Default correction message",
        "defaultEncouragement": "Default encouragement"
      },
      "questions": []
    }

    Currently supported activity:
    - multipleChoice: Use for four-choice or small-choice practice, first-step questions, vocabulary checks, expression interpretation, identifying equivalent forms, and simple review.

    Multiple-choice flow:
    - Always set "advanceMode": "manual".
    - After Check, the widget should show correct or incorrect feedback, update score/progress, and wait for the student to press Next.
    - Do not use "automaticOnCorrect" or "automaticAfterAnswer" for MathBoard lesson widgets.

    Text color:
    - All instructional, question, answer, label, hint, feedback, and math text should be black.
    - Do not request colored text in generated content. MathBoard may still use native button states, borders, meters, icons, and feedback highlights for interaction.

    Multiple-choice question shape:
    {
      "id": "q1",
      "prompt": "What should the student decide?",
      "expression": "Optional math expression shown prominently, written as LaTeX",
      "choices": [
        { "id": "a", "label": "Choice text", "isCorrect": false },
        { "id": "b", "label": "Choice text", "isCorrect": true }
      ],
      "hints": ["Hint 1", "Hint 2"],
      "correctFeedback": "Specific explanation for the correct answer.",
      "incorrectFeedback": "Specific encouragement or correction.",
      "explanation": "Optional full explanation.",
      "difficulty": "easy",
      "skillTag": "optional-skill-tag"
    }

    Math formatting:
    - Write prominent question expressions and math-only choice labels as LaTeX.
    - Escape LaTeX backslashes because this is JSON: use "\\frac{12}{3}", "\\sqrt{49}", "\\cdot", and "x^2".
    - Prefer LaTeX notation over calculator notation: use "\\cdot" for explicit multiplication, "\\frac{a}{b}" for fractions, ordinary parentheses for grouped factors, and "^" for exponents.
    - Do not wrap the expression in Markdown. Optional math delimiters "$...$", "\\(...\\)", or "$$...$$" are accepted, but raw LaTeX in the expression field is preferred.

    Answer accuracy requirements:
    - Before returning JSON, privately solve every generated question from scratch.
    - Verify that the choice marked "isCorrect": true exactly matches the computed answer or mathematically correct concept.
    - Verify that every incorrect choice is actually incorrect and that there is exactly one correct choice.
    - For arithmetic, order-of-operations, fractions, exponents, equation solving, graph identification, and equivalent-expression questions, re-check the final answer using a second method before marking it correct.
    - Put the correct reasoning in "correctFeedback" or "explanation" so a teacher can audit the answer from the preview.
    - If you are unsure about any answer, replace that question with one you can verify confidently.

    Validation rules:
    - title and learningObjective must be non-empty.
    - questions must contain at least one question.
    - each question must have a prompt or expression.
    - each question must have 2-6 choices.
    - each question must have exactly one correct choice.
    - every choice needs a non-empty id and label.

    Calculator policy:
    - Set "calculatorAllowed": false when the activity is meant to assess mental arithmetic, operation sense, factoring fluency, basic equation steps, or calculator-free reasoning.
    - Set "calculatorAllowed": true when calculator use supports the learning goal, such as graph exploration, messy decimal arithmetic, regression, statistics, or numerical investigation.

    Do not invent unsupported activities, themes, experiences, keys, or UI components.
    Make distractors plausible and educationally useful. Include hints and feedback that help students recover without shaming them.
    """

    static let orderOpsActivityJSON = #"""
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

    static let aiInstructions = """
    You are creating a MathBoard Widget.

    Return only valid JSON. Do not include Markdown, comments, prose, or a code fence.

    The JSON must follow this schema:
    {
      "schemaVersion": 1,
      "widgetId": "short-stable-id",
      "title": "Widget title",
      "description": "Short teacher-facing description",
      "learningObjective": "What students will practice",
      "analytics": { "enabled": false },
      "presentation": {
        "preferredWidth": 520,
        "preferredHeight": 720,
        "scroll": "enabled"
      },
      "initialState": {
        "score": 0,
        "target": 24,
        "answer": ""
      },
      "body": { "type": "stack", "axis": "vertical", "children": [] }
    }

    Component types:
    - stack: { "type": "stack", "axis": "vertical" | "horizontal", "spacing": 12, "children": [...] }
    - grid: { "type": "grid", "columns": 2, "spacing": 10, "children": [...] }
    - text: { "type": "text", "role": "title" | "subtitle" | "body" | "caption" | "math", "text": "Use {{stateKey}} to show state" }
    - formula: { "type": "formula", "label": "Equation", "template": "y = {{a}}x + {{b}}", "result": { "kind": "state", "stateKey": "y" }, "displayMode": "formulaOnly" | "valueOnly" | "formulaAndValue" }
    - mathTemplate: { "type": "mathTemplate", "fontScale": "compact" | "regular" | "large", "spacing": 6, "parts": [...] }
    - numberInput: { "type": "numberInput", "label": "Answer", "stateKey": "answer", "placeholder": "?" }
    - mathBox: { "type": "mathBox", "label": "Expression", "stateKey": "expressionAnswer", "placeholder": "", "maxLength": 24, "clearOnSelect": true }
    - numberBox: { "type": "numberBox", "label": "Answer", "stateKey": "answer", "placeholder": "", "shape": "circle" | "square" | "roundedSquare", "maxLength": 2, "clearOnSelect": true }
    - digitPad: { "type": "digitPad", "digits": [0,1,2,3,4,5,6,7,8,9], "shape": "circle" | "square" | "roundedSquare" }
    - mathPad: { "type": "mathPad", "preset": "numeric" | "integer" | "operations" | "algebra" | "calculator", "extraKeys": ["a"], "shape": "circle" | "square" | "roundedSquare" }
    - valueStepper: { "type": "valueStepper", "label": "h", "stateKey": "h", "min": -10, "max": 10, "step": 1 }
    - valueSlider: { "type": "valueSlider", "label": "a", "stateKey": "a", "min": -5, "max": 5, "step": 1 }
    - choiceGroup: { "type": "choiceGroup", "label": "Choose a move", "stateKey": "selectedMove", "style": "tiles" | "pills" | "buttons", "choices": [{ "label": "Add 5", "value": "add5" }] }
    - goalMeter: { "type": "goalMeter", "label": "Progress", "stateKey": "score", "goalValue": 5, "style": "bar" | "radial" }
    - hintProvider: { "type": "hintProvider", "title": "Need a hint?", "stateKey": "hintLevel", "hints": ["First hint", "Second hint"] }
    - symbolCollection: { "type": "symbolCollection", "symbol": "star" | "basketball" | "target" | "coin" | "numberTile" | "trophy" | "rocket" | "checkmark", "countStateKey": "stars", "maxCount": 5, "style": "row" | "wrap" }
    - graphic: { "type": "graphic", "width": 320, "height": 180, "decoration": { "fill": "#F8FAFC", "borderColor": "#2563EB", "borderWidth": 2, "cornerRadius": 12, "padding": 8 }, "elements": [...] }
    - nativeGraph: { "type": "nativeGraph", "width": 320, "height": 220, "xMin": -10, "xMax": 10, "yMin": -10, "yMax": 10, "elements": [...] }
    - questionSet: { "type": "questionSet", "mode": "sequential" | "random", "currentIndexStateKey": "currentQuestionIndex", "completedCountStateKey": "completed", "questions": [{ "id": "q1", "title": "Question 1", "body": { ... } }] }
    - button: { "type": "button", "title": "Check", "style": "primary" | "secondary" | "destructive", "actions": [...] }
    - feedback: { "type": "feedback" }
    - score: { "type": "score", "label": "Score", "stateKey": "score" }
    - divider: { "type": "divider" }

    Math formatting:
    - Use LaTeX for math display strings wherever a component shows math.
    - Escape LaTeX backslashes because this is JSON: use "\\\\frac{12}{3}", "\\\\sqrt{49}", "\\\\cdot", and "x^2".
    - Prefer LaTeX notation over calculator notation: use "\\\\cdot" for explicit multiplication, "\\\\frac{a}{b}" for fractions, ordinary parentheses for grouped factors, and "^" for exponents.
    - Do not include Markdown code fences or Markdown math blocks in JSON fields.

    Text color:
    - All instructional, question, answer, label, hint, feedback, and math text should be black.
    - Do not request colored text in generated content. Use color only for non-text graphics, borders, meters, icons, and feedback-state decoration when it helps the activity.

    Answer accuracy requirements:
    - Before returning JSON, privately solve every generated question from scratch.
    - Verify that any answer, target value, condition, or correct choice exactly matches the computed answer or mathematically correct concept.
    - Verify that every distractor or incorrect condition is actually incorrect.
    - For arithmetic, order-of-operations, fractions, exponents, equation solving, graph identification, and equivalent-expression questions, re-check the final answer using a second method before wiring correctness.
    - Put the correct reasoning in visible feedback, explanation text, or teacher-auditable content so mistakes can be spotted in preview.
    - If you are unsure about any answer, replace that item with one you can verify confidently.

    Presentation metadata:
    - preferredWidth: initial widget width. Use 420-560 for most widgets.
    - preferredHeight: initial widget height. Use 560-760 for ordinary practice, 760-1000 for taller widgets with digit pads, graphs, hints, or many controls.
    - scroll: "enabled" or "disabled". Use "enabled" unless the widget is very compact and guaranteed to fit.

    Example:
    {
      "presentation": {
        "preferredWidth": 540,
        "preferredHeight": 820,
        "scroll": "enabled"
      }
    }

    Stack and grid can include optional decoration:
    { "fill": "#FFFFFF", "borderColor": "#CBD5E1", "borderWidth": 1, "cornerRadius": 12, "padding": 10 }

    Use formula to display math formulas or computed values from WidgetExpression. Use template for the symbolic formula with {{stateKey}} interpolation. Use result for an evaluated WidgetExpression. Use displayMode "formulaOnly" to show only the symbolic formula, "valueOnly" to show only the evaluated result, or "formulaAndValue" to show formula = result. This is for display; use checkAnswer or conditions for correctness.

    Example formula:
    {
      "type": "formula",
      "label": "Current equation",
      "template": "y = {{a}}x + {{b}}",
      "result": {
        "kind": "binary",
        "operator": "add",
        "left": {
          "kind": "binary",
          "operator": "multiply",
          "left": { "kind": "state", "stateKey": "a" },
          "right": { "kind": "state", "stateKey": "x" }
        },
        "right": { "kind": "state", "stateKey": "b" }
      },
      "displayMode": "formulaAndValue"
    }

    Math template parts:
    - text: { "type": "text", "text": "(" }
    - numberBox: { "type": "numberBox", "stateKey": "answer", "placeholder": "", "maxLength": 2, "clearOnSelect": true }

    Use mathTemplate for algebraic answer entry layouts such as factoring, equations, expressions with parentheses, variables, exponents, operators, fractions written inline, or answer blanks inside math. Do not build algebraic answer rows by placing separate text and numberBox components in a horizontal stack. mathTemplate keeps parentheses, variables, operators, and number boxes visually aligned and similarly sized.

    Example mathTemplate for factoring:
    {
      "type": "mathTemplate",
      "fontScale": "large",
      "spacing": 6,
      "parts": [
        { "type": "text", "text": "(" },
        { "type": "numberBox", "stateKey": "gcf", "placeholder": "", "maxLength": 2, "clearOnSelect": true },
        { "type": "text", "text": ")(" },
        { "type": "numberBox", "stateKey": "firstTerm", "placeholder": "", "maxLength": 2, "clearOnSelect": true },
        { "type": "text", "text": "x + " },
        { "type": "numberBox", "stateKey": "secondTerm", "placeholder": "", "maxLength": 2, "clearOnSelect": true },
        { "type": "text", "text": ")" }
      ]
    }

    Graphic elements:
    - line: { "type": "line", "x1": 0.1, "y1": 0.8, "x2": 0.9, "y2": 0.2, "strokeColor": "#2563EB", "strokeWidth": 3 }
    - arrow: { "type": "arrow", "x1": 0.1, "y1": 0.8, "x2": 0.9, "y2": 0.2, "strokeColor": "#2563EB", "strokeWidth": 3 }
    - point: { "type": "point", "x": 0.5, "y": 0.5, "fillColor": "#F97316", "size": 12 }
    - label: { "type": "label", "x": 0.5, "y": 0.1, "text": "Label" }
    - parabola: { "type": "parabola", "a": 1, "h": 0, "k": 0, "strokeColor": "#F97316", "strokeWidth": 3 }
    - absoluteValue: { "type": "absoluteValue", "a": 1, "h": 0, "k": 0, "strokeColor": "#9333EA", "strokeWidth": 3 }
    - symbol: { "type": "symbol", "symbol": "basketball", "x": 0.7, "y": 0.3, "size": 34 }

    Native graph elements:
    - line: { "type": "line", "slope": 1, "intercept": 0, "color": "#2563EB", "width": 3 }
    - parabola: { "type": "parabola", "a": 1, "h": 0, "k": 0, "color": "#F97316", "width": 3 }
    - absoluteValue: { "type": "absoluteValue", "a": 1, "h": 0, "k": 0, "color": "#9333EA", "width": 3 }
    - point: { "type": "point", "x": 0, "y": 0, "label": "vertex", "color": "#DC2626" }

    Expression forms:
    - literal values: 4, "hello", true
    - state value: { "kind": "state", "stateKey": "answer" }
    - random integer: { "kind": "randomInt", "min": 2, "max": 12 }
    - random choice: { "kind": "randomChoice", "values": [1, 2, 3] }
    - unary math/logic: { "kind": "unary", "operator": "abs" | "sqrt" | "sin" | "cos" | "tan" | "not", "value": ... }
    - binary math: { "kind": "binary", "operator": "add" | "subtract" | "multiply" | "divide" | "modulo" | "power" | "min" | "max", "left": ..., "right": ... }
    - logical: { "kind": "logical", "operator": "and" | "or", "values": [...] }
    - comparison: { "kind": "comparison", "condition": { "left": ..., "relation": "equals", "right": ... } }
    - ternary: { "kind": "ternary", "condition": { "left": ..., "relation": "equals", "right": ... }, "trueValue": ..., "falseValue": ... }

    Action types:
    - set: { "action": "set", "stateKey": "target", "value": ... }
    - increment: { "action": "increment", "stateKey": "score", "by": 1 }
    - showFeedback: { "action": "showFeedback", "message": "Correct!", "style": "success" }
    - clearFeedback: { "action": "clearFeedback" }
    - playAnimation: { "action": "playAnimation", "target": "optionalTargetId", "animation": "pulse" | "shake" | "fall" | "successHighlight" | "fadeDim" }
    - recordAttempt: { "action": "recordAttempt", "questionId": "optional-id", "answerStateKeys": ["answer"], "correct": true }
    - checkAnswer: { "action": "checkAnswer", "check": { "answer": { "kind": "state", "stateKey": "answer" }, "accepted": [12], "tolerance": 0, "caseSensitive": false, "success": [...], "failure": [...] } }
    - nextQuestion: { "action": "nextQuestion", "stateKey": "currentQuestionIndex", "count": 5, "mode": "sequential" | "random" }
    - previousQuestion: { "action": "previousQuestion", "stateKey": "currentQuestionIndex", "count": 5 }
    - jumpToQuestion: { "action": "jumpToQuestion", "stateKey": "currentQuestionIndex", "index": 0 }
    - reset: { "action": "reset" }
    - if: {
        "action": "if",
        "condition": { "left": ..., "relation": "equals", "right": ... },
        "then": [...],
        "else": [...]
      }

    Supported condition relations:
    equals, notEquals, greaterThan, lessThan, greaterThanOrEquals, lessThanOrEquals.

    Use questionSet for multi-question practice, simple lesson flows, card stacks, or page-like widgets. Put currentQuestionIndex in initialState. Use nextQuestion, previousQuestion, or jumpToQuestion actions for navigation. Use mode "random" when the nextQuestion action should choose a random question.

    Use checkAnswer when a widget needs multiple accepted answers, numeric tolerance, or consistent success/failure action blocks. For exact text answers, set caseSensitive false unless capitalization matters.

    For playful numeric touch input, prefer numberBox plus digitPad instead of numberInput. A numberBox is selected by touch. If clearOnSelect is true, tapping it clears its current value. Tapping a digitPad digit appends that digit to the selected numberBox up to maxLength. Every numberBox stateKey must exist in initialState. For mathTemplate numberBox parts, the same selection and digitPad behavior applies.

    For variables, operators, signed integers, or full expression entry, use mathBox plus mathPad. A mathBox is selected by touch and stores text such as "x", "-3", "2x+5", "(x+4)", or "x^2". mathPad inserts keys into the selected mathBox or numberBox. Use preset "numeric" for digits only, "integer" for digits plus a minus sign, "operations" for + - * / ^ = and parentheses, "algebra" for common variables and operations, and "calculator" for a broader expression keypad. Use extraKeys only for a few specific variables or symbols needed by the task. Do not hand-build keypads with many individual button components unless the keypad must do something mathPad cannot do.

    Example expression entry:
    {
      "type": "stack",
      "axis": "vertical",
      "spacing": 10,
      "children": [
        { "type": "mathBox", "label": "Your expression", "stateKey": "answerExpression", "placeholder": "2x+5", "maxLength": 24, "clearOnSelect": true },
        { "type": "mathPad", "preset": "algebra", "extraKeys": ["m"], "shape": "roundedSquare" }
      ]
    }

    Make widgets visually engaging by default. Use decoration, goalMeter, symbolCollection, hints, choiceGroup, nativeGraph, and graphic elements when helpful. Use only built-in symbols and native graphics. Do not use remote images, URLs, HTML, CSS, JavaScript, SVG, or arbitrary code.

    Choose presentation.preferredHeight large enough that important controls are not cut off. If the widget includes a digitPad, hints, graph, or goal area, usually use preferredHeight 760 or more and scroll "enabled".

    Button styles and feedback styles are different. Button styles are primary, secondary, destructive. Feedback styles are neutral, success, warning, error. Never use destructive as a showFeedback style.

    Make the widget classroom-friendly, concise, and usable inside a resizable whiteboard object.
    """

    static let logicPassInstructions = """
    You are doing the LOGIC PASS for a MathBoard Widget.

    Return only valid JSON. Do not include Markdown, comments, prose, or a code fence.

    Goal: create or improve the educational logic of one complete MathBoard Widget JSON document. Focus on correctness, state, questions, answer checking, feedback, score, hints, randomization, and learning objective. Keep layout simple. Do not spend effort on decorative styling.

    Top-level required structure:
    {
      "schemaVersion": 1,
      "widgetId": "short-stable-id",
      "title": "Widget title",
      "description": "Short teacher-facing description",
      "learningObjective": "What students will practice",
      "analytics": { "enabled": false },
      "presentation": { "preferredWidth": 520, "preferredHeight": 760, "scroll": "enabled" },
      "initialState": {},
      "body": { "type": "stack", "axis": "vertical", "spacing": 12, "children": [] }
    }

    Logic-focused components:
    - text: { "type": "text", "role": "title" | "subtitle" | "body" | "caption" | "math", "text": "Use {{stateKey}} to show state" }
    - formula: { "type": "formula", "label": "Equation", "template": "y = {{a}}x + {{b}}", "result": { "kind": "state", "stateKey": "y" }, "displayMode": "formulaOnly" | "valueOnly" | "formulaAndValue" }
    - numberInput: { "type": "numberInput", "label": "Answer", "stateKey": "answer", "placeholder": "?" }
    - numberBox: { "type": "numberBox", "label": "Answer", "stateKey": "answer", "placeholder": "", "shape": "roundedSquare", "maxLength": 2, "clearOnSelect": true }
    - mathBox: { "type": "mathBox", "label": "Expression", "stateKey": "expressionAnswer", "placeholder": "2x+5", "maxLength": 24, "clearOnSelect": true }
    - choiceGroup: { "type": "choiceGroup", "label": "Choose", "stateKey": "choice", "style": "tiles", "choices": [{ "label": "A", "value": "a" }] }
    - hintProvider: { "type": "hintProvider", "title": "Need a hint?", "stateKey": "hintLevel", "hints": ["First hint", "Second hint"] }
    - questionSet: { "type": "questionSet", "mode": "sequential" | "random", "currentIndexStateKey": "currentQuestionIndex", "completedCountStateKey": "completed", "questions": [{ "id": "q1", "title": "Question 1", "body": { ... } }] }
    - button: { "type": "button", "title": "Check", "style": "primary" | "secondary" | "destructive", "actions": [] }
    - feedback: { "type": "feedback" }
    - score: { "type": "score", "label": "Score", "stateKey": "score" }

    Expression kinds:
    - state: { "kind": "state", "stateKey": "answer" }
    - randomInt: { "kind": "randomInt", "min": 2, "max": 12 }
    - randomChoice: { "kind": "randomChoice", "values": [1, 2, 3] }
    - unary: { "kind": "unary", "operator": "abs" | "sqrt" | "sin" | "cos" | "tan" | "not", "value": ... }
    - binary: { "kind": "binary", "operator": "add" | "subtract" | "multiply" | "divide" | "modulo" | "power" | "min" | "max", "left": ..., "right": ... }
    - logical: { "kind": "logical", "operator": "and" | "or", "values": [...] }
    - comparison: { "kind": "comparison", "condition": { "left": ..., "relation": "equals", "right": ... } }
    - ternary: { "kind": "ternary", "condition": { "left": ..., "relation": "equals", "right": ... }, "trueValue": ..., "falseValue": ... }

    Action types:
    - set, increment, showFeedback, clearFeedback, playAnimation, recordAttempt, checkAnswer, nextQuestion, previousQuestion, jumpToQuestion, if, reset.
    - Use checkAnswer for multiple accepted answers, numeric tolerance, and success/failure action blocks.
    - Feedback styles are neutral, success, warning, error. Do not use destructive as a feedback style.

    Rules:
    - Return a complete widget document, not a partial component.
    - Every stateKey used by inputs, hints, score, progress, or checks must exist in initialState.
    - Reward success and encourage mistakes with useful feedback.
    - Do not invent unsupported components, actions, or style names.
    - Keep decoration minimal in this pass.
    """

    static let layoutPassInstructions = """
    You are doing the LAYOUT PASS for a MathBoard Widget.

    You will receive an existing complete MathBoard Widget JSON document. Return only the complete updated JSON. Do not include Markdown, comments, prose, or a code fence.

    Goal: improve structure, readability, sizing, and placement without changing the educational logic unless a layout issue reveals an obvious bug.

    Layout components:
    - stack: { "type": "stack", "axis": "vertical" | "horizontal", "spacing": 12, "children": [...] }
    - grid: { "type": "grid", "columns": 2, "spacing": 10, "children": [...] }
    - divider: { "type": "divider" }
    - text: use roles title, subtitle, body, caption, math.
    - formula: use for displayed equations and computed expression values.
    - mathTemplate: use for formatted algebraic answer rows with blanks.
    - nativeGraph and graphic: place where students can see them without crowding inputs.

    Presentation rules:
    - Use presentation.preferredWidth 420-560 for most widgets.
    - Use presentation.preferredHeight 560-760 for compact widgets.
    - Use presentation.preferredHeight 760-1000 for widgets with keypads, graphs, hints, question sets, or several controls.
    - Use scroll: "enabled" unless the widget is guaranteed compact.
    - Make sure buttons and keypads are not cut off.

    Input placement rules:
    - Put numberBox/digitPad or mathBox/mathPad near the question they answer.
    - Use mathTemplate instead of manually lining up text and number boxes in a horizontal stack for algebraic answers.
    - Avoid placing too many controls in one row.

    Rules:
    - Return the complete updated widget JSON.
    - Preserve valid existing state keys and answer logic.
    - Do not remove checkAnswer, if actions, hints, score, or feedback unless they are duplicated or broken.
    - Do not add decorative polish beyond simple grouping unless asked.
    - Do not invent unsupported layout fields such as visibleIf, absolutePosition, or tabs.
    """

    static let interactionPassInstructions = """
    You are doing the INTERACTION PASS for a MathBoard Widget.

    You will receive an existing complete MathBoard Widget JSON document. Return only the complete updated JSON. Do not include Markdown, comments, prose, or a code fence.

    Goal: improve how students interact with the widget. Preserve the learning objective and answer logic.

    Interaction components:
    - numberInput: plain typed numeric input.
    - numberBox + digitPad: playful touch-based numeric entry.
    - mathBox + mathPad: variables, operators, signed numbers, parentheses, or expression entry.
    - choiceGroup: selectable tiles/pills/buttons.
    - valueStepper: arrow increment controls for values like a, h, k, slope, intercept.
    - valueSlider: smooth numeric exploration.
    - hintProvider: progressive hints using hintLevel.
    - questionSet plus nextQuestion/previousQuestion/jumpToQuestion for multi-question flow.
    - button actions should run checkAnswer, showFeedback, increment score/streak, move questions, or reset.

    Keypad rules:
    - Use digitPad only for digits.
    - Use mathPad preset numeric, integer, operations, algebra, or calculator.
    - Do not hand-build a keypad with many individual buttons unless mathPad cannot do it.

    Feedback rules:
    - Correct answers should show success feedback and optionally increment score, streak, stars, or completed.
    - Incorrect answers should show specific encouragement and suggest a next step.
    - Use hintProvider for help instead of dumping all hints at once.

    Rules:
    - Return the complete updated widget JSON.
    - Every stateKey used by a new interaction must be present in initialState.
    - Do not change the core math unless needed to fix an interaction bug.
    - Do not invent unsupported gestures such as drag, drop, tapGraph, or draw.
    """

    static let decorationPassInstructions = """
    You are doing the DECORATION AND POLISH PASS for a MathBoard Widget.

    You will receive an existing complete MathBoard Widget JSON document. Return only the complete updated JSON. Do not include Markdown, comments, prose, or a code fence.

    Goal: make the widget visually clear, classroom-friendly, and a little playful while preserving all educational logic and interactions.

    Decoration tools:
    - stack/grid decoration: fill, borderColor, borderWidth, cornerRadius, padding.
    - goalMeter: visual progress using bar or radial.
    - symbolCollection: built-in rewards like star, basketball, target, coin, numberTile, trophy, rocket, checkmark.
    - graphic: simple built-in drawings with line, arrow, point, label, parabola, absoluteValue, symbol.
    - nativeGraph: coordinate-plane visuals with line, parabola, absoluteValue, point.
    - formula/text roles: make headings, formulas, and instructions easy to scan.
    - playAnimation/showFeedback animation values: pulse, shake, fall, successHighlight, fadeDim.

    Style rules:
    - Use a restrained palette with readable contrast.
    - Use decoration to group related controls, not to create clutter.
    - Add rewards when they reinforce success.
    - Keep high school Algebra 2 widgets mature enough for classroom use.
    - Do not use remote images, URLs, HTML, CSS, JavaScript, SVG, or arbitrary code.

    Built-in symbol values:
    star, basketball, target, coin, numberTile, trophy, rocket, checkmark.

    Rules:
    - Return the complete updated widget JSON.
    - Do not change answer logic, accepted answers, question content, or state meaning.
    - Do not invent unsupported decorative assets, mascots, media, or style fields.
    - Make sure presentation.preferredHeight is large enough and scroll is enabled if needed.
    """

    static let factorPairsDocument = MathBoardWidgetDocument(
        title: "Factor Pair Sprint",
        description: "Students find two factors that multiply to the target number.",
        initialState: [
            "target": .number(24),
            "factorA": .string(""),
            "factorB": .string(""),
            "score": .number(0)
        ],
        body: .stack(WidgetStack(
            axis: .vertical,
            spacing: 14,
            children: [
                .text(WidgetText(id: nil, text: "Target", role: .caption)),
                .text(WidgetText(id: nil, text: "{{target}}", role: .math)),
                .score(WidgetScore(label: "Score", stateKey: "score")),
                .stack(WidgetStack(
                    axis: .horizontal,
                    spacing: 10,
                    children: [
                        .numberInput(WidgetNumberInput(id: nil, label: "Factor A", stateKey: "factorA", placeholder: "A")),
                        .text(WidgetText(id: nil, text: "x", role: .subtitle)),
                        .numberInput(WidgetNumberInput(id: nil, label: "Factor B", stateKey: "factorB", placeholder: "B"))
                    ]
                )),
                .button(WidgetButton(
                    id: nil,
                    title: "Check Pair",
                    style: .primary,
                    actions: [
                        .if(
                            condition: WidgetCondition(
                                left: .binary(
                                    operator: .multiply,
                                    left: .state("factorA"),
                                    right: .state("factorB")
                                ),
                                relation: .equals,
                                right: .state("target")
                            ),
                            then: [
                                .increment(stateKey: "score", by: .value(.number(1))),
                                .showFeedback(message: "Correct: {{factorA}} x {{factorB}} = {{target}}", style: .success, animation: .pulse)
                            ],
                            else: [
                                .showFeedback(message: "Try again. Multiply your two factors and compare with {{target}}.", style: .error, animation: .shake)
                            ]
                        )
                    ]
                )),
                .button(WidgetButton(
                    id: nil,
                    title: "New Target",
                    style: .secondary,
                    actions: [
                        .set(stateKey: "target", value: .randomInt(min: 10, max: 60)),
                        .set(stateKey: "factorA", value: .value(.string(""))),
                        .set(stateKey: "factorB", value: .value(.string(""))),
                        .showFeedback(message: "New target: {{target}}", style: .neutral, animation: nil)
                    ]
                )),
                .feedback(WidgetFeedback(id: nil))
            ]
        ))
    )

    static let factorPairsJSON = WidgetJSONCodec.prettyPrint(factorPairsDocument)

    static let algebraShowcaseJSON = #"""
    {
      "schemaVersion": 1,
      "widgetId": "algebra-transform-showcase",
      "title": "Transformation Coach",
      "description": "Adjust h and k, choose the parent function, and track progress.",
      "learningObjective": "Explore parent-function transformations using native widget controls.",
      "analytics": { "enabled": false },
      "initialState": {
        "selectedFunction": "parabola",
        "h": 0,
        "k": 0,
        "score": 2,
        "stars": 2,
        "hintLevel": 0
      },
      "body": {
        "type": "stack",
        "axis": "vertical",
        "spacing": 12,
        "decoration": {
          "fill": "#F8FAFC",
          "borderColor": "#93C5FD",
          "borderWidth": 2,
          "cornerRadius": 16,
          "padding": 12
        },
        "children": [
          {
            "type": "text",
            "role": "title",
            "text": "Move the Parent Function"
          },
          {
            "type": "choiceGroup",
            "label": "Parent function",
            "stateKey": "selectedFunction",
            "style": "tiles",
            "choices": [
              { "label": "Parabola", "value": "parabola" },
              { "label": "Absolute Value", "value": "absoluteValue" }
            ]
          },
          {
            "type": "grid",
            "columns": 2,
            "spacing": 10,
            "children": [
              { "type": "valueStepper", "label": "h", "stateKey": "h", "min": -5, "max": 5, "step": 1 },
              { "type": "valueSlider", "label": "k", "stateKey": "k", "min": -5, "max": 5, "step": 1 }
            ]
          },
          {
            "type": "nativeGraph",
            "width": 320,
            "height": 220,
            "xMin": -6,
            "xMax": 6,
            "yMin": -6,
            "yMax": 8,
            "elements": [
              {
                "type": "parabola",
                "a": 1,
                "h": { "kind": "state", "stateKey": "h" },
                "k": { "kind": "state", "stateKey": "k" },
                "color": "#F97316",
                "width": 3
              },
              {
                "type": "point",
                "x": { "kind": "state", "stateKey": "h" },
                "y": { "kind": "state", "stateKey": "k" },
                "label": "vertex",
                "color": "#DC2626"
              }
            ]
          },
          {
            "type": "goalMeter",
            "label": "Goal",
            "stateKey": "score",
            "goalValue": 5,
            "style": "bar"
          },
          {
            "type": "symbolCollection",
            "symbol": "star",
            "countStateKey": "stars",
            "maxCount": 5,
            "style": "row"
          },
          {
            "type": "hintProvider",
            "title": "Need a hint?",
            "stateKey": "hintLevel",
            "hints": [
              "h moves the graph left or right.",
              "k moves the graph up or down.",
              "The vertex is currently at ({{h}}, {{k}})."
            ]
          },
          {
            "type": "button",
            "title": "I explained the movement",
            "style": "primary",
            "actions": [
              { "action": "increment", "stateKey": "score", "by": 1 },
              { "action": "increment", "stateKey": "stars", "by": 1 },
              {
                "action": "showFeedback",
                "message": "Nice: the vertex is at ({{h}}, {{k}}).",
                "style": "success",
                "animation": "pulse"
              },
              {
                "action": "recordAttempt",
                "questionId": "transform-parent-function",
                "answerStateKeys": ["h", "k"],
                "correct": true
              }
            ]
          },
          { "type": "feedback" }
        ]
      }
    }
    """#

    static let mathTemplateShowcaseJSON = #"""
    {
      "schemaVersion": 1,
      "widgetId": "math-template-showcase",
      "title": "Factoring Format Check",
      "description": "Shows aligned algebraic answer entry with mathTemplate.",
      "learningObjective": "Format factored expressions clearly.",
      "analytics": { "enabled": false },
      "initialState": {
        "gcf": "",
        "firstTerm": "",
        "secondTerm": ""
      },
      "body": {
        "type": "stack",
        "axis": "vertical",
        "spacing": 14,
        "children": [
          {
            "type": "text",
            "role": "math",
            "text": "Factor: 8x + 20"
          },
          {
            "type": "mathTemplate",
            "fontScale": "large",
            "spacing": 6,
            "parts": [
              { "type": "text", "text": "(" },
              { "type": "numberBox", "stateKey": "gcf", "placeholder": "", "maxLength": 2, "clearOnSelect": true },
              { "type": "text", "text": ")(" },
              { "type": "numberBox", "stateKey": "firstTerm", "placeholder": "", "maxLength": 2, "clearOnSelect": true },
              { "type": "text", "text": "x + " },
              { "type": "numberBox", "stateKey": "secondTerm", "placeholder": "", "maxLength": 2, "clearOnSelect": true },
              { "type": "text", "text": ")" }
            ]
          },
          {
            "type": "digitPad",
            "digits": [0,1,2,3,4,5,6,7,8,9],
            "shape": "circle"
          }
        ]
      }
    }
    """#

    static let advancedHTML = """
    <!doctype html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body { font-family: -apple-system, sans-serif; padding: 20px; background: #f6f8fb; }
        button { font-size: 20px; padding: 12px 18px; border-radius: 10px; }
        #count { font-size: 56px; font-weight: 800; margin: 16px 0; }
      </style>
    </head>
    <body>
      <h2>Advanced HTML Widget</h2>
      <p>Experimental WKWebView mode.</p>
      <div id="count">0</div>
      <button onclick="count++; document.getElementById('count').textContent = count">Add 1</button>
      <script>let count = 0;</script>
    </body>
    </html>
    """
}
