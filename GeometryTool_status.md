# Geometry Tool Status

**Last updated:** 2026-07-09

This is the focused handoff document for MathBoard's Geometry tool. New AI sessions working on geometry should read this after `Project_status.md` Section 0.

## Current Behavior

- The Compact palette Geometry tool creates vector geometry objects, not PencilKit ink.
- Supported shapes are line, circle, right triangle, triangle, rectangle, and polygon.
- Geometry objects persist in the drawing package through the `CanvasGeometryObject` sidecar.
- Line arrowheads render with their tips at the true line endpoints. The shaft is shortened behind arrowheads so the arrows visually define the ends of the line.
- Selecting a geometry object opens the Geometry attribute menu and loads that object's current attributes into the palette.
- While a geometry object is selected, Geometry palette controls edit the selected object live: stroke color, stroke width, opacity, fill color, fill opacity, shape, polygon sides, and line arrow mode.
- Selecting an existing geometry object puts the canvas into object manipulation behavior even though the Geometry tool is visually active in the palette.
- After drawing a new geometry object, the object remains selected and the canvas enters this same object manipulation behavior. Further touches should move, resize, rotate, or deselect the selected object rather than creating duplicate shapes.
- Second-tapping the highlighted Geometry tool while a geometry object is selected clears the selected object, closes the edit state, and arms new-shape drawing. Choosing a shape from the strip menu after that should set the next shape to draw, not mutate the previously selected object.

## Manipulation Behavior

- Dragging the selected geometry object moves it.
- The lower-right resize handle resizes the actual object, not just the selection outline.
- For directional shapes, dragging the resize handle through the object's source origin preserves signed dimensions and flips the shape. Right triangles use this to move the right-angle corner horizontally and vertically; regular triangles use vertical flips to move the apex below the base.
- Resize resets any explicit off-center rotation pivot back to the object's center before resizing. This avoids complicated pivot preservation during scale.
- The blue rotation handle rotates the selected object around the current green pivot dot.
- The green pivot dot can be dragged to relocate the center of rotation.
- Double-tapping the green pivot dot resets it to the center of the object.
- If an explicit off-center pivot has been set, dragging the whole object moves that pivot with the object so it keeps its relative position.
- The geometry Action HUD is draggable so the user can move it away from line handles or the pivot dot.

## Mode Rules

- **First Geometry tap with no geometry selected:** Geometry create mode is armed.
- **Geometry object selected:** Geometry palette is open for editing, but canvas interactions act like Select mode for that object.
- **Geometry attributes changed while selected:** update the selected object.
- **Geometry tool tapped again while selected:** clear selection and arm create mode.
- **Shape chosen from strip with no selected geometry:** set the drawing shape for the next object.
- **Shape chosen from strip with selected geometry:** change the selected object's shape.
- **Tap blank canvas while selected:** deselect and return the palette to Select mode unless the deselect was caused by the intentional second Geometry tap described above.

## Key Files

- `MathBoardCore/Sources/Canvas/PencilKitCanvas.swift`
  - Main iPad canvas integration.
  - Owns geometry creation recognizer, geometry selection, resize/rotate/pivot gestures, hit-testing, overlay refresh, and command application order.
  - Important state includes selected geometry IDs, last selected geometry fallback ID, active geometry config, moving/resizing/rotating/pivot drag state, and pending geometry handle hits.
- `MathBoardCore/Sources/Canvas/CanvasGeometryObject.swift`
  - Geometry object model and sidecar persistence.
  - Stores frame, shape, stroke/fill attributes, polygon sides, arrow mode, rotation, and optional explicit pivot.
- `MathBoardCore/Sources/Canvas/CanvasGeometryRenderer.swift`
  - Draws geometry objects and handles shape-specific rendering.
- `MathBoardCore/Sources/Canvas/CanvasEditControls.swift`
  - Shared command/state types between Presentation and Canvas.
  - Includes geometry update commands and the clear-selection command used by the second Geometry tap behavior.
