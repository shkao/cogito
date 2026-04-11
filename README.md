# Cogito

[![Swift](https://img.shields.io/badge/Swift-6-FA7343?logo=swift)](Sources/)
[![macOS](https://img.shields.io/badge/macOS-%E2%89%A5%2014-000000?logo=apple)](Package.swift)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

*Cogito, ergo sum.* I think, therefore I am.

A macOS PDF reader built to help you think. Most PDF readers display pages. Cogito turns reading into active thinking through margin notes, instant word translation, AI-generated chapter videos, and on-device LLM inference.

## What it does

**PDF reading** — opens any PDF with automatic margin cropping, single and two-page layouts, zoom, bookmarks, and full-text search. The outline sidebar supports both PDFKit-provided outlines and LLM-inferred chapter structure for PDFs with no embedded table of contents.

**Cornell notes** — narrow note panels flank the pages in two-page mode. Notes are saved per page, per document, and survive restarts.

**Word translation** — select any word to get a translation card powered by the Wikipedia summary API. Eight target languages, persistent preference.

**Video overviews** — hover any chapter in the outline and click the video icon. Cogito extracts that chapter as a PDF, uploads it to Google NotebookLM via a Python bridge, and generates an Explainer or Deep Dive video with Whiteboard or Slideshow style. A production brief instructs the generator to favor animation over static slides and to cover every concept in the chapter. The finished video plays in a full-window overlay with caption support.

**Local LLM inference** — Gemma 3n E4B runs on-device via mlx-swift for chapter outline detection and any future on-device tasks. No cloud call, no GPU required beyond the Apple Silicon Neural Engine.

## Architecture

```mermaid
%%{init:{'theme':'base','themeVariables':{'primaryColor':'#6366f1','primaryTextColor':'#1e1b4b','lineColor':'#a5b4fc','fontSize':'13px'}}}%%
graph LR
    User(("User"))

    subgraph App[" Cogito.app "]
        direction TB

        subgraph UI[" SwiftUI UI Layer "]
            direction LR
            CV["ContentView"]
            SB["SidebarView"]
            PR["PDFReaderView"]
            TC["TranslationCardView"]
            VB["VideoGenerationBannerView"]
            VO["VideoOverlayView\n(AVFoundation)"]
        end

        VM[["PDFViewModel\n@MainActor ObservableObject\n\nstate · navigation · bookmarks\noutline · search · notes"]]

        subgraph Services[" Services "]
            direction TB
            LLM["LLMService\nGemma 3n E4B\nmlx-swift · on-device"]
            WTS["WikiTranslationService\nURLSession"]
            NLM["NotebookLMService\nProcess actor\n(shells out to Python)"]
        end

        PDFKit[["PDFKit\nsystem framework"]]
    end

    subgraph Bridge[" Python bridge "]
        PY["generate_video.py\nnotebooklm-py 0.3.x"]
    end

    subgraph Cloud[" Cloud "]
        Wiki[("Wikipedia\nREST API")]
        NLMAPI[("Google\nNotebookLM")]
    end

    User -- "open / navigate\nbookmark / search" --> CV
    CV & SB & PR --> VM
    VM --> PDFKit

    VM -- "infer outline\nfrom TOC pages" --> LLM
    VM -- "selected word" --> WTS
    VM -- "chapter PDF +\noutput path" --> NLM

    WTS -- "GET summary" --> Wiki
    Wiki -- "definition" --> WTS
    WTS -- "translation" --> TC

    NLM -- "spawn process" --> PY
    PY -- "upload + generate" --> NLMAPI
    NLMAPI -- "MP4 download" --> PY
    PY -- "JSON status lines" --> NLM
    NLM -- "AsyncStream<VideoStatus>" --> VB
    NLM -- "done(videoPath:)" --> VO

    LLM -- "OutlineNode[]" --> VM

    style App fill:#fafafe,stroke:#6366f1,stroke-width:2px,color:#4338ca
    style UI fill:#eff6ff,stroke:#3b82f6,stroke-width:1.5px,color:#1e40af
    style Services fill:#fdf2f8,stroke:#ec4899,stroke-width:1.5px,color:#9d174d
    style Bridge fill:#fffbeb,stroke:#d97706,stroke-width:1.5px,color:#92400e
    style Cloud fill:#f0fdf4,stroke:#4ade80,stroke-width:1.5px,color:#14532d
    style VM fill:#eef2ff,stroke:#6366f1,stroke-width:2px,color:#3730a3
    style PDFKit fill:#dbeafe,stroke:#60a5fa,color:#1e3a5f
    style LLM fill:#fce7f3,stroke:#f472b6,color:#831843
    style WTS fill:#fce7f3,stroke:#f472b6,color:#831843
    style NLM fill:#fce7f3,stroke:#f472b6,color:#831843
    style PY fill:#fffbeb,stroke:#f59e0b,color:#78350f
    style Wiki fill:#dcfce7,stroke:#4ade80,color:#14532d
    style NLMAPI fill:#dcfce7,stroke:#4ade80,color:#14532d
```

**Data flows:**

| Action | Path |
|--------|------|
| Open PDF | `PDFViewModel` → `PDFKit` → renders in `PDFReaderView` |
| Infer outline (no TOC) | `PDFViewModel` → `LLMService` (Gemma, on-device) → `OutlineNode[]` |
| Select word | `PDFReaderView` → `PDFViewModel` → `WikiTranslationService` → Wikipedia API → `TranslationCardView` |
| Generate video | `PDFViewModel` → `NotebookLMService` → `generate_video.py` → NotebookLM → MP4 on disk → `VideoOverlayView` |

## Project structure

```
cogito/
├── Sources/Cogito/
│   ├── CogitoApp.swift              # App entry, menu commands
│   ├── ContentView.swift            # Root layout, toolbar, video overlay
│   ├── PDFViewModel.swift           # Central state (navigation, bookmarks,
│   │                                #   outline, notes, translation, video)
│   ├── PDFReaderView.swift          # PDFKit NSView bridge, selection handling
│   ├── SidebarView.swift            # Outline / thumbnails / bookmarks / videos
│   ├── CornellNoteView.swift        # Per-page margin note editor
│   ├── TranslationCardView.swift    # Floating word translation card
│   ├── VideoGenerationBannerView.swift  # Status banner (uploading/polling/done)
│   ├── NotebookLMService.swift      # Process actor: spawns Python, streams status
│   ├── LLMService.swift             # mlx-swift wrapper for Gemma 3n E4B
│   ├── WikiTranslationService.swift # Wikipedia summary API client
│   └── ...                          # Supporting views and utilities
│
├── Scripts/
│   └── generate_video.py            # Python bridge: PDFKit → NotebookLM → MP4
│
├── Package.swift                    # SPM: mlx-swift dependency
├── Makefile                         # build / bundle / run targets
└── FEATURES.md                      # Roadmap and design notes
```

## Requirements

| Dependency | Version | Role |
|------------|---------|------|
| macOS | ≥ 14 | SwiftUI, PDFKit, AVFoundation |
| Swift | ≥ 6 | Language and SPM |
| Python 3 | any recent | Video generation bridge |
| [notebooklm-py](https://github.com/inconsistentpassion/notebooklm-py) | ≥ 0.3 | NotebookLM API client |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | ≥ 0.21 | On-device LLM inference |

## Building

```bash
# Install Python dependency
pip install notebooklm-py

# Authenticate with NotebookLM (one-time, browser-based)
notebooklm login

# Build and run (dev build, no bundle)
make build && make run

# Full app bundle (copies mlx.metallib and generate_video.py into .app)
make bundle && open Cogito.app
```

The `mlx.metallib` GPU shader library is copied automatically from the Python MLX installation. If Python MLX is not installed (`pip install mlx`), on-device LLM inference will fall back to CPU.

## Video generation

Video generation uses Google NotebookLM, which requires a Google account. Authentication is browser-based and persists in a local cookie store managed by `notebooklm-py`.

The Python bridge (`Scripts/generate_video.py`) receives a chapter PDF and the full expected output path from the Swift side, uploads both the PDF and a production brief to a new NotebookLM notebook, triggers video generation, and polls until the MP4 is ready. Progress is emitted as JSON lines on stdout and parsed by `NotebookLMService` into a typed `AsyncStream<VideoStatus>`.

Videos are cached in `~/Library/Caches/com.cogito.app/Videos/` with a stable per-book hash suffix to prevent cross-book collisions.

## License

MIT
