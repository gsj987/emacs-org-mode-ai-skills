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
    (should (string-match-p "\\*\\*\\* Leaf"
                            (plist-get request :prompt)))))

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
            (let ((subtree (org-ai-skills-org-resolve-subtree 'current)))
              (cl-letf (((symbol-function 'called-interactively-p)
                         (lambda (&rest _args) t))
                        ((symbol-function 'completing-read)
                         (lambda (&rest _args)
                           (ert-fail "interactive auto-apply should not ask candidate selection")))
                        ((symbol-function 'org-ai-skills-gptel-dispatch-rewrite)
                         (lambda (_request callback)
                           (funcall callback "*** Leaf\nAuto-applied body.\n"))))
                (org-ai-skills-org-rewrite-subtree subtree skill "Rewrite now"))
              (goto-char (point-min))
              (should (re-search-forward "Auto-applied body\\." nil t)))))
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
      (org-ai-skills-embark-plan-and-run-subtree-action "target")
      (org-ai-skills-embark-plan-and-run-subtree-repeat-task-action "target"))
    (should (member #'org-ai-skills-org-plan-and-run-subtree calls))
    (should (member #'org-ai-skills-org-plan-and-run-subtree-repeat-task calls))))

(ert-deftest org-ai-skills-plan-and-run-caches-last-task ()
  "Planner command should persist last task for reuse helper."
  (let ((org-ai-skills--last-planner-task nil)
        received-task)
    (cl-letf (((symbol-function 'org-ai-skills-run-task-with-planner)
               (lambda (task _subtree _options _callback)
                 (setq received-task task))))
      (org-ai-skills-org-plan-and-run-subtree
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
                        #'org-ai-skills-embark-plan-and-run-subtree-action))
            (should (eq (lookup-key (symbol-value
                                     (cdr (assq 'org-heading embark-keymap-alist)))
                                    (kbd "p"))
                        #'org-ai-skills-embark-plan-and-run-subtree-repeat-task-action))))
      (if had-bound
          (set 'embark-keymap-alist old-value)
        (makunbound 'embark-keymap-alist)))))

(ert-deftest org-ai-skills-plan-repeat-errors-without-last-task ()
  "Planner repeat helper should fail when no prior task exists."
  (let ((org-ai-skills--last-planner-task nil))
    (should-error
     (org-ai-skills-org-plan-and-run-subtree-repeat-task '(:heading "Leaf"))
     :type 'org-ai-skills-planner-error)))

(ert-deftest org-ai-skills-plan-repeat-reuses-last-task ()
  "Planner repeat helper should forward cached task."
  (let ((org-ai-skills--last-planner-task "Refine notes")
        called-target
        called-task
        called-origin)
    (cl-letf (((symbol-function 'org-ai-skills-org-plan-and-run-subtree)
               (lambda (target task &optional interactive-origin)
                 (setq called-target target)
                 (setq called-task task)
                 (setq called-origin interactive-origin))))
      (org-ai-skills-org-plan-and-run-subtree-repeat-task '(:heading "Leaf")))
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
    (cl-letf (((symbol-function 'org-ai-skills-org-plan-and-run-subtree)
               (lambda (target task &optional interactive-origin)
                 (setq org-ai-skills-test--captured-target target)
                 (setq org-ai-skills-test--captured-task task)
                 (setq org-ai-skills-test--captured-origin interactive-origin))))
      (org-ai-skills-org-plan-and-run-subtree-preset '(:heading "Leaf") "notes")
      (should (equal org-ai-skills-test--captured-target '(:heading "Leaf")))
      (should (string= org-ai-skills-test--captured-task "Convert to concise notes"))
      (should org-ai-skills-test--captured-origin))))

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
        (cl-letf (((symbol-function 'org-ai-skills-org-plan-and-run-subtree)
                   (lambda (target task &optional interactive-origin)
                     (setq captured-target target)
                     (setq captured-task task)
                     (setq captured-origin interactive-origin))))
          (funcall command '(:heading "Leaf"))
          (should (equal captured-target '(:heading "Leaf")))
          (should (string= captured-task "Turn subtree into action items"))
          (should captured-origin))
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
