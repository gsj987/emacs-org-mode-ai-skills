;;; org-ai-skills-test.el --- Tests for org-ai-skills -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'ert)
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

;;; org-ai-skills-test.el ends here
