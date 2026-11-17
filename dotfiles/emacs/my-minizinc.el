;;; my-minizinc.el --- MiniZinc editing and solver menu -*- lexical-binding: t; -*-

;; Package installation is managed by init.el.  See the dotfiles README for
;; the MiniZinc executable and one-time tree-sitter grammar setup.

(require 'use-package)

(defvar minizinc-ts-program)
(defvar minizinc-ts-compile-function)
(declare-function minizinc-ts-solve "minizinc-ts-mode" (file &optional solver))

(defun my/minizinc-solve-with-solver ()
  "Solve the current model after asking which solver to use."
  (interactive)
  (let ((current-prefix-arg '(4)))
    (call-interactively #'minizinc-ts-solve)))

(defun my/minizinc-check ()
  "Save and check the current MiniZinc model without solving it."
  (interactive)
  (unless buffer-file-name
    (user-error "Save the model to a file first"))
  (save-buffer)
  (funcall minizinc-ts-compile-function
           (mapconcat #'shell-quote-argument
                      (list minizinc-ts-program "--model-check-only"
                            buffer-file-name)
                      " ")))

(use-package minizinc-ts-mode
  :mode "\\.[mdfo]zn\\'"
  :bind (:map minizinc-ts-mode-map
              ("C-c C-t" . my/minizinc-check)
              ("C-c C-k" . kill-compilation))
  :config
  (require 'compile)
  (require 'easymenu)
  (easy-menu-define my/minizinc-menu minizinc-ts-mode-map
    "MiniZinc model commands."
    '("MiniZinc"
      ["Solve Model" minizinc-ts-solve
       :enable buffer-file-name :keys "C-c C-s"]
      ["Solve with Another Solver..." my/minizinc-solve-with-solver
       :enable buffer-file-name :keys "C-u C-c C-s"]
      ["Check Model" my/minizinc-check :enable buffer-file-name]
      "---"
      ["Stop Solver" kill-compilation
       :enable (and (buffer-live-p compilation-last-buffer)
                    (get-buffer-process compilation-last-buffer))]
      ["Next Error" next-error :keys "M-g n"]
      ["Previous Error" previous-error :keys "M-g p"]
      "---"
      ["MiniZinc Manual"
       (browse-url "https://docs.minizinc.org/en/stable/") t]
      ["Customize MiniZinc" (customize-group 'minizinc-ts) t])))

(provide 'my-minizinc)
;;; my-minizinc.el ends here
