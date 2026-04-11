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
import time
from pathlib import Path


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


async def run(pdf_path: str, output_dir: str, title: str, fmt: str = "explainer", style: str = "whiteboard") -> None:
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

    out_dir = Path(output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    safe = "".join(c if c.isalnum() or c in " -_" else "_" for c in title).strip()
    out_path = out_dir / f"{safe}.mp4"

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

            fmt_enum = VideoFormat[fmt.upper()] if fmt.upper() in VideoFormat.__members__ else VideoFormat.EXPLAINER
            style_enum = VideoStyle[style.upper()] if style.upper() in VideoStyle.__members__ else VideoStyle.WHITEBOARD
            emit({
                "status": "generating",
                "message": f"Starting video generation ({fmt_enum.name.title()} + {style_enum.name.title()}, ~15 min)...",
            })
            gs = await client.artifacts.generate_video(
                notebook_id=nid,
                source_ids=[source.id],
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
    p.add_argument("--output-dir", required=True, help="Directory to save the video")
    p.add_argument("--title", required=True, help="Chapter title (used as notebook and file name)")
    p.add_argument("--format", default="explainer", help="Video format: explainer or deep_dive")
    p.add_argument("--style", default="whiteboard", help="Video style: whiteboard or slideshow")
    args = p.parse_args()
    asyncio.run(run(args.pdf_path, args.output_dir, args.title, args.format, args.style))


if __name__ == "__main__":
    main()
