(in-package :cl-cli/test)

;; Reuses MANPAGE-DEMO-APP (defined in t/cases-doc-manpage.lisp): a
;; version'd, summarized app with a count option, a hidden option, a command
;; with its own option + positional, a hidden command, and an example.

(defun markdown-text (app)
  (with-string-output (stream)
    (render-markdown app stream)))

(describe-sequential "markdown renderer"
  (it "renders a title, summary blockquote, version, and description"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-searches text "# demo"
                       "> Demo build tool."
                       "**Version:** 1.2.0"
                       "A longer description of demo.")))

  (it "renders a fenced usage block with the dispatch synopsis"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-searches text "## Usage" "demo [global-options] <command> [args]")))

  (it "renders an options table with a code-spanned token and metadata"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-searches text "## Options"
                       "| Option | Description |"
                       "`--verbose, -v`"
                       "(count)")))

  (it "omits hidden options from the options table"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-not-searches text "secret")))

  (it "renders a per-command section with synopsis, positionals, and options"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-searches text "## Commands"
                       "### `compile`"
                       "Compile sources."
                       "demo compile [options] INPUT"
                       "`INPUT`"
                       "`--output, -o <OUTPUT>`")))

  (it "omits hidden commands from the document"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-not-searches text "sneaky" "Should not appear")))

  (it "renders an examples section in a fenced block"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-searches text "## Examples" "demo compile src/main.lisp")))

  (it "escapes a pipe inside a table cell"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "sep"
                                                             :kind :value
                                                             :description "left | right"))))
           (text (markdown-text app)))
      (assert-searches text "left \\| right")))

  (it "escapes a pipe in the code-span column too, not just the description"
    ;; The test above covers the description column, which goes through
    ;; %MD-ESCAPE-CELL. The first column goes through %MD-INLINE-CODE, and a
    ;; code span is no shelter from GFM's cell splitting -- verified against
    ;; cmark-gfm, GitHub's own renderer, which turned this row into
    ;; `<td>`--fmt &lt;json</td><td>yaml</td>`: code span destroyed, `toml>`
    ;; lost, description column dropped entirely. `<json|yaml|toml>` is an
    ;; idiomatic value name, so this is easy to hit by accident.
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "fmt"
                                                             :kind :value
                                                             :value-name "json|yaml|toml"
                                                             :description "Output format."))))
           (text (markdown-text app)))
      (assert-searches text "| `--fmt <json\\|yaml\\|toml>` | Output format. |")))

  (it "keeps the pipe escape scoped to table cells"
    ;; Asserted on the two helpers rather than through a spec, because no spec
    ;; can reach the non-cell path with a pipe: command names are validated to
    ;; letters, digits, '-', '_' and '.', so the one other %MD-INLINE-CODE
    ;; caller (the per-command heading) cannot receive one. The distinction
    ;; still has to hold -- a heading is not a cell, and `\|` there would
    ;; render as a literal backslash rather than a pipe.
    (expect (string= (cl-cli::%md-inline-code "a|b") "`a|b`"))
    (expect (string= (cl-cli::%md-inline-code-cell "a|b") "`a\\|b`")))

  (it "escapes raw HTML and Markdown controls in prose metadata"
    (let* ((app (make-app :name "tool"
                          :version "<b>2.0</b> *beta*"
                          :description "<img src=x onerror=alert(1)> [docs](javascript:alert(1))"
                          :commands (list (make-command
                                           :name "run"
                                           :description "Run <script>alert(1)</script>"
                                           :help-footer "See [unsafe](javascript:alert(1))."))))
           (text (markdown-text app)))
      (assert-searches text
                       "**Version:** &lt;b&gt;2.0&lt;/b&gt; \\*beta\\*"
                       "&lt;img src=x onerror=alert(1)&gt;"
                       "\\[docs\\](javascript:alert(1))"
                       "Run &lt;script&gt;alert(1)&lt;/script&gt;"
                       "See \\[unsafe\\](javascript:alert(1)).")
      (assert-not-searches text
                           "<img"
                            "<script>"
                            "<b>2.0</b>"
                            "[docs](javascript:alert(1))")))

  (it "strips control characters and uses delimiter-safe Markdown fences"
    (let* ((escape (string (code-char 27)))
           (app (make-app :name "tool"
                          :description (format nil "safe~Atext" escape)
                          :examples (list "echo ``` cannot close fence")))
           (text (markdown-text app)))
      (assert-searches text
                       "safetext"
                       "````"
                       "echo ``` cannot close fence")
      (assert-not-searches text escape)))

  (it "counts a backtick run across a dropped control character but not across a space-mapped one"
    ;; CL-CLI::%MD-MAX-BACKTICK-RUN replicates %MD-CONTROL-SAFE-STRING's
    ;; character mapping while counting, instead of building the safe string
    ;; first and counting on that -- a regression here would silently pick a
    ;; too-short backtick fence/code-span delimiter. A true control character
    ;; (e.g. ESC) is DROPPED entirely by control-safety, so two backticks
    ;; either side of one become adjacent in the final output and must count
    ;; as a run of 2; a newline/return/tab is instead MAPPED to a space, which
    ;; sits between the backticks in the output, so each stays its own run of 1.
    (let ((escape (string (code-char 27))))
      (expect (= 2 (cl-cli::%md-max-backtick-run
                    (list (format nil "`~A`" escape)))))
      (expect (= 1 (cl-cli::%md-max-backtick-run
                    (list (format nil "`~%`")))))))

  (it "uses delimiter-safe Markdown code spans for value names"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "template"
                                                             :kind :value
                                                             :value-name "VA`L"
                                                             :description "Template."))))
           (text (markdown-text app)))
      (assert-searches text "``--template <VA`L>``")))

  (it "renders an arguments table for a flat positional app"
    (let* ((app (make-app :name "script"
                          :positionals (list (make-positional :key :file
                                                              :required-p t
                                                              :description "Target file."))))
           (text (markdown-text app)))
      (assert-searches text "## Arguments" "| Argument | Description |" "`FILE`")))

  (it "returns the document as a string when no stream is given"
    (let ((result (render-markdown (manpage-demo-app))))
      (expect (stringp result))
      (assert-searches result "# demo")))

  (it "returns no values when given a stream"
    (with-string-output (stream)
      (expect (null (multiple-value-list (render-markdown (manpage-demo-app) stream))))))

  (it "escapes a bare ampersand in prose metadata"
    (let* ((app (make-app :name "tool" :description "Fish & Chips"))
           (text (markdown-text app)))
      (assert-searches text "Fish &amp; Chips")
      (assert-not-searches text "Fish & Chips"))))
