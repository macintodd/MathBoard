# WidgetEngine Status

## Current State

The WidgetEngine currently has a component-based JSON schema in `WidgetSchema.swift` and a native SwiftUI renderer in `WidgetNativeRenderer.swift`. This path can render functional widgets with stacks, grids, text, formulas, inputs, choice groups, keypads, hints, feedback, scores, question sets, graphics, and actions.

## Issue Found

The component schema works technically, but it puts too much visual design responsibility on the AI. Valid widgets often look like generic form-based practice activities because the AI is assembling the full interface from low-level pieces.

## Architecture Pivot

The next direction is an activity-based widget architecture. AI should generate educational content and logic, while MathBoard should render that content through curated native SwiftUI experiences.

Detailed handoff and implementation notes live in `WidgetActivityArchitecture_status.md`.

