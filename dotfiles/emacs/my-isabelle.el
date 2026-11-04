;;; my-isabelle.el --- Pinned Isabelle development -*- lexical-binding: t; -*-

(require 'json)
(require 'easymenu)
(defconst my/isabelle-profile-file
  (expand-file-name "../isabelle/profile.json"
                    (file-name-directory (file-truename load-file-name))))
(defconst my/isabelle-profile
  (json-read-file my/isabelle-profile-file))
(defconst my/isabelle-home
  (expand-file-name (alist-get 'isabelle_home my/isabelle-profile)))
(defvar my/isabelle-auto-start t
  "Start the pinned LSP prover when opening a theory; nil for offline editing.")

(defun my/isabelle-check-installation ()
  "Report missing external checkouts with an actionable bootstrap command."
  (dolist (entry '((isar_mode_home . "isar-mode.el")
                   (lsp_mode_home . "lsp-mode.el")
                   (isabelle_home . "src/Tools/emacs-lsp/lsp-isar/lsp-isar.el")
                   (isabelle_home . "etc/symbols")
                   (isabelle_home . "bin/isabelle")))
    (let ((file (expand-file-name
                 (cdr entry) (expand-file-name
                              (alist-get (car entry) my/isabelle-profile)))))
      (unless (file-readable-p file)
        (user-error "Missing Isabelle dependency: %s. Run: python3 %s --install"
                    file (shell-quote-argument
                          (expand-file-name "setup.py"
                                            (file-name-directory
                                             my/isabelle-profile-file)))))))
  ;; Keep this dependency list aligned with the pinned lsp-mode Package-Requires.
  (dolist (library '("dash" "f" "ht" "spinner" "markdown-mode" "lv"))
    (unless (locate-library library)
      (user-error "Missing Emacs dependency: %s. Run M-x package-install RET lsp-mode to install its dependencies"
                  library))))

(my/isabelle-check-installation)

(add-to-list 'load-path
             (expand-file-name (alist-get 'isar_mode_home my/isabelle-profile)))
(add-to-list 'load-path
             (expand-file-name (alist-get 'lsp_mode_home my/isabelle-profile)))
(add-to-list 'load-path
             (expand-file-name "clients"
                               (alist-get 'lsp_mode_home my/isabelle-profile)))
(add-to-list 'load-path
             (expand-file-name "src/Tools/emacs-lsp/lsp-isar" my/isabelle-home))

(require 'isar-mode)
;; Leave the user's existing Evil configuration and initial-state choices alone.
(setq unicode-tokens-use-shortcuts nil
      isar-mode-remove-utf8-when-saving t)

;; The official table also covers newer symbols absent from the mode's table.
(with-temp-buffer
  (insert-file-contents (expand-file-name "etc/symbols" my/isabelle-home))
  (while (re-search-forward
          "^\\\\<\\([^>]+\\)>[ \t]+code:[ \t]+0x\\([[:xdigit:]]+\\)" nil t)
    (let ((entry (list (match-string 1)
                       (string (string-to-number (match-string 2) 16)))))
      (setq isar-symbols-tokens
            (cons entry (assoc-delete-all (car entry) isar-symbols-tokens)))
      (setq isar-token-symbol-map
            (cons entry (assoc-delete-all (car entry) isar-token-symbol-map))))))

(require 'lsp-isar)
(setq lsp-isar-path-to-isabelle my/isabelle-home
      lsp-isar-parse-use nil
      lsp-isar-output-use-async nil
      lsp-isabelle-options
      (append (list "-l" (alist-get 'logic my/isabelle-profile)
                    "-o" "quick_and_dirty=false" "-o" "threads=2")
              (apply #'append
                     (mapcar (lambda (dir) (list "-d" (expand-file-name dir)))
                             (append (alist-get 'session_directories
                                                my/isabelle-profile) nil)))))

(defun my/isabelle-output ()
  "Display the live proof state without imposing an editor layout."
  (interactive)
  (display-buffer (get-buffer-create "*lsp-isar-state*")))

(defun my/isabelle-build ()
  "Independently check the profile's session with quick_and_dirty=false."
  (interactive)
  (compile (concat
            (shell-quote-argument
             (expand-file-name "../bin/isabelle-dev"
                               (file-name-directory my/isabelle-profile-file)))
            " build")))

(defun my/isabelle-setup ()
  "Keep theory editing, disk synchronization, and input methods independent."
  ;; auto-revert never replaces buffers with unsaved edits.
  (auto-revert-mode 1)
  ;; Theories do not need snippets; avoid requiring an unrelated snippet package.
  (setq-local lsp-enable-snippet nil)
  (when my/isabelle-auto-start
    (lsp-isar-define-client-and-start)))

(add-hook 'isar-mode-hook #'my/isabelle-setup)
(define-key isar-mode-map (kbd "C-c C-l") #'lsp-isar-define-client-and-start)
(define-key isar-mode-map (kbd "C-c C-o") #'my/isabelle-output)
(define-key isar-mode-map (kbd "C-c C-k") #'my/isabelle-build)
;; C-x s remains save-some-buffers.  Upstream Sledgehammer is under C-c C-h.

(easy-menu-define my/isabelle-menu isar-mode-map
  "Isabelle editing, proof development, and symbol commands."
  '("Isabelle"
    ["Start live checking" lsp-isar-define-client-and-start t]
    ["Show proof state" my/isabelle-output t]
    ["Build configured session" my/isabelle-build t]
    "--"
    ["Sledgehammer interface" lsp-isar-sledgehammer-interface (lsp-workspaces)]
    ["Insert Sledgehammer" lsp-isar-insert-sledgehammer-and-call (lsp-workspaces)]
    ["Try proof methods (try0)" lsp-isar-insert-try-and-call (lsp-workspaces)]
    ("Symbols"
     ["Insert symbol by name..." unicode-tokens-insert-token t]
     ["List symbols" unicode-tokens-list-tokens t]
     ["List input shortcuts" unicode-tokens-list-shortcuts t]
     ["Display mathematical symbols" unicode-tokens-mode
      :style toggle :selected (bound-and-true-p unicode-tokens-mode)])
    ("Input methods"
     ["Choose input method..." set-input-method t]
     ["Toggle selected input method" toggle-input-method t])
    "--"
    ["Mode help" describe-mode t]
    ["Isabelle keybindings" (describe-keymap isar-mode-map) t]
    ["Isabelle settings..." (customize-apropos "isar") t]))

(provide 'my-isabelle)
;;; my-isabelle.el ends here
