;;; org-ai-skills.el --- Cognitive runtime scaffolding for Org AI skills -*- lexical-binding: t; -*-

;; Author: org-ai-skills contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: ai, tools
;; URL: https://example.invalid/org-ai-skills

;;; Commentary:

;; Minimal bootstrap module for org-ai-skills.

;;; Code:

(require 'subr-x)

(defgroup org-ai-skills nil
  "Experimental cognitive runtime for Org-based AI skills."
  :group 'tools
  :prefix "org-ai-skills-")

(defcustom org-ai-skills-skill-dir
  (expand-file-name "../skills" (file-name-directory (or load-file-name buffer-file-name)))
  "Directory that stores Org skill specifications."
  :type 'directory
  :group 'org-ai-skills)

(defconst org-ai-skills--allowed-tags
  '((effect . ("pure" "local" "external" "irreversible"))
    (invocation . ("auto" "suggest" "manual"))
    (context . ("buffer" "project" "global"))
    (determinism . ("deterministic" "heuristic")))
  "Allowed semantic tags for skill specifications.")

(define-error 'org-ai-skills-parse-error "Invalid skill specification")

(defun org-ai-skills--signal-parse-error (file message)
  "Signal parse error with FILE context and MESSAGE."
  (signal 'org-ai-skills-parse-error
          (list (format "%s (%s)" message file))))

(defun org-ai-skills--match-required (content regexp file field-name)
  "Return required match from CONTENT by REGEXP for FILE and FIELD-NAME."
  (if (string-match regexp content)
      (string-trim (match-string 1 content))
    (org-ai-skills--signal-parse-error
     file
     (format "Missing required field: %s" field-name))))

(defun org-ai-skills--parse-description (content file)
  "Parse skill description section from CONTENT for FILE."
  (if (string-match
       "^\\*\\* Description[ \t]*\n\\([[:ascii:][:nonascii:]\n]*?\\)\\(?:\n\\*\\* \\|\\'\\)"
       content)
      (string-trim (match-string 1 content))
    (org-ai-skills--signal-parse-error file "Missing required section: Description")))

(defun org-ai-skills--extract-tag (content tag-key file)
  "Extract TAG-KEY value from CONTENT for FILE."
  (org-ai-skills--match-required
   content
   (format "^#\\+%s:[ \t]*\\([^ \t\n]+\\)" tag-key)
   file
   tag-key))

(defun org-ai-skills--validate-tag (tag-name tag-value file)
  "Validate TAG-NAME with TAG-VALUE for FILE."
  (let ((allowed (alist-get tag-name org-ai-skills--allowed-tags)))
    (unless (member tag-value allowed)
      (org-ai-skills--signal-parse-error
       file
       (format "Invalid %s value: %s" (upcase (symbol-name tag-name)) tag-value)))))

(defun org-ai-skills-discover-skill-files (&optional directory)
  "Discover skill files in DIRECTORY.
When DIRECTORY is nil, use `org-ai-skills-skill-dir'."
  (let* ((dir (or directory org-ai-skills-skill-dir))
         (pattern (expand-file-name "*.org" dir)))
    (sort (file-expand-wildcards pattern t) #'string<)))

(defun org-ai-skills-parse-skill-file (file)
  "Parse and validate one skill specification FILE.
Return a plist with normalized keys."
  (unless (file-readable-p file)
    (org-ai-skills--signal-parse-error file "Skill file is not readable"))
  (let* ((content (with-temp-buffer
                    (insert-file-contents file)
                    (buffer-string)))
         (title (org-ai-skills--match-required
                 content "^\\* Skill:[ \t]*\\(.+\\)$" file "Skill heading"))
         (skill-id (org-ai-skills--match-required
                    content "^:SKILL_ID:[ \t]*\\(.+\\)$" file "SKILL_ID"))
         (effect (org-ai-skills--extract-tag content "EFFECT" file))
         (invocation (org-ai-skills--extract-tag content "INVOCATION" file))
         (context (org-ai-skills--extract-tag content "CONTEXT" file))
         (determinism (org-ai-skills--extract-tag content "DETERMINISM" file))
         (description (org-ai-skills--parse-description content file)))
    (org-ai-skills--validate-tag 'effect effect file)
    (org-ai-skills--validate-tag 'invocation invocation file)
    (org-ai-skills--validate-tag 'context context file)
    (org-ai-skills--validate-tag 'determinism determinism file)
    (list :file file
          :title title
          :skill-id skill-id
          :description description
          :tags (list :effect effect
                      :invocation invocation
                      :context context
                      :determinism determinism))))

(defun org-ai-skills-load-skills (&optional directory)
  "Load all skill specs from DIRECTORY."
  (mapcar #'org-ai-skills-parse-skill-file
          (org-ai-skills-discover-skill-files directory)))

(defun org-ai-skills-build-gptel-payload (skill goal)
  "Build a structured gptel payload from parsed SKILL and GOAL."
  (list :skill-id (plist-get skill :skill-id)
        :skill-title (plist-get skill :title)
        :goal goal
        :description (plist-get skill :description)
        :tags (plist-get skill :tags)
        :prompt (format "Use skill %s (%s) to solve: %s"
                        (plist-get skill :skill-id)
                        (plist-get skill :title)
                        goal)))

(defun org-ai-skills-require-gptel (&optional gptel-dir)
  "Load gptel from GPTEL-DIR or default straight checkout path."
  (let ((dir (or gptel-dir
                 (expand-file-name "~/.emacs.d/straight/repos/gptel/"))))
    (add-to-list 'load-path dir)
    (require 'gptel nil t)))

(define-minor-mode org-ai-skills-mode
  "Toggle org-ai-skills mode.

This mode is the initial runtime entry point used during bootstrap."
  :global nil
  :lighter " OrgAI")

(provide 'org-ai-skills)

;;; org-ai-skills.el ends here
