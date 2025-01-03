#!/usr/bin/env bash

set -euo pipefail

# ----- logging & colors -------------------------------------------------- {{{

red=$'\x1b[0;31m'
green=$'\x1b[0;32m'
yellow=$'\x1b[0;33m'
cyan=$'\x1b[0;36m'
cnone=$'\x1b[0m'

USE_COLOR=
if [ -t 1 ]; then
  USE_COLOR=1
fi

# Detects whether we can add colors or not
in_color() {
  local color="$1"
  shift

  if [ -z "$USE_COLOR" ]; then
    echo "$*"
  else
    echo "$color$*$cnone"
  fi
}

success() { echo "$(in_color "$green" "[ OK ]") $*" >&2; }
error()   { echo "$(in_color "$red"   "[ERR!]") $*" >&2; }
info()    { echo "$(in_color "$cyan"  "[ .. ]") $*" >&2; }
fatal()   { error "$@"; exit 1; }
# Color entire message to get users' attention (because we won't stop).
attn()    { in_color "$yellow" "[ .. ] $*" >&2; }

# }}}

# ----- helper functions ------------------------------------------------------

usage() {
  cat <<'EOF'

print-epub.sh: Convert EPUB3 to PDF by simulating printing it with PrinceXML

Usage:
  print-epub.sh [options] <book.epub>

Arguments:
  <book.epub>      The input EPUB3 file

Options:
  -o, --output <book.pdf>
                   The output PDF file [default: same as input, but with 'epub'
                   extension chanaged to 'pdf']
      --prince <path>
                   The path to the prince or prince-books executable
                   [default: prince-books if on $PATH, else prince]
                   (See https://www.princexml.com/)
      --xq         The path to the xq executable [default: xq]
                   (See https://github.com/sibprogrammer/xq)
      --prince-arg <arg>
                   Extra argument to pass to PrinceXML when generating the PDF.
                   May be repeated. Any paths must be absolutely qualified
                   because the working directory will become the unzipped epub
                   during PDF generation. Useful for passing custom CSS
                   stylesheets, in addition to the default used by print-epub.
                   (See https://www.princexml.com/doc/command-line/)
      --no-theme   Omit passing the (opinionated) theme.css file. There are no
                   alternative themes, so you will want to design your own.
      --no-nav     Omit passing the nav.css file. This file uses the various
                   -prince-bookmark-* CSS properties to translate the EPUB's
                   declared table of contents to a PDF outline (aka bookmarks).
                   Certain books artificially constraint their table of
                   contents, so a custom stylesheet (using --prince-arg) can
                   allow for an even more detailed PDF outline.
  -v, --verbose    Enable verbose debug logging
  -h, --help       Print this help message

Environment variables:
  XDG_CACHE_DIR    Stores CSS files which control PDF output
                   [default: $HOME/.cache]

EOF
}

# ----- option parsing --------------------------------------------------------

input=
output=
prince_exe=prince
if command -v prince-books &> /dev/null; then
  prince_exe=prince-books
fi
xq_exe=xq
prince_args=()
XDG_CACHE_DIR=${XDG_CACHE_DIR:-$HOME/.cache}

while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output)
      output="$2"
      shift
      shift
      ;;
    --prince)
      prince_exe="$2"
      shift
      shift
      ;;
    --xq)
      xq_exe="$2"
      shift
      shift
      ;;
    --prince-arg)
      prince_args+=("$2")
      shift
      shift
      ;;
    -v|--verbose)
      set -x
      shift
      ;;
    -h|--help)
      usage
      exit
      ;;
    -*)
      error "Unrecognized option: $1"
      >&2 usage
      exit 1
      ;;
    *)
      if [ "${input:-}" != "" ]; then
        error "Input specified multiple times: '$input' and '$1'"
        >&2 usage
        exit 1
      fi
      input="$1"
      shift
      ;;
  esac
done

if [ "${input:-}" = "" ]; then
  error "No input epub file specified"
  >&2 usage
  exit 1
fi

if ! [ -f "$input" ]; then
  error "Input file does not exist: $input"
  >&2 usage
  exit 1
fi

