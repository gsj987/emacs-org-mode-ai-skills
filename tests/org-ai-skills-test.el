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

(defconst org-ai-skills-test--twitter-skill-file
  (expand-file-name "skills/002-simplify-for-twitter-post.org" org-ai-skills-test--project-root))

(defconst org-ai-skills-test--financial-skill-file
  (expand-file-name "skills/003-daily-financial-news-report.org" org-ai-skills-test--project-root))

(defconst org-ai-skills-test--article-outline-skill-file
  (expand-file-name "skills/004-article-outline-from-source.org" org-ai-skills-test--project-root))

(defconst org-ai-skills-test--article-compose-skill-file
  (expand-file-name "skills/005-article-compose-from-outline.org" org-ai-skills-test--project-root))

(defconst org-ai-skills-test--article-repair-skill-file
  (expand-file-name "skills/006-article-repair-subtree.org" org-ai-skills-test--project-root))

(defconst org-ai-skills-test--article-polish-skill-file
  (expand-file-name "skills/007-article-polish-editorial.org" org-ai-skills-test--project-root))

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
    (should (string= (plist-get (plist-get skill :tags) :invocation) "suggest"))
    (should (plist-get skill :outputs))
    (should (listp (plist-get skill :contracts)))
    (should (listp (plist-get skill :requirements)))
    (should (listp (plist-get skill :function-calls)))
    (should (plist-get skill :raw-sections))))

(ert-deftest org-ai-skills-parse-twitter-simplification-skill-success ()
  "Twitter simplification example skill should parse to a structured object."
  (let ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--twitter-skill-file)))
    (should (string= (plist-get skill :skill-id) "simplify-twitter"))
    (should (string= (plist-get skill :title) "Simplify For Twitter Post"))
    (should (string= (plist-get (plist-get skill :tags) :invocation) "suggest"))
    (should (member "produce at least one tweet-ready sentence no longer than 280 characters"
                    (plist-get skill :contracts)))
    (should (member "remove unnecessary verbosity, repetition, and filler"
                    (plist-get skill :requirements)))
    (should (plist-get skill :raw-sections))))

(ert-deftest org-ai-skills-parse-financial-report-skill-success ()
  "Financial news example skill should parse to a structured object."
  (let ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--financial-skill-file)))
    (should (string= (plist-get skill :skill-id) "fin-news-daily-report"))
    (should (string= (plist-get skill :title) "Generate Daily Financial News Report"))
    (should (equal (plist-get (plist-get skill :tags) :effect) "external"))
    (should (= (length (plist-get skill :function-calls)) 1))
    (should (= (length (plist-get skill :function-definitions)) 1))
    (should (equal (plist-get (car (plist-get skill :function-calls)) :name)
                   "org-ai-skills-search1api-fetch-financial-news-raw"))))

(ert-deftest org-ai-skills-parse-article-workflow-skills-success ()
  "Article workflow skills should parse with expected IDs."
  (let ((skills (mapcar #'org-ai-skills-parse-skill-file
                        (list org-ai-skills-test--article-outline-skill-file
                              org-ai-skills-test--article-compose-skill-file
                              org-ai-skills-test--article-repair-skill-file
                              org-ai-skills-test--article-polish-skill-file))))
    (should (equal (mapcar (lambda (skill) (plist-get skill :skill-id)) skills)
                   '("article-outline-from-source"
                     "article-compose-from-outline"
                     "article-repair-subtree"
                     "article-polish-editorial")))
    (should (equal (plist-get (car (plist-get (car skills) :function-calls)) :name)
                   "org-ai-skills-read-buffer"))
    (should (equal (plist-get (car (last (plist-get (nth 2 skills) :function-calls))) :name)
                   "org-ai-skills-read-file"))))

