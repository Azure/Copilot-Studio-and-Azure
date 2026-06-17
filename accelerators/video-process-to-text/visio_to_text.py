#!/usr/bin/env python3
"""
visio_to_text.py
================

Convert Visio process / flowchart diagrams (.vsdx and .vsd) into plain-text
"process pseudo information" that can be ingested by Copilot Studio (or any
other RAG pipeline) which does not natively support Visio files.

The conversion is fully deterministic - it does not call any LLM. It works by:

1. Reading the diagram as an OPC package (a .vsdx file is just a ZIP of XML).
2. Extracting every shape (its text + geometry) and every connector.
3. Rebuilding the directed graph of the flow from Visio's <Connects> table
   (BeginX -> source shape, EndX -> target shape). Connector text becomes the
   edge label (e.g. "YES" / "NO").
4. Walking the graph from its start node(s) to emit a readable, indented
   outline with decisions and branches.

Old binary .vsd files cannot be read directly. If LibreOffice (`soffice`) is
installed it is used to convert them to .vsdx first; otherwise they are skipped
with a clear message.

Usage
-----
    # Convert every .vsd/.vsdx in ./input -> ./output/*.txt
    python visio_to_text.py

    # Convert a single file or a folder, choose an output folder
    python visio_to_text.py "input/Chylothorax algorithm.vsdx" --out output

    # Convert a whole folder
    python visio_to_text.py ./diagrams --out ./text

No third-party packages are required (standard library only).
"""

from __future__ import annotations

import argparse
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass, field

# Visio main namespace used inside the package parts.
NS = "{http://schemas.microsoft.com/office/visio/2012/main}"
REL_NS = "{http://schemas.openxmlformats.org/package/2006/relationships}"


# --------------------------------------------------------------------------- #
# Data model
# --------------------------------------------------------------------------- #
@dataclass
class Shape:
    sid: str
    text: str = ""
    pin_x: float = 0.0
    pin_y: float = 0.0
    width: float = 0.0
    height: float = 0.0
    is_connector: bool = False


@dataclass
class Edge:
    connector_id: str
    source: str | None = None
    target: str | None = None
    label: str = ""


@dataclass
class Page:
    name: str
    shapes: dict[str, Shape] = field(default_factory=dict)
    edges: list[Edge] = field(default_factory=list)


# --------------------------------------------------------------------------- #
# Text extraction helpers
# --------------------------------------------------------------------------- #
def _strip_ns(tag: str) -> str:
    return tag.split("}", 1)[-1] if "}" in tag else tag


def extract_shape_text(shape_el: ET.Element) -> str:
    """Return the visible text of a shape, preserving paragraph breaks.

    Visio stores text in a <Text> element with inline <cp>/<pp>/<tp>/<fld>
    markers. <pp> marks a new paragraph, so we turn those into newlines.
    """
    text_el = shape_el.find(f"{NS}Text")
    if text_el is None:
        return ""

    parts: list[str] = []

    def walk(el: ET.Element, is_root: bool) -> None:
        # A <pp> element introduces a new paragraph (but not before any text).
        tag = _strip_ns(el.tag)
        if tag == "pp" and parts and not parts[-1].endswith("\n"):
            parts.append("\n")
        if el.text:
            parts.append(el.text)
        for child in el:
            walk(child, False)
            if child.tail:
                parts.append(child.tail)

    if text_el.text:
        parts.append(text_el.text)
    for child in text_el:
        walk(child, False)
        if child.tail:
            parts.append(child.tail)

    raw = "".join(parts)
    raw = html.unescape(raw)
    # Normalise whitespace: collapse runs of spaces/tabs, trim each line,
    # drop empty lines.
    lines = [re.sub(r"[ \t\u00a0]+", " ", ln).strip() for ln in raw.split("\n")]
    lines = [ln for ln in lines if ln]
    return "\n".join(lines)


def _get_cell(shape_el: ET.Element, name: str) -> float | None:
    for cell in shape_el.findall(f"{NS}Cell"):
        if cell.get("N") == name:
            try:
                return float(cell.get("V"))
            except (TypeError, ValueError):
                return None
    return None


