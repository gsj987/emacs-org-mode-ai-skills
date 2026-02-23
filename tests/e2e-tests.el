;;; e2e-tests.el --- Live BDD E2E entry tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-ai-skills)

(defconst org-ai-skills-e2e-test--project-root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))

(ert-deftest org-ai-skills-e2e-live-bdd-twitter-rewrite ()
  "Run BDD 001 via live gptel call."
  (let* ((default-directory org-ai-skills-e2e-test--project-root)
         (result (org-ai-skills-bdd-run-file
                  "tests/bdd/001-twitter-shorten-subtree.org"
                  '(:model "meta-llama/llama-3.2-3b-instruct"))))
    (should (eq (plist-get result :status) 'pass))
    (should (null (plist-get result :failures)))))

