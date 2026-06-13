;;; rex-mode.el — Emacs major mode for Rex V5.0
;;
;; Installation (manual):
;;   (load "/path/to/rex-mode.el")
;;   (add-to-list 'auto-mode-alist '("\\.rex\\'" . rex-mode))
;;
;; Installation (use-package):
;;   (use-package rex-mode
;;     :load-path "/path/to/editors/"
;;     :mode "\\.rex\\'")
;;
;; LSP integration:
;;   - With lsp-mode:   M-x lsp  (auto-detected when rex-mode is active)
;;   - With eglot:      M-x eglot  (auto-detected)
;;
;; Prerequisites:
;;   - `rex` binary on PATH  (sudo make install)

;;; Code:

(require 'font-lock)

;; ─── Syntax table ─────────────────────────────────────────────────────────────

(defvar rex-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; Line comments: // ...
    (modify-syntax-entry ?/ ". 124b" table)
    (modify-syntax-entry ?\n "> b" table)
    ;; Block comments: /* ... */
    (modify-syntax-entry ?* ". 23"  table)
    ;; String delimiter
    (modify-syntax-entry ?\" "\"" table)
    ;; Single-char delimiter
    (modify-syntax-entry ?' "\"" table)
    ;; Identifier characters
    (modify-syntax-entry ?_ "w" table)
    table)
  "Syntax table for `rex-mode'.")

;; ─── Keywords ─────────────────────────────────────────────────────────────────

(defconst rex-keywords
  '("if" "elif" "else" "for" "while" "each" "repeat" "blast" "pipe"
    "stop" "skip" "pass" "return" "prot" "when" "is" "use" "mm" "gc"
    "arena" "pool" "and" "or" "not" "in" "as" "import" "from"
    "output" "err" "input" "push" "pop" "len" "cap" "typeof" "abs" "swap"
    "assert" "unreachable")
  "Rex control flow and builtin keywords.")

(defconst rex-types
  '("int" "float" "bool" "str" "char" "byte" "seq" "dict" "set" "tup"
    "const" "volatile")
  "Rex type keywords.")

(defconst rex-constants
  '("true" "false" "maybe")
  "Rex boolean/tristate constants.")

(defconst rex-decorators
  '("#memo" "#hot" "#inline" "#unsafe")
  "Rex decorator annotations.")

;; ─── Font lock rules ──────────────────────────────────────────────────────────

(defconst rex-font-lock-keywords
  `(
    ;; Doc comments: /// ...
    ("///.*$" . font-lock-doc-face)
    ;; Line comments: // ...
    ("//[^/].*$" . font-lock-comment-face)
    ;; Decorators: #memo #hot etc.
    (,(regexp-opt rex-decorators 'words) . font-lock-preprocessor-face)
    ;; Type names
    (,(regexp-opt rex-types 'words) . font-lock-type-face)
    ;; Constants: true false maybe
    (,(regexp-opt rex-constants 'words) . font-lock-constant-face)
    ;; Keywords
    (,(regexp-opt rex-keywords 'words) . font-lock-keyword-face)
    ;; Protocol calls: @name(
    ("@\\([a-zA-Z_][a-zA-Z0-9_.]*\\)" 1 font-lock-function-name-face)
    ;; Protocol definitions: prot name(
    ("\\bprot\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1 font-lock-function-name-face)
    ;; Write-site mutation sigil:  :varname
    (":\\([a-zA-Z_][a-zA-Z0-9_]*\\)\\s-*=" 1 font-lock-warning-face)
    ;; Number literals (including hex/bin/octal)
    ("\\b\\(0x[0-9a-fA-F_]+\\|0b[01_]+\\|0o[0-7_]+\\|[0-9][0-9_]*\\(\\.[0-9_]+\\)?\\)\\b"
     . font-lock-constant-face)
    )
  "Font lock rules for `rex-mode'.")

;; ─── Indentation ──────────────────────────────────────────────────────────────

(defun rex-indent-line ()
  "Indent current line for Rex source."
  (let ((indent (rex-calculate-indent)))
    (save-excursion
      (back-to-indentation)
      (delete-region (line-beginning-position) (point))
      (indent-to indent))
    (when (< (point) (save-excursion (back-to-indentation) (point)))
      (back-to-indentation))))

(defun rex-calculate-indent ()
  "Calculate indentation level for the current line."
  (save-excursion
    (let ((indent 0))
      (beginning-of-line)
      ;; Find the previous non-blank line
      (when (re-search-backward "^[[:space:]]*[^[:space:]\n]" nil t)
        (back-to-indentation)
        (setq indent (current-column))
        ;; If previous line ends with ':', increase indent
        (end-of-line)
        (when (looking-back ":[[:space:]]*" nil)
          (setq indent (+ indent 4))))
      ;; If current line starts with else/elif, decrease indent
      (goto-char (save-excursion (beginning-of-line) (point)))
      (back-to-indentation)
      (when (looking-at "\\(else\\|elif\\)\\b")
        (setq indent (max 0 (- indent 4))))
      indent)))

;; ─── Mode definition ──────────────────────────────────────────────────────────

;;;###autoload
(define-derived-mode rex-mode prog-mode "Rex"
  "Major mode for editing Rex V5.0 source files."
  :syntax-table rex-mode-syntax-table
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "//+\\s-*")
  (setq-local font-lock-defaults '(rex-font-lock-keywords))
  (setq-local indent-line-function #'rex-indent-line)
  (setq-local tab-width 4)
  (setq-local indent-tabs-mode nil))

;; ─── LSP integration ──────────────────────────────────────────────────────────

;; lsp-mode integration
(with-eval-after-load 'lsp-mode
  (add-to-list 'lsp-language-id-configuration '(rex-mode . "rex"))
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection '("rex" "lsp"))
    :activation-fn (lsp-activate-on "rex")
    :server-id 'rex-lsp
    :priority -1)))

;; eglot integration
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(rex-mode . ("rex" "lsp"))))

;; Auto-detect .rex files
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.rex\\'" . rex-mode))

(provide 'rex-mode)
;;; rex-mode.el ends here