# --------------------------------------------------------------------------- #
# Page parsing
# --------------------------------------------------------------------------- #
def _collect_shapes(
    shapes_el: ET.Element,
    page: Page,
    offset_x: float,
    offset_y: float,
) -> None:
    """Recursively collect shapes, descending into Visio Group shapes.

    A flowchart's nodes are frequently nested inside one or more <Shape
    Type='Group'> containers, each with its own <Shapes> list. Child shapes
    store their PinX/PinY relative to the group origin, so we accumulate the
    parent offset to keep absolute coordinates for left-to-right ordering.
    """
    for shape_el in shapes_el.findall(f"{NS}Shape"):
        sid = shape_el.get("ID")
        if sid is None:
            continue
        local_x = _get_cell(shape_el, "PinX") or 0.0
        local_y = _get_cell(shape_el, "PinY") or 0.0
        abs_x = offset_x + local_x
        abs_y = offset_y + local_y

        shp = Shape(
            sid=sid,
            text=extract_shape_text(shape_el),
            pin_x=abs_x,
            pin_y=abs_y,
            width=_get_cell(shape_el, "Width") or 0.0,
            height=_get_cell(shape_el, "Height") or 0.0,
        )
        page.shapes[sid] = shp

        # Descend into nested group children. The group's local pin (minus its
        # LocPin) is the origin for its children's coordinates.
        child_shapes_el = shape_el.find(f"{NS}Shapes")
        if child_shapes_el is not None:
            loc_x = _get_cell(shape_el, "LocPinX") or 0.0
            loc_y = _get_cell(shape_el, "LocPinY") or 0.0
            _collect_shapes(
                child_shapes_el, page, abs_x - loc_x, abs_y - loc_y
            )


def parse_page(xml_bytes: bytes, page_name: str) -> Page:
    page = Page(name=page_name)
    root = ET.fromstring(xml_bytes)

    shapes_el = root.find(f"{NS}Shapes")
    if shapes_el is not None:
        _collect_shapes(shapes_el, page, 0.0, 0.0)

    # Build edges from the <Connects> table.
    connects_el = root.find(f"{NS}Connects")
    by_connector: dict[str, Edge] = {}
    if connects_el is not None:
        for c in connects_el.findall(f"{NS}Connect"):
            cid = c.get("FromSheet")
            from_cell = c.get("FromCell") or ""
            to_sheet = c.get("ToSheet")
            if cid is None or to_sheet is None:
                continue
            edge = by_connector.setdefault(cid, Edge(connector_id=cid))
            if from_cell.startswith("Begin"):
                edge.source = to_sheet
            elif from_cell.startswith("End"):
                edge.target = to_sheet

    for cid, edge in by_connector.items():
        connector_shape = page.shapes.get(cid)
        if connector_shape is not None:
            connector_shape.is_connector = True
            edge.label = connector_shape.text
        page.edges.append(edge)

    return page


def read_pages(zf: zipfile.ZipFile) -> list[tuple[str, str]]:
    """Return a list of (page_name, page_part_path) in document order."""
    names = zf.namelist()
    pages_part = "visio/pages/pages.xml"
    if pages_part not in names:
        # Fall back: just use page*.xml files we can find.
        page_files = sorted(
            n for n in names if re.match(r"visio/pages/page\d+\.xml$", n)
        )
        return [(f"Page-{i + 1}", p) for i, p in enumerate(page_files)]

    # Map relationship id -> target part.
    rels_path = "visio/pages/_rels/pages.xml.rels"
    rel_map: dict[str, str] = {}
    if rels_path in names:
        rels_root = ET.fromstring(zf.read(rels_path))
        for rel in rels_root.findall(f"{REL_NS}Relationship"):
            rid = rel.get("Id")
            target = rel.get("Target")
            if rid and target:
                rel_map[rid] = f"visio/pages/{target}"

    result: list[tuple[str, str]] = []
    root = ET.fromstring(zf.read(pages_part))
    for i, page_el in enumerate(root.findall(f"{NS}Page")):
        name = page_el.get("Name") or page_el.get("NameU") or f"Page-{i + 1}"
        rel_el = page_el.find(f"{NS}Rel")
        target = None
        if rel_el is not None:
            rid = rel_el.get(
                "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"
            )
            target = rel_map.get(rid) if rid else None
        if target is None:
            # Best-effort fallback by index.
            guess = f"visio/pages/page{i + 1}.xml"
            target = guess if guess in names else None
        if target and target in names:
            result.append((name, target))
    return result


