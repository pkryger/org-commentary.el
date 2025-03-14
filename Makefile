export EMACS ?= $(shell command -v emacs 2>/dev/null)
CASK_DIR := $(shell cask package-directory)

files = $$(cask files | grep -Ev 'org-commentary-(pkg|autoloads).el')
test_files = $(wildcard test/org-commentary*.t.el)

$(CASK_DIR): Cask
	cask install
	@touch $(CASK_DIR)

.PHONY: cask
cask: $(CASK_DIR)

.PHONY: bytecompile
bytecompile: cask
	cask emacs -batch -L . -L test \
      --eval "(setq byte-compile-error-on-warn t)" \
      -f batch-byte-compile $(files) $(test_files)
	  (ret=$$? ; cask clean-elc ; rm -f test/*.elc ; exit $$ret)

.PHONY: lint
lint: cask
	cask emacs -batch -L . \
      --load package-lint \
      --eval '(setq package-lint-main-file "org-commentary.el")' \
      --funcall package-lint-batch-and-exit $(files)

.PHONY: relint
relint: cask
	cask emacs -batch -L . -L test \
      --load relint \
      --funcall relint-batch $(files) $(test_files)

define CHECKDOC_ALLOW_CASK_EMACS
(progn
  (require 'rx)
  (advice-add #'checkdoc-in-example-string-p
             :after-until
            (lambda (&rest _)
              (save-match-data
                (looking-back (rx symbol-start "cask emacs")
                              (line-beginning-position))))))
endef

export CHECKDOC_ALLOW_CASK_EMACS
.PHONY: checkdoc
checkdoc: cask
	cask emacs -batch -L . \
      --load checkdoc \
      --load checkdoc-batch \
      --eval "$$CHECKDOC_ALLOW_CASK_EMACS" \
      --funcall checkdoc-batch $(files)

.PHONY: commentary
commentary: cask
	cask emacs -batch -L . \
      --load org-commentary \
      --funcall org-commentary-check-batch
