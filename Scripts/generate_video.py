#!/usr/bin/env python3
"""Upload a chapter PDF to NotebookLM and generate an Explainer + Whiteboard video.

Usage:
    python3 generate_video.py --pdf-path chapter.pdf --output-dir ~/Videos --title "Chapter 3"

Progress is emitted as JSON lines on stdout:
    {"status": "uploading", "message": "..."}
    {"status": "generating", "message": "..."}
    {"status": "polling", "elapsed": 120, "message": "..."}
    {"status": "downloading", "message": "..."}
    {"status": "done", "path": "/path/to/video.mp4"}
    {"status": "error", "message": "..."}
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import tempfile
import time
from pathlib import Path

# Production brief injected as a second source so the video generator
# favours dynamic animations over static diagrams and bullet slides.
ANIMATION_BRIEF = """\
VIDEO PRODUCTION BRIEF — Animation-First Explainer

Apply these principles when generating the video for this chapter:

LENGTH AND COVERAGE
Target length: 8 to 10 minutes. Do not exceed 10 minutes.
Coverage: every major concept, algorithm, equation, and worked example in
the source chapter must appear in the video. Omitting a key topic is a
failure mode. If time is tight, compress the opening hook and closing
recap — never cut core content.

CORE PHILOSOPHY
Every concept must be shown through motion. Build, transform, flow, and
connect — never just present text on screen. A viewer who pauses at any
frame should see an animation mid-way through, not a finished static slide.

ANIMATION PRINCIPLES

1. Progressive reveal — introduce one element at a time. Let each idea
   settle visually before the next appears. Never show the full diagram
   upfront and then talk through it.

2. Show processes in motion — if something is a sequence, algorithm, or
   pipeline, animate every step. Show data values changing, structures
   forming, signals propagating. Do not describe a process in words while
   displaying a finished-state diagram.

3. Transform, don't replace — when a concept evolves or a variable
   updates, animate the change in place rather than cutting to a new
   static view. The viewer's eye should track the transformation.

4. Spatial cause-and-effect — show relationships by drawing animated
   arrows, by moving one object toward another, or by highlighting the
   region that changes as a result of an action.

5. Physical metaphors for abstract ideas — translate abstractions into
   motion: gradient descent as a ball rolling to a valley floor; a neural
   network as light pulses traveling through a wire mesh; a probability
   distribution as sand settling into a curve; overfitting as a line
   contorting to chase every dot.

6. Annotate live — write labels, equations, and callouts directly onto the
   animation as it plays, in sync with the narration. Never pre-place all
   text before speaking.

STRUCTURE

- Open with a concrete, moving motivating example before any definitions.
- Introduce formal notation only after the intuition is established visually.
- Each section needs one persistent visual anchor (a diagram, a grid, a
  graph) that gets built up and annotated throughout — not replaced each
  time the topic shifts.
- Close with a rapid replay of the key animations to reinforce retention.

WHAT TO AVOID

