;;; test_isabelle_lsp.el --- Real Isabelle LSP smoke test -*- lexical-binding: t; -*-
(require 'package)
(package-initialize)
(require 'cl-lib)
(defvar my/isabelle-auto-start nil)
(load (expand-file-name "../dotfiles/emacs/my-isabelle.el"
                        (file-name-directory load-file-name)) nil t)

(defun my/test-isabelle-wait (description predicate &optional seconds)
  (let ((deadline (+ (float-time) (or seconds 60))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.2))
    (unless (funcall predicate) (error "Timed out: %s" description))
    (princ (format "PASS: %s\n" description))))

(let* ((directory (make-temp-file "isabelle-lsp-" t))
       (file (expand-file-name "Live_Check.thy" directory))
       (lsp-session-file (expand-file-name "lsp-session" directory))
       (lsp-auto-guess-root t)
       (lsp-enable-file-watchers nil)
       (lsp-enable-indentation nil)
       (lsp-enable-on-type-formatting nil)
       (text "theory Live_Check imports Main begin\nlemma identity: \"P \\<Longrightarrow> P\"\nproof -\n  assume p: P\n  show P using p by assumption\nqed\nend\n")
       buffer)
  (unwind-protect
      (progn
        (with-temp-file file (insert text))
        (setq buffer (find-file-noselect file))
        (switch-to-buffer buffer)
        (lsp-workspace-folders-add directory)
        (call-interactively (key-binding (kbd "C-c C-l")))
        (my/test-isabelle-wait "LSP initialized" #'lsp-workspaces 90)
        (my/test-isabelle-wait
         "PIDE output initialized"
         (lambda () (buffer-live-p lsp-isar-output-state-buffer)))
        (goto-char (point-min))
        (forward-line 4)
        (search-forward "show P")
        (lsp-isar-caret--send-caret-update)
        (my/test-isabelle-wait
         "live proof-state feedback"
         (lambda () (with-current-buffer lsp-isar-output-state-buffer
                      (string-match-p "goal\\|subgoal\\|proof" (buffer-string)))))
        (princ (with-current-buffer lsp-isar-output-state-buffer
                 (concat "STATE: " (buffer-string) "\n")))
        (goto-char (point-min))
        (search-forward "by assumption")
        (replace-match "by nonexistent_method" t t)
        (save-buffer)
        (when (buffer-modified-p) (error "Single save left theory modified"))
        (lsp--flush-delayed-changes)
        (my/test-isabelle-wait
         "deliberate error diagnostic"
         (lambda () (cl-some
                     (lambda (diagnostic)
                       (string-match-p "nonexistent_method"
                                       (lsp:diagnostic-message diagnostic)))
                     (gethash (lsp--fix-path-casing buffer-file-name)
                              (lsp-diagnostics t)))))
        (goto-char (point-min))
        (search-forward "by nonexistent_method")
        (replace-match "by assumption" t t)
        (save-buffer)
        (lsp--flush-delayed-changes)
        (my/test-isabelle-wait
         "completed proof has no error diagnostics"
         (lambda () (not (cl-some
                          (lambda (diagnostic)
                            (= 1 (or (lsp:diagnostic-severity? diagnostic) 1)))
                          (gethash (lsp--fix-path-casing buffer-file-name)
                                   (lsp-diagnostics t))))))
        (princ "PASS: LSP editing/error/recovery round-trip\n"))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (dolist (workspace (lsp-workspaces)) (lsp-workspace-shutdown workspace))
        (set-buffer-modified-p nil)
        (kill-buffer buffer)))
    (delete-directory directory t)))

;;; test_isabelle_lsp.el ends here