# --------------------------------------------------------------------------- #
# Flow rendering
# --------------------------------------------------------------------------- #
def _indent_text(text: str, pad: str) -> str:
    """Indent continuation lines of a multi-line label."""
    lines = text.split("\n")
    if len(lines) == 1:
        return lines[0]
    head = lines[0]
    rest = [pad + "    " + ln for ln in lines[1:]]
    return "\n".join([head] + rest)


def render_flow(page: Page) -> str:
    nodes = {
        sid: s
        for sid, s in page.shapes.items()
        if not s.is_connector and s.text.strip()
    }
    # Connectors with no text and no node text are ignored.

    out_edges: dict[str, list[Edge]] = {sid: [] for sid in nodes}
    in_degree: dict[str, int] = {sid: 0 for sid in nodes}
    for e in page.edges:
        if e.source in nodes and e.target in nodes:
            out_edges[e.source].append(e)
            in_degree[e.target] += 1

    # Order each node's outgoing edges left-to-right (by target PinX) so the
    # branches read consistently.
    for sid in out_edges:
        out_edges[sid].sort(key=lambda e: nodes[e.target].pin_x)

    connected = {
        sid
        for sid in nodes
        if out_edges[sid] or in_degree[sid] > 0
    }
    isolated = [sid for sid in nodes if sid not in connected]

    # Start nodes: connected nodes with no incoming edge. Prefer the topmost.
    starts = [
        sid for sid in connected if in_degree.get(sid, 0) == 0 and out_edges[sid]
    ]
    starts.sort(key=lambda sid: -nodes[sid].pin_y)
    if not starts and connected:
        # Cyclic graph with no clear start: pick the topmost connected node.
        starts = [max(connected, key=lambda sid: nodes[sid].pin_y)]

    lines: list[str] = []
    visited: set[str] = set()

    def emit_node(sid: str, indent: int, edge_label: str) -> None:
        pad = "    " * indent
        node = nodes[sid]
        label_prefix = f"[{edge_label.strip()}] " if edge_label.strip() else ""
        outs = out_edges.get(sid, [])

        if sid in visited:
            lines.append(
                f"{pad}{label_prefix}(go to) "
                + _indent_text(node.text, pad)
            )
            return

        visited.add(sid)
        is_decision = len(outs) > 1
        tag = "DECISION: " if is_decision else ""
        lines.append(f"{pad}{label_prefix}{tag}" + _indent_text(node.text, pad))

        if not outs:
            lines.append(f"{pad}    -> END")
            return

        if is_decision:
            for e in outs:
                branch_label = e.label.strip() or "(unlabeled)"
                lines.append(f"{pad}  - IF {branch_label}:")
                emit_node(e.target, indent + 2, "")
        else:
            emit_node(outs[0].target, indent, outs[0].label)

    if starts:
        lines.append("PROCESS FLOW")
        lines.append("-" * 60)
    for i, start in enumerate(starts):
        if i > 0:
            lines.append("")
        lines.append("START")
        emit_node(start, 0, "")

    # Any connected nodes not reached (separate sub-graphs / orphan targets).
    unreached = [
        sid for sid in connected if sid not in visited
    ]
    unreached.sort(key=lambda sid: -nodes[sid].pin_y)
    if unreached:
        lines.append("")
        lines.append("OTHER CONNECTED STEPS (not reachable from a start node)")
        lines.append("-" * 60)
        for sid in unreached:
            emit_node(sid, 0, "")

    # Isolated text blocks: titles, scope notes, legends, callouts.
    if isolated:
        isolated.sort(key=lambda sid: -nodes[sid].pin_y)
        notes_lines: list[str] = []
        for sid in isolated:
            notes_lines.append("- " + _indent_text(nodes[sid].text, ""))
        if lines:
            lines.append("")
        lines.append("NOTES / STANDALONE TEXT")
        lines.append("-" * 60)
        lines.extend(notes_lines)

    return "\n".join(lines).rstrip() + "\n"


def vsdx_to_text(path: str) -> str:
    with zipfile.ZipFile(path) as zf:
        pages = read_pages(zf)
        blocks: list[str] = []
        title = os.path.splitext(os.path.basename(path))[0]
        blocks.append(title)
        blocks.append("=" * len(title))
        blocks.append("")
        for page_name, part in pages:
            page = parse_page(zf.read(part), page_name)
            if len(pages) > 1:
                blocks.append(f"## Page: {page_name}")
                blocks.append("")
            blocks.append(render_flow(page))
        return "\n".join(blocks).rstrip() + "\n"


