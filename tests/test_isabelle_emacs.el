;;; test_isabelle_emacs.el --- Run the maintained Isabelle editor tests -*- lexical-binding: t; -*-

;; Keep the earlier test command working.  Its reader-only package-vc installer
;; has been superseded by the pinned environment.  Test each suite in a fresh
;; process so loaded integration state cannot conceal eager startup behavior.
(let ((directory (file-name-directory load-file-name)))
  (dolist (suite '("test_isabelle_lazy.el" "test_isabelle.el"))
    (with-temp-buffer
      (let ((status (call-process
                     (expand-file-name invocation-name invocation-directory)
                     nil t nil "--batch" "-Q" "-l"
                     (expand-file-name suite directory)
                     "-f" "ert-run-tests-batch-and-exit")))
        (princ (buffer-string))
        (unless (eq status 0)
          (error "Isabelle test suite failed: %s (exit %s)" suite status))))))

;;; test_isabelle_emacs.el ends here
