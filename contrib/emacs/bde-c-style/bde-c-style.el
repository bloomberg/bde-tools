;;; bde-c-style.el --- Provides a BDE c-style for cc-mode

;; Author: Chen He (che24 at bloomberg dot net)
;; Keywords: c, tools
;; Homepage: https://github.com/bloomberg/bde-tools

;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:

;; This package provides a cc-mode C/C++ style, 'bde', that conforms to the BDE
;; style guide.
;;
;; To use, make sure that this file is in your load path, and set "bde" as the
;; default c++-mode style:
;;
;;     (require 'bde-c-style)
;;     (add-to-list 'c-default-style '(c++-mode . "bde"))
;;     (add-to-list 'c-default-style '(c-mode . "bde"))
;;
;; Alternatively, you can call `c-set-style' in the `c-mode-common-hook':
;;
;;     (add-hook 'c-mode-common-hook
;;          (lambda () (c-set-style "bde"))
;;
;; To find out more about how to customize CC-mode indentation, take a look at
;; the cc-mode manual:
;;
;;   http://cc-mode.sourceforge.net/html-manual/Indentation-Engine-Basics.html


;;; Code:

(require 'cc-mode)

(defun bde-c-style--indent-statement-block-intro (langelem)
  "Return the appropriate indent for the start of a statement block.

The default identation is is '+' (1 basic offset), unless we are in
a switch statement, in which case the indentation is set to
'*' (half basic offset).

Example:

switch(val) {
  case 100: {
      return 1;
  } break;
  default: {
      return 0;
  } break;
}
"
  (save-excursion
    (goto-char (c-langelem-pos langelem))
    (if (looking-at "\\(case\\|default\\)")
        '* '+)))

(defun bde-c-style--under-function-member-p (class-elem top-elem)
  "Return t if point is directly under a function member.

This function's behavior is only defined if the current point is
within a class definition.

This function works by checking for the following 2 conditions in
order:

 1 If the top-elem is a type name, then the point is not under a
   function member.

 2 Look at the previous line, if it is either empty, a comment,
   or an access specifier, assume that the point is also not
   under a function member."

  (if (or (save-excursion
            (goto-char (c-langelem-pos top-elem))
            (looking-at "\\s-*\\(class\\|struct\\|union\\)"))
          (save-excursion
            (forward-line -1)
            (goto-char (point-at-bol))
            (looking-at "\\s-*\\(public:\\|private:\\|protected:\\)?$")))
      nil
    t))

(defvar c-syntactic-context)

(defun bde-indent-comment-intro (langelem)
  "Return the approriate indentation for the comment block.

Supported indentation:
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

void Test::setSomething();
    // set something.
.."
  (let ((class-elem (assq 'inclass c-syntactic-context))
        (top-elem (assq 'topmost-intro c-syntactic-context))
        (statement-block-intro (assq
                                'statement-block-intro c-syntactic-context))
        (defun-block-intro (assq 'defun-block-intro c-syntactic-context)))
    (cond
     ;; The point is under a class definition.
     ((and class-elem top-elem)
      (if (bde-c-style--under-function-member-p
           class-elem top-elem)
          '+
        0))
     ;; The point is directly under the beginning of a statement block or
     ;; function definition.
     ((or statement-block-intro defun-block-intro)
      0)
     (t
      ;; Find the beginning of the comment block.  See if the comment block is
      ;; either 1) a banner block, or 2) a comment block after a function
      ;; declaration, and set the appropriate indentation.  If the comment
      ;; block is neither 1) or 2), then indent the same amount as the previous
      ;; comment line.  Otherwise, do not ident.
      (let (banner-flag
            function-flag
            comment-start
            pre-comment-start)
        (save-excursion
          (goto-char (c-langelem-pos (car c-syntactic-context)))
          (setq comment-start (- (point) (point-at-bol))))
        (save-excursion
          (goto-char (point-at-bol))
          (let (past-begin-flag)
            (while (and (not past-begin-flag) (looking-at "\\s-*//"))
              (goto-char (point-at-bol))
              ;; Assume the line is part of a banner when the loop encounters
              ;; "// ============..."
              (when (looking-at "\\s-*// \\(\\(=\\|-\\)+\\)\\s-*$")
                (when (> 75 (length (match-string 1)))
                  (setq banner-flag 't)))
              (if (< (forward-line -1) 0)
                  (setq past-begin-flag 't)
                (condition-case nil
                    ;; Save the margin of the previous comment line.
                    (setq pre-comment-start
                          (- (re-search-forward "//" (point-at-eol))
                             (point-at-bol) 2))
                  (error
                   ;; Assume a non-empty, non-comment line above the comment
                   ;; block is a function declaration.
                   (setq function-flag (and (not (looking-at "^\\s-*$"))
                                            top-elem))
                   (setq past-begin-flag 't)))))))
        (cond
         (banner-flag 24)
         (pre-comment-start
          ;; Match previous comment line's left margins.
          (- pre-comment-start comment-start))
         (function-flag '+)
         (t '0)))))))

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
    (statement-block-intro . bde-c-style--indent-statement-block-intro)
    (statement-case-intro  . *)
    (statement-case-open   . 0)
    (inline-open           . 0)
    )))

(provide 'bde-c-style)

;;; bde-c-style.el ends here