(ert-deftest org-ai-skills-parse-new-sections-for-context-bundle ()
  "Parser should extract contracts, requirements, and function calls."
  (let ((file (org-ai-skills-test--write-temp-skill
               "* Skill: Extended Skill\n:PROPERTIES:\n:SKILL_ID: ext-skill\n:END:\n#+EFFECT: pure\n#+INVOCATION: manual\n#+CONTEXT: project\n#+DETERMINISM: deterministic\n\n** Description\nExtended skill.\n\n** Contracts\n- Output must be concise.\n- Preserve source language.\n\n** Requirements\n- Keep Org structure valid.\n\n** Function Calls\n- name: normalize-headings\n  when: before-return\n  args: (target-level)\n")))
    (unwind-protect
        (let* ((skill (org-ai-skills-parse-skill-file file))
               (functions (plist-get skill :function-calls)))
          (should (equal (plist-get skill :contracts)
                         '("Output must be concise." "Preserve source language.")))
          (should (equal (plist-get skill :requirements)
                         '("Keep Org structure valid.")))
          (should (= (length functions) 1))
          (should (equal (plist-get (car functions) :name) "normalize-headings"))
          (should (equal (plist-get (car functions) :when) "before-return"))
          (should (equal (plist-get (car functions) :args) "(target-level)")))
      (delete-file file))))

(ert-deftest org-ai-skills-parse-function-calls-supports-underscore-keys ()
  "Function call parser should preserve custom keys with underscores."
  (let* ((items (org-ai-skills--parse-function-calls
                 "- name: fn\n  args: (language_hint)\n  language_hint: zh or en"))
         (item (car items)))
    (should (equal (plist-get item :name) "fn"))
    (should (equal (plist-get item :language_hint) "zh or en"))))

(ert-deftest org-ai-skills-parse-old-spec-backward-compatible ()
  "Missing optional sections should default to empty structures."
  (let ((file (org-ai-skills-test--write-temp-skill
               "* Skill: Legacy Skill\n:PROPERTIES:\n:SKILL_ID: legacy\n:END:\n#+EFFECT: pure\n#+INVOCATION: suggest\n#+CONTEXT: project\n#+DETERMINISM: deterministic\n\n** Description\nLegacy only.\n")))
    (unwind-protect
        (let ((skill (org-ai-skills-parse-skill-file file)))
          (should-not (plist-get skill :contracts))
          (should-not (plist-get skill :requirements))
          (should-not (plist-get skill :function-calls))
          (should (plist-get skill :raw-sections)))
      (delete-file file))))

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

(ert-deftest org-ai-skills-org-resolve-subtree-includes-purpose-and-source-path ()
  "Resolved subtree should carry inherited PURPOSE and SOURCE_FILE_PATH."
  (with-temp-buffer
    (org-mode)
    (insert "* Root\n:PROPERTIES:\n:PURPOSE: Explain article strategy\n:SOURCE_FILE_PATH: ./notes/source.md\n:END:\n** Child\nBody.\n")
    (search-backward "Body.")
    (let ((subtree (org-ai-skills-org-resolve-subtree 'current)))
      (should (equal (plist-get subtree :purpose) "Explain article strategy"))
      (should (equal (plist-get subtree :source-file-path) "./notes/source.md")))))

(ert-deftest org-ai-skills-org-resolve-subtree-falls-back-to-file-keywords ()
  "Resolved subtree should read PURPOSE and SOURCE_FILE_PATH from file keywords."
  (with-temp-buffer
    (org-mode)
    (insert "#+PURPOSE: File-level purpose\n#+SOURCE_FILE_PATH: ./docs/source.txt\n\n* Child\nBody.\n")
    (search-backward "Body.")
    (let ((subtree (org-ai-skills-org-resolve-subtree 'current)))
      (should (equal (plist-get subtree :purpose) "File-level purpose"))
      (should (equal (plist-get subtree :source-file-path) "./docs/source.txt")))))

(ert-deftest org-ai-skills-org-resolve-subtree-does-not-guess-source-file-path ()
  "Resolved subtree should not infer SOURCE_FILE_PATH from current Org file."
  (with-temp-buffer
    (org-mode)
    (let ((buffer-file-name "/tmp/current-note.org"))
      (insert "* Child\nBody.\n")
      (search-backward "Body.")
      (let ((subtree (org-ai-skills-org-resolve-subtree 'current)))
        (should (equal (plist-get subtree :purpose) ""))
        (should-not (plist-get subtree :source-file-path))))))

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
                    :level 3
                    :path "Top/Child/Leaf"
                    :purpose "Explain details"
                    :source-file-path "./notes/source.md"
                    :text "*** Leaf\nBody\n"
                    :context-mode current
                    :levels-up 0))
         (request (org-ai-skills-build-gptel-rewrite-request
                   skill subtree "Rewrite with concise style")))
    (should (equal (plist-get request :skill-id) "gen-notes"))
    (should (equal (plist-get request :headline) "Leaf"))
    (should (eq (plist-get request :context-mode) 'current))
    (should (plist-get request :skill-context))
    (should (equal (plist-get (plist-get (plist-get request :skill-context) :meta)
                              :skill-id)
                   "gen-notes"))
    (should (string-match-p "Rewrite with concise style"
                            (plist-get request :prompt)))
    (should (string-match-p "Source file path: ./notes/source.md"
                            (plist-get request :prompt)))
    (should (equal (plist-get request :source-file-path) "./notes/source.md"))
    (should (string-match-p "\\*\\*\\* Leaf"
                            (plist-get request :prompt)))))

(ert-deftest org-ai-skills-build-gptel-rewrite-request-compose-enforces-outline-lock ()
  "Compose skill rewrite request should include strict outline constraints."
  (let* ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--article-compose-skill-file))
         (subtree '(:heading "Draft"
                    :level 1
                    :path "Draft"
                    :purpose "Compose article"
                    :source-file-path "./notes/source.md"
                    :text "* Draft\n** A\n:PURPOSE: p\n:END:\n"
                    :context-mode current
                    :levels-up 0))
         (request (org-ai-skills-build-gptel-rewrite-request skill subtree "Compose")))
    (should (plist-get request :rewrite-constraints))
    (should (plist-get (plist-get request :rewrite-constraints) :preserve-headlines))
    (should (plist-get (plist-get request :rewrite-constraints) :omit-property-drawers))
    (should (string-match-p "Keep every headline line unchanged"
                            (plist-get request :prompt)))
    (should (string-match-p "Outline summary (compact context)"
                            (plist-get request :prompt)))))

(ert-deftest org-ai-skills-build-step-request-compose-uses-compact-context ()
  "Planner step request for compose skill should use compact outline context."
  (let* ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--article-compose-skill-file))
         (step '(:step-id "s1" :goal "compose" :skills ("article-compose-from-outline")))
         (run-state '(:task "compose article"
                     :subtree (:text "* Root\n** A\n:PURPOSE: x\n:END:\n")))
         (request (org-ai-skills-build-step-request step run-state (list skill))))
    (should (string-match-p "Outline summary (compact context)"
                            (plist-get request :prompt)))
    (should (string-match-p "Strict compose constraints"
                            (plist-get request :prompt)))))

(ert-deftest org-ai-skills-core-read-tools-enabled-by-default ()
  "Core read tools should be included in tool-call surface by default."
  (let* ((org-ai-skills-enable-core-read-tools t)
         (calls (org-ai-skills--request-function-calls '()))
         (names (mapcar (lambda (entry) (plist-get entry :name)) calls)))
    (should (member "org-ai-skills-read-buffer" names))
    (should (member "org-ai-skills-read-file" names))))

(ert-deftest org-ai-skills-core-read-tools-can-be-disabled ()
  "Core read tools should be omitted when feature flag is nil."
  (let* ((org-ai-skills-enable-core-read-tools nil)
         (calls (org-ai-skills--request-function-calls '()))
         (names (mapcar (lambda (entry) (plist-get entry :name)) calls)))
    (should-not (member "org-ai-skills-read-buffer" names))
    (should-not (member "org-ai-skills-read-file" names))))

(ert-deftest org-ai-skills-core-provider-tools-enabled-by-default ()
  "Core provider tools should be exposed by default."
  (let* ((org-ai-skills-enable-core-provider-tools t)
         (calls (org-ai-skills--request-function-calls '()))
         (names (mapcar (lambda (entry) (plist-get entry :name)) calls)))
    (should (member "org-ai-skills-core-provider-shell-exec" names))
    (should (member "org-ai-skills-core-provider-python-exec" names))))

(ert-deftest org-ai-skills-core-provider-allowed-paths-custom-type-is-repeat-string ()
  "Allowed paths customize type should accept free-form path strings."
  (should (equal (get 'org-ai-skills-core-provider-allowed-paths 'custom-type)
                 '(repeat string))))

(ert-deftest org-ai-skills-core-provider-effective-allowed-paths-ignores-invalid-entries ()
  "Effective allowed path list should ignore nil/non-string entries."
  (let ((org-ai-skills-core-provider-allowed-paths
         (list nil "/tmp" 42 ""))
        (org-ai-skills--core-provider-context-directory nil))
    (let ((paths (org-ai-skills--core-provider-effective-allowed-paths)))
      (should (member (expand-file-name "/tmp") paths))
      (should-not (member nil paths))
      (should (= (length paths) 1)))))

(ert-deftest org-ai-skills-default-core-provider-allowed-paths-is-nil-safe ()
  "Default allowed path initializer should never error when file vars are nil."
  (with-temp-buffer
    (let ((load-file-name nil)
          (default-directory "/tmp/"))
      (let ((paths (org-ai-skills--default-core-provider-allowed-paths)))
        (should (listp paths))
        (should (= (length paths) 1))
        (should (stringp (car paths)))))))

(ert-deftest org-ai-skills-core-provider-tools-can-be-disabled ()
  "Core provider tools should be omitted when feature flag is nil."
  (let* ((org-ai-skills-enable-core-provider-tools nil)
         (calls (org-ai-skills--request-function-calls '()))
         (names (mapcar (lambda (entry) (plist-get entry :name)) calls)))
    (should-not (member "org-ai-skills-core-provider-read-file" names))
    (should-not (member "org-ai-skills-core-provider-list-files" names))
    (should-not (member "org-ai-skills-core-provider-search-files" names))
    (should-not (member "org-ai-skills-core-provider-shell-exec" names))
    (should-not (member "org-ai-skills-core-provider-python-exec" names))
    (should-not (member "org-ai-skills-core-provider-org-babel-exec" names))))

(ert-deftest org-ai-skills-core-provider-read-file-enforces-allowed-paths ()
  "Provider read should deny paths outside allowed roots."
  (let ((org-ai-skills-core-provider-allowed-paths (list default-directory)))
    (let ((result (org-ai-skills-core-provider-read-file "/tmp/not-allowed.txt")))
      (should-not (plist-get result :ok))
      (should (equal (plist-get result :error-kind) "path-not-allowed")))))

(ert-deftest org-ai-skills-core-provider-read-file-enforces-allowed-command ()
  "Provider read should deny command types not in allowlist."
  (let* ((file (make-temp-file "org-ai-skills-core-provider-read-")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "abc"))
          (let ((org-ai-skills-core-provider-allowed-commands '(file-list))
                (org-ai-skills-core-provider-allowed-paths (list (file-name-directory file))))
            (let ((result (org-ai-skills-core-provider-read-file file)))
              (should-not (plist-get result :ok))
              (should (equal (plist-get result :error-kind) "command-not-allowed")))))
      (delete-file file))))

(ert-deftest org-ai-skills-core-provider-shell-exec-returns-output ()
  "Provider shell exec should return stdout and exit code metadata."
  (let ((org-ai-skills-core-provider-allowed-paths (list default-directory))
        (org-ai-skills-core-provider-allowed-commands '(shell-exec)))
    (let ((result (org-ai-skills-core-provider-shell-exec "printf 'hello'" default-directory)))
      (should (plist-get result :ok))
      (should (= (plist-get result :exit-code) 0))
      (should (equal (plist-get result :stdout) "hello")))))

(ert-deftest org-ai-skills-core-provider-python-exec-returns-output ()
  "Provider python exec should return stdout when Python exists."
  (skip-unless (or (executable-find "python3") (executable-find "python")))
  (let ((org-ai-skills-core-provider-allowed-paths (list default-directory))
        (org-ai-skills-core-provider-allowed-commands '(python-exec)))
    (let ((result (org-ai-skills-core-provider-python-exec "print('ok')" default-directory)))
      (should (plist-get result :ok))
      (should (= (plist-get result :exit-code) 0))
      (should (equal (string-trim (plist-get result :stdout)) "ok")))))

(ert-deftest org-ai-skills-core-provider-org-babel-exec-emacs-lisp ()
  "Provider Org Babel exec should evaluate emacs-lisp block body."
  (let ((org-ai-skills-core-provider-allowed-paths (list default-directory))
        (org-ai-skills-core-provider-allowed-commands '(org-babel-exec)))
    (let ((result (org-ai-skills-core-provider-org-babel-exec
                   "emacs-lisp"
                   "(+ 2 3)"
                   default-directory)))
      (should (plist-get result :ok))
      (should (equal (string-trim (plist-get result :result)) "5")))))

(ert-deftest org-ai-skills-core-provider-dispatch-routes-command ()
  "Provider dispatch should route by registry command type."
  (let ((result (org-ai-skills-core-provider-dispatch 'file-list default-directory 5)))
    (should (plist-member result :command-type))
    (should (eq (plist-get result :command-type) 'file-list))))

(ert-deftest org-ai-skills-resolve-working-directory-prefers-purpose-path ()
  "Working directory resolver should use existing path extracted from PURPOSE."
  (let ((subtree (list :purpose "帮我研究一下 ~/Workspace/org-ai-skills-015/ 的项目结构"
                       :source-file-path "/tmp/unknown-file.org")))
    (should (equal (org-ai-skills--resolve-working-directory subtree)
                   (expand-file-name "~/Workspace/org-ai-skills-015/")))))

(ert-deftest org-ai-skills-core-provider-shell-exec-uses-context-directory-by-default ()
  "Provider shell command should use request context directory when DIRECTORY is omitted."
  (let* ((dir (make-temp-file "org-ai-skills-context-dir-" t))
         (org-ai-skills-core-provider-allowed-paths nil)
         (org-ai-skills--core-provider-context-directory dir)
         (org-ai-skills-core-provider-allowed-commands '(shell-exec)))
    (unwind-protect
        (let ((result (org-ai-skills-core-provider-shell-exec "pwd")))
          (should (plist-get result :ok))
          (should (string= (string-trim (plist-get result :stdout))
                           (directory-file-name dir))))
      (delete-directory dir t))))

(ert-deftest org-ai-skills-resolve-subtree-from-slot-prefers-slot-id-over-markers ()
  "Target resolution should locate subtree by slot ID even if markers drift."
  (with-temp-buffer
    (org-mode)
    (insert "* A\nBody A\n* B\nBody B\n")
    (goto-char (point-min))
    (let* ((subtree-a (org-ai-skills-org-resolve-subtree 'current))
           (slot-a (org-ai-skills--ensure-subtree-slot-id subtree-a)))
      ;; Move to B and craft stale markers that point to B by mistake.
      (re-search-forward "^\\* B$")
      (let ((slot-stale (append slot-a
                                (list :begin (copy-marker (line-beginning-position))
                                      :end (copy-marker (point-max))))))
        (let ((resolved (org-ai-skills--resolve-subtree-from-slot slot-stale (current-buffer))))
          (should (equal (plist-get resolved :heading) "A"))
          (should (string-match-p "^\\* A" (plist-get resolved :text))))))))

(ert-deftest org-ai-skills-apply-candidate-uses-slot-id-to-avoid-wrong-subtree ()
  "Auto-apply path should use slot-ID target resolution to avoid drift."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-auto-apply-generated-candidate t))
          (with-temp-buffer
            (org-mode)
            (insert "* A\nBody A\n* B\nBody B\n")
            (goto-char (point-min))
            (let* ((subtree-a (org-ai-skills-org-resolve-subtree 'current))
                   (slot-a (org-ai-skills--ensure-subtree-slot-id subtree-a)))
              ;; Pass stale markers that point to B; slot-id should still resolve to A.
              (re-search-forward "^\\* B$")
              (let ((drifted (append slot-a
                                     (list :begin (copy-marker (line-beginning-position))
                                           :end (copy-marker (point-max))))))
                (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
                           (lambda (_request callback)
                             (funcall callback "*** A\nNew A\n"))))
                  (org-ai-skills-org-rewrite-subtree drifted skill "Rewrite A"))
                (goto-char (point-min))
                (re-search-forward "^\\* A$")
                (re-search-forward "New A" nil t)
                (re-search-forward "^\\* B$")
                (forward-line 1)
                (should (looking-at-p "Body B"))))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-core-provider-integration-explore-and-experiment ()
  "Integration flow: explore project files, locate function, run experiments."
  (let* ((dir (make-temp-file "org-ai-skills-core-provider-int-" t))
         (py-file (expand-file-name "sample.py" dir)))
    (unwind-protect
        (progn
          (with-temp-file py-file
            (insert "def add_numbers(a, b):\n    return a + b\n"))
          (let ((org-ai-skills-core-provider-allowed-paths (list dir))
                (org-ai-skills-core-provider-allowed-commands
                 '(file-list file-search python-exec org-babel-exec)))
            (let* ((listed (org-ai-skills-core-provider-list-files dir 20))
                   (searched (org-ai-skills-core-provider-search-files "def add_numbers" dir 20))
                   (python-run
                    (org-ai-skills-core-provider-python-exec
                     "import sample; print(sample.add_numbers(2, 3))"
                     dir))
                   (org-run
                    (org-ai-skills-core-provider-org-babel-exec
                     "emacs-lisp"
                     "(format \"* Experiment Report\\n- function: add_numbers\\n- status: %s\" \"ok\")"
                     dir)))
              (should (plist-get listed :ok))
              (should (member "sample.py" (plist-get listed :entries)))
              (should (plist-get searched :ok))
              (should (= (plist-get searched :match-count) 1))
              (should (plist-get python-run :ok))
              (should (equal (string-trim (plist-get python-run :stdout)) "5"))
              (should (plist-get org-run :ok))
              (should (string-match-p "\\* Experiment Report"
                                      (plist-get org-run :result))))))
      (delete-directory dir t))))

(ert-deftest org-ai-skills-read-file-respects-max-chars ()
  "File read helper should truncate content by max char budget."
  (let ((file (make-temp-file "org-ai-skills-read-file-")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "abcdef"))
          (should (equal (org-ai-skills-read-file file 3) "abc"))
          (should (equal (org-ai-skills-read-file file "4") "abcd")))
      (delete-file file))))

(ert-deftest org-ai-skills-read-file-supports-relative-source-path ()
  "File read helper should resolve project-relative source paths."
  (let* ((dir (make-temp-file "org-ai-skills-source-rel-" t))
         (file (expand-file-name "source.md" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "relative source content"))
          (let ((default-directory dir))
            (should (equal (org-ai-skills-read-file "./source.md")
                           "relative source content"))))
      (delete-directory dir t))))

(ert-deftest org-ai-skills-read-buffer-supports-range-and-buffer-name ()
  "Buffer read helper should support named buffer and start/end slicing."
  (let ((buf (generate-new-buffer "*org-ai-skills-read-buffer*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "0123456789")
          (should (equal (org-ai-skills-read-buffer (buffer-name buf) 3 7)
                         "2345")))
      (kill-buffer buf))))

(ert-deftest org-ai-skills-function-calls-available-only-when-skill-applied ()
  "Function calls should be available only while skill is active."
  (let* ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--financial-skill-file))
         (subtree '(:heading "Leaf"
                    :level 3
                    :path "Top/Child/Leaf"
                    :text "*** Leaf\nBody\n"
                    :context-mode current
                    :levels-up 0)))
    (unwind-protect
        (progn
          (org-ai-skills-clear-active-skill-functions)
          (let ((request (org-ai-skills-build-gptel-rewrite-request skill subtree)))
            (should-not (string-match-p "Possible function calls"
                                        (plist-get request :prompt))))
          (org-ai-skills-apply-skill-function-calls skill)
          (let ((request (org-ai-skills-build-gptel-rewrite-request skill subtree)))
            (should (string-match-p
                     "org-ai-skills-search1api-fetch-financial-news-raw"
                     (plist-get request :prompt))))
          (org-ai-skills-exclude-skill-function-calls skill)
          (let ((request (org-ai-skills-build-gptel-rewrite-request skill subtree)))
            (should-not (string-match-p "Possible function calls"
                                        (plist-get request :prompt)))))
      (org-ai-skills-clear-active-skill-functions))))

(ert-deftest org-ai-skills-apply-skill-functions-fails-for-missing-elisp-function ()
  "Applying a skill should fail when declared function is not defined."
  (let ((skill '(:skill-id "bad-fn-skill"
                :function-calls ((:name "org-ai-skills-missing-function")))))
    (org-ai-skills-clear-active-skill-functions)
    (should-error (org-ai-skills-apply-skill-function-calls skill)
                  :type 'org-ai-skills-function-call-error)
    (should-not (org-ai-skills-active-skill-function-calls "bad-fn-skill"))))

(ert-deftest org-ai-skills-skill-local-search1api-function-definitions-load-and-unload ()
  "Skill-local function definitions should load on apply and unload on exclude."
  (let ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--financial-skill-file)))
    (unwind-protect
        (progn
          (org-ai-skills-clear-active-skill-functions)
          (cl-letf (((symbol-function 'auth-source-pick-first-password)
                     (lambda (&rest _args) "test-key"))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (&rest _args)
                       (with-current-buffer (generate-new-buffer " *org-ai-skills-search1api*")
                         (insert "HTTP/1.1 200 OK\r\n")
                         (insert "Content-Type: application/json\r\n\r\n")
                         (insert "{\"results\":[{\"title\":\"Stocks Rally\",\"url\":\"https://example.com/a\",\"snippet\":\"Equities advanced today.\"}]}")
                         (current-buffer)))))
            (org-ai-skills-apply-skill-function-calls skill)
            (should (fboundp 'org-ai-skills-search1api-fetch-financial-news-raw))
            (let* ((raw (org-ai-skills-search1api-fetch-financial-news-raw
                         "market" 5 "en" "2026-02-18"))
                   (payload (json-parse-string raw
                                               :object-type 'plist
                                               :array-type 'list
                                               :null-object nil
                                               :false-object nil)))
              (should (string= (plist-get payload :date) "2026-02-18"))
              (should (string= (plist-get payload :query) "market"))
              (should (equal (plist-get payload :count) 1))))
          (org-ai-skills-exclude-skill-function-calls skill)
          (should-not (fboundp 'org-ai-skills-search1api-fetch-financial-news-raw)))
      (org-ai-skills-clear-active-skill-functions))))

(ert-deftest org-ai-skills-skill-local-search1api-raw-output-is-multibyte-json ()
  "Raw Search1API tool output should be multibyte JSON text for gptel tool flow."
  (let ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--financial-skill-file)))
    (unwind-protect
        (progn
          (org-ai-skills-clear-active-skill-functions)
          (cl-letf (((symbol-function 'auth-source-pick-first-password)
                     (lambda (&rest _args) "test-key"))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (&rest _args)
                       (with-current-buffer (generate-new-buffer " *org-ai-skills-search1api*")
                         (insert "HTTP/1.1 200 OK\r\n")
                         (insert "Content-Type: application/json\r\n\r\n")
                         (insert "{\"results\":[{\"title\":\"标题\",\"url\":\"https://example.com/a\",\"snippet\":\"摘要\"}]}")
                         (current-buffer)))))
            (org-ai-skills-apply-skill-function-calls skill)
            (let ((raw (org-ai-skills-search1api-fetch-financial-news-raw
                        "今天的金融新闻日报" 5 "zh" "2026-02-19")))
              (should (multibyte-string-p raw))
              (let ((payload (json-parse-string raw
                                                :object-type 'plist
                                                :array-type 'list
                                                :null-object nil
                                                :false-object nil)))
                (should (equal (plist-get payload :language_hint) "zh"))
                (should (equal (plist-get payload :count) 1))))))
      (org-ai-skills-exclude-skill-function-calls skill)
      (org-ai-skills-clear-active-skill-functions))))

(ert-deftest org-ai-skills-skill-local-search1api-request-data-is-unibyte ()
  "Skill-local Search1API request body should be UTF-8 encoded unibyte string."
  (let ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--financial-skill-file)))
    (unwind-protect
        (progn
          (org-ai-skills-clear-active-skill-functions)
          (cl-letf (((symbol-function 'auth-source-pick-first-password)
                     (lambda (&rest _args) "test-key"))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (url &rest _args)
                       (unless (string= url "https://api.search1api.com/news")
                         (error "unexpected endpoint: %s" url))
                       (when (multibyte-string-p url-request-data)
                         (error "request-data must be unibyte"))
                       (with-current-buffer (generate-new-buffer " *org-ai-skills-search1api*")
                         (insert "HTTP/1.1 200 OK\r\n")
                         (insert "Content-Type: application/json\r\n\r\n")
                         (insert "{\"results\":[]}")
                         (current-buffer)))))
            (org-ai-skills-apply-skill-function-calls skill)
            (should (equal (org-ai-skills-search1api-fetch-financial-news
                            "生成今天的金融新闻日报"
                            5)
                           nil))))
      (org-ai-skills-exclude-skill-function-calls skill)
      (org-ai-skills-clear-active-skill-functions))))

(ert-deftest org-ai-skills-skill-local-search1api-raw-keyword-args-parse-limit ()
  "Raw tool function should accept keyword args and parse string limit."
  (let ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--financial-skill-file)))
    (unwind-protect
        (progn
          (org-ai-skills-clear-active-skill-functions)
          (cl-letf (((symbol-function 'auth-source-pick-first-password)
                     (lambda (&rest _args) "test-key"))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (_url &rest _args)
                       (let ((payload (json-parse-string
                                       (decode-coding-string url-request-data 'utf-8)
                                       :object-type 'plist
                                       :array-type 'list
                                       :null-object nil
                                       :false-object nil)))
                         (should (= (plist-get payload :max_results) 100)))
                       (with-current-buffer (generate-new-buffer " *org-ai-skills-search1api*")
                         (insert "HTTP/1.1 200 OK\r\n")
                         (insert "Content-Type: application/json\r\n\r\n")
                         (insert "{\"results\":[{\"title\":\"A\",\"url\":\"https://example.com/a\",\"snippet\":\"S\"}]}")
                         (current-buffer)))))
            (org-ai-skills-apply-skill-function-calls skill)
            (let* ((raw (org-ai-skills-search1api-fetch-financial-news-raw
                         :limit "100"
                         :date "2026-02-19"
                         :language_hint "zh"))
                   (result (json-parse-string raw
                                              :object-type 'plist
                                              :array-type 'list
                                              :null-object nil
                                              :false-object nil)))
              (should (string= (plist-get result :date) "2026-02-19"))
              (should (string= (plist-get result :language_hint) "zh"))
              (should (= (plist-get result :count) 1)))))
      (org-ai-skills-exclude-skill-function-calls skill)
      (org-ai-skills-clear-active-skill-functions))))

(ert-deftest org-ai-skills-skill-local-search1api-errors-when-url-returns-nil ()
  "Search1API fetch should signal explicit error when URL backend returns nil."
  (let ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--financial-skill-file)))
    (unwind-protect
        (progn
          (org-ai-skills-clear-active-skill-functions)
          (cl-letf (((symbol-function 'auth-source-pick-first-password)
                     (lambda (&rest _args) "test-key"))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (&rest _args) nil)))
            (org-ai-skills-apply-skill-function-calls skill)
            (should-error
             (org-ai-skills-search1api-fetch-financial-news-raw
              :date "2026-02-19")
             :type 'org-ai-skills-function-call-error)))
      (org-ai-skills-exclude-skill-function-calls skill)
      (org-ai-skills-clear-active-skill-functions))))

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

(ert-deftest org-ai-skills-debug-disabled-does-not-write-buffer ()
  "Dispatch should not write debug entries when disabled."
  (let ((org-ai-skills-debug-enabled nil)
        (org-ai-skills-debug-buffer-name "*org-ai-skills-debug-test*")
        (org-ai-skills--last-debug-entry nil)
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (when (get-buffer org-ai-skills-debug-buffer-name)
      (kill-buffer org-ai-skills-debug-buffer-name))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel) t (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request) t (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest _args) t)))
      (org-ai-skills-gptel-dispatch-rewrite
       '(:prompt "hello" :skill-context (:source-subtree (:headline "H")))
       #'ignore))
    (should-not org-ai-skills--last-debug-entry)
    (should-not (get-buffer org-ai-skills-debug-buffer-name))))

(ert-deftest org-ai-skills-debug-enabled-writes-dispatch-entry ()
  "Dispatch should append debug entry when enabled."
  (let ((org-ai-skills-debug-enabled t)
        (org-ai-skills-debug-buffer-name "*org-ai-skills-debug-test*")
        (org-ai-skills--debug-events nil)
        (org-ai-skills--last-debug-entry nil)
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (when (get-buffer org-ai-skills-debug-buffer-name)
      (kill-buffer org-ai-skills-debug-buffer-name))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel) t (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request) t (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest _args) t)))
      (org-ai-skills-gptel-dispatch-rewrite
       '(:prompt "hello"
         :context-mode current
         :levels-up 0
         :buffer-name "buf"
         :buffer-file "/tmp/file.org"
         :skill-context (:source-subtree (:headline "Leaf" :path "Top/Leaf")))
       #'ignore))
    (should (stringp org-ai-skills--last-debug-entry))
    (should (string-match-p "Prompt:" org-ai-skills--last-debug-entry))
    (should (string-match-p "Leaf" org-ai-skills--last-debug-entry))
    (with-current-buffer org-ai-skills-debug-buffer-name
      (should (string-match-p "Request:" (buffer-string))))
    (kill-buffer org-ai-skills-debug-buffer-name)))

(ert-deftest org-ai-skills-debug-filter-events-by-level ()
  "Debug filter should support exact level matching."
  (let ((org-ai-skills-debug-enabled t)
        (org-ai-skills--debug-events nil)
        (org-ai-skills-debug-buffer-name "*org-ai-skills-debug-test*"))
    (when (get-buffer org-ai-skills-debug-buffer-name)
      (kill-buffer org-ai-skills-debug-buffer-name))
    (org-ai-skills--append-debug-entry
     '(:event-type rewrite :step-id "s1" :prompt "rewrite"))
    (org-ai-skills--append-debug-entry
     '(:event-type tool-call :step-id "s1" :prompt "tool"))
    (org-ai-skills--append-debug-entry
     '(:event-type callback-error :step-id "s2" :prompt "error"))
    (let ((error-events (org-ai-skills-debug-filter-events 'error nil))
          (debug-events (org-ai-skills-debug-filter-events 'debug nil))
          (all-events (org-ai-skills-debug-filter-events nil nil)))
      (should (= (length all-events) 3))
      (should (= (length error-events) 1))
      (should (= (length debug-events) 1))
      (should (eq (plist-get (car error-events) :event-type) 'callback-error))
      (should (eq (plist-get (car debug-events) :event-type) 'tool-call)))
    (kill-buffer org-ai-skills-debug-buffer-name)))

(ert-deftest org-ai-skills-debug-filter-events-by-step-or-stage ()
  "Debug filter should match by step-id and stage-id."
  (let ((org-ai-skills-debug-enabled t)
        (org-ai-skills--debug-events nil)
        (org-ai-skills-debug-buffer-name "*org-ai-skills-debug-test*"))
    (when (get-buffer org-ai-skills-debug-buffer-name)
      (kill-buffer org-ai-skills-debug-buffer-name))
    (org-ai-skills--append-debug-entry
     '(:event-type step-execution :step-id "s1" :log-level info :prompt "step 1"))
    (org-ai-skills--append-debug-entry
     '(:event-type planner :stage-id "planning" :log-level info :prompt "plan"))
    (org-ai-skills--append-debug-entry
     '(:event-type step-execution :step-id "s2" :log-level warn :prompt "step 2"))
    (let ((s1-events (org-ai-skills-debug-filter-events nil "s1"))
          (planning-events (org-ai-skills-debug-filter-events nil "planning"))
          (warn-s2-events (org-ai-skills-debug-filter-events 'warn "s2")))
      (should (= (length s1-events) 1))
      (should (= (length planning-events) 1))
      (should (= (length warn-s2-events) 1))
      (should (eq (plist-get (car planning-events) :event-type) 'planner)))
    (kill-buffer org-ai-skills-debug-buffer-name)))

(ert-deftest org-ai-skills-org-context-candidates-show-path-preview ()
  "Rewrite target candidates should include buffer/current/ancestor previews."
  (with-temp-buffer
    (org-mode)
    (insert "* Top\n** Child\n*** Leaf\nLeaf body.\n")
    (search-backward "Leaf body.")
    (let ((candidates (org-ai-skills-org-collect-context-candidates)))
      (should (= (length candidates) 4))
      (should (string-match-p "\\[buffer\\]"
                              (car (nth 0 candidates))))
      (should (string-match-p "\\[current\\] Top/Child/Leaf"
                              (car (nth 1 candidates))))
      (should (string-match-p "\\[up:1\\] Top/Child"
                              (car (nth 2 candidates))))
      (should (eq (plist-get (cdr (nth 0 candidates)) :context-mode) 'buffer))
      (should (equal (plist-get (cdr (nth 1 candidates)) :heading) "Leaf"))
      (should (equal (plist-get (cdr (nth 2 candidates)) :heading) "Child")))))

(ert-deftest org-ai-skills-org-read-rewrite-target-uses-selected-preview ()
  "Selected preview candidate should resolve to expected target subtree."
  (with-temp-buffer
    (org-mode)
    (insert "* Top\n** Child\n*** Leaf\nLeaf body.\n")
    (search-backward "Leaf body.")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt collection &rest _rest)
                 (nth 2 collection))))
      (let ((target (org-ai-skills-org-read-rewrite-target)))
        (should (equal (plist-get target :heading) "Child"))
        (should (eq (plist-get target :context-mode) 'upper-level))
        (should (= (plist-get target :levels-up) 1))))))

(ert-deftest org-ai-skills-org-collect-context-candidates-allows-buffer-without-heading ()
  "Scope picker should still provide buffer target before first heading."
  (with-temp-buffer
    (org-mode)
    (insert "Title only\nNo headings yet.\n")
    (goto-char (point-min))
    (let ((candidates (org-ai-skills-org-collect-context-candidates)))
      (should (= (length candidates) 1))
      (should (eq (plist-get (cdar candidates) :context-mode) 'buffer)))))

(ert-deftest org-ai-skills-org-collect-context-candidates-buffer-uses-file-keywords ()
  "Buffer scope candidate should include file-level PURPOSE and SOURCE_FILE_PATH."
  (with-temp-buffer
    (org-mode)
    (insert "#+PURPOSE: Whole-file purpose\n#+SOURCE_FILE_PATH: ./notes/file.md\n\nPlain text.\n")
    (goto-char (point-min))
    (let* ((candidates (org-ai-skills-org-collect-context-candidates))
           (buffer-scope (cdar candidates)))
      (should (eq (plist-get buffer-scope :context-mode) 'buffer))
      (should (equal (plist-get buffer-scope :purpose) "Whole-file purpose"))
      (should (equal (plist-get buffer-scope :source-file-path) "./notes/file.md")))))

(ert-deftest org-ai-skills-org-collect-context-candidates-buffer-does-not-guess-source-file-path ()
  "Buffer scope should not infer SOURCE_FILE_PATH from current Org file."
  (with-temp-buffer
    (org-mode)
    (let ((buffer-file-name "/tmp/current-note.org"))
      (insert "Plain text.\n")
      (goto-char (point-min))
      (let* ((candidates (org-ai-skills-org-collect-context-candidates))
             (buffer-scope (cdar candidates)))
        (should (eq (plist-get buffer-scope :context-mode) 'buffer))
        (should-not (plist-get buffer-scope :source-file-path))))))

(ert-deftest org-ai-skills-sanitize-rewrite-output-fixes-level-and-preface ()
  "Sanitizer should remove explanation preface and enforce target level."
  (let* ((subtree '(:level 2 :heading "Child"))
         (raw "Here is the rewrite:\n*** Child Revised\n**** Sub\nBody\n")
         (cleaned (org-ai-skills--sanitize-rewrite-output raw subtree)))
    (should-not (string-match-p "Here is the rewrite" cleaned))
    (should (string-prefix-p "** Child" cleaned))
    (should (string-match-p "^\\*\\*\\* Sub$" cleaned))))

(ert-deftest org-ai-skills-sanitize-rewrite-output-restores-root-heading ()
  "Sanitizer should force root heading text back to target heading."
  (let* ((subtree '(:level 2 :heading "Draft From Outline"))
         (raw "** Renamed Heading\nBody paragraph.\n")
         (cleaned (org-ai-skills--sanitize-rewrite-output raw subtree)))
    (should (string-prefix-p "** Draft From Outline" cleaned))
    (should-not (string-match-p "^\\*\\* Renamed Heading$" cleaned))))

(ert-deftest org-ai-skills-strip-property-drawers-from-text-removes-drawers ()
  "Property drawer stripping helper should remove all drawer blocks."
  (let* ((raw "* H\n:PROPERTIES:\n:K: V\n:END:\nBody\n")
         (cleaned (org-ai-skills--strip-property-drawers-from-text raw)))
    (should-not (string-match-p ":PROPERTIES:" cleaned))
    (should (string-match-p "^\\* H$" cleaned))
    (should (string-match-p "Body" cleaned))))

(ert-deftest org-ai-skills-strip-indented-property-drawers-only-removes-indented ()
  "Indented pseudo drawers should be removed while canonical drawers remain."
  (let* ((raw "* H\n:PROPERTIES:\n:ID: keep\n:END:\n\n  :PROPERTIES:\n  :PURPOSE: bad\n  :END:\n")
         (cleaned (org-ai-skills--strip-indented-property-drawers-from-text raw)))
    (should (string-match-p "^:PROPERTIES:$" cleaned))
    (should-not (string-match-p "^  :PROPERTIES:$" cleaned))))

(ert-deftest org-ai-skills-enforce-rewrite-constraints-rejects-heading-change ()
  "Strict constraints should reject rewritten content with heading changes."
  (let ((subtree '(:context-mode current
                   :text "* Root\n** A\nText\n** B\nText\n")))
    (should-error
     (org-ai-skills--enforce-rewrite-constraints
      "* Root\n** A-Changed\nText\n** B\nText\n"
      subtree
      '(:preserve-headlines t))
     :type 'org-ai-skills-org-context-error)))

(ert-deftest org-ai-skills-rewrite-subtree-strict-builds-guarded-request ()
  "Strict rewrite command should forward heading-lock/drawer constraints."
  (let ((captured nil))
    (cl-letf (((symbol-function 'org-ai-skills-org-rewrite-subtree)
               (lambda (target skill instruction interactive-origin constraints)
                 (setq captured (list target skill instruction interactive-origin constraints)))))
      (org-ai-skills-org-rewrite-subtree-strict
       '(:begin 1 :end 2 :context-mode current)
       '(:skill-id "x")
       "Focus tone"
       t))
    (should (plist-get (nth 4 captured) :preserve-headlines))
    (should (plist-get (nth 4 captured) :omit-property-drawers))
    (should (string-match-p "Strict constraints:" (nth 2 captured)))
    (should (string-match-p "Focus tone" (nth 2 captured)))))

(ert-deftest org-ai-skills-ensure-subtree-slot-id-writes-id-property ()
  "Slot identity helper should auto-generate and write back :ID:."
  (with-temp-buffer
    (org-mode)
    (insert "* Slot\nBody\n")
    (goto-char (point-min))
    (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
           (slot (org-ai-skills--ensure-subtree-slot-id subtree)))
      (should (stringp (plist-get slot :slot-id)))
      (goto-char (point-min))
      (should (string= (org-entry-get (point) "ID")
                       (plist-get slot :slot-id))))))

(ert-deftest org-ai-skills-ensure-subtree-slot-id-uses-stable-buffer-slot-for-buffer-scope ()
  "Buffer-scope target should use stable slot id without Org heading mutation."
  (with-temp-buffer
    (org-mode)
    (insert "#+TITLE: Draft\nBody\n")
    (let* ((slot (org-ai-skills--ensure-subtree-slot-id
                  (list :begin (point-min)
                        :end (point-max)
                        :context-mode 'buffer))))
      (should (equal (plist-get slot :slot-id) "buffer-root"))
      (should (string-match-p "|buffer-root$" (plist-get slot :slot-key))))))

(ert-deftest org-ai-skills-ensure-subtree-slot-id-prefers-marker-buffer-over-current-buffer ()
  "Slot id/file should be derived from target marker buffer, not control buffer."
  (let ((source (generate-new-buffer " *org-ai-source*"))
        (control (generate-new-buffer " *org-ai-control*")))
    (unwind-protect
        (with-current-buffer source
          (org-mode)
          (insert "* Root\n** Leaf\nBody\n")
          (goto-char (point-min))
          (re-search-forward "^\\*\\* Leaf$")
          (beginning-of-line)
          (let* ((begin (copy-marker (point)))
                 (end (save-excursion
                        (org-end-of-subtree t t)
                        (copy-marker (point))))
                 (subtree (list :begin begin
                                :end end
                                :context-mode 'current))
                 slot)
            (with-current-buffer control
              (setq slot (org-ai-skills--ensure-subtree-slot-id subtree)))
            (should (string-match-p
                     "buffer: \\*org-ai-source\\*\\|buffer:\\*org-ai-source\\*"
                     (plist-get slot :slot-file)))))
      (when (buffer-live-p source)
        (kill-buffer source))
      (when (buffer-live-p control)
        (kill-buffer control)))))

(ert-deftest org-ai-skills-org-apply-rewrite-result-buffer-scope-preserves-front-matter ()
  "Buffer scope apply should keep existing file front matter and replace body."
  (with-temp-buffer
    (org-mode)
    (insert "#+TITLE: Old\n#+FILETAGS: :blog:\n#+PURPOSE: Draft\n\n* A\nOld body.\n")
    (org-ai-skills-org-apply-rewrite-result
     (list :begin (point-min)
           :end (point-max)
           :context-mode 'buffer)
     "#+TITLE: New\n#+FILETAGS: :new:\n\n* A\nNew body.\n")
    (should (string= (buffer-string)
                     "#+TITLE: Old\n#+FILETAGS: :blog:\n#+PURPOSE: Draft\n\n* A\nNew body.\n"))))

(ert-deftest org-ai-skills-org-apply-rewrite-result-buffer-scope-replaces-when-no-front-matter ()
  "Buffer scope apply should fully replace content when no front matter exists."
  (with-temp-buffer
    (org-mode)
    (insert "* A\nOld body.\n")
    (org-ai-skills-org-apply-rewrite-result
     (list :begin (point-min)
           :end (point-max)
           :context-mode 'buffer)
     "* A\nNew body.\n")
    (should (string= (buffer-string) "* A\nNew body.\n"))))

(ert-deftest org-ai-skills-org-apply-rewrite-result-buffer-scope-preserves-subheading-properties ()
  "Buffer scope apply should retain PURPOSE/SOURCE_FILE_PATH on nested headings."
  (with-temp-buffer
    (org-mode)
    (insert "#+TITLE: Draft\n#+PURPOSE: File purpose\n\n"
            "* Root\n"
            ":PROPERTIES:\n"
            ":PURPOSE: Root purpose\n"
            ":END:\n"
            "** A\n"
            ":PROPERTIES:\n"
            ":PURPOSE: A purpose\n"
            ":END:\n"
            "** B\n"
            ":PROPERTIES:\n"
            ":PURPOSE: B purpose\n"
            ":SOURCE_FILE_PATH: /tmp/b.md\n"
            ":END:\n")
    (org-ai-skills-org-apply-rewrite-result
     (list :begin (point-min)
           :end (point-max)
           :context-mode 'buffer)
     "#+TITLE: Draft 2\n\n* Root Changed\n** A changed\nBody A\n** B changed\nBody B\n")
    (goto-char (point-min))
    (re-search-forward "^\\*\\* A changed$")
    (should (string= (org-entry-get (point) "PURPOSE" nil) "A purpose"))
    (re-search-forward "^\\*\\* B changed$")
    (should (string= (org-entry-get (point) "PURPOSE" nil) "B purpose"))
    (should (string= (org-entry-get (point) "SOURCE_FILE_PATH" nil) "/tmp/b.md"))))

(ert-deftest org-ai-skills-ui-apply-selected-candidate-preserves-buffer-context-mode ()
  "UI apply should forward buffer context to avoid heading-only apply path."
  (let ((applied-subtree nil))
    (cl-letf (((symbol-function 'org-ai-skills-org-apply-candidate-to-subtree)
               (lambda (subtree _candidate)
                 (setq applied-subtree subtree)))
              ((symbol-function 'org-ai-skills-ui-select-candidate)
               (lambda ()
                 '(:slot-key "k" :candidate-id "c1" :output-text "x")))
              ((symbol-function 'org-ai-skills--ui-clear-overlay)
               (lambda () nil))
              ((symbol-function 'org-ai-skills--ui-set-status)
               (lambda (_status _progress) nil)))
      (let ((org-ai-skills--ui-run-state
             (list :status 'ready
                   :source-buffer (current-buffer)
                   :begin 1
                   :end 10
                   :context-mode 'buffer
                   :selected-candidate nil)))
        (org-ai-skills-ui-apply-selected-candidate)))
    (should (eq (plist-get applied-subtree :context-mode) 'buffer))))

(ert-deftest org-ai-skills-ui-apply-selected-candidate-runs-in-source-buffer ()
  "Control-panel apply should update source buffer rather than control buffer."
  (with-temp-buffer
    (org-mode)
    (insert "#+TITLE: Draft\nOld\n")
    (let ((source-buffer (current-buffer))
          (begin (copy-marker (point-min)))
          (end (copy-marker (point-max)))
          (org-ai-skills--ui-run-state nil))
      (with-temp-buffer
        (setq org-ai-skills--ui-run-state
              (list :status 'ready
                    :begin begin
                    :end end
                    :context-mode 'buffer
                    :source-buffer source-buffer
                    :selected-candidate
                    '(:slot-key "k" :candidate-id "c1" :output-text "#+TITLE: Draft\nNew\n")))
        (cl-letf (((symbol-function 'org-ai-skills--ui-clear-overlay)
                   (lambda () nil))
                  ((symbol-function 'org-ai-skills--ui-set-status)
                   (lambda (_status _progress) nil))
                  ((symbol-function 'org-ai-skills--update-candidate-status)
                   (lambda (_slot-key _candidate-id _status) nil)))
          (org-ai-skills-ui-apply-selected-candidate)))
      (with-current-buffer source-buffer
        (should (string= (buffer-string) "#+TITLE: Draft\n\nNew\n"))))))

(ert-deftest org-ai-skills-ui-apply-selected-candidate-errors-when-slot-key-missing ()
  "Apply should signal actionable error when run state has no slot key."
  (let ((org-ai-skills--ui-run-state
         (list :status 'ready
               :source-buffer (current-buffer)
               :begin 1
               :end 1
               :context-mode 'buffer
               :selected-candidate nil
               :slot-key nil)))
    (should-error (org-ai-skills-ui-apply-selected-candidate)
                  :type 'org-ai-skills-version-store-error)))

(ert-deftest org-ai-skills-ui-current-target-reconstructs-from-ui-state ()
  "When stored target is absent, UI should reconstruct scope from run state."
  (let* ((org-ai-skills--ui-run-state
          (list :target nil
                :begin 1
                :end 10
                :context-mode 'buffer
                :heading "Demo"))
         (target (org-ai-skills--ui-current-target)))
    (should (equal (plist-get target :begin) 1))
    (should (equal (plist-get target :end) 10))
    (should (eq (plist-get target :context-mode) 'buffer))
    (should (equal (plist-get target :heading) "Demo"))))

(ert-deftest org-ai-skills-ui-current-target-infers-buffer-from-slot-id ()
  "UI target reconstruction should infer buffer context from slot id."
  (with-temp-buffer
    (org-mode)
    (insert "#+TITLE: Draft\nBody\n")
    (let* ((org-ai-skills--ui-run-state
            (list :target nil
                  :begin (copy-marker (point-min))
                  :end (copy-marker (point-max))
                  :context-mode nil
                  :slot-id "buffer-root"
                  :heading "Draft"))
           (target (org-ai-skills--ui-current-target)))
      (should (eq (plist-get target :context-mode) 'buffer)))))

(ert-deftest org-ai-skills-plan-run-buffer-scope-auto-apply-preserves-context-mode ()
  "Planner auto-apply should keep buffer context mode in apply path."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (applied-subtree nil))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-auto-apply-generated-candidate t))
          (with-temp-buffer
            (org-mode)
            (insert "#+TITLE: Draft\nBody\n")
            (let ((target (list :begin (point-min)
                                :end (point-max)
                                :context-mode 'buffer
                                :heading (buffer-name)
                                :path (buffer-name)
                                :text (buffer-string))))
              (cl-letf (((symbol-function 'org-ai-skills-run-task-with-planner)
                         (lambda (_task _slot _options callback)
                           (funcall callback '(:final-output "#+TITLE: Draft\nUpdated\n"))))
                        ((symbol-function 'org-ai-skills-org-apply-candidate-to-subtree)
                         (lambda (subtree _candidate)
                           (setq applied-subtree subtree))))
                (org-ai-skills-plan-run target "outline" t nil))))
          (should (eq (plist-get applied-subtree :context-mode) 'buffer)))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-plan-run-does-not-message-fatal-for-stale-run ()
  "Planner callback should not emit fatal message when run id is stale."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (message-count 0))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-auto-apply-generated-candidate t))
          (with-temp-buffer
            (org-mode)
            (insert "* Root\nBody\n")
            (let ((target (list :begin (point-min)
                                :end (point-max)
                                :context-mode 'current
                                :heading "Root"
                                :path "Root"
                                :text (buffer-string)
                                :slot-key "k"
                                :slot-id "id")))
              (cl-letf (((symbol-function 'org-ai-skills--candidate-id)
                         (lambda () "new-run-id"))
                        ((symbol-function 'org-ai-skills-run-task-with-planner)
                         (lambda (_task _slot _options callback)
                           (funcall callback '(:fatal-error "Planner integration error: stale run"))))
                        ((symbol-function 'org-ai-skills--ui-stop-requested-p)
                         (lambda (_run-id) nil))
                        ((symbol-function 'org-ai-skills--ui-run-get)
                         (lambda (key)
                           (pcase key
                             (:run-id "old-run-id")
                             (_ nil))))
                        ((symbol-function 'message)
                         (lambda (&rest _args)
                           (setq message-count (1+ message-count)))))
                (org-ai-skills-plan-run target "task" t nil)))))
      (delete-directory store-dir t))
    (should (= message-count 0))))

(ert-deftest org-ai-skills-planner-constraints-follow-last-step-skill ()
  "Planner constraints should be derived from final completed step only."
  (should (equal (org-ai-skills--planner-constraints-for-run-state
                  '(:steps ((:skills ("gen-notes"))
                            (:skills ("article-compose-from-outline")))))
                 '(:preserve-headlines t :omit-property-drawers t)))
  (should-not (org-ai-skills--planner-constraints-for-run-state
               '(:steps ((:skills ("article-compose-from-outline"))
                         (:skills ("article-polish-editorial")))))))

(ert-deftest org-ai-skills-org-apply-rewrite-result-subtree-scope-keeps-siblings ()
  "Subtree apply should not modify sibling subtree content."
  (with-temp-buffer
    (org-mode)
    (insert "* Root\n** A\nOld A.\n** B\nKeep B.\n")
    (goto-char (point-min))
    (re-search-forward "^\\*\\* A$")
    (let ((target (org-ai-skills-org-resolve-subtree 'current)))
      (org-ai-skills-org-apply-rewrite-result target "** A\nNew A.\n"))
    (goto-char (point-min))
    (should (re-search-forward "New A\\." nil t))
    (should (re-search-forward "^\\*\\* B\nKeep B\\.$" nil t))))

(ert-deftest org-ai-skills-org-apply-rewrite-result-subtree-preserves-purpose-and-source-path ()
  "Subtree apply should preserve PURPOSE/SOURCE_FILE_PATH on matching child headings."
  (with-temp-buffer
    (org-mode)
    (insert "* Root\n"
            ":PROPERTIES:\n"
            ":PURPOSE: Root purpose\n"
            ":END:\n"
            "** Intro\n"
            ":PROPERTIES:\n"
            ":PURPOSE: Intro purpose\n"
            ":SOURCE_FILE_PATH: /tmp/source.md\n"
            ":END:\n"
            "Old intro.\n"
            "** Body\n"
            ":PROPERTIES:\n"
            ":PURPOSE: Body purpose\n"
            ":END:\n"
            "Old body.\n")
    (goto-char (point-min))
    (let ((target (org-ai-skills-org-resolve-subtree 'current)))
      (org-ai-skills-org-apply-rewrite-result
       target
       "* Root\n** Intro\nNew intro.\n** Body\nNew body.\n"))
    (goto-char (point-min))
    (re-search-forward "^\\*\\* Intro$")
    (should (string= (org-entry-get (point) "PURPOSE" nil) "Intro purpose"))
    (should (string= (org-entry-get (point) "SOURCE_FILE_PATH" nil) "/tmp/source.md"))
    (re-search-forward "^\\*\\* Body$")
    (should (string= (org-entry-get (point) "PURPOSE" nil) "Body purpose"))))

(ert-deftest org-ai-skills-org-apply-rewrite-result-removes-indented-pseudo-drawers ()
  "Subtree apply should drop indented pseudo drawers to avoid duplicate drawers."
  (with-temp-buffer
    (org-mode)
    (insert "* Root\n** Sec\n:PROPERTIES:\n:PURPOSE: keep me\n:END:\nOld.\n")
    (goto-char (point-min))
    (let ((target (org-ai-skills-org-resolve-subtree 'current)))
      (org-ai-skills-org-apply-rewrite-result
       target
       "* Root\n** Sec\n\n     :PROPERTIES:\n     :PURPOSE: model\n     :END:\nNew.\n"))
    (goto-char (point-min))
    (re-search-forward "^\\*\\* Sec$")
    (should (string= (org-entry-get (point) "PURPOSE" nil) "keep me"))
    (should (= 0 (how-many "^[ \t]+:PROPERTIES:[ \t]*$" (point-min) (point-max))))))

(ert-deftest org-ai-skills-org-apply-rewrite-result-strips-leading-generated-drawers ()
  "Subtree apply should strip generated top drawers to avoid duplicate property blocks."
  (with-temp-buffer
    (org-mode)
    (insert "* News Daily Report\n"
            ":PROPERTIES:\n"
            ":ID:       36872c24-3a5b-4e09-9791-8148d5d997a2\n"
            ":PURPOSE: 生成今天(2026-02-22)的金融新闻日报\n"
            ":END:\n"
            "Old body.\n")
    (goto-char (point-min))
    (let ((target (org-ai-skills-org-resolve-subtree 'current)))
      (org-ai-skills-org-apply-rewrite-result
       target
       (concat "* News Daily Report\n"
               "\n"
               ":PROPERTIES:\n"
               ":ID: 36872c24-3a5b-4e09-9791-8148d5d997a2\n"
               ":REPORT_DATE: 2026-02-22\n"
               ":END:\n"
               "Updated body.\n")))
    (goto-char (point-min))
    (should (= (how-many "^:PROPERTIES:$" (point-min) (point-max)) 1))
    (should (re-search-forward "^:REPORT_DATE: 2026-02-22$" nil t))
    (should (re-search-forward "Updated body\\." nil t))))

(ert-deftest org-ai-skills-org-apply-rewrite-result-subtree-assigns-heading-ids ()
  "Subtree apply should ensure resulting headings have :ID:."
  (with-temp-buffer
    (org-mode)
    (insert "* Root\n** Intro\nOld intro.\n** Body\nOld body.\n")
    (goto-char (point-min))
    (let ((target (org-ai-skills-org-resolve-subtree 'current)))
      (org-ai-skills-org-apply-rewrite-result
       target
       "* Root\n** Intro\nNew intro.\n** Body\nNew body.\n"))
    (goto-char (point-min))
    (re-search-forward "^\\* Root$")
    (should (stringp (org-entry-get (point) "ID" nil)))
    (re-search-forward "^\\*\\* Intro$")
    (should (stringp (org-entry-get (point) "ID" nil)))
    (re-search-forward "^\\*\\* Body$")
    (should (stringp (org-entry-get (point) "ID" nil)))))

(ert-deftest org-ai-skills-org-apply-rewrite-result-subtree-preserves-properties-on-renamed-headings ()
  "Subtree apply should preserve key properties when child headings are renamed."
  (with-temp-buffer
    (org-mode)
    (insert "* Root\n"
            "** Intro\n"
            ":PROPERTIES:\n"
            ":PURPOSE: Intro purpose\n"
            ":SOURCE_FILE_PATH: /tmp/source.md\n"
            ":END:\n"
            "Old intro.\n"
            "** Body\n"
            ":PROPERTIES:\n"
            ":PURPOSE: Body purpose\n"
            ":END:\n"
            "Old body.\n")
    (goto-char (point-min))
    (let ((target (org-ai-skills-org-resolve-subtree 'current)))
      (org-ai-skills-org-apply-rewrite-result
       target
       "* Root\n** Introduction\nNew intro.\n** Main Body\nNew body.\n"))
    (goto-char (point-min))
    (re-search-forward "^\\*\\* Introduction$")
    (should (string= (org-entry-get (point) "PURPOSE" nil) "Intro purpose"))
    (should (string= (org-entry-get (point) "SOURCE_FILE_PATH" nil) "/tmp/source.md"))
    (re-search-forward "^\\*\\* Main Body$")
    (should (string= (org-entry-get (point) "PURPOSE" nil) "Body purpose"))))

(ert-deftest org-ai-skills-org-apply-rewrite-result-subtree-preserves-later-sibling-properties ()
  "Subtree apply should keep 2nd/3rd sibling properties despite inserted first sibling."
  (with-temp-buffer
    (org-mode)
    (insert "* Root\n"
            "** Alpha\n"
            ":PROPERTIES:\n"
            ":PURPOSE: Alpha purpose\n"
            ":END:\n"
            "A\n"
            "** Beta\n"
            ":PROPERTIES:\n"
            ":PURPOSE: Beta purpose\n"
            ":SOURCE_FILE_PATH: /tmp/beta.md\n"
            ":END:\n"
            "B\n"
            "** Gamma\n"
            ":PROPERTIES:\n"
            ":PURPOSE: Gamma purpose\n"
            ":SOURCE_FILE_PATH: /tmp/gamma.md\n"
            ":END:\n"
            "C\n")
    (goto-char (point-min))
    (let ((target (org-ai-skills-org-resolve-subtree 'current)))
      (org-ai-skills-org-apply-rewrite-result
       target
       "* Root\n** Overview\nIntro\n** Beta Updated\nB2\n** Gamma Updated\nC2\n"))
    (goto-char (point-min))
    (re-search-forward "^\\*\\* Beta Updated$")
    (should (string= (org-entry-get (point) "PURPOSE" nil) "Beta purpose"))
    (should (string= (org-entry-get (point) "SOURCE_FILE_PATH" nil) "/tmp/beta.md"))
    (re-search-forward "^\\*\\* Gamma Updated$")
    (should (string= (org-entry-get (point) "PURPOSE" nil) "Gamma purpose"))
    (should (string= (org-entry-get (point) "SOURCE_FILE_PATH" nil) "/tmp/gamma.md"))))

(ert-deftest org-ai-skills-candidate-persistence-roundtrip-and-status-update ()
  "Candidate store should persist and allow applied-status updates."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t)))
    (unwind-protect
        (let* ((org-ai-skills-version-store-dir store-dir)
               (slot '(:slot-id "slot-1"
                       :slot-key "file|slot-1"
                       :slot-file "/tmp/demo.org"
                       :heading "Demo"))
               (c1 (org-ai-skills--record-generated-candidate
                    slot "task-a" "rewrite" "prompt-a" "*** Demo\nA\n"))
               (_c2 (org-ai-skills--record-generated-candidate
                     slot "task-a" "rewrite" "prompt-a" "*** Demo\nB\n"))
               (items (org-ai-skills--load-slot-candidates "file|slot-1")))
          (should (= (length items) 2))
          (org-ai-skills--update-candidate-status
           "file|slot-1"
           (plist-get c1 :candidate-id)
           "applied")
          (let ((updated (seq-find
                          (lambda (it)
                            (equal (plist-get it :candidate-id)
                                   (plist-get c1 :candidate-id)))
                          (org-ai-skills--load-slot-candidates "file|slot-1"))))
            (should (string= (plist-get updated :status) "applied"))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-candidate-persistence-keeps-utf8-content ()
  "Candidate store should persist UTF-8 content without coding prompts/loss."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t)))
    (unwind-protect
        (let* ((org-ai-skills-version-store-dir store-dir)
               (slot '(:slot-id "slot-utf8"
                       :slot-key "file|slot-utf8"
                       :slot-file "/tmp/demo.org"
                       :heading "Demo"))
               (text "* 标题\n中文内容：市场上涨。\n"))
          (org-ai-skills--record-generated-candidate
           slot "task-utf8" "rewrite" "prompt-utf8" text)
          (let* ((items (org-ai-skills--load-slot-candidates "file|slot-utf8"))
                 (loaded (plist-get (car items) :output-text)))
            (should (= (length items) 1))
            (should (string= loaded text))
            (should (multibyte-string-p loaded))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-rewrite-noninteractive-saves-candidate-when-auto-apply-disabled ()
  "Non-interactive rewrite should keep source unchanged when auto-apply is disabled."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-auto-apply-generated-candidate nil))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nOriginal body.\n")
            (goto-char (point-min))
            (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
                   (slot (org-ai-skills--ensure-subtree-slot-id subtree)))
              (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
                         (lambda (_request callback)
                           (funcall callback "*** Leaf\nRewritten body.\n"))))
                (org-ai-skills-org-rewrite-subtree subtree skill "Rewrite now"))
              (goto-char (point-min))
              (should (re-search-forward "Original body\\." nil t))
              (let ((items (org-ai-skills--load-slot-candidates
                            (plist-get slot :slot-key))))
                (should (= (length items) 1))
                (should (string-match-p "Rewritten body"
                                        (plist-get (car items) :output-text)))))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-rewrite-noninteractive-auto-applies-when-enabled ()
  "Non-interactive rewrite should auto-apply generated candidate when enabled."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-auto-apply-generated-candidate t))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nOriginal body.\n")
            (goto-char (point-min))
            (let ((subtree (org-ai-skills-org-resolve-subtree 'current)))
              (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
                         (lambda (_request callback)
                           (funcall callback "*** Leaf\nRewritten body.\n"))))
                (org-ai-skills-org-rewrite-subtree subtree skill "Rewrite now"))
              (goto-char (point-min))
              (should (re-search-forward "Rewritten body\\." nil t)))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-rewrite-interactive-auto-applies-generated-candidate ()
  "Interactive rewrite should auto-apply latest generated candidate by default."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-auto-apply-generated-candidate t))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nOriginal body.\n")
            (goto-char (point-min))
            (let ((source (current-buffer))
                  (subtree (org-ai-skills-org-resolve-subtree 'current)))
              (cl-letf (((symbol-function 'called-interactively-p)
                         (lambda (&rest _args) t))
                        ((symbol-function 'completing-read)
                         (lambda (&rest _args)
                           (ert-fail "interactive auto-apply should not ask candidate selection")))
                        ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
                         (lambda (_request callback)
                           (funcall callback "*** Leaf\nAuto-applied body.\n"))))
                (org-ai-skills-org-rewrite-subtree subtree skill "Rewrite now"))
              (with-current-buffer source
                (goto-char (point-min))
                (should (re-search-forward "Auto-applied body\\." nil t))))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-apply-slot-candidate-replaces-subtree-and-updates-status ()
  "Apply command should replace subtree from selected candidate."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nOriginal body.\n")
            (goto-char (point-min))
            (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
                   (slot (org-ai-skills--ensure-subtree-slot-id subtree))
                   (candidate (org-ai-skills--record-generated-candidate
                               slot "rewrite" "rewrite" "prompt"
                               "* Leaf\nApplied body.\n"))
                   (display (org-ai-skills--candidate-display candidate)))
              (cl-letf (((symbol-function 'completing-read)
                         (lambda (&rest _args) display)))
                (org-ai-skills-org-apply-slot-candidate subtree))
              (goto-char (point-min))
              (should (re-search-forward "Applied body\\." nil t))
              (let ((updated (seq-find
                              (lambda (it)
                                (equal (plist-get it :candidate-id)
                                       (plist-get candidate :candidate-id)))
                              (org-ai-skills--load-slot-candidates
                               (plist-get slot :slot-key)))))
                (should (string= (plist-get updated :status) "applied"))))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-apply-slot-candidate-preserves-property-drawer ()
  "Applying a candidate should preserve existing subtree properties."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\n:PROPERTIES:\n:ID: keep-id\n:END:\nOriginal body.\n")
            (goto-char (point-min))
            (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
                   (slot (org-ai-skills--ensure-subtree-slot-id subtree))
                   (candidate (org-ai-skills--record-generated-candidate
                               slot "rewrite" "rewrite" "prompt"
                               "* Leaf\nReplaced body.\n"))
                   (display (org-ai-skills--candidate-display candidate)))
              (cl-letf (((symbol-function 'completing-read)
                         (lambda (&rest _args) display)))
                (org-ai-skills-org-apply-slot-candidate subtree))
              (goto-char (point-min))
              (should (re-search-forward ":ID: keep-id" nil t))
              (should (re-search-forward "Replaced body\\." nil t)))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-apply-candidate-with-missing-slot-metadata-does-not-crash ()
  "Applying candidate should not crash when slot metadata is missing."
  (with-temp-buffer
    (org-mode)
    (insert "* Leaf\nOriginal body.\n")
    (goto-char (point-min))
    (let ((subtree (org-ai-skills-org-resolve-subtree 'current))
          (candidate '(:output-text "* Leaf\nApplied body.\n"
                       :slot-key nil
                       :candidate-id nil)))
      (org-ai-skills-org-apply-candidate-to-subtree subtree candidate)
      (goto-char (point-min))
      (should (re-search-forward "Applied body\\." nil t)))))

(ert-deftest org-ai-skills-ui-workspace-open-close-lifecycle ()
  "Workspace command should open control/source columns and restore layout on close."
  (save-window-excursion
    (delete-other-windows)
    (with-temp-buffer
      (org-mode)
      (insert "* Leaf\nBody\n")
      (let ((source (current-buffer))
            (org-ai-skills--ui-run-state (list :source-buffer (current-buffer))))
        (org-ai-skills-ui-open-workspace (current-buffer))
        (should (= (length (window-list)) 2))
        (should (window-live-p (get-buffer-window org-ai-skills-control-buffer-name)))
        (should (eq (window-buffer (selected-window))
                    (get-buffer org-ai-skills-control-buffer-name)))
        (let ((total-width (window-total-width (frame-root-window))))
          (should (<= (window-total-width (selected-window))
                      (max 24 (/ total-width 2)))))
        (should (<= (window-total-width (selected-window))
                    org-ai-skills-ui-control-window-width))
        (should (window-live-p (get-buffer-window source)))
        (org-ai-skills-ui-close-workspace)
        (should (= (length (window-list)) 1))))))

(ert-deftest org-ai-skills-control-mode-map-uses-layered-dispatch ()
  "Control mode map should route layered keys through one dispatcher."
  (should (eq (lookup-key org-ai-skills-control-mode-map (kbd "v"))
              #'org-ai-skills-ui-control-dispatch))
  (should (eq (lookup-key org-ai-skills-control-mode-map (kbd "r"))
              #'org-ai-skills-ui-control-dispatch))
  (should (eq (lookup-key org-ai-skills-control-mode-map (kbd "c"))
              #'org-ai-skills-ui-control-dispatch))
  (should (eq (lookup-key org-ai-skills-control-mode-map (kbd "p"))
              #'org-ai-skills-ui-control-dispatch))
  (should (eq (lookup-key org-ai-skills-control-mode-map (kbd "o"))
              #'org-ai-skills-ui-control-dispatch)))

(ert-deftest org-ai-skills-ui-control-dispatch-v-routes-by-layer ()
  "Key `v` should dispatch to different commands by active control menu layer."
  (let ((calls nil)
        (org-ai-skills--ui-run-state
         (list :status 'ready
               :slot-key "slot-1"
               :planner-run-state '(:steps ((:step-id "s1"))))))
    (cl-letf (((symbol-function 'org-ai-skills-ui-show-dag)
               (lambda () (interactive) (push 'dag calls)))
              ((symbol-function 'org-ai-skills-ui-preview-selected-proposal)
               (lambda () (interactive) (push 'preview calls)))
              ((symbol-function 'org-ai-skills--load-proposals)
               (lambda (_slot-key)
                 (list '(:proposal-id "p1" :status "proposed"))))
              ((symbol-function 'message)
               (lambda (&rest _args) nil)))
      (setq org-ai-skills--ui-run-state
            (plist-put org-ai-skills--ui-run-state :control-layer 'observability))
      (org-ai-skills--ui-control-dispatch-key "v")
      (setq org-ai-skills--ui-run-state
            (plist-put org-ai-skills--ui-run-state :control-layer 'proposal))
      (org-ai-skills--ui-run-set :selected-proposal '(:proposal-id "p1" :status "proposed"))
      (org-ai-skills--ui-control-dispatch-key "v")
      (setq org-ai-skills--ui-run-state
            (plist-put org-ai-skills--ui-run-state :control-layer 'top))
      (org-ai-skills--ui-control-dispatch-key "v"))
    (should (equal calls '(preview dag)))))

(ert-deftest org-ai-skills-ui-control-dispatch-lowercase-opens-submenus ()
  "Top-layer lowercase menu keys should switch to the expected submenu."
  (let ((org-ai-skills--ui-run-state (list :status 'ready :control-layer 'top)))
    (org-ai-skills--ui-control-dispatch-key "r")
    (should (eq (plist-get org-ai-skills--ui-run-state :control-layer) 'run))
    (org-ai-skills--ui-control-dispatch-key "b")
    (org-ai-skills--ui-control-dispatch-key "c")
    (should (eq (plist-get org-ai-skills--ui-run-state :control-layer) 'candidate))
    (org-ai-skills--ui-control-dispatch-key "b")
    (org-ai-skills--ui-control-dispatch-key "p")
    (should (eq (plist-get org-ai-skills--ui-run-state :control-layer) 'proposal))
    (org-ai-skills--ui-control-dispatch-key "b")
    (org-ai-skills--ui-control-dispatch-key "o")
    (should (eq (plist-get org-ai-skills--ui-run-state :control-layer) 'observability))
    (org-ai-skills--ui-control-dispatch-key "b")
    (should (eq (plist-get org-ai-skills--ui-run-state :control-layer) 'top))))

(ert-deftest org-ai-skills-ui-overlay-lifecycle-running-ready-stop ()
  "Overlay should support running/ready states and clear on stop."
  (with-temp-buffer
    (org-mode)
    (insert "* Leaf\nBody\n")
    (goto-char (point-min))
    (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
           (begin (copy-marker (plist-get subtree :begin)))
           (end (copy-marker (plist-get subtree :end)))
           (org-ai-skills--ui-run-state
           (list :source-buffer (current-buffer)
                  :begin begin
                  :end end
                  :run-id "run-1"
                  :status 'running
                  :stop-requested nil)))
      (org-ai-skills--ui-set-overlay 'running)
      (should (overlayp (plist-get org-ai-skills--ui-run-state :overlay)))
      (should (eq (overlay-get (plist-get org-ai-skills--ui-run-state :overlay) 'face)
                  'org-ai-skills-ui-overlay-running-face))
      (org-ai-skills--ui-set-overlay 'ready)
      (should (overlayp (plist-get org-ai-skills--ui-run-state :overlay)))
      (should (eq (overlay-get (plist-get org-ai-skills--ui-run-state :overlay) 'face)
                  'org-ai-skills-ui-overlay-ready-face))
      (org-ai-skills-ui-stop-run)
      (should-not (plist-get org-ai-skills--ui-run-state :overlay))
      (should (eq (plist-get org-ai-skills--ui-run-state :status) 'canceled)))))

(ert-deftest org-ai-skills-ui-rerun-dispatches-rerun-function ()
  "Control rerun should dispatch stored rerun function."
  (let ((called nil)
        (org-ai-skills--ui-run-state nil))
    (setq org-ai-skills--ui-run-state
          (list :source-buffer (current-buffer)
                :rerun-fn (lambda () (setq called t))))
    (org-ai-skills-ui-rerun)
    (should called)))

(ert-deftest org-ai-skills-ui-rerun-runs-in-source-buffer ()
  "Rerun from control panel should execute function in source buffer context."
  (with-temp-buffer
    (org-mode)
    (insert "* Source\n")
    (let ((source-buffer (current-buffer))
          (called nil))
      (with-temp-buffer
        (setq org-ai-skills--ui-run-state
              (list :source-buffer source-buffer
                    :rerun-fn
                    (lambda ()
                      (setq called (eq (current-buffer) source-buffer)))))
        (org-ai-skills-ui-rerun))
      (should called))))

(ert-deftest org-ai-skills-ui-apply-selected-candidate-errors-without-source-buffer ()
  "Apply should fail explicitly when control state cannot resolve source buffer."
  (let ((org-ai-skills--ui-run-state
         (list :status 'ready
               :begin 1
               :end 1
               :context-mode 'current
               :source-buffer nil
               :selected-candidate
               '(:slot-key "k" :candidate-id "c1" :output-text "* X\nY\n"))))
    (should-error (org-ai-skills-ui-apply-selected-candidate)
                  :type 'org-ai-skills-org-context-error)))

(ert-deftest org-ai-skills-ui-adjust-planner-runs-in-source-buffer ()
  "Adjust planner action should run planner from source buffer context."
  (with-temp-buffer
    (org-mode)
    (insert "* Root\nBody\n")
    (let ((source-buffer (current-buffer))
          (begin (copy-marker (point-min)))
          (end (copy-marker (point-max)))
          (called-in-source nil)
          (captured-target nil))
      (with-temp-buffer
        (setq org-ai-skills--ui-run-state
              (list :status 'ready
                    :run-type 'planner
                    :source-buffer source-buffer
                    :target nil
                    :begin begin
                    :end end
                    :context-mode 'current
                    :task "old task"))
        (cl-letf (((symbol-function 'read-string)
                   (lambda (&rest _args) "new task"))
                  ((symbol-function 'org-ai-skills-plan-run)
                   (lambda (target _task &optional _interactive-origin _preset-id)
                     (setq captured-target target)
                     (setq called-in-source (eq (current-buffer) source-buffer)))))
          (org-ai-skills-ui-adjust-task-or-instruction)))
      (should called-in-source)
      (should (eq (plist-get captured-target :context-mode) 'current)))))

(ert-deftest org-ai-skills-ui-select-candidate-wires-minibuffer-flow ()
  "Control candidate selector should reuse minibuffer and store selected candidate."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nOriginal body.\n")
            (goto-char (point-min))
            (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
                   (slot (org-ai-skills--ensure-subtree-slot-id subtree))
                   (candidate (org-ai-skills--record-generated-candidate
                               slot "rewrite" "rewrite" "prompt"
                               "* Leaf\nApplied body.\n"))
                   (display (org-ai-skills--candidate-display candidate))
                   (begin (copy-marker (plist-get subtree :begin)))
                   (end (copy-marker (plist-get subtree :end)))
                   (org-ai-skills--ui-run-state
                    (list :run-id "run-2"
                          :source-buffer (current-buffer)
                          :begin begin
                          :end end
                          :slot-key (plist-get slot :slot-key)
                          :status 'running
                          :progress "candidate-ready")))
              (org-ai-skills--ui-set-overlay 'ready)
              (cl-letf (((symbol-function 'completing-read)
                         (lambda (&rest _args) display)))
                (org-ai-skills-ui-select-candidate))
              (should (equal (plist-get (plist-get org-ai-skills--ui-run-state :selected-candidate)
                                        :candidate-id)
                             (plist-get candidate :candidate-id)))
              (should-not (plist-get org-ai-skills--ui-run-state :overlay)))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-ui-extract-pattern-proposal-persists-artifact ()
  "Manual control-panel extraction should persist a proposal artifact."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (proposal-dir (make-temp-file "org-ai-skills-proposals-" t)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-proposal-store-dir proposal-dir))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nOriginal body.\n")
            (goto-char (point-min))
            (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
                   (slot (org-ai-skills--ensure-subtree-slot-id subtree))
                   (candidate (org-ai-skills--record-generated-candidate
                               slot "rewrite" "rewrite" "prompt"
                               "* Leaf\n- Step one\n- Step two\nEnsure formatting.\nIf missing data then retry.\n"))
                   (begin (copy-marker (plist-get subtree :begin)))
                   (end (copy-marker (plist-get subtree :end)))
                   (org-ai-skills--ui-run-state
                    (list :run-id "run-proposal-1"
                          :run-type 'rewrite
                          :source-buffer (current-buffer)
                          :begin begin
                          :end end
                          :slot-key (plist-get slot :slot-key)
                          :target-skill-id "gen-notes"
                          :target-skill-file "/tmp/gen-notes.org"
                          :status 'ready
                          :progress "candidate-ready"
                          :selected-candidate nil)))
              (org-ai-skills-ui-extract-pattern-proposal)
              (should (equal (plist-get org-ai-skills--ui-run-state :progress)
                             "pattern-proposal-extracted"))
              (let* ((proposal (plist-get org-ai-skills--ui-run-state :selected-proposal))
                     (proposal-id (plist-get proposal :proposal-id))
                     (file (expand-file-name (format "%s.json" proposal-id) proposal-dir))
                     (artifact nil))
                (should (stringp proposal-id))
                (should (file-exists-p file))
                (setq artifact
                      (json-parse-string
                       (with-temp-buffer
                         (insert-file-contents file)
                         (buffer-string))
                       :object-type 'plist
                       :array-type 'list
                       :null-object nil
                       :false-object nil))
                (should (equal (plist-get artifact :source-candidate-id)
                               (plist-get candidate :candidate-id)))
                (should (equal (plist-get artifact :target-skill-id) "gen-notes"))
                (should (equal (plist-get artifact :target-skill-file) "/tmp/gen-notes.org"))
                (should (equal (plist-get artifact :extraction-mode)
                               "manual-control-panel"))
                (should (> (length (plist-get (plist-get artifact :patterns) :steps)) 0))))))
      (delete-directory store-dir t)
      (delete-directory proposal-dir t)))

(ert-deftest org-ai-skills-ui-extract-pattern-proposal-unavailable-while-running ()
  "Manual extraction should be unavailable while run status is running."
  (let ((message-log nil)
        (org-ai-skills--ui-run-state
         (list :status 'running
               :slot-key "dummy|slot")))
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) message-log))))
      (org-ai-skills-ui-extract-pattern-proposal))
    (should (equal (car message-log)
                   "org-ai-skills: extract unavailable while running"))
    (should-not (plist-get org-ai-skills--ui-run-state :selected-proposal))))

(ert-deftest org-ai-skills-ui-extract-pattern-proposal-errors-without-target-skill ()
  "Manual extraction should fail when previous run context has no target skill."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (proposal-dir (make-temp-file "org-ai-skills-proposals-" t)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-proposal-store-dir proposal-dir))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nOriginal body.\n")
            (goto-char (point-min))
            (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
                   (slot (org-ai-skills--ensure-subtree-slot-id subtree))
                   (_candidate (org-ai-skills--record-generated-candidate
                                slot "rewrite" "rewrite" "prompt"
                                "* Leaf\n- Step one\n"))
                   (begin (copy-marker (plist-get subtree :begin)))
                   (end (copy-marker (plist-get subtree :end)))
                   (org-ai-skills--ui-run-state
                    (list :run-id "run-proposal-no-target"
                          :run-type 'rewrite
                          :source-buffer (current-buffer)
                          :begin begin
                          :end end
                          :slot-key (plist-get slot :slot-key)
                          :status 'ready
                          :progress "candidate-ready")))
              (should-error (org-ai-skills-ui-extract-pattern-proposal)
                            :type 'org-ai-skills-proposal-store-error))))
      (delete-directory store-dir t)
      (delete-directory proposal-dir t))))

(ert-deftest org-ai-skills-ui-proposal-review-approve-and-apply-with-audit-log ()
  "Proposal review workflow should persist status transitions and audit events."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (proposal-dir (make-temp-file "org-ai-skills-proposals-" t)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-proposal-store-dir proposal-dir))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nBody\n")
            (goto-char (point-min))
            (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
                   (slot (org-ai-skills--ensure-subtree-slot-id subtree))
                   (_candidate (org-ai-skills--record-generated-candidate
                                slot "rewrite" "rewrite" "prompt"
                                "* Leaf\n- Step one\nEnsure correctness.\n"))
                   (begin (copy-marker (plist-get subtree :begin)))
                   (end (copy-marker (plist-get subtree :end)))
                   (org-ai-skills--ui-run-state
                    (list :run-id "run-review-1"
                          :run-type 'rewrite
                          :source-buffer (current-buffer)
                          :begin begin
                          :end end
                          :slot-key (plist-get slot :slot-key)
                          :target-skill-id "gen-notes"
                          :target-skill-file "/tmp/gen-notes.org"
                          :status 'ready
                          :progress "candidate-ready")))
              (org-ai-skills-ui-extract-pattern-proposal)
              (org-ai-skills-ui-approve-selected-proposal)
              (should (equal (plist-get (plist-get org-ai-skills--ui-run-state :selected-proposal)
                                        :status)
                             "approved"))
              (org-ai-skills-ui-apply-selected-proposal)
              (let* ((selected (plist-get org-ai-skills--ui-run-state :selected-proposal))
                     (proposal-id (plist-get selected :proposal-id))
                     (proposal-file (expand-file-name (format "%s.json" proposal-id) proposal-dir))
                     (artifact (json-parse-string
                                (with-temp-buffer
                                  (insert-file-contents proposal-file)
                                  (buffer-string))
                                :object-type 'plist
                                :array-type 'list
                                :null-object nil
                                :false-object nil))
                     (audit-file (expand-file-name "audit-log.jsonl" proposal-dir))
                     (audit-lines (split-string
                                   (with-temp-buffer
                                     (insert-file-contents audit-file)
                                     (buffer-string))
                                   "\n" t))
                     (actions (mapcar
                               (lambda (line)
                                 (plist-get (json-parse-string line
                                                               :object-type 'plist
                                                               :array-type 'list
                                                               :null-object nil
                                                               :false-object nil)
                                            :action))
                               audit-lines)))
                (should (equal (plist-get artifact :status) "applied"))
                (should (equal (plist-get (plist-get artifact :application) :mode)
                               "artifact-only"))
                (should (member "approved" actions))
                (should (member "applied" actions))))))
      (delete-directory store-dir t)
      (delete-directory proposal-dir t))))

(ert-deftest org-ai-skills-ui-proposal-apply-requires-approved-status ()
  "Proposal apply should reject transitions from non-approved states."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (proposal-dir (make-temp-file "org-ai-skills-proposals-" t)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-proposal-store-dir proposal-dir))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nBody\n")
            (goto-char (point-min))
            (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
                   (slot (org-ai-skills--ensure-subtree-slot-id subtree))
                   (_candidate (org-ai-skills--record-generated-candidate
                                slot "rewrite" "rewrite" "prompt" "* Leaf\n- Step one\n"))
                   (begin (copy-marker (plist-get subtree :begin)))
                   (end (copy-marker (plist-get subtree :end)))
                   (org-ai-skills--ui-run-state
                    (list :run-id "run-review-2"
                          :run-type 'rewrite
                          :source-buffer (current-buffer)
                          :begin begin
                          :end end
                          :slot-key (plist-get slot :slot-key)
                          :target-skill-id "gen-notes"
                          :target-skill-file "/tmp/gen-notes.org"
                          :status 'ready
                          :progress "candidate-ready")))
              (org-ai-skills-ui-extract-pattern-proposal)
              (should-error (org-ai-skills-ui-apply-selected-proposal)
                            :type 'org-ai-skills-proposal-store-error))))
      (delete-directory store-dir t)
      (delete-directory proposal-dir t))))

(ert-deftest org-ai-skills-ui-proposal-apply-safety-blocks-skill-mutation ()
  "Apply should fail when proposal indicates runtime mutation under skills/."
  (let ((proposal-dir (make-temp-file "org-ai-skills-proposals-" t))
        (skill-dir (make-temp-file "org-ai-skills-skills-" t)))
    (unwind-protect
        (let* ((org-ai-skills-proposal-store-dir proposal-dir)
               (org-ai-skills-skill-dir skill-dir)
               (unsafe-file (expand-file-name "001-skill.org" skill-dir))
               (proposal (org-ai-skills--persist-proposal
                          (list :proposal-id "proposal-safety-1"
                                :created-at "2026-02-22T00:00:00+0000"
                                :type "skill-pattern-proposal"
                                :status "approved"
                                :target-skill-file unsafe-file
                                :proposed-files (vector unsafe-file)
                                :source-slot-key "slot-1"
                                :source-candidate-id "cand-1"))))
          (let ((org-ai-skills--ui-run-state
                 (list :status 'ready
                       :slot-key "slot-1"
                       :selected-proposal proposal)))
            (should-error (org-ai-skills-ui-apply-selected-proposal)
                          :type 'org-ai-skills-safety-error))))
      (delete-directory proposal-dir t)
      (delete-directory skill-dir t))))

(ert-deftest org-ai-skills-ui-proposal-apply-to-skill-file-appends-block ()
  "Confirmed skill-file apply should append proposal block and mark applied."
  (let ((proposal-dir (make-temp-file "org-ai-skills-proposals-" t))
        (skill-dir (make-temp-file "org-ai-skills-skills-" t)))
    (unwind-protect
        (let* ((org-ai-skills-proposal-store-dir proposal-dir)
               (org-ai-skills-skill-dir skill-dir)
               (skill-file (expand-file-name "001-target.org" skill-dir)))
          (with-temp-file skill-file
            (insert "* Skill: Target Skill\n:PROPERTIES:\n:SKILL_ID: target-skill\n:END:\n\n** Description\nBase.\n"))
          (let* ((proposal (org-ai-skills--persist-proposal
                            (list :proposal-id "proposal-file-1"
                                  :created-at "2026-02-22T00:00:00+0000"
                                  :type "skill-pattern-proposal"
                                  :status "approved"
                                  :target-skill-id "target-skill"
                                  :target-skill-file skill-file
                                  :patterns
                                  (list :steps ["Step one"] :checks [] :failure-handling [] :heuristics [])
                                  :source-slot-key "slot-1"
                                  :source-candidate-id "cand-1")))
                 (org-ai-skills--ui-run-state
                  (list :status 'ready
                        :slot-key "slot-1"
                        :selected-proposal proposal)))
            (cl-letf (((symbol-function 'yes-or-no-p)
                       (lambda (&rest _args) t)))
              (org-ai-skills-ui-apply-selected-proposal-to-skill-file))
            (with-temp-buffer
              (insert-file-contents skill-file)
              (goto-char (point-min))
              (should (re-search-forward "Extracted Pattern Proposal: proposal-file-1" nil t))
              (should (re-search-forward ":TARGET_SKILL_ID: target-skill" nil t))
              (should (re-search-forward "Step one" nil t)))
            (should (equal (plist-get (plist-get org-ai-skills--ui-run-state :selected-proposal) :status)
                           "applied"))
            (should (equal (plist-get (plist-get (plist-get org-ai-skills--ui-run-state :selected-proposal)
                                                 :application)
                                      :mode)
                           "skill-file-append"))))
      (delete-directory proposal-dir t)
      (delete-directory skill-dir t))))

(ert-deftest org-ai-skills-ui-proposal-apply-to-skill-file-unavailable-while-running ()
  "Skill-file apply should be unavailable while run status is running."
  (let ((message-log nil)
        (org-ai-skills--ui-run-state
         (list :status 'running
               :slot-key "slot-1")))
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) message-log))))
      (org-ai-skills-ui-apply-selected-proposal-to-skill-file))
    (should (equal (car message-log)
                   "org-ai-skills: skill-file apply unavailable while running"))))

(ert-deftest org-ai-skills-ui-preview-selected-proposal-renders-buffer ()
  "Preview command should render selected proposal details."
  (let ((proposal-dir (make-temp-file "org-ai-skills-proposals-" t)))
    (unwind-protect
        (let* ((org-ai-skills-proposal-store-dir proposal-dir)
               (proposal (org-ai-skills--persist-proposal
                          (list :proposal-id "proposal-preview-1"
                                :created-at "2026-02-22T00:00:00+0000"
                                :type "skill-pattern-proposal"
                                :status "proposed"
                                :source-slot-key "slot-1"
                                :source-candidate-id "cand-1"
                                :target-skill-id "gen-notes"
                                :target-skill-file "/tmp/gen-notes.org"
                                :rationale "Preview rationale"
                                :confidence 0.5
                                :risk "medium"
                                :patterns
                                (list :steps ["Step one"]
                                      :checks ["Check one"]
                                      :failure-handling ["Retry once"]
                                      :heuristics ["Prefer concise edits"])))))
          (let ((org-ai-skills--ui-run-state
                 (list :status 'ready
                       :slot-key "slot-1"
                       :selected-proposal proposal)))
            (org-ai-skills-ui-preview-selected-proposal)
            (with-current-buffer (get-buffer "*org-ai-skills-proposal*")
              (goto-char (point-min))
              (should (re-search-forward "Proposal ID: proposal-preview-1" nil t))
              (should (re-search-forward "Target skill: gen-notes" nil t))
              (should (re-search-forward "Preview rationale" nil t))
              (should (re-search-forward "Step one" nil t)))))
      (delete-directory proposal-dir t))))

(ert-deftest org-ai-skills-ui-preview-selected-proposal-unavailable-while-running ()
  "Preview should be unavailable while run status is running."
  (let ((message-log nil)
        (org-ai-skills--ui-run-state
         (list :status 'running
               :slot-key "slot-1")))
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) message-log))))
      (org-ai-skills-ui-preview-selected-proposal))
    (should (equal (car message-log)
                   "org-ai-skills: proposal preview unavailable while running"))))

(ert-deftest org-ai-skills-ui-control-buffer-renders-candidate-history ()
  "Control buffer should render candidate history list for the current slot."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nBody\n")
            (goto-char (point-min))
            (let* ((subtree (org-ai-skills-org-resolve-subtree 'current))
                   (slot (org-ai-skills--ensure-subtree-slot-id subtree))
                   (candidate-a (org-ai-skills--record-generated-candidate
                                 slot "rewrite" "rewrite" "prompt-a" "* Leaf\nA\n"))
                   (_candidate-b (org-ai-skills--record-generated-candidate
                                  slot "rewrite" "rewrite" "prompt-b" "* Leaf\nB\n"))
                   (org-ai-skills--ui-run-state
                    (list :run-id "run-history"
                          :status 'ready
                          :progress "candidate-ready"
                          :run-type 'rewrite
                          :slot-key (plist-get slot :slot-key)
                          :heading "Leaf"
                          :task "rewrite"
                          :selected-candidate candidate-a)))
              (org-ai-skills-ui-refresh-control-buffer)
              (with-current-buffer (get-buffer org-ai-skills-control-buffer-name)
                (goto-char (point-min))
                (should (re-search-forward "Keys (Top):" nil t))
                (should (re-search-forward "o open observability menu" nil t))
                (goto-char (point-min))
                (should (re-search-forward "Candidates (2):" nil t))
                (should-not (re-search-forward
                             (regexp-quote (plist-get candidate-a :candidate-id))
                             nil t))
                (goto-char (point-min))
                (should (re-search-forward " \\*01 \\[G\\] " nil t))))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-ui-control-buffer-renders-error-detail ()
  "Control buffer should show explicit failure error detail."
  (let ((org-ai-skills--ui-run-state
         (list :run-id "run-error"
               :status 'failed
               :progress "tool-error"
               :error-detail "Provider tool failed (org-ai-skills-core-provider-list-files, path-not-allowed): blocked"
               :run-type 'rewrite
               :heading "Code Base Learning"
               :task "research")))
    (org-ai-skills-ui-refresh-control-buffer)
    (with-current-buffer (get-buffer org-ai-skills-control-buffer-name)
      (goto-char (point-min))
      (should (re-search-forward "^Status: failed$" nil t))
      (should (re-search-forward "^Progress: tool-error$" nil t))
      (should (re-search-forward "^Error: Provider tool failed" nil t)))))

(ert-deftest org-ai-skills-ui-control-buffer-disables-dag-key-when-empty ()
  "Control buffer should dim DAG key when no DAG data is available yet."
  (let ((org-ai-skills--ui-run-state
         (list :run-id "run-empty-dag"
               :status 'running
               :progress "planning"
               :run-type 'planner
               :heading "Leaf"
               :task "task"
               :selected-candidate nil
               :planner-run-state nil
               :control-layer 'observability)))
    (org-ai-skills-ui-refresh-control-buffer)
    (with-current-buffer (get-buffer org-ai-skills-control-buffer-name)
      (goto-char (point-min))
      (re-search-forward "v view DAG")
      (should (eq (get-text-property (line-beginning-position) 'face) 'shadow)))))

(ert-deftest org-ai-skills-build-execution-dag-derives-deps-status-and-metrics ()
  "DAG builder should derive node dependencies, status, and metrics from run-state."
  (let* ((run-state
          '(:active-plan ((:step-id "s1"
                           :goal "g1"
                           :skills ("a")
                           :input-from ("task"))
                          (:step-id "s2"
                           :goal "g2"
                           :skills ("b")
                           :input-from ("s1")))
            :steps ((:step-id "s1" :status done :skills ("a") :goal "g1"))
            :events ((:stage-id execution.step
                      :step-id "s1"
                      :duration-ms 7
                      :usage (:input-tokens 4 :output-tokens 3 :total-tokens 7)
                      :estimated-cost-usd 0.0012))))
         (dag (org-ai-skills-build-execution-dag run-state))
         (nodes (plist-get dag :nodes))
         (edges (plist-get dag :edges))
         (node-s1 (seq-find (lambda (n) (equal (plist-get n :id) "s1")) nodes))
         (node-s2 (seq-find (lambda (n) (equal (plist-get n :id) "s2")) nodes)))
    (should (= (length nodes) 2))
    (should (= (length edges) 1))
    (should (eq (plist-get node-s1 :status) 'success))
    (should (eq (plist-get node-s2 :status) 'pending))
    (should (equal (plist-get (car edges) :from) "s1"))
    (should (equal (plist-get (car edges) :to) "s2"))
    (should (= (plist-get (plist-get node-s1 :metrics) :duration-ms) 7))
    (should (= (plist-get (plist-get node-s1 :metrics) :total-tokens) 7))))

(ert-deftest org-ai-skills-build-execution-dag-dedupes-duplicate-step-ids ()
  "DAG builder should render each step id once even if plan repeats it."
  (let* ((run-state
          '(:active-plan ((:step-id "polish-report" :goal "g1" :skills ("article-polish-editorial") :input-from ("task"))
                          (:step-id "polish-report" :goal "g2" :skills ("article-polish-editorial") :input-from ("task")))
            :steps ((:step-id "polish-report" :status done :skills ("article-polish-editorial")))
            :events ((:stage-id execution.step
                      :step-id "polish-report"
                      :duration-ms 10
                      :usage (:input-tokens 5 :output-tokens 3 :total-tokens 8)))))
         (dag (org-ai-skills-build-execution-dag run-state))
         (nodes (plist-get dag :nodes)))
    (should (= (length nodes) 1))
    (should (equal (plist-get (car nodes) :id) "polish-report"))))

(ert-deftest org-ai-skills-build-execution-dag-includes-planning-events-chronologically ()
  "Event DAG mode should include planning/execution events per occurrence."
  (let* ((run-state
          '(:steps ((:step-id "s1" :status done :skills ("fin-news-daily-report") :goal "draft"))
            :events ((:stage-id planning.request
                      :status success
                      :duration-ms 30
                      :plan-revision 1
                      :usage (:input-tokens 10 :output-tokens 5 :total-tokens 15))
                     (:stage-id planning.parse
                      :status success
                      :duration-ms 5
                      :plan-revision 1
                      :usage (:input-tokens 10 :output-tokens 5 :total-tokens 15))
                     (:stage-id execution.step
                      :status success
                      :duration-ms 20
                      :step-id "s1"
                      :skill-ids ("fin-news-daily-report")
                      :usage (:input-tokens 8 :output-tokens 12 :total-tokens 20))
                     (:stage-id planning.request
                      :status success
                      :duration-ms 25
                      :plan-revision 2
                      :usage (:input-tokens 9 :output-tokens 4 :total-tokens 13)))))
         (dag (org-ai-skills-build-execution-dag run-state nil t))
         (nodes (plist-get dag :nodes))
         (edges (plist-get dag :edges)))
    (should (= (length nodes) 4))
    (should (= (length edges) 3))
    (should (equal (plist-get (nth 0 nodes) :id) "planning.request#1"))
    (should (equal (plist-get (nth 1 nodes) :id) "planning.parse#1"))
    (should (equal (plist-get (nth 2 nodes) :id) "execution.step:s1#1"))
    (should (equal (plist-get (nth 3 nodes) :id) "planning.request#2"))
    (should (equal (plist-get (plist-get (nth 2 nodes) :metrics) :total-tokens) 20))
    (should (equal (plist-get (car edges) :from) "planning.request#1"))
    (should (equal (plist-get (car edges) :to) "planning.parse#1"))))

(ert-deftest org-ai-skills-build-execution-dag-includes-call-level-nodes-under-step ()
  "Event DAG should show api.call nodes linked from their parent step."
  (let* ((run-state
          '(:steps ((:step-id "s1" :status done :skills ("fin-news-daily-report") :goal "draft"))
            :events ((:stage-id api.call
                      :request-role execution
                      :call-index 1
                      :status success
                      :duration-ms 12
                      :step-id "s1"
                      :usage (:input-tokens 3 :output-tokens 4 :total-tokens 7)))))
         (dag (org-ai-skills-build-execution-dag run-state nil t))
         (nodes (plist-get dag :nodes))
         (edges (plist-get dag :edges))
         (call-id "api.call:execution:s1:1#1")
         (step-node (seq-find (lambda (n) (equal (plist-get n :id) "s1")) nodes))
         (call-node (seq-find (lambda (n) (equal (plist-get n :id) call-id)) nodes))
         (step-edge (seq-find (lambda (e)
                                (and (equal (plist-get e :from) "s1")
                                     (equal (plist-get e :to) call-id)))
                              edges)))
    (should step-node)
    (should call-node)
    (should step-edge)
    (should (equal (plist-get (plist-get call-node :metrics) :total-tokens) 7))))

(ert-deftest org-ai-skills-build-execution-dag-includes-tool-call-nodes-under-step ()
  "Event DAG should show tool.call nodes linked from their parent step."
  (let* ((run-state
          '(:steps ((:step-id "s1" :status done :skills ("fin-news-daily-report") :goal "draft"))
            :events ((:stage-id tool.call
                      :request-role execution
                      :tool-name "org-ai-skills-search1api-fetch-financial-news-raw"
                      :call-index 2
                      :status success
                      :duration-ms 450
                      :step-id "s1"))))
         (dag (org-ai-skills-build-execution-dag run-state nil t))
         (nodes (plist-get dag :nodes))
         (edges (plist-get dag :edges))
         (call-id "tool.call:org-ai-skills-search1api-fetch-financial-news-raw:s1:2#1")
         (step-node (seq-find (lambda (n) (equal (plist-get n :id) "s1")) nodes))
         (call-node (seq-find (lambda (n) (equal (plist-get n :id) call-id)) nodes))
         (step-edge (seq-find (lambda (e)
                                (and (equal (plist-get e :from) "s1")
                                     (equal (plist-get e :to) call-id)))
                              edges)))
    (should step-node)
    (should call-node)
    (should step-edge)
    (should (= (plist-get (plist-get call-node :metrics) :duration-ms) 450))))

(ert-deftest org-ai-skills-build-execution-dag-treats-applied-as-success ()
  "DAG status mapping should treat applied step status as success."
  (let* ((run-state
          '(:steps ((:step-id "rewrite"
                     :status applied
                     :skills ("simplify-twitter")
                     :goal "Rewrite for twitter"))))
         (dag (org-ai-skills-build-execution-dag run-state))
         (node (car (plist-get dag :nodes))))
    (should (equal (plist-get node :id) "rewrite"))
    (should (eq (plist-get node :status) 'success))))

(ert-deftest org-ai-skills-ui-show-dag-renders-current-planner-run ()
  "DAG view command should render from current planner run-state."
  (let ((org-ai-skills--ui-run-state
         '(:planner-run-state
           (:run-id "run-1"
            :plan-revision 1
            :active-plan ((:step-id "s1" :goal "g1" :skills ("a") :input-from ("task")))
            :steps ((:step-id "s1" :status done :skills ("a") :goal "g1"))
            :events ((:stage-id execution.step
                      :step-id "s1"
                      :duration-ms 5
                      :usage (:input-tokens 2 :output-tokens 1 :total-tokens 3)
                      :estimated-cost-usd 0.0003))))))
    (cl-letf (((symbol-function 'pop-to-buffer)
               (lambda (buffer &rest _args) buffer)))
      (org-ai-skills-ui-show-dag))
    (with-current-buffer (get-buffer org-ai-skills-dag-buffer-name)
      (goto-char (point-min))
      (should (re-search-forward "Execution DAG" nil t))
      (should (re-search-forward "\\[success\\] execution.step:s1#1" nil t)))))

(ert-deftest org-ai-skills-render-execution-dag-text-indents-by-level ()
  "DAG text should indent nodes based on dependency depth."
  (let* ((dag '(:nodes ((:id "root"
                         :status success
                         :dependencies nil
                         :skills nil
                         :metrics (:duration-ms 1 :input-tokens 0 :output-tokens 0 :total-tokens 0 :estimated-cost-usd 0.0))
                        (:id "child"
                         :status success
                         :dependencies ("root")
                         :skills ("skill-a")
                         :metrics (:duration-ms 2 :input-tokens 1 :output-tokens 2 :total-tokens 3 :estimated-cost-usd 0.001))
                        (:id "grandchild"
                         :status success
                         :dependencies ("child")
                         :skills ("skill-b")
                         :metrics (:duration-ms 3 :input-tokens 2 :output-tokens 3 :total-tokens 5 :estimated-cost-usd 0.002)))
                :edges ((:from "root" :to "child")
                        (:from "child" :to "grandchild"))))
         (text (org-ai-skills-render-execution-dag-text dag)))
    (should (string-match-p "^- \\[success\\] root (L0)$" text))
    (should (string-match-p "^  - \\[success\\] child (L1)$" text))
    (should (string-match-p "^    - \\[success\\] grandchild (L2)$" text))))

(ert-deftest org-ai-skills-render-execution-dag-text-allows-depth-to-return ()
  "DAG text indentation should return to shallower levels for later branches."
  (let* ((dag '(:nodes ((:id "s1"
                         :status success
                         :dependencies nil
                         :skills ("a")
                         :metrics (:duration-ms 1 :input-tokens 0 :output-tokens 0 :total-tokens 0 :estimated-cost-usd 0.0))
                        (:id "api.call:execution:s1:1#1"
                         :status success
                         :dependencies ("s1")
                         :skills ("a")
                         :metrics (:duration-ms 2 :input-tokens 0 :output-tokens 0 :total-tokens 0 :estimated-cost-usd 0.0))
                        (:id "s2"
                         :status success
                         :dependencies nil
                         :skills ("b")
                         :metrics (:duration-ms 1 :input-tokens 0 :output-tokens 0 :total-tokens 0 :estimated-cost-usd 0.0))
                        (:id "api.call:execution:s2:1#1"
                         :status success
                         :dependencies ("api.call:execution:s1:1#1" "s2")
                         :skills ("b")
                         :metrics (:duration-ms 2 :input-tokens 0 :output-tokens 0 :total-tokens 0 :estimated-cost-usd 0.0)))
                :edges nil))
         (text (org-ai-skills-render-execution-dag-text dag)))
    (should (string-match-p "^- \\[success\\] s1 (L0)$" text))
    (should (string-match-p "^  - \\[success\\] api\\.call:execution:s1:1#1 (L1)$" text))
    (should (string-match-p "^- \\[success\\] s2 (L0)$" text))
    (should (string-match-p "^  - \\[success\\] api\\.call:execution:s2:1#1 (L1)$" text))))

(ert-deftest org-ai-skills-rewrite-interactive-auto-opens-control-workspace ()
  "Interactive rewrite should auto-open control workspace when enabled."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file))
        (opened nil))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-auto-apply-generated-candidate t)
              (org-ai-skills-ui-auto-open t))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nOriginal body.\n")
            (goto-char (point-min))
            (let ((subtree (org-ai-skills-org-resolve-subtree 'current)))
              (cl-letf (((symbol-function 'called-interactively-p)
                         (lambda (&rest _args) t))
                        ((symbol-function 'org-ai-skills-ui-open-workspace)
                         (lambda (&optional _source-buffer)
                           (setq opened t)))
                        ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
                         (lambda (_request callback)
                           (funcall callback "*** Leaf\nAuto-applied body.\n"))))
                (org-ai-skills-org-rewrite-subtree subtree skill "Rewrite now"))
              (should opened))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-embark-action-delegates-to-rewrite-command ()
  "Embark adapter should dispatch to the interactive rewrite command."
  (let (called)
    (cl-letf (((symbol-function 'call-interactively)
               (lambda (command &optional _record-flag _keys)
                 (setq called command))))
      (org-ai-skills-embark-rewrite-subtree-action "target")
      (should (eq called #'org-ai-skills-org-rewrite-subtree)))))

(ert-deftest org-ai-skills-embark-action-delegates-to-planner-commands ()
  "Embark planner adapters should dispatch to their interactive commands."
  (let (calls)
    (cl-letf (((symbol-function 'call-interactively)
               (lambda (command &optional _record-flag _keys)
                 (push command calls))))
      (org-ai-skills-embark-plan-run-action "target")
      (org-ai-skills-embark-plan-repeat-task-action "target"))
    (should (member #'org-ai-skills-plan-run calls))
    (should (member #'org-ai-skills-plan-repeat-task calls))))

(ert-deftest org-ai-skills-plan-and-run-caches-last-task ()
  "Planner command should persist last task for reuse helper."
  (let ((org-ai-skills--last-planner-task nil)
        received-task)
    (cl-letf (((symbol-function 'org-ai-skills-run-task-with-planner)
               (lambda (task _subtree _options _callback)
                 (setq received-task task))))
      (org-ai-skills-plan-run
       '(:heading "Leaf" :level 3 :text "*** Leaf\n")
       "Normalize and shorten"))
    (should (string= received-task "Normalize and shorten"))
    (should (string= org-ai-skills--last-planner-task "Normalize and shorten"))))

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
                        #'org-ai-skills-embark-rewrite-subtree-action))
            (should (eq (lookup-key (symbol-value
                                     (cdr (assq 'org-heading embark-keymap-alist)))
                                    (kbd "P"))
                        #'org-ai-skills-embark-plan-run-action))
            (should (eq (lookup-key (symbol-value
                                     (cdr (assq 'org-heading embark-keymap-alist)))
                                    (kbd "p"))
                        #'org-ai-skills-embark-plan-repeat-task-action))))
      (if had-bound
          (set 'embark-keymap-alist old-value)
        (makunbound 'embark-keymap-alist)))))

(ert-deftest org-ai-skills-plan-repeat-errors-without-last-task ()
  "Planner repeat helper should fail when no prior task exists."
  (let ((org-ai-skills--last-planner-task nil))
    (should-error
     (org-ai-skills-plan-repeat-task '(:heading "Leaf"))
     :type 'org-ai-skills-planner-error)))

(ert-deftest org-ai-skills-plan-repeat-reuses-last-task ()
  "Planner repeat helper should forward cached task."
  (let ((org-ai-skills--last-planner-task "Refine notes")
        called-target
        called-task
        called-origin)
    (cl-letf (((symbol-function 'org-ai-skills-plan-run)
               (lambda (target task &optional interactive-origin preset-id)
                 (setq called-target target)
                 (setq called-task task)
                 (setq called-origin interactive-origin)
                 (setq org-ai-skills-test--captured-preset preset-id))))
      (org-ai-skills-plan-repeat-task '(:heading "Leaf")))
    (should (equal called-target '(:heading "Leaf")))
    (should (string= called-task "Refine notes"))
    (should called-origin)))

(ert-deftest org-ai-skills-read-planner-task-preset-errors-when-missing ()
  "Reading preset should fail when no presets configured."
  (let ((org-ai-skills-planner-task-presets nil))
    (should-error (org-ai-skills-read-planner-task-preset)
                  :type 'org-ai-skills-planner-error)))

(ert-deftest org-ai-skills-plan-run-preset-forwards-mapped-task ()
  "Preset planner command should map preset id to task text."
  (let ((org-ai-skills-planner-task-presets
         '(("notes" . "Convert to concise notes"))))
    (cl-letf (((symbol-function 'org-ai-skills-plan-run)
               (lambda (target task &optional interactive-origin preset-id)
                 (setq org-ai-skills-test--captured-target target)
                 (setq org-ai-skills-test--captured-task task)
                 (setq org-ai-skills-test--captured-origin interactive-origin)
                 (setq org-ai-skills-test--captured-preset preset-id))))
      (org-ai-skills-plan-run-preset '(:heading "Leaf") "notes")
      (should (equal org-ai-skills-test--captured-target '(:heading "Leaf")))
      (should (string= org-ai-skills-test--captured-task "Convert to concise notes"))
      (should org-ai-skills-test--captured-origin)
      (should (string= org-ai-skills-test--captured-preset "notes")))))

(ert-deftest org-ai-skills-build-step-request-includes-source-path-for-stage-routing ()
  "Planner step request should include source path for stage-grounded execution."
  (let* ((step '(:step-id "s1"
                :goal "compose draft"
                :skills ("article-compose-from-outline")
                :expected-output "draft"))
         (run-state '(:task "compose"
                     :subtree (:text "* Article\nBody\n"
                               :source-file-path "./notes/source.md")
                     :latest-output nil))
         (skill '(:skill-id "article-compose-from-outline"
                 :title "Compose"
                 :description "Compose article sections."
                 :outputs ("expanded-org-article-subtree")
                 :contracts ("respect :PURPOSE:")
                 :requirements ("preserve structure")
                 :tags (:effect "pure" :invocation "manual" :context "project" :determinism "heuristic")
                 :raw-sections (:description "Compose article sections.")
                 :function-calls nil))
         (request (org-ai-skills-build-step-request step run-state (list skill))))
    (should (equal (plist-get request :source-file-path) "./notes/source.md"))
    (should (string-match-p "Source file path: \\./notes/source\\.md"
                            (plist-get request :prompt)))))

(ert-deftest org-ai-skills-define-plan-run-preset-command-uses-fixed-task ()
  "Generated preset command should invoke planner with fixed task."
  (let ((command 'org-ai-skills-test--fixed-task-command)
        captured-target
        captured-task
        captured-origin)
    (fmakunbound command)
    (org-ai-skills-define-plan-run-preset-command
     org-ai-skills-test--fixed-task-command
     "Turn subtree into action items")
    (unwind-protect
        (cl-letf (((symbol-function 'org-ai-skills-plan-run)
                   (lambda (target task &optional interactive-origin preset-id)
                     (setq captured-target target)
                     (setq captured-task task)
                     (setq captured-origin interactive-origin)
                     (setq org-ai-skills-test--captured-preset preset-id))))
          (funcall command '(:heading "Leaf"))
          (should (equal captured-target '(:heading "Leaf")))
          (should (string= captured-task "Turn subtree into action items"))
          (should captured-origin)
          (should-not org-ai-skills-test--captured-preset))
      (fmakunbound command))))

(ert-deftest org-ai-skills-load-skill-metadata-returns-meta-only-shape ()
  "Metadata loader should provide planner-safe minimal fields."
  (let* ((meta (car (org-ai-skills-load-skill-metadata
                     (expand-file-name "skills" org-ai-skills-test--project-root)))))
    (should (string= (plist-get meta :skill-id) "gen-notes"))
    (should (stringp (plist-get meta :summary)))
    (should-not (plist-member meta :contracts))
    (should-not (plist-member meta :requirements))
    (should-not (plist-member meta :function-calls))))

(ert-deftest org-ai-skills-build-planner-request-serializes-metadata-array ()
  "Planner request builder should serialize metadata list without json type errors."
  (let* ((metadata (org-ai-skills-load-skill-metadata
                    (expand-file-name "skills" org-ai-skills-test--project-root)))
         (request (org-ai-skills-build-planner-request
                   "Polish this subtree"
                   metadata
                   '(:task "Polish this subtree" :steps nil :plan-revision 1)))
         (prompt (plist-get request :prompt)))
    (should (stringp prompt))
    (should (eq (plist-get request :request-role) 'planner))
    (should (string-match-p "\"skill-id\":\"gen-notes\"" prompt))
    (should (string-match-p "Skill metadata list (JSON):" prompt))))

(ert-deftest org-ai-skills-build-planner-request-uses-compact-metadata-and-min-rules ()
  "Planner request should avoid verbose metadata fields and include minimization rules."
  (let* ((metadata (org-ai-skills-load-skill-metadata
                    (expand-file-name "skills" org-ai-skills-test--project-root)))
         (request (org-ai-skills-build-planner-request
                   "Polish this subtree"
                   metadata
                   '(:task "Polish this subtree" :steps nil :plan-revision 1)))
         (prompt (plist-get request :prompt)))
    (should (string-match-p "Output minimization rules:" prompt))
    (should (string-match-p "Use at most 3 candidates and 2 steps" prompt))
    (should-not (string-match-p "\"file\":" prompt))))

(ert-deftest org-ai-skills-build-planner-request-supports-non-ascii-task ()
  "Planner request prompt should remain valid with non-ASCII task text."
  (let* ((metadata (org-ai-skills-load-skill-metadata
                    (expand-file-name "skills" org-ai-skills-test--project-root)))
         (request (org-ai-skills-build-planner-request
                   "优化和重写我的章节，让他有足够的说服力"
                   metadata
                   '(:task "优化和重写我的章节，让他有足够的说服力"
                     :steps nil
                     :plan-revision 1)))
         (prompt (plist-get request :prompt))
         (payload (list :messages
                        (vector (list :role "user" :content prompt)))))
    (should (multibyte-string-p prompt))
    (should (string-match-p "优化和重写我的章节" prompt))
    (should (stringp (json-serialize payload :null-object :null :false-object :json-false)))))

(ert-deftest org-ai-skills-build-planner-request-handles-completed-step-skill-list ()
  "Planner request should serialize completed step summaries with list skill ids."
  (let* ((metadata (org-ai-skills-load-skill-metadata
                    (expand-file-name "skills" org-ai-skills-test--project-root)))
         (run-state '(:task "优化和重写我的章节，让他有足够的说服力"
                     :plan-revision 1
                     :steps ((:step-id 1
                              :skills ("gen-notes")
                              :goal "Optimize and rewrite"
                              :output "* LLM Skill 在 Org-mode 中的优势"))
                     :latest-output nil))
         (request (org-ai-skills-build-planner-request
                   "优化和重写我的章节，让他有足够的说服力"
                   metadata
                   run-state))
         (prompt (plist-get request :prompt)))
    (should (stringp prompt))
    (should (string-match-p "\"skills\":\\[\"gen-notes\"\\]" prompt))))

(ert-deftest org-ai-skills-parse-planner-response-validates-known-skills ()
  "Planner response parser should reject unknown skill ids."
  (let* ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
         (json "{\"candidates\":[{\"skill_id\":\"unknown\",\"why\":\"x\",\"score\":0.2}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"unknown\"],\"input_from\":[\"task\"],\"expected_output\":\"o\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}"))
    (should-error (org-ai-skills-parse-planner-response json metadata)
                  :type 'org-ai-skills-planner-error)))

(ert-deftest org-ai-skills-parse-planner-response-builds-fallback-for-empty-initial-plan ()
  "Planner parser should build fallback plan from candidates when initial plan is empty."
  (let* ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
         (json "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
         (parsed (org-ai-skills-parse-planner-response json metadata)))
    (should (= (length (plist-get parsed :plan)) 1))
    (should (equal (plist-get (car (plist-get parsed :plan)) :skills)
                   '("gen-notes")))))

(ert-deftest org-ai-skills-parse-planner-response-rejects-empty-plan-without-candidates ()
  "Planner parser should reject empty initial plan when no candidate can seed fallback."
  (let* ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
         (json "{\"candidates\":[],\"plan\":[],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}"))
    (should-error (org-ai-skills-parse-planner-response json metadata)
                  :type 'org-ai-skills-planner-error)))

(ert-deftest org-ai-skills-parse-planner-response-signals-planner-error-on-malformed-json ()
  "Planner parser should surface malformed JSON as planner error."
  (let* ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
         (json "{\"candidates\":[{\"skill_id\":\"gen-notes\"}],\"plan\":["))
    (should-error (org-ai-skills-parse-planner-response json metadata)
                  :type 'org-ai-skills-planner-error)))

(ert-deftest org-ai-skills-extract-json-object-keeps-multiline-root-object ()
  "JSON extractor should keep full multiline object, not stop at first line-ending brace."
  (let* ((json "{\n  \"candidates\": [\n    {\n      \"skill_id\": \"fin-news-daily-report\",\n      \"why\": \"This skill directly addresses the task of generating a daily financial news report.\",\n      \"score\": 1.0\n    }\n  ],\n  \"plan\": [\n    {\n      \"step_id\": \"s1\",\n      \"goal\": \"Generate the daily financial news report.\",\n      \"skills\": [\n        \"fin-news-daily-report\"\n      ],\n      \"input_from\": [],\n      \"expected_output\": \"A polished daily Org report containing financial news.\",\n      \"composition_reason\": \"This is the first and only step needed to fulfill the task.\"\n    }\n  ],\n  \"replan_signal\": {\n    \"enabled\": false,\n    \"condition\": \"\"\n  }\n}")
         (extracted (org-ai-skills--extract-json-object json)))
    (should (stringp extracted))
    (should (string-match-p "\"replan_signal\"" extracted))
    (should (string-match-p "\"condition\"" extracted))
    (should (string-suffix-p "}" (string-trim-right extracted)))))

(ert-deftest org-ai-skills-parse-planner-response-accepts-multiline-json ()
  "Planner parser should accept multiline structured JSON payloads."
  (let* ((metadata (list '(:skill-id "fin-news-daily-report"
                           :title "Financial"
                           :summary "S")))
         (json "{\n  \"candidates\": [\n    {\n      \"skill_id\": \"fin-news-daily-report\",\n      \"why\": \"This skill directly addresses the task of generating a daily financial news report.\",\n      \"score\": 1.0\n    }\n  ],\n  \"plan\": [\n    {\n      \"step_id\": \"s1\",\n      \"goal\": \"Generate the daily financial news report.\",\n      \"skills\": [\n        \"fin-news-daily-report\"\n      ],\n      \"input_from\": [],\n      \"expected_output\": \"A polished daily Org report containing financial news.\",\n      \"composition_reason\": \"This is the first and only step needed to fulfill the task.\"\n    }\n  ],\n  \"replan_signal\": {\n    \"enabled\": false,\n    \"condition\": \"\"\n  }\n}")
         (parsed (org-ai-skills-parse-planner-response json metadata)))
    (should (listp parsed))
    (should (= (length (plist-get parsed :plan)) 1))
    (should (equal (plist-get (car (plist-get parsed :plan)) :skills)
                   '("fin-news-daily-report")))))

(ert-deftest org-ai-skills-find-first-value-recursive-supports-vectors ()
  "Recursive scanner should traverse vectors in provider payloads."
  (let* ((payload '(:choices [(:message (:content "{\"ok\":true}"))]))
         (value (org-ai-skills--find-first-value-recursive payload '(:content) 6)))
    (should (stringp value))
    (should (string-match-p "\"ok\"" value))))

(ert-deftest org-ai-skills-extract-gptel-response-text-from-info-data-choices ()
  "Text extraction should recover content nested in INFO data choices."
  (let ((text (org-ai-skills--extract-gptel-response-text
               nil
               '(:status "HTTP/2 200"
                 :data (:choices [(:message (:content "{\"k\":1}"))])))))
    (should (stringp text))
    (should (string-match-p "\"k\"" text))))

(ert-deftest org-ai-skills-extract-gptel-response-text-ignores-request-message-content ()
  "Text extraction should not read echoed request messages as model output."
  (let ((text (org-ai-skills--extract-gptel-response-text-if-ready
               nil
               '(:status "HTTP/2 200"
                 :data (:messages
                        [(:role "system" :content "planner-system-prompt")
                         (:role "user" :content "planner-user-prompt")])))))
    (should-not text)))

(ert-deftest org-ai-skills-request-planner-plan-fails-on-malformed-json ()
  "Planner request should return fatal run-state when planner JSON is malformed."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (malformed "{\"candidates\":[],\"plan\":[")
        callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback malformed '(:data (:payload t)))
                 (funcall callback t '(:data (:done t)))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (car response))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (_parsed run-state) (setq callback-run-state run-state))))
    (should (stringp (plist-get callback-run-state :fatal-error)))))

(ert-deftest org-ai-skills-request-planner-plan-ignores-echoed-request-metadata-callback ()
  "Planner should ignore metadata-only callback payload before actual model text."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (valid "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"gen-notes\"],\"input_from\":[\"task\"],\"expected_output\":\"o\",\"composition_reason\":\"r\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
        callback-result
        callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback
                          nil
                          '(:status "HTTP/2 200"
                            :data (:messages
                                   [(:role "system" :content "planner-system-prompt")
                                    (:role "user" :content "planner-user-prompt")])))
                 (funcall callback
                          valid
                          '(:status "HTTP/2 200" :stop-reason "stop")))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (parsed run-state)
         (setq callback-result parsed
               callback-run-state run-state))))
    (should-not (plist-get callback-run-state :fatal-error))
    (should (listp callback-result))
    (should (= (length (plist-get callback-result :plan)) 1))))

(ert-deftest org-ai-skills-request-planner-plan-fails-fast-on-http-parse-error-callback ()
  "Planner should fail fast when callback reports HTTP parse error and no text."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback nil '(:status "Could not parse HTTP response.")))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (_parsed run-state)
         (setq callback-run-state run-state))))
    (should (stringp (plist-get callback-run-state :fatal-error)))
    (should (string-match-p "Could not parse HTTP response"
                            (plist-get callback-run-state :fatal-error)))))


(ert-deftest org-ai-skills-request-planner-plan-ignores-reasoning-until-final-text ()
  "Planner request should ignore interim reasoning callbacks until final text arrives."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (valid "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"gen-notes\"],\"input_from\":[\"task\"],\"expected_output\":\"o\",\"composition_reason\":\"r\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
        callback-result)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback '(reasoning . "thinking...") '(:data (:payload t)))
                 (funcall callback valid '(:data (:payload t)))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (let ((first (car response)))
                   (if (and (consp first) (eq (car first) 'reasoning))
                       nil
                     first)))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (parsed _run-state) (setq callback-result parsed))))
    (should (listp callback-result))
    (should (= (length (plist-get callback-result :plan)) 1))))

(ert-deftest org-ai-skills-request-planner-plan-does-not-finalize-on-reasoning-terminal-metadata ()
  "Planner should not finalize when first callback is reasoning with stop metadata."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (valid "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"gen-notes\"],\"input_from\":[\"task\"],\"expected_output\":\"o\",\"composition_reason\":\"r\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
        callback-result)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback '(reasoning . "thinking")
                          '(:status "HTTP/2 200" :stop-reason "stop"))
                 (funcall callback valid
                          '(:status "HTTP/2 200" :stop-reason "stop"))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (let ((first (car response)))
                   (if (and (consp first) (eq (car first) 'reasoning))
                       nil
                     first)))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (parsed _run-state) (setq callback-result parsed))))
    (should (listp callback-result))
    (should (= (length (plist-get callback-result :plan)) 1))))

(ert-deftest org-ai-skills-request-planner-plan-accumulates-chunked-json ()
  "Planner request should accumulate chunked text before JSON parse."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (chunk-1 "{\"candidates\":[{\"skill_id\":\"gen-notes\"")
        (chunk-2 ",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"gen-notes\"],\"input_from\":[\"task\"],\"expected_output\":\"o\",\"composition_reason\":\"r\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
        callback-result)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback chunk-1 '(:data (:payload t)))
                 (funcall callback chunk-2 '(:data (:payload t)))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (car response))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (parsed _run-state) (setq callback-result parsed))))
    (should (listp callback-result))
    (should (= (length (plist-get callback-result :plan)) 1))))

(ert-deftest org-ai-skills-request-planner-plan-does-not-finalize-on-http-status-with-text ()
  "Planner request should keep accumulating when only HTTP status appears with text."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (chunk-1 "{\"candidates\":[{\"skill_id\":\"gen-notes\"")
        (chunk-2 ",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"gen-notes\"],\"input_from\":[\"task\"],\"expected_output\":\"o\",\"composition_reason\":\"r\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
        (count 0)
        callback-result)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (setq count (1+ count))
                 (funcall callback chunk-1 '(:status "HTTP/2 200"))
                 (funcall callback chunk-2 '(:data (:payload t)))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (let ((first (car response)))
                   (and (stringp first) first)))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (parsed _run-state) (setq callback-result parsed))))
    (should (= count 1))
    (should (listp callback-result))
    (should (= (length (plist-get callback-result :plan)) 1))))

(ert-deftest org-ai-skills-request-planner-plan-waits-for-second-stop-reason-text-chunk ()
  "Planner should not fail on first truncated stop-reason chunk when another text chunk follows."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (chunk-1 "{\"candidates\":[{\"skill_id\":\"gen-notes\"")
        (chunk-2 ",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"gen-notes\"],\"input_from\":[\"task\"],\"expected_output\":\"o\",\"composition_reason\":\"r\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
        callback-result
        callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback chunk-1 '(:status "HTTP/2 200" :stop-reason "stop"))
                 (funcall callback chunk-2 '(:status "HTTP/2 200" :stop-reason "stop"))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (let ((first (car response)))
                   (and (stringp first) first)))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (parsed run-state)
         (setq callback-result parsed
               callback-run-state run-state))))
    (should-not (plist-get callback-run-state :fatal-error))
    (should (listp callback-result))
    (should (= (length (plist-get callback-result :plan)) 1))))

(ert-deftest org-ai-skills-request-planner-plan-treats-terminal-text-as-final-when-stream-false ()
  "Planner should treat text callback as final when stop metadata and stream=false are present."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (org-ai-skills-planner-use-streaming nil)
        (org-ai-skills-planner-parse-retries 0)
        (calls nil)
        callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (request callback)
                 (push request calls)
                 (funcall callback
                          "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\"}"
                          '(:status "HTTP/2 200" :stop-reason "stop" :data (:stream :json-false)))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (let ((first (car response)))
                   (and (stringp first) first)))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (_parsed run-state) (setq callback-run-state run-state))))
    (setq calls (nreverse calls))
    (should (= (length calls) 1))
    (should-not (plist-get (car calls) :planner-disable-schema))
    (should (stringp (plist-get callback-run-state :fatal-error)))))

(ert-deftest org-ai-skills-request-planner-plan-streaming-does-not-finalize-on-stop-text ()
  "Streaming planner should not finalize parse on stop-reason text chunks."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (org-ai-skills-planner-use-streaming t)
        (chunk-1 "{\"candidates\":[{\"skill_id\":\"gen-notes\"")
        (chunk-2 ",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"gen-notes\"],\"input_from\":[\"task\"],\"expected_output\":\"o\",\"composition_reason\":\"r\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
        callback-result
        callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback chunk-1 '(:status "HTTP/2 200"
                                              :stop-reason "stop"
                                              :data (:stream :json-false)))
                 (funcall callback chunk-2 '(:status "HTTP/2 200"
                                              :stop-reason "stop"
                                              :data (:stream :json-false)))
                 (funcall callback t '(:status "HTTP/2 200" :stop-reason "stop"))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (let ((first (car response)))
                   (and (stringp first) first)))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (parsed run-state)
         (setq callback-result parsed
               callback-run-state run-state))))
    (should-not (plist-get callback-run-state :fatal-error))
    (should (listp callback-result))
    (should (= (length (plist-get callback-result :plan)) 1))))

(ert-deftest org-ai-skills-request-planner-plan-terminal-text-truncated-does-not-hang ()
  "Planner request should not hang on terminal completion with truncated JSON."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (org-ai-skills-planner-parse-retries 0)
        callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback
                          "{\"candidates\":[{\"skill_id\":\"gen-notes\""
                          '(:status "HTTP/2 200" :stop-reason "stop"))
                 (funcall callback t '(:status "HTTP/2 200" :stop-reason "stop"))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response) (car response))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (_parsed run-state) (setq callback-run-state run-state))))
    (should (stringp (plist-get callback-run-state :fatal-error)))))

(ert-deftest org-ai-skills-request-planner-plan-ignores-no-json-error-until-json-arrives ()
  "Planner request should ignore provisional no-JSON parse error and continue."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (chunk-1 "thinking...")
        (chunk-2 "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"gen-notes\"],\"input_from\":[\"task\"],\"expected_output\":\"o\",\"composition_reason\":\"r\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
        callback-result)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback chunk-1 '(:status "HTTP/2 200" :stop-reason "stop"))
                 (funcall callback chunk-2 '(:data (:payload t)))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response) (car response))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (parsed _run-state) (setq callback-result parsed))))
    (should (listp callback-result))
    (should (= (length (plist-get callback-result :plan)) 1))))

(ert-deftest org-ai-skills-request-planner-plan-salvages-final-json-from-terminal-info ()
  "Planner request should recover from truncated buffer using terminal info text."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (chunk-1 "{\"candidates\":[{\"skill_id\":\"gen-notes\"")
        (valid "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"gen-notes\"],\"input_from\":[\"task\"],\"expected_output\":\"o\",\"composition_reason\":\"r\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
        callback-result)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback chunk-1 '(:data (:payload t)))
                 (funcall callback t `(:stop-reason "stop" :data (:done t :text ,valid)))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response) (car response))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (parsed _run-state) (setq callback-result parsed))))
    (should (listp callback-result))
    (should (= (length (plist-get callback-result :plan)) 1))))

(ert-deftest org-ai-skills-request-planner-plan-does-not-fallback-without-schema-on-terminal-truncation ()
  "Planner request should fail directly on terminal truncated JSON without schema fallback."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (org-ai-skills-planner-parse-retries 0)
        (calls nil)
        callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (request callback)
                 (push request calls)
                 (funcall callback
                          "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\"}"
                          '(:status "HTTP/2 200" :stop-reason "stop"))
                 (funcall callback t '(:status "HTTP/2 200" :stop-reason "stop"))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response) (car response))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (_parsed run-state) (setq callback-run-state run-state))))
    (setq calls (nreverse calls))
    (should (= (length calls) 1))
    (should-not (plist-get (car calls) :planner-disable-schema))
    (should (stringp (plist-get callback-run-state :fatal-error)))))

(ert-deftest org-ai-skills-request-planner-plan-terminal-signal-truncation-without-final-event-waits ()
  "Planner should not fallback/retry on non-final stop-reason text chunks."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (org-ai-skills-planner-parse-retries 0)
        (calls nil)
        callback-run-state
        timer-fn)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (request callback)
                 (push request calls)
                 (funcall callback
                          "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\"}"
                          '(:status "HTTP/2 200" :stop-reason "stop"))))
              ((symbol-function 'run-at-time)
               (lambda (_secs _repeat fn &rest _args)
                 (setq timer-fn fn)
                 'fake-timer))
              ((symbol-function 'cancel-timer)
               (lambda (_timer) nil))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response) (car response))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (_parsed run-state) (setq callback-run-state run-state)))
      (funcall timer-fn))
    (setq calls (nreverse calls))
    (should (= (length calls) 1))
    (should-not (plist-get (car calls) :planner-disable-schema))
    (should (stringp (plist-get callback-run-state :fatal-error)))
    (should (string-match-p "timeout" (downcase (plist-get callback-run-state :fatal-error))))))

(ert-deftest org-ai-skills-request-planner-plan-times-out-without-callback ()
  "Planner request should fail fast when no callback arrives."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (org-ai-skills-planner-request-timeout-seconds 1)
        callback-run-state
        timer-fn)
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request _callback)
                 nil))
              ((symbol-function 'run-at-time)
               (lambda (_secs _repeat fn &rest _args)
                 (setq timer-fn fn)
                 'fake-timer))
              ((symbol-function 'cancel-timer)
               (lambda (_timer) nil)))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1)
       (lambda (_parsed run-state) (setq callback-run-state run-state)))
      (funcall timer-fn))
    (should (stringp (plist-get callback-run-state :fatal-error)))
    (should (string-match-p
             "Planner request timeout"
             (plist-get callback-run-state :fatal-error)))))

(ert-deftest org-ai-skills-request-planner-plan-records-timing-events ()
  "Planner request should append planning timing events into run-state."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (valid "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"gen-notes\"],\"input_from\":[\"task\"],\"expected_output\":\"o\",\"composition_reason\":\"r\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
        callback-run-state
        (ticks '(0.001 0.002 0.004))
        (org-ai-skills-observability-now-function nil))
    (setq org-ai-skills-observability-now-function
          (lambda ()
            (prog1 (or (car ticks) 0.004)
              (setq ticks (cdr ticks)))))
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback
                          valid
                          '(:data (:usage (:prompt_tokens 12
                                           :completion_tokens 8
                                           :total_tokens 20))))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response) (car response))))
      (org-ai-skills--request-planner-plan
       "task"
       metadata
       '(:task "task" :steps nil :plan-revision 1 :events nil)
       (lambda (_parsed run-state) (setq callback-run-state run-state))))
    (let* ((events (plist-get callback-run-state :events))
           (parse-event (car events))
           (call-event (cadr events))
           (request-event (caddr events)))
      (should (= (length events) 3))
      (should (eq (plist-get parse-event :stage-id) 'planning.parse))
      (should (eq (plist-get call-event :stage-id) 'api.call))
      (should (eq (plist-get call-event :request-role) 'planner))
      (should (= (plist-get call-event :call-index) 1))
      (should (eq (plist-get request-event :stage-id) 'planning.request))
      (should (>= (plist-get parse-event :duration-ms) 1))
      (should (>= (plist-get request-event :duration-ms)
                  (plist-get parse-event :duration-ms)))
      (should (equal (plist-get (plist-get parse-event :usage) :input-tokens) 12))
      (should (equal (plist-get (plist-get parse-event :usage) :output-tokens) 8))
      (should (equal (plist-get (plist-get parse-event :usage) :total-tokens) 20))
      (should (equal
               (plist-get
                (plist-get (plist-get callback-run-state :metrics) :usage-totals)
                :total-tokens)
               20)))))

(ert-deftest org-ai-skills-run-task-with-planner-does-not-pass-run-state-as-retry-attempt ()
  "Planner entry call should not pass run-state plist as retry-attempt."
  (let (captured-retry callback-state)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-metadata)
               (lambda (&optional _directory)
                 (list '(:skill-id "gen-notes" :title "Notes" :summary "S"))))
              ((symbol-function 'org-ai-skills--request-planner-plan)
               (lambda (_task _metadata run-state callback &optional retry-attempt)
                 (setq captured-retry retry-attempt)
                 (funcall callback
                          '(:plan ((:step-id "s1"
                                            :skills ("gen-notes")
                                            :goal "g"
                                            :input-from ("task")
                                            :expected-output "o"
                                            :composition-reason "r")))
                          run-state)))
              ((symbol-function 'org-ai-skills--run-plan-steps)
               (lambda (_task _metadata run-state _plan callback &optional _directory)
                 (funcall callback run-state))))
      (org-ai-skills-run-task-with-planner
       "task"
       '(:begin 1 :end 2 :text "* H\n")
       nil
       (lambda (state) (setq callback-state state))))
    (should (null captured-retry))
    (should (listp callback-state))))

(ert-deftest org-ai-skills-execute-plan-step-records-timing-event ()
  "Step execution should append call-level and step-level timing events."
  (let ((ticks '(0.010 0.015))
        callback-run-state
        (org-ai-skills-observability-now-function nil))
    (setq org-ai-skills-observability-now-function
          (lambda ()
            (prog1 (or (car ticks) 0.015)
              (setq ticks (cdr ticks)))))
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (&rest _args) '(:skill-id "gen-notes" :title "Notes")))
              ((symbol-function 'org-ai-skills-apply-skill-function-calls)
               (lambda (&rest _args) nil))
              ((symbol-function 'org-ai-skills-exclude-skill-function-calls)
               (lambda (&rest _args) nil))
              ((symbol-function 'org-ai-skills-build-step-request)
               (lambda (&rest _args)
                 '(:event-type step-execution :request-role execution :step-id "s1" :prompt "p")))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback
                          "* H\nBody\n"
                          '(:data (:usage (:input_tokens 4 :output_tokens 3))))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response) (car response))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :skills ("gen-notes") :goal "g")
       '(:task "task" :subtree (:text "* H\n") :plan-revision 1 :events nil)
       (lambda (run-state _output) (setq callback-run-state run-state))))
    (let* ((events (plist-get callback-run-state :events))
           (call-event (car events))
           (step-event (cadr events)))
      (should (= (length events) 2))
      (should (eq (plist-get call-event :stage-id) 'api.call))
      (should (eq (plist-get call-event :request-role) 'execution))
      (should (= (plist-get call-event :call-index) 1))
      (should (equal (plist-get call-event :step-id) "s1"))
      (should (eq (plist-get step-event :stage-id) 'execution.step))
      (should (equal (plist-get step-event :step-id) "s1"))
      (should (= (plist-get step-event :duration-ms) 5))
      (should (equal
               (plist-get
                (plist-get (plist-get callback-run-state :metrics) :usage-totals)
                :total-tokens)
               7)))))

(ert-deftest org-ai-skills-execute-plan-step-records-tool-call-timing-events ()
  "Step execution should record tool.call timing separate from api.call."
  (let ((ticks '(0.010 0.015 0.020 0.030 0.060))
        callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (&rest _args) '(:skill-id "gen-notes" :title "Notes")))
              ((symbol-function 'org-ai-skills-apply-skill-function-calls)
               (lambda (&rest _args) nil))
              ((symbol-function 'org-ai-skills-exclude-skill-function-calls)
               (lambda (&rest _args) nil))
              ((symbol-function 'org-ai-skills-build-step-request)
               (lambda (&rest _args)
                 '(:event-type step-execution :request-role execution :step-id "s1" :prompt "p")))
              ((symbol-function 'org-ai-skills--observability-now-ms)
               (lambda ()
                 (truncate (* 1000.0
                              (prog1 (or (car ticks) 0.060)
                                (setq ticks (cdr ticks)))))))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback
                          '(tool-call
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:query "q1")))
                          nil)
                 (funcall callback
                          '(tool-result
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:query "q1")
                             "{\"ok\":true}"))
                          nil)
                 (funcall callback "*** Final\nBody\n" nil)))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (let ((first (car response)))
                   (and (stringp first) first)))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :skills ("gen-notes") :goal "g")
       '(:task "task" :subtree (:text "* H\n") :plan-revision 1 :events nil)
       (lambda (run-state _output) (setq callback-run-state run-state))))
    (let* ((events (plist-get callback-run-state :events))
           (tool-event (seq-find (lambda (e) (eq (plist-get e :stage-id) 'tool.call)) events))
           (api-event (seq-find (lambda (e) (eq (plist-get e :stage-id) 'api.call)) events))
           (step-event (seq-find (lambda (e) (eq (plist-get e :stage-id) 'execution.step)) events)))
      (should tool-event)
      (should api-event)
      (should step-event)
      (should (equal (plist-get tool-event :tool-name)
                     "org-ai-skills-search1api-fetch-financial-news-raw"))
      (should (= (plist-get tool-event :call-index) 1))
      (should (> (plist-get tool-event :duration-ms) 0))
      (should (> (plist-get api-event :duration-ms)
                 (plist-get tool-event :duration-ms))))))

(ert-deftest org-ai-skills-execute-plan-step-tool-timing-pairs-when-args-reordered ()
  "Tool timing should pair starts/results even when callback args shape changes."
  (let ((ticks '(0.010 0.015 0.025 0.060))
        callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (&rest _args) '(:skill-id "gen-notes" :title "Notes")))
              ((symbol-function 'org-ai-skills-apply-skill-function-calls)
               (lambda (&rest _args) nil))
              ((symbol-function 'org-ai-skills-exclude-skill-function-calls)
               (lambda (&rest _args) nil))
              ((symbol-function 'org-ai-skills-build-step-request)
               (lambda (&rest _args)
                 '(:event-type step-execution :request-role execution :step-id "s1" :prompt "p")))
              ((symbol-function 'org-ai-skills--observability-now-ms)
               (lambda ()
                 (truncate (* 1000.0
                              (prog1 (or (car ticks) 0.060)
                                (setq ticks (cdr ticks)))))))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback
                          '(tool-call
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:query "q1" :limit "8")))
                          nil)
                 (funcall callback
                          '(tool-result
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:limit "8" :query "q1")
                             "{\"ok\":true}"))
                          nil)
                 (funcall callback "*** Final\nBody\n" nil)))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (let ((first (car response)))
                   (and (stringp first) first)))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :skills ("gen-notes") :goal "g")
       '(:task "task" :subtree (:text "* H\n") :plan-revision 1 :events nil)
       (lambda (run-state _output) (setq callback-run-state run-state))))
    (let* ((events (plist-get callback-run-state :events))
           (tool-events (seq-filter (lambda (e) (eq (plist-get e :stage-id) 'tool.call)) events))
           (tool-event (car tool-events)))
      (should (= (length tool-events) 1))
      (should (eq (plist-get tool-event :status) 'success))
      (should (= (plist-get tool-event :duration-ms) 10)))))

(ert-deftest org-ai-skills-execute-plan-step-fails-on-terminal-without-text ()
  "Execution step should fail explicitly when terminal callback has no text payload."
  (let (callback-run-state timer-fn)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (&rest _args) '(:skill-id "gen-notes" :title "Notes")))
              ((symbol-function 'org-ai-skills-apply-skill-function-calls)
               (lambda (&rest _args) nil))
              ((symbol-function 'org-ai-skills-exclude-skill-function-calls)
               (lambda (&rest _args) nil))
              ((symbol-function 'org-ai-skills-build-step-request)
               (lambda (&rest _args)
                 '(:event-type step-execution :request-role execution :step-id "s1" :prompt "p")))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback t nil)))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (let ((first (car response)))
                   (if (eq first t) nil first))))
              ((symbol-function 'run-at-time)
               (lambda (_secs _repeat fn &rest _args)
                 (setq timer-fn fn)
                 'fake-timer))
              ((symbol-function 'cancel-timer)
               (lambda (_timer) nil)))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :skills ("gen-notes") :goal "g")
       '(:task "task" :subtree (:text "* H\n") :plan-revision 1 :events nil)
       (lambda (run-state _output)
         (setq callback-run-state run-state))))
    (should timer-fn)
    (should (stringp (plist-get callback-run-state :fatal-error)))
    (should (string-match-p "without usable text payload"
                            (plist-get callback-run-state :fatal-error)))))

(ert-deftest org-ai-skills-execute-plan-step-times-out-without-callback ()
  "Execution step should fail explicitly on callback timeout."
  (let ((org-ai-skills-execution-request-timeout-seconds 1)
        callback-run-state
        timer-fn)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (&rest _args) '(:skill-id "gen-notes" :title "Notes")))
              ((symbol-function 'org-ai-skills-apply-skill-function-calls)
               (lambda (&rest _args) nil))
              ((symbol-function 'org-ai-skills-exclude-skill-function-calls)
               (lambda (&rest _args) nil))
              ((symbol-function 'org-ai-skills-build-step-request)
               (lambda (&rest _args)
                 '(:event-type step-execution :request-role execution :step-id "s1" :prompt "p")))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request _callback) nil))
              ((symbol-function 'run-at-time)
               (lambda (_secs _repeat fn &rest _args)
                 (setq timer-fn fn)
                 'fake-timer))
              ((symbol-function 'cancel-timer)
               (lambda (_timer) nil)))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :skills ("gen-notes") :goal "g")
       '(:task "task" :subtree (:text "* H\n") :plan-revision 1 :events nil)
       (lambda (run-state _output)
         (setq callback-run-state run-state)))
      (funcall timer-fn))
    (should (stringp (plist-get callback-run-state :fatal-error)))
    (should (string-match-p "Execution step timeout"
                            (plist-get callback-run-state :fatal-error)))))

(ert-deftest org-ai-skills-execute-plan-step-resets-watchdog-on-tool-progress ()
  "Execution watchdog should reset on non-terminal tool-call progress."
  (let ((org-ai-skills-execution-request-timeout-seconds 1)
        callback-run-state
        (timer-fns (make-hash-table :test 'equal))
        (timer-order nil)
        (canceled nil)
        (timer-id 0))
    (cl-labels
        ((fire-timer (id)
           (unless (member id canceled)
             (let ((fn (gethash id timer-fns)))
               (when (functionp fn)
                 (funcall fn))))))
      (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
                 (lambda (&rest _args) '(:skill-id "gen-notes" :title "Notes")))
                ((symbol-function 'org-ai-skills-apply-skill-function-calls)
                 (lambda (&rest _args) nil))
                ((symbol-function 'org-ai-skills-exclude-skill-function-calls)
                 (lambda (&rest _args) nil))
                ((symbol-function 'org-ai-skills-build-step-request)
                 (lambda (&rest _args)
                   '(:event-type step-execution :request-role execution :step-id "s1" :prompt "p")))
                ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
                 (lambda (_request callback)
                   (funcall callback '(tool-call (:id "tc-1")) nil)))
                ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
                 (lambda (&rest _response) nil))
                ((symbol-function 'run-at-time)
                 (lambda (_secs _repeat fn &rest _args)
                   (let ((id (format "t-%d" (setq timer-id (1+ timer-id)))))
                     (puthash id fn timer-fns)
                     (setq timer-order (append timer-order (list id)))
                     id)))
                ((symbol-function 'cancel-timer)
                 (lambda (timer)
                   (setq canceled (cons timer canceled)))))
        (org-ai-skills-execute-plan-step
         '(:step-id "s1" :skills ("gen-notes") :goal "g")
         '(:task "task" :subtree (:text "* H\n") :plan-revision 1 :events nil)
         (lambda (run-state _output)
           (setq callback-run-state run-state)))
        (should (= (length timer-order) 2))
        (fire-timer (car timer-order))
        (should-not callback-run-state)
        (fire-timer (cadr timer-order))
        (should (stringp (plist-get callback-run-state :fatal-error)))
        (should (string-match-p "Execution step timeout"
                                (plist-get callback-run-state :fatal-error)))))))

(ert-deftest org-ai-skills-request-planner-plan-resets-watchdog-on-progress ()
  "Planner watchdog should reset on non-terminal callback progress."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        callback-run-state
        (timer-fns (make-hash-table :test 'equal))
        (timer-order nil)
        (canceled nil)
        (timer-id 0))
    (cl-labels
        ((fire-timer (id)
           (unless (member id canceled)
             (let ((fn (gethash id timer-fns)))
               (when (functionp fn)
                 (funcall fn))))))
      (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
                 (lambda (_request callback)
                   (funcall callback '(reasoning (:text "thinking")) nil)))
                ((symbol-function 'run-at-time)
                 (lambda (_secs _repeat fn &rest _args)
                   (let ((id (format "p-%d" (setq timer-id (1+ timer-id)))))
                     (puthash id fn timer-fns)
                     (setq timer-order (append timer-order (list id)))
                     id)))
                ((symbol-function 'cancel-timer)
                 (lambda (timer)
                   (setq canceled (cons timer canceled))))
                ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
                 (lambda (&rest _response) nil)))
        (org-ai-skills--request-planner-plan
         "task"
         metadata
         '(:task "task" :steps nil :plan-revision 1 :events nil)
         (lambda (_parsed run-state)
           (setq callback-run-state run-state)))
        (should (= (length timer-order) 2))
        (fire-timer (car timer-order))
        (should-not callback-run-state)
        (fire-timer (cadr timer-order))
        (should (stringp (plist-get callback-run-state :fatal-error)))
        (should (string-match-p "Planner request timeout"
                                (plist-get callback-run-state :fatal-error)))))))

(ert-deftest org-ai-skills-normalize-provider-usage-supports-multiple-key-shapes ()
  "Usage adapter should normalize common provider usage key variants."
  (let* ((shape-a (org-ai-skills--normalize-provider-usage
                   '(:usage (:prompt_tokens 10 :completion_tokens 4 :total_tokens 14 :cost 0.0025))))
         (shape-b (org-ai-skills--normalize-provider-usage
                   '(:input-tokens 3 :output-tokens 2)))
         (shape-c (org-ai-skills--normalize-provider-usage
                   '(:usage (:input_tokens 6 :output_tokens 1)))))
    (should (= (plist-get shape-a :input-tokens) 10))
    (should (= (plist-get shape-a :output-tokens) 4))
    (should (= (plist-get shape-a :total-tokens) 14))
    (should (= (plist-get shape-a :estimated-cost-usd) 0.0025))
    (should (= (plist-get shape-b :total-tokens) 5))
    (should (= (plist-get shape-c :total-tokens) 7))))

(ert-deftest org-ai-skills-normalize-provider-usage-estimates-cost-from-rates ()
  "Usage adapter should estimate cost when provider cost is missing."
  (let ((org-ai-skills-observability-cost-per-1k-input-tokens 0.001)
        (org-ai-skills-observability-cost-per-1k-output-tokens 0.002))
    (let* ((usage (org-ai-skills--normalize-provider-usage
                   '(:usage (:input_tokens 1000 :output_tokens 500))))
           (cost (plist-get usage :estimated-cost-usd)))
      (should (< (abs (- cost 0.002)) 0.000001)))))

(ert-deftest org-ai-skills-normalize-provider-usage-handles-symbol-and-nested-keys ()
  "Usage adapter should parse symbol-key and nested usage payload shapes."
  (let* ((payload-a '((response . ((usage . ((prompt_tokens . 21)
                                             (completion_tokens . 9)
                                             (total_tokens . 30)))))))
         (usage-a (org-ai-skills--normalize-provider-usage payload-a))
         (payload-b '(:data (:usage_metadata (:input_tokens 11 :output_tokens 5))))
         (usage-b (org-ai-skills--normalize-provider-usage payload-b))
         (payload-c '(:data (:prompt_eval_count 14 :eval_count 6)))
         (usage-c (org-ai-skills--normalize-provider-usage payload-c)))
    (should (= (plist-get usage-a :input-tokens) 21))
    (should (= (plist-get usage-a :output-tokens) 9))
    (should (= (plist-get usage-a :total-tokens) 30))
    (should (= (plist-get usage-b :total-tokens) 16))
    (should (= (plist-get usage-c :input-tokens) 14))
    (should (= (plist-get usage-c :output-tokens) 6))
    (should (= (plist-get usage-c :total-tokens) 20))))

(ert-deftest org-ai-skills-normalize-provider-usage-handles-camelcase-and-partial-totals ()
  "Usage adapter should parse camelCase keys and infer totals from partial values."
  (let* ((payload-a '(:usage (:promptTokens 21 :completionTokens 9)))
         (usage-a (org-ai-skills--normalize-provider-usage payload-a))
         (payload-b '(:usage (:completionTokens 17)))
         (usage-b (org-ai-skills--normalize-provider-usage payload-b)))
    (should (= (plist-get usage-a :input-tokens) 21))
    (should (= (plist-get usage-a :output-tokens) 9))
    (should (= (plist-get usage-a :total-tokens) 30))
    (should (= (plist-get usage-b :output-tokens) 17))
    (should (= (plist-get usage-b :total-tokens) 17))))

(ert-deftest org-ai-skills-select-provider-usage-source-prefers-observed-usage ()
  "Provider usage source selector should pick candidate with observable usage."
  (let* ((first '(:content "ok"))
         (info '(:data (:usage (:input_tokens 13 :output_tokens 7))))
         (selected (org-ai-skills--select-provider-usage-source first info nil))
         (usage (org-ai-skills--normalize-provider-usage selected)))
    (should (= (plist-get usage :input-tokens) 13))
    (should (= (plist-get usage :output-tokens) 7))
    (should (= (plist-get usage :total-tokens) 20))))

(ert-deftest org-ai-skills-select-provider-usage-source-prefers-more-complete-signal ()
  "Provider usage source selector should keep the most complete usage payload."
  (let* ((first '(:usage (:completion_tokens 50)))
         (info '(:data (:usage (:prompt_tokens 80 :completion_tokens 50 :total_tokens 130))))
         (selected (org-ai-skills--select-provider-usage-source first info nil))
         (usage (org-ai-skills--normalize-provider-usage selected)))
    (should (= (plist-get usage :input-tokens) 80))
    (should (= (plist-get usage :output-tokens) 50))
    (should (= (plist-get usage :total-tokens) 130))))

(ert-deftest org-ai-skills-parse-planner-response-allows-empty-plan-for-replan ()
  "Planner parser should allow empty plan in replan context."
  (let* ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
         (json "{\"candidates\":[],\"plan\":[],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
         (parsed (org-ai-skills-parse-planner-response json metadata t)))
    (should (equal (plist-get parsed :plan) nil))
    (should-not (plist-get (plist-get parsed :replan-signal) :enabled))))

(ert-deftest org-ai-skills-parse-planner-response-ignores-empty-skill-steps-on-replan ()
  "Replan parser should ignore no-op steps with empty skill list."
  (let* ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
         (json "{\"candidates\":[],\"plan\":[{\"step_id\":3,\"goal\":\"Task complete\",\"skills\":[],\"input_from\":[],\"expected_output\":null,\"composition_reason\":\"done\"}],\"replan_signal\":{\"enabled\":false,\"condition\":null}}")
         (parsed (org-ai-skills-parse-planner-response json metadata t)))
    (should (equal (plist-get parsed :plan) nil))))

(ert-deftest org-ai-skills-parse-planner-response-enforces-skill-limit-reject ()
  "Planner parser should fail when step skill count exceeds configured limit."
  (let* ((org-ai-skills-planner-max-skills-per-step 1)
         (org-ai-skills-planner-overflow-strategy 'reject)
         (metadata (list '(:skill-id "s1")
                         '(:skill-id "s2")))
         (json "{\"candidates\":[],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"s1\",\"s2\"],\"input_from\":[\"task\"],\"expected_output\":\"o\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}"))
    (should-error (org-ai-skills-parse-planner-response json metadata)
                  :type 'org-ai-skills-planner-error)))

(ert-deftest org-ai-skills-parse-planner-response-enforces-skill-limit-split ()
  "Planner parser should auto-split oversized steps when configured."
  (let* ((org-ai-skills-planner-max-skills-per-step 1)
         (org-ai-skills-planner-max-steps 5)
         (org-ai-skills-planner-overflow-strategy 'split)
         (metadata (list '(:skill-id "s1")
                         '(:skill-id "s2")))
         (json "{\"candidates\":[],\"plan\":[{\"step_id\":\"s1\",\"goal\":\"g\",\"skills\":[\"s1\",\"s2\"],\"input_from\":[\"task\"],\"expected_output\":\"o\"}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
         (parsed (org-ai-skills-parse-planner-response json metadata))
         (plan (plist-get parsed :plan)))
    (should (= (length plan) 2))
    (should (equal (plist-get (car plan) :skills) '("s1")))
    (should (equal (plist-get (cadr plan) :skills) '("s2")))))

(ert-deftest org-ai-skills-parse-planner-response-accepts-skill-objects-in-step ()
  "Planner parser should accept step skills as objects with skill_id."
  (let* ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
         (json "{\"candidates\":[{\"skill_id\":\"gen-notes\",\"why\":\"fit\",\"score\":0.9}],\"plan\":[{\"step_id\":1,\"goal\":\"Rewrite\",\"skills\":[{\"skill_id\":\"gen-notes\",\"input_from\":[\"user\"],\"expected_output\":\"out\"}]}],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}")
         (parsed (org-ai-skills-parse-planner-response json metadata))
         (plan (plist-get parsed :plan)))
    (should (= (length plan) 1))
    (should (equal (plist-get (car plan) :skills) '("gen-notes")))))

(ert-deftest org-ai-skills-execute-plan-step-loads-only-selected-skills ()
  "Step execution should lazily load only skills referenced by the step."
  (let (loaded-ids callback-run-state)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (skill-id &optional _directory)
                 (push skill-id loaded-ids)
                 (list :skill-id skill-id
                       :title (format "Skill %s" skill-id)
                       :description "desc"
                       :outputs nil
                       :contracts nil
                       :requirements nil)))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback "*** Result\nBody\n"))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :goal "g" :skills ("alpha" "beta") :expected-output "o")
       '(:task "task" :subtree (:text "*** Input\n"))
       (lambda (run-state _output)
         (setq callback-run-state run-state))))
    (should (equal (sort loaded-ids #'string<) '("alpha" "beta")))
    (should (equal (plist-get (car (plist-get callback-run-state :steps)) :skills)
                   '("alpha" "beta")))))

(ert-deftest org-ai-skills-execute-plan-step-unloads-function-calls-after-callback ()
  "Step execution should unload skill function calls after callback."
  (let ((skill '(:skill-id "fin-news-daily-report"
                :title "Finance"
                :description "desc"
                :function-definitions ("(defun org-ai-skills-search1api-fetch-financial-news-raw (&optional _query _limit _language_hint _date) \"Test fn.\" \"{}\")")
                :function-calls ((:name "org-ai-skills-search1api-fetch-financial-news-raw")))))
    (org-ai-skills-clear-active-skill-functions)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (_skill-id &optional _directory) skill))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (should (org-ai-skills-active-skill-function-calls "fin-news-daily-report"))
                 (funcall callback "*** Result\nBody\n"))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :goal "g" :skills ("fin-news-daily-report") :expected-output "o")
       '(:task "task" :subtree (:text "*** Input\n"))
       (lambda (_run-state _output) nil)))
    (should-not (org-ai-skills-active-skill-function-calls "fin-news-daily-report"))))

(ert-deftest org-ai-skills-execute-plan-step-ignores-tool-events-until-text-response ()
  "Step execution should ignore interim tool callback events and wait for text."
  (let ((skill '(:skill-id "fin-news-daily-report"
                :title "Finance"
                :description "desc"
                :function-definitions ("(defun org-ai-skills-search1api-fetch-financial-news-raw (&optional _query _limit _language_hint _date) \"Test fn.\" \"{}\")")
                :function-calls ((:name "org-ai-skills-search1api-fetch-financial-news-raw"))))
        callback-output
        callback-count)
    (org-ai-skills-clear-active-skill-functions)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (_skill-id &optional _directory) skill))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback '(tool-result ((dummy . t))) '(:data (:dummy t)))
                 (funcall callback "*** Final\nBody\n" '(:data (:dummy t))))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :goal "g" :skills ("fin-news-daily-report") :expected-output "o")
       '(:task "task" :subtree (:text "*** Input\n"))
       (lambda (_run-state output)
         (setq callback-output output)
         (setq callback-count (1+ (or callback-count 0))))))
    (should (= callback-count 1))
    (should (string-match-p "^\\*\\*\\* Final" callback-output))))

(ert-deftest org-ai-skills-extract-tool-result-errors-detects-provider-failure ()
  "Tool-result parser should detect provider failures with error taxonomy."
  (let* ((errors
          (org-ai-skills--extract-tool-result-errors
           '(tool-result
             (dummy-tool
              (:directory "/tmp/demo")
              "(:ok nil :error-kind \"path-not-allowed\" :error-message \"blocked\")"))))
         (first (car errors)))
    (should (= (length errors) 1))
    (should (string= (plist-get first :error-kind) "path-not-allowed"))
    (should (string= (plist-get first :error-message) "blocked"))))

(ert-deftest org-ai-skills-extract-tool-result-errors-detects-function-call-error-string ()
  "Tool-result parser should detect plain org-ai-skills function-call error strings."
  (let* ((errors
          (org-ai-skills--extract-tool-result-errors
           '(tool-result
             (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                            "org-ai-skills-search1api-fetch-financial-news-raw"
                            "desc" nil nil "org-ai-skills" nil t)
              (:query "q")
              "org-ai-skills-function-call-error Search1API request failed: no response buffer"))))
         (first (car errors)))
    (should (= (length errors) 1))
    (should (string= (plist-get first :error-kind) "function-call-error"))
    (should (string-match-p "no response buffer"
                            (plist-get first :error-message)))))

(ert-deftest org-ai-skills-execute-plan-step-fails-fast-on-provider-tool-error ()
  "Planner step should return fatal error state when provider tool call fails."
  (let (callback-run-state callback-output)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (skill-id &optional _directory)
                 (list :skill-id skill-id :title "Skill" :description "desc")))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback
                          '(tool-result
                            (dummy-tool
                             (:directory "/blocked")
                             "(:ok nil :error-kind \"path-not-allowed\" :error-message \"blocked\")")))
                 (funcall callback t nil))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :goal "g" :skills ("alpha") :expected-output "o")
       '(:task "task" :subtree (:text "*** Input\n"))
       (lambda (run-state output)
         (setq callback-run-state run-state)
         (setq callback-output output))))
    (should (stringp (plist-get callback-run-state :fatal-error)))
    (should-not (plist-get callback-run-state :steps))
    (should-not callback-output)))

(ert-deftest org-ai-skills-execute-plan-step-fails-fast-on-function-call-error-string ()
  "Planner step should fail fast when tool-result carries function-call error string."
  (let (callback-run-state callback-output)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (skill-id &optional _directory)
                 (list :skill-id skill-id :title "Skill" :description "desc")))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback
                          '(tool-result
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:query "q")
                             "org-ai-skills-function-call-error Search1API request failed: no response buffer")))
                 (funcall callback t nil))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :goal "g" :skills ("alpha") :expected-output "o")
       '(:task "task" :subtree (:text "*** Input\n"))
       (lambda (run-state output)
         (setq callback-run-state run-state)
         (setq callback-output output))))
    (should (stringp (plist-get callback-run-state :fatal-error)))
    (should (string-match-p "function-call-error"
                            (plist-get callback-run-state :fatal-error)))
    (should-not (plist-get callback-run-state :steps))
    (should-not callback-output)))

(ert-deftest org-ai-skills-execute-plan-step-allows-recovered-tool-result-after-error ()
  "Execution should continue when a tool error is later recovered by success result."
  (let (callback-run-state callback-output)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (skill-id &optional _directory)
                 (list :skill-id skill-id :title "Skill" :description "desc")))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 ;; First tool attempt fails.
                 (funcall callback
                          '(tool-result
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:query "q1")
                             "org-ai-skills-function-call-error Search1API request failed: no response buffer")))
                 ;; Later tool attempt succeeds and clears pending error.
                 (funcall callback
                          '(tool-result
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:query "q2")
                             "{\"count\":8,\"items\":[{\"title\":\"ok\"}]}")))
                 (funcall callback "*** Final\nRecovered output\n"))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :goal "g" :skills ("alpha") :expected-output "o")
       '(:task "task" :subtree (:text "*** Input\n"))
       (lambda (run-state output)
         (setq callback-run-state run-state)
         (setq callback-output output))))
    (should-not (plist-get callback-run-state :fatal-error))
    (should (stringp callback-output))
    (should (string-match-p "Recovered output" callback-output))))

(ert-deftest org-ai-skills-execute-plan-step-does-not-fail-on-nonterminal-text-before-tool-recovery ()
  "Execution should not fail early when text arrives before tool error is recovered."
  (let (callback-run-state callback-output)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (skill-id &optional _directory)
                 (list :skill-id skill-id :title "Skill" :description "desc")))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 ;; First tool attempt fails.
                 (funcall callback
                          '(tool-result
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:query "q1")
                             "org-ai-skills-function-call-error Search1API request failed: no response buffer")))
                 ;; Non-terminal text arrives while retry is still in progress.
                 (funcall callback "Interim draft text chunk")
                 ;; Later tool attempt succeeds and clears pending error.
                 (funcall callback
                          '(tool-result
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:query "q2")
                             "{\"count\":8,\"items\":[{\"title\":\"ok\"}]}")))
                 ;; Final text should now succeed.
                 (funcall callback "*** Final\nRecovered output\n"))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :goal "g" :skills ("alpha") :expected-output "o")
       '(:task "task" :subtree (:text "*** Input\n"))
       (lambda (run-state output)
         (setq callback-run-state run-state)
         (setq callback-output output))))
    (should-not (plist-get callback-run-state :fatal-error))
    (should (stringp callback-output))
    (should (string-match-p "Recovered output" callback-output))))

(ert-deftest org-ai-skills-execute-plan-step-ignores-terminal-metadata-on-tool-result-events ()
  "Execution should not treat tool-result callbacks as terminal via INFO stop-reason."
  (let (callback-run-state callback-output)
    (cl-letf (((symbol-function 'org-ai-skills-load-skill-by-id)
               (lambda (skill-id &optional _directory)
                 (list :skill-id skill-id :title "Skill" :description "desc")))
              ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 ;; Backend emits stop-reason on non-terminal tool-result callback.
                 (funcall callback
                          '(tool-result
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:query "q1")
                             "org-ai-skills-function-call-error Search1API request failed: no response buffer"))
                          '(:status "HTTP/2 200" :stop-reason "stop"))
                 ;; Recovery arrives later.
                 (funcall callback
                          '(tool-result
                            (#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                                           "org-ai-skills-search1api-fetch-financial-news-raw"
                                           "desc" nil nil "org-ai-skills" nil t)
                             (:query "q2")
                             "{\"count\":8,\"items\":[{\"title\":\"ok\"}]}"))
                          '(:status "HTTP/2 200" :stop-reason "stop"))
                 (funcall callback "*** Final\nRecovered output\n"
                          '(:status "HTTP/2 200" :stop-reason "stop")))))
      (org-ai-skills-execute-plan-step
       '(:step-id "s1" :goal "g" :skills ("alpha") :expected-output "o")
       '(:task "task" :subtree (:text "*** Input\n"))
       (lambda (run-state output)
         (setq callback-run-state run-state)
         (setq callback-output output))))
    (should-not (plist-get callback-run-state :fatal-error))
    (should (stringp callback-output))
    (should (string-match-p "Recovered output" callback-output))))

(ert-deftest org-ai-skills-tool-name-from-result-item-normalizes-symbol-and-string ()
  "Tool-name extraction should always return normalized string keys."
  (should
   (string=
    (org-ai-skills--tool-name-from-result-item
     '((gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                   "org-ai-skills-search1api-fetch-financial-news-raw"
                   "desc" nil nil "org-ai-skills" nil t)
       (:query "q")
       "ok"))
    "org-ai-skills-search1api-fetch-financial-news-raw"))
  (should
   (string=
    (org-ai-skills--tool-name-from-result-item
     '(#s(gptel-tool org-ai-skills-search1api-fetch-financial-news-raw
                     "org-ai-skills-search1api-fetch-financial-news-raw"
                     "desc" nil nil "org-ai-skills" nil t)
       (:query "q")
       "ok"))
    "org-ai-skills-search1api-fetch-financial-news-raw")))

(ert-deftest org-ai-skills-rewrite-fails-fast-on-provider-tool-error ()
  "Rewrite flow should fail and not apply content after provider tool errors."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir)
              (org-ai-skills-auto-apply-generated-candidate t)
              (applied nil)
              (statuses nil))
          (with-temp-buffer
            (org-mode)
            (insert "* Leaf\nOriginal body.\n")
            (goto-char (point-min))
            (let ((subtree (org-ai-skills-org-resolve-subtree 'current)))
              (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
                         (lambda (_request callback)
                           (funcall callback
                                    '(tool-result
                                      (dummy-tool
                                       (:directory "/blocked")
                                       "(:ok nil :error-kind \"path-not-allowed\" :error-message \"blocked\")")))
                           (funcall callback "*** Leaf\nRewritten body.\n")))
                        ((symbol-function 'org-ai-skills-org-apply-candidate-to-subtree)
                         (lambda (&rest _args) (setq applied t)))
                        ((symbol-function 'org-ai-skills--ui-set-status)
                         (lambda (status progress)
                           (push (list status progress) statuses)))
                        ((symbol-function 'org-ai-skills--ui-clear-overlay)
                         (lambda () nil)))
                (org-ai-skills-org-rewrite-subtree subtree skill "Rewrite now")))
            (goto-char (point-min))
            (should (re-search-forward "Original body\\." nil t))
            (should-not applied)
            (should (member '(failed "tool-error") statuses))))
      (delete-directory store-dir t))))

(ert-deftest org-ai-skills-gptel-dispatch-registers-request-tools ()
  "Dispatch should register request-scoped function calls as gptel tools."
  (let ((org-ai-skills-debug-enabled nil)
        (org-ai-skills-enable-core-read-tools nil)
        (org-ai-skills-enable-core-provider-tools nil)
        (gptel-use-tools nil)
        (gptel-tools nil)
        (captured-use-tools nil)
        (captured-tools nil)
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel) t (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (memq symbol '(gptel-request gptel-make-tool))
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'org-ai-skills-sample-tool)
               (lambda (&optional _query) "ok"))
              ((symbol-function 'gptel-make-tool)
               (lambda (&rest slots) slots))
              ((symbol-function 'gptel-request)
               (lambda (&rest args)
                 (setq captured-use-tools gptel-use-tools)
                 (setq captured-tools gptel-tools)
                 (let ((callback (plist-get (cdr args) :callback)))
                   (funcall callback "*** Result\nBody\n" (list :data '(:payload t))))
                 t)))
      (org-ai-skills-gptel-dispatch-rewrite
       '(:prompt "hello"
         :skill-context (:function-calls ((:name "org-ai-skills-sample-tool"
                                           :args "(query)"
                                           :when "when needed"))))
       #'ignore))
    (should captured-use-tools)
    (should (= (length captured-tools) 1))))

(ert-deftest org-ai-skills-gptel-dispatch-planner-does-not-register-tools ()
  "Planner dispatch should not expose gptel tools."
  (let ((org-ai-skills-debug-enabled nil)
        (gptel-use-tools nil)
        (gptel-tools nil)
        (captured-use-tools nil)
        (captured-tools nil)
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel) t (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (memq symbol '(gptel-request gptel-make-tool))
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-make-tool)
               (lambda (&rest slots) slots))
              ((symbol-function 'gptel-request)
               (lambda (&rest args)
                 (setq captured-use-tools gptel-use-tools)
                 (setq captured-tools gptel-tools)
                 (let ((callback (plist-get (cdr args) :callback)))
                   (funcall callback "{\"candidates\":[],\"plan\":[],\"replan_signal\":{\"enabled\":false,\"condition\":\"\"}}"
                            (list :data '(:payload t))))
                 t)))
      (org-ai-skills-gptel-dispatch-rewrite
       '(:event-type planner
         :request-role planner
         :prompt "planner")
       #'ignore))
    (should-not captured-use-tools)
    (should-not captured-tools)))

(ert-deftest org-ai-skills-build-gptel-rewrite-request-tags-execution-role ()
  "Rewrite request builder should annotate execution request role."
  (let* ((skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file))
         (subtree '(:heading "Leaf"
                    :context-mode current
                    :levels-up 0
                    :path "Top/Leaf"
                    :text "*** Leaf\nBody\n"))
         (request (org-ai-skills-build-gptel-rewrite-request
                   skill subtree "Rewrite now")))
    (should (eq (plist-get request :request-role) 'execution))
    (should (eq (plist-get request :event-type) 'rewrite))))

(ert-deftest org-ai-skills-gptel-dispatch-routes-role-model-and-system-prompt ()
  "Dispatch should route model/system prompt by planner vs execution roles."
  (let ((org-ai-skills-model-planner 'planner-model)
        (org-ai-skills-model-execution 'exec-model)
        (org-ai-skills-system-prompt-planner "planner system")
        (org-ai-skills-system-prompt-execution "execution system")
        captured
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     t
                   (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request)
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest args)
                 (push (list :args (cdr args) :model gptel-model) captured)
                 t)))
      (org-ai-skills-gptel-dispatch-rewrite
       '(:prompt "plan" :request-role planner)
       #'ignore)
      (org-ai-skills-gptel-dispatch-rewrite
       '(:prompt "exec" :request-role execution)
       #'ignore))
    (let* ((exec-call (car captured))
           (planner-call (cadr captured))
           (exec-args (plist-get exec-call :args))
           (planner-args (plist-get planner-call :args)))
      (should (eq (plist-get planner-call :model) 'planner-model))
      (should (string= (plist-get planner-args :system) "planner system"))
      (should (eq (plist-get exec-call :model) 'exec-model))
      (should (string= (plist-get exec-args :system) "execution system")))))

(ert-deftest org-ai-skills-gptel-dispatch-omits-model-when-role-model-is-nil ()
  "Dispatch should preserve ambient gptel-model when role model override is nil."
  (let ((org-ai-skills-model-execution nil)
        (org-ai-skills-system-prompt-execution "execution system")
        captured-args
        captured-model
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     t
                   (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request)
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest args)
                 (setq captured-args (cdr args))
                 (setq captured-model gptel-model)
                 t)))
      (let ((gptel-model 'ambient-model))
        (org-ai-skills-gptel-dispatch-rewrite
         '(:prompt "exec" :request-role execution)
         #'ignore)))
    (should (string= (plist-get captured-args :system) "execution system"))
    (should (eq captured-model 'ambient-model))))

(ert-deftest org-ai-skills-gptel-dispatch-planner-applies-generation-settings ()
  "Planner dispatch should apply planner-specific temperature and max tokens."
  (let ((org-ai-skills-planner-temperature 0.0)
        (org-ai-skills-planner-max-tokens 2048)
        captured-temperature
        captured-max-tokens
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     t
                   (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request)
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest _args)
                 (setq captured-temperature gptel-temperature)
                 (setq captured-max-tokens gptel-max-tokens)
                 t)))
      (org-ai-skills-gptel-dispatch-rewrite
       '(:prompt "plan" :request-role planner)
       #'ignore))
    (should (equal captured-temperature 0.0))
    (should (equal captured-max-tokens 2048))))

(ert-deftest org-ai-skills-gptel-dispatch-planner-disables-reasoning ()
  "Planner dispatch should force-disable reasoning in state and request params."
  (let ((org-ai-skills-gptel-request-params
         '(:include-reasoning t :include_reasoning t :reasoning (:effort "high") :foo "bar"))
        (org-ai-skills-planner-use-streaming t)
        captured-args
        captured-request-params
        captured-include-reasoning
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     t
                   (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request)
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest args)
                 (setq captured-args (cdr args))
                 (setq captured-request-params gptel--request-params)
                 (setq captured-include-reasoning gptel-include-reasoning)
                 t)))
      (org-ai-skills-gptel-dispatch-rewrite
       '(:prompt "plan" :request-role planner)
       #'ignore))
    (should (eq (plist-get captured-args :stream) t))
    (should (eq captured-include-reasoning nil))
    (should-not (plist-member captured-request-params :include-reasoning))
    (should (eq (plist-get captured-request-params :include_reasoning) :json-false))
    (should (equal (plist-get captured-request-params :reasoning)
                   '(:exclude t)))
    (should (string= (plist-get captured-request-params :foo) "bar"))))

(ert-deftest org-ai-skills-gptel-dispatch-planner-includes-structured-schema ()
  "Planner dispatch should include :schema for structured output."
  (let (captured-args
        (org-ai-skills-planner-schema-mode 'strict)
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     t
                   (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request)
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest args)
                 (setq captured-args (cdr args))
                 t)))
      (org-ai-skills-gptel-dispatch-rewrite
       '(:prompt "plan" :request-role planner)
       #'ignore))
    (should (plist-member captured-args :schema))
    (should (equal (plist-get (plist-get captured-args :schema) :type) "object"))))

(ert-deftest org-ai-skills-gptel-dispatch-rewrite-provides-live-request-buffer ()
  "Dispatch should pass dedicated live :buffer/:position to gptel."
  (let (captured-args
        captured-callback
        dispatch-buffer
        source-buffer
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     t
                   (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request)
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest args)
                 (setq captured-args (cdr args))
                 (setq captured-callback (plist-get captured-args :callback))
                 t)))
      (setq source-buffer (generate-new-buffer " *org-ai-skills-test-source*"))
      (with-current-buffer source-buffer
        (insert "* H\nBody\n"))
      (org-ai-skills-gptel-dispatch-rewrite
       (list :prompt "exec"
             :request-role 'execution
             :source-buffer source-buffer
             :source-text "* H\nBody\n")
       #'ignore)
      (setq dispatch-buffer (plist-get captured-args :buffer))
      (should (bufferp dispatch-buffer))
      (should (buffer-live-p dispatch-buffer))
      (should (markerp (plist-get captured-args :position)))
      (should (eq (marker-buffer (plist-get captured-args :position))
                  dispatch-buffer))
      (with-current-buffer dispatch-buffer
        (should (string-match-p "Body" (buffer-string))))
      ;; Source buffer can disappear without invalidating callback buffer.
      (when (buffer-live-p source-buffer)
        (kill-buffer source-buffer))
      (funcall captured-callback t nil)
      (should-not (buffer-live-p dispatch-buffer)))))

(ert-deftest org-ai-skills-gptel-dispatch-planner-auto-mode-keeps-schema-for-gemini ()
  "Planner dispatch should keep schema enabled for Gemini in auto mode."
  (let (captured-args
        (org-ai-skills-planner-schema-mode 'auto)
        (org-ai-skills-model-planner "google/gemini-2.5-flash-lite")
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     t
                   (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request)
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest args)
                 (setq captured-args (cdr args))
                 t)))
      (org-ai-skills-gptel-dispatch-rewrite
       '(:prompt "plan" :request-role planner)
       #'ignore))
    (should (plist-member captured-args :schema))
    (should (equal (plist-get (plist-get captured-args :schema) :type) "object"))))

(ert-deftest org-ai-skills-gptel-dispatch-execution-keeps-default-generation-settings ()
  "Execution dispatch should not override ambient gptel generation settings."
  (let ((org-ai-skills-planner-temperature 0.0)
        (org-ai-skills-planner-max-tokens 2048)
        captured-temperature
        captured-max-tokens
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     t
                   (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request)
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest _args)
                 (setq captured-temperature gptel-temperature)
                 (setq captured-max-tokens gptel-max-tokens)
                 t)))
      (let ((gptel-temperature 0.7)
            (gptel-max-tokens 512))
        (org-ai-skills-gptel-dispatch-rewrite
         '(:prompt "exec" :request-role execution)
         #'ignore)))
    (should (equal captured-temperature 0.7))
    (should (equal captured-max-tokens 512))))

(ert-deftest org-ai-skills-gptel-dispatch-falls-back-to-default-system-prompt-when-empty ()
  "Dispatch should use default system prompt when configured system prompt is empty."
  (let ((org-ai-skills-system-prompt-execution "")
        captured-args
        (orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     t
                   (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request)
                     t
                   (funcall orig-fboundp symbol))))
              ((symbol-function 'gptel-request)
               (lambda (&rest args)
                 (setq captured-args (cdr args))
                 t)))
      (org-ai-skills-gptel-dispatch-rewrite
       '(:prompt "exec" :request-role execution)
       #'ignore))
    (should (string= (plist-get captured-args :system)
                     org-ai-skills--default-system-prompt-execution))))

(ert-deftest org-ai-skills-gptel-dispatch-errors-on-unsupported-request-role ()
  "Dispatch should reject unsupported request role values."
  (let ((orig-featurep (symbol-function 'featurep))
        (orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (if (eq feature 'gptel)
                     t
                   (funcall orig-featurep feature))))
              ((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'gptel-request)
                     t
                   (funcall orig-fboundp symbol)))))
      (should-error
       (org-ai-skills-gptel-dispatch-rewrite
        '(:prompt "bad" :request-role unknown-role)
        #'ignore)
       :type 'org-ai-skills-gptel-error))))

(ert-deftest org-ai-skills-function-call-to-gptel-tool-prefers-skill-arg-hints ()
  "Tool arg descriptions should use per-argument hints from skill spec."
  (cl-letf (((symbol-function 'org-ai-skills-sample-tool)
             (lambda (&optional _query _limit) "ok"))
            ((symbol-function 'gptel-make-tool)
             (lambda (&rest slots) slots)))
    (let* ((tool (org-ai-skills--function-call-to-gptel-tool
                  '(:name "org-ai-skills-sample-tool"
                    :args "(query limit)"
                    :query "Topic query text"
                    :limit "Result count limit")))
           (args (plist-get tool :args))
           (query-arg (seq-find (lambda (a) (equal (plist-get a :name) "query")) args))
           (limit-arg (seq-find (lambda (a) (equal (plist-get a :name) "limit")) args)))
      (should (string= (plist-get query-arg :description) "Topic query text"))
      (should (string= (plist-get limit-arg :description) "Result count limit")))))

(ert-deftest org-ai-skills-maybe-replan-enforces-max-replans ()
  "Replan helper should stop when max replan count is reached."
  (let ((org-ai-skills-planner-max-replans 1))
    (should-error
     (org-ai-skills-maybe-replan
      '(:replans 1 :latest-output "[[REPLAN]]")
      '(:replan-signal (:enabled t) :plan ((:step-id "s2" :skills ("gen-notes")))))
     :type 'org-ai-skills-planner-error)))

(ert-deftest org-ai-skills-should-request-replan-p-marker-or-boundary ()
  "Replan predicate should gate intermediate steps unless marker/boundary is present."
  (let ((org-ai-skills-planner-auto-replan t)
        (org-ai-skills-planner-replan-trigger 'marker-or-boundary))
    (should-not
     (org-ai-skills--should-request-replan-p
      '(:latest-output "*** output")
      '((:step-id "s2"))))
    (should
     (org-ai-skills--should-request-replan-p
      '(:latest-output "*** output")
      nil))
    (should
     (org-ai-skills--should-request-replan-p
      '(:latest-output "*** output [[REPLAN]]")
      '((:step-id "s2"))))))

(ert-deftest org-ai-skills-run-plan-steps-replans-only-at-boundary-by-default ()
  "Step runner should avoid intermediate planner requests with marker-or-boundary trigger."
  (let ((org-ai-skills-planner-auto-replan t)
        (org-ai-skills-planner-replan-trigger 'marker-or-boundary)
        (planner-calls 0)
        final-state)
    (cl-letf (((symbol-function 'org-ai-skills-execute-plan-step)
               (lambda (step run-state callback &optional _directory)
                 (let* ((step-id (plist-get step :step-id))
                        (output (format "*** output-%s" step-id))
                        (entry (list :step-id step-id
                                     :status 'success
                                     :skills (plist-get step :skills)
                                     :output output))
                        (next-state (plist-put
                                     (plist-put run-state
                                                :steps
                                                (append (or (plist-get run-state :steps) nil)
                                                        (list entry)))
                                     :latest-output output)))
                   (funcall callback next-state output))))
              ((symbol-function 'org-ai-skills--request-planner-plan)
               (lambda (_task _metadata run-state callback &optional _retry-attempt)
                 (setq planner-calls (1+ planner-calls))
                 (funcall callback
                          '(:replan-signal (:enabled nil) :plan nil)
                          run-state))))
      (org-ai-skills--run-plan-steps
       "task"
       nil
       '(:run-id "r1" :task "task" :steps nil :latest-output nil :plan-revision 1 :replans 0)
       '((:step-id "s1" :skills ("a"))
         (:step-id "s2" :skills ("b")))
       (lambda (run-state) (setq final-state run-state))))
    (should (= planner-calls 1))
    (should (= (length (plist-get final-state :steps)) 2))))

(ert-deftest org-ai-skills-run-plan-steps-marker-only-triggers-on-marker ()
  "Marker-only trigger should request planner only when latest output includes [[REPLAN]]."
  (let ((org-ai-skills-planner-auto-replan t)
        (org-ai-skills-planner-replan-trigger 'marker-only)
        (planner-calls 0)
        final-state)
    (cl-letf (((symbol-function 'org-ai-skills-execute-plan-step)
               (lambda (step run-state callback &optional _directory)
                 (let* ((step-id (plist-get step :step-id))
                        (output (if (equal step-id "s1")
                                    "*** output-s1 [[REPLAN]]"
                                  "*** output-s2"))
                        (entry (list :step-id step-id
                                     :status 'success
                                     :skills (plist-get step :skills)
                                     :output output))
                        (next-state (plist-put
                                     (plist-put run-state
                                                :steps
                                                (append (or (plist-get run-state :steps) nil)
                                                        (list entry)))
                                     :latest-output output)))
                   (funcall callback next-state output))))
              ((symbol-function 'org-ai-skills--request-planner-plan)
               (lambda (_task _metadata run-state callback &optional _retry-attempt)
                 (setq planner-calls (1+ planner-calls))
                 (funcall callback
                          '(:replan-signal (:enabled nil) :plan nil)
                          run-state))))
      (org-ai-skills--run-plan-steps
       "task"
       nil
       '(:run-id "r2" :task "task" :steps nil :latest-output nil :plan-revision 1 :replans 0)
       '((:step-id "s1" :skills ("a"))
         (:step-id "s2" :skills ("b")))
       (lambda (run-state) (setq final-state run-state))))
    (should (= planner-calls 1))
    (should (= (length (plist-get final-state :steps)) 2))))

(ert-deftest org-ai-skills-org-src-block-at-point-resolves-parent-block ()
  "Src block resolver should work when point is inside block body."
  (with-temp-buffer
    (org-mode)
    (insert "* Demo\n#+begin_src sh\necho hello\n#+end_src\n")
    (goto-char (point-min))
    (search-forward "echo hello")
    (let ((block (org-ai-skills-org-src-block-at-point)))
      (should (equal (plist-get block :language) "sh"))
      (should (string-match-p "echo hello" (plist-get block :body))))))

(ert-deftest org-ai-skills-org-execute-src-block-shell-success ()
  "Shell src block execution should return captured stdout and success status."
  (with-temp-buffer
    (org-mode)
    (insert "* Demo\n#+begin_src sh\necho run-ok\n#+end_src\n")
    (goto-char (point-min))
    (search-forward "echo run-ok")
    (let ((result (org-ai-skills-org-execute-src-block
                   nil nil nil 1 nil)))
      (should (eq (plist-get result :status) 'success))
      (should (= (plist-get result :exit-code) 0))
      (should (string-match-p "run-ok" (plist-get result :stdout))))))

(ert-deftest org-ai-skills-org-execute-src-block-shell-failure ()
  "Shell src block execution should report non-zero exit as failure."
  (with-temp-buffer
    (org-mode)
    (insert "* Demo\n#+begin_src sh\nexit 7\n#+end_src\n")
    (goto-char (point-min))
    (search-forward "exit 7")
    (let ((result (org-ai-skills-org-execute-src-block
                   nil nil nil 1 nil)))
      (should (eq (plist-get result :status) 'failed))
      (should (= (plist-get result :exit-code) 7))
      (should-not (plist-get result :meets-prompt)))))

(ert-deftest org-ai-skills-org-execute-src-block-appends-metadata-comment ()
  "Execution with metadata enabled should append an Org comment block."
  (with-temp-buffer
    (org-mode)
    (insert "* Demo\n#+begin_src sh\necho run-ok\n#+end_src\n")
    (goto-char (point-min))
    (search-forward "echo run-ok")
    (org-ai-skills-org-execute-src-block nil nil nil 1 t)
    (goto-char (point-min))
    (should (search-forward "org-ai-skills execution metadata" nil t))
    (should (search-forward "#+END_COMMENT" nil t))))

(ert-deftest org-ai-skills-org-run-src-block-auto-debug-repairs-prompt-mismatch ()
  "Auto debug should repair and rerun when output does not meet prompt evaluation."
  (with-temp-buffer
    (org-mode)
    (insert "* Demo\n#+begin_src sh\necho wrong\n#+end_src\n")
    (goto-char (point-min))
    (search-forward "echo wrong")
    (let* ((evaluator
            (lambda (result _prompt)
              (if (string-match-p "right" (or (plist-get result :stdout) ""))
                  '(:ok t :reason "")
                '(:ok nil :reason "missing target output"))))
           (repair-fn
            (lambda (_context) "echo right"))
           (summary
            (org-ai-skills-org-run-src-block-auto-debug
             "must print right"
             repair-fn
             nil
             evaluator
             '(:max-retries 2 :apply-fixes t :append-metadata nil)))
           (final-result (plist-get summary :final-result))
           (final-block (org-ai-skills-org-src-block-at-point)))
      (should (eq (plist-get summary :status) 'success))
      (should (= (plist-get summary :attempt-count) 2))
      (should (eq (plist-get final-result :status) 'success))
      (should (string-match-p "echo right" (plist-get final-block :body))))))

(ert-deftest org-ai-skills-org-run-src-block-auto-debug-errors-on-invalid-repair ()
  "Auto debug should fail fast when repair function returns empty body."
  (with-temp-buffer
    (org-mode)
    (insert "* Demo\n#+begin_src sh\nexit 1\n#+end_src\n")
    (goto-char (point-min))
    (search-forward "exit 1")
    (should-error
     (org-ai-skills-org-run-src-block-auto-debug
      "must pass"
      (lambda (_context) "")
      nil nil
      '(:max-retries 2 :apply-fixes nil :append-metadata nil))
     :type 'org-ai-skills-execution-error)))

(ert-deftest org-ai-skills-bdd-parse-file-collects-gwt-steps ()
  "BDD parser should preserve Given/When/Then step phases."
  (let* ((file (expand-file-name "tests/bdd/001-twitter-shorten-subtree.org"
                                  org-ai-skills-test--project-root))
         (scenario (org-ai-skills-bdd-parse-file file))
         (steps (plist-get scenario :steps)))
    (should (string-match-p "BDD 001" (plist-get scenario :title)))
    (should (seq-find (lambda (step)
                        (and (eq (plist-get step :phase) 'given)
                             (string-match-p "target heading" (plist-get step :text))))
                      steps))
    (should (seq-find (lambda (step)
                        (and (eq (plist-get step :phase) 'when)
                             (string-match-p "org-ai-skills-org-rewrite-subtree"
                                             (plist-get step :text))))
                      steps))
    (should (seq-find (lambda (step)
                        (and (eq (plist-get step :phase) 'then)
                             (string-match-p "effective model should be"
                                             (plist-get step :text))))
                      steps))))

(ert-deftest org-ai-skills-bdd-parse-file-collects-scenario-properties ()
  "BDD parser should expose scenario property drawer entries."
  (let* ((file (expand-file-name "tests/bdd/000-template.org"
                                 org-ai-skills-test--project-root))
         (scenario (org-ai-skills-bdd-parse-file file))
         (props (plist-get scenario :scenario-properties)))
    (should (equal "bdd-xxx" (cdr (assoc "SCENARIO_ID" props))))
    (should (equal "p2" (cdr (assoc "PRIORITY" props))))))

(ert-deftest org-ai-skills-bdd-assertions-support-status-one-of ()
  "BDD assertions should support `run status should be one of ...` grammar."
  (let* ((steps (list (list :phase 'then
                            :text "run status should be one of \"applied,success,done\"")))
         (result (org-ai-skills-bdd--assertions-from-steps
                  steps
                  'applied
                  "Heading"
                  "* Heading\nBody"
                  ""
                  "Execution DAG"
                  "qwen/qwen3-8b"
                  "* Heading\nFixture"))
         (passed (car result))
         (failed (cdr result)))
    (should (= (length passed) 1))
    (should (null failed))))

(ert-deftest org-ai-skills-bdd-run-file-supports-planner-command ()
  "BDD runner should execute planner scenarios without requiring skill id."
  (let* ((scenario-file (make-temp-file "org-ai-skills-bdd-planner-" nil ".org"))
         (scenario
          (concat
           "#+TITLE: Planner BDD test\n\n"
           "* Scenario: planner command path\n"
           "Given target heading \"Planner Target\"\n"
           "And fixture source is \"inline section: Fixture Input\"\n"
           "And planner task \"Plan this subtree\"\n"
           "And model \"qwen/qwen3-8b\"\n"
           "And provider mode \"live\"\n"
           "When user runs command \"org-ai-skills-plan-run\"\n"
           "Then run status should be one of \"applied,success,done\"\n"
           "And dag info should contain \"planning.request\"\n"
           "And debug log should contain \"planner\"\n\n"
           "* Fixture Input\n"
           "** Planner Target\n"
           "Seed text.\n")))
    (unwind-protect
        (progn
          (with-temp-file scenario-file
            (insert scenario))
          (cl-letf (((symbol-function 'org-ai-skills-bdd--ensure-live-environment)
                     (lambda () t))
                    ((symbol-function 'org-ai-skills--observability-now-ms)
                     (lambda () 1000))
                    ((symbol-function 'org-ai-skills-bdd--wait-for-run-completion)
                     (lambda (_run-id _timeout) 'applied))
                    ((symbol-function 'org-ai-skills-plan-run)
                     (lambda (_target _task &optional _interactive-origin _preset-id)
                       (setq org-ai-skills--ui-run-state
                             (list :run-id "bdd-planner-run"
                                   :status 'applied
                                   :planner-run-state
                                   (list :run-id "bdd-planner-run"
                                         :active-plan (list (list :step-id "step-1"
                                                                  :goal "plan"
                                                                  :skills (list "fin-news-daily-report")
                                                                  :input-from nil))
                                         :events (list (list :stage-id 'planning.request
                                                             :status 'success
                                                             :duration-ms 12)
                                                       (list :stage-id 'planning.parse
                                                             :status 'success
                                                             :duration-ms 8)))))
                       (with-current-buffer (get-buffer-create org-ai-skills-debug-buffer-name)
                         (goto-char (point-max))
                         (insert "planner")))))
            (let ((result (org-ai-skills-bdd-run-file scenario-file)))
              (should (eq (plist-get result :status) 'pass))
              (should (null (plist-get result :failures))))))
      (delete-file scenario-file))))

(ert-deftest org-ai-skills-bdd-scenarios-cover-all-current-skills ()
  "BDD scenarios should include at least one case for every current skill id."
  (let* ((skill-files
          (directory-files (expand-file-name "skills" org-ai-skills-test--project-root)
                           t "\\.org\\'"))
         (scenario-files
          (directory-files (expand-file-name "tests/bdd" org-ai-skills-test--project-root)
                           t "^[0-9][0-9][0-9]-.*\\.org\\'"))
         (skill-ids
          (sort
           (delete-dups
            (mapcar (lambda (file)
                      (plist-get (org-ai-skills-parse-skill-file file) :skill-id))
                    skill-files))
           #'string<))
         (scenario-skill-ids
          (sort
           (delete-dups
            (delq
             nil
             (mapcar
              (lambda (file)
                (let* ((scenario (org-ai-skills-bdd-parse-file file))
                       (steps (plist-get scenario :steps))
                       (skill-step (seq-find
                                    (lambda (step)
                                      (and (eq (plist-get step :phase) 'given)
                                           (string-match
                                            "^skill id \"\\([^\"]+\\)\"$"
                                            (plist-get step :text))))
                                    steps)))
                  (and skill-step
                       (string-match
                        "^skill id \"\\([^\"]+\\)\"$"
                        (plist-get skill-step :text))
                       (match-string 1 (plist-get skill-step :text)))))
              scenario-files)))
           #'string<)))
    (dolist (skill-id skill-ids)
      (should (member skill-id scenario-skill-ids)))))

;;; org-ai-skills-test.el ends here
