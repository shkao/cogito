# Feature: Jupyter-like Executable Code Blocks in PDF Reader

## Context

Cogito is a macOS SwiftUI PDF reader for textbooks. The user wants to run code snippets directly from the PDF, like Jupyter notebook cells. Textbooks (e.g., ML/clustering chapters) contain Python code that readers currently have to copy-paste into a separate environment. This feature lets them execute code inline, keeping reading and experimentation in one place.

**Key challenge:** `PDFTextExtractor.normalize()` strips leading whitespace (line 33), destroying indentation. We need a raw extraction path that preserves indentation for code detection.

## Architecture

Four subsystems: (1) code block detection, (2) Python kernel, (3) notebook UI, (4) ViewModel wiring.

## New Files

| File | Purpose |
|------|---------|
| `Sources/Cogito/CodeBlockDetector.swift` | Heuristic + LLM code extraction from PDF text |
| `Sources/Cogito/PythonKernelService.swift` | Actor managing a persistent Python REPL subprocess |
| `Sources/Cogito/CodeNotebookView.swift` | Notebook panel with scrollable code cells |
| `Sources/Cogito/CodeCellView.swift` | Individual cell: editor + run button + output area |
| `Scripts/kernel_driver.py` | Python-side REPL driver with JSON stdin/stdout protocol |

## Modified Files

| File | Changes |
|------|---------|
| `Sources/Cogito/PDFTextExtractor.swift` | Add `rawText(from:)` that preserves indentation |
| `Sources/Cogito/PDFViewModel.swift` | Add notebook state, cell management, kernel lifecycle |
| `Sources/Cogito/ContentView.swift` | Add notebook panel to layout, toolbar button |

---

## Phase 1: Kernel Infrastructure

### 1a. `Scripts/kernel_driver.py`

A long-running Python process that reads JSON commands from stdin and writes JSON responses to stdout.

- Maintains a persistent `namespace = {}` dict across executions
- Each cell: `exec(code, namespace)` with stdout/stderr capture via `io.StringIO` + `contextlib.redirect_stdout`
- Matplotlib handling: `matplotlib.use('Agg')` on startup, patch `plt.show()` to save figures to temp PNGs
- Protocol:
  - **Input:** `{"id": "uuid", "code": "import numpy as np\n..."}`
  - **Output (success):** `{"id": "uuid", "status": "ok", "stdout": "...", "stderr": "...", "figures": ["/tmp/fig_0.png"]}`
  - **Output (error):** `{"id": "uuid", "status": "error", "traceback": "..."}`
  - **Interrupt:** `{"id": "uuid", "action": "interrupt"}` sends KeyboardInterrupt
- Flush stdout after every response to prevent buffering issues

### 1b. `Sources/Cogito/PythonKernelService.swift`

An `actor` following the `NotebookLMService` pattern (`NotebookLMService.swift:244-268`).

- `resolvePython()` probes the same candidate paths but validates with `import numpy` instead of `import notebooklm`
- `resolveScriptPath()` same pattern as `NotebookLMService.resolveScriptPath()` but for `kernel_driver.py`
- Spawns `Process` with stdin/stdout/stderr pipes
- `execute(code:) async -> CellResult` writes JSON to stdin, reads JSON response from stdout
- `restart()` kills and respawns the process (clears namespace)
- `shutdown()` terminates on app quit

```swift
enum CellResult {
    case success(stdout: String, stderr: String, figures: [URL])
    case error(traceback: String)
}
```

---

## Phase 2: Code Block Detection

### `Sources/Cogito/CodeBlockDetector.swift`

**Two-pass approach: fast heuristic, optional LLM refinement.**

First, add a `rawText(from:)` method to `PDFTextExtractor` that skips the `trimmingCharacters(in: .whitespaces)` call, preserving indentation.

**Heuristic signals** (scan raw text line by line, group consecutive code-like lines):
- Lines starting with `>>>` or `...` (Python REPL)
- Lines starting with `import `, `from ... import`, `def `, `class `
- Blocks of 3+ consecutive lines with consistent 4+ space indentation relative to surrounding prose
- Lines containing `print(`, `plt.`, `np.`, `pd.`, `sklearn.`, `fit(`, `predict(`
- Lines ending with `:` followed by indented lines

