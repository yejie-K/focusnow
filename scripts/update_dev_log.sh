#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

output_file="$repo_root/docs/开发日志.md"
tmp_file="$(mktemp)"

cat > "$tmp_file" <<'EOF'
# 开发日志

这个文件由 `scripts/update_dev_log.sh` 自动生成。

按提交时间倒序记录日常开发变更。
EOF

python3 - "$repo_root" "$tmp_file" <<'PY'
import subprocess
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
tmp_file = Path(sys.argv[2])

try:
    raw = subprocess.check_output(
        [
            "git",
            "-c",
            "core.quotePath=false",
            "-C",
            str(repo_root),
            "log",
            "--date=format:%Y-%m-%d %H:%M",
            "--pretty=format:__ENTRY__%n%ad%n%s",
            "--name-only",
        ],
        text=True,
    )
except subprocess.CalledProcessError:
    raw = ""

entries = [chunk.strip() for chunk in raw.split("__ENTRY__") if chunk.strip()]

with tmp_file.open("a", encoding="utf-8") as f:
    for entry in entries:
        lines = [line.rstrip() for line in entry.splitlines()]
        if len(lines) < 2:
            continue

        date = lines[0].strip()
        subject = lines[1].strip()
        files = []
        for file in lines[2:]:
            file = file.strip()
            if not file or file == "docs/开发日志.md":
                continue
            files.append(file)

        if ":" in subject:
            change_type, summary = subject.split(":", 1)
            change_type = change_type.strip()
            summary = summary.strip()
        else:
            change_type = "misc"
            summary = subject

        f.write(f"\n## {date} | {change_type}\n\n")
        f.write(f"{summary}\n\n")
        if files:
            f.write("涉及文件\n\n")
            for file in files:
                f.write(f"- {file}\n")
            f.write("\n")
PY

mv "$tmp_file" "$output_file"