- Slides that consist of bullet points without accompanying animation.
- Copying a static figure from the source material without animating it.
- Cutting away from an animation before the viewer has fully absorbed it.
- Text-heavy frames where the animation is decorative rather than explanatory.
- Skipping any concept, algorithm, or worked example present in the source.
"""


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


async def try_download(client, nid: str, artifact_id: str, out_path: Path) -> bool:
    """Attempt to download a video artifact. Returns True on success."""
    from notebooklm.exceptions import ArtifactNotReadyError
    try:
        await client.artifacts.download_video(
            notebook_id=nid,
            output_path=str(out_path),
            artifact_id=artifact_id,
        )
        return True
    except ArtifactNotReadyError:
        return False


async def run(pdf_path: str, output_path: str, title: str, fmt: str = "explainer", style: str = "whiteboard") -> None:
    try:
        from notebooklm import NotebookLMClient
        from notebooklm.exceptions import ArtifactNotReadyError
        from notebooklm.types import VideoFormat, VideoStyle
    except ImportError:
        emit({"status": "error", "message": "notebooklm-py not installed. Run: pip install notebooklm-py"})
        sys.exit(1)

    pdf = Path(pdf_path)
    if not pdf.exists():
        emit({"status": "error", "message": f"PDF not found: {pdf_path}"})
        sys.exit(1)

    out_path = Path(output_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        async with await NotebookLMClient.from_storage() as client:
            # Check for an existing notebook with a completed video before creating a new one.
            emit({"status": "uploading", "message": "Checking for existing video..."})
            try:
                notebooks = await client.notebooks.list()
                for nb in notebooks:
                    if nb.title != title:
                        continue
                    videos = await client.artifacts.list_video(nb.id)
                    completed = [v for v in videos if v.is_completed]
                    if not completed:
                        continue
                    # Found a completed video — download it.
                    emit({"status": "downloading", "message": "Downloading existing video..."})
                    if await try_download(client, nb.id, completed[0].id, out_path):
                        emit({"status": "done", "path": str(out_path)})
                        return
            except Exception:
                pass  # If listing fails, fall through to create a new notebook.

            emit({"status": "uploading", "message": f'Creating notebook "{title}"...'})
            notebook = await client.notebooks.create(title=title)
            nid = notebook.id

            emit({"status": "uploading", "message": "Uploading chapter PDF..."})
            source = await client.sources.add_file(
                notebook_id=nid,
                file_path=str(pdf),
                wait=True,
            )

            # Upload the animation production brief as a second source so the
            # video generator favours dynamic animations over static slides.
            emit({"status": "uploading", "message": "Uploading animation brief..."})
            with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False, prefix="cogito-brief-") as f:
                f.write(ANIMATION_BRIEF)
                brief_path = f.name
            try:
                brief_source = await client.sources.add_file(
                    notebook_id=nid,
                    file_path=brief_path,
                    wait=True,
                )
                source_ids = [source.id, brief_source.id]
            except Exception:
                source_ids = [source.id]  # Brief upload failed — proceed without it.
            finally:
                Path(brief_path).unlink(missing_ok=True)

            fmt_key = fmt.upper()
            style_key = style.upper()
            fmt_enum = VideoFormat[fmt_key] if fmt_key in VideoFormat.__members__ else VideoFormat.EXPLAINER
            style_enum = VideoStyle[style_key] if style_key in VideoStyle.__members__ else VideoStyle.WHITEBOARD
            emit({
                "status": "generating",
                "message": f"Starting video generation ({fmt_enum.name.title()} + {style_enum.name.title()}, ~15 min)...",
            })
            gs = await client.artifacts.generate_video(
                notebook_id=nid,
                source_ids=source_ids,
                video_format=fmt_enum,
                video_style=style_enum,
            )
            task_id = gs.task_id

            # poll_status has a bug in _is_media_ready for videos — it reports
            # PROCESSING even when the video is done. Instead, attempt download
            # every 30s; ArtifactNotReadyError means it is not ready yet.
            start = time.monotonic()
            while True:
                await asyncio.sleep(30)

                elapsed = int(time.monotonic() - start)
                mins, secs = divmod(elapsed, 60)
                elapsed_str = f"{mins}m {secs}s" if mins > 0 else f"{secs}s"

                emit({"status": "downloading", "message": "Checking if video is ready..."})
                if await try_download(client, nid, task_id, out_path):
                    emit({"status": "done", "path": str(out_path)})
                    return

                emit({
                    "status": "polling",
                    "elapsed": elapsed,
                    "message": f"Generating... ({elapsed_str} elapsed)",
                })

    except Exception as exc:
        msg = str(exc)
        auth_words = ("auth", "login", "cookie", "credential", "unauthenticated", "permission", "403", "sign in")
        if any(k in msg.lower() for k in auth_words):
            emit({
                "status": "error",
                "message": "NotebookLM auth required. Run 'notebooklm login' in Terminal.",
            })
        else:
            emit({"status": "error", "message": f"Error: {msg}"})
        sys.exit(1)


def main() -> None:
    p = argparse.ArgumentParser(description="Generate NotebookLM video for a chapter PDF.")
    p.add_argument("--pdf-path", required=True, help="Path to chapter PDF file")
    p.add_argument("--output-path", required=True, help="Full path for the output video file")
    p.add_argument("--title", required=True, help="Chapter title (used as the NotebookLM notebook name)")
    p.add_argument("--format", default="explainer", help="Video format: explainer or deep_dive")
    p.add_argument("--style", default="whiteboard", help="Video style: whiteboard or slideshow")
    args = p.parse_args()
    asyncio.run(run(args.pdf_path, args.output_path, args.title, args.format, args.style))


if __name__ == "__main__":
    main()
