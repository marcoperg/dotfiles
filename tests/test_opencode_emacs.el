;;; test_opencode_emacs.el --- Direct OpenCode launch checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'project)

(defvar vterm-shell nil)

;; Load just the launch definitions without running the workstation init or
;; requiring a native terminal module in batch mode.
(let ((init (expand-file-name "../dotfiles/emacs/init.el"
                              (file-name-directory load-file-name))))
  (with-temp-buffer
    (insert-file-contents init)
    (goto-char (point-min))
    (condition-case nil
        (while t
          (let ((form (read (current-buffer))))
            (when (and (eq (car-safe form) 'defun)
                       (memq (cadr form)
                              '(my/opencode-start-direct my/opencode my/opencode2)))
              (eval form t))))
      (end-of-file nil))))

(provide 'vterm)

(ert-deftest opencode-direct-launch-selects-version-directory-and-fresh-buffer ()
  (dolist (in-project '(t nil))
    (let* ((default-directory "/tmp/current directory/")
           (root (if in-project "/tmp/project root/" default-directory))
           (calls nil)
           (configured nil)
           (buffers nil))
      (cl-letf (((symbol-function 'project-current)
                 (lambda (&rest _) (and in-project 'test-project)))
                ((symbol-function 'project-root)
                 (lambda (_) "/tmp/project root/"))
                ((symbol-function 'vterm)
                 (lambda (name)
                   (push (list name default-directory vterm-shell) calls)
                   (let ((buffer (get-buffer-create name)))
                     (push buffer buffers)
                     buffer)))
                ((symbol-function 'my/opencode-configure-vterm-buffer)
                 (lambda () (push (current-buffer) configured))))
        (unwind-protect
            (progn
              (dolist (entry '((my/opencode "" "~/.local/bin/opencode")
                               (my/opencode2 "2" "~/.local/bin/opencode2")))
                (pcase-let ((`(,command ,version ,executable) entry))
                  (let ((first (funcall command))
                        (second (funcall command)))
                    (should-not (eq first second))
                    (should (memq first configured))
                    (should (memq second configured))
                    (dolist (call (cl-subseq calls 0 2))
                      (should (string-prefix-p
                               (format "*opencode%s:%s" version
                                       (file-name-nondirectory
                                        (directory-file-name root)))
                               (car call)))
                      (should (equal (cadr call) root))
                      (should (equal (caddr call)
                                     (mapconcat #'shell-quote-argument
                                                (list (expand-file-name executable)
                                                      root)
                                                " ")))))))
              (should (= (length calls) 4)))
          (mapc #'kill-buffer buffers))))))

(ert-run-tests-batch-and-exit)