if [ "${output:-}" = "" ]; then
  output="$(dirname "$input")/$(basename "$input" .epub).pdf"
  output="${output#./}"
fi

if [[ "$output" != /* ]]; then
  output_abs="$(pwd)/$output"
else
  output_abs="$output"
fi

if ! command -v "$prince_exe" &> /dev/null; then
  error "No suitable prince executable ('$prince_exe')"
  >&2 usage
  exit 1
fi
if [[ "$prince_exe" =~ "/" ]]; then
  prince_exe="$(pwd)/$prince_exe"
fi

# I'm not particularly in love with xq, but it works well enough.
# I just want something that has command-line XPath support.
# If there's a better or more popular option, let's switch to that.
if ! command -v "$xq_exe" &> /dev/null; then
  error "No suitable xq executable ('$xq_exe')"
  >&2 usage
  exit 1
fi
if [[ "$xq_exe" =~ "/" ]]; then
  xq_exe="$(pwd)/$xq_exe"
fi

# ----- cache setup -----------------------------------------------------------

#
# Bump this any time the CSS files change, so that any old caches are busted
#
cache_version=1

cache_dir="$XDG_CACHE_DIR/print-epub"
if [[ "$cache_dir" != /* ]]; then
  cache_dir="$(pwd)/$cache_dir"
fi

mkdir -p "$cache_dir"
if ! [ -f "$cache_dir/version" ] || [ "$(< "$cache_dir/version")" != "$cache_version" ]; then
  info "Evicting cached stylesheets (new cache version: $cache_version)"
  rm -rf "$cache_dir"
  mkdir -p "$cache_dir"
  echo "$cache_version" > "$cache_dir/version"
fi

cache_files=(
  "styles/nav.css"
  "styles/theme.css"
)

mk_styles/nav.css() { # {{{ nav.css
  cat <<'EOF'
@namespace epub url("http://www.idpf.org/2007/ops");

/* Don't use Prince's inferred bookmark levels, because we have nav information */
h1 { prince-bookmark-level: none; }
h2 { prince-bookmark-level: none; }
h3 { prince-bookmark-level: none; }
h4 { prince-bookmark-level: none; }
h5 { prince-bookmark-level: none; }
h6 { prince-bookmark-level: none; }

nav[epub|type="landmarks"],
nav[epub|type="page-list"] {
  display: none;
}

nav[epub|type="toc"] {
  max-height: 0;
  overflow: hidden;
}

/* Convert structure of nav toc to bookmarks. */
[epub|type="toc"] a {
  prince-bookmark-target: attr(href);
}

[epub|type="toc"]
  [epub|type="list"]
  a {
  prince-bookmark-level: 1;
}
[epub|type="toc"]
  [epub|type="list"]
  [epub|type="list"]
  a {
  prince-bookmark-level: 2;
}
[epub|type="toc"]
  [epub|type="list"]
  [epub|type="list"]
  [epub|type="list"]
  a {
  prince-bookmark-level: 3;
}
[epub|type="toc"]
  [epub|type="list"]
  [epub|type="list"]
  [epub|type="list"]
  [epub|type="list"]
  a {
  prince-bookmark-level: 4;
}
[epub|type="toc"]
  [epub|type="list"]
  [epub|type="list"]
  [epub|type="list"]
  [epub|type="list"]
  [epub|type="list"]
  a {
  prince-bookmark-level: 5;
}
[epub|type="toc"]
  [epub|type="list"]
  [epub|type="list"]
  [epub|type="list"]
  [epub|type="list"]
  [epub|type="list"]
  [epub|type="list"]
  a {
  prince-bookmark-level: 6;
}
EOF
} # }}} nav.css
mk_styles/theme.css() { # {{{ theme.css
  cat <<'EOF'
@namespace epub url("http://www.idpf.org/2007/ops");

/**
 * If we want our user-defined stylesheets to behave as if they were specified
 * after all author-defined stylesheets, it's the same as if we mark everything
 * `!important`
 *
 * See https://www.princexml.com/doc/prince-input/#priority-determination
 */

body {
  font-size: 15pt;
}

@page {
  size: 7.75in 10.25in !important;
  margin-bottom: 48pt !important;
  margin-top: 48pt !important;
  margin-right: 48pt !important;
  margin-left: 144pt !important;
}

@page title-page {
  margin: 0 !important;
}

img[epub|type="cover"] {
  height: 10.25in !important;
  width: 7.75in !important;
  object-fit: contain !important;
  page: title-page !important;
  display: block !important;
}

[epub|type="titlepage"] {
  page: title-page !important;

  /* Vertically center on page */
  /* https://www.princexml.com/doc/styling/#margins-of-page-and-column-floats */
  -prince-float: top !important;
  margin: auto 0 !important;
}

p {
  /* This setting can easily double or triple the time it takes to render large PDFs. */
  hyphens: auto !important;
}
EOF
} # }}} theme.css

for file in "${cache_files[@]}"; do
  cache_path="$cache_dir/$file"
  if ! [ -f "$cache_path" ]; then
    mkdir -p "$(dirname "$cache_path")"
    "mk_$file" > "$cache_path"
  fi
done

# ----- main ------------------------------------------------------------------

info "Analyzing and unpacking input"

set +e
mimetype="$(unzip -p "$input" mimetype)"
if [[ $? -ne 0 || "$mimetype" != "application/epub+zip" ]]; then
  fatal "Input missing mimetype. Is it an EPUB3 file?"
fi
set -e

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

unzip -q "$input" -d "$tmpdir"

# TODO(jez) Might be nice to able to resume from here, after unpacking, so that
# you can more easily inspect and munge the contents of the epub after it's
# been unzipped. Maybe extend the script to take either an input file or a path
# to where it's already been unzipped?

container_xml="$tmpdir/META-INF/container.xml"
if ! [ -f "$container_xml" ]; then
  fatal "Failed to find container.xml inside epub. Is it an EPUB3 file?"
fi

package_opf="$tmpdir/$("$xq_exe" "$container_xml" -x '//rootfile/@full-path')"
if ! [ -f "$package_opf" ]; then
  fatal "Failed to find OPF package manifest inside epub. Is it an EPUB3 file?"
fi

package_dir="$(dirname "$package_opf")"
# Since we cd here, all filepaths mentioned in `--prince-args` must be absolute
cd "$package_dir"

# Prepend our --style flags, to allow any `--style` args in `--prince-args` to
# override our styles.
prince_args=(
  "--style" "$cache_dir/styles/nav.css"
  "--style" "$cache_dir/styles/theme.css"
  ${prince_args[@]+"${prince_args[@]}"}
)

spine_items=0
while IFS='' read -r line; do
  prince_args+=("$line")
  spine_items=$(( spine_items + 1 ))
done < <(
  "$xq_exe" -x '//spine/itemref/@idref' "$package_opf" | \
    xargs -n 1 -I'{}' "$xq_exe" -x '//manifest/item[@id="{}"]/@href' "$package_opf"
)

info "Found $spine_items spine items in input"

# This is like `properties~="nav"` in a CSS attribute selector
# https://stackoverflow.com/a/1390680
props_has_nav='contains(concat(" ", normalize-space(@properties), " "), " nav ")'
nav_html="$("$xq_exe" -x "//manifest/item[$props_has_nav]/@href" "$package_opf")"

if ! [ -f "$nav_html" ]; then
  warning "Input does not have a nav.html: PDF will have no outline (bookmarks)"
  warning "Fallback to EPUB2-style NCX table of contents is not implemented."
  info "Try using Calibre or other to convert to EPUB3?"
  # TODO(jez) Consider using XSLT to allow passing toc.ncx directly to prince?
else
  prince_args+=("$nav_html")
fi

title="$("$xq_exe" -x '//metadata/dc:title' "$package_opf")"
if [ "${title:-}" != "" ]; then
  prince_args+=("--pdf-title" "$title")
fi

author="$("$xq_exe" -x '//metadata/dc:creator' "$package_opf")"
if [ "${author:-}" != "" ]; then
  prince_args+=("--pdf-author" "$author")
fi

prince_args+=(
  "--output"
  "$output_abs"
)

info "Generating PDF with Prince (will take a while for large books)"
"$prince_exe" "${prince_args[@]}"

success "Generated $output"

# vim:fdm=marker
