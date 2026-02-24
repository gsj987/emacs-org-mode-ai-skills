;;; e2e-tests.el --- Live BDD E2E entry tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-ai-skills)
(defvar org-ai-skills-e2e-openrouter-tool-request-params nil)

(defconst org-ai-skills-e2e-test--project-root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))

(defun org-ai-skills-e2e-test--transport-error-p (result)
  "Return non-nil when RESULT indicates transport/provider request failure."
  (let* ((debug-log (or (plist-get result :debug-log) ""))
         (failures (or (plist-get result :failures) nil))
         (failure-text (mapconcat #'identity failures "\n")))
    (or (string-match-p "Could not parse HTTP response" debug-log)
        (string-match-p "gptel returned no text" debug-log)
        (string-match-p "No endpoints found that support tool use" debug-log)
        (string-match-p "Could not parse HTTP response" failure-text)
        (string-match-p "gptel returned no text" failure-text)
        (string-match-p "No endpoints found that support tool use" failure-text))))

(defun org-ai-skills-e2e-test--debug-tail (result)
  "Return last part of debug log from RESULT for assertion diagnostics."
  (let* ((debug-log (or (plist-get result :debug-log) ""))
         (n (min 1600 (length debug-log))))
    (if (<= (length debug-log) n)
        debug-log
      (substring debug-log (- (length debug-log) n)))))

(defun org-ai-skills-e2e-test--run-bdd (scenario-file)
  "Run one BDD SCENARIO-FILE and assert pass with no failures."
  (let* ((default-directory org-ai-skills-e2e-test--project-root)
         (model (or org-ai-skills-e2e-model-profile
                    "openai/gpt-4o-mini"))
         (result (org-ai-skills-bdd-run-file scenario-file (list :model model))))
    (when (org-ai-skills-e2e-test--transport-error-p result)
      (ert-fail (format "Live transport/provider failure for %s: %S\nDebug tail:\n%s"
                        scenario-file
                        (plist-get result :failures)
                        (org-ai-skills-e2e-test--debug-tail result))))
    (should (eq (plist-get result :status) 'pass))
    (should (null (plist-get result :failures)))))

(defun org-ai-skills-e2e-test--run-bdd-result (scenario-file)
  "Run SCENARIO-FILE once and return result plist."
  (let* ((default-directory org-ai-skills-e2e-test--project-root)
         (model (or org-ai-skills-e2e-model-profile
                    "openai/gpt-4o-mini")))
    (org-ai-skills-bdd-run-file scenario-file (list :model model))))

(ert-deftest org-ai-skills-e2e-live-bdd-001-twitter-rewrite ()
  "Run BDD 001 via live gptel call." 
  (org-ai-skills-e2e-test--run-bdd
   "tests/bdd/001-twitter-shorten-subtree.org"))

(ert-deftest org-ai-skills-e2e-live-bdd-002-generate-structured-notes ()
  "Run BDD 002 via live gptel call."
  (org-ai-skills-e2e-test--run-bdd
   "tests/bdd/002-generate-structured-notes-subtree.org"))

(ert-deftest org-ai-skills-e2e-live-bdd-003-daily-financial-news-report ()
  "Run BDD 003 via live gptel call."
  (org-ai-skills-e2e-test--run-bdd
   "tests/bdd/003-daily-financial-news-report-subtree.org"))

(ert-deftest org-ai-skills-e2e-live-bdd-004-article-outline-from-source ()
  "Run BDD 004 via live gptel call."
  (org-ai-skills-e2e-test--run-bdd
   "tests/bdd/004-article-outline-from-source-subtree.org"))

(ert-deftest org-ai-skills-e2e-live-bdd-005-article-compose-from-outline ()
  "Run BDD 005 via live gptel call."
  (org-ai-skills-e2e-test--run-bdd
   "tests/bdd/005-article-compose-from-outline-subtree.org"))

(ert-deftest org-ai-skills-e2e-live-bdd-006-article-repair-subtree ()
  "Run BDD 006 via live gptel call."
  (org-ai-skills-e2e-test--run-bdd
   "tests/bdd/006-article-repair-subtree.org"))

(ert-deftest org-ai-skills-e2e-live-bdd-007-article-polish-editorial ()
  "Run BDD 007 via live gptel call."
  (org-ai-skills-e2e-test--run-bdd
   "tests/bdd/007-article-polish-editorial-subtree.org"))

(ert-deftest org-ai-skills-e2e-live-tool-call-financial-report ()
  "Verify live tool-calling path by requiring a tool event in BDD 003."
  (let ((org-ai-skills-enable-skill-function-calls t)
        (org-ai-skills-gptel-request-params
         (or org-ai-skills-e2e-openrouter-tool-request-params
             '(:provider (:require_parameters t :allow_fallbacks :json-false))))
        (org-ai-skills-bdd-live-timeout-seconds 300))
    (let* ((result (org-ai-skills-e2e-test--run-bdd-result
                    "tests/bdd/003-daily-financial-news-report-subtree.org"))
           (debug-log (or (plist-get result :debug-log) "")))
      (when (org-ai-skills-e2e-test--transport-error-p result)
        (ert-fail (format "Tool-call transport/provider failure: %S\nDebug tail:\n%s"
                          (plist-get result :failures)
                          (org-ai-skills-e2e-test--debug-tail result))))
      (should (eq (plist-get result :status) 'pass))
      (should (null (plist-get result :failures)))
      (should (or (string-match-p "gptel callback event: (tool-call" debug-log)
                  (string-match-p "gptel callback event: (tool-result" debug-log))))))