# --------------------------------------------------------------------------- #
# .vsd handling via LibreOffice
# --------------------------------------------------------------------------- #
def find_soffice() -> str | None:
    candidates = [
        shutil.which("soffice"),
        shutil.which("soffice.exe"),
        r"C:\Program Files\LibreOffice\program\soffice.exe",
        r"C:\Program Files (x86)\LibreOffice\program\soffice.exe",
        "/usr/bin/soffice",
        "/opt/libreoffice/program/soffice",
        "/Applications/LibreOffice.app/Contents/MacOS/soffice",
    ]
    for c in candidates:
        if c and os.path.exists(c):
            return c
    return None


def convert_vsd_to_vsdx(path: str, soffice: str) -> str | None:
    tmp = tempfile.mkdtemp(prefix="visio_conv_")
    try:
        subprocess.run(
            [soffice, "--headless", "--convert-to", "vsdx", "--outdir", tmp, path],
            check=True,
            capture_output=True,
            timeout=180,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(f"  ! LibreOffice conversion failed: {exc}", file=sys.stderr)
        shutil.rmtree(tmp, ignore_errors=True)
        return None
    base = os.path.splitext(os.path.basename(path))[0] + ".vsdx"
    out = os.path.join(tmp, base)
    return out if os.path.exists(out) else None


# --------------------------------------------------------------------------- #
# Driver
# --------------------------------------------------------------------------- #
def collect_inputs(target: str) -> list[str]:
    if os.path.isdir(target):
        files: list[str] = []
        for entry in sorted(os.listdir(target)):
            if entry.lower().endswith((".vsd", ".vsdx")):
                files.append(os.path.join(target, entry))
        return files
    return [target]


def process_file(path: str, out_dir: str, soffice: str | None) -> bool:
    name = os.path.basename(path)
    print(f"Processing: {name}")
    ext = os.path.splitext(path)[1].lower()

    cleanup_dir: str | None = None
    work_path = path
    if ext == ".vsd":
        if not soffice:
            print(
                "  ! Skipped: .vsd is the old binary format and LibreOffice "
                "(soffice) was not found. Install LibreOffice or save the file "
                "as .vsdx in Visio.",
                file=sys.stderr,
            )
            return False
        converted = convert_vsd_to_vsdx(path, soffice)
        if not converted:
            print("  ! Skipped: conversion to .vsdx did not produce a file.",
                  file=sys.stderr)
            return False
        work_path = converted
        cleanup_dir = os.path.dirname(converted)

    try:
        text = vsdx_to_text(work_path)
    except Exception as exc:  # noqa: BLE001 - report and continue with others
        print(f"  ! Failed to parse: {exc}", file=sys.stderr)
        if cleanup_dir:
            shutil.rmtree(cleanup_dir, ignore_errors=True)
        return False

    os.makedirs(out_dir, exist_ok=True)
    out_name = os.path.splitext(name)[0] + ".txt"
    out_path = os.path.join(out_dir, out_name)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"  -> {out_path}")

    if cleanup_dir:
        shutil.rmtree(cleanup_dir, ignore_errors=True)
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert Visio (.vsd/.vsdx) process diagrams to plain text."
    )
    parser.add_argument(
        "input",
        nargs="?",
        default="input",
        help="A .vsd/.vsdx file or a folder of them (default: ./input).",
    )
    parser.add_argument(
        "--out",
        default="output",
        help="Output folder for the .txt files (default: ./output).",
    )
    args = parser.parse_args(argv)

    if not os.path.exists(args.input):
        print(f"Input not found: {args.input}", file=sys.stderr)
        return 2

    inputs = collect_inputs(args.input)
    if not inputs:
        print(f"No .vsd/.vsdx files found in: {args.input}", file=sys.stderr)
        return 1

    soffice = find_soffice()
    if any(f.lower().endswith(".vsd") for f in inputs) and not soffice:
        print(
            "Note: .vsd files detected but LibreOffice (soffice) was not found; "
            "those files will be skipped.\n",
            file=sys.stderr,
        )

    ok = 0
    for f in inputs:
        if process_file(f, args.out, soffice):
            ok += 1

    print(f"\nDone. {ok}/{len(inputs)} file(s) converted into '{args.out}'.")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
