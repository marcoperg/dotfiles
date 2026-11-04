;;; test_isabelle_lazy.el --- Optional integration loads only on use -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'package)
(package-initialize)
(defvar my/isabelle-auto-start nil)

(defconst my/test-lazy-init
  (expand-file-name "../dotfiles/emacs/init.el" (file-name-directory load-file-name)))

(ert-deftest my/isabelle-lazy-startup-and-first-use ()
  (let ((selected (copy-tree package-selected-packages))
        (vc-loaded (featurep 'package-vc)))
  (let ((load-file-name my/test-lazy-init))
    (with-temp-buffer
      (insert-file-contents my/test-lazy-init)
      (goto-char (point-min))
      (search-forward "; Load/check this optional installation")
      (beginning-of-line)
      (let ((start (point)))
        (search-forward "; Javascript")
        (beginning-of-line)
        (cl-letf (((symbol-function 'package-vc-install)
                   (lambda (&rest _) (error "Unexpected package installation at startup")))
                  ((symbol-function 'customize-save-variable)
                   (lambda (&rest _) (error "Unexpected Customize write at startup")))
                  ((symbol-function 'display-warning)
                   (lambda (&rest _) (error "Unexpected Isabelle warning at startup"))))
          (eval-region start (point))))))
  (with-temp-buffer
    (setq buffer-file-name "Unrelated.txt")
    (set-auto-mode)
    (should (eq major-mode 'text-mode)))
  (should (equal selected package-selected-packages))
  (should (eq vc-loaded (featurep 'package-vc))))
  (should (autoloadp (symbol-function 'isar-mode)))
  (should-not (featurep 'my-isabelle))
  (should-not (featurep 'lsp-isar))
  (let ((original (symbol-function 'file-readable-p)))
    (cl-letf (((symbol-function 'file-readable-p)
               (lambda (path)
                 (and (not (string-match-p "/isabelle-dev/" path))
                      (funcall original path)))))
      (with-temp-buffer
        (let ((error (should-error (call-interactively 'isar-mode) :type 'user-error)))
          (should (string-match-p "setup.py.*--install" (error-message-string error)))))))
  ;; A failed first attempt must remain retryable after installation.
  (should (autoloadp (symbol-function 'isar-mode)))
  (with-temp-buffer
    (setq buffer-file-name "Lazy_Test.thy")
    (set-auto-mode)
    (should (eq major-mode 'isar-mode))
    (should (featurep 'my-isabelle))))

;;; test_isabelle_lazy.el ends here
