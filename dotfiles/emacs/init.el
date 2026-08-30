;;; init.el --- Personal Emacs configuration -*- lexical-binding: t; -*-

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)

(defconst my/required-packages
  '(auctex
    auto-dim-other-buffers
    citar
    company
    eat
    elfeed
    elfeed-org
    evil
    evil-collection
    flycheck
    flycheck-color-mode-line
    flycheck-pos-tip
    gptel
    org-roam
    pdf-tools
    undo-fu
    visual-fill-column
    vterm)
  "Packages installed automatically by this configuration.")

(defun my/ensure-required-packages ()
  "Install packages from `my/required-packages' that are missing."
  (let ((missing (seq-remove #'package-installed-p my/required-packages)))
    (when missing
      (package-refresh-contents)
      (dolist (pkg missing)
        (condition-case err
            ;; DONT-SELECT keeps package.el from rewriting this tracked file.
            (package-install pkg t)
          (error
           (display-warning
            'packages
            (format "Could not install %s: %s" pkg (error-message-string err))
            :warning)))))))

(my/ensure-required-packages)

(condition-case err
    (load-theme 'modus-vivendi t)
  (error
   (message "Modus Vivendi unavailable (%s); using Wombat" (error-message-string err))
   (load-theme 'wombat t)))
(global-visual-line-mode t)
(global-auto-revert-mode t)

; === SOME GLOBAL PREFERENCES ===
;; Prefer vert split
(setq split-height-threshold nil)  ; disable horizontal splitting
(setq split-width-threshold 0)     ; always prefer vertical splits

(setenv "PATH" (concat (getenv "PATH") ":/opt/homebrew/bin"))
(add-to-list 'exec-path "/opt/homebrew/bin")

(global-display-line-numbers-mode)
(setq-default display-line-numbers-type 'relative)

(setq backup-directory-alist '(("." . "~/.emacs.d/backups")))

; GPG Config
(setq epa-pinentry-mode 'loopback)
;; Praxis Secreta key must never linger in the gpg-agent cache: flush its
;; keygrip right after each decrypt so every secreta note re-prompts. The
;; mail/identity key keeps its normal 24h cache -- only this keygrip is
;; evicted, and clearing a non-cached keygrip is a harmless no-op.
(defconst my/secreta-keygrip "FC5833230506D9A8A4A24F2F951C5DC6AF027CE2")
;; (defun my/flush-secreta-passphrase (&rest _)
;;   (call-process "gpg-connect-agent" nil 0 nil
;;                 (format "CLEAR_PASSPHRASE --mode=normal %s" my/secreta-keygrip) "/bye"))

(defun my/flush-secreta-passphrase (&rest _)
  (call-process "gpg-connect-agent"
                nil 0 nil
                "CLEAR_PASSPHRASE"
                "--mode=normal"
                my/secreta-keygrip
                "/bye"))

(advice-add 'epg-decrypt-file   :after #'my/flush-secreta-passphrase)
(advice-add 'epg-decrypt-string :after #'my/flush-secreta-passphrase)

;; Open files
(defun my/open-marked-file ()
  "Open the file whose path is currently marked (selected) in the buffer."
  (interactive)
  (if (use-region-p)
      (let ((filename (buffer-substring-no-properties (region-beginning) (region-end))))
        (setq filename (expand-file-name filename))
        (if (file-exists-p filename)
            (find-file filename)
          (message "File does not exist: %s" filename)))
    (message "No region selected")))

(global-set-key (kbd "C-c C-o") #'my/open-marked-file)

;; Dim other buffers
;; See: https://github.com/mina86/auto-dim-other-buffers.el/blob/master/README.md
(add-hook 'after-init-hook (lambda ()
 (when (fboundp 'auto-dim-other-buffers-mode)
   (auto-dim-other-buffers-mode t))))

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(initial-buffer-choice t)
 '(package-selected-packages
   '(citar claude-code-ide company eat evil evil-collection flycheck
		     flycheck-color-mode-line flycheck-pos-tip undo-fu))
 '(package-vc-selected-packages
   '((claude-code-ide :url
		      "https://github.com/manzaltu/claude-code-ide.el")))
 '(warning-suppress-log-types '((native-compiler) (lsp-mode))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

; (setq initial-buffer-choice (lambda () (dired "~/docs/")))
(when (string= system-type "darwin")
  (setq dired-use-ls-dired nil))


; === TEX MODE ===
;; TeX (https://chatgpt.com/share/682a517f-6cb8-8002-be7a-a0d9f44ae0fe)
(setq TeX-view-evince-keep-focus nil) ;; or whichever viewer you use
;(setq TeX-view-program-selection
;      '((output-pdf "PDF Tools")))

(setq TeX-view-program-selection
      '((output-pdf "PDF Tools"))
      TeX-view-program-list
      '(("PDF Tools" TeX-pdf-tools-sync-view)))

(setq TeX-view-ps-select 'always)    ;; always other window

(add-hook 'LaTeX-mode-hook
  (lambda ()
    (TeX-PDF-mode 1)
    (TeX-source-correlate-mode 1)
    (setq TeX-source-correlate-start-server t)
    (auto-revert-mode 1)))  ; auto-refresh PDF viewer

;; Live update the PDF buffer without manual revert
(add-hook 'pdf-view-mode-hook 'auto-revert-mode)

;; Prefer line highlighting instead of rectangle when jumping
(setq pdf-view-display-size 'fit-page)

(defun my-TeX-file-has-documentclass-p (f)
  "Non-nil if file F contains \\documentclass in its first KB."
  (and f (file-readable-p f)
       (with-temp-buffer
         (insert-file-contents f nil 0 1000) ; only first KB
         (goto-char (point-min))
         (re-search-forward "\\\\documentclass" nil t))))

(defun my-TeX-master-from-documentclass ()
  "Return the master .tex file (the one with \\documentclass).
If the current buffer's own file has \\documentclass it is its own master;
otherwise search its directory for a sibling that does.  Checking the current
file first is what makes a directory with several master files (e.g. two decks
that share \\input fragments) each compile itself."
  (if (my-TeX-file-has-documentclass-p buffer-file-name)
      buffer-file-name                    ; this file IS a master
    (let ((dir (locate-dominating-file
                (or buffer-file-name default-directory)
                (lambda (d)
                  (directory-files d nil "\\.tex\\'" t)))))
      (when dir
        (catch 'found
          (dolist (f (directory-files dir t "\\.tex\\'" t))
            (when (my-TeX-file-has-documentclass-p f)
              (throw 'found f))))))))

;; AUCTeX's `TeX-master' does NOT accept a function value; it only understands
;; nil/t/'shared/'dwim/string.  So we run the finder ourselves on mode entry and
;; set a concrete value, which stops AUCTeX from ever prompting for the master.
(defun my-TeX-set-master ()
  "Set `TeX-master' from the file containing \\documentclass, without prompting."
  (unless (TeX-local-master-p)          ; respect an explicit `% TeX-master:' line
    (let ((master (my-TeX-master-from-documentclass)))
      (setq TeX-master
            (cond
             ((null master) t)          ; nothing found: treat file as its own master
             ((string= (file-truename master)
                       (file-truename (or buffer-file-name "")))
              t)                         ; this file *is* the master
             (t (file-name-sans-extension master)))))))

(add-hook 'LaTeX-mode-hook #'my-TeX-set-master)

;; Never let AUCTeX write a `% TeX-master:' line into my files.
(setq TeX-one-master "<none>")

(with-eval-after-load 'tex
  ;; 1. Define the LatexMk command
  (add-to-list 'TeX-command-list
               '("LatexMk"
                 "latexmk -pdf -interaction=nonstopmode %t"
                 TeX-run-TeX 
                 nil 
                 t 
                 :help "Run LatexMk") 
               t)
  
  ;; ;; 2. FORCE LatexMk as the default
  ;; ;;    AUCTeX normally tries to guess the next command. 
  ;; ;;    This hook forces it to "LatexMk" every time.
  ;; (add-hook 'TeX-mode-hook
  ;;           (lambda () (setq TeX-command-default "LatexMk")))
  
  ;; ;; 3. Ensure this applies to derived modes (LaTeX-mode) as well
  ;; (add-hook 'LaTeX-mode-hook
  ;;           (lambda () (setq TeX-command-default "LatexMk"))))
)

; === PDF READER ===
(add-hook 'pdf-view-mode-hook (lambda () (display-line-numbers-mode -1)))

(customize-set-variable 'tramp-default-method "ssh")

(with-eval-after-load 'doc-view
  (define-key doc-view-mode-map (kbd "C-c p") 'doc-view-fit-page-to-window))

(defun my/pdf-view-disable-cursor ()
  "Disable the cursor in pdf-view-mode, even with evil-mode."
  (setq-local cursor-type nil)
  (setq-local evil-normal-state-cursor '(nil)) ; no cursor in normal state
  (setq-local evil-visual-state-cursor '(nil)) ; no cursor in visual state
  (setq-local evil-insert-state-cursor '(nil)) ; no cursor in insert state
  (setq-local evil-replace-state-cursor '(nil)) ; no cursor in replace state
  (setq-local evil-operator-state-cursor '(nil)) ; no cursor in operator state
  (blink-cursor-mode 0))

(add-hook 'pdf-view-mode-hook #'my/pdf-view-disable-cursor)

(with-eval-after-load 'pdf-view
  (defun my/pdf-scroll-left (&optional arg)
    "Scroll PDF view to the left."
    (interactive "p")
    (image-scroll-left (or arg 10)))

  (defun my/pdf-scroll-right (&optional arg)
    "Scroll PDF view to the right."
    (interactive "p")
    (image-scroll-right (or arg 10)))

  (define-key pdf-view-mode-map (kbd "<wheel-left>") 'my/pdf-scroll-left)
  (define-key pdf-view-mode-map (kbd "<wheel-right>") 'my/pdf-scroll-right))

; beamer mode

(defun my/pdf-presentation-mode ()
  "Open PDF in presentation mode: fullscreen, no mode-line or minibuffer."
  (interactive)
  (delete-other-windows)
  (when (fboundp 'toggle-frame-fullscreen)
    (toggle-frame-fullscreen))
  (pdf-view-fit-page-to-window)
  (setq mode-line-format nil)
  (redraw-display))

(defun my/pdf-presentation-in-new-frame (file)
  "Open PDF FILE in a new fullscreen frame for presentation."
  (interactive "fPDF file: ")
  (let ((frame (make-frame '((name . "Presentation")
                             (fullscreen . fullboth)))))
    (select-frame-set-input-focus frame)
    (find-file file)
    (pdf-view-mode)
    (pdf-presentation-mode)))


; EVIL MODE
(defconst evil_mode_enabled t
  "If not-nil, activate evil mode.")
(when evil_mode_enabled
  (use-package undo-fu :ensure t)
  (use-package evil
    :ensure t
    :init
    (setq evil-undo-system 'undo-fu
          ;; https://github.com/emacs-evil/evil-collection/issues/60
          evil-want-keybinding nil)
    :config
    (evil-mode 1))
  (use-package evil-collection
    :ensure t
    :after evil
    :config
    (evil-collection-init)
    (evil-collection-define-key 'normal 'doc-view-mode-map
      "j" 'doc-view-next-page
      "k" 'doc-view-previous-page)))

(with-eval-after-load 'evil-maps
  (define-key evil-motion-state-map (kbd "SPC") nil)
  (define-key evil-motion-state-map (kbd "RET") nil)
  (define-key evil-motion-state-map (kbd "TAB") nil))

;; Shell names
;; New version that reuses deleted shell names
(defun new-shell ()
  "Same as shell, but gives the shell an appropriate name"
  (interactive)
  (setq new_shell_name (find-free-shell-name 0))
  (new-named-shell new_shell_name)
  )

(defun find-free-shell-name (n)
  (setq current-shell-name (concat (int-to-string (+ n 1)) "shell"))
  (if (get-buffer current-shell-name) 
      (find-free-shell-name (+ n 1))
    current-shell-name))
(global-set-key "\C-cns" 'new-shell)

(defun new-named-shell (name &optional target-dir)
  (interactive)
  (shell name)
  (switch-to-buffer name)
  (message (concat "Target dir is " target-dir))
  (if target-dir
      (let ((string (concat "cd " target-dir " \n")))
	(message (concat "Switching to " target-dir))
	(cd target-dir)
	(let ((inhibit-read-only t))
	  (insert-before-markers string))
	(process-send-string
	 (get-buffer-process (current-buffer))
	 string))))

; === ORG MODE ===
(setq org-return-follows-link t)
(setq visual-fill-column-width 100) ; Change to desired max width
(setq visual-fill-column-center-text t)
(defun my/org-maybe-disable-line-numbers ()
  "Disable line numbers if the current file is in an 'episteme' folder."
  (when (and buffer-file-name
             (string-match-p "/episteme/" (file-truename buffer-file-name)))
    (display-line-numbers-mode 0)
    (visual-line-mode 1)
    (visual-fill-column-mode 1)))

(add-hook 'org-mode-hook #'my/org-maybe-disable-line-numbers)



(setq org-roam-directory (file-truename "~/knowledge/episteme"))
(load "~/knowledge/praxis/lisp/praxis-utils.el")
(add-to-list 'load-path
             (expand-file-name "~/knowledge/episteme/lisp"))
(require 'episteme-citations)

(use-package citar
  :ensure t
  :no-require
  :custom
  (org-cite-global-bibliography
   (list (expand-file-name "~/knowledge/bibliotheca/zotero-library.bib")))
  (org-cite-insert-processor 'citar)
  (org-cite-follow-processor 'citar)
  (org-cite-activate-processor 'citar)
  (citar-bibliography org-cite-global-bibliography)
  (citar-open-entry-function #'episteme-open-bibliotheca-entry)
  ;; Bibliotheca is the catalogue; source-specific notes remain hand-authored.
  (citar-open-resources '(:files :links))
  :hook
  (org-mode . citar-capf-setup)
  :bind
  (("C-c B" . episteme-citation-dwim)
   (:map org-mode-map :package org
         ("C-c b" . org-cite-insert))))

(when (and (require 'org-roam nil t)
           (require 'use-package nil t))
  (org-roam-db-autosync-mode)
  (use-package org-roam
    :after org
    :custom
    (org-roam-directory (file-truename org-roam-directory))
    :init
    (org-roam-setup)
    :bind (("C-c n f" . org-roam-node-find)
           ("C-c n r" . org-roam-node-random)		    
           (:map org-mode-map
                 (("C-c n i" . org-roam-node-insert)
                  ("C-c n o" . org-id-get-create)
                  ("C-c n t" . org-roam-tag-add)
                  ("C-c n a" . org-roam-alias-add)
                  ("C-c n l" . org-roam-buffer-toggle))))))

(defun my/org-roam-get-path ()
  "Create Org-roam note path in current buffer's directory using raw title."
  (let* ((default-dir (file-name-directory (or (buffer-file-name) default-directory)))
         (title (read-string "Note title: "))
         ;; Replace problematic characters from the title for filenames
         (safe-title (replace-regexp-in-string "[/:*?\"<>|]" "-" title))
         (path (expand-file-name (concat safe-title ".org") default-dir)))
    (setq org-roam-capture--info `((title . ,title)))
    path))

(setq org-roam-capture-templates
       '(("d" "default" plain
         "%?"
         :if-new (file+head "%(my/org-roam-get-path)"
                            "#+title: ${title}\n")
         :unnarrowed t)))

(defun my/org-export-to-pdf-in-dotpdfs ()
  "Export current Org file to PDF, move it to a '.pdfs' folder, delete the .tex file, and open the PDF unless already open."
  (interactive)
  (unless (eq major-mode 'org-mode)
    (error "This command only works in Org mode"))
  (let* ((org-file (buffer-file-name))
         (base-name (file-name-base org-file))
         (default-directory (file-name-directory org-file))
         (pdfs-dir (expand-file-name ".pdfs" default-directory))
         (tex-file (expand-file-name (concat base-name ".tex") default-directory)))
    (unless (file-exists-p pdfs-dir)
      (make-directory pdfs-dir))
    ;; Export to PDF
    (let ((pdf-file (org-latex-export-to-pdf)))
      (when pdf-file
        (let* ((pdf-filename (file-name-nondirectory pdf-file))
               (target-file (expand-file-name pdf-filename pdfs-dir)))
          ;; Move PDF
          (rename-file pdf-file target-file t)
          ;; Delete .tex file
          (when (file-exists-p tex-file)
            (delete-file tex-file))
          (message "PDF exported to: %s" target-file))))))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-v") #'my/org-export-to-pdf-in-dotpdfs))

(with-eval-after-load 'org
  (plist-put org-format-latex-options :scale 4))
(defun my/image-scale-advice (image)
  (let* ((factor (image-property image :scale))
         (new-factor (if factor
                         (/ factor 4.0)
                       0.25)))
    (image--set-property image :scale new-factor)
    image))
(advice-add 'org--create-inline-image :filter-return #'my/image-scale-advice)
(defun my/overlay-scale-advice (beg end image &optional imagetype)
  (mapc (lambda (ov) (if (equal (overlay-get ov 'org-overlay-type) 'org-latex-overlay)
                                (overlay-put ov
                                             'display
                                             (list 'image :type (or (intern imagetype) 'png) :file image :ascent 'center :scale 0.25))))
        (overlays-at beg)))
(advice-add 'org--make-preview-overlay :after #'my/overlay-scale-advice)

(defun my/export-all-org-in-dir (&optional dir)
  "Recursively export all .org files under DIR (default: `default-directory`)
to PDF using `my/org-export-to-pdf-in-dotpdfs`."
  (interactive "DDirectory: ")
  (let* ((target-dir (or dir default-directory))
         (org-files (directory-files-recursively target-dir "\\.org$")))
    (dolist (file org-files)
      (message "Exporting: %s" file)
      (with-current-buffer (find-file-noselect file)
        (setq org-confirm-babel-evaluate nil) ;; avoid prompts
        (condition-case err
            (my/org-export-to-pdf-in-dotpdfs)
          (error (message "Error exporting %s: %s" file err)))
        (kill-buffer)))))

(defun create-weekly-note-from-template ()
  "Create a weekly Org note using a template from a folder."
  (let* ((template-file "~/knowledge/praxis/planning/weekly-template.org")
         (week-file (format "~/knowledge/praxis/planning//weeks/week-%s-%s.org"
                            (format-time-string "%Y")
                            (format-time-string "%W"))))
    (unless (file-exists-p week-file)
      (copy-file template-file week-file)
      (with-current-buffer (find-file-noselect week-file)
        ;; Replace placeholders
        (goto-char (point-min))
        (while (re-search-forward "%W" nil t)
          (replace-match (format-time-string "%W")))
        (goto-char (point-min))
        (while (re-search-forward "%Y" nil t)
          (replace-match (format-time-string "%Y")))
        (save-buffer)))
    week-file))  ;; Return the path to capture into


(setq org-capture-templates
      '(("w" "Weekly Note" entry
         ;; Instead of file+headline, use a function that creates/returns the file
         (function create-weekly-note-from-template)
         "%?"  ;; Cursor will be placed here after creation
         :empty-lines 1)))

(defun open-current-weekly-note ()
  "Open the weekly note for the current week."
  (interactive)
  (let ((week-file (format "~/knowledge/praxis/planning/weeks/week-%s-%s.org"
                           (format-time-string "%Y")
                           (format-time-string "%W"))))
    (if (file-exists-p week-file)
        (find-file week-file)
      (message "Weekly note does not exist yet. Use capture to create it."))))

(defun open-or-create-current-weekly-note ()
  "Open or create the weekly note for the current week."
  (interactive)
  (let ((week-file (create-weekly-note-from-template))) ;; uses your template function
    (find-file week-file)))

(with-eval-after-load 'dired
  (define-key dired-mode-map (kbd "C-c w") #'open-or-create-current-weekly-note)
  (define-key dired-mode-map (kbd "C-c c") #'org-capture))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c w") #'open-or-create-current-weekly-note)
  (define-key org-mode-map (kbd "C-c c") #'org-capture))

; === MAIL ===
;; mu4e ships with the external mu program, not as an ELPA package.
(let ((local-mu4e-dir (expand-file-name "~/.local/share/emacs/site-lisp/mu4e")))
  (when (file-directory-p local-mu4e-dir)
    (add-to-list 'load-path local-mu4e-dir)))
(dolist (dir (append
              '("/usr/share/emacs/site-lisp/mu4e"
                "/usr/local/share/emacs/site-lisp/mu4e"
                "/usr/local/share/emacs/site-lisp/mu/mu4e"
                "/usr/local/opt/mu/share/emacs/site-lisp/mu4e"
                "/usr/local/opt/mu/share/emacs/site-lisp/mu/mu4e"
                "/opt/homebrew/share/emacs/site-lisp/mu4e"
                "/opt/homebrew/share/emacs/site-lisp/mu/mu4e"
                "/opt/homebrew/opt/mu/share/emacs/site-lisp/mu4e"
                "/opt/homebrew/opt/mu/share/emacs/site-lisp/mu/mu4e")
              (file-expand-wildcards "/usr/share/emacs/site-lisp/elpa/mu4e-*")
              (file-expand-wildcards "/usr/local/Cellar/mu/*/share/emacs/site-lisp/mu4e")
              (file-expand-wildcards "/usr/local/Cellar/mu/*/share/emacs/site-lisp/mu/mu4e")
              (file-expand-wildcards "/opt/homebrew/Cellar/mu/*/share/emacs/site-lisp/mu4e")
              (file-expand-wildcards "/opt/homebrew/Cellar/mu/*/share/emacs/site-lisp/mu/mu4e")))
  (when (file-directory-p dir)
    (add-to-list 'load-path dir t)))
(when (require 'mu4e nil t)

;; Base configuration
(let ((local-mu (expand-file-name "~/.local/bin/mu")))
  (when (file-executable-p local-mu)
    (setq mu4e-mu-binary local-mu)))
(setq mu4e-maildir "~/Mail")
;; Getting mail
(setq mu4e-get-mail-command "mbsync -a")
(setq mu4e-update-interval (* 10 60)) ;; Sync every 10 minutes
(setq mu4e-change-filenames-when-moving t)
(setq mu4e-headers-date-format "%Y/%m/%d")

(setq mu4e-bookmarks
      '((:name "Unread messages"
               :query "flag:unread AND NOT flag:trashed AND NOT maildir:/UPM/Trash AND NOT maildir:/IMDEA/Deleted\ Messages AND NOT maildir:/UPM/Archive AND NOT maildir:/IMDEA/Archive"
               :key ?u)
        (:name "Today's messages"
               :query "date:today..now AND NOT flag:trashed AND NOT maildir:/UPM/Trash AND NOT maildir:/IMDEA/Deleted\ Messages AND NOT maildir:/UPM/Archive AND NOT maildir:/IMDEA/Archive"
               :key ?t)
	(:name "Last 7 days"
	       :query "date:7d..now AND NOT flag:trashed AND NOT maildir:/UPM/Trash AND NOT maildir:/IMDEA/Deleted\ Messages AND NOT maildir:/UPM/Archive AND NOT maildir:/IMDEA/Archive"
	       :hide-unread t
	       :key ?w)
	(:name "Inbox"
	       :query "(maildir:/UPM/Inbox OR maildir:/IMDEA/Inbox) AND NOT flag:trashed"
	       :hide-unread t
               :key ?i)))

;; Contexts
(setq mu4e-contexts
  (list
   ;; Personal Account Context
   (make-mu4e-context
    :name "UPM"
    :match-func (lambda (msg)
                  (when msg (string-prefix-p "/UPM" (mu4e-message-field msg :maildir))))
    :vars '((user-mail-address      . "marco.perez@alumnos.upm.es")
            (user-full-name         . "Marco Pérez González")
	    (mu4e-sent-folder       . "/UPM/Sent")
            (mu4e-drafts-folder     . "/UPM/Drafts")
            (mu4e-trash-folder      . "/UPM/Trash")
	    (mu4e-refile-folder     . "/UPM/Archive")
            (smtpmail-smtp-server   . "smtp.upm.es")
            (smtpmail-smtp-service  . 587)
            (smtpmail-stream-type   . starttls)))

   ;; Work Account Context
   (make-mu4e-context
    :name "IMDEA"
    :match-func (lambda (msg)
                  (when msg (string-prefix-p "/IMDEA" (mu4e-message-field msg :maildir))))
    :vars '((user-mail-address      . "marco.perez@imdea.org")
            (user-full-name         . "Marco Pérez González")
	    (mu4e-sent-folder       . "/IMDEA/Sent")
	    (mu4e-drafts-folder     . "/IMDEA/Drafts")
            (mu4e-trash-folder      . "/IMDEA/Deleted Messages")
	    (mu4e-refile-folder     . "/IMDEA/Archive")
            (smtpmail-smtp-server   . "mail.imdea.org")
            (smtpmail-smtp-service  . 587)
            (smtpmail-stream-type   . starttls)))))

(setq mu4e-context-policy 'pick-first)
(setq mu4e-compose-context-policy 'ask)

;; Sending
(setq auth-sources '("~/.authinfo.gpg"))

;;; With smtpmail cmd (now commented)
;; (setq message-send-mail-function 'smtpmail-send-it)
;; (setq message-send-mail-function 'smtpmail-send-it)
;; (setq message-send-mail-function 'smtpmail-send-it
;;       smtpmail-smtp-server "smtp.email.com"
;;       smtpmail-smtp-service 587
;;       smtpmail-stream-type 'starttls)

;;; With msmtp
(setq message-send-mail-function 'message-send-mail-with-sendmail
      sendmail-program "msmtp"
      sendmail-extra-arguments '("--read-envelope-from"))

(add-hook 'mu4e-compose-mode-hook
          (lambda ()
            (set-input-method "spanish-prefix"))))

; Telega package
(setq telega-server-libs-prefix "/opt/homebrew/Cellar/tdlib/HEAD-0ae923c")

; === DIRED MODE ===
(defun my/dired-open-in-file-manager ()
  "Open current directory in OS file manager."
  (interactive)
  (let ((dir (expand-file-name (dired-current-directory))))
    (cond
     ((eq system-type 'darwin)
      (call-process "open" nil 0 nil dir))  ; 0 = don't wait, detached
     ((eq system-type 'gnu/linux)
      (call-process "xdg-open" nil 0 nil dir))
     (t (message "Unsupported system type")))))

(with-eval-after-load 'dired
  (setq dired-mouse-drag-files nil)  ; prevent crash on macOS
  (add-to-list 'dired-guess-shell-alist-user
               (list "\\.py\\'" (expand-file-name "~/miniconda3/bin/python3")))
  (define-key dired-mode-map (kbd "C-c o") #'my/dired-open-in-file-manager))

(setq dired-mouse-drag-files nil)
(when (fboundp 'setopt)
  (setopt dired-mouse-drag-files nil))

; === RSS FEED ===
(setq rmh-elfeed-org-files
      (list (expand-file-name "elfeed.org" user-emacs-directory)))
(when (require 'elfeed-org nil t)
  (elfeed-org))
(setq-default elfeed-search-filter "@6-months-ago +unread -hidden")

(defun my/elfeed-purge-feed (feed-url)
  "Remove FEED-URL and all its entries from the elfeed database.
Note: also delete the feed's line from elfeed.org, or reopening
elfeed will re-subscribe on the next fetch."
  (interactive
   (let* ((entry (ignore-errors (car (elfeed-search-selected))))
          (default (and entry (elfeed-feed-url (elfeed-entry-feed entry)))))
     (list (completing-read
            (if default (format "Purge feed (default %s): " default) "Purge feed: ")
            (hash-table-keys elfeed-db-feeds) nil nil nil nil default))))
  (let (ids)
    ;; collect first — don't mutate the index while walking it
    (with-elfeed-db-visit (entry _feed)
      (when (equal (elfeed-entry-feed-id entry) feed-url)
        (push (elfeed-entry-id entry) ids)))
    (dolist (id ids)
      (avl-tree-delete elfeed-db-index id)
      (remhash id elfeed-db-entries))
    (remhash feed-url elfeed-db-feeds)
    (elfeed-db-save)
    (message "Purged %d entries from %s" (length ids) feed-url)))

;; --- Send the selected entry to wallabag (read-later on the phone) ---
;; Credentials live in ~/.authinfo.gpg, never here:
;;   machine perseo.penguin-hen.ts.net port 8443 login USER password PASS
;;   machine wallabag-api login CLIENT_ID password CLIENT_SECRET
(require 'cl-lib)
(defvar my/wallabag-host "https://perseo.penguin-hen.ts.net:8443"
  "Base URL of the wallabag instance.")

(defvar my/wallabag--token nil
  "Cached OAuth access token for the wallabag API.")

(defun my/wallabag--auth (host)
  "Return (LOGIN . SECRET) for HOST from auth-source, or signal an error."
  (let ((f (car (auth-source-search :host host :require '(:user :secret) :max 1))))
    (unless f (error "No authinfo entry for %s" host))
    (cons (plist-get f :user)
          (let ((s (plist-get f :secret)))
            (if (functionp s) (funcall s) s)))))

(defun my/wallabag--skip-headers ()
  "Move point past the HTTP headers in a url retrieval buffer."
  (goto-char (point-min))
  (re-search-forward "\r?\n\r?\n"))

(defun my/wallabag--fetch-token ()
  "Obtain and cache an OAuth token via the password grant."
  (let* ((client (my/wallabag--auth "wallabag-api"))
         (user   (my/wallabag--auth "perseo.penguin-hen.ts.net"))
         (url-request-method "POST")
         (url-request-extra-headers
          '(("Content-Type" . "application/x-www-form-urlencoded")))
         (url-request-data
          (url-build-query-string
           `(("grant_type" "password")
             ("client_id" ,(car client))
             ("client_secret" ,(cdr client))
             ("username" ,(car user))
             ("password" ,(cdr user)))))
         (buf (url-retrieve-synchronously
               (concat my/wallabag-host "/oauth/v2/token") t t)))
    (with-current-buffer buf
      (my/wallabag--skip-headers)
      (let ((json (json-parse-buffer :object-type 'alist)))
        (setq my/wallabag--token (alist-get 'access_token json))
        (unless my/wallabag--token
          (error "wallabag token error: %S" json))
        my/wallabag--token))))

(defun my/wallabag--token ()
  (or my/wallabag--token (my/wallabag--fetch-token)))

(defun my/wallabag-add-url (url)
  "Add URL to wallabag, refreshing the token once on a 401."
  (cl-flet ((post ()
              (let* ((url-request-method "POST")
                     (url-request-extra-headers
                      `(("Authorization" . ,(concat "Bearer " (my/wallabag--token)))
                        ("Content-Type" . "application/x-www-form-urlencoded")))
                     (url-request-data (url-build-query-string `(("url" ,url))))
                     (buf (url-retrieve-synchronously
                           (concat my/wallabag-host "/api/entries") t t)))
                (with-current-buffer buf
                  (goto-char (point-min))
                  (and (looking-at "HTTP/[0-9.]+ \\([0-9]+\\)")
                       (string-to-number (match-string 1)))))))
    (let ((code (post)))
      (when (eql code 401)
        (setq my/wallabag--token nil)
        (setq code (post)))
      (if (memql code '(200 201))
          (message "Sent to wallabag: %s" url)
        (error "wallabag add failed (HTTP %s)" code)))))

(defun my/elfeed-send-to-wallabag ()
  "Send the selected elfeed entry to wallabag, then mark it read."
  (interactive)
  (let ((entry (car (elfeed-search-selected))))
    (unless entry (user-error "No elfeed entry selected"))
    (my/wallabag-add-url (elfeed-entry-link entry))
    (elfeed-search-untag-all-unread)))

(with-eval-after-load 'evil
  (with-eval-after-load 'elfeed-search
    ;; Keep evil-collection's default `normal' state (which provides j/k and
    ;; all the other elfeed bindings) and only override R in that state.
    (evil-define-key 'normal elfeed-search-mode-map
      (kbd "R") #'my/elfeed-send-to-wallabag)))


; === WRITTING TOOLS ===
; LPTP
(autoload 'lptp-mode "/Users/meu/fun/lptp/etc/lptp-mode" 
    "Major mode for editing formal proofs" t)
(setq auto-mode-alist 
    (cons '("\\.pr$" . lptp-mode) auto-mode-alist))
(transient-mark-mode 1)
(add-hook 'lptp-mode #'display-line-numbers-mode)

; === AI TOOLS ===
;; Claude is the first-party coding agent. Keep arbitrary Elisp evaluation
;; disabled while retaining the navigation and diagnostics MCP tools.
(use-package claude-code-ide
  :vc (:url "https://github.com/manzaltu/claude-code-ide.el" :rev :newest)
  :bind (("C-c C-'" . claude-code-ide-menu)
         ("C-c a c" . claude-code-ide-menu))
  :custom
  (claude-code-ide-enable-execute-code nil)
  :config
  (claude-code-ide-emacs-tools-setup))

;; Claude keeps the first-party fullscreen TUI and Emacs IDE integration.
;; Evil normal state navigates the transcript; insert state edits the prompt.
(defun my/claude-code-eat-send-control (key &optional meta)
  "Send CTRL+KEY, prefixed with META when non-nil, to Claude's Eat terminal."
  (eat-term-send-string
   eat-terminal
   (concat (if meta "\e" "")
           (string (logand (string-to-char key) 31)))))

(defun my/claude-code-line-up ()
  (interactive)
  (my/claude-code-eat-send-control "y" t))

(defun my/claude-code-line-down ()
  (interactive)
  (my/claude-code-eat-send-control "e" t))

(defun my/claude-code-half-page-up ()
  (interactive)
  (my/claude-code-eat-send-control "u" t))

(defun my/claude-code-half-page-down ()
  (interactive)
  (my/claude-code-eat-send-control "d" t))

(defun my/claude-code-page-up ()
  (interactive)
  (my/claude-code-eat-send-control "b" t))

(defun my/claude-code-page-down ()
  (interactive)
  (my/claude-code-eat-send-control "f" t))

(defun my/claude-code-first-message ()
  (interactive)
  (my/claude-code-eat-send-control "h" t))

(defun my/claude-code-last-message ()
  (interactive)
  (my/claude-code-eat-send-control "l" t))

(defun my/claude-code-command ()
  "Enter insert state and begin a Claude slash command."
  (interactive)
  (evil-insert-state)
  (eat-term-send-string eat-terminal "/"))

(defun my/claude-code-interrupt ()
  "Send Escape to Claude."
  (interactive)
  (eat-term-send-string eat-terminal "\e"))

(defvar my/claude-code-eat-mode-map (make-sparse-keymap))

(define-minor-mode my/claude-code-eat-mode
  "Vim-style controls for Claude Code's fullscreen TUI in Eat."
  :lighter " Claude"
  :keymap my/claude-code-eat-mode-map)

(with-eval-after-load 'evil
  (evil-define-key 'normal my/claude-code-eat-mode-map
    "j" #'my/claude-code-line-down
    "k" #'my/claude-code-line-up
    (kbd "C-d") #'my/claude-code-half-page-down
    (kbd "C-u") #'my/claude-code-half-page-up
    (kbd "C-f") #'my/claude-code-page-down
    (kbd "C-b") #'my/claude-code-page-up
    (kbd "g g") #'my/claude-code-first-message
    "G" #'my/claude-code-last-message
    ":" #'my/claude-code-command
    "/" #'my/claude-code-command
    (kbd "<escape>") #'my/claude-code-interrupt))

(defun my/claude-code-eat-setup (&rest _)
  "Enable modal controls only in Claude Code IDE Eat buffers."
  (when (string-prefix-p "*claude-code[" (buffer-name))
    (my/claude-code-eat-mode 1)
    (evil-normal-state)))

(with-eval-after-load 'eat
  (add-hook 'eat-exec-hook #'my/claude-code-eat-setup))

;; OpenCode is the autonomous OpenAI coding agent. It uses the existing
;; ChatGPT OAuth credential managed by the OpenCode CLI.
(let ((opencode-bin-directory (expand-file-name "~/.opencode/bin")))
  (add-to-list 'exec-path opencode-bin-directory)
  (setenv "PATH" (concat opencode-bin-directory path-separator (getenv "PATH"))))

;; OpenCode uses SGR mouse reporting, which vterm does not forward from Emacs
;; mouse events.  Send clicks explicitly while leaving all keyboard input to
;; vterm and OpenCode.
(defun my/opencode-vterm-send-mouse (event button final)
  "Send mouse EVENT to OpenCode using SGR FINAL byte."
  (let* ((position (event-start event))
         (column-row (posn-col-row position 'use-window)))
    (vterm-send-string
     (format "\e[<%d;%d;%d%s"
             button
             (1+ (car column-row))
             (1+ (cdr column-row))
             final))))

(defun my/opencode-vterm-mouse-down (event)
  (interactive "e")
  (my/opencode-vterm-send-mouse event 0 "M"))

(defun my/opencode-vterm-mouse-up (event)
  (interactive "e")
  (my/opencode-vterm-send-mouse event 0 "m"))

(defun my/opencode-vterm-wheel-up (event)
  (interactive "e")
  (my/opencode-vterm-send-mouse event 64 "M"))

(defun my/opencode-vterm-wheel-down (event)
  (interactive "e")
  (my/opencode-vterm-send-mouse event 65 "M"))

(defun my/opencode-vterm-toggle-output ()
  "Send OpenCode's C-x o output toggle."
  (interactive)
  (vterm-send-key "x" nil nil t)
  (vterm-send-key "o"))

(defun my/opencode-vterm-leader-key ()
  "Forward OpenCode's C-x leader followed by the invoking key."
  (interactive)
  (vterm-send-key "x" nil nil t)
  (dolist (key (vterm--translate-event-to-args last-command-event))
    (apply #'vterm-send-key key)))

(defun my/opencode-vterm-interrupt ()
  "Send Escape directly to OpenCode."
  (interactive)
  (vterm-send-key "<escape>"))

(defun my/opencode-vterm-line-up ()
  (interactive)
  (vterm-send-key "y" nil t t))

(defun my/opencode-vterm-line-down ()
  (interactive)
  (vterm-send-key "e" nil t t))

(defun my/opencode-vterm-page-up ()
  (interactive)
  (vterm-send-key "b" nil t t))

(defun my/opencode-vterm-page-down ()
  (interactive)
  (vterm-send-key "f" nil t t))

(defconst my/opencode-leader-keys
  '("q" "e" "t" "b" "s" "x" "n" "l" "g" "c" "<down>"
    "m" "a" "y" "u" "r" "h" "o")
  "Keys used after OpenCode's C-x leader.")

(defvar my/opencode-vterm-input-mode-map nil)

(setq my/opencode-vterm-input-mode-map
      (let ((map (make-sparse-keymap))
            (alternate-leader-map (make-sparse-keymap)))
        (define-key map [down-mouse-1] #'my/opencode-vterm-mouse-down)
        (define-key map [mouse-1] #'my/opencode-vterm-mouse-up)
        (define-key map [wheel-up] #'my/opencode-vterm-wheel-up)
        (define-key map [wheel-down] #'my/opencode-vterm-wheel-down)
        (define-key map [mouse-4] #'my/opencode-vterm-wheel-up)
        (define-key map [mouse-5] #'my/opencode-vterm-wheel-down)
        (define-key map [escape] #'my/opencode-vterm-interrupt)
        (define-key map (kbd "M-o") #'my/opencode-vterm-toggle-output)
        (define-key map (kbd "C-y") #'my/opencode-vterm-line-up)
        (define-key map (kbd "C-e") #'my/opencode-vterm-line-down)
        (define-key map (kbd "C-b") #'my/opencode-vterm-page-up)
        (define-key map (kbd "C-f") #'my/opencode-vterm-page-down)
        (dolist (key my/opencode-leader-keys)
          (define-key alternate-leader-map (kbd key)
                      #'my/opencode-vterm-leader-key)
          (let ((sequence (kbd (concat "C-x " key))))
            (unless (key-binding sequence)
              (define-key map sequence #'my/opencode-vterm-leader-key))))
        (define-key map (kbd "C-c o") alternate-leader-map)
        map))

(define-minor-mode my/opencode-vterm-input-mode
  "Forward OpenCode mouse input from vterm."
  :keymap my/opencode-vterm-input-mode-map)

(defun my/opencode-configure-vterm-buffer ()
  "Give OpenCode unfiltered keyboard and mouse input in the current vterm."
  (display-line-numbers-mode -1)
  (when (fboundp 'evil-local-mode)
    (evil-local-mode -1))
  (my/opencode-vterm-input-mode 1))

(defun my/opencode ()
  "Open the official OpenCode TUI in a project-local vterm."
  (interactive)
  (require 'vterm)
  (let* ((project (project-current))
         (root (file-name-as-directory
                 (expand-file-name (if project (project-root project)
                                     default-directory))))
         (name (format "*opencode:%s*"
                       (file-name-nondirectory (directory-file-name root))))
         (existing (get-buffer name)))
    (if (buffer-live-p existing)
        (progn
          (pop-to-buffer existing)
          (with-current-buffer existing
            (my/opencode-configure-vterm-buffer)))
      (let ((default-directory root)
            (vterm-shell
             (mapconcat
              #'shell-quote-argument
              (list (expand-file-name "~/.opencode/bin/opencode")
                    "attach" "http://localhost:4096" "--dir" root)
              " ")))
        (let ((buffer (vterm name)))
          (with-current-buffer buffer
            (my/opencode-configure-vterm-buffer))
          buffer)))))

(global-set-key (kbd "C-c a o") #'my/opencode)

;; gptel is the lightweight ChatGPT interface for conversations, selected
;; context, and in-place rewrites. It intentionally has no agentic tools.
(use-package gptel
  :ensure t
  :commands (gptel gptel-send gptel-rewrite gptel-openai-oauth-login)
  :bind (("C-c a g" . gptel)
         ("C-c a s" . gptel-send)
         ("C-c a r" . gptel-rewrite))
  :config
  (setq gptel-model 'gpt-5.6-terra
        gptel-backend (gptel-make-openai-oauth "ChatGPT")))

(defun project-root-override (dir)
  (let ((root (locate-dominating-file dir ".project.el"))
        (backend (ignore-errors (vc-responsible-backend dir))))
    (when root (list 'vc backend root))))

(add-hook 'project-find-functions #'project-root-override)
;; Use the `eat' terminal backend instead of vterm to fix rendering
;; glitches (reflow/scroll/flicker). eat handles TUI redraws differently
;; and often renders these full-screen agents more cleanly than vterm.
;; The vterm-* tweaks below become no-ops under eat, but are kept so
;; switching back to 'vterm restores the previous tuning.
(setq claude-code-ide-terminal-backend 'eat)
(setq claude-code-ide-no-flicker t)  ; CLAUDE_CODE_NO_FLICKER=1, Claude's own flicker-free renderer

(setq claude-code-ide-prevent-reflow-glitch t)
(setq claude-code-ide-vterm-anti-flicker t)
(setq claude-code-ide-vterm-render-delay 0.01) ; increase from default 0.005s
(setq claude-code-ide-terminal-initialization-delay 0.15)  ; bump from 0.1
(setq claude-code-ide-cli-extra-flags "--plugin-dir ~/clip/Systems/ciao-skills")

; ispell
(with-eval-after-load 'ispell
  (setq ispell-program-name "hunspell")
  (setq ispell-dictionary "en_US,es_ES")
  (ispell-set-spellchecker-params)
  (ispell-hunspell-add-multi-dic "en_US,es_ES"))

; Javascript
(add-hook 'js-mode-hook
          (lambda ()
            (setq js-indent-level 2)))

(add-to-list 'auto-mode-alist '("\\.ts\\'" . typescript-ts-mode))
(add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode))

(add-hook 'typescript-ts-mode-hook #'eglot-ensure)
(add-hook 'tsx-ts-mode-hook #'eglot-ensure)

; Arabic
(set-fontset-font t 'arabic "Noto Naskh Arabic")
(setq bidi-paragraph-direction nil)
(add-hook 'org-mode-hook
  (lambda ()
    (set-face-attribute 'org-table nil :inherit 'fixed-pitch)))

; Agda
(when (executable-find "agda")
  (load-file (let ((coding-system-for-read 'utf-8))
               (string-trim (shell-command-to-string "agda --emacs-mode locate"))))
  (require 'agda-input)
  (add-hook 'LaTeX-mode-hook
            (lambda () (set-input-method "Agda"))))

; CIAO

(if (file-exists-p "/Users/meu/clip/Systems/ciao-devel/bndls/ciao_lptp/etc/ciao-lptp.el")
  (load-file "/Users/meu/clip/Systems/ciao-devel/bndls/ciao_lptp/etc/ciao-lptp.el"))

; @begin(53614285)@ - Do not edit these lines - added automatically!
(if (file-exists-p "/Users/meu/clip/Systems/ciao-devel/bndls/ciao_emacs/elisp/ciao-site-file.el")
  (load-file "/Users/meu/clip/Systems/ciao-devel/bndls/ciao_emacs/elisp/ciao-site-file.el"))
; @end(53614285)@ - End of automatically added lines.

;; -------------------------------------------------
 ;; ** Ciao company
 ;; -------------------------------------------------
 ;;; Paths to use ciao source instead of package in ./emacs.c/elpa: ***
 (add-to-list 'load-path "/Users/Meu/clip/Systems/ciao-devel/bndls/ciao_emacs/contrib")
 (add-to-list 'load-path "/Users/Meu/clip/Systems/ciao-devel/bndls/ciao_emacs/contrib/company-ciao")
 ;; For Company support, insert the next line into your Emacs init file.

 ;; ****** Set up company-ciao once ciao is actually loaded (ciao-mode is
 ;; autoloaded lazily, so `featurep' is nil at startup even when installed).
 (with-eval-after-load 'ciao
   (require 'company-ciao)
   (add-hook 'company-mode-hook 'company-ciao-setup))
 ;; If you use [use-package]
 ;; (https://github.com/jwiegley/use-package
 ;; ), you can insert instead
 ;; (use-package company-ciao
 ;;   :after company
 ;;   :hook
 ;;   (company-mode . company-ciao-setup)
 ;;   )
 ;; **Optional**: Enable `company-mode` in all buffers where possible.
 (use-package company :ensure t)
 (add-hook 'after-init-hook 'global-company-mode)
 ;;
 ;; This is super-useful in general: first tab indents, second auto-completes
 (setq tab-always-indent 'complete)
 ;;
 ;; -------------------------------------------------
 ;; ** Ciao flycheck ("verifly")
 ;; -------------------------------------------------
 ;; 
 ;; (MH: This below already done above in this file:)
 ;;      (require 'package)
 ;;      (add-to-list 'package-archives '("MELPA Stable" .
 ;; "https://stable.melpa.org/packages/"
 ;; ) t)
 ;;      (package-initialize)
 ;; 
 ;; There are two options for the setup:
 ;;    * Insert the next line into your `emacs' init file.
 ;;           (eval-after-load 'flycheck '(add-hook 'flycheck-mode-hook #'flycheck-ciao-setup))
 ;;    * If you use use-package
 ;; (https://github.com/jwiegley/use-package
 ;; ),
 ;;      you can insert instead.
 ;;           (use-package flycheck-ciao
 ;;             :after flycheck
 ;;             :hook
 ;;             (flycheck-mode . flycheck-ciao-setup)
 ;;             )
 ;; 
 ;; Install `ciao-emacs-plus` package via Emacs built-in package manager (`package.el`).
 ;; [ALT+X]package-install-file[RET](ciao-emacs-plus.el PATH)[RET]
 ;; ~/clip/Systems/ciao-devel/bndls/ciao_emacs/contrib/ciao-emacs-plus.el
 ;; 
 ;;; Paths to ciao source instead of package in ./emacs.c/elpa: ***
 (add-to-list 'load-path "/Users/Meu/clip/Systems/ciao-devel/bndls/ciao_emacs/contrib/flycheck-ciao")
 (use-package flycheck :ensure t)
 (with-eval-after-load 'ciao (load-library "flycheck-ciao"))
 ;; `flycheck-ciao-setup' lives in flycheck-ciao.el, which is loaded lazily
 ;; only once the `ciao' feature loads (the `load-library' above, on first
 ;; .pl file).  `global-flycheck-mode' can enable flycheck in a non-Ciao
 ;; buffer (*scratch*, etc.) at startup, before any .pl file has been opened;
 ;; the bare symbol would then be void and signal an error.  Guard the call so
 ;; it runs only once actually defined -- Ciao buffers load it on demand.
 (with-eval-after-load 'flycheck
   (add-hook 'flycheck-mode-hook
             (lambda ()
               (when (fboundp 'flycheck-ciao-setup) (flycheck-ciao-setup)))))
 (with-eval-after-load 'flycheck (add-hook 'flycheck-mode-hook 'my-change-flycheck-faces))
 ;; Optional: Enable `flycheck-mode` in all buffers where syntax checking is possible.
 (add-hook 'after-init-hook 'global-flycheck-mode)
 ;; CiaoPP analysis is heavy and the ciaopp server handles one request at a
 ;; time.  Checking on every keystroke makes concurrent checks race: one
 ;; check's temp-file cleanup deletes the file another is analyzing, the server
 ;; returns {"not_ready":"No such file or directory"}, and flycheck then shows 0
 ;; errors and drops the assertion notes.  Only check on save (and mode enable).
 (setq flycheck-check-syntax-automatically '(save mode-enabled))
 ;; Give in-flight checks room to finish before another can start.
 (setq flycheck-idle-change-delay 3)
 ;; Use the serverless CiaoPP checker.  The default `ciaopp' checker talks to a
 ;; persistent `ciao-serve' server, which proved unreliable two ways:
 ;;   * when the server DIED, `ciaopp-client' returned empty output (it only errs
 ;;     on curl exit 7 / connection-refused, not on timeouts) and flycheck
 ;;     silently showed "0 errors";
 ;;   * when the server was still BOOTING, the timeout-less curl blocked on the
 ;;     cold load and the check hung forever in "running".
 ;; `ciaopp-no-keep-alive' runs the `ciaopp' binary directly (~0.6s for a small
 ;; module) with no server to die, boot, or hang; flycheck manages the process
 ;; itself.  Force it as the checker in every Ciao buffer.
 (defun my-ciao-use-serverless-checker ()
   "Force the serverless `ciaopp-no-keep-alive' checker in Ciao buffers."
   (when (derived-mode-p 'ciao-mode)
     (setq-local flycheck-checker 'ciaopp-no-keep-alive)))
 (with-eval-after-load 'flycheck
   (add-hook 'flycheck-mode-hook 'my-ciao-use-serverless-checker))
 ;; Add to 'flycheck-ciao-setup?
 (defun my-change-flycheck-faces ()
  (defface flycheck-info
    ;; Use just margin mark (no underline) for info-level messages
    ;; (e.g., checked)
    '((t))
    "Flycheck face for informational messages."
    :group 'flycheck-faces))
 ;; Flycheck changes color in mode line 
 (use-package flycheck-color-mode-line :ensure t)
 (use-package flycheck-pos-tip :ensure t)
 (add-hook 'flycheck-mode-hook 'flycheck-color-mode-line-mode)
 ;; To re-flycheck after a file revert: 
 (eval-after-load 'flycheck
  '(add-to-list 'flycheck-hooks-alist '(after-revert-hook
                                        . flycheck-buffer)))
 ;; Trying something else:
 ;; (custom-set-faces!
 ;; (custom-set-faces
 ;;  '(flycheck-error :underline (:color "red2" :style wave))
 ;;  )

 ;;
 ;; Now done in flycheck-ciao ***
 ;; Disable flycheck for for _co files:
 ;; ------------------------------------
 ;; (add-hook 'flycheck-mode-hook 'my-skip-flycheck-for-ciaopp-output)
 ;; 
 ;; (defun my-skip-flycheck-for-ciaopp-output ()
 ;;   "Hook to turn off flycheck on _co.pl files (output from CiaoPP)."
 ;;   (let ((filename))
 ;;     (when (and (eq major-mode 'ciao-mode)
 ;;                (buffer-file-name)
 ;;                ; Check if flycheck is enabled, also avoids going
 ;;                ; recursively into hook. 
 ;;                (and (boundp 'flycheck-mode) flycheck-mode) 
 ;;                (string= (substring (buffer-file-name)
 ;;                                    (-  (length "_co.pl"))
 ;;                                    nil)
 ;;                         "_co.pl"))
 ;;       (flycheck-mode -1)
 ;;       (message "flycheck mode disabled for CiaoPP output buffer")
 ;;       )))

 ;; ** Pop-ups for Ciao flycheck ("verifly")
 ;; -------------------------------------------------
 ;; *** A) flycheck-pos-tip-mode (works best with syntax coloring)
 ;; ----------------------------------------------------------
 (with-eval-after-load 'flycheck
  (progn
    (flycheck-pos-tip-mode)
    (setq flycheck-pos-tip-timeout -1)
    ;; Fixes problem with tool tip width (was one character short)
    (defun pos-tip-tooltip-width (width char-width)
      "Calculate tooltip pixel width."
      (+ (* width char-width)
         (ash (+ pos-tip-border-width
             pos-tip-internal-border-width)
          2)))
    ;; Fix so that text properties are displayed
    (defun flycheck-pos-tip-error-messages (errors)
      "Display ERRORS, using a graphical tooltip on GUI frames."
      (when errors
        (if (display-graphic-p)
            (let ((message (flycheck-help-echo-all-error-messages errors))
                  (line-height (car (window-line-height))))
              (flycheck-pos-tip--check-pos)
              ;; MH: This is the relevant change:
              ;; pos-tip-show -> pos-tip-show-no-propertize
              (pos-tip-show-no-propertize message nil nil nil flycheck-pos-tip-timeout
                                          flycheck-pos-tip-max-width nil
                                          ;; Add a little offset to the tooltip to move it away
                                          ;; from the corresponding text in the buffer.  We
                                          ;; explicitly take the line height into account because
                                          ;; pos-tip computes the offset from the top of the line
                                          ;; apparently.
                                          nil (and line-height (+ line-height 5)))
              )
          (funcall flycheck-pos-tip-display-errors-tty-function errors))))))

 ;; *** B) flycheck-popup-tip
 ;; ;; ---------------------
 ;; (require 'flycheck-popup-tip)
 ;; (add-hook 'flycheck-mode-hook 'flycheck-popup-tip-mode)
 ;; ;; (defface popup-face
 ;; ;;   ;; '((t (:inherit default :background "lightgray" :foreground "black")))
 ;; ;;   '((t ()))
 ;; ;;   "Face for popup."
 ;; ;;   :group 'popup)
 ;; ;; (defface popup-tip-face
 ;; ;;   '((t (:background "khaki1" :foreground "black")))
 ;; ;;   "Face for popup tip."
 ;; ;;   :group 'popup)
 ;; (defface popup-tip-face
 ;;   ;; '((t (:background "lightgray")))
 ;;   '((t (:background "white")))
 ;;   "Face for popup tip."
 ;;   :group 'popup)
 ;; 
 ;; (defun flycheck-popup-tip-format-errors (errors)
 ;;   "Formats ERRORS messages for display."
 ;;   (let* ((messages-and-id (mapcar #'flycheck-error-format-message-and-id
 ;;                                   (delete-dups errors)))
 ;;          (messages (sort
 ;;                     (mapcar
 ;;                      (lambda (m) (concat flycheck-popup-tip-error-prefix m))
 ;;                      messages-and-id)
 ;;                     'string-lessp)))
 ;;     (propertize
 ;;      (mapconcat 'identity messages "\n")
 ;;      'face
 ;;      '(;; MH:
 ;;       :background "white"
 ;; ;;      :background "lightgray"
 ;; ;; :inherit popup-tip-face
 ;; ;;                 :underline nil
 ;; ;;                 :overline nil
 ;; ;;                 :strike-through nil
 ;; ;;                 :box nil
 ;; ;;                 :slant normal
 ;; ;;                 :width normal
 ;; ;;                 :weight normal
 ;;      ))
 ;;     )
 ;;   )

 ;; ** Defining a checker by hand (not necessary: new versions are connected to menu)
 ;; ------------------------------------------------------------------------------
 ;; (flycheck-define-checker ciaopp-full-noinc
 ;;   "A Ciao syntax and assertions checker using CiaoPP for ciao-mode"
 ;;   :command ("ciaopp"
 ;; ;;             "-op"
 ;; ;;             (eval flycheck-tmp-file-ciao-suffix)
 ;;             "-V"
 ;;             (eval (ciao-flycheck-create-tmp-file))
 ;; ;            "-fassert_ctcheck=auto"
 ;;             "-fassert_ctcheck=manual"
 ;;             "-fcheck_config_ana=on"
 ;;             "-fana_nf=nf"
 ;; ;            "-fmodes=shfr" ; Forced by nf and det?
 ;; ;            "-ftypes=eterms" ; Forced by nf and det?
 ;; ;            "-fana_cost=resources"
 ;; ;            "-fana_cost=steps_ualb"
 ;;             "-fana_det=det"
 ;; ;;             "-fentry_point=entry"
 ;; ;;             "-fpp_ctchecks=off"
 ;; ;;             "-fincremental=off"
 ;;             "-fmenu_output=off"
 ;; ;;             "-fpp_info=on"
 ;;             )
 ;;   :predicate (lambda ()
 ;;           (if (not (flycheck-ciao-enable-check))
 ;;           nil
 ;;         (when (not ciao-server-process)
 ;;                    (ciao-server-start))
 ;;         t))
 ;;   :error-parser flycheck-parse-ciao
 ;;   :error-filter
 ;;   (lambda (errors)
 ;;      (flycheck-ciao-skip-comments
 ;;       (flycheck-fill-empty-line-numbers
 ;;        (flycheck-sanitize-errors errors))))
 ;;   :modes ciao-mode
 ;;   )
 ;; 
 ;; (flycheck-define-checker ciaopp-default
 ;;   "A Ciao syntax and assertions checker using CiaoPP for ciao-mode"
 ;;   :command ("ciaopp"
 ;; ;;             "-op"
 ;; ;;             (eval flycheck-tmp-file-ciao-suffix)
 ;;             "-V"
 ;;             (eval (ciao-flycheck-create-tmp-file))
 ;; ;            "-fassert_ctcheck=auto"
 ;; ;            "-fassert_ctcheck=manual"
 ;; ;            "-fcheck_config_ana=on"
 ;; ;            "-fana_nf=nf"
 ;; ;            "-fmodes=shfr" ; Forced by nf and det?
 ;; ;            "-ftypes=eterms" ; Forced by nf and det?
 ;; ;            "-fana_cost=resources"
 ;; ;            "-fana_cost=steps_ualb"
 ;; ;            "-fana_det=det"
 ;; ;;             "-fentry_point=entry"
 ;; ;;             "-fpp_ctchecks=off"
 ;; ;;             "-fincremental=off"
 ;; ;            "-fmenu_output=off"
 ;; ;;             "-fpp_info=on"
 ;;             )
 ;;   :predicate (lambda ()
 ;;           (if (not (flycheck-ciao-enable-check))
 ;;           nil
 ;;         (when (not ciao-server-process)
 ;;                    (ciao-server-start))
 ;;         t))
 ;;   :error-parser flycheck-parse-ciao
 ;;   :error-filter
 ;;   (lambda (errors)
 ;;      (flycheck-ciao-skip-comments
 ;;       (flycheck-fill-empty-line-numbers
 ;;        (flycheck-sanitize-errors errors))))
 ;;   :modes ciao-mode
 ;;   )
 ;;
 ;; (flycheck-define-checker ciaopp-non-incremental
 ;;   "A Ciao syntax and assertions checker using CiaoPP for ciao-mode"
 ;;   :command ("ciaopp-client"
 ;;        "-op"
 ;;             (eval flycheck-tmp-file-ciao-suffix)
 ;;             "-V"
 ;;             (eval (ciao-flycheck-create-tmp-file))
 ;;              ;; (option-list "-f" flycheck-ciaopp-flags concat)
 ;;             "-fassert_ctcheck=manual"
 ;;             "-ftypes=none"
 ;;             "-fmodes=sharefree_clique"
 ;;             "-fpp_ctchecks=off"
 ;;             "-fintermod=on"
 ;;             ;; "-fct_modular=curr_mod"
 ;;             "-fct_modular=all"
 ;;             "-fentry_policy=top_level"
 ;;             "-ffixpoint=dd"
 ;;             "-fmain_module=/Users/isabel.garcia/git/ciao-devel/bndls/chat80/src/top/top.pl"
 ;;             "-fincremental=off"
 ;;             "-fdel_strategy=bottom_up"
 ;;             "-fmenu_output=off"
 ;;              )
 ;;   :predicate (lambda ()
 ;;           (if (not (flycheck-ciao-enable-check))
 ;;           nil
 ;;         (when (not ciao-server-process)
 ;;                    (ciao-server-start))
 ;;         t))
 ;;   :error-parser flycheck-parse-ciao
 ;;   :error-filter
 ;;   (lambda (errors)
 ;;      (flycheck-ciao-skip-comments
 ;;       (flycheck-fill-empty-line-numbers
 ;;        (flycheck-sanitize-errors errors))))
 ;;   :modes ciao-mode
 ;;   )
 ;;
 ;; (flycheck-define-checker ciaopp-incremental
 ;;   "A Ciao syntax and assertions checker using CiaoPP for ciao-mode"
 ;;   :command ("ciaopp-client"
 ;;        "-op"
 ;;             (eval flycheck-tmp-file-ciao-suffix)
 ;;             "-V"
 ;;             (eval (ciao-flycheck-create-tmp-file))
 ;;              ;; (option-list "-f" flycheck-ciaopp-flags concat)
 ;;             "-fassert_ctcheck=manual"
 ;;             "-ftypes=none"
 ;;             "-fmodes=sharefree_clique"
 ;;             "-fpp_ctchecks=off"
 ;;             "-fintermod=on"
 ;;             ;; "-fct_modular=curr_mod"
 ;;             "-fct_modular=all"
 ;;             "-fentry_policy=top_level"
 ;;             "-ffixpoint=dd"
 ;;             "-fmain_module=/Users/isabel.garcia/git/ciao-devel/bndls/chat80/src/top/top.pl"
 ;;             "-fincremental=on"
 ;;             "-fdel_strategy=bottom_up"
 ;;             "-fmenu_output=off"
 ;;              )
 ;;   :predicate (lambda ()
 ;;           (if (not (flycheck-ciao-enable-check))
 ;;           nil
 ;;         (when (not ciao-server-process)
 ;;                    (ciao-server-start))
 ;;         t))
 ;;   :error-parser flycheck-parse-ciao
 ;;   :error-filter
 ;;   (lambda (errors)
 ;;      (flycheck-ciao-skip-comments
 ;;       (flycheck-fill-empty-line-numbers
 ;;        (flycheck-sanitize-errors errors))))
 ;;   :modes ciao-mode
 ;;   )
 ;; -------------- END FLYCHECK AND COMPANY ---------------------


(global-display-line-numbers-mode)
