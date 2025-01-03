#!/bin/bash

set -euo pipefail

inline_file() {
  local source_file_basename=$1
  local source_file=styles/$source_file_basename
  local target_file=$2

  local begin_marker="{{{ $source_file_basename\$"
  local end_marker="}}} $source_file_basename\$"

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
  "nav.css"
  "theme.css"
)

for file in "${files[@]}"; do
  inline_file "$file" print-epub.sh
done
