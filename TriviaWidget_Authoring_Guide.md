# Trivia Widget Content & JSON Guidelines

## Target Audience & Tone
* Target age demographic: 57 to 70 years old.
* Tone: Nostalgic, engaging, fun, and culturally relevant (1960s–1990s pop culture, history, music, classic television, and household trivia).

## Category Mapping
1. Groovy Decades (1960s & 1970s Culture)
2. Blockbuster Silver Screen
3. Global Landmarks & Jet-Set Travel
4. Household Classics & Commercials
5. Legends of Rock, Pop, & Soul
6. Kitchen & Comfort Food

## JSON Schema Requirements for Trivia Batches
When generating question batches for the MathBoard multiple-choice activity format, ensure each batch adheres to the standard `ActivityWidgetDocument` structure:
- `activity`: "multipleChoice"
- `schemaVersion`: 1
- `questions`: Array of objects containing:
  - `id`: Unique string identifier (e.g., "groovy-01")
  - `prompt`: The trivia question text
  - `choices`: Exactly 4 options (A, B, C, D)
  - `correctAnswerIndex`: Index of the correct choice (0 through 3)
  - `explanation`: Short, fun trivia fact shown after answering
