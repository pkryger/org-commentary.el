(source gnu)
(source melpa)

(package-file "org-commentary.el")

(development
 (depends-on "org" "9.6")
 (depends-on "flycheck")
 ;; Last commit before merging support for Emacs-30.1
 (depends-on "package-lint"
             :git "https://github.com/purcell/package-lint.git"
             :ref "21edc6d0d0eadd2d0a537f422fb9b7b8a3ae6991"
             :files ("*.el" "data"))
 (depends-on "relint")
 (depends-on "checkdoc-batch"
             :git "https://github.com/pkryger/ckeckdoc-batch.el.git"))
