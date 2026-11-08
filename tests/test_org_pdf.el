;;; test_org_pdf.el --- Native PDF mirror regression checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(load (expand-file-name "../dotfiles/emacs/my-org-pdf.el"
                        (file-name-directory load-file-name)) nil t)

(defvar org-pdf-test--compiles 0)
(defvar org-pdf-test--record nil)

(defun org-pdf-test--write (path text)
  (make-directory (file-name-directory path) t)
  (with-temp-file path (insert text))
  path)

(defmacro org-pdf-test--fixture (&rest body)
  (declare (indent 0))
  `(let* ((workspace (file-truename (make-temp-file "org-pdf-test-" t)))
          (root (file-name-as-directory (expand-file-name "notes" workspace)))
          (cache (file-name-as-directory (expand-file-name "cache" workspace)))
          (scope (file-name-as-directory (expand-file-name "course" root)))
          (mirror (expand-file-name ".pdfs/" root))
          (my/org-pdf-source-root root)
          (my/org-pdf-cache-directory cache)
          (my/org-pdf-mirror-directory nil)
          (org-cite-global-bibliography nil)
          (org-pdf-test--compiles 0)
          (org-pdf-test--record nil)
          (setup (expand-file-name "setup.org" root))
          (a (expand-file-name "A note.org" scope))
          (b (expand-file-name "sub/B note.org" scope))
          (c (expand-file-name "other/C note.org" root)))
     (unwind-protect
         (progn
           (org-pdf-test--write setup "#+options: toc:nil author:nil date:nil num:nil\n")
           (org-pdf-test--write a
                                ":PROPERTIES:\n:ID: a\n:END:\n#+title: Note A\n#+SETUPFILE: ../setup.org\n\n[[id:b][B]] and [[id:c][C]].\n\n* Local\n:PROPERTIES:\n:ID: local\n:END:\n[[id:local][Local heading]].\n")
           (org-pdf-test--write b
                                ":PROPERTIES:\n:ID: b\n:END:\n#+title: Note B\n#+SETUPFILE: ../../setup.org\n\nB body.\n")
           (org-pdf-test--write c
                                ":PROPERTIES:\n:ID: c\n:END:\n#+title: Note C\n\nC body.\n")
           (cl-letf (((symbol-function 'org-latex-compile)
                      (lambda (tex &rest _)
                        (cl-incf org-pdf-test--compiles)
                        (should (file-in-directory-p tex cache))
                        (should (file-in-directory-p default-directory root))
                        (let ((pdf (concat (file-name-sans-extension tex) ".pdf")))
                          (org-pdf-test--write pdf (format "%%PDF-1.7\nMock %d\n" org-pdf-test--compiles))
                          (org-pdf-test--write (concat (file-name-sans-extension tex) ".log") "Clean build.\n")
                          (org-pdf-test--write (concat (file-name-sans-extension tex) ".fls")
                                               (if org-pdf-test--record (concat "INPUT " org-pdf-test--record "\n") ""))
                          pdf))))
             ,@body))
       ;; Only sandbox files created by this test are removed.
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer)
                    (file-in-directory-p (buffer-file-name buffer) workspace))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory workspace t))))

(defun org-pdf-test--request (scope sources &optional mode force)
  (my/org-pdf--request (or mode 'study) sources scope force))

(defun org-pdf-test--statuses (results)
  (mapcar (lambda (entry) (plist-get entry :status)) results))

(defun org-pdf-test--latest-tex (cache basename)
  (car (sort (directory-files-recursively cache (concat (regexp-quote basename) "\\.tex\\'"))
             (lambda (a b) (file-newer-than-file-p a b)))))

(ert-deftest org-pdf-scans-only-notes-and-does-not-follow-links ()
  (org-pdf-test--fixture
    (org-pdf-test--write (expand-file-name "setup.org" scope) "#+latex_header: test\n")
    (org-pdf-test--write (expand-file-name "infra/fixture.org" scope) "Excluded\n")
    (org-pdf-test--write (expand-file-name ".hidden/file.org" scope) "Excluded\n")
    (make-symbolic-link (file-name-directory c) (expand-file-name "linked" scope))
    (should (equal (my/org-pdf--files scope mirror) (list a b)))))

(ert-deftest org-pdf-second-build-is-a-cache-hit ()
  (org-pdf-test--fixture
    (let ((request (org-pdf-test--request scope (list a b))))
      (should (equal (org-pdf-test--statuses (my/org-pdf--run request)) '(built built)))
      (should (equal (org-pdf-test--statuses (my/org-pdf--run request)) '(current current)))
      (should (= org-pdf-test--compiles 2)))))

(ert-deftest org-pdf-single-source-change-does-not-rebuild-neighbours ()
  (org-pdf-test--fixture
    (let ((request (org-pdf-test--request scope (list a b))))
      (my/org-pdf--run request)
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert "New prose.\n") (write-region nil nil b nil 'silent))
      (should (equal (org-pdf-test--statuses (my/org-pdf--run request)) '(current built))))))

(ert-deftest org-pdf-shared-setup-invalidates-selected-dependants ()
  (org-pdf-test--fixture
    (let ((request (org-pdf-test--request scope (list a b))))
      (my/org-pdf--run request)
      (org-pdf-test--write setup "#+options: toc:nil\n#+latex_header: changed\n")
      (should (equal (org-pdf-test--statuses (my/org-pdf--run request)) '(built built)))
      (should-not (file-exists-p (expand-file-name "other/C note.pdf" mirror))))))

(ert-deftest org-pdf-missing-output-and-force-trigger-builds ()
  (org-pdf-test--fixture
    (let* ((request (org-pdf-test--request scope (list b)))
           (result (car (my/org-pdf--run request))))
      (delete-file (plist-get result :pdf))
      (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))
      (setq request (plist-put request :force t))
      (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))
      (should (= org-pdf-test--compiles 3)))))

(ert-deftest org-pdf-source-tree-is-untouched ()
  (org-pdf-test--fixture
    (let ((before (directory-files-recursively scope ".*")))
      (my/org-pdf--run (org-pdf-test--request scope (list a b)))
      (should (equal before (directory-files-recursively scope ".*")))
      (should (equal (sort (directory-files-recursively mirror ".*") #'string<)
                     (list (expand-file-name "course/A note.pdf" mirror)
                           (expand-file-name "course/sub/B note.pdf" mirror)))))))

(ert-deftest org-pdf-study-links-use-final-relative-paths-with-literal-spaces ()
  (org-pdf-test--fixture
    (my/org-pdf--run (org-pdf-test--request scope (list a b)))
    (let ((tex (org-pdf-test--latest-tex cache "A note")))
      (with-temp-buffer
        (insert-file-contents tex)
        (should (search-forward "\\href{file:sub/B note.pdf}{B}" nil t))
        (goto-char (point-min))
        (should (search-forward (concat "\\href{file:" c "}{C (Org)}") nil t))
        (goto-char (point-min))
        (should (re-search-forward "\\\\hyperref\\[[^]]+\\]{Local heading}" nil t))
        (should-not (string-match-p "%20" (buffer-string)))))))

(ert-deftest org-pdf-preview-does-not-overwrite-study-pdf ()
  (org-pdf-test--fixture
    (let* ((study (car (my/org-pdf--run (org-pdf-test--request scope (list a b)))))
           (study-hash (my/org-pdf--hash-file (plist-get study :pdf)))
           (preview (car (my/org-pdf--run (org-pdf-test--request scope (list a) 'preview)))))
      (should (file-in-directory-p (plist-get preview :pdf) cache))
      (should (equal study-hash (my/org-pdf--hash-file (plist-get study :pdf)))))))

(ert-deftest org-pdf-scope-changes-do-not-change-destination-addresses ()
  (org-pdf-test--fixture
    (let ((first (car (my/org-pdf--run (org-pdf-test--request scope (list b)))))
          (second (car (my/org-pdf--run
                        (org-pdf-test--request (file-name-directory b) (list b))))))
      (should (equal (plist-get first :pdf) (plist-get second :pdf)))
      (should (eq (plist-get second :status) 'current)))))

(ert-deftest org-pdf-failed-compilation-preserves-previous-output-and-cache ()
  (org-pdf-test--fixture
    (let* ((request (org-pdf-test--request scope (list b)))
           (original (car (my/org-pdf--run request)))
           (pdf (plist-get original :pdf))
           (hash (my/org-pdf--hash-file pdf)))
      (setq request (plist-put request :force t))
      (cl-letf (((symbol-function 'org-latex-compile) (lambda (&rest _) (error "Broken TeX"))))
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'failed)))
      (should (equal hash (my/org-pdf--hash-file pdf)))
      (setq request (plist-put request :force nil))
      (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'current)))))

(ert-deftest org-pdf-catches-native-produced-pdf-with-errors ()
  (org-pdf-test--fixture
    (let ((compile (symbol-function 'org-latex-compile)))
      (cl-letf (((symbol-function 'org-latex-compile)
                 (lambda (tex &rest _)
                   (let ((pdf (funcall compile tex)))
                     (org-pdf-test--write (concat (file-name-sans-extension tex) ".log")
                                          "! Undefined control sequence.\n")
                     pdf))))
        (should (eq (plist-get (car (my/org-pdf--run
                                     (org-pdf-test--request scope (list b)))) :status) 'failed))
        (should-not (file-exists-p (expand-file-name "course/sub/B note.pdf" mirror)))))))

(ert-deftest org-pdf-source-change-during-compile-is-not-published ()
  (org-pdf-test--fixture
    (let ((compile (symbol-function 'org-latex-compile)))
      (cl-letf (((symbol-function 'org-latex-compile)
                 (lambda (tex &rest _)
                   (prog1 (funcall compile tex)
                     (org-pdf-test--write b "#+title: changed during build\n")))))
        (should (eq (plist-get (car (my/org-pdf--run
                                     (org-pdf-test--request scope (list b)))) :status) 'failed))))))

(ert-deftest org-pdf-transitive-includes-and-recorder-inputs-invalidate ()
  (org-pdf-test--fixture
    (let ((fragment (expand-file-name "fragment.txt" scope))
          (raw (expand-file-name "raw.tex" scope)))
      (org-pdf-test--write fragment "Included prose\n")
      (org-pdf-test--write raw "Raw input\n")
      (setq org-pdf-test--record raw)
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert "\n#+INCLUDE: \"../fragment.txt\"\n")
                        (write-region nil nil b nil 'silent))
      (let ((request (org-pdf-test--request scope (list b))))
        (my/org-pdf--run request)
        (org-pdf-test--write fragment "Changed included prose\n")
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))
        (org-pdf-test--write raw "Changed raw input\n")
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))))))

(ert-deftest org-pdf-bibliography-is-absolute-and-tracked ()
  (org-pdf-test--fixture
    (let ((bib (expand-file-name "library/references.bib" workspace)))
      (org-pdf-test--write bib "@book{example,title={Example},author={Someone},year={2026}}\n")
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert "\n#+cite_export: biblatex numeric\n#+bibliography: ../../../library/references.bib\n[cite:@example]\n#+print_bibliography:\n")
                        (write-region nil nil b nil 'silent))
      (let ((request (org-pdf-test--request scope (list b))))
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))
        (with-temp-buffer
          (insert-file-contents (org-pdf-test--latest-tex cache "B note"))
          (should (search-forward (concat "\\addbibresource{" bib "}") nil t)))
        (org-pdf-test--write bib "@book{example,title={Changed},author={Someone},year={2026}}\n")
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))))))

(ert-deftest org-pdf-babel-never-executes-and-confirmation-is-unchanged ()
  (org-pdf-test--fixture
    (let ((marker (expand-file-name "must-not-exist" workspace))
          (org-confirm-babel-evaluate t))
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert (format "\n#+begin_src emacs-lisp :exports results\n(write-region \"bad\" nil %S)\n#+end_src\n" marker))
                        (write-region nil nil b nil 'silent))
      (my/org-pdf--run (org-pdf-test--request scope (list b)))
      (should org-confirm-babel-evaluate)
      (should-not (file-exists-p marker)))))

(ert-deftest org-pdf-existing-user-buffer-is-not-killed-or-modified ()
  (org-pdf-test--fixture
    (let* ((org-inhibit-startup t)
           (buffer (find-file-noselect b)))
      (with-current-buffer buffer (goto-char (point-max)) (insert "Unsaved user work"))
      (my/org-pdf--run (org-pdf-test--request scope (list b)))
      (should (buffer-live-p buffer))
      (should (buffer-modified-p buffer))
      (with-current-buffer buffer (should (string-suffix-p "Unsaved user work" (buffer-string)))))))

(ert-deftest org-pdf-metadata-example-ids-are-not-indexed ()
  (org-pdf-test--fixture
    (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                      (insert "\n#+begin_example\n:PROPERTIES:\n:ID: fake\n:END:\n#+end_example\n")
                      (write-region nil nil b nil 'silent))
    (let ((index (my/org-pdf--make-index (list b))))
      (should (gethash "b" index))
      (should-not (gethash "fake" index)))))

(ert-deftest org-pdf-rejects-missing-and-duplicate-link-ids ()
  (org-pdf-test--fixture
    (org-pdf-test--write c ":PROPERTIES:\n:ID: b\n:END:\n#+title: Duplicate\n")
    (let ((result (car (my/org-pdf--run (org-pdf-test--request scope (list a))))))
      (should (eq (plist-get result :status) 'failed))
      (should (string-match-p "Duplicate Org ID" (plist-get result :error))))))

(ert-deftest org-pdf-refuses-outside-scope-and-source-side-cache ()
  (org-pdf-test--fixture
    (should-error (my/org-pdf--request 'study (list c) workspace nil) :type 'user-error)
    (let ((my/org-pdf-cache-directory (expand-file-name ".cache" root)))
      (should-error (org-pdf-test--request scope (list a)) :type 'user-error))))

(ert-deftest org-pdf-save-prompt-is-scoped-and-does-not-discard-work ()
  (org-pdf-test--fixture
    (let* ((org-inhibit-startup t)
           (buffer (find-file-noselect a)))
      (with-current-buffer buffer (goto-char (point-max)) (insert "Unsaved work"))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
        (should-error (my/org-pdf--save-sources (list a)) :type 'user-error))
      (should (buffer-modified-p buffer)))))

(ert-deftest org-pdf-binding-does-not-steal-babel-prefix ()
  (let ((org-mode-map (copy-keymap org-mode-map))
        (org-preview-latex-image-directory org-preview-latex-image-directory))
    (my/org-pdf-setup)
    (should (keymapp (lookup-key org-mode-map (kbd "C-c C-v"))))
    (should (eq (lookup-key org-mode-map (kbd "C-c n p")) #'my/org-pdf-preview))
    (should (eq (lookup-key org-mode-map (kbd "C-c n P")) #'my/org-pdf-update-directory))
    (should (file-name-absolute-p org-preview-latex-image-directory))))

(ert-deftest org-pdf-cancellation-is-cooperative-and-stops-further-notes ()
  (org-pdf-test--fixture
    (let* ((cancel (expand-file-name "cancel" cache))
           (request (plist-put (org-pdf-test--request scope (list a b)) :cancel-file cancel))
           (compile (symbol-function 'org-latex-compile)))
      (cl-letf (((symbol-function 'org-latex-compile)
                 (lambda (tex &rest _)
                   (prog1 (funcall compile tex) (my/org-pdf--write cancel t)))))
        (should (equal (org-pdf-test--statuses (my/org-pdf--run request)) '(built cancelled))))
      (should (= org-pdf-test--compiles 1)))))

(ert-deftest org-pdf-worker-lock-rejects-competing-live-workers ()
  (org-pdf-test--fixture
    (let ((lock (my/org-pdf--acquire-lock cache)))
      (unwind-protect
          (should-error (my/org-pdf--acquire-lock cache))
        (unlock-file lock)))))

(ert-deftest org-pdf-dependency-save-prompts-only-for-relevant-modified-buffers ()
  (org-pdf-test--fixture
    (let* ((org-inhibit-startup t)
           (setup-buffer (find-file-noselect setup))
           (other-buffer (find-file-noselect c)) prompts)
      (with-current-buffer setup-buffer (goto-char (point-max)) (insert "\n# Changed setup\n"))
      (with-current-buffer other-buffer (goto-char (point-max)) (insert "Unrelated unsaved prose"))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (push prompt prompts) t)))
        (my/org-pdf--prepare-sources (list b)))
      (should (= (length prompts) 1))
      (should-not (buffer-modified-p setup-buffer))
      (should (buffer-modified-p other-buffer)))))

(ert-deftest org-pdf-unknown-id-is-an-actionable-per-note-failure ()
  (org-pdf-test--fixture
    (org-pdf-test--write a "#+title: A\n[[id:unknown][Unknown]]\n")
    (let ((results (my/org-pdf--run (org-pdf-test--request scope (list a b)))))
      (should (equal (org-pdf-test--statuses results) '(failed built)))
      (should (string-match-p "Unknown Org ID: unknown" (plist-get (car results) :error))))))

(ert-deftest org-pdf-scope-link-change-invalidates-but-keeps-the-address ()
  (org-pdf-test--fixture
    (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                      (insert "\n[[id:a][A]]\n") (write-region nil nil b nil 'silent))
    (let* ((first (cadr (my/org-pdf--run (org-pdf-test--request scope (list a b)))))
           (second (car (my/org-pdf--run
                         (org-pdf-test--request (file-name-directory b) (list b))))))
      (should (eq (plist-get second :status) 'built))
      (should (equal (plist-get first :pdf) (plist-get second :pdf)))
      (with-temp-buffer
        (insert-file-contents (org-pdf-test--latest-tex cache "B note"))
        (should (search-forward (concat "\\href{file:" a "}{A (Org)}") nil t))))))

(ert-deftest org-pdf-external-heading-links-do-not-claim-a-document-pdf-anchor ()
  (org-pdf-test--fixture
    (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                      (insert "\n[[id:local][A heading]]\n") (write-region nil nil b nil 'silent))
    (my/org-pdf--run (org-pdf-test--request scope (list a b)))
    (with-temp-buffer
      (insert-file-contents (org-pdf-test--latest-tex cache "B note"))
      (should (search-forward (concat "\\href{file:" a "}{A heading (Org)}") nil t)))))

(ert-deftest org-pdf-image-dependency-is-tracked ()
  (org-pdf-test--fixture
    (let ((image (expand-file-name "figure.png" (file-name-directory b))))
      (org-pdf-test--write image "First image bytes")
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert "\n[[file:figure.png]]\n") (write-region nil nil b nil 'silent))
      (let ((request (org-pdf-test--request scope (list b))))
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))
        (org-pdf-test--write image "Second image bytes")
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))))))

(ert-deftest org-pdf-recorder-relative-paths-use-the-original-source-directory ()
  (org-pdf-test--fixture
    (let ((raw (expand-file-name "raw.tex" (file-name-directory b))))
      (org-pdf-test--write raw "First raw input")
      (setq org-pdf-test--record "raw.tex")
      (let ((request (org-pdf-test--request scope (list b))))
        (my/org-pdf--run request)
        (org-pdf-test--write raw "Second raw input")
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))))))

(ert-deftest org-pdf-export-name-overrides-never-delete-authored-tex ()
  (org-pdf-test--fixture
    (let ((authored (expand-file-name "B note.tex" (file-name-directory b))))
      (org-pdf-test--write authored "User-authored TeX, not an export artifact")
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert "\n#+export_file_name: another name\n")
                        (write-region nil nil b nil 'silent))
      (let ((result (car (my/org-pdf--run (org-pdf-test--request scope (list b))))))
        (should (eq (plist-get result :status) 'built))
        (should (equal (plist-get result :pdf) (expand-file-name "course/sub/B note.pdf" mirror))))
      (with-temp-buffer (insert-file-contents authored)
                        (should (equal (buffer-string) "User-authored TeX, not an export artifact"))))))

(ert-deftest org-pdf-output-symlinks-cannot-escape-the-mirror ()
  (org-pdf-test--fixture
    (let ((outside (expand-file-name "outside" workspace)))
      (make-directory outside)
      (make-directory (expand-file-name "course" mirror) t)
      (make-symbolic-link outside (expand-file-name "course/sub" mirror))
      (let ((result (car (my/org-pdf--run (org-pdf-test--request scope (list b))))))
        (should (eq (plist-get result :status) 'failed))
        (should (string-match-p "escapes" (plist-get result :error)))))))

(ert-deftest org-pdf-rendering-setting-change-invalidates-the-cache ()
  (org-pdf-test--fixture
    (my/org-pdf--run (org-pdf-test--request scope (list b)))
    (let ((org-latex-default-class "report"))
      (should (eq (plist-get (car (my/org-pdf--run
                                   (org-pdf-test--request scope (list b)))) :status) 'built)))))

(ert-deftest org-pdf-title-change-does-not-rename-the-output ()
  (org-pdf-test--fixture
    (let ((first (car (my/org-pdf--run (org-pdf-test--request scope (list b))))))
      (with-temp-buffer (insert-file-contents b) (goto-char (point-min))
                        (search-forward "Note B") (replace-match "A different title")
                        (write-region nil nil b nil 'silent))
      (let ((second (car (my/org-pdf--run (org-pdf-test--request scope (list b))))))
        (should (eq (plist-get second :status) 'built))
        (should (equal (plist-get first :pdf) (plist-get second :pdf)))))))

(ert-deftest org-pdf-native-warnings-remain-visible-without-discarding-good-output ()
  (org-pdf-test--fixture
    (let ((compile (symbol-function 'org-latex-compile)))
      (cl-letf (((symbol-function 'org-latex-compile)
                 (lambda (tex &rest _)
                   (prog1 (funcall compile tex)
                     (org-pdf-test--write (concat (file-name-sans-extension tex) ".log")
                                          "LaTeX Warning: Example warning.\n")))))
        (let ((result (car (my/org-pdf--run (org-pdf-test--request scope (list b))))))
          (should (eq (plist-get result :status) 'built))
          (should (equal (plist-get result :warnings) '("LaTeX Warning: Example warning."))))))))

(ert-deftest org-pdf-a-stale-biber-error-cannot-poison-a-later-attempt ()
  (org-pdf-test--fixture
    (let ((compile (symbol-function 'org-latex-compile))
          (request (org-pdf-test--request scope (list b))))
      (cl-letf (((symbol-function 'org-latex-compile)
                 (lambda (tex &rest _)
                   (prog1 (funcall compile tex)
                     (when (= org-pdf-test--compiles 1)
                       (org-pdf-test--write (concat (file-name-sans-extension tex) ".blg")
                                            "ERROR - Old Biber failure\n"))))))
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'failed))
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))
        (should (= (length (directory-files-recursively cache "B note\\.tex\\'")) 2))))))

(ert-deftest org-pdf-a-corrupt-state-record-is-a-cache-miss ()
  (org-pdf-test--fixture
    (let ((request (org-pdf-test--request scope (list b))))
      (my/org-pdf--run request)
      (org-pdf-test--write (cl-find-if (lambda (file) (string-match-p "/state/" file))
                                       (directory-files-recursively cache "\\.eld\\'"))
                           "broken-cache\n")
      (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built)))))

(ert-deftest org-pdf-org-includes-are-classified-by-semantics-not-extension ()
  (org-pdf-test--fixture
    (let ((chapter (expand-file-name "chapter.txt" (file-name-directory b)))
          (nested (expand-file-name "nested.txt" (file-name-directory b))))
      (org-pdf-test--write chapter "Chapter text\n#+INCLUDE: \"nested.txt\"\n")
      (org-pdf-test--write nested "Nested text\n")
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert "\n#+INCLUDE: \"chapter.txt\"\n")
                        (write-region nil nil b nil 'silent))
      (let ((request (org-pdf-test--request scope (list b))))
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))
        (org-pdf-test--write nested "Changed nested text\n")
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))))))

(ert-deftest org-pdf-literal-org-includes-do-not-activate-their-links-or-includes ()
  (org-pdf-test--fixture
    (let ((example (expand-file-name "library/example.org" workspace)))
      (org-pdf-test--write example "[[id:unknown-example][Example]]\n#+INCLUDE: \"missing.org\"\n")
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert "\n#+INCLUDE: \"../../../library/example.org\" src org\n")
                        (write-region nil nil b nil 'silent))
      (should (eq (plist-get (car (my/org-pdf--run
                                   (org-pdf-test--request scope (list b)))) :status) 'built)))))

(ert-deftest org-pdf-included-local-ids-can-come-from-outside-the-index ()
  (org-pdf-test--fixture
    (let ((chapter (expand-file-name "library/chapter.txt" workspace)))
      (org-pdf-test--write chapter "* Included heading\n:PROPERTIES:\n:ID: included-heading\n:END:\nIncluded body.\n")
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert "\n[[id:included-heading][Included]]\n#+INCLUDE: \"../../../library/chapter.txt\"\n")
                        (write-region nil nil b nil 'silent))
      (let ((result (car (my/org-pdf--run (org-pdf-test--request scope (list b))))))
        (should (eq (plist-get result :status) 'built)))
      (with-temp-buffer
        (insert-file-contents (org-pdf-test--latest-tex cache "B note"))
        (should (re-search-forward "\\\\hyperref\\[[^]]+\\]{Included}" nil t))))))

(ert-deftest org-pdf-global-bibliography-is-tracked-for-included-citations ()
  (org-pdf-test--fixture
    (let* ((chapter (expand-file-name "chapter.txt" (file-name-directory b)))
           (bib (expand-file-name "library/global.bib" workspace))
           (org-cite-global-bibliography (list bib)))
      (org-pdf-test--write chapter "Included citation [cite:@example].\n")
      (org-pdf-test--write bib "@book{example,title={First title},author={Someone},year={2026}}\n")
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert "\n#+cite_export: biblatex numeric\n#+INCLUDE: \"chapter.txt\"\n#+print_bibliography:\n")
                        (write-region nil nil b nil 'silent))
      (let ((request (org-pdf-test--request scope (list b))))
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))
        (org-pdf-test--write bib "@book{example,title={New title},author={Someone},year={2026}}\n")
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))))))

(ert-deftest org-pdf-multiple-native-bibliography-declarations-and-quoted-paths ()
  (org-pdf-test--fixture
    (let ((first (expand-file-name "library/first.bib" workspace))
          (second (expand-file-name "library/second references.bib" workspace)))
      (org-pdf-test--write first "@book{first,title={First}}\n")
      (org-pdf-test--write second "@book{second,title={Second}}\n")
      (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                        (insert "\n#+bibliography: ../../../library/first.bib\n#+bibliography: \"../../../library/second references.bib\"\n")
                        (write-region nil nil b nil 'silent))
      (let ((request (org-pdf-test--request scope (list b))))
        (my/org-pdf--run request)
        (org-pdf-test--write second "@book{second,title={Changed second}}\n")
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))))))

(ert-deftest org-pdf-hidden-unresolved-links-do-not-break-an-export ()
  (org-pdf-test--fixture
    (with-temp-buffer (insert-file-contents b) (goto-char (point-max))
                      (insert "\n* Private draft :noexport:\n[[id:unknown-hidden][Unfinished reference]]\n")
                      (write-region nil nil b nil 'silent))
    (should (eq (plist-get (car (my/org-pdf--run
                                 (org-pdf-test--request scope (list b)))) :status) 'built))))

(ert-deftest org-pdf-native-lock-protects-against-another-emacs-process ()
  (org-pdf-test--fixture
    (let* ((buffer (generate-new-buffer " *org-pdf-lock-test*"))
           (form `(let ((lock (my/org-pdf--acquire-lock ,cache)))
                    (unwind-protect
                        (progn (princ "READY\n") (read-string ""))
                      (unlock-file lock))))
           (process (make-process
                     :name "org-pdf-lock-test" :buffer buffer :noquery t
                     :connection-type 'pipe
                     :command (list (expand-file-name invocation-name invocation-directory)
                                    "--batch" "-Q" "-l" my/org-pdf--module-file
                                    "--eval" (prin1-to-string form))))
           (deadline (+ (float-time) 15)))
      (unwind-protect
          (progn
            (while (and (process-live-p process) (< (float-time) deadline)
                        (not (with-current-buffer buffer (string-match-p "READY" (buffer-string)))))
              (accept-process-output process 0.1))
            (should (with-current-buffer buffer (string-match-p "READY" (buffer-string))))
            (should-error (my/org-pdf--acquire-lock cache))
            (process-send-string process "\n")
            (while (and (process-live-p process) (< (float-time) deadline))
              (accept-process-output process 0.1))
            (should-not (process-live-p process))
            (let ((lock (my/org-pdf--acquire-lock cache))) (unlock-file lock)))
        (when (process-live-p process) (delete-process process))
        (kill-buffer buffer)))))

