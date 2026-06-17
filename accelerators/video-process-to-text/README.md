# Visio Process → Text

Convert Visio process / flowchart diagrams (`.vsdx` and `.vsd`) into plain-text
**process pseudo information** so they can be ingested by Copilot Studio (or any
other RAG pipeline) which does **not** support Visio files.

The conversion is **fully deterministic** — no LLM is used. The tool reads the
diagram, rebuilds the flow graph from Visio's connector table, and emits a
readable, indented outline with decisions, `YES`/`NO` branches, loops, and any
standalone notes.

## Requirements

- Python 3.10+ (standard library only — no `pip install` needed).
- **Optional:** [LibreOffice](https://www.libreoffice.org/) for the old binary
  `.vsd` format. The tool calls `soffice --headless` to convert `.vsd` → `.vsdx`
  automatically when LibreOffice is installed. Modern `.vsdx` files need nothing
  extra. (Alternatively, open the `.vsd` in Visio and "Save As" `.vsdx`.)

## Usage

```powershell
# Convert every .vsd/.vsdx in ./input  ->  ./output/*.txt
python visio_to_text.py

# Convert a single file
python visio_to_text.py "input/Chylothorax algorithm.vsdx" --out output

# Convert a folder, choosing the output folder
python visio_to_text.py ./diagrams --out ./text
```

Each input diagram produces one `.txt` file with the same base name.

## Output format

```
<Diagram title>
===============

PROCESS FLOW
------------
START
<step text>
DECISION: <question text>
  - IF YES:
        <branch steps...>
  - IF NO:
        <branch steps...>
        -> END

NOTES / STANDALONE TEXT
-----------------------
- <text boxes / legends / scope notes that are not wired into the flow>
```

- `DECISION:` marks a node with more than one outgoing connector.
- `- IF <label>:` uses the connector's own text (e.g. `YES` / `NO`) as the
  branch label; unlabeled connectors show `(unlabeled)`.
- `(go to) <step>` indicates the flow loops back to a step already shown
  (prevents infinite repetition on cyclic diagrams).
- Multi-page diagrams emit a `## Page: <name>` header per page.

## How it works

A `.vsdx` is an OPC (ZIP) package of XML. The tool:

1. Reads `visio/pages/page*.xml` from the package.
2. Extracts every shape's text + geometry.
3. Rebuilds edges from the `<Connects>` table (`BeginX` → source shape,
   `EndX` → target shape); the connector's text becomes the edge label.
4. Walks the graph from its start node(s) to produce the outline above.
