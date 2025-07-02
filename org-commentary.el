;;; org-commentary.el --- Convert README.org into a package main file's commentary -*- lexical-binding: t -*-

;; Copyright (C) 2025 Przemyslaw Kryger

;; Author: Przemyslaw Kryger <pkryger@gmail.com>
;; Keywords: tools package development
;; Homepage: https://github.com/pkryger/org-commentry.el
;; Package-Requires: ((emacs "28.1") (compat "29.4") (org "9.6"))
;; Version: 0.0.0
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Description
;; ===========
;;
;; This package allows you to use a `README.org' file in your repository as a
;; canonical source of documentation.  That is, it uses built-in `org-mode'
;; ASCII export functionality to generate `Commentary' section in your package
;; main file.
;;
;;
;; Installation
;; ============
;;
;; This package is not available on MELPA.  To use it you need to install it
;; directly from source.  One option is to use `use-package', for example:
;;
;; (use-package org-commentary
;;   :defer t
;;   :vc (:url "https://github.com/pkryger/org-commentary.el.git"
;;        :rev :newest))
;;
;; If you use [Cask] you can add the following your `Cask' file:
;;
;; (development
;;  (depends-on "org-commentary"
;;              :git "https://github.com/pkryger/org-commentary.el.git"))
;;
;;
;; [Cask] <https://github.com/cask/cask>
;;
;;
;; Usage
;; =====
;;
;; Simply write documentation in `README.org', and when done (while still in
;; the `README.org' buffer), type `M-x org-commentary-update' .  This will
;; export current content of the `README.org' into a `Commentary' section of
;; your package main file.
;;
;; The package main file is inferred from the `project' name (assumed to be
;; the same as the name of the directory, the `.el' extension is added if
;; necessary).  Alternatively, if not such a file found the first word in the
;; first top level section in `README.org' file is used as a package name
;; (again, the `.el' is added if necessary).  If these methods are
;; insufficient the variable `org-commentary-main-file' can be used.  When the
;; latter is set it's tried first.
;;
;; Export is done between lines `;;; Commentary:' and `;;; Code:' so make sure
;; these are present in the package main file.
;;
;; - /variable/: `org-commentary-main-file' the name of the package main file.
;; - /command/: `org-commentary-update' update the package main file based on
;;   the content of the current buffer.
;; - /command/: `org-commentary-preview' generate commentary (based on the
;;   content of the current buffer) and preview it in a new buffer.  If
;;   `flycheck' is installed, a custom `checkdoc' checker is run in the
;;   preview buffer.
;; - /command/: `org-commnentary-check' check if the export of the current
;;   buffer and content of the commentary section of the package main file
;;   match.
;; - /function/: `org-commetnary-check-batch' check if the export of the
;;   `README.org' file and the commentary section of the package main file
;;   match, for example:
;;
;; cask emacs -batch -L . \
;;   --load org-commentary \
;;   --funcall org-commentary-check-batch

;;; Code:

(require 'cl-lib)
(require 'compat)
(require 'diff)
(require 'flycheck nil t)
(require 'org)
(require 'org-element)
(require 'ox)
(require 'project)

(defvar org-commentary-main-file nil
  "Main package file to perform export to.")
(put 'org-commentary-main-file 'save-local-variable #'stringp)

(when (featurep 'flycheck)
  (flycheck-define-checker org-commentary-checkdoc
    "An Emacs Lisp style checker using CheckDoc.

Adjusted for commentary checks, boosting all diagnostics to errors
and filtering header and footer ones.
The checker runs `checkdoc-current-buffer'."
    :command ("emacs" (eval flycheck-emacs-args)
              "--eval" (eval (flycheck-sexp-to-string
                              (flycheck-emacs-lisp-checkdoc-variables-form)))
              "--eval" (eval flycheck-emacs-lisp-checkdoc-form)
              "--" source)
    :error-patterns
    ((error line-start (file-name) ":" line ": " (message) line-end))
    :error-filter
    (lambda (errors)
      (cl-remove-if
       (lambda (err)
         (string-match
          (rx (or "The first line should be of the form: \";;; package --- Summary\""
                  "You should have a summary line (\";;; .* --- .*\")"
                  "You should have a section marked \";;; Commentary:\""
                  "You should have a section marked \";;; Code:\""
                  (seq "The footer should be: (provide '"
                       (one-or-more (or alnum "-" "."))
                       ")\\n;;; "
                       (one-or-more (or alnum "-" ".")) " ends here")))
          (flycheck-error-message err)))
       errors))
    :modes (emacs-lisp-mode)
    :enabled #'flycheck--emacs-lisp-checkdoc-enabled-p))

