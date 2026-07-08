# Calculator Status

## 2026-07-05

Calculator-only work completed in this pass:

- Added TI-style screen states for Calc home, Math menu, Stat menu, Stat editor, and regression result screens.
- Wired full keypad callbacks for `math`, `stat`, `2nd`, `alpha`, arrows, and shifted trig/log/root keys.
- Added Math menu tabs:
  - `MATH`: `1:>Frac`, `2:>Dec`, `3:^3`, `4:³√(`, `5:x√(`, `A:logBASE(` are active.
  - `NUM`: `1:abs(`, `8:lcm(`, and `9:gcd(` are active.
  - `CMPLX`, `PROB`, and `FRAC` show menu items as visual placeholders only.
- Added a simple STAT list editor for `L1` and `L2` so students can enter x/y data.
- Added STAT CALC regression result screens for:
  - `4:LinReg(ax+b)`
  - `5:QuadReg`
  - `6:CubicReg`
  - `7:QuartReg`
- Added regression math helper for linear, quadratic, cubic, and quartic least-squares fits.

Known intentional placeholders:

- STAT `1-Var Stats`, `2-Var Stats`, sorting, tests, complex, probability, and fraction template tabs are menu-only for now.
- `x√(` is backed by `root(value,index)` in the engine, not a full MathPrint template yet.
- Regression screens calculate from the internal `L1` and `L2` lists only. Store-to-Y and residual lists are not implemented yet.
- The Math `>Frac` display approximates the current numeric result as `n/d`; it does not yet insert a full TI fraction template.
