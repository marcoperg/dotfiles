;;; my-org-pdf.el --- Cached native Org PDFs without source-side debris -*- lexical-binding: t; -*-

;; Org remains the renderer.  This module owns only selection, destinations,
;; dependency records, a serial background worker, and study-PDF links.

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'ox-latex)
(require 'oc)
(require 'subr-x)

(defvar dired-mode-map)
(declare-function pdf-view-current-page "pdf-view" (&optional window))
(declare-function pdf-view-goto-page "pdf-view" (page &optional window))
(declare-function pdf-info-number-of-pages "pdf-info" (&optional file-or-buffer))

(defgroup my-org-pdf nil "Native Org preview and study PDFs." :group 'org-export)

(defcustom my/org-pdf-source-root (expand-file-name "~/knowledge/episteme/")
  "Source tree mirrored by the study commands."
  :type 'directory)

(defcustom my/org-pdf-mirror-directory nil
  "Study PDF root, or nil for .pdfs below `my/org-pdf-source-root'."
  :type '(choice (const :tag "Source root/.pdfs" nil) directory))

(defcustom my/org-pdf-cache-directory
  (expand-file-name "~/.cache/emacs/org-pdf/")
  "Private work, preview, dependency, and diagnostic files."
  :type 'directory)

(defconst my/org-pdf--module-file (file-truename (or load-file-name buffer-file-name)))
(defconst my/org-pdf--schema 1)
(defvar my/org-pdf--queue nil)
(defvar my/org-pdf--process nil)
(defvar my/org-pdf--last-result nil)
(defvar my/org-pdf--index nil)
(defvar my/org-pdf--source nil)
(defvar my/org-pdf--origin nil)
(defvar my/org-pdf--scope nil)
(defvar my/org-pdf--study-files nil)
(defvar my/org-pdf--mirror nil)
(defvar my/org-pdf--mode nil)
(defvar my/org-pdf--links nil)
(defvar my/org-pdf--hashes nil)
(defvar my/org-pdf--last-work nil)

(defun my/org-pdf--directory (path)
  (file-name-as-directory (file-truename (expand-file-name path))))

(defun my/org-pdf--inside-p (file directory)
  ;; `file-in-directory-p' returns nil for a not-yet-created output root.
  ;; Resolve symlinks first, then compare complete path components instead.
  (let ((file (file-truename file))
        (directory (my/org-pdf--directory directory)))
    (or (equal (directory-file-name file) (directory-file-name directory))
        (string-prefix-p directory file (file-name-case-insensitive-p directory)))))

(defun my/org-pdf--hash-file (file)
  "Hash FILE once per operation; absent inputs have a distinct fingerprint."
  (let* ((attributes (file-attributes file))
         (key (list file (and attributes (nth 5 attributes))
                    (and attributes (nth 6 attributes))
                    (and attributes (nth 7 attributes))))
         (cached (and my/org-pdf--hashes (gethash key my/org-pdf--hashes))))
    (or cached
        (let ((hash (if (file-regular-p file)
                        (with-temp-buffer
                          (set-buffer-multibyte nil)
                          (insert-file-contents-literally file)
                          (secure-hash 'sha256 (current-buffer)))
                      :missing)))
          (when my/org-pdf--hashes (puthash key hash my/org-pdf--hashes))
          hash))))

(defun my/org-pdf--hash (object)
  (secure-hash 'sha256 (prin1-to-string object)))

(defun my/org-pdf--read (file)
  "Read data, never evaluate it.  Invalid/discarded cache files are misses."
  (when (file-readable-p file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (let ((read-circle nil)) (read (current-buffer))))
      (error nil))))

(defun my/org-pdf--read-state (file)
  "A corrupt or obsolete dependency record is a cache miss, not a build error."
  (let ((value (my/org-pdf--read file)))
    (when (and (proper-list-p value)
               (proper-list-p (plist-get value :context))
               (eq (car (plist-get value :context)) my/org-pdf--schema)
               (proper-list-p (plist-get value :recorded))
               (cl-every #'stringp (plist-get value :recorded))
               (proper-list-p (plist-get value :inputs))
               (cl-every (lambda (input)
                           (and (consp input) (stringp (car input))
                                (or (stringp (cdr input)) (eq (cdr input) :missing))))
                         (plist-get value :inputs)))
      value)))

(defun my/org-pdf--write (file data)
  "Atomically write DATA beside FILE, including across interrupted builds."
  (make-directory (file-name-directory file) t)
  (let ((temporary (make-temp-file (concat file ".new-"))))
    (unwind-protect
        (progn
          (with-temp-file temporary
            (let ((print-length nil) (print-level nil))
              (prin1 data (current-buffer))
              (insert "\n")))
          (set-file-modes temporary #o600)
          (rename-file temporary file t))
      (when (file-exists-p temporary) (delete-file temporary)))))

(defun my/org-pdf--files (directory &optional mirror)
  "Find ordinary Org sources, without traversing symlinks or hidden caches."
  (let (files)
    (dolist (file (directory-files directory t directory-files-no-dot-files-regexp))
      (unless (or (file-symlink-p file)
                  (string-prefix-p "." (file-name-nondirectory file))
                  (equal (file-name-nondirectory file) "infra")
                  (and mirror (my/org-pdf--inside-p file mirror)))
        (cond
         ((file-directory-p file)
          (setq files (nconc files (my/org-pdf--files file mirror))))
         ((and (string-suffix-p ".org" file)
               (not (equal (downcase (file-name-nondirectory file)) "setup.org")))
          (push (file-truename file) files)))))
    (sort files #'string<)))

(defmacro my/org-pdf--with-source (file &rest body)
  "Read FILE in an isolated Org buffer, without interactive startup hooks."
  (declare (indent 1))
  `(with-temp-buffer
     (let ((org-inhibit-startup t) (org-mode-hook nil)
           (enable-local-variables nil) (enable-local-eval nil)
           (create-lockfiles nil))
       (insert-file-contents ,file)
       (setq buffer-file-name ,file default-directory (file-name-directory ,file))
       (delay-mode-hooks (org-mode))
       ,@body)))

(defun my/org-pdf--make-index (files)
  "Index real Org IDs, excluding examples.  Duplicate IDs remain errors."
  (let ((index (make-hash-table :test #'equal)))
    (dolist (file files)
      (my/org-pdf--with-source file
        (let* ((tree (org-element-parse-buffer))
               (title (or (cadr (assoc "TITLE" (org-collect-keywords '("TITLE"))))
                          (file-name-base file))))
          (org-element-map tree 'node-property
            (lambda (property)
              (when (equal (org-element-property :key property) "ID")
                (let* ((id (org-element-property :value property))
                       (entry (list :file file :title title
                                    :heading (and (org-element-lineage property '(headline)) t))))
                  (puthash id (if (gethash id index) 'duplicate entry) index))))))))
    index))

(defun my/org-pdf--local (name directory)
  "Resolve local NAME against DIRECTORY; do not cache remote dependencies."
  (setq name (org-strip-quotes name))
  (when (or (file-remote-p name) (org-url-p name))
    (error "Remote export dependency is not supported: %s" name))
  (file-truename (expand-file-name (org-link-unescape name) directory)))

(defun my/org-pdf--dependencies (source)
  "Collect input files and rendered Org contexts using native include semantics."
  (let ((seen (make-hash-table :test #'equal)) files org-inputs local-locations
        uses-bibliography)
    (cl-labels
        ((visit
           (file kind)
           (let ((previous (gethash file seen)))
             (unless previous (push file files))
             (unless (file-readable-p file) (error "Missing export input: %s" file))
             ;; A literal include may later also be used as actual Org content.
             (when (or (not previous)
                       (and (eq kind 'setup) (eq previous 'raw))
                       (and (eq kind 'org) (not (eq previous 'org))))
               (puthash file kind seen)
               (unless (eq kind 'raw)
                 (my/org-pdf--with-source file
                   (let ((tree (org-element-parse-buffer))
                         (directory (file-name-directory file)))
                     (when (eq kind 'org)
                       (push file org-inputs)
                       (org-element-map tree 'node-property
                         (lambda (property)
                           (when (equal (org-element-property :key property) "ID")
                             (push (cons (org-element-property :value property) file)
                                   local-locations))))
                       (when (org-element-map tree 'citation #'identity nil t)
                         (setq uses-bibliography t)))
                     (org-element-map tree 'keyword
                       (lambda (keyword)
                         (let ((key (org-element-property :key keyword))
                               (value (org-element-property :value keyword)))
                           (pcase key
                             ("SETUPFILE" (visit (my/org-pdf--local value directory) 'setup))
                             ("INCLUDE"
                              (when (eq kind 'org)
                                (let* ((parameters (org-export-parse-include-value value directory))
                                       (include (plist-get parameters :file)))
                                  (unless include (error "Invalid INCLUDE in %s: %s" file value))
                                  (visit (my/org-pdf--local include directory)
                                         (if (plist-get parameters :env) 'raw 'org)))))
                             ("PRINT_BIBLIOGRAPHY"
                              (when (eq kind 'org) (setq uses-bibliography t)))))))
                     ;; Follow Org Cite's syntax, including repeated declarations,
                     ;; quoted filenames, and declarations inherited from setup.
                     (let ((org-cite-global-bibliography nil))
                       (dolist (bib (org-cite-list-bibliography-files))
                         (visit (my/org-pdf--local bib directory) 'raw)))
                     (when (eq kind 'org)
                       (org-element-map tree 'link
                         (lambda (link)
                           (when (and (equal (org-element-property :type link) "file")
                                      (org-export-inline-image-p link org-latex-inline-image-rules))
                             (visit (my/org-pdf--local (org-element-property :path link) directory)
                                    'raw))))))))))))
      (visit source 'org)
      (when uses-bibliography
        (dolist (bib org-cite-global-bibliography)
          (visit (my/org-pdf--local bib (file-name-directory source)) 'raw))))
    (list :files (sort files #'string<) :org-inputs (delete-dups org-inputs)
          :local-locations (delete-dups local-locations))))

(defun my/org-pdf--destination (source root mirror)
  (setq source (file-truename source)
        root (my/org-pdf--directory root)
        mirror (my/org-pdf--directory mirror))
  (let ((target (expand-file-name
                 (concat (file-name-sans-extension (file-relative-name source root)) ".pdf")
                 mirror)))
    (unless (and (my/org-pdf--inside-p source root)
                 (my/org-pdf--inside-p target mirror))
      (error "PDF path escapes its configured tree: %s" source))
    target))

(defun my/org-pdf--link-target (link)
  "Describe an external Org LINK, or return nil for native internal links."
  (let* ((type (org-element-property :type link))
         (path (org-element-property :path link))
         (entry (and (equal type "id") (gethash path my/org-pdf--index)))
         (file (cond
                ((eq entry 'duplicate) (error "Duplicate Org ID: %s" path))
                (entry (plist-get entry :file))
                ((equal type "id") (error "Unknown Org ID: %s" path))
                ((and (equal type "file") (string-suffix-p ".org" path))
                 (my/org-pdf--local path (file-name-directory my/org-pdf--source))))))
    (when (and file (not (equal file my/org-pdf--source)))
      (unless (file-readable-p file) (error "Missing linked Org source: %s" file))
      (let ((pdf (and (eq my/org-pdf--mode 'study)
                      (not (plist-get entry :heading))
                      (not (org-element-property :search-option link))
                      (member file my/org-pdf--study-files))))
        (list :target (if pdf
                          (file-relative-name
                           (my/org-pdf--destination file my/org-pdf-source-root my/org-pdf--mirror)
                           (file-name-directory
                            (my/org-pdf--destination (or my/org-pdf--origin my/org-pdf--source)
                                                     my/org-pdf-source-root my/org-pdf--mirror)))
                        file)
              :pdf pdf :title (or (plist-get entry :title) (file-name-base file)))))))

(defun my/org-pdf--link-map (source org-inputs local-ids)
  "Record only link destinations that influence SOURCE's rendered document."
  (let ((my/org-pdf--source source) links)
    (dolist (file org-inputs)
      (my/org-pdf--with-source file
        (let ((my/org-pdf--source file))
          (org-element-map (org-element-parse-buffer) 'link
            (lambda (link)
              (let ((target
                     (unless (and (equal (org-element-property :type link) "id")
                                  (member (org-element-property :path link) local-ids))
                       ;; Preflight also sees noexport/commented material.
                       ;; Actual exported links are validated by the filter.
                       (condition-case error-data
                           (my/org-pdf--link-target link)
                         (error (list :unresolved (error-message-string error-data)))))))
                (when target
                  (push (list file (org-element-property :raw-link link) target) links))))))))
    (sort (delete-dups links) (lambda (a b) (string< (prin1-to-string a) (prin1-to-string b))))))

(defun my/org-pdf--filter-tree (tree backend info)
  "Use Org's custom-link extension only in this export's temporary parse tree."
  (when (org-export-derived-backend-p backend 'latex)
    (let ((local-ids
           (append
            (org-element-map tree 'headline
              (lambda (headline) (org-element-property :ID headline)))
            (org-element-map tree 'node-property
              (lambda (property)
                (when (equal (org-element-property :key property) "ID")
                  (org-element-property :value property)))))))
      (org-element-map tree 'link
        (lambda (link)
          (let ((target (unless (and (equal (org-element-property :type link) "id")
                                     (member (org-element-property :path link) local-ids))
                          (my/org-pdf--link-target link))))
            (when target
              (let ((key (number-to-string (length my/org-pdf--links))))
                (push (cons key target) my/org-pdf--links)
                (org-element-put-property link :type "org-pdf-job")
                (org-element-put-property link :path key)))))
        info)))
  tree)

(defun my/org-pdf--export-link (path description backend info)
  (when (org-export-derived-backend-p backend 'latex)
    (let* ((target (cdr (assoc path my/org-pdf--links)))
           (file (plist-get target :target))
           ;; File specifications in PDF GoToR actions need literal spaces,
           ;; not URL-encoded %20 directory names.
           (escaped (replace-regexp-in-string
                     "[%#{}&]" (lambda (s) (concat "\\" s)) file t t)))
      (format "\\href{file:%s}{%s%s}" escaped
              (or description (org-latex-plain-text (plist-get target :title) info))
              (if (plist-get target :pdf) "" " (Org)")))))

(defun my/org-pdf--absolute-bibliography (text backend _info)
  "Let Biber find source-relative resources when its control file is cached."
  (if (not (org-export-derived-backend-p backend 'latex)) text
    (replace-regexp-in-string
     "\\\\addbibresource\\(\\[[^]\n]*\\]\\)?{\\([^}\n]+\\)}"
     (lambda (match)
       (let ((options (match-string 1 match)) (file (match-string 2 match)))
         (if (org-url-p file) match
           (format "\\addbibresource%s{%s}" (or options "")
                   (expand-file-name file (file-name-directory my/org-pdf--source))))))
     text t t)))

(defun my/org-pdf--settings ()
  "Capture supported Org rendering options, not the user's entire init file."
  (let ((variables
         (delete-dups
          (append
           (delq nil (mapcar (lambda (option)
                               (let ((variable (nth 3 option)))
                                 (and variable (symbolp variable) variable)))
                             (org-export-get-all-options 'latex)))
           '(org-latex-classes org-latex-default-packages-alist org-latex-packages-alist
                               org-latex-hyperref-template org-latex-pdf-process org-latex-bib-compiler
                               org-cite-export-processors org-cite-global-bibliography org-cite-biblatex-options
                               org-export-global-macros org-export-default-language)))))
    (mapcar (lambda (variable) (cons variable (symbol-value variable)))
            (cl-remove-if-not #'boundp variables))))

(defun my/org-pdf--signatures (files)
  (mapcar (lambda (file) (cons file (my/org-pdf--hash-file file)))
          (sort (delete-dups (copy-sequence files)) #'string<)))

(defun my/org-pdf--recorded-inputs (tex)
  "Read TeX's recorder without treating generated work files as source inputs."
  (let ((recorder (concat (file-name-sans-extension tex) ".fls")) files)
    (when (file-readable-p recorder)
      (with-temp-buffer
        (insert-file-contents recorder)
        (goto-char (point-min))
        (while (re-search-forward "^INPUT \\(.*\\)$" nil t)
          (let ((file (file-truename (expand-file-name (match-string 1)))))
            (when (and (file-regular-p file)
                       (not (my/org-pdf--inside-p file my/org-pdf-cache-directory))
                       (not (my/org-pdf--inside-p file my/org-pdf--mirror)))
              (push file files))))))
    (delete-dups files)))

(defun my/org-pdf--compile (source tex)
  "Run native Org export and compilation, retaining SOURCE lookup context."
  (my/org-pdf--with-source source
    (let ((org-export-use-babel nil)
          (org-export-with-broken-links nil)
          (org-latex-remove-logfiles nil)
          (org-export-filter-parse-tree-functions '(my/org-pdf--filter-tree))
          (org-export-filter-final-output-functions '(my/org-pdf--absolute-bibliography))
          (org-link-parameters (copy-tree org-link-parameters))
          (my/org-pdf--links nil))
      (org-link-set-parameters "org-pdf-job" :export #'my/org-pdf--export-link)
      (org-export-to-file 'latex tex nil nil nil nil nil #'org-latex-compile))))

(defun my/org-pdf--validate-pdf (pdf)
  "Do not accept a merely existing PDF after a failed native compilation."
  (unless (and (file-readable-p pdf) (> (file-attribute-size (file-attributes pdf)) 5)
               (with-temp-buffer
                 (insert-file-contents-literally pdf nil 0 5)
                 (equal (buffer-string) "%PDF-")))
    (error "Compiler did not produce a PDF: %s" pdf))
  (let ((log (concat (file-name-sans-extension pdf) ".log")) warnings)
    (unless (file-readable-p log) (error "Missing compilation log: %s" log))
    (with-temp-buffer
      (insert-file-contents log)
      (goto-char (point-min))
      (when (re-search-forward
             "^!\\|^.*\\.\\(?:tex\\|sty\\|cls\\):[0-9]+:\\|LaTeX Error:\\|Package [^\n]+ Error:\\|There were undefined references\\|Citation .* undefined\\|Empty bibliography" nil t)
        (error "LaTeX errors or unresolved references; see %s" log))
      (goto-char (point-min))
      (while (re-search-forward "^.*\\(?:Warning:\\|Overfull\\|Underfull\\|Missing character\\).*" nil t)
        (push (match-string 0) warnings)))
    (let ((biber (concat (file-name-sans-extension pdf) ".blg")))
      (when (file-readable-p biber)
        (with-temp-buffer
          (insert-file-contents biber)
          (when (re-search-forward "\\bERROR\\b" nil t)
            (error "Bibliography compilation failed; see %s" biber)))))
    (nreverse warnings)))

(defun my/org-pdf--promote (pdf target)
  "Copy across filesystems, then atomically replace TARGET on its filesystem."
  (make-directory (file-name-directory target) t)
  (let ((temporary (make-temp-file (expand-file-name ".org-pdf-" (file-name-directory target))
                                   nil ".pdf")))
    (unwind-protect
        (progn (copy-file pdf temporary t) (rename-file temporary target t))
      (when (file-exists-p temporary) (delete-file temporary)))))

(defun my/org-pdf--build-one (source request base)
  "Build one SOURCE, or return a cache hit; never alter source files."
  (let* ((my/org-pdf--source source)
         (my/org-pdf--origin source)
         (default-directory (file-name-directory source))
         (key (my/org-pdf--hash (list source my/org-pdf--mode)))
         (state-file (expand-file-name (concat "state/" key ".eld") base))
         (old (my/org-pdf--read-state state-file))
         (dependency-data (my/org-pdf--dependencies source))
         (dependencies (plist-get dependency-data :files))
         (local-locations (plist-get dependency-data :local-locations))
         (links (my/org-pdf--link-map source (plist-get dependency-data :org-inputs)
                                      (mapcar #'car local-locations)))
         (context (list my/org-pdf--schema emacs-version (org-version)
                        (my/org-pdf--hash-file my/org-pdf--module-file)
                        (plist-get request :settings) links))
         (inputs (my/org-pdf--signatures
                  (append dependencies (plist-get old :recorded))))
         (target (if (eq my/org-pdf--mode 'study)
                     (my/org-pdf--destination source my/org-pdf-source-root my/org-pdf--mirror)
                   (expand-file-name (concat "preview/" key ".pdf") base))))
    (if (and (not (plist-get request :force))
             (equal context (plist-get old :context))
             (equal inputs (plist-get old :inputs))
             (file-readable-p target)
             (equal (my/org-pdf--hash-file target) (plist-get old :pdf-hash)))
        (list :source source :pdf target :status 'current)
      (let* ((work-root (expand-file-name (concat "work/" key "/") base))
             (_ (make-directory work-root t))
             (work (file-name-as-directory
                    (make-temp-file (expand-file-name "attempt-" work-root) t)))
             (tex (expand-file-name (concat (file-name-base source) ".tex") work))
             (pdf (concat (file-name-sans-extension tex) ".pdf"))
             (started (current-time))
             warnings recorded verified-inputs)
        (setq my/org-pdf--last-work work)
        ;; Fresh attempts cannot inherit stale Biber errors or misleading PDFs.
        (let ((org-id-locations (copy-hash-table org-id-locations)))
          (dolist (entry local-locations)
            (puthash (car entry) (cdr entry) org-id-locations))
          (my/org-pdf--compile source tex))
        (setq warnings (my/org-pdf--validate-pdf pdf)
              recorded (my/org-pdf--recorded-inputs tex))
        ;; Snapshot before final validation and publication, never afterwards.
        (setq verified-inputs
              (my/org-pdf--signatures (append dependencies recorded)))
        (unless (equal inputs
                       (let ((my/org-pdf--hashes nil))
                         (my/org-pdf--signatures (mapcar #'car inputs))))
          (error "Inputs changed during compilation; run export again: %s" source))
        ;; Newly discovered raw TeX inputs were not in the initial fingerprint.
        ;; If they changed during this first attempt, their output is uncertain.
        (dolist (file recorded)
          (unless (assoc file inputs)
            (let ((attributes (file-attributes file)))
              (when (or (time-less-p started (nth 5 attributes))
                        (time-less-p started (nth 6 attributes)))
                (error "A newly discovered input changed during compilation: %s" file)))))
        (my/org-pdf--promote pdf target)
        (my/org-pdf--write
         state-file (list :context context :inputs verified-inputs
                          :recorded recorded :work work
                          :pdf-hash (my/org-pdf--hash-file target)))
        (list :source source :pdf target :status 'built :warnings warnings)))))

(defun my/org-pdf--run (request)
  "Execute REQUEST synchronously in a worker (also useful for batch tests)."
  (let* ((my/org-pdf-source-root (my/org-pdf--directory (plist-get request :root)))
         (my/org-pdf-cache-directory (my/org-pdf--directory (plist-get request :cache)))
         (my/org-pdf--mirror (my/org-pdf--directory (plist-get request :mirror)))
         (my/org-pdf--scope (my/org-pdf--directory (plist-get request :scope)))
         (my/org-pdf--mode (plist-get request :mode))
         (my/org-pdf--study-files (mapcar #'file-truename (plist-get request :sources)))
         (my/org-pdf--hashes (make-hash-table :test #'equal))
         (settings (plist-get request :settings))
         (base (expand-file-name (concat (my/org-pdf--hash my/org-pdf-source-root) "/")
                                 my/org-pdf-cache-directory))
         results)
    (unless (and (memq my/org-pdf--mode '(preview study))
                 (my/org-pdf--inside-p my/org-pdf--scope my/org-pdf-source-root)
                 (not (my/org-pdf--inside-p my/org-pdf-cache-directory my/org-pdf-source-root))
                 (not (my/org-pdf--inside-p my/org-pdf-source-root my/org-pdf--mirror)))
      (error "Invalid source, mirror, cache, or scope configuration"))
    (dolist (source my/org-pdf--study-files)
      (unless (and (file-regular-p source)
                   (file-in-directory-p source my/org-pdf--scope)
                   (not (file-in-directory-p source my/org-pdf--mirror)))
        (error "Not an ordinary source inside the selected scope: %s" source)))
    (cl-progv (mapcar #'car settings) (mapcar #'cdr settings)
      (let* ((my/org-pdf--index (my/org-pdf--make-index
                                 (my/org-pdf--files my/org-pdf-source-root my/org-pdf--mirror)))
             (org-id-track-globally t)
             (org-id-locations-file nil)
             (org-id-files nil)
             (org-id-extra-files nil)
             (org-id-locations (make-hash-table :test #'equal)))
        (maphash (lambda (id entry)
                   (unless (eq entry 'duplicate)
                     (puthash id (plist-get entry :file) org-id-locations)))
                 my/org-pdf--index)
        (dolist (source my/org-pdf--study-files)
          (message "Org PDF: %s" (file-relative-name source my/org-pdf-source-root))
          (setq my/org-pdf--last-work nil)
          (push (condition-case error-data
                    (if (and (plist-get request :cancel-file)
                             (file-exists-p (plist-get request :cancel-file)))
                        (list :source source :status 'cancelled)
                      (my/org-pdf--build-one source request base))
                  (error (list :source source :status 'failed
                               :error (error-message-string error-data)
                               :work (or my/org-pdf--last-work
                                         (expand-file-name "work/" base)))))
                results))))
    (nreverse results)))

(defun my/org-pdf--acquire-lock (cache)
  "Use Emacs's atomic file locking and native stale-owner detection."
  (unless (file-directory-p cache)
    (make-directory cache t)
    (set-file-modes cache #o700))
  (let ((lock (expand-file-name "worker" cache))
        (create-lockfiles t))
    (when (file-locked-p lock)
      (error "Another Org PDF worker owns %s; wait for it to finish" lock))
    (cl-letf (((symbol-function 'ask-user-about-lock)
               (lambda (&rest _) (error "Another Org PDF worker owns %s" lock))))
      (lock-file lock))
    (unless (eq (file-locked-p lock) t) (error "Could not acquire Org PDF worker lock"))
    lock))

(defun my/org-pdf--worker (request-file result-file)
  "Clean batch entry point: no personal init, persistent ID cache, or daemon."
  (let* ((request (my/org-pdf--read request-file))
         (cache (plist-get request :cache))
         lock result)
    (unwind-protect
        (condition-case error-data
            (progn
              (setq lock (my/org-pdf--acquire-lock cache))
              (setq result (list :results (my/org-pdf--run request))))
          (error (setq result (list :error (error-message-string error-data)))))
      (when lock
        (unlock-file lock)))
    (my/org-pdf--write result-file result)))

(defun my/org-pdf--request (mode sources scope force)
  (let* ((root (my/org-pdf--directory my/org-pdf-source-root))
         (mirror (my/org-pdf--directory
                  (or my/org-pdf-mirror-directory (expand-file-name ".pdfs/" root))))
         (cache (my/org-pdf--directory my/org-pdf-cache-directory)))
    (unless (and (my/org-pdf--inside-p scope root)
                 (not (my/org-pdf--inside-p cache root))
                 (not (my/org-pdf--inside-p root mirror)))
      (user-error "Select sources below %s; work/cache must be outside it" root))
    (list :root root :mirror mirror :cache cache :scope (my/org-pdf--directory scope)
          :sources (mapcar #'file-truename sources) :mode mode :force (and force t)
          :settings (my/org-pdf--settings))))

(defun my/org-pdf--save-sources (sources)
  "Do not kill existing buffers, save unrelated work, or build unsaved changes."
  (setq sources (mapcar #'file-truename sources))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and buffer-file-name (buffer-modified-p)
                 (member (file-truename buffer-file-name) sources))
        (unless (y-or-n-p (format "Save %s before PDF export? " (buffer-name)))
          (user-error "Save relevant changes before exporting PDFs"))
        (save-buffer)))))

(defun my/org-pdf--prepare-sources (sources)
  "Save requested sources and known modified dependencies, never unrelated work."
  (my/org-pdf--save-sources sources)
  (let (dependencies)
    (dolist (source sources)
      ;; Missing/unsupported inputs are reported per note by the worker, not
      ;; used to prevent exporting the other valid notes in this directory.
      (setq dependencies
            (append (plist-get (ignore-errors (my/org-pdf--dependencies source)) :files)
                    dependencies)))
    (my/org-pdf--save-sources (delete-dups dependencies))))

(defun my/org-pdf--show-preview (file)
  "Reuse a PDF buffer/window without rearranging the user's workspace."
  (let* ((buffer (find-file-noselect file))
         (window (get-buffer-window buffer t))
         (page (and (fboundp 'pdf-view-current-page)
                    (with-current-buffer buffer
                      (and (derived-mode-p 'pdf-view-mode) (pdf-view-current-page))))))
    (with-current-buffer buffer
      (when (and (not (buffer-modified-p))
                 (not (verify-visited-file-modtime buffer)))
        (revert-buffer t t))
      (when (and page (fboundp 'pdf-view-goto-page))
        (pdf-view-goto-page (min page (pdf-info-number-of-pages)))))
    (unless window (display-buffer buffer '(display-buffer-pop-up-window)))))

(defun my/org-pdf--summary (result)
  (if-let ((error-message (plist-get result :error)))
      (concat "Org PDF: " error-message)
    (let* ((records (plist-get result :results))
           (count (lambda (status)
                    (cl-count status records :key (lambda (entry) (plist-get entry :status))))))
      (format "Org PDF: %d selected; %d current; %d rebuilt; %d failed%s (M-x my/org-pdf-show-log)"
              (length records) (funcall count 'current) (funcall count 'built)
              (funcall count 'failed)
              (if (> (funcall count 'cancelled) 0)
                  (format "; %d cancelled" (funcall count 'cancelled)) "")))))

(defun my/org-pdf--sentinel (process _event)
  (when (memq (process-status process) '(exit signal))
    (let* ((request (process-get process 'request))
           (result (or (my/org-pdf--read (process-get process 'result-file))
                       (list :error (format "Worker %s; see *Org PDF*" (process-exit-status process))))))
      (setq my/org-pdf--last-result result my/org-pdf--process nil)
      (with-current-buffer (get-buffer-create "*Org PDF*")
        (goto-char (point-max))
        (insert "\n" (my/org-pdf--summary result) "\n")
        (dolist (record (plist-get result :results))
          (insert (format "%s  %s\n" (plist-get record :status) (plist-get record :source)))
          (when (plist-get record :error)
            (insert (format "  %s\n  Work/logs: %s\n"
                            (plist-get record :error) (plist-get record :work))))
          (dolist (warning (plist-get record :warnings)) (insert "  " warning "\n"))))
      (message "%s" (my/org-pdf--summary result))
      (when (eq (plist-get request :mode) 'preview)
        (let ((record (car (plist-get result :results))))
          (when (plist-get record :pdf)
            (condition-case error-data
                (my/org-pdf--show-preview (plist-get record :pdf))
              (error (message "PDF exported; viewer error: %s" (error-message-string error-data)))))))
      (my/org-pdf--start-next))))

(defun my/org-pdf--start-next ()
  (when (and (not (process-live-p my/org-pdf--process)) my/org-pdf--queue)
    (let* ((request (pop my/org-pdf--queue))
           (cache (plist-get request :cache)))
      (unless (file-directory-p cache)
        (make-directory cache t)
        (set-file-modes cache #o700))
      (let* ((job (make-temp-file (expand-file-name "job-" cache) t))
             (input (expand-file-name "request.eld" job))
             (output (expand-file-name "result.eld" job))
             (default-directory (plist-get request :root))
             (process-environment (copy-sequence process-environment)))
        (setq request (plist-put request :cancel-file (expand-file-name "cancel" job)))
        (my/org-pdf--write input request)
        (setenv "PATH" (mapconcat #'identity exec-path path-separator))
        (setq my/org-pdf--process
              (make-process
               :name "org-pdf" :buffer (get-buffer-create "*Org PDF*")
               :noquery t :connection-type 'pipe
               :command (list (expand-file-name invocation-name invocation-directory)
                              "--batch" "-Q" "-l" my/org-pdf--module-file
                              "--eval" (prin1-to-string
                                        (list 'my/org-pdf--worker input output)))))
        (process-put my/org-pdf--process 'request request)
        (process-put my/org-pdf--process 'result-file output)
        (set-process-sentinel my/org-pdf--process #'my/org-pdf--sentinel)))))

(defun my/org-pdf--enqueue (request)
  (setq my/org-pdf--queue (nconc my/org-pdf--queue (list request)))
  (my/org-pdf--start-next)
  (message "Org PDF: queued %d note(s); Emacs remains available"
           (length (plist-get request :sources))))

;;;###autoload
(defun my/org-pdf-preview (&optional force)
  "Preview this saved note with native Org/PDF Tools; prefix FORCE rebuilds."
  (interactive "P")
  (unless (and (derived-mode-p 'org-mode) buffer-file-name)
    (user-error "Visit an Org source file first"))
  (let ((source (file-truename buffer-file-name)))
    (my/org-pdf--prepare-sources (list source))
    (my/org-pdf--enqueue
     (my/org-pdf--request 'preview (list source) (file-name-directory source) force))))

;;;###autoload
(defun my/org-pdf-update-directory (directory &optional force)
  "Update missing/stale study PDFs below DIRECTORY; prefix FORCE rebuilds all.
The directory only selects sources; mirror addresses remain repository-relative.
This command does not open the library or recursively export linked neighbours."
  (interactive (list (read-directory-name "Study source directory: " default-directory)
                     current-prefix-arg))
  (let* ((scope (my/org-pdf--directory directory))
         (root (my/org-pdf--directory my/org-pdf-source-root))
         (mirror (my/org-pdf--directory
                  (or my/org-pdf-mirror-directory (expand-file-name ".pdfs/" root)))))
    (unless (and (my/org-pdf--inside-p scope root)
                 (not (my/org-pdf--inside-p scope mirror)))
      (user-error "Select an ordinary source directory below %s" root))
    (let ((sources (my/org-pdf--files scope mirror)))
      (unless sources (user-error "No Org notes in %s" scope))
      (my/org-pdf--prepare-sources sources)
      (my/org-pdf--enqueue (my/org-pdf--request 'study sources scope force)))))

(defun my/org-pdf-show-log ()
  "Show build progress, failures, retained logs, and the last batch summary."
  (interactive)
  (pop-to-buffer (get-buffer-create "*Org PDF*")))

(defun my/org-pdf-cancel ()
  "Cancel queued exports after the active note finishes.
Letting its compiler exit normally avoids orphaned Biber/LaTeX processes."
  (interactive)
  (setq my/org-pdf--queue nil)
  (when (process-live-p my/org-pdf--process)
    (let ((request (process-get my/org-pdf--process 'request)))
      (my/org-pdf--write (plist-get request :cancel-file) t))
    (message "Org PDF: cancellation requested; the active note will finish first")))

(defun my/org-pdf-setup ()
  "Install note commands without replacing Org's Babel/export bindings."
  (define-key org-mode-map (kbd "C-c n p") #'my/org-pdf-preview)
  (define-key org-mode-map (kbd "C-c n P") #'my/org-pdf-update-directory)
  ;; Also make the directory command available while browsing source folders.
  (with-eval-after-load 'dired
    (define-key dired-mode-map (kbd "C-c n P") #'my/org-pdf-update-directory))
  ;; Handle reevaluation in a session that still has the retired binding.
  (when (eq (lookup-key org-mode-map (kbd "C-c C-v"))
            'my/org-export-to-pdf-in-dotpdfs)
    (define-key org-mode-map (kbd "C-c C-v") org-babel-map))
  (setq org-preview-latex-image-directory
        (expand-file-name "latex-preview/" my/org-pdf-cache-directory)))

(provide 'my-org-pdf)
;;; my-org-pdf.el ends here
