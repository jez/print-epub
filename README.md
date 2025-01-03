# print-epub.sh

Convert EPUB3 to PDF by simulating printing it with [PrinceXML].

## Installation

1.  `print-epub.sh` requires two tools on your system:

    - [`prince-books`] or [`prince`]

      This tool is used to convert the XHTML inside an PUB into a PDF. See
      <https://www.princexml.com/download/> and
      <https://www.princexml.com/books/>.

      At the time of writing, PrinceXML is free to download for testing purposes
      and for non-commercial use. The free version generates PDFs with a Prince
      logo in a PDF "note" annotation on the first page. It can be deleted in
      PDF readers that allow editing annotations (like macOS Preview).

    - [`xq`]

      See <https://github.com/sibprogrammer/xq>. This tool allows using XPath
      expressions to extract text from XML files, like those which store
      metadata about an EPUB's structure.

      (If you have suggestions for alternative tools, please open an issue to
      outline why another tool might be better at this.)

      `xq` is released under the MIT License.

    If you have these tools on your system but not on your `$PATH`, see the
    `--prince` and `--xq` options when invoking `print-epub.sh` below.

2.  Download `print-epub.sh` and ensure that it's executable. Ensure that the
    result is available on your `$PATH`. For example, if `~/.local/bin` is on
    your `$PATH`:

    ```
    curl -O https://raw.githubusercontent.com/jez/print-epub/refs/heads/master/print-epub.sh
    chmod +x print-epub.sh
    mv print-epub.sh ~/.local/bin/print-epub.sh
    ```

    Only this file need be downloaded. (The script requires various CSS
    resources, but they are included as strings inside the script.)

## Usage

The most simple usage looks like:

```
print-epub.sh book.epub
```

which will generate `book.pdf` in the current directory. For full usage, see
`print-epub.sh --help`, reproduced below.

```
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
```

## Versus alternatives

Two main alternatives exist:

- `pandoc`

  [Pandoc] does not convert from `epub` to `pdf` directly. It first converts to
  `html`, by stitching the individual chapters of the book together into one big
  file. In the process, `pandoc` normalizes the underlying XHTML which makes
  up the EPUB to Pandoc's internal document representation, which is lossy. For
  example, the EPUB's declared table of contents is not present in this internal
  representation, which means it is not in the HTML representation. Instead, the
  generated PDF relies on the PDF engine's attempt to infer a table of contents
  from headings, which might not be in the same hierarchy as the EPUB's table of
  contents.

  Roundtripping through an internal representation is also slow: for an EPUB
  with 3.6MB of unzipped text, `pandoc` takes 6 sec on my machine—unzipping and
  concatenating takes 700 ms, adding time to the overall PDF generation
  process.

  Having created HTML, it then hands that off to a PDF engine to create the PDF.
  The default PDF engine at the time of writing is WeasyPrint, an HTML to PDF
  rendering pipeline not based on an existing browser engine (like WebKit or
  Gecko).

- `ebook-convert` (CLI interface to Calibre's default EPUB → PDF plugin)

  Calibre first converts the EPUB is into its internal "open ebook"
  representation (essentially: an EPUB2 book that's been unzipped). Various
  benign transformations are done on the book at this point, like replacing
  `&#....;` character entities with real Unicode characters, various kinds of
  pretty printing, inserting `div`'s and `span`'s to force page and chapter
  breaks in various places.

  Calibre's EPUB → PDF conversion pipeline is built to assume the worst about
  the PDFs it takes in. For example: it has various command line options which
  allow ad hoc modifications to things like the table of contents, to work
  around poorly crafted EPUBs.

  But by far the most invasive transformation Calibre does it to munge all the
  CSS included in internal stylesheets so that all styles are expressed as
  `.css-class { ... }`. The post-processed CSS drops all the more complicated
  CSS selectors. This has the effect of throwing out large swaths of valid
  styles. This is probably useful for old EPUB readers that have misbehaving CSS
  rendering algorithms, but does not apply to any ebook reader I use, nor to any
  PDF rendering engine I use.

  For the PDF rendering itself, Calibre invokes Qt's `QWebEnginePage`, which is
  a wrapper around headless Chromium. Chromium is notoriously bad at generating
  PDFs: ligatures in the generated PDF are not selectable or searchable, the
  text layout algorithm does hyphenation and line breaking poorly (designed for
  fast page loads, not optimal layout), etc.

By contrast, `print-epub.sh`:

- uses [PrinceXML], specifically Prince for Books which means:
  - line breaks and hyphenation choices are much better than WebKit, rivaling
    desktop publishing software
  - ligatures are selectable, searchable, copyable etc. as if they were the
    underlying characters.
- uses Prince's support for [PDF bookmarks] to translate the EPUB's native table
  of contents to a PDF outline.
- does not touch the EPUB's original CSS, meaning it's allowed to style the
  final PDF, preserving layout choices the EPUB's author made.

Some downsides of this approach:

- The actual PDF generation can take a while for large PDFs, as the line
  breaking and hyphenation algorithms are much more expensive (all the more
  reason why it's important to save time in the pre-processing phase).
- It requires an EPUB3 ebook. If you don't already have one, consider using
  Calibre to convert to EPUB3. The main difference is the structure of the
  EPUB's table of contents. In EPUB2, it's specified using a custom XML schema.
  In EPUB3, it's specified with XHTML, which means we can style it with CSS, in
  particular the CSS that Prince uses to declare [PDF bookmarks].
- It assumes that the EPUB's typesetting choices are good. This might not be
  true for all books.

## TODO

- [ ] Accept a path to where it's already been unzipped, to make it easier to
  munge the EPUB itself before generating a PDF.
- [ ] Figure out how to deal with Unicode font fallback in PrinceXML.
  - <https://www.princexml.com/forum/topic/5101/font-fallback-doesnt-happen-for-generic-fonts-if-specifying>
  - This doesn't affect the tool overall, it affects my personal `fonts.css`
    choices.
- [ ] Support for EPUB2-style NCX table of contents?

## License

[![MIT License](https://img.shields.io/badge/license-BlueOak-blue.svg)](https://jez.io/blueoak-license/)

Blue Oak Model License, Version 1.0.0

[Pandoc]: https://pandoc.org/
[PrinceXML]: https://www.princexml.com/
[PDF bookmarks]: https://www.princexml.com/doc/prince-output/#pdf-bookmarks
