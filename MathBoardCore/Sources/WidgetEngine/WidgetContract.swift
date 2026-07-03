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
    <title>Math Word Search</title>
    <style>
    body{
        font-family:Arial,Helvetica,sans-serif;
        background:#f4f8fc;
        text-align:center;
        margin:20px;
    }

    h2{
        margin-bottom:5px;
    }

    #definition{
        font-size:22px;
        font-weight:bold;
        color:#0b4f9c;
        margin:15px;
    }

    table{
        border-collapse:collapse;
        margin:auto;
        touch-action:none;
        user-select:none;
    }

    td{
        width:42px;
        height:42px;
        border:1px solid #888;
        font-size:24px;
        font-weight:bold;
        text-align:center;
        cursor:pointer;
        background:white;
    }

    .selected{
        background:#ffd54f;
    }

    .correct{
        background:#6fcf97 !important;
        color:white;
    }

    #message{
        margin-top:20px;
        font-size:22px;
        font-weight:bold;
        color:green;
    }
    </style>
    </head>

    <body>

    <h2>Math Vocabulary Word Search</h2>

    <p>Find the word that matches the definition.</p>

    <div id="definition"></div>

    <table id="grid"></table>

    <div id="message"></div>

    <script>

    const grid = [
    ['L','I','N','E','Q','R','T','Y','U','P'],
    ['A','D','F','G','H','J','K','L','M','N'],
    ['S','L','O','P','E','B','V','C','X','Z'],
    ['R','T','Y','U','I','O','P','A','S','D'],
    ['F','G','H','J','K','L','Q','W','E','R'],
    ['Y','I','N','T','E','R','C','E','P','T'],
    ['T','Y','U','I','O','P','A','S','D','F'],
    ['G','H','J','K','L','Z','X','C','V','B'],
    ['N','M','Q','W','E','R','T','Y','U','I'],
    ['O','P','L','K','J','H','G','F','D','S']
    ];

    const words = [
    {
    word:"LINE",
    definition:"A straight path that extends forever in both directions."
    },
    {
    word:"SLOPE",
    definition:"The steepness of a line. It tells how much the line rises or falls."
    },
    {
    word:"YINTERCEPT",
    definition:"The point where a line crosses the y-axis."
    }
    ];

    let current = 0;
    let selecting = false;
    let selectedCells = [];

    const table = document.getElementById("grid");

    function buildGrid(){

    for(let r=0;r<10;r++){

        const row=document.createElement("tr");

        for(let c=0;c<10;c++){

            const cell=document.createElement("td");
            cell.textContent=grid[r][c];
            cell.dataset.row=r;
            cell.dataset.col=c;

            cell.addEventListener("pointerdown",startSelection);
            cell.addEventListener("pointerenter",extendSelection);

            row.appendChild(cell);

        }

        table.appendChild(row);

    }

    document.addEventListener("pointerup",finishSelection);

    }

    function updateDefinition(){

    if(current>=words.length){
        document.getElementById("definition").innerHTML="🎉 You found every word!";
        return;
    }

    document.getElementById("definition").textContent=
    words[current].definition;

    }

    function startSelection(e){

    clearSelection();

    selecting=true;
    addCell(e.target);

    }

    function extendSelection(e){

    if(!selecting) return;
    addCell(e.target);

    }

    function addCell(cell){

    if(selectedCells.includes(cell)) return;

    selectedCells.push(cell);
    cell.classList.add("selected");

    }

    function finishSelection(){

    if(!selecting) return;

    selecting=false;

    let guess="";

    selectedCells.forEach(c=>{
    guess+=c.textContent;
    });

    const answer=words[current].word;

    if(guess===answer || guess.split("").reverse().join("")===answer){

    selectedCells.forEach(c=>{
    c.classList.remove("selected");
    c.classList.add("correct");
    });

    current++;

    if(current<words.length){

    setTimeout(()=>{
    updateDefinition();
    },400);

    }else{

    document.getElementById("message").textContent=
    "Excellent! You found all of the vocabulary words.";

    updateDefinition();

    }

    }else{

    selectedCells.forEach(c=>{
    c.classList.remove("selected");
    });

    }

    selectedCells=[];

    }

    function clearSelection(){

    selectedCells.forEach(c=>{
    c.classList.remove("selected");
    });

    selectedCells=[];

    }

    buildGrid();
    updateDefinition();

    </script>

    </body>
    </html>
    """
}
