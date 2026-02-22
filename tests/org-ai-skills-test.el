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
  (let* ((calls (org-ai-skills--request-function-calls '()))
         (names (mapcar (lambda (entry) (plist-get entry :name)) calls)))
    (should (member "org-ai-skills-read-buffer" names))
    (should (member "org-ai-skills-read-file" names))))

(ert-deftest org-ai-skills-core-read-tools-can-be-disabled ()
  "Core read tools should be omitted when feature flag is nil."
  (let ((org-ai-skills-enable-core-read-tools nil))
    (should-not (org-ai-skills--request-function-calls '()))))

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
      (should (string-match-p "Request plist" (buffer-string))))
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

(ert-deftest org-ai-skills-sanitize-rewrite-output-fixes-level-and-preface ()
  "Sanitizer should remove explanation preface and enforce target level."
  (let* ((subtree '(:level 2 :heading "Child"))
         (raw "Here is the rewrite:\n*** Child Revised\n**** Sub\nBody\n")
         (cleaned (org-ai-skills--sanitize-rewrite-output raw subtree)))
    (should-not (string-match-p "Here is the rewrite" cleaned))
    (should (string-prefix-p "** Child Revised" cleaned))
    (should (string-match-p "^\\*\\*\\* Sub$" cleaned))))

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

(ert-deftest org-ai-skills-rewrite-noninteractive-saves-candidate-without-auto-apply ()
  "Non-interactive rewrite should persist candidate and not mutate subtree text."
  (let ((store-dir (make-temp-file "org-ai-skills-versions-" t))
        (skill (org-ai-skills-parse-skill-file org-ai-skills-test--first-skill-file)))
    (unwind-protect
        (let ((org-ai-skills-version-store-dir store-dir))
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
          (list :rerun-fn (lambda () (setq called t))))
    (org-ai-skills-ui-rerun)
    (should called)))

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
                (should (re-search-forward "Candidates (2):" nil t))
                (should-not (re-search-forward
                             (regexp-quote (plist-get candidate-a :candidate-id))
                             nil t))
                (goto-char (point-min))
                (should (re-search-forward " \\*01 \\[G\\] " nil t))))))
      (delete-directory store-dir t))))

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

(ert-deftest org-ai-skills-parse-planner-response-rejects-empty-plan-by-default ()
  "Planner parser should reject empty plan for initial planning."
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

(ert-deftest org-ai-skills-request-planner-plan-fails-on-malformed-json ()
  "Planner request should fail fast when planner response JSON is malformed."
  (let ((metadata (list '(:skill-id "gen-notes" :title "Notes" :summary "S")))
        (malformed "{\"candidates\":[],\"plan\":["))
    (cl-letf (((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
               (lambda (_request callback)
                 (funcall callback malformed '(:data (:payload t)))
                 (funcall callback t '(:data (:done t)))))
              ((symbol-function 'org-ai-skills--extract-gptel-response-text-if-ready)
               (lambda (&rest response)
                 (car response))))
      (should-error
       (org-ai-skills--request-planner-plan
        "task"
        metadata
        '(:task "task" :steps nil :plan-revision 1)
        #'ignore)
       :type 'org-ai-skills-planner-error))))

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
       (lambda (parsed) (setq callback-result parsed))))
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
       (lambda (parsed) (setq callback-result parsed))))
    (should (listp callback-result))
    (should (= (length (plist-get callback-result :plan)) 1))))

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

(ert-deftest org-ai-skills-gptel-dispatch-registers-request-tools ()
  "Dispatch should register request-scoped function calls as gptel tools."
  (let ((org-ai-skills-debug-enabled nil)
        (org-ai-skills-enable-core-read-tools nil)
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

(ert-deftest org-ai-skills-gptel-dispatch-planner-includes-structured-schema ()
  "Planner dispatch should include :schema for structured output."
  (let (captured-args
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

;;; org-ai-skills-test.el ends here
