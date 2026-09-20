#!/usr/bin/env python3
"""Package the Curie family and its credits for the release download."""

import csv
import io
from pathlib import Path
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parent.parent
output = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "dist"
output.mkdir(parents=True, exist_ok=True)
example = "curie-joliot"
prefix = f"Examples/{example}/"
files = subprocess.check_output(
    ["git", "ls-files", "-z", "--", prefix], cwd=root
).decode().split("\0")
files = [path for path in files if path]
assert f"{prefix}{example}.ged" in files, "Example GEDCOM is missing"

with (root / "Examples/CREDITS.csv").open(newline="", encoding="utf-8") as source:
    reader = csv.DictReader(source)
    columns = reader.fieldnames
    credits = [row for row in reader if row["file"].startswith(f"{example}/")]
credited = {f"Examples/{row['file']}" for row in credits}
media = {path for path in files if "/Media/" in path or "/Attachments/" in path}
assert media <= credited, f"Missing credits: {media - credited}"
credit_text = io.StringIO(newline="")
writer = csv.DictWriter(credit_text, fieldnames=columns)
writer.writeheader()
for row in credits:
    writer.writerow({**row, "file": row["file"].removeprefix(f"{example}/")})

archive = output / "Swarm-Curie-Example.zip"
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
    for path in files:
        bundle.write(root / path, path.removeprefix("Examples/"))
    bundle.writestr(f"{example}/CREDITS.csv", credit_text.getvalue())
    bundle.write(root / "LICENSE", f"{example}/LICENSE")
    bundle.writestr(f"{example}/README.txt", """Try the Curie family in Swarm

Download Swarm: https://github.com/samoilev/swarm/releases/latest
Requires macOS 15 or later.

1. Unpack this ZIP and open Swarm. Choose English on first launch.
2. Click Import GEDCOM and select this entire curie-joliot folder.
3. The preview lists two country names without map coordinates. Check
   Continue with these warnings, then click Import. The tree opens automatically.

Choose the folder rather than the GEDCOM file to include photos and attachments.
Swarm imports a separate copy, so you can safely explore and edit the example.

The example comes from https://github.com/samoilev/swarm/tree/main/Examples
See LICENSE for the project license and CREDITS.csv for each image's source,
attribution and separate license. The image files are unchanged.
""")
with zipfile.ZipFile(archive) as bundle:
    assert bundle.testzip() is None, "Archive verification failed"
print(f"Created {archive} ({len(files)} example files, {len(credits)} image credits)")