**LLM refinement** (optional, for low-confidence blocks): send page text to `LLMService.shared.generate()` with a prompt asking for JSON code block boundaries. Same pattern as `inferOutlineWithLLM` in PDFViewModel.

```swift
struct DetectedCodeBlock: Identifiable {
    let id: UUID
    var code: String
    let pageIndex: Int
    var confidence: Double  // 0.0-1.0
}
```

---

## Phase 3: Notebook UI

### 3a. Data Model

```swift
struct CodeCell: Identifiable {
    let id: UUID
    var code: String
    var stdout: String?
    var stderr: String?
    var figures: [NSImage]
    var isRunning: Bool
    var executionOrder: Int?  // [1], [2], etc.
}
```

### 3b. `Sources/Cogito/CodeCellView.swift`

Each cell has:
- Monospace `TextEditor` (`.system(.body, design: .monospaced)`) for editable code
- Play button (SF Symbol `play.fill`) in top-right corner
- Output area below: stdout in monospace, stderr in orange, figure images via `Image(nsImage:)`
- Execution order badge `[N]` in top-left
- Running state shows `ProgressView()`

### 3c. `Sources/Cogito/CodeNotebookView.swift`

Right-side panel (380pt wide) containing:
- Header: chapter title, "Restart Kernel" button, "Run All" button, "Add Cell" button
- `ScrollView` of `CodeCellView` items
- Empty state when no code blocks detected

### 3d. Layout integration in `ContentView.swift`

Add the notebook panel after the PDF ZStack, inside the outer `HStack`:

```swift
HStack(spacing: 0) {
    if showSidebar { SidebarView()... }
    ZStack { /* existing PDF + overlays */ }
    if vm.isNotebookVisible {
        Divider()
        CodeNotebookView()
            .frame(width: 380)
    }
}
```

Toolbar button: terminal icon, Cmd+K shortcut.

---

## Phase 4: ViewModel Wiring

Add to `PDFViewModel.swift`:

```swift
// Published state
@Published var isNotebookVisible = false
@Published var codeCells: [CodeCell] = []
@Published var isDetectingCode = false

// Methods
func toggleNotebook()       // Toggle panel, auto-detect on first open
func detectCodeBlocks()     // Run detector on current chapter
func runCell(_ cell: CodeCell)
func runAllCells()
func restartKernel()
func addEmptyCell()
func deleteCell(_ cell: CodeCell)
```

**Kernel lifecycle:** per-chapter. When detecting code for a new chapter, restart the kernel to clear the namespace. Track the current chapter ID to know when a restart is needed.

---

## Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| UI placement | Right panel (380pt) | Wide enough for code; preserves PDF visibility. Cornell notes are only 48pt, too narrow. A modal overlay hides the PDF. |
| Kernel scope | Per-chapter | Textbook chapters are self-contained units. Variables from Chapter 10 shouldn't leak into Chapter 11. |
| Code detection | Heuristic-first | Fast, zero LLM latency for obvious patterns. LLM as fallback for ambiguous blocks. |
| Python env | Reuse existing resolvePython pattern | Consistent with NotebookLMService. Probe common paths, validate with `import numpy`. |
| Plot capture | Patch plt.show(), save to temp PNG | Standard approach. NSImage loads the PNG for display in SwiftUI. |

---

## Verification

1. **Build:** `make build` compiles without errors
2. **Kernel test:** Open app, toggle notebook (Cmd+K), add empty cell, type `print("hello")`, click Run, verify "hello" appears in output
3. **Detection test:** Open a textbook PDF with code (e.g., ML clustering chapter), toggle notebook, verify code blocks are extracted and editable
4. **Persistence test:** Run `x = 42` in cell 1, then `print(x)` in cell 2, verify it prints 42
5. **Plot test:** Run `import matplotlib.pyplot as plt; plt.plot([1,2,3]); plt.show()`, verify figure image appears
6. **Kernel restart:** Click "Restart Kernel", verify `print(x)` in a new cell raises NameError
7. **Chapter switch:** Navigate to a different chapter, verify cells update and kernel restarts
