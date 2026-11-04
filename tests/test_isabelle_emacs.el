;;; test_isabelle_emacs.el --- Isabelle reader checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'package)
(require 'package-vc)

(defvar isar-mode-remove-utf8-when-saving)

;; Read only the Isabelle section: do not run the workstation init or install
;; any packages while exercising its bootstrap logic.
(defconst isabelle-test-forms
  (let ((init (expand-file-name "../dotfiles/emacs/init.el"
                                (file-name-directory load-file-name))))
    (with-temp-buffer
      (insert-file-contents init)
      (goto-char (point-min))
      (search-forward "; Isabelle theory reading:")
      (forward-line 1)
      (let ((start (point))
            forms)
        (search-forward "; Javascript")
        (beginning-of-line)
        (narrow-to-region start (point))
        (goto-char (point-min))
        (condition-case nil
            (while t (push (read (current-buffer)) forms))
          (end-of-file nil))
        (nreverse forms)))))

(defun isabelle-test-eval-config ()
  "Evaluate just the lazy Isabelle reader configuration."
  (dolist (form isabelle-test-forms)
    (eval form t)))

(defun isabelle-test-in-fresh-emacs (goal)
  "Run GOAL in a fresh Emacs, failing with its output if it exits nonzero."
  (with-temp-buffer
    (unless (eq (call-process (expand-file-name invocation-name invocation-directory)
                             nil t nil "--batch" "-Q" "--eval"
                             (prin1-to-string goal))
                0)
      (ert-fail (buffer-string)))))

(defun isabelle-test-activate-with-fake-reader ()
  "Exercise first-use setup without loading the optional reader library."
  (let ((original-require (symbol-function 'require)))
    (cl-letf (((symbol-function 'require)
               (lambda (feature &rest args)
                 (if (eq feature 'isar-mode)
                     t
                   (apply original-require feature args))))
              ((symbol-function 'isar-mode)
               (lambda () (setq major-mode 'isar-mode))))
      (my/isar-mode))))

(ert-deftest isabelle-startup-does-not-load-or-install-the-reader ()
  ;; Fresh processes catch eager loads and uninitialized package-vc variables
  ;; even though the unit tests preload package-vc to stub its installer.
  (isabelle-test-in-fresh-emacs
   `(progn
      (require 'cl-lib)
      (require 'package)
      (let ((original-require (symbol-function 'require))
            (selected-before (copy-tree package-selected-packages)))
        (cl-letf (((symbol-function 'require)
                   (lambda (feature &rest args)
                     (when (memq feature '(package-vc isar-mode))
                       (error "Unexpected eager load: %S" feature))
                     (apply original-require feature args)))
                  ((symbol-function 'package-installed-p)
                   (lambda (&rest _) (error "Unexpected package check at startup")))
                  ((symbol-function 'customize-save-variable)
                   (lambda (&rest _) (error "Unexpected Customize write")))
                  ((symbol-function 'display-warning)
                   (lambda (&rest args) (error "Unexpected warning: %S" args))))
          ,@isabelle-test-forms
          (with-temp-buffer
            (setq buffer-file-name "Unrelated.txt")
            (set-auto-mode)
            (unless (eq major-mode 'text-mode)
              (error "Ordinary text file did not open normally"))))
        (when (or (featurep 'package-vc)
                  (featurep 'isar-mode)
                  (boundp 'package-vc-selected-packages)
                  (boundp 'isar-mode-remove-utf8-when-saving)
                  (not (equal selected-before package-selected-packages)))
          (error "Startup unexpectedly initialized the optional reader"))))))

(ert-deftest isabelle-first-theory-loads-package-vc-on-a-cold-start ()
  (isabelle-test-in-fresh-emacs
   `(progn
      (require 'cl-lib)
      (require 'package)
      ,@isabelle-test-forms
      (let ((original-require (symbol-function 'require)))
        (cl-letf (((symbol-function 'require)
                   (lambda (feature &rest args)
                     (if (eq feature 'isar-mode)
                         t
                       (apply original-require feature args))))
                  ((symbol-function 'package-installed-p) (lambda (_) t))
                  ((symbol-function 'isar-mode)
                   (lambda () (setq major-mode 'isar-mode)))
                  ((symbol-function 'customize-save-variable)
                   (lambda (&rest _) (error "Unexpected Customize write")))
                  ((symbol-function 'display-warning)
                   (lambda (&rest args) (error "Unexpected warning: %S" args))))
          (with-temp-buffer
            (setq buffer-file-name "Example.thy")
            (set-auto-mode)
            (unless (eq major-mode 'isar-mode)
              (error "First theory did not activate the reader")))))
      (unless (and (featurep 'package-vc)
                   (memq 'isar-mode package-selected-packages)
                   (assq 'isar-mode package-vc-selected-packages))
        (error "First-use setup did not initialize its selections")))))

(ert-deftest isabelle-bootstrap-preselects-before-installing ()
  (let ((auto-mode-alist nil)
        (package-selected-packages '(other-package))
        (package-vc-selected-packages '((other-package :url "https://example.org/other")))
        installed)
    (isabelle-test-eval-config)
    (cl-letf (((symbol-function 'package-installed-p) (lambda (_) nil))
              ((symbol-function 'customize-save-variable)
               (lambda (&rest _) (ert-fail "Bootstrap must not save Customize")))
              ((symbol-function 'package-vc-install)
               (lambda (spec)
                 (should (memq 'isar-mode package-selected-packages))
                 (should (equal spec (assq 'isar-mode package-vc-selected-packages)))
                 ;; This is the package-vc lookup that otherwise triggers a
                 ;; Customize write during the first installation.
                 (should (equal (package-vc--desc->spec
                                 (package-desc-create :name 'isar-mode :kind 'vc))
                                (cdr spec)))
                 (setq installed spec))))
      (with-temp-buffer
        (isabelle-test-activate-with-fake-reader)
        (should (eq major-mode 'isar-mode))
        (should-not isar-mode-remove-utf8-when-saving)))
    (should (equal installed
                   '(isar-mode :url "https://github.com/m-fleury/isar-mode")))
    (should (memq 'other-package package-selected-packages))
    (should (assq 'other-package package-vc-selected-packages))))

(ert-deftest isabelle-bootstrap-skips-installed-package-and-is-idempotent ()
  (let ((auto-mode-alist nil)
        (package-selected-packages nil)
        (package-vc-selected-packages nil))
    (isabelle-test-eval-config)
    (cl-letf (((symbol-function 'package-installed-p) (lambda (_) t))
              ((symbol-function 'package-vc-install)
               (lambda (&rest _) (ert-fail "Must not reinstall isar-mode")))
              ((symbol-function 'customize-save-variable)
               (lambda (&rest _) (ert-fail "Bootstrap must not save Customize"))))
      (with-temp-buffer
        (isabelle-test-activate-with-fake-reader)
        (isabelle-test-activate-with-fake-reader)))
    (should (equal package-selected-packages '(isar-mode)))
    (should (= (length package-vc-selected-packages) 1))))

(ert-deftest isabelle-reader-falls-back-to-text-on-installation-failure ()
  (let ((auto-mode-alist nil)
        (package-selected-packages nil)
        (package-vc-selected-packages nil)
        warning)
    (isabelle-test-eval-config)
    (cl-letf (((symbol-function 'package-installed-p) (lambda (_) nil))
              ((symbol-function 'package-vc-install)
               (lambda (&rest _) (error "Network unavailable")))
              ((symbol-function 'display-warning)
               (lambda (_type message &rest _) (setq warning message))))
      (with-temp-buffer
        (insert "theory Example\nimports Main\nbegin\nend\n")
        (let ((before (buffer-string)))
          (isabelle-test-activate-with-fake-reader)
          (should (eq major-mode 'text-mode))
          (should (equal (buffer-string) before)))))
    (should (string-match-p "using text-mode: Network unavailable" warning))))

(ert-deftest isabelle-reader-registers-theories-without-initializing-packages ()
  (let ((auto-mode-alist nil)
        (package-selected-packages nil)
        (package-vc-selected-packages nil)
        (isar-mode-remove-utf8-when-saving t))
    (isabelle-test-eval-config)
    (should (eq (assoc-default "Example.thy" auto-mode-alist #'string-match-p)
                'my/isar-mode))
    (should-not package-selected-packages)
    (should-not package-vc-selected-packages)
    (should isar-mode-remove-utf8-when-saving)))

;; These two smoke tests also exercise the actual upstream mode when packages
;; have been initialized before loading this test file.  They never install it.
(ert-deftest isabelle-reader-displays-symbols-without-changing-text ()
  (skip-unless (and (package-installed-p 'isar-mode) (locate-library "isar-mode")))
  (let ((auto-mode-alist nil)
        (package-selected-packages nil)
        (package-vc-selected-packages nil)
        (isar-mode-remove-utf8-when-saving t)
        (theory "theory Example\nimports Main\nbegin\nlemma identity: \"\\<forall>x. x = x\" by simp\nend\n"))
    (isabelle-test-eval-config)
    (with-temp-buffer
      (setq buffer-file-name "Example.thy")
      (insert theory)
      (set-auto-mode)
      (font-lock-ensure)
      (should (eq major-mode 'isar-mode))
      (should (bound-and-true-p unicode-tokens-mode))
      (should (eq (get-text-property (point-min) 'face) 'font-lock-builtin-face))
      (goto-char (point-min))
      (search-forward "\\<forall>")
      (should (get-text-property (match-beginning 0) 'composition))
      (should (equal (buffer-substring-no-properties (point-min) (point-max))
                     theory)))))

(ert-deftest isabelle-reader-preserves-unicode-and-encoded-symbols-on-save ()
  (skip-unless (and (package-installed-p 'isar-mode) (locate-library "isar-mode")))
  (let ((auto-mode-alist nil)
        (package-selected-packages nil)
        (package-vc-selected-packages nil)
        (isar-mode-remove-utf8-when-saving t)
        (make-backup-files nil)
        (create-lockfiles nil)
        (file (make-temp-file "isabelle-theory-" nil ".thy"))
        (theory "theory Example\nimports Main\nbegin\ntext ‹Unicode ∀ and encoded \\<forall>›\nend\n")
        buffer)
    (unwind-protect
        (progn
          (isabelle-test-eval-config)
          (setq buffer (find-file-noselect file))
          (with-current-buffer buffer
            (should (eq major-mode 'isar-mode))
            (should (memq 'isar-replace-all-utf8-by-encoding after-save-hook))
            (insert theory)
            (save-buffer)
            (should-not (buffer-modified-p))
            (should (equal (buffer-substring-no-properties (point-min) (point-max))
                           theory)))
          (with-temp-buffer
            (insert-file-contents file)
            (should (equal (buffer-string) theory))))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (delete-file file))))

(ert-run-tests-batch-and-exit)
