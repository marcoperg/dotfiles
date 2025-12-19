(load-theme 'modus-vivendi)
(global-visual-line-mode t)

; Prefer vert split
(setq split-height-threshold nil)  ; disable horizontal splitting
(setq split-width-threshold 0)     ; always prefer vertical splits

(setenv "PATH" (concat (getenv "PATH") ":/opt/homebrew/bin"))
(add-to-list 'exec-path "/opt/homebrew/bin")

(global-display-line-numbers-mode)
(setq-default display-line-numbers-type 'relative)

(setq backup-directory-alist '(("." . "~/.emacs.d/backups")))


; Open files
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

(global-set-key (kbd "C-c o") #'my/open-marked-file)


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

(defun my-TeX-master-from-documentclass ()
  "Return master file by searching upwards for a \\documentclass line."
  (let ((dir (locate-dominating-file
              (or buffer-file-name default-directory)
              (lambda (d)
                (directory-files d nil "\\.tex\\'" t)))))
    (when dir
      (catch 'found
        (dolist (f (directory-files dir t "\\.tex\\'" t))
          (with-temp-buffer
            (insert-file-contents f nil 0 1000) ; only first KB
            (goto-char (point-min))
            (when (re-search-forward "\\\\documentclass" nil t)
              (throw 'found f))))))))

(setq-default TeX-master #'my-TeX-master-from-documentclass)


(setq TeX-command-default "LatexMk")
(add-hook 'LaTeX-mode-hook
          (lambda ()
            (push
             '("LatexMk" "latexmk -pdf -synctex=1 %s" TeX-run-TeX nil t
               :help "Run LatexMk")
             TeX-command-list)))


(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(initial-buffer-choice t)
 '(package-selected-packages
   '(auctex evil evil-collection eww-lnum haskell-mode languagetool magit
	    markdown-mode org-roam org-side-tree pdf-tools undo-fu
	    visual-fill-column lsp-mode dash)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

; (setq initial-buffer-choice (lambda () (dired "~/docs/")))
(when (string= system-type "darwin")
  (setq dired-use-ls-dired nil))

;; PDF
(pdf-tools-install)
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

(defun pdf-presentation-mode ()
  "Open PDF in presentation mode: fullscreen, no mode-line or minibuffer."
  (interactive)
  (delete-other-windows)
  (when (fboundp 'toggle-frame-fullscreen)
    (toggle-frame-fullscreen))
  (pdf-view-fit-page-to-window)
  (setq mode-line-format nil)
  (redraw-display))

(defun pdf-presentation-in-new-frame (file)
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
    (setq evil-undo-system 'undo-fu)
    ;; https://github.com/emacs-evil/evil-collection/issues/60
    (setq evil-want-keybinding nil)

    ;; Set up package.el to work with MELPA
    (require 'package)
    (add-to-list 'package-archives
		'("melpa" . "https://melpa.org/packages/"))
    (package-initialize)
    ; (package-refresh-contents)

    ;; Download Evil
    (unless (package-installed-p 'evil)
    (package-install 'evil))

    ;; Enable Evil
    (require 'evil)
    (evil-mode 1)

    (evil-collection-init)

    ;; DocView
    (evil-collection-define-key 'normal 'doc-view-mode-map
      "j" 'doc-view-next-page
      "k" 'doc-view-previous-page
    )
)

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

; Org mode
(setq visual-fill-column-width 100) ; Change to desired max width
(setq visual-fill-column-center-text t)
(defun my/org-maybe-disable-line-numbers ()
  "Disable line numbers if the current file is in an 'ontology' folder."
  (when (and buffer-file-name
             (string-match-p "/ontology/" (file-truename buffer-file-name)))
    (display-line-numbers-mode 0)
    (visual-line-mode 1)
    (visual-fill-column-mode 1)))

(add-hook 'org-mode-hook #'my/org-maybe-disable-line-numbers)



(setq org-roam-directory (file-truename "~/fun/ontology"))

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
                  ("C-c n l" . org-roam-buffer-toggle)))))

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

(define-key org-mode-map (kbd "C-c C-v") #'my/org-export-to-pdf-in-dotpdfs)

(plist-put org-format-latex-options :scale 4)
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
  (let* ((template-file "~/docs/planning/weekly-template.org")
         (week-file (format "~/docs/planning//weeks/week-%s-%s.org"
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
  (let ((week-file (format "~/docs/planning/weeks/week-%s-%s.org"
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



; LPTP
(autoload 'lptp-mode "/Users/meu/fun/lptp/etc/lptp-mode" 
    "Major mode for editing formal proofs" t)
(setq auto-mode-alist 
    (cons '("\\.pr$" . lptp-mode) auto-mode-alist))
(transient-mark-mode 1)
(add-hook 'lptp-mode #'display-line-numbers-mode)



; Language Tool
(setq languagetool-java-arguments '("-Dfile.encoding=UTF-8")
        languagetool-console-command "/opt/homebrew/Cellar/languagetool/6.6/libexec/languagetool-commandline.jar"

        languagetool-server-command "/opt/homebrew/Cellar/languagetool/6.6/libexec/languagetool-server.jar")


; LANGUAGES

; Javascript
(add-hook 'js-mode-hook
          (lambda ()
            (setq js-indent-level 2)))

; Arabic
(set-fontset-font t 'arabic "Noto Naskh Arabic")
(setq bidi-paragraph-direction nil)
(add-hook 'org-mode-hook
  (lambda ()
    (set-face-attribute 'org-table nil :inherit 'fixed-pitch)))

; Lean
(add-to-list 'load-path "~/.emacs.d/lean4-mode")
(require 'lean4-mode)
(add-hook 'lean-mode-hook 'lean-toggle-show-goal)


; CIAO

(if (file-exists-p "/Users/meu/clip/Systems/ciao-devel/bndls/ciao_lptp/etc/ciao-lptp.el")
  (load-file "/Users/meu/clip/Systems/ciao-devel/bndls/ciao_lptp/etc/ciao-lptp.el"))

; @begin(53614285)@ - Do not edit these lines - added automatically!
(if (file-exists-p "/Users/meu/clip/Systems/ciao-devel/bndls/ciao_emacs/elisp/ciao-site-file.el")
  (load-file "/Users/meu/clip/Systems/ciao-devel/bndls/ciao_emacs/elisp/ciao-site-file.el"))
; @end(53614285)@ - End of automatically added lines.

(global-display-line-numbers-mode)
