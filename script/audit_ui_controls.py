#!/usr/bin/env python3
"""Fail fast on obviously inert controls; this is not a substitute for GUI tests.

Checks production SwiftUI source for literal empty click handlers (including
Button, ThemeButton, onTapGesture, onSubmit) and prints a review inventory.
It cannot infer user intent, verify OS permissions or click every control.
"""
from collections import Counter
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent / "Housekeeping" / "Sources"
files = sorted(root.rglob("*.swift"))
if not files:
    sys.exit("No application Swift files found")

# These patterns intentionally match only unambiguous no-op closures. More
# ambitious regex parsing would misread nested SwiftUI view builders, comments,
# interpolated strings and conditional compilation.
empty_patterns = [
    re.compile(r"\b(?:Button|ThemeButton)\s*\([^\n]*\)\s*\{\s*\}", re.MULTILINE),
    re.compile(r"\bButton\s*\{\s*\}", re.MULTILINE),
    re.compile(r"\baction\s*:\s*\{\s*\}", re.MULTILINE),
    re.compile(r"\.on(?:TapGesture|Submit|Change)\s*(?:\([^)]*\))?\s*\{\s*\}", re.MULTILINE),
]
counts = Counter()
failures = []
for file in files:
    text = file.read_text(encoding="utf-8")
    # Leave source positions intact for error lines while removing comments.
    without_comments = re.sub(r"/\*.*?\*/", lambda m: " " * len(m.group()), text, flags=re.S)
    without_comments = re.sub(r"//[^\n]*", lambda m: " " * len(m.group()), without_comments)
    for kind in ("Button", "ThemeButton", "Toggle", "Picker", "Menu", "TextField"):
        counts[kind] += len(re.findall(rf"\b{kind}\s*\(", without_comments))
    for pattern in empty_patterns:
        for match in pattern.finditer(without_comments):
            line = without_comments.count("\n", 0, match.start()) + 1
            failures.append(f"{file.relative_to(root)}:{line}: inert handler: {match.group()[:100]!r}")

for kind, count in sorted(counts.items()):
    print(f"{kind}: {count}")
if failures:
    sys.exit("Obvious no-op controls found:\n" + "\n".join(failures))

print(f"No literal empty actions found in {len(files)} Swift source files.")
print("This checks only static no-ops. Manual real-device interaction and accessibility tests remain mandatory.")
