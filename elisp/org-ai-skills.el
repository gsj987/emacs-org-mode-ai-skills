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
(require 'cl-lib)
(require 'org)

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
(define-error 'org-ai-skills-org-context-error "Invalid Org subtree context")
(define-error 'org-ai-skills-gptel-error "gptel integration error")
(define-error 'org-ai-skills-embark-error "Embark integration error")

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

(defun org-ai-skills--signal-org-context-error (message)
  "Signal Org context error with MESSAGE."
  (signal 'org-ai-skills-org-context-error (list message)))

(defun org-ai-skills--signal-gptel-error (message)
  "Signal gptel integration error with MESSAGE."
  (signal 'org-ai-skills-gptel-error (list message)))

(defun org-ai-skills--signal-embark-error (message)
  "Signal Embark integration error with MESSAGE."
  (signal 'org-ai-skills-embark-error (list message)))

(defun org-ai-skills--require-org-mode ()
  "Ensure current buffer is an Org buffer."
  (unless (derived-mode-p 'org-mode)
    (org-ai-skills--signal-org-context-error
     "Current buffer is not in org-mode")))

(defun org-ai-skills--subtree-at-heading-point ()
  "Return subtree plist at heading point.
Caller must ensure point is at a valid Org heading."
  (let ((begin (point))
        (level (org-outline-level))
        (heading (org-get-heading t t t t)))
    (save-excursion
      (org-end-of-subtree t t)
      (list :begin begin
            :end (point)
            :level level
            :heading heading
            :text (buffer-substring-no-properties begin (point))))))

(defun org-ai-skills-org-resolve-subtree (&optional context-mode levels-up)
  "Resolve target subtree at point.
CONTEXT-MODE can be `current' or `upper-level'. LEVELS-UP is used
when CONTEXT-MODE is `upper-level' and must be a positive integer."
  (org-ai-skills--require-org-mode)
  (let ((mode (or context-mode 'current))
        (up (or levels-up 1)))
    (unless (memq mode '(current upper-level))
      (org-ai-skills--signal-org-context-error
       (format "Unsupported context mode: %s" mode)))
    (when (and (eq mode 'upper-level)
               (or (not (integerp up)) (< up 1)))
      (org-ai-skills--signal-org-context-error
       "levels-up must be a positive integer for upper-level mode"))
    (save-excursion
      (org-with-wide-buffer
       (when (org-before-first-heading-p)
         (org-ai-skills--signal-org-context-error "No Org heading at point"))
       (unless (org-at-heading-p)
         (org-back-to-heading t))
       (when (eq mode 'upper-level)
         (dotimes (_ up)
           (unless (org-up-heading-safe)
             (org-ai-skills--signal-org-context-error
              (format "Cannot move up %d level(s) from current heading" up)))))
       (let ((subtree (org-ai-skills--subtree-at-heading-point)))
         (append subtree
                 (list :context-mode mode
                       :levels-up (if (eq mode 'upper-level) up 0))))))))

(defun org-ai-skills--collect-skills-for-completion (&optional directory)
  "Return completion candidates from skills in DIRECTORY."
  (mapcar
   (lambda (skill)
     (cons (format "%s | %s"
                   (plist-get skill :skill-id)
                   (plist-get skill :title))
           skill))
   (org-ai-skills-load-skills directory)))

(defun org-ai-skills-read-skill (&optional directory)
  "Read and return one parsed skill from DIRECTORY."
  (let* ((candidates (org-ai-skills--collect-skills-for-completion directory))
         (choice (completing-read "Skill: "
                                  (mapcar #'car candidates)
                                  nil t)))
    (or (cdr (assoc choice candidates))
        (org-ai-skills--signal-parse-error
         (or directory org-ai-skills-skill-dir)
         "Unable to select skill"))))

(defun org-ai-skills-build-gptel-rewrite-request (skill subtree &optional instruction)
  "Build a rewrite request from parsed SKILL and SUBTREE.
INSTRUCTION overrides the default rewrite goal."
  (let* ((heading (plist-get subtree :heading))
         (mode (plist-get subtree :context-mode))
         (levels-up (plist-get subtree :levels-up))
         (goal (if (string-empty-p (or instruction ""))
                   (format "Rewrite Org subtree for heading: %s" heading)
                 instruction))
         (base-payload (org-ai-skills-build-gptel-payload skill goal))
         (rewrite-prompt
          (concat (plist-get base-payload :prompt)
                  "\n\nContext mode: "
                  (symbol-name mode)
                  "\nLevels up: "
                  (number-to-string levels-up)
                  "\n\nOutput requirements:\n"
                  "- Return only the rewritten Org subtree.\n"
                  "- Do not include explanations, analysis, or progress notes.\n"
                  "- Do not wrap output in code fences.\n"
                  "- Keep Org syntax valid.\n\n"
                  "Rewrite the following Org subtree:\n\n"
                  (plist-get subtree :text))))
    (list :skill-id (plist-get base-payload :skill-id)
          :skill-title (plist-get base-payload :skill-title)
          :goal goal
          :description (plist-get base-payload :description)
          :tags (plist-get base-payload :tags)
          :headline heading
          :context-mode mode
          :levels-up levels-up
          :source-text (plist-get subtree :text)
          :prompt rewrite-prompt)))

(defun org-ai-skills--extract-gptel-response-text (&rest response)
  "Extract response text from gptel RESPONSE callback args."
  (let ((first (car response))
        (second (cadr response)))
    (cond
     ((stringp first) first)
     ((and (listp first) (plist-get first :content))
      (plist-get first :content))
     ((stringp second) second)
     (t (org-ai-skills--signal-gptel-error
         "gptel callback did not return text response")))))

(defun org-ai-skills--strip-markdown-fences (text)
  "Return TEXT without surrounding markdown code fences."
  (let ((trimmed (string-trim text)))
    (if (string-match
         (concat "\\`"
                 "```[[:alpha:]]*\n\\([[:ascii:][:nonascii:]\n]*\\)\n```\\'")
         trimmed)
        (match-string 1 trimmed)
      trimmed)))

(defun org-ai-skills--extract-subtree-body (text)
  "Extract Org subtree text from TEXT, removing preface chatter."
  (let* ((cleaned (org-ai-skills--strip-markdown-fences text))
         (start (string-match "^\\*+\\s-+" cleaned)))
    (if start
        (substring cleaned start)
      cleaned)))

(defun org-ai-skills--normalize-subtree-levels (text target-level)
  "Normalize heading levels in TEXT so root heading equals TARGET-LEVEL."
  (let ((root-match (string-match "^\\(\\*+\\)\\s-+" text)))
    (if (not root-match)
        text
      (let* ((generated-root-level (length (match-string 1 text)))
             (delta (- target-level generated-root-level)))
        (mapconcat
         (lambda (line)
           (if (string-match "^\\(\\*+\\)\\(\\s-+\\)" line)
               (let* ((stars (match-string 1 line))
                      (spaces (match-string 2 line))
                      (level (length stars))
                      (new-level (max 1 (+ level delta))))
                 (concat (make-string new-level ?*) spaces
                         (string-trim-left
                          (substring line (match-end 0)))))
             line))
         (split-string text "\n")
         "\n")))))

(defun org-ai-skills--sanitize-rewrite-output (rewritten-text subtree)
  "Sanitize REWRITTEN-TEXT and normalize heading levels for SUBTREE."
  (let* ((target-level (plist-get subtree :level))
         (target-heading (plist-get subtree :heading))
         (cleaned (org-ai-skills--extract-subtree-body rewritten-text))
         (with-heading
          (if (string-match "^\\*+\\s-+" cleaned)
              cleaned
            (format "%s %s\n%s"
                    (make-string target-level ?*)
                    target-heading
                    (string-trim-left cleaned)))))
    (org-ai-skills--normalize-subtree-levels with-heading target-level)))

(defun org-ai-skills-org-apply-rewrite-result (subtree rewritten-text)
  "Replace SUBTREE region with REWRITTEN-TEXT."
  (unless (stringp rewritten-text)
    (org-ai-skills--signal-org-context-error "Rewritten text must be a string"))
  (let ((begin (plist-get subtree :begin))
        (end (plist-get subtree :end)))
    (unless (and begin end (<= begin end))
      (org-ai-skills--signal-org-context-error
       "Invalid subtree range for rewrite"))
    (save-excursion
      (goto-char begin)
      (delete-region begin end)
      (insert rewritten-text)
      (unless (or (bolp) (string-suffix-p "\n" rewritten-text))
        (insert "\n")))))

(defun org-ai-skills-org-collect-context-candidates ()
  "Collect subtree rewrite scope candidates from current heading upward.
Return an alist where each item is (DISPLAY . SUBTREE-PLIST)."
  (org-ai-skills--require-org-mode)
  (save-excursion
    (org-with-wide-buffer
      (when (org-before-first-heading-p)
        (org-ai-skills--signal-org-context-error "No Org heading at point"))
      (unless (org-at-heading-p)
        (org-back-to-heading t))
      (let ((items nil)
            (levels-up 0)
            (done nil))
        (while (not done)
          (let* ((path (mapconcat #'identity (org-get-outline-path t t) "/"))
                 (subtree (org-ai-skills--subtree-at-heading-point))
                 (mode (if (= levels-up 0) 'current 'upper-level))
                 (display (format "[%s] %s"
                                  (if (= levels-up 0)
                                      "current"
                                    (format "up:%d" levels-up))
                                  path)))
            (push (cons display
                        (append subtree
                                (list :context-mode mode
                                      :levels-up levels-up
                                      :path path)))
                  items))
          (if (org-up-heading-safe)
              (setq levels-up (1+ levels-up))
            (setq done t)))
        (nreverse items)))))

(defun org-ai-skills-org-read-rewrite-target ()
  "Read rewrite target subtree from minibuffer with headline path preview."
  (let* ((candidates (org-ai-skills-org-collect-context-candidates))
         (choice (completing-read "Rewrite scope: "
                                  (mapcar #'car candidates)
                                  nil t)))
    (or (cdr (assoc choice candidates))
        (org-ai-skills--signal-org-context-error
         "Unable to resolve selected rewrite target"))))

(defun org-ai-skills-gptel-dispatch-rewrite (request callback)
  "Send rewrite REQUEST to gptel and run CALLBACK with response."
  (unless (or (featurep 'gptel) (org-ai-skills-require-gptel))
    (org-ai-skills--signal-gptel-error
     "gptel is unavailable; install or configure gptel first"))
  (unless (fboundp 'gptel-request)
    (org-ai-skills--signal-gptel-error
     "gptel-request is not available in current gptel version"))
  (funcall #'gptel-request
           (plist-get request :prompt)
           :callback callback))

(defun org-ai-skills--interactive-rewrite-args ()
  "Read interactive arguments for `org-ai-skills-org-rewrite-subtree'."
  (let* ((target (org-ai-skills-org-read-rewrite-target))
         (skill (org-ai-skills-read-skill))
         (instruction (read-string "Rewrite instruction (optional): ")))
    (list target skill instruction)))

(defun org-ai-skills-org-rewrite-subtree (target skill &optional instruction)
  "Rewrite Org TARGET subtree at point via gptel using SKILL.
When TARGET is nil, resolve current subtree."
  (interactive (org-ai-skills--interactive-rewrite-args))
  (let* ((subtree (or target (org-ai-skills-org-resolve-subtree 'current)))
         (request (org-ai-skills-build-gptel-rewrite-request
                   skill subtree instruction))
         (buffer (current-buffer))
         ;; Markers keep target positions stable for async callback.
         (begin (copy-marker (plist-get subtree :begin)))
         (end (copy-marker (plist-get subtree :end))))
    (org-ai-skills-gptel-dispatch-rewrite
     request
     (lambda (&rest response)
       (let* ((raw (apply #'org-ai-skills--extract-gptel-response-text response))
              (rewritten (org-ai-skills--sanitize-rewrite-output
                          raw
                          subtree)))
         (with-current-buffer buffer
           (org-ai-skills-org-apply-rewrite-result
            (list :begin begin :end end)
            rewritten)
           (message "org-ai-skills rewrite applied for: %s"
                    (plist-get subtree :heading))))))))

(defvar org-ai-skills-embark-org-heading-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "R") #'org-ai-skills-embark-rewrite-subtree-action)
    map)
  "Embark keymap for Org heading actions provided by org-ai-skills.")

(defun org-ai-skills-embark-rewrite-subtree-action (&optional _target)
  "Embark action adapter for `org-ai-skills-org-rewrite-subtree'."
  (interactive)
  (call-interactively #'org-ai-skills-org-rewrite-subtree))

(defun org-ai-skills-embark-install-action ()
  "Install org-ai-skills rewrite action into Embark Org heading target map.
Returns non-nil when the action is successfully installed."
  (unless (require 'embark nil t)
    (org-ai-skills--signal-embark-error
     "Embark is unavailable; install embark before registering actions"))
  (unless (boundp 'embark-keymap-alist)
    (org-ai-skills--signal-embark-error
     "embark-keymap-alist is unavailable in current Embark version"))
  (unless (assq 'org-heading embark-keymap-alist)
    (add-to-list 'embark-keymap-alist
                 '(org-heading . org-ai-skills-embark-org-heading-map)))
  t)

(define-minor-mode org-ai-skills-mode
  "Toggle org-ai-skills mode.

This mode is the initial runtime entry point used during bootstrap."
  :global nil
  :lighter " OrgAI")

(provide 'org-ai-skills)

;;; org-ai-skills.el ends here
