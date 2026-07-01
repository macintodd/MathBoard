//
//  WidgetContract.swift
//  WidgetEngine
//
//  Public contract for the Widget Engine prototype.
//
//  This file is intentionally free of any dependency on MathBoard.app or the
//  other MathBoardCore modules. `MathBoardObject` is the minimal shape a future
//  Coordinator can adopt to place widgets on the main canvas, but nothing here
//  reaches into the app's drawing or state management.
//

import Foundation
import CoreGraphics

/// The minimal contract any object placed on the whiteboard must satisfy.
///
/// Kept deliberately small so the app can later bridge widgets onto the real
/// canvas without WidgetEngine ever having to know how that canvas works.
protocol MathBoardObject: Identifiable {
    /// Stable identity for the object.
    var id: UUID { get }

    /// The object's position and size in its parent coordinate space.
    /// Mutable so containers can update it while dragging / resizing.
    var frame: CGRect { get set }
}

/// A concrete whiteboard object that renders an interactive HTML/JS widget.
struct WidgetObject: MathBoardObject {
    let id: UUID

    /// Position and size in the parent coordinate space.
    var frame: CGRect

    /// Human-readable label shown in the container's header.
    var name: String

    /// The raw HTML/JS source rendered inside the widget's web view.
    var codeString: String

    init(
        id: UUID = UUID(),
        name: String,
        codeString: String,
        frame: CGRect
    ) {
        self.id = id
        self.name = name
        self.codeString = codeString
        self.frame = frame
    }
}

extension WidgetObject {
    /// A ready-to-render sample used by previews and as a sensible default when
    /// the user first opens the editor.
    static var sample: WidgetObject {
        WidgetObject(
            name: "Sample Widget",
            codeString: WidgetSampleCode.counter,
            frame: CGRect(x: 80, y: 120, width: 360, height: 280)
        )
    }
}

/// Bundled boilerplate strings for the prototype. Keeping these here avoids
/// scattering large string literals through the view code.
enum WidgetSampleCode {
    /// The prompt users copy into their AI assistant to generate a widget.
    static let boilerplatePrompt = """
    Copy the following text to your AI to generate a widget: Write in a single \
    copyable code window the html/js code that would create an interactive \
    widget. Here is what the widget should help students practice and \
    comprehend: [User Description]
    """

    /// A small self-contained interactive widget used as the default preview.
    static let counter = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>Factoring Trinomials</title>
        <style>
            body { font-family: sans-serif; text-align: center; padding: 20px; }
            #problem { font-size: 2em; margin: 20px; }
            .slot { 
                display: inline-block; width: 60px; height: 50px; border: 2px solid #333; 
                vertical-align: middle; line-height: 50px; font-weight: bold; cursor: pointer;
                background: #fff; margin: 0 5px; border-radius: 5px;
            }
            .block { 
                display: inline-block; width: 40px; height: 40px; margin: 5px; cursor: pointer; 
                color: white; font-weight: bold; line-height: 40px; border-radius: 4px;
            }
        </style>
    </head>
    <body>

        <h2>Fill in the factors:</h2>
        <div id="problem">x² + <span id="b"></span>x + <span id="c"></span></div>
        
        <div>(x + <div class="slot" id="s1" onclick="removeFromSlot(0)"></div>)(x + <div class="slot" id="s2" onclick="removeFromSlot(1)"></div>)</div>
        
        <div id="blocks-container" style="margin-top: 20px;"></div>
        <br>
        <button onclick="checkAnswer()">Check Answer</button>
        <button onclick="initGame()">New Problem</button>
        <p>Score: <span id="score">0</span></p>

        <script>
            let b, c, score = 0;
            let selected = [null, null];

            function initGame() {
                const p = (Math.floor(Math.random() * 9) + 1) * (Math.random() > 0.5 ? 1 : -1);
                const q = (Math.floor(Math.random() * 9) + 1) * (Math.random() > 0.5 ? 1 : -1);
                b = p + q; c = p * q;
                document.getElementById('b').innerText = b;
                document.getElementById('c').innerText = c;
                selected = [null, null];
                updateDisplay();
                
                const container = document.getElementById('blocks-container');
                container.innerHTML = '';
                for (let i = -9; i <= 9; i++) {
                    if (i === 0) continue;
                    const div = document.createElement('div');
                    div.className = 'block';
                    div.innerText = i;
                    div.style.backgroundColor = i > 0 ? '#4a90e2' : '#e74c3c';
                    div.onclick = () => addToSlot(i);
                    container.appendChild(div);
                }
            }

            function addToSlot(val) {
                if (selected[0] === null) selected[0] = val;
                else if (selected[1] === null) selected[1] = val;
                updateDisplay();
            }

            function removeFromSlot(idx) {
                selected[idx] = null;
                updateDisplay();
            }

            function updateDisplay() {
                document.getElementById('s1').innerText = selected[0] !== null ? selected[0] : '';
                document.getElementById('s2').innerText = selected[1] !== null ? selected[1] : '';
            }

            function checkAnswer() {
                if (selected[0] === null || selected[1] === null) return alert("Fill both slots!");
                if ((selected[0] + selected[1] === b) && (selected[0] * selected[1] === c)) {
                    score++; alert("Correct!"); initGame();
                } else {
                    score = Math.max(0, score - 1); alert("Try again!");
                }
                document.getElementById('score').innerText = score;
            }
            initGame();
        </script>
    </body>
    </html>
    """
}