(ert-deftest org-pdf-directory-command-is-also-bound-in-dired ()
  (require 'dired)
  (let ((org-mode-map (copy-keymap org-mode-map))
        (dired-mode-map (copy-keymap dired-mode-map))
        (org-preview-latex-image-directory org-preview-latex-image-directory))
    (my/org-pdf-setup)
    (should (eq (lookup-key dired-mode-map (kbd "C-c n P"))
                #'my/org-pdf-update-directory))))

(ert-deftest org-pdf-preview-reuses-its-window-and-restores-the-page ()
  (let ((buffer (generate-new-buffer " *org-pdf-preview-test*"))
        reverted page displayed)
    (unwind-protect
        (progn
          (with-current-buffer buffer (setq major-mode 'pdf-view-mode))
          (cl-letf (((symbol-function 'find-file-noselect) (lambda (&rest _) buffer))
                    ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window)))
                    ((symbol-function 'pdf-view-current-page) (lambda (&rest _) 2))
                    ((symbol-function 'pdf-view-goto-page) (lambda (value &rest _) (setq page value)))
                    ((symbol-function 'pdf-info-number-of-pages) (lambda (&rest _) 3))
                    ((symbol-function 'verify-visited-file-modtime) (lambda (&rest _) nil))
                    ((symbol-function 'revert-buffer) (lambda (&rest _) (setq reverted t)))
                    ((symbol-function 'display-buffer) (lambda (&rest _) (setq displayed t))))
            (my/org-pdf--show-preview "/unused/preview.pdf")
            (should reverted)
            (should (= page 2))
            (should-not displayed)))
      (kill-buffer buffer))))

(ert-deftest org-pdf-source-change-during-publication-is-not-marked-current ()
  (org-pdf-test--fixture
    (let ((request (org-pdf-test--request scope (list b)))
          (promote (symbol-function 'my/org-pdf--promote)))
      (cl-letf (((symbol-function 'my/org-pdf--promote)
                 (lambda (pdf target)
                   (prog1 (funcall promote pdf target)
                     (org-pdf-test--write b "#+title: Changed during publication\n")))))
        (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built)))
      (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))
      (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'current))
      (should (= org-pdf-test--compiles 2)))))

(ert-deftest org-pdf-new-recorder-input-changed-during-compile-is-not-published ()
  (org-pdf-test--fixture
    (let ((raw (expand-file-name "raw.tex" (file-name-directory b)))
          (request (org-pdf-test--request scope (list b)))
          (compile (symbol-function 'org-latex-compile)))
      (org-pdf-test--write raw "Original raw input\n")
      (setq org-pdf-test--record raw)
      (cl-letf (((symbol-function 'org-latex-compile)
                 (lambda (tex &rest _)
                   (prog1 (funcall compile tex)
                     (org-pdf-test--write raw "Changed during compilation\n")))))
        (let ((result (car (my/org-pdf--run request))))
          (should (eq (plist-get result :status) 'failed))
          (should (string-match-p "newly discovered input changed" (plist-get result :error)))))
      (should-not (file-exists-p (expand-file-name "course/sub/B note.pdf" mirror)))
      (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'built))
      (should (eq (plist-get (car (my/org-pdf--run request)) :status) 'current))
      (should (= org-pdf-test--compiles 2)))))

(ert-run-tests-batch-and-exit)