- `MathBoardCore/Sources/Presentation/PresentingCanvasView.swift`
  - Bridges `ToolPaletteCommand` into `CanvasToolCommand` / `CanvasObjectCommand`.
  - Routes Geometry palette commands to either edit the selected object or arm drawing for a new object.
  - Suppresses the normal "deselected geometry returns palette to Select" behavior during the intentional second Geometry tap.
- `MathBoardCore/Sources/ToolPalette/CompactToolPaletteView.swift`
  - Compact palette UI, including Geometry tool, quick strip, and full Geometry drawer.
- `MathBoardCore/Sources/ToolPalette/ToolPaletteModels.swift`
  - Tool palette state and command model.

## Recent Fixes

- Geometry handle hit-testing was corrected after resize/rotate handles were visible but touches fell through to object dragging or deselection.
- Handle hit-testing now accounts for the selected geometry fallback path because selected IDs can be nil by gesture begin.
- Resize, rotation, and pivot relocation are working in device testing.
- Explicit pivot movement with object drag is working.
- Double-tap pivot reset is working.
- Resize now begins by resetting the explicit pivot to center.
- Post-create secret Select behavior is working.
- Second-tapping the highlighted Geometry tool while editing a selected geometry object now deselects the object and arms new drawing.
- Line arrow rendering now shortens the shaft behind arrowheads so start/end arrows sit on the actual line endpoints instead of appearing inset.
- Right triangles now support resize-to-flip: signed width/height are preserved during resize, the resize handle follows the signed corner, and the renderer chooses the right-angle corner from the horizontal/vertical flip state.
- Regular triangles now use signed height during rendering so dragging the resize handle upward past the source origin flips the apex below the base.

## Known Watch Points

- Geometry hit-testing is sensitive to `PKCanvasView` coordinate spaces, content offset, zoom scale, and overlay/source transforms. Avoid simplifying handle hit-tests without device verification.
- Command ordering matters: when clearing selection and re-arming Geometry creation in the same update, the canvas must apply the object command before the tool command.
- `lastSelectedGeometryObjectID` is intentionally used as a fallback for handle gestures, but it must be cleared during explicit deselection paths where stale handle selection would be wrong.
- The Geometry palette deliberately uses the same visible active tool for two canvas modes: edit-selected and create-new. Check `PresentingCanvasView` routing before assuming the highlighted tool equals the canvas interaction mode.
- If the HUD overlaps handles, prefer draggable/repositionable HUD behavior over moving geometry handles.
- Line rendering is shared by on-canvas overlay, external-display committed frames, and PDF export through `CanvasGeometryRenderer`; arrowhead visual fixes should be made there.
- `CanvasGeometryObject.width` and `height` are intentionally signed for geometry. Use `normalizedFrame` for bounds/hit regions, but use the signed values for directional rendering and the active resize corner.

## Device Test Checklist

- Draw a rectangle, then confirm the new object is selected and further canvas drags move it instead of creating another rectangle.
- Change stroke/fill/shape while selected and confirm the selected object updates.
- Drag the lower-right resize handle and confirm the object resizes.
- Drag the rotation handle and confirm the object rotates around the green pivot.
- Drag the green pivot off-center, rotate, then drag the whole object and confirm the pivot moves with it.
- Double-tap the green pivot and confirm it returns to center.
- Resize after moving the pivot and confirm the pivot resets to center before resizing.
- With a geometry object selected, tap the highlighted Geometry tool again, choose a shape from the strip, and draw; confirm the old object is not changed and a new shape is created.
- Tap blank canvas after selecting a geometry object and confirm the object deselects and the palette returns to Select mode.
- Draw a two-ended arrow line at a thick stroke width and confirm both arrowhead tips land at the line endpoints with no visible shaft protruding through the arrowheads.
- Draw a right triangle, drag the resize handle left past the source origin, and confirm the right angle flips to the opposite side.
- Drag the same right triangle resize handle upward past the source origin and confirm the right angle flips vertically.
- Draw a regular triangle, drag the resize handle upward past the source origin, and confirm the apex flips to the bottom.
