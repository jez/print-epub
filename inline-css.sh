#!/bin/bash

set -euo pipefail

inline_file() {
  local source_file=$1
  local target_file=$2

  begin_marker="{{{ $source_file\$"
  end_marker="}}} $source_file\$"
  sed -i.bak -e "
    /$begin_marker/,/$end_marker/ {
      /$begin_marker/ {
        p
        i\\
    cat <<'EOF'
        r $source_file
        a\\
  EOF
      }
      /$end_marker/p
      d
    }" "$target_file"

  rm -f "$target_file.bak"
  echo "inlined: $source_file"
}

files=(
  "styles/nav.css"
  "styles/theme.css"
)

for file in "${files[@]}"; do
  inline_file "$file" print-epub.sh
done
