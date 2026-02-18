;;; org-ai-skills-test.el --- Tests for org-ai-skills -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)
(add-to-list 'load-path (expand-file-name "../elisp" (file-name-directory (or load-file-name buffer-file-name))))
(require 'org-ai-skills)

(defconst org-ai-skills-test--project-root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))

(defconst org-ai-skills-test--first-skill-file
  (expand-file-name "skills/001-generate-structured-notes.org" org-ai-skills-test--project-root))

(defconst org-ai-skills-test--gptel-dir
  (expand-file-name "~/.emacs.d/straight/repos/gptel/"))

(defun org-ai-skills-test--write-temp-skill (content)
  "Write CONTENT to a temporary skill file and return its path."
  (let ((file (make-temp-file "org-ai-skills-" nil ".org")))
    (with-temp-file file
      (insert content))
    file))

(ert-deftest org-ai-skills-feature-provided ()
  "The package should provide the expected feature."
  (should (featurep 'org-ai-skills)))

(ert-deftest org-ai-skills-mode-toggle ()
  "The mode should enable and disable cleanly in a temp buffer."
  (with-temp-buffer
    (org-ai-skills-mode 1)
    (should org-ai-skills-mode)
    (org-ai-skills-mode 0)
    (should-not org-ai-skills-mode)))

(ert-deftest org-ai-skills-parse-first-skill-success ()
  "The first skill spec should parse to a structured object."
  (let ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file)))
    (should (string= (plist-get skill :skill-id) "gen-notes"))
    (should (string= (plist-get skill :title) "Generate Structured Notes"))
    (should (string= (plist-get (plist-get skill :tags) :invocation) "suggest"))))

(ert-deftest org-ai-skills-parse-missing-skill-id-fails ()
  "Missing SKILL_ID should raise a parse error."
  (let ((file (org-ai-skills-test--write-temp-skill
               "* Skill: Missing Id\n#+EFFECT: pure\n#+INVOCATION: suggest\n#+CONTEXT: project\n#+DETERMINISM: deterministic\n\n** Description\nNo id.\n")))
    (unwind-protect
        (should-error (org-ai-skills-parse-skill-file file)
                      :type 'org-ai-skills-parse-error)
      (delete-file file))))

(ert-deftest org-ai-skills-parse-invalid-invocation-fails ()
  "Invalid INVOCATION value should raise a parse error."
  (let ((file (org-ai-skills-test--write-temp-skill
               "* Skill: Bad Invocation\n:PROPERTIES:\n:SKILL_ID: bad-invoke\n:END:\n#+EFFECT: pure\n#+INVOCATION: random\n#+CONTEXT: project\n#+DETERMINISM: deterministic\n\n** Description\nBad invocation value.\n")))
    (unwind-protect
        (should-error (org-ai-skills-parse-skill-file file)
                      :type 'org-ai-skills-parse-error)
      (delete-file file))))

(ert-deftest org-ai-skills-parse-does-not-mutate-file ()
  "Parsing must not modify the original skill file."
  (let ((before (with-temp-buffer
                  (insert-file-contents org-ai-skills-test--first-skill-file)
                  (secure-hash 'sha256 (buffer-string)))))
    (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file)
    (let ((after (with-temp-buffer
                   (insert-file-contents org-ai-skills-test--first-skill-file)
                   (secure-hash 'sha256 (buffer-string)))))
      (should (string= before after)))))

(ert-deftest org-ai-skills-gptel-payload-is-structured ()
  "Skill data should map into a stable payload for gptel."
  (let* ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file))
         (payload (org-ai-skills-build-gptel-payload
                   skill
                   "Draft a product specification for org-ai-skills plugin")))
    (should (equal (plist-get payload :skill-id) "gen-notes"))
    (should (plist-get payload :tags))
    (should (string-match-p "Draft a product specification"
                            (plist-get payload :prompt)))))

(ert-deftest org-ai-skills-can-require-gptel-from-straight-checkout ()
  "gptel should be loadable from straight checkout path."
  (unless (file-directory-p org-ai-skills-test--gptel-dir)
    (ert-fail (format "Expected gptel directory to exist: %s"
                      org-ai-skills-test--gptel-dir)))
  (should (org-ai-skills-require-gptel org-ai-skills-test--gptel-dir))
  (should (featurep 'gptel)))

(ert-deftest org-ai-skills-org-resolve-subtree-current-heading ()
  "Resolve nearest heading subtree from point in Org content."
  (with-temp-buffer
    (org-mode)
    (insert "* Top\n** Child\n*** Leaf\nLeaf body.\n")
    (search-backward "Leaf body.")
    (let ((subtree (org-ai-skills-org-resolve-subtree 'current)))
      (should (equal (plist-get subtree :heading) "Leaf"))
      (should (= (plist-get subtree :level) 3))
      (should (eq (plist-get subtree :context-mode) 'current))
      (should (= (plist-get subtree :levels-up) 0))
      (should (string-prefix-p "*** Leaf" (plist-get subtree :text))))))

(ert-deftest org-ai-skills-org-resolve-subtree-upper-level ()
  "Resolve ancestor heading when expanding upper levels."
  (with-temp-buffer
    (org-mode)
    (insert "* Top\n** Child\n*** Leaf\nLeaf body.\n")
    (search-backward "Leaf body.")
    (let ((subtree (org-ai-skills-org-resolve-subtree 'upper-level 1)))
      (should (equal (plist-get subtree :heading) "Child"))
      (should (= (plist-get subtree :level) 2))
      (should (eq (plist-get subtree :context-mode) 'upper-level))
      (should (= (plist-get subtree :levels-up) 1))
      (should (string-prefix-p "** Child" (plist-get subtree :text))))))

(ert-deftest org-ai-skills-org-resolve-subtree-errors-without-heading ()
  "Subtree resolution should fail when point is before first heading."
  (with-temp-buffer
    (org-mode)
    (insert "No heading here.\n")
    (goto-char (point-min))
    (should-error (org-ai-skills-org-resolve-subtree 'current)
                  :type 'org-ai-skills-org-context-error)))

(ert-deftest org-ai-skills-org-resolve-subtree-errors-on-invalid-expansion ()
  "Upper-level expansion should fail when ancestor does not exist."
  (with-temp-buffer
    (org-mode)
    (insert "* Top\n** Child\n")
    (goto-char (point-max))
    (should-error (org-ai-skills-org-resolve-subtree 'upper-level 5)
                  :type 'org-ai-skills-org-context-error)))

(ert-deftest org-ai-skills-build-gptel-rewrite-request-structure ()
  "Rewrite payload should include subtree content and context metadata."
  (let* ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file))
         (subtree '(:heading "Leaf"
                    :text "*** Leaf\nBody\n"
                    :context-mode current
                    :levels-up 0))
         (request (org-ai-skills-build-gptel-rewrite-request
                   skill subtree "Rewrite with concise style")))
    (should (equal (plist-get request :skill-id) "gen-notes"))
    (should (equal (plist-get request :headline) "Leaf"))
    (should (eq (plist-get request :context-mode) 'current))
    (should (string-match-p "Rewrite with concise style"
                            (plist-get request :prompt)))
    (should (string-match-p "\\*\\*\\* Leaf"
                            (plist-get request :prompt)))))

(ert-deftest org-ai-skills-gptel-dispatch-errors-when-gptel-missing ()
  "Dispatch should fail with explicit error when gptel is unavailable."
  (let ((original-featurep (symbol-function 'featurep)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     nil
                   (funcall original-featurep feature))))
              ((symbol-function 'org-ai-skills-require-gptel)
               (lambda (&optional _gptel-dir) nil)))
      (should-error (org-ai-skills-gptel-dispatch-rewrite
                     '(:prompt "rewrite")
                     #'ignore)
                    :type 'org-ai-skills-gptel-error))))

(ert-deftest org-ai-skills-org-context-candidates-show-path-preview ()
  "Rewrite target candidates should include current and ancestor path previews."
  (with-temp-buffer
    (org-mode)
    (insert "* Top\n** Child\n*** Leaf\nLeaf body.\n")
    (search-backward "Leaf body.")
    (let ((candidates (org-ai-skills-org-collect-context-candidates)))
      (should (= (length candidates) 3))
      (should (string-match-p "\\[current\\] Top/Child/Leaf"
                              (car (nth 0 candidates))))
      (should (string-match-p "\\[up:1\\] Top/Child"
                              (car (nth 1 candidates))))
      (should (equal (plist-get (cdr (nth 0 candidates)) :heading) "Leaf"))
      (should (equal (plist-get (cdr (nth 1 candidates)) :heading) "Child")))))

(ert-deftest org-ai-skills-org-read-rewrite-target-uses-selected-preview ()
  "Selected preview candidate should resolve to expected target subtree."
  (with-temp-buffer
    (org-mode)
    (insert "* Top\n** Child\n*** Leaf\nLeaf body.\n")
    (search-backward "Leaf body.")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt collection &rest _rest)
                 (nth 1 collection))))
      (let ((target (org-ai-skills-org-read-rewrite-target)))
        (should (equal (plist-get target :heading) "Child"))
        (should (eq (plist-get target :context-mode) 'upper-level))
        (should (= (plist-get target :levels-up) 1))))))

(ert-deftest org-ai-skills-sanitize-rewrite-output-fixes-level-and-preface ()
  "Sanitizer should remove explanation preface and enforce target level."
  (let* ((subtree '(:level 2 :heading "Child"))
         (raw "Here is the rewrite:\n*** Child Revised\n**** Sub\nBody\n")
         (cleaned (org-ai-skills--sanitize-rewrite-output raw subtree)))
    (should-not (string-match-p "Here is the rewrite" cleaned))
    (should (string-prefix-p "** Child Revised" cleaned))
    (should (string-match-p "^\\*\\*\\* Sub$" cleaned))))

(ert-deftest org-ai-skills-embark-action-delegates-to-rewrite-command ()
  "Embark adapter should dispatch to the interactive rewrite command."
  (let (called)
    (cl-letf (((symbol-function 'call-interactively)
               (lambda (command &optional _record-flag _keys)
                 (setq called command))))
      (org-ai-skills-embark-rewrite-subtree-action "target")
      (should (eq called #'org-ai-skills-org-rewrite-subtree)))))

(ert-deftest org-ai-skills-embark-install-action-registers-org-heading-map ()
  "Embark install helper should register the org heading action map."
  (let ((had-bound (boundp 'embark-keymap-alist))
        (old-value (and (boundp 'embark-keymap-alist)
                        (symbol-value 'embark-keymap-alist))))
    (unwind-protect
        (progn
          (set 'embark-keymap-alist nil)
          (cl-letf (((symbol-function 'require)
                     (lambda (feature &optional _filename _noerror)
                       (eq feature 'embark))))
            (should (org-ai-skills-embark-install-action))
            (should (assq 'org-heading embark-keymap-alist))
            (should (eq (lookup-key (symbol-value
                                     (cdr (assq 'org-heading embark-keymap-alist)))
                                    (kbd "R"))
                        #'org-ai-skills-embark-rewrite-subtree-action))))
      (if had-bound
          (set 'embark-keymap-alist old-value)
        (makunbound 'embark-keymap-alist)))))

;;; org-ai-skills-test.el ends here
