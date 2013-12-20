;;-----------------------------------------------------------------------------
;; BDE CC-Mode Style
;;-----------------------------------------------------------------------------
;; Create BDE style for cc-mode that obey the BDE style guide.
;; *Some useful links* (under http://cc-mode.sourceforge.net/html-manual/)
;; Indentation-Engine-Basics.html
;; Customizing-Indentation.html
;; Syntactic-Symbols.html

(defun bde-indent-statement-block-intro (langelem)
  "Format statement according to BDE style.
..
switch {
  case 2: {
    statement-block-intro;
  }
}
..
"
  (save-excursion
    (goto-char (c-langelem-pos langelem))
    (if (looking-at "\\(case\\|default\\)")
        '* '+)))

(defun bde-indent-comment-intro (langelem)
  "Format class-level documentation according to BDE style.
..
// ============================================================================
// ...
// ============================================================================

                        // ==========
                        // class Test
                        // ==========
class Test {
    // class-level doc
  public:
    // CREATORS
    Test();

    // MANIPULATORS
    void setSomething();
        // functional-level doc
}
..
"
  (let ((class-elem (assq 'inclass c-syntactic-context))
        (top-elem (assq 'topmost-intro c-syntactic-context))
        (statement-block-intro (assq
                                'statement-block-intro c-syntactic-context))
        (defun-block-intro (assq 'defun-block-intro c-syntactic-context)))
    (cond
     ((and class-elem top-elem)
      (cond
       ((save-excursion
          (progn
            (goto-char (c-langelem-pos top-elem))
            (looking-at "\\s-*\\(class\\|struct\\|union\\)")))
        0)
       ((save-excursion
          (progn
            (forward-line -1)
            (goto-char (point-at-bol))
            (looking-at "\\s-*\\(public:\\|private:\\)?$")))
        0)
       (t '+)))
     ((or statement-block-intro defun-block-intro)
      ;; for doc in test drivers' case statemnets
      (if (and defun-block-intro
               (save-excursion
                 (progn
                   (goto-char (c-langelem-pos defun-block-intro))
                   (looking-at "DEFINE_TEST_CASE")))) ;; workaround for
                                                      ;; packedcalendar test
                                                      ;; driver
          4
        0))
     (t
      (let (is-banner is-not-function comment-start pre-comment-start)
        (save-excursion
          (goto-char (point-at-bol))
          (save-excursion
            (goto-char (c-langelem-pos (car c-syntactic-context)))
            (setq comment-start (- (point) (point-at-bol))))
          (while (looking-at "\\s-*//")
            (goto-char (point-at-bol))
            (when (looking-at "\\s-*// \\(\\(=\\|-\\)+\\)\\s-*$")
              (when (> 75 (length (match-string 1)))
                (setq is-banner 't)))
            (forward-line -1)
            (condition-case nil
                (setq pre-comment-start
                      (- (re-search-forward "//" (point-at-eol))
                         (point-at-bol) 2))
              (error
               (setq is-not-function (looking-at "^\\s-*$"))
               ))
            (goto-char (point-at-bol))))
        (cond
         (is-banner 24)
         ((and
           pre-comment-start
           (or (looking-at "\\s-*$") (not class-elem)))
          (- pre-comment-start comment-start)) ;; match comment left margins
         ((and (not is-not-function) top-elem) '+)
         (t '0))))
      )))


(c-add-style
 "bde"
 '((c-basic-offset . 4)
   (fill-column . 79)
   (c-echo-syntactic-information-p . t)
   (c-backslash-column . 78)
   (c-backslash-max-column . 78)
   (c-hanging-braces-alist     . ((substatement-open after)
                                  (class-open after)
                                  (block-close . (before after))
                                  (brace-list-open)))
   (c-hanging-colons-alist     . ((member-init-intro before)
                                  (inher-intro)
                                  (case-label after)
                                  (label after)
                                  (access-label after)))
   (c-cleanup-list             . (scope-operator
                                  empty-defun-braces
                                  defun-close-semi))
   (c-offsets-alist
    (topmost-intro         . 0)
    (innamespace           . 0)
    (inclass               . +)
    (access-label          . /)
    (comment-intro         . bde-indent-comment-intro)
    (member-init-intro     . 0)
    (member-init-cont      . /)
    (substatement-open     . 0)
    (case-label            . *)
    (statement-block-intro . bde-indent-statement-block-intro)
    (statement-case-intro  . *)
    (statement-case-open   . 0)
    (inline-open           . 0)
    (cpp-define-intro      . 4)
    (func-decl-cont        . 0)
    )))

;;-----------------------------------------------------------------------------
;; BDE Formatting Utils
;;-----------------------------------------------------------------------------

(defun bde-right-align ()
  "Right align current line up to the fill column."
  (interactive)
  (save-excursion
    (let ((numColumns 0) numNew bp el cn)
      (if mark-active
         (progn
           (setq bp (region-beginning))
           (goto-char (region-end))
           (setq el (line-number-at-pos (region-end)))
           (when (= (point) (point-at-bol))
             (setq el (1- el))))
        (progn
          (setq bp (point))
          (setq el (line-number-at-pos bp))))
      (goto-char bp)
      (setq cn (current-column))
      (while (<= (line-number-at-pos (point)) el)
        (setq numColumns (max (- (point-at-eol) (point-at-bol)) numColumns))
        (forward-line))
      (setq numNew (- fill-column numColumns))
      (goto-char bp)
      (while (<= (line-number-at-pos (point)) el)
        (if (= (line-number-at-pos (point)) (line-number-at-pos bp))
            (goto-char bp)
          (goto-char (point-at-bol)))
        (re-search-forward "^//" (point-at-eol) t)
        (if (< 0 numNew)
          (insert-char ?\s numNew)
          (delete-char (abs numNew)))
        (forward-line))
      (deactivate-mark))))

(defun bde-mark-paragraph ()
  "Mark a paragraph according to BDE formatting rules."
  (interactive)
  (let ((bdry (concat "^\\s-*\\("
                      "$\\|"
                      "///\\|"
                      "//\\.\\.\\|"
                      "//:?\\s-*$\\|"
                      "//:\\s-+\\(o\\|[0-9]+\\)\\s-+\\|"
                      "//\\s--+\\|"
                      "[^/ \t]"
                      "\\)")))
    (beginning-of-line)
    (cond
     ((looking-at "^\\s-*//:\\s-+\\(o\\|[0-9]+\\)\\s-+")
      (push-mark)
      (forward-line 1)
      (goto-char (point-at-bol))
      (search-forward-regexp bdry nil t)
      (forward-line -1)
      (goto-char (point-at-eol))
      (activate-mark))
     ((looking-at "^\\s-*//:")
      (when
          (search-backward-regexp
           "^\\s-*//:\\s-+\\(o\\|[0-9]+\\)\\s-+" nil t)
        (bde-mark-paragraph)))
     ((looking-at "^\\s-*//")
          (search-backward-regexp bdry nil t)
          (forward-line 1)
          (goto-char (point-at-bol))
          (push-mark)
          (search-forward-regexp bdry nil t)
          (forward-line -1)
          (goto-char (point-at-eol))
          (activate-mark))
                                        ;))
     (t
      (when (search-forward-regexp "//" nil t)
        (backward-char 2)
        (push-mark)
        (goto-char (point-at-eol))))
     )))

(defun bde-fill-comment-block ()
  (interactive)
  (save-excursion
    (if mark-active
        (fill-region (region-beginning) (region-end))
      (progn
        (bde-mark-paragraph)
        (if mark-active
            (fill-region (region-beginning) (region-end))
          (fill-paragraph)))
      ))
  (deactivate-mark))

(defun bde-find-other-file ()
  "Open other files corresponding to the current component."
  (interactive)
  (let ((fname (file-name-nondirectory (buffer-file-name))))
    (when (string-match "^\\(.+\\)\\(\\.h\\|\\.cpp\\)$" fname)
      (let ((fbase (substring fname (match-beginning 1) (match-end 1)))
            (ext (substring fname (match-beginning 2) (match-end 2)))
            (extlist '(".h" ".cpp" ".t.cpp")))
        (when (and (string-match "^.+\\(\\.t\\)$" fbase) (equal ext ".cpp"))
          (setq ext ".t.cpp")
          (setq fbase (substring fbase 0 (- (length fbase) 2))))
        (setq ext (member ext extlist))
        (find-file (concat fbase (if (and ext (cdr ext))
                                     (car (cdr ext))
                                   (car extlist))))))))

(defun bde-adapt-ue (from to)
  "Adapt usage example code to the component-level documentation."
  (interactive (progn
                 (barf-if-buffer-read-only)
                 (list (region-beginning) (region-end))))
  (save-excursion
    (goto-char from)
    (let (lineCount, newTo)
      (setq lineCount (count-lines from to))
      ;; (indent-region from (point-at-eol lineCount))
      (replace-regexp "^" "//  " nil from (point-at-eol lineCount)))))

(defun bde-change-component-name (from-package from-name to-package to-name)
  "Change the component name in a source file using BLP conventions."
  (interactive)
  (let* ((from-package (or from-package (read-from-minibuffer "Old package: ")))
         (to-package (or to-package (read-from-minibuffer "New package: ")))
         (from-name (or from-name (read-from-minibuffer "Old name: ")))
         (to-name (or to-name (read-from-minibuffer "New name: ")))
    (save-excursion
      (let ((from-component-name (concat from-package "::" from-name))
            (to-component-name (concat to-package "::" to-name))
            (case-fold-search nil)
            (case-replace t))
        (goto-char (point-min))
        (while (re-search-forward (format
                                   "INCLUDED_\\(%s\\)"
                                   (upcase from-component-name))
                                  nil
                                  t)
          (replace-match (upcase to-component-name) nil nil nil 1))

        (goto-char (point-min))
        (while (re-search-forward (format
                                   "\\(%s\\)\\(\\.\\|_\\)\\(h\\|cpp\\|t\\.cpp\\)"
                                   (downcase from-component-name))
                                  nil
                                  t)
          (replace-match (downcase to-component-name) nil nil nil 1))

        (goto-char (point-min))
        (while (re-search-forward (format "\\(%s\\)" from-component-name) nil t)
          (replace-match to-component-name nil nil nil 1))
        )))))

(defun bdem ()
  (interactive)
  (bde-change-component-name "gr1p1" "Comp1"
                             "gr2p1" "Comp1")
  ;; (bde-change-component-name "bdecs" "CalendarLoader"
  ;;                            "bdet" "CalendarLoader")
  ;; (bde-change-component-name "bdec" "DayOfWeekSet"
  ;;                            "bdet" "DayOfWeekSet")
  ;; (save-excursion
  ;;   (goto-char (point-min))
  ;;   (replace-string "bdes_ident" "bsls_ident")
  ;;   (goto-char (point-min))
  ;;   (replace-string "bdescm_version" "bdlscm_version")
  ;;   (replace-string "bdema" "bdlma")
  ;;   )
  )

(defun bde-wrap (&optional b e)
  (interactive "r")
  (shell-command-on-region b e "/bbsrc/bin/prod/bin/aotools/bdewrap"
                           (current-buffer) t))

;;-----------------------------------------------------------------------------
;; CC-Mode Setup
;;-----------------------------------------------------------------------------

(setq c-default-style "bde")

(add-hook 'c-mode-common-hook
          (lambda ()
            ;; Allow the use of //: and bullet points as the fill prefix
            (setq adaptive-fill-regexp
                  "\\(//:?\\)?\\s-*\\(//:?\\s-*\\(\\([0-9]+\\|o\\)\\s-\\)?\\)")
            ;; highlight lines with only a single space after a period
            ;; (we use double space after period in fixed sized fonts!)
            ;; (highlight-regexp "//.*\\s-\\[^\\s-\\]"  "hi-green-b")
            (highlight-regexp "//.*[^\\.]\\. [^ ]." "hi-green")
            (setq paragraph-separate
                  ;; make "//.." a paragraph separator
                  "[ 	]*\\(//+\\|//\\.\\.\\|\\**\\)[ 	]*$\\|^\f")
            ;; (local-set-key [return] 'newline-and-indent)
            (c-toggle-auto-newline -1)
            (set-fill-column 79)
            (local-set-key [?\M-o] 'bde-find-other-file)
            (local-set-key [?\M-h] 'bde-mark-paragraph)
            (local-set-key [?\M-q] 'bde-fill-comment-block)))

(provide 'bde)
