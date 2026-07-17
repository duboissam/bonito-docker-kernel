#!/usr/bin/env bash
set -euo pipefail

dest="${1:-/usr/local/bin/mkdtimg}"
tmp_bin="$(mktemp)"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -f "$tmp_bin"
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

curl -fsSL 'https://android.googlesource.com/platform/system/libufdt/+/refs/heads/android10-release/utils/src/mkdtboimg.py?format=TEXT' \
  | base64 --decode >"$tmp_bin"

python3 - "$tmp_bin" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
text = p.read_text()

replacements = [
    (
        "parser.add_argument('conf_file', nargs='?',\n"
        "                        type=argparse.FileType('rb'),",
        "parser.add_argument('conf_file', nargs='?',\n"
        "                        type=argparse.FileType('r'),",
    ),
    (
        '        dt_entry_buf = ""',
        '        dt_entry_buf = b""',
    ),
    (
        "        self.__metadata = array('c', ' ' * self.__metadata_size)",
        "        self.__metadata = array('b', b' ' * self.__metadata_size)",
    ),
    (
        '        if version is 0:',
        '        if version == 0:',
    ),
]

for old, new in replacements:
    if old not in text:
        raise SystemExit(f"mkdtimg patch target not found: {old!r}")
    text = text.replace(old, new, 1)

p.write_text(text)
PY

chmod +x "$tmp_bin"

if install -m 0755 "$tmp_bin" "$dest" 2>/dev/null; then
  :
else
  sudo install -m 0755 "$tmp_bin" "$dest"
fi

"$dest" help cfg_create >/dev/null

printf 'not-a-real-dtb-but-good-enough-for-mkdtimg\n' >"$tmp_dir/test.dtbo"
cat >"$tmp_dir/test.cfg" <<'EOF'
  page_size=4096
test.dtbo
  id=0
  rev=0
EOF

"$dest" cfg_create "$tmp_dir/dtbo.img" "$tmp_dir/test.cfg" --dtb-dir "$tmp_dir"
test -s "$tmp_dir/dtbo.img"