(defun org-commentary--remove-top-level (backend)
  "Remove top level headline from export.
BACKEND is the export back-end being used, as a symbol."
  (org-map-entries
   (lambda ()
     (when (and (eq backend 'org-commentary--ascii)
                (looking-at (rx line-start "* ")))
       (delete-region (point)
                      (save-excursion (outline-next-heading) (point)))
       (setq org-map-continue-from (point))))))

(defun org-commentary--src-block (src-block _contents info)
  "Transcode a SRC-BLOCK element from Org to Commentary.
CONTENTS is nil.  INFO is a plist used as a communication channel."
  (org-element-normalize-string
   (org-export-format-code-default src-block info)))

(defun org-commentary-final-output (contents _backend _info)
  "Transcode CONTENTS element from Org to Commentary."
  (replace-regexp-in-string
   "^;;\\'" ""
   (replace-regexp-in-string
    "^;; $" ";;"
    (replace-regexp-in-string
     "^" ";; "
     contents))))

(org-export-define-derived-backend 'org-commentary--ascii 'ascii
  :translate-alist '((src-block . org-commentary--src-block))
  :filters-alist
  '((:filter-final-output . org-commentary-final-output)))

(defmacro org-commentary-with-defaults (&rest body)
  "Execute BODY with `org-commentary' defaults."
  `(let ((org-export-before-parsing-functions
          (cons
           #'org-commentary--remove-top-level
           org-export-before-parsing-functions))
         (org-ascii-text-width 75)
         (org-ascii-global-margin 0)
         (org-ascii-inner-margin 0))
     ,@body))

(defun org-commentary--buffer ()
  "Get the buffer to export from."
  (if (and (derived-mode-p 'org-mode)
           (not current-prefix-arg))
      (current-buffer)
    (read-buffer "Org-mode buffer: "
                 (when-let* ((project (project-current))
                             (readme (file-name-concat
                                      (project-root project) "README.org"))
                             ((file-exists-p readme)))
                   (cl-some (lambda (buffer)
                              (when (equal (buffer-file-name buffer)
                                           readme)
                                buffer))
                            (buffer-list)))
                 t
                 (lambda (buffer)
                   (with-current-buffer buffer
                     (derived-mode-p 'org-mode))))))

;;;###autoload
(defun org-commentary-preview (buffer)
  "Export a preview of commentary from the specified BUFFER.

Enable `org-commentary-checkdoc' checker when `flycheck' is available.

When called interactively in an `org-mode' buffer then use
current buffer as BUFFER.  When called with a prefix argument or
with a buffer that is not in `org-mode' ask for buffer."
  (interactive
   (list (org-commentary--buffer)))
  (let ((preview-buffer (get-buffer-create "*Org ORG-COMMENTARY Preview*")))
    (with-current-buffer preview-buffer
      (setq buffer-read-only nil))
    (with-current-buffer buffer
      (org-commentary-with-defaults
       (org-export-to-buffer 'org-commentary--ascii preview-buffer
         nil nil nil nil nil
         (lambda ()
           (emacs-lisp-mode)
           (set-buffer-modified-p nil)
           (setq buffer-read-only t)
           (when (featurep 'flycheck)
             (setf (car (flycheck-checker-get
                         'org-commentary-checkdoc 'command))
                   flycheck-this-emacs-executable)
             (add-to-list 'flycheck-disabled-checkers 'emacs-lisp-checkdoc)
             ;; Do not clobber user configuration
             (make-local-variable 'flycheck-checkers)
             (add-to-list 'flycheck-checkers 'org-commentary-checkdoc)
             (flycheck-mode))))))))

(defun org-commentary--file (buffer &optional user-file)
  "Find a file to export to.
When USER-FILE is non-nil use it as the file name.  If the file
has not been found, and `org-commentary-main-file' is non-nil use
it as the file name.  If the file has not been found use
`current-project''s name as the file name.  If the file has not
been found use BUFFER to extract the file (a first word in a
first heading)."
  (if current-prefix-arg
      (read-file-name "Package main file: " nil nil t nil
                      (lambda (file)
                        (string-suffix-p ".el" file)))
    (when-let* ((project-root (when-let* ((project (project-current)))
                                (project-root project)))
                (candidates (lambda (file-name)
                              (mapcar (lambda (dir)
                                        (file-name-concat project-root
                                                          dir
                                                          file-name))
                                      '("" "lisp" "src")))))
      (cl-some (lambda (file)
                 (when (file-exists-p file)
                   file))
               (append
                (when user-file
                  (if (or (file-name-absolute-p user-file)
                          (file-exists-p user-file))
                      (list org-commentary-main-file))
                  (funcall candidates user-file))
                (when org-commentary-main-file
                  (if (file-name-absolute-p org-commentary-main-file)
                      (list org-commentary-main-file)
                    (funcall candidates org-commentary-main-file)))
                (funcall candidates
                         (let ((project-dir
                                (file-name-nondirectory (directory-file-name
                                                         project-root))))
                           (if (string-suffix-p ".el" project-dir)
                               project-dir
                             (concat project-dir ".el"))))
                (when-let*
                    ((name
                      (with-current-buffer buffer
                        (when (derived-mode-p 'org-mode)
                          (save-excursion
                            (save-restriction
                              (widen)
                              (goto-char (point-min))
                              (org-next-visible-heading 1)
                              (when-let*
                                  (((re-search-forward
                                     (rx (one-or-more "*")
                                         " "
                                         (group (one-or-more (or alnum "-" "."))))
                                     nil t))
                                   (name
                                    (match-string-no-properties 1)))
                                (if (string-suffix-p ".el" name)
                                    name
                                  (concat name ".el")))))))))
                  (funcall candidates name)))))))

(defmacro org-commentary--with-region-and-export
    (buffer file start end export &rest body)
  "Execute BODY in conest of the FILE region (START END) and EXPORT from BUFFER."
  (declare (indent 5) (debug (form form symbolp symbolp symbolp body)))
  `(org-commentary-with-defaults
    (with-current-buffer (find-file-noselect ,file)
      (goto-char (point-min))
      (if-let* ((,start (when (re-search-forward "^;;; Commentary:$" nil t)
                          (beginning-of-line 3)
                         (point)))
                (,end (when (re-search-forward "^;;; Code:$" nil t)
                       (end-of-line 0)
                       (point)))
                (,export (with-current-buffer ,buffer
                          (org-export-as 'org-commentary--ascii))))
          (progn ,@body)
        (user-error (cond
                     ((null ,export)
                      "Org export from %s didn't return anything" ,buffer)
                     ((null ,end)
                      "Missing ;;; Code: section in %s" ,file)
                     (t
                      "Missing ;;; Commentary: section in %s" ,file)))))))

;;;###autoload
(defun org-commentary-update (&optional buffer file)
  "Update commentary section in FILE with export from BUFFER."
  (interactive (let ((buf (org-commentary--buffer)))
                  (list buf
                        (org-commentary--file buf))))
  (if-let* ((buffer (or buffer
                        (when (derived-mode-p 'org-mode)
                          (current-buffer))))
            (file (or file
                      (org-commentary--file buffer))))
      (org-commentary--with-region-and-export
          buffer file start end export
        (delete-region start end)
        (insert export)
        (save-buffer))
    (user-error (if buffer
                    (format "Cannot determine file for %s" buffer)
                  "Missing org-mode buffer"))))

(defmacro org-commentary--with-temp-buffers (buffer-a buffer-b &rest body)
  "Create temporary BUFFER-A and BUFFER-B, and evaluate BODY like `progn'."
  (declare (indent 2) (debug (symbolp symbolp body)))
  `(let ((,buffer-a (generate-new-buffer " *temp*" t))
         (,buffer-b (generate-new-buffer " *temp*" t)))
     (unwind-protect
	     (progn ,@body)
       (when (buffer-name ,buffer-a)
         (kill-buffer ,buffer-a))
       (when (buffer-name ,buffer-b)
         (kill-buffer ,buffer-b)))))

;;;###autoload
(defun org-commentary-check (buffer file)
  "Check if commentary section in FILE matches export from BUFFER."
  (interactive (let ((buf (org-commentary--buffer)))
                 (list buf
                       (org-commentary--file buf))))
  (org-commentary--with-region-and-export
      buffer file start end export
    (org-commentary--with-temp-buffers
        exported
        in-file
      (with-current-buffer exported
        (insert export))
      (let ((commentary (buffer-substring start end)))
        (with-current-buffer in-file
          (insert commentary)))
      (with-temp-buffer
        (diff-no-select in-file exported
                        nil t
                        (current-buffer))
        (goto-char (point-min))
        (when-let*
            (((not (string-match-p "\nDiff finished (no differences)\\."
                                   (buffer-string))))
             (tmp-file
              (buffer-substring (re-search-forward "^diff -u ")
                                (- (re-search-forward " ") 1)))
             (actual-file
              (file-name-nondirectory file))
             (tmp-buffer
              (buffer-substring (point)
                                (compat-call pos-eol))) ; Since Emacs-29
             (actual-buffer-or-file
              (or (when-let* ((file (buffer-file-name buffer)))
                    (file-name-nondirectory file))
                  buffer))
             (inhibit-read-only t))
          (goto-char (point-min))
          (perform-replace tmp-file
                           actual-file
                           nil nil nil)
          (goto-char (point-min))
          (perform-replace tmp-buffer
                           (format "<exported from %s>"
                                   actual-buffer-or-file)
                           nil nil nil)
          (error
           (concat "Generated Commentary in `%s' differs from the one "
                   "generated from `%s'\n\n%s")
           actual-file
           actual-buffer-or-file
           (buffer-string)))))))

(defun org-commentary-check-batch ()
  "Run `org-commentary-check' on the org and package main file from command line."
  (when (equal (car command-line-args-left) "--")
    (setq command-line-args-left
          (cdr command-line-args-left)))
  (message "%S" command-line-args-left)
  (if (or (null command-line-args-left)
          (<= 0 (length command-line-args-left) 2))
      (progn (setq command-line-args-left nil)
             (with-temp-buffer
               (insert-file-contents (or (car command-line-args-left)
                                         "README.org")
                                     'visit)
               (org-mode)
               (org-commentary-check
                (current-buffer)
                (org-commentary--file (current-buffer)
                                      (cadr command-line-args-left)))))
    (error "Invalid arguments.  Expected: [org-file [package-main-file]]")))

(provide 'org-commentary)

;;; org-commentary.el ends here
