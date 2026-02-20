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
(require 'seq)
(require 'org)
(require 'org-id)
(require 'pp)
(require 'json)

(defgroup org-ai-skills nil
  "Experimental cognitive runtime for Org-based AI skills."
  :group 'tools
  :prefix "org-ai-skills-")

(defcustom org-ai-skills-skill-dir
  (expand-file-name "../skills" (file-name-directory (or load-file-name buffer-file-name)))
  "Directory that stores Org skill specifications."
  :type 'directory
  :group 'org-ai-skills)

(defcustom org-ai-skills-debug-enabled nil
  "When non-nil, append gptel dispatch payloads to debug buffer."
  :type 'boolean
  :group 'org-ai-skills)

(defcustom org-ai-skills-debug-buffer-name "*org-ai-skills-debug*"
  "Buffer name used for org-ai-skills debug logs."
  :type 'string
  :group 'org-ai-skills)

(defcustom org-ai-skills-planner-max-steps 6
  "Maximum number of plan steps allowed in one planner revision."
  :type 'integer
  :group 'org-ai-skills)

(defcustom org-ai-skills-planner-max-replans 2
  "Maximum number of replan revisions allowed during one run."
  :type 'integer
  :group 'org-ai-skills)

(defcustom org-ai-skills-planner-auto-replan t
  "When non-nil, allow planner-guided replan during execution."
  :type 'boolean
  :group 'org-ai-skills)

(defcustom org-ai-skills-planner-max-skills-per-step 2
  "Maximum number of skills allowed in one execution step."
  :type 'integer
  :group 'org-ai-skills)

(defcustom org-ai-skills-planner-batching-mode 'balanced
  "Strategy for balancing quality and speed in multi-skill batching."
  :type '(choice (const :tag "Quality First" quality-first)
                 (const :tag "Balanced" balanced)
                 (const :tag "Speed First" speed-first))
  :group 'org-ai-skills)

(defcustom org-ai-skills-planner-overflow-strategy 'reject
  "How to handle planner steps exceeding max skills per step."
  :type '(choice (const :tag "Reject plan" reject)
                 (const :tag "Auto split step" split))
  :group 'org-ai-skills)

(defcustom org-ai-skills-planner-task-presets nil
  "Preset planner task intents as (ID . TASK) pairs.
Each ID is a short key, and TASK is the full planner intent text."
  :type '(repeat
          (cons (string :tag "Preset ID")
                (string :tag "Task intent")))
  :group 'org-ai-skills)

(defcustom org-ai-skills-version-store-dir
  (expand-file-name "~/.emacs.d/skills/versions/")
  "Directory for persisted candidate versions."
  :type 'directory
  :group 'org-ai-skills)

(defcustom org-ai-skills-auto-apply-generated-candidate t
  "When non-nil, interactive generation auto-applies the newly generated candidate.
When nil, interactive flow asks user to select a candidate explicitly."
  :type 'boolean
  :group 'org-ai-skills)

(defcustom org-ai-skills-ui-auto-open t
  "When non-nil, interactive rewrite/planner runs auto-open the control workspace."
  :type 'boolean
  :group 'org-ai-skills)

(defcustom org-ai-skills-ui-control-window-width 34
  "Preferred width (columns) for the control window."
  :type 'integer
  :group 'org-ai-skills)

(defcustom org-ai-skills-model-planner nil
  "Model override for planner requests.
When nil, planner requests use gptel default model selection."
  :type '(choice (const :tag "Use gptel default model" nil)
                 (string :tag "Model id")
                 (symbol :tag "Model symbol"))
  :group 'org-ai-skills)

(defcustom org-ai-skills-model-execution nil
  "Model override for execution/rewrite requests.
When nil, execution requests use gptel default model selection."
  :type '(choice (const :tag "Use gptel default model" nil)
                 (string :tag "Model id")
                 (symbol :tag "Model symbol"))
  :group 'org-ai-skills)

(defcustom org-ai-skills-planner-temperature 0.0
  "Sampling temperature used for planner requests."
  :type 'number
  :group 'org-ai-skills)

(defcustom org-ai-skills-planner-max-tokens 2048
  "Maximum token budget for planner responses.
Set to nil to use gptel/backend default."
  :type '(choice (const :tag "Use backend default" nil)
                 (integer :tag "Max tokens"))
  :group 'org-ai-skills)

(defconst org-ai-skills--default-system-prompt-planner
  (string-join
   '("You are the planner for org-ai-skills."
     "Your only job is to produce a machine-parseable plan from provided task, metadata, and run-state."
     "Use only provided skills and constraints."
     "Return strict JSON only. No markdown. No prose. No analysis. No hidden-thinking text."
     "Do not include extra keys or commentary outside the required JSON contract.")
   "\n")
  "Default system prompt used for planner role requests.")

(defconst org-ai-skills--default-system-prompt-execution
  (string-join
   '("You are the execution engine for org-ai-skills."
     "Operate only within the provided scope, input content, and skill context."
     "Always return valid Org-mode content as the final artifact."
     "Do not return commentary, analysis, progress notes, or markdown code fences."
     "Follow provided contracts and requirements; do not invent missing external context.")
   "\n")
  "Default system prompt used for execution role requests.")

(defcustom org-ai-skills-system-prompt-planner
  org-ai-skills--default-system-prompt-planner
  "System prompt used for planner role requests.
When set to an empty string, dispatch falls back to the default planner system prompt."
  :type 'string
  :group 'org-ai-skills)

(defcustom org-ai-skills-system-prompt-execution
  org-ai-skills--default-system-prompt-execution
  "System prompt used for execution role requests.
When set to an empty string, dispatch falls back to the default execution system prompt."
  :type 'string
  :group 'org-ai-skills)

(defconst org-ai-skills--planner-response-schema
  '(:type "object"
    :properties
    (:candidates
     (:type "array"
      :items
      (:type "object"
       :properties (:skill_id (:type "string")
                    :why (:type "string")
                    :score (:type "number"))))
     :plan
     (:type "array"
      :items
      (:type "object"
       :properties (:step_id (:type "string")
                    :goal (:type "string")
                    :skills (:type "array" :items (:type "string"))
                    :input_from (:type "array" :items (:type "string"))
                    :expected_output (:type "string")
                    :composition_reason (:type "string"))))
     :replan_signal
     (:type "object"
      :properties (:enabled (:type "boolean")
                   :condition (:type "string")))))
  "JSON schema used for planner structured output.")

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
(define-error 'org-ai-skills-planner-error "Planner integration error")
(define-error 'org-ai-skills-function-call-error "Skill function call error")

(define-error 'org-ai-skills-version-store-error "Version store error")

(defvar org-ai-skills--last-debug-entry nil
  "Last debug entry captured for gptel dispatch.")

(defvar org-ai-skills--last-planner-task nil
  "Last task string used by planner run commands.")

(defvar org-ai-skills--planner-task-history nil
  "Minibuffer history for planner task prompts.")

(defvar org-ai-skills--active-skill-function-calls nil
  "Alist mapping active skill-id to function call specs.")

(defvar org-ai-skills--skill-defined-function-symbols nil
  "Alist mapping skill-id to function symbols defined from skill code blocks.")

(defvar org-ai-skills--candidate-selection-history nil
  "Minibuffer history for candidate selection prompts.")

(defconst org-ai-skills-control-buffer-name "*org-ai-skills-control*"
  "Buffer name for runtime control panel.")

(defvar org-ai-skills--ui-window-configuration nil
  "Window configuration captured before opening control workspace.")

(defvar org-ai-skills--ui-run-state nil
  "Runtime UI state for current run and control workspace.")

(defvar org-ai-skills-control-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "s") #'org-ai-skills-ui-stop-run)
    (define-key map (kbd "g") #'org-ai-skills-ui-rerun)
    (define-key map (kbd "t") #'org-ai-skills-ui-adjust-task-or-instruction)
    (define-key map (kbd "c") #'org-ai-skills-ui-select-candidate)
    (define-key map (kbd "a") #'org-ai-skills-ui-apply-selected-candidate)
    (define-key map (kbd "d") #'org-ai-skills-ui-discard-selected-candidate)
    (define-key map (kbd "q") #'org-ai-skills-ui-close-workspace)
    (define-key map (kbd "r") #'org-ai-skills-ui-refresh-control-buffer)
    map)
  "Keymap for `org-ai-skills-control-mode'.")

(defface org-ai-skills-ui-overlay-running-face
  '((t :inherit highlight))
  "Face for source-region overlay while generation is running."
  :group 'org-ai-skills)

(defface org-ai-skills-ui-overlay-ready-face
  '((t :inherit secondary-selection))
  "Face for source-region overlay when candidate is ready."
  :group 'org-ai-skills)

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
  (let ((description (org-ai-skills--extract-section content "Description")))
    (if description
        description
      (org-ai-skills--signal-parse-error file "Missing required section: Description"))))

(defun org-ai-skills--extract-section (content section-name)
  "Extract SECTION-NAME body from CONTENT.
Return trimmed section text, or nil if section does not exist."
  (when (string-match
         (format "^\\*\\* %s[ \t]*\n\\([[:ascii:][:nonascii:]\n]*?\\)\\(?:\n\\*\\* \\|\\'\\)"
                 (regexp-quote section-name))
         content)
    (string-trim (match-string 1 content))))

(defun org-ai-skills--parse-bullet-lines (section-text)
  "Parse bullet list items from SECTION-TEXT."
  (if (string-empty-p (or section-text ""))
      nil
    (let ((items nil))
      (dolist (line (split-string section-text "\n"))
        (when (string-match "^[ \t]*-\\s-+\\(.+\\)$" line)
          (push (string-trim (match-string 1 line)) items)))
      (nreverse items))))

(defun org-ai-skills--parse-function-calls (section-text)
  "Parse function calls from SECTION-TEXT."
  (if (string-empty-p (or section-text ""))
      nil
    (let ((items nil)
          (current nil)
          (raw-lines nil))
      (dolist (line (split-string section-text "\n"))
        (cond
         ((string-match "^[ \t]*-\\s-*name:\\s-*\\(.+\\)$" line)
          (when current
            (push (append current
                          (list :raw (string-join (nreverse raw-lines) "\n")))
                  items))
          (setq current (list :name (string-trim (match-string 1 line))))
          (setq raw-lines (list (string-trim line))))
         ((and current (string-match "^[ \t]+\\([[:alnum:]_-]+\\):\\s-*\\(.+\\)$" line))
          (let* ((key-name (downcase (match-string 1 line)))
                 (value (string-trim (match-string 2 line)))
                 (key (pcase key-name
                        ("when" :when)
                        ("args" :args)
                        (_ (intern (format ":%s" key-name))))))
            (setq current (plist-put current key value))
            (push (string-trim line) raw-lines)))
         ((and current (not (string-empty-p (string-trim line))))
          (push (string-trim line) raw-lines))))
      (when current
        (push (append current
                      (list :raw (string-join (nreverse raw-lines) "\n")))
              items))
      (nreverse items))))

(defun org-ai-skills--parse-elisp-source-blocks (section-text)
  "Parse emacs-lisp source blocks from SECTION-TEXT."
  (if (string-empty-p (or section-text ""))
      nil
    (let ((items nil)
          (start 0)
          (case-fold-search t))
      (while (string-match
              "#\\+begin_src\\s-+emacs-lisp\\b[^\n]*\n\\([[:ascii:][:nonascii:]\n]*?\\)#\\+end_src"
              section-text
              start)
        (push (string-trim (match-string 1 section-text)) items)
        (setq start (match-end 0)))
      (nreverse items))))

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
         (description (org-ai-skills--parse-description content file))
         (inputs-section (or (org-ai-skills--extract-section content "Inputs") ""))
         (outputs-section (or (org-ai-skills--extract-section content "Outputs") ""))
         (steps-section (or (org-ai-skills--extract-section content "Steps") ""))
         (contracts-section (or (org-ai-skills--extract-section content "Contracts") ""))
         (requirements-section (or (org-ai-skills--extract-section content "Requirements") ""))
         (function-calls-section (or (org-ai-skills--extract-section content "Function Calls") ""))
         (function-definitions-section (or (org-ai-skills--extract-section content "Function Definitions") ""))
         (outputs (org-ai-skills--parse-bullet-lines outputs-section))
         (contracts (org-ai-skills--parse-bullet-lines contracts-section))
         (requirements (org-ai-skills--parse-bullet-lines requirements-section))
         (function-calls (org-ai-skills--parse-function-calls function-calls-section))
         (function-definitions (org-ai-skills--parse-elisp-source-blocks function-definitions-section)))
    (org-ai-skills--validate-tag 'effect effect file)
    (org-ai-skills--validate-tag 'invocation invocation file)
    (org-ai-skills--validate-tag 'context context file)
    (org-ai-skills--validate-tag 'determinism determinism file)
    (list :file file
          :title title
          :skill-id skill-id
          :description description
          :outputs outputs
          :contracts contracts
          :requirements requirements
          :function-calls function-calls
          :function-definitions function-definitions
          :raw-sections (list :description description
                              :inputs inputs-section
                              :outputs outputs-section
                              :steps steps-section
                              :contracts contracts-section
                              :requirements requirements-section
                              :function-calls function-calls-section
                              :function-definitions function-definitions-section)
          :tags (list :effect effect
                      :invocation invocation
                      :context context
                      :determinism determinism))))

(defun org-ai-skills-load-skills (&optional directory)
  "Load all skill specs from DIRECTORY."
  (mapcar #'org-ai-skills-parse-skill-file
          (org-ai-skills-discover-skill-files directory)))

(defun org-ai-skills--description-summary (description)
  "Return one-line summary derived from DESCRIPTION."
  (let ((first-line (car (split-string (or description "") "\n" t "[ \t]+"))))
    (string-trim (or first-line ""))))

(defun org-ai-skills--signal-function-call-error (message)
  "Signal function call error with MESSAGE."
  (signal 'org-ai-skills-function-call-error (list message)))

(defun org-ai-skills-clear-active-skill-functions ()
  "Clear all active skill function calls."
  (setq org-ai-skills--active-skill-function-calls nil)
  (setq org-ai-skills--skill-defined-function-symbols nil))

(defun org-ai-skills--function-call-spec-valid-p (fn-spec)
  "Return non-nil when FN-SPEC references a callable Elisp function."
  (let* ((name (plist-get fn-spec :name))
         (symbol (and (stringp name) (intern-soft name))))
    (and symbol (fboundp symbol))))

(defun org-ai-skills--eval-skill-elisp-string (source skill-id)
  "Evaluate one SOURCE elisp string for SKILL-ID."
  (with-temp-buffer
    (insert source)
    (goto-char (point-min))
    (condition-case err
        (while (< (point) (point-max))
          (let ((form (read (current-buffer))))
            (eval form t)))
      (error
       (org-ai-skills--signal-function-call-error
        (format "Failed to evaluate function definition for skill %s: %s"
                skill-id
                (error-message-string err)))))))

(defun org-ai-skills--load-skill-function-definitions (skill)
  "Load function definitions declared by SKILL."
  (let ((blocks (or (plist-get skill :function-definitions) nil))
        (skill-id (plist-get skill :skill-id)))
    (dolist (source blocks)
      (org-ai-skills--eval-skill-elisp-string source skill-id))))

(defun org-ai-skills-apply-skill-function-calls (skill)
  "Activate function calls declared by SKILL and load its function definitions."
  (let* ((skill-id (plist-get skill :skill-id))
         (function-calls (or (plist-get skill :function-calls) nil))
         (previously-unbound nil)
         (newly-defined nil))
    (dolist (fn-spec function-calls)
      (let* ((name (plist-get fn-spec :name))
             (symbol (and (stringp name) (intern-soft name))))
        (when (and symbol (not (fboundp symbol)))
          (push symbol previously-unbound))))
    (org-ai-skills--load-skill-function-definitions skill)
    (dolist (fn-spec function-calls)
      (unless (org-ai-skills--function-call-spec-valid-p fn-spec)
        (org-ai-skills--signal-function-call-error
         (format "Skill %s declares unavailable function call: %s"
                 skill-id
                 (or (plist-get fn-spec :name) "")))))
    (dolist (symbol previously-unbound)
      (when (fboundp symbol)
        (push symbol newly-defined)))
    (setq org-ai-skills--active-skill-function-calls
          (assq-delete-all skill-id org-ai-skills--active-skill-function-calls))
    (when function-calls
      (push (cons skill-id function-calls) org-ai-skills--active-skill-function-calls))
    (setq org-ai-skills--skill-defined-function-symbols
          (assq-delete-all skill-id org-ai-skills--skill-defined-function-symbols))
    (when newly-defined
      (push (cons skill-id newly-defined) org-ai-skills--skill-defined-function-symbols))
    function-calls))

(defun org-ai-skills-exclude-skill-function-calls (skill-or-id)
  "Deactivate function calls for SKILL-OR-ID."
  (let ((skill-id (if (stringp skill-or-id)
                      skill-or-id
                    (plist-get skill-or-id :skill-id))))
    (setq org-ai-skills--active-skill-function-calls
          (assq-delete-all skill-id org-ai-skills--active-skill-function-calls))
    (let ((defined-symbols (cdr (assoc skill-id org-ai-skills--skill-defined-function-symbols))))
      (dolist (symbol defined-symbols)
        (when (fboundp symbol)
          (fmakunbound symbol))))
    (setq org-ai-skills--skill-defined-function-symbols
          (assq-delete-all skill-id org-ai-skills--skill-defined-function-symbols))))

(defun org-ai-skills-active-skill-function-calls (skill-or-id)
  "Return active function call specs for SKILL-OR-ID."
  (let ((skill-id (if (stringp skill-or-id)
                      skill-or-id
                    (plist-get skill-or-id :skill-id))))
    (cdr (assoc skill-id org-ai-skills--active-skill-function-calls))))

(defun org-ai-skills-parse-skill-metadata-file (file)
  "Parse planner metadata from skill FILE.
This parser intentionally avoids extracting full context sections."
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
    (list :skill-id skill-id
          :title title
          :file file
          :summary (org-ai-skills--description-summary description)
          :tags (list :effect effect
                      :invocation invocation
                      :context context
                      :determinism determinism))))

(defun org-ai-skills-load-skill-metadata (&optional directory)
  "Load planner metadata for all skills from DIRECTORY."
  (mapcar #'org-ai-skills-parse-skill-metadata-file
          (org-ai-skills-discover-skill-files directory)))

(defun org-ai-skills-load-skill-by-id (skill-id &optional directory)
  "Load full parsed skill by SKILL-ID from DIRECTORY."
  (let* ((metadata (org-ai-skills-load-skill-metadata directory))
         (entry (seq-find
                 (lambda (meta)
                   (string= (plist-get meta :skill-id) skill-id))
                 metadata)))
    (unless entry
      (signal 'org-ai-skills-planner-error
              (list (format "Unknown skill id: %s" skill-id))))
    (org-ai-skills-parse-skill-file (plist-get entry :file))))

(defun org-ai-skills-build-planner-request (task metadata-list run-state)
  "Build planner request payload from TASK, METADATA-LIST, and RUN-STATE."
  (let* ((completed-step-summary
          (mapcar
           (lambda (step)
             (list :step-id (plist-get step :step-id)
                   :skills (vconcat (or (plist-get step :skills) nil))
                   :goal (plist-get step :goal)
                   :output (plist-get step :output)))
           (or (plist-get run-state :steps) nil)))
         ;; json-serialize requires vectors for unambiguous JSON arrays.
         (metadata-json
          (decode-coding-string
           (json-serialize (vconcat metadata-list))
           'utf-8 t))
         (run-state-json
          (decode-coding-string
           (json-serialize
            (list :task (plist-get run-state :task)
                  :plan-revision (or (plist-get run-state :plan-revision) 0)
                  :completed-steps (vconcat completed-step-summary)
                  :latest-output (plist-get run-state :latest-output)))
           'utf-8 t))
         (prompt
          (concat
           "You are the org-ai-skills planner.\n"
           "Select skill candidates and produce an execution plan.\n"
           "Use ONLY the provided skill metadata and do not assume hidden skills.\n\n"
           "Constraints:\n"
           (format "- max_steps: %d\n" org-ai-skills-planner-max-steps)
           (format "- max_skills_per_step: %d\n" org-ai-skills-planner-max-skills-per-step)
           (format "- batching_mode: %s\n\n"
                   (symbol-name org-ai-skills-planner-batching-mode))
           "Task:\n"
           task
           "\n\nSkill metadata list (JSON):\n"
           metadata-json
           "\n\nRun state summary (JSON):\n"
           run-state-json
           "\n\nReturn STRICT JSON object with keys:\n"
           "- candidates: [{skill_id, why, score}]\n"
           "- plan: [{step_id, goal, skills, input_from, expected_output, composition_reason}]\n"
           "- replan_signal: {enabled, condition}\n"
           "No markdown. No prose.")))
    (list :event-type 'planner
          :request-role 'planner
          :task task
          :metadata-count (length metadata-list)
          :run-state run-state
          :prompt prompt)))

(defun org-ai-skills--extract-json-object (text)
  "Extract first JSON object from TEXT."
  (let* ((cleaned (org-ai-skills--strip-markdown-fences (or text "")))
         (start (string-match "{" cleaned))
         (end (and start (let ((idx (string-match "}\\s-*$" cleaned)))
                           (and idx (+ idx 1))))))
    (unless (and start end (> end start))
      (signal 'org-ai-skills-planner-error
              (list "Planner response does not contain a JSON object")))
    (substring cleaned start end)))

(defun org-ai-skills--plist-value (plist &rest keys)
  "Return first non-nil value in PLIST matching KEYS."
  (let ((value nil))
    (while (and keys (null value))
      (setq value (plist-get plist (car keys)))
      (setq keys (cdr keys)))
    value))

(defun org-ai-skills--chunk-list (items size)
  "Split ITEMS into chunks of SIZE."
  (let ((out nil)
        (rest items))
    (while rest
      (push (cl-subseq rest 0 (min size (length rest))) out)
      (setq rest (nthcdr size rest)))
    (nreverse out)))

(defun org-ai-skills--split-step-by-skill-limit (step)
  "Split STEP into multiple steps according to max skills setting."
  (let* ((skills (copy-sequence (or (plist-get step :skills) nil)))
         (chunks (org-ai-skills--chunk-list skills org-ai-skills-planner-max-skills-per-step))
         (base-id (or (plist-get step :step-id) "step"))
         (index 1)
         (split-steps nil))
    (dolist (chunk chunks)
      (let ((new-step (copy-sequence step)))
        (setq new-step (plist-put new-step :step-id
                                  (format "%s-part-%d" base-id index)))
        (setq new-step (plist-put new-step :skills chunk))
        (setq new-step (plist-put new-step :composition-reason
                                  (format "Auto-split from %s due to max_skills_per_step=%d"
                                          base-id
                                          org-ai-skills-planner-max-skills-per-step)))
        (push new-step split-steps)
        (setq index (1+ index))))
    (nreverse split-steps)))

(defun org-ai-skills--validate-planner-step (step known-skill-ids)
  "Validate one planner STEP against KNOWN-SKILL-IDS.
Return a list of one or more normalized steps."
  (let* ((step-id (or (plist-get step :step-id)
                      (signal 'org-ai-skills-planner-error
                              (list "Planner step missing step_id"))))
         (goal (or (plist-get step :goal) ""))
         (skills-raw (or (plist-get step :skills) nil))
         (skills (mapcar #'org-ai-skills--normalize-step-skill-entry skills-raw)))
    (unless (and (listp skills) skills)
      (signal 'org-ai-skills-planner-error
              (list (format "Planner step %s must contain non-empty skills list" step-id))))
    (dolist (skill-id skills)
      (unless (member skill-id known-skill-ids)
        (signal 'org-ai-skills-planner-error
                (list (format "Planner step %s references unknown skill id: %s"
                              step-id skill-id)))))
    (let ((normalized
           (list :step-id step-id
                 :goal goal
                 :skills skills
                 :input-from (or (plist-get step :input-from) '("previous"))
                 :expected-output (or (plist-get step :expected-output) "")
                 :composition-reason (or (plist-get step :composition-reason) ""))))
      (if (<= (length skills) org-ai-skills-planner-max-skills-per-step)
          (list normalized)
        (pcase org-ai-skills-planner-overflow-strategy
          ('split (org-ai-skills--split-step-by-skill-limit normalized))
          (_ (signal 'org-ai-skills-planner-error
                     (list (format "Planner step %s exceeds max skills per step (%d > %d)"
                                   step-id
                                   (length skills)
                                   org-ai-skills-planner-max-skills-per-step)))))))))

(defun org-ai-skills--normalize-step-skill-entry (entry)
  "Normalize planner step skill ENTRY into a skill-id string."
  (cond
   ((stringp entry) entry)
   ((and (listp entry)
         (org-ai-skills--plist-value entry :skill-id :skill_id))
    (org-ai-skills--plist-value entry :skill-id :skill_id))
   (t entry)))

(defun org-ai-skills--planner-step-has-skills-p (step)
  "Return non-nil when normalized planner STEP contains at least one skill id."
  (let* ((skills-raw (or (plist-get step :skills) nil))
         (skills (mapcar #'org-ai-skills--normalize-step-skill-entry skills-raw)))
    (and (listp skills) skills)))

(defun org-ai-skills--normalize-planner-candidate (candidate known-skill-ids)
  "Normalize one planner CANDIDATE against KNOWN-SKILL-IDS."
  (let* ((skill-id (or (org-ai-skills--plist-value candidate :skill-id :skill_id)
                       (signal 'org-ai-skills-planner-error
                               (list "Planner candidate missing skill_id"))))
         (why (or (plist-get candidate :why) ""))
         (score (or (plist-get candidate :score) 0.0)))
    (unless (member skill-id known-skill-ids)
      (signal 'org-ai-skills-planner-error
              (list (format "Planner candidate references unknown skill id: %s" skill-id))))
    (list :skill-id skill-id :why why :score score)))

(defun org-ai-skills--normalize-planner-step (step)
  "Normalize planner STEP keys."
  (list :step-id (or (org-ai-skills--plist-value step :step-id :step_id) "")
        :goal (or (plist-get step :goal) "")
        :skills (or (plist-get step :skills) nil)
        :input-from (or (org-ai-skills--plist-value step :input-from :input_from) nil)
        :expected-output (or (org-ai-skills--plist-value step :expected-output :expected_output) "")
        :composition-reason (or (org-ai-skills--plist-value step :composition-reason :composition_reason) "")))

(defun org-ai-skills-parse-planner-response (text metadata-list &optional allow-empty-plan)
  "Parse planner TEXT into normalized structure using METADATA-LIST.
When ALLOW-EMPTY-PLAN is non-nil, an empty plan is accepted."
  (let* ((json-object (org-ai-skills--extract-json-object text))
         (raw (condition-case err
                  (json-parse-string
                   json-object
                   :object-type 'plist
                   :array-type 'list
                   :null-object nil
                   :false-object nil)
                (error
                 (signal 'org-ai-skills-planner-error
                         (list
                          (format
                           "Planner response contains malformed JSON (%s). Common causes: truncated model output or non-JSON text in response."
                           (error-message-string err)))))))
         (known-skill-ids
          (mapcar (lambda (meta) (plist-get meta :skill-id))
                  metadata-list))
         (candidates-raw (or (plist-get raw :candidates) nil))
         (plan-raw (or (plist-get raw :plan) nil))
         (normalized-plan-raw
          (mapcar #'org-ai-skills--normalize-planner-step plan-raw))
         (effective-plan-raw
          (if allow-empty-plan
              (cl-remove-if-not #'org-ai-skills--planner-step-has-skills-p normalized-plan-raw)
            normalized-plan-raw))
         (replan-raw
          (or (org-ai-skills--plist-value raw :replan-signal :replan_signal)
              nil)))
    (unless (listp plan-raw)
      (signal 'org-ai-skills-planner-error
              (list "Planner response must include plan list")))
    (when (and (not allow-empty-plan) (null effective-plan-raw))
      (signal 'org-ai-skills-planner-error
              (list "Planner response must include non-empty plan")))
    (when (> (length effective-plan-raw) org-ai-skills-planner-max-steps)
      (signal 'org-ai-skills-planner-error
              (list (format "Planner response exceeds max steps (%d > %d)"
                            (length effective-plan-raw)
                            org-ai-skills-planner-max-steps))))
    (let* ((normalized-candidates
            (mapcar (lambda (candidate)
                      (org-ai-skills--normalize-planner-candidate candidate known-skill-ids))
                    candidates-raw))
           (normalized-steps
            (apply #'append
                   (mapcar (lambda (step)
                             (org-ai-skills--validate-planner-step
                              step
                              known-skill-ids))
                           effective-plan-raw)))
           (replan-enabled (and replan-raw
                                (org-ai-skills--plist-value replan-raw :enabled)))
           (replan-condition (and replan-raw
                                  (or (plist-get replan-raw :condition) ""))))
      (when (> (length normalized-steps) org-ai-skills-planner-max-steps)
        (signal 'org-ai-skills-planner-error
                (list (format "Normalized plan exceeds max steps (%d > %d)"
                              (length normalized-steps)
                              org-ai-skills-planner-max-steps))))
      (list :candidates normalized-candidates
            :plan normalized-steps
            :replan-signal (list :enabled (if replan-enabled t nil)
                                 :condition replan-condition)))))

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

(defun org-ai-skills-build-skill-context (skill subtree)
  "Build normalized skill context bundle from SKILL and SUBTREE."
  (list
   :meta (list :skill-id (plist-get skill :skill-id)
               :skill-title (plist-get skill :title)
               :tags (plist-get skill :tags))
   :description (plist-get skill :description)
   :outputs (or (plist-get skill :outputs) nil)
   :contracts (or (plist-get skill :contracts) nil)
   :requirements (or (plist-get skill :requirements) nil)
   :function-calls (or (org-ai-skills-active-skill-function-calls skill) nil)
   :raw-sections (plist-get skill :raw-sections)
   :source-subtree (list :headline (plist-get subtree :heading)
                         :level (plist-get subtree :level)
                         :path (plist-get subtree :path)
                         :context-mode (plist-get subtree :context-mode)
                         :levels-up (plist-get subtree :levels-up)
                         :text (plist-get subtree :text))))

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
        (heading (org-get-heading t t t t))
        (path (mapconcat #'identity (org-ai-skills--heading-path-at-point) "/")))
    (save-excursion
      (org-end-of-subtree t t)
      (list :begin begin
            :end (point)
            :level level
            :heading heading
            :path path
            :text (buffer-substring-no-properties begin (point))))))

(defun org-ai-skills--heading-path-at-point ()
  "Return stable heading path at point from root to current heading."
  (let ((parts nil))
    (save-excursion
      (unless (org-at-heading-p)
        (org-back-to-heading t))
      (push (org-get-heading t t t t) parts)
      (while (org-up-heading-safe)
        (push (org-get-heading t t t t) parts)))
    parts))

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
         (skill-context (org-ai-skills-build-skill-context skill subtree))
         (outputs (or (plist-get skill :outputs) nil))
         (contracts (or (plist-get skill :contracts) nil))
         (requirements (or (plist-get skill :requirements) nil))
         (function-calls (or (org-ai-skills-active-skill-function-calls skill) nil))
         (outputs-block
          (if outputs
              (concat "Outputs:\n- " (string-join outputs "\n- ") "\n\n")
            ""))
         (contracts-block
          (if contracts
              (concat "Contracts:\n- " (string-join contracts "\n- ") "\n\n")
            ""))
         (requirements-block
          (if requirements
              (concat "Requirements:\n- " (string-join requirements "\n- ") "\n\n")
            ""))
         (function-calls-block
          (if function-calls
              (concat
               "Possible function calls:\n"
               (mapconcat
                (lambda (fn-spec)
                  (format "- %s (when: %s, args: %s)"
                          (or (plist-get fn-spec :name) "")
                          (or (plist-get fn-spec :when) "")
                          (or (plist-get fn-spec :args) "")))
                function-calls
                "\n")
               "\n\n")
            ""))
         (rewrite-prompt
          (concat (plist-get base-payload :prompt)
                  "\n\nContext mode: "
                  (symbol-name mode)
                  "\nLevels up: "
                  (number-to-string levels-up)
                  "\nHeading path: "
                  (or (plist-get subtree :path) heading)
                  "\n\nSkill description:\n"
                  (or (plist-get skill :description) "")
                  "\n\n"
                  outputs-block
                  contracts-block
                  requirements-block
                  function-calls-block
                  "\n\nOutput requirements:\n"
                  "- Return only the rewritten Org subtree.\n"
                  "- Do not include explanations, analysis, or progress notes.\n"
                  "- Do not wrap output in code fences.\n"
                  "- Keep Org syntax valid.\n\n"
                  "Rewrite the following Org subtree:\n\n"
                  (plist-get subtree :text))))
    (list :event-type 'rewrite
          :request-role 'execution
          :skill-id (plist-get base-payload :skill-id)
          :skill-title (plist-get base-payload :skill-title)
          :goal goal
          :description (plist-get base-payload :description)
          :tags (plist-get base-payload :tags)
          :headline heading
          :context-mode mode
          :levels-up levels-up
          :source-text (plist-get subtree :text)
          :skill-context skill-context
          :prompt rewrite-prompt)))

(defun org-ai-skills--run-state-latest-output (run-state)
  "Return latest step output from RUN-STATE."
  (or (plist-get run-state :latest-output)
      (let ((steps (plist-get run-state :steps)))
        (when steps
          (plist-get (car (last steps)) :output)))))

(defun org-ai-skills-build-step-request (step run-state loaded-skills)
  "Build one execution request from STEP, RUN-STATE, and LOADED-SKILLS."
  (let* ((task (or (plist-get run-state :task) ""))
         (subtree (plist-get run-state :subtree))
         (input-text (or (org-ai-skills--run-state-latest-output run-state)
                         (plist-get subtree :text)
                         ""))
         (skill-block
          (mapconcat
           (lambda (skill)
             (let ((outputs (plist-get skill :outputs))
                   (contracts (plist-get skill :contracts))
                   (requirements (plist-get skill :requirements))
                   (function-calls (org-ai-skills-active-skill-function-calls skill)))
               (concat
                (format "- Skill: %s (%s)\n"
                        (plist-get skill :skill-id)
                        (plist-get skill :title))
                (format "  Description: %s\n" (or (plist-get skill :description) ""))
                (if outputs
                    (format "  Outputs: %s\n" (string-join outputs "; "))
                  "")
                (if contracts
                    (format "  Contracts: %s\n" (string-join contracts "; "))
                  "")
                (if requirements
                    (format "  Requirements: %s\n" (string-join requirements "; "))
                  "")
                (if function-calls
                    (format "  Function Calls: %s\n"
                            (mapconcat
                             (lambda (fn-spec)
                               (or (plist-get fn-spec :name) ""))
                             function-calls
                             ", "))
                  ""))))
           loaded-skills
           ""))
         (prompt
          (concat
           "You are executing one org-ai-skills plan step.\n"
           "Return only the transformed Org content. No analysis.\n\n"
           "Task:\n" task "\n\n"
           "Step:\n"
           (format "- step_id: %s\n" (plist-get step :step-id))
           (format "- goal: %s\n" (or (plist-get step :goal) ""))
           (format "- expected_output: %s\n" (or (plist-get step :expected-output) ""))
           (format "- composition_reason: %s\n\n" (or (plist-get step :composition-reason) ""))
           "Selected skills:\n"
           skill-block
           "\nInput content:\n\n"
           input-text)))
    (list :event-type 'step-execution
          :request-role 'execution
          :step-id (plist-get step :step-id)
          :skill-ids (plist-get step :skills)
          :composition-reason (or (plist-get step :composition-reason) "")
          :plan-revision (or (plist-get run-state :plan-revision) 1)
          :skill-contexts (mapcar
                           (lambda (skill)
                             (org-ai-skills-build-skill-context skill subtree))
                           loaded-skills)
          :prompt prompt)))

(defun org-ai-skills--record-run-step (run-state step output)
  "Append STEP and OUTPUT to RUN-STATE."
  (let* ((steps (or (plist-get run-state :steps) nil))
         (entry (list :step-id (plist-get step :step-id)
                      :status 'done
                      :skills (plist-get step :skills)
                      :goal (plist-get step :goal)
                      :composition-reason (plist-get step :composition-reason)
                      :output output)))
    (plist-put (plist-put run-state :steps (append steps (list entry)))
               :latest-output output)))

(defun org-ai-skills-execute-plan-step (step run-state callback &optional directory)
  "Execute one planner STEP with RUN-STATE, then invoke CALLBACK.
Only skills referenced by STEP are loaded from DIRECTORY."
  (let* ((skill-ids (or (plist-get step :skills) nil))
         (loaded-skills (mapcar (lambda (skill-id)
                                  (org-ai-skills-load-skill-by-id skill-id directory))
                                skill-ids))
         (request nil)
         (dispatched nil))
    (unwind-protect
        (progn
          (dolist (skill loaded-skills)
            (org-ai-skills-apply-skill-function-calls skill))
          (setq request (org-ai-skills-build-step-request step run-state loaded-skills))
          (org-ai-skills-gptel-dispatch-rewrite
           request
           (lambda (&rest response)
             (unwind-protect
                 (let ((raw (apply #'org-ai-skills--extract-gptel-response-text-if-ready response)))
                   (when raw
                     (let* ((output (org-ai-skills--extract-subtree-body raw))
                            (updated-run-state (org-ai-skills--record-run-step run-state step output)))
                       (funcall callback updated-run-state output))))
               (dolist (skill loaded-skills)
                 (org-ai-skills-exclude-skill-function-calls skill)))))
          (setq dispatched t))
      (unless dispatched
        (dolist (skill loaded-skills)
          (org-ai-skills-exclude-skill-function-calls skill))))))

(defun org-ai-skills-maybe-replan (run-state planner-response)
  "Return revised plan from PLANNER-RESPONSE when RUN-STATE should replan."
  (let* ((latest-output (or (org-ai-skills--run-state-latest-output run-state) ""))
         (signal (plist-get planner-response :replan-signal))
         (planner-requests-replan (plist-get signal :enabled))
         (marker-replan (string-match-p "\\[\\[REPLAN\\]\\]" latest-output)))
    (when (or planner-requests-replan marker-replan)
      (when (>= (or (plist-get run-state :replans) 0) org-ai-skills-planner-max-replans)
        (signal 'org-ai-skills-planner-error
                (list (format "Maximum replans reached (%d)"
                              org-ai-skills-planner-max-replans))))
      (plist-get planner-response :plan))))

(defun org-ai-skills--completed-step-ids (run-state)
  "Return completed step id list from RUN-STATE."
  (mapcar (lambda (step) (plist-get step :step-id))
          (or (plist-get run-state :steps) nil)))

(defun org-ai-skills--filter-pending-steps (plan run-state)
  "Return PLAN steps that are not yet completed in RUN-STATE."
  (let ((done-ids (org-ai-skills--completed-step-ids run-state)))
    (cl-remove-if
     (lambda (step)
       (member (plist-get step :step-id) done-ids))
     plan)))

(defun org-ai-skills--request-planner-plan (task metadata run-state callback)
  "Request planner plan using TASK, METADATA, and RUN-STATE, then CALLBACK."
  (let ((request (org-ai-skills-build-planner-request task metadata run-state)))
    (org-ai-skills-gptel-dispatch-rewrite
     request
     (lambda (&rest response)
       (let ((text (apply #'org-ai-skills--extract-gptel-response-text-if-ready response)))
         (when text
           (let ((parsed (org-ai-skills-parse-planner-response
                          text metadata (and (listp (plist-get run-state :steps))
                                             (plist-get run-state :steps)))))
             (funcall callback parsed))))))))

(defun org-ai-skills--run-plan-steps (task metadata run-state plan callback &optional directory)
  "Run PLAN steps recursively for TASK and METADATA.
Invoke CALLBACK with final run-state when done."
  (let ((pending (org-ai-skills--filter-pending-steps plan run-state)))
    (if (null pending)
        (funcall callback
                 (plist-put run-state :final-output
                            (org-ai-skills--run-state-latest-output run-state)))
      (org-ai-skills-execute-plan-step
       (car pending)
       run-state
       (lambda (updated-run-state _output)
         (if (not org-ai-skills-planner-auto-replan)
             (org-ai-skills--run-plan-steps
              task metadata updated-run-state (cdr pending) callback directory)
           (org-ai-skills--request-planner-plan
            task
            metadata
            updated-run-state
            (lambda (planner-response)
              (let ((revised-plan
                     (org-ai-skills-maybe-replan updated-run-state planner-response)))
                (if revised-plan
                    (let ((next-state
                           (plist-put
                            (plist-put updated-run-state
                                       :plan-revision
                                       (1+ (or (plist-get updated-run-state
                                                           :plan-revision)
                                               1)))
                            :replans (1+ (or (plist-get updated-run-state :replans) 0)))))
                      (org-ai-skills--run-plan-steps
                       task metadata next-state revised-plan callback directory))
                  (org-ai-skills--run-plan-steps
                   task metadata updated-run-state (cdr pending) callback directory)))))))
       directory))))

(defun org-ai-skills-run-task-with-planner (task subtree &optional options callback)
  "Run TASK on SUBTREE using autonomous planner flow.
OPTIONS is a plist; CALLBACK receives final run-state."
  (let* ((directory (or (plist-get options :directory) org-ai-skills-skill-dir))
         (metadata (org-ai-skills-load-skill-metadata directory))
         (run-state (list :run-id (format-time-string "%Y%m%d%H%M%S")
                          :task task
                          :subtree subtree
                          :metadata-snapshot metadata
                          :plan-revision 1
                          :replans 0
                          :steps nil
                          :latest-output nil
                          :final-output nil
                          :events nil))
         (final-callback (or callback (lambda (_state) nil))))
    (org-ai-skills--request-planner-plan
     task
     metadata
     run-state
     (lambda (planner-response)
       (let ((plan (plist-get planner-response :plan)))
         (org-ai-skills--run-plan-steps task metadata run-state plan final-callback directory))))
    run-state))

(defun org-ai-skills--append-debug-entry (request)
  "Append one debug REQUEST entry when debug mode is enabled."
  (when org-ai-skills-debug-enabled
    (let* ((timestamp (format-time-string "%Y-%m-%d %H:%M:%S %z"))
           (source (plist-get (plist-get request :skill-context) :source-subtree))
           (event-type (or (plist-get request :event-type) 'rewrite))
           (request-role (or (plist-get request :request-role) ""))
           (effective-model (or (plist-get request :effective-model) ""))
           (system-fingerprint (or (plist-get request :effective-system-prompt-fingerprint) ""))
           (entry
            (concat
             (format "=== org-ai-skills gptel dispatch @ %s ===\n" timestamp)
             (format "Event: %s\n" event-type)
             (format "Request role: %s\n" request-role)
             (format "Effective model: %s\n" effective-model)
             (format "System prompt fingerprint: %s\n" system-fingerprint)
             (format "Buffer: %s\n" (or (plist-get request :buffer-name) ""))
             (format "File: %s\n" (or (plist-get request :buffer-file) ""))
             (format "Headline: %s\n" (or (plist-get source :headline) ""))
             (format "Path: %s\n" (or (plist-get source :path) ""))
             (format "Context mode: %s\n" (or (plist-get request :context-mode) ""))
             (format "Levels up: %s\n" (or (plist-get request :levels-up) ""))
             (format "Metadata count: %s\n" (or (plist-get request :metadata-count) ""))
             (format "Step id: %s\n" (or (plist-get request :step-id) ""))
             (format "Skill ids: %s\n" (or (plist-get request :skill-ids) ""))
             (format "Composition reason: %s\n" (or (plist-get request :composition-reason) ""))
             "Prompt:\n"
             (or (plist-get request :prompt) "")
             "\n\nRequest plist:\n"
             (pp-to-string request)
             "\n")))
      (setq org-ai-skills--last-debug-entry entry)
      (with-current-buffer (get-buffer-create org-ai-skills-debug-buffer-name)
        (goto-char (point-max))
        (insert entry)))))

(defun org-ai-skills-debug-toggle (&optional enabled)
  "Toggle org-ai-skills debug logging.
If ENABLED is non-nil, set debug mode accordingly."
  (interactive)
  (setq org-ai-skills-debug-enabled
        (if (null enabled)
            (not org-ai-skills-debug-enabled)
          enabled))
  (message "org-ai-skills debug %s"
           (if org-ai-skills-debug-enabled "enabled" "disabled")))

(defun org-ai-skills-debug-show-last ()
  "Show the most recent debug entry."
  (interactive)
  (if (string-empty-p (or org-ai-skills--last-debug-entry ""))
      (message "No org-ai-skills debug entries yet")
    (with-current-buffer (get-buffer-create org-ai-skills-debug-buffer-name)
      (goto-char (point-max))
      (pop-to-buffer (current-buffer)))))

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

(defun org-ai-skills--extract-gptel-response-text-if-ready (&rest response)
  "Return text when RESPONSE is a final text callback, else nil.
Interim callback events such as tool-call, tool-result, reasoning chunks,
or stream completion markers are ignored and return nil."
  (let ((first (car response)))
    (if (or (eq first t)
            (and (consp first)
                 (memq (car first) '(tool-call tool-result reasoning))))
        nil
      (apply #'org-ai-skills--extract-gptel-response-text response))))

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
  "Replace SUBTREE region with REWRITTEN-TEXT.
Preserve target heading and property drawer by replacing subtree body."
  (unless (stringp rewritten-text)
    (org-ai-skills--signal-org-context-error "Rewritten text must be a string"))
  (let ((begin (plist-get subtree :begin))
        (end (plist-get subtree :end)))
    (unless (and begin end (<= begin end))
      (org-ai-skills--signal-org-context-error
       "Invalid subtree range for rewrite"))
    (let ((new-body "")
          (existing-heading-line "")
          (existing-drawer ""))
      (with-temp-buffer
        (insert rewritten-text)
        (goto-char (point-min))
        (if (re-search-forward "^\\*+\\s-+" nil t)
            (progn
              (beginning-of-line)
              (forward-line 1)
              (when (looking-at-p "^[ \t]*:PROPERTIES:[ \t]*$")
                (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                  (forward-line 1)))
              (setq new-body (buffer-substring-no-properties (point) (point-max))))
          (setq new-body rewritten-text)))
      (setq new-body (replace-regexp-in-string "\\`\n+" "" (or new-body "")))
      (save-excursion
        (org-fold-core-ignore-modifications
         (goto-char begin)
         (setq existing-heading-line
               (buffer-substring-no-properties
                (line-beginning-position)
                (min (point-max) (1+ (line-end-position)))))
         (forward-line 1)
         (when (looking-at-p "^[ \t]*:PROPERTIES:[ \t]*$")
           (let ((drawer-start (point)))
             (when (re-search-forward "^[ \t]*:END:[ \t]*$" end t)
               (forward-line 1)
               (setq existing-drawer
                     (buffer-substring-no-properties drawer-start (point))))))
         (delete-region begin end)
         (insert existing-heading-line existing-drawer new-body)
         (unless (or (bolp) (string-suffix-p "\n" new-body))
           (insert "\n")))))))

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
          (let* ((path (mapconcat #'identity (org-ai-skills--heading-path-at-point) "/"))
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

(define-derived-mode org-ai-skills-control-mode special-mode "Org-AI-Control"
  "Major mode for org-ai-skills control workspace."
  (setq-local truncate-lines t))

(defun org-ai-skills--ui-control-buffer ()
  "Return control buffer."
  (get-buffer-create org-ai-skills-control-buffer-name))

(defun org-ai-skills--ui-run-get (key)
  "Return KEY from current UI run state."
  (plist-get org-ai-skills--ui-run-state key))

(defun org-ai-skills--ui-run-set (key value)
  "Set KEY in current UI run state to VALUE."
  (setq org-ai-skills--ui-run-state
        (plist-put org-ai-skills--ui-run-state key value)))

(defun org-ai-skills--ui-clear-overlay ()
  "Remove source overlay from current UI run state."
  (let ((ov (org-ai-skills--ui-run-get :overlay)))
    (when (overlayp ov)
      (delete-overlay ov)))
  (org-ai-skills--ui-run-set :overlay nil))

(defun org-ai-skills--ui-set-overlay (state)
  "Set source overlay STATE for current UI run."
  (let* ((source-buffer (org-ai-skills--ui-run-get :source-buffer))
         (begin (org-ai-skills--ui-run-get :begin))
         (end (org-ai-skills--ui-run-get :end)))
    (org-ai-skills--ui-clear-overlay)
    (when (and (buffer-live-p source-buffer)
               (markerp begin)
               (marker-buffer begin)
               (markerp end)
               (marker-buffer end))
      (with-current-buffer source-buffer
        (let ((ov (make-overlay begin end source-buffer t t)))
          (overlay-put ov 'evaporate t)
          (overlay-put ov 'priority 1000)
          (overlay-put ov 'face
                       (pcase state
                         ('ready 'org-ai-skills-ui-overlay-ready-face)
                         (_ 'org-ai-skills-ui-overlay-running-face)))
          (overlay-put ov 'help-echo
                       (pcase state
                         ('ready "org-ai-skills: candidate ready")
                         (_ "org-ai-skills: processing")))
          (org-ai-skills--ui-run-set :overlay ov))))))

(defun org-ai-skills--ui-candidate-list-display (candidate index preview-width selected-id)
  "Return compact one-line display for CANDIDATE at INDEX.
PREVIEW-WIDTH bounds preview text width. SELECTED-ID marks selected row."
  (let* ((candidate-id (or (plist-get candidate :candidate-id) ""))
         (c-status (or (plist-get candidate :status) "generated"))
         (status-mark (pcase c-status
                        ("applied" "A")
                        ("discarded" "D")
                        (_ "G")))
         (selected-mark (if (equal candidate-id selected-id) "*" " "))
         (text (or (plist-get candidate :output-text) ""))
         (preview (replace-regexp-in-string "[\n\r\t ]+" " " text)))
    (format " %s%02d [%s] %s"
            selected-mark
            (1+ index)
            status-mark
            (truncate-string-to-width preview (max 16 preview-width) nil nil t))))

(defun org-ai-skills-ui-refresh-control-buffer ()
  "Re-render control buffer content from current runtime state."
  (interactive)
  (let* ((buffer (org-ai-skills--ui-control-buffer))
         (status (or (org-ai-skills--ui-run-get :status) 'idle))
         (progress (or (org-ai-skills--ui-run-get :progress) "idle"))
         (running (eq status 'running))
         (run-type (org-ai-skills--ui-run-get :run-type))
         (task (or (org-ai-skills--ui-run-get :task) ""))
         (preset (or (org-ai-skills--ui-run-get :preset-id) ""))
         (slot-key (org-ai-skills--ui-run-get :slot-key))
         (candidates (if (stringp slot-key)
                         (org-ai-skills--load-slot-candidates slot-key)
                       nil))
         (heading (or (org-ai-skills--ui-run-get :heading) ""))
         (selected (org-ai-skills--ui-run-get :selected-candidate))
         (selected-id (or (and selected (plist-get selected :candidate-id)) "none"))
         (rerun-enabled (and (functionp (org-ai-skills--ui-run-get :rerun-fn))
                             (not running)))
         (adjust-enabled (and (memq run-type '(planner rewrite))
                              (not running)))
         (candidate-enabled (and (listp candidates) (> (length candidates) 0)))
         (apply-enabled (and candidate-enabled (not running)))
         (discard-enabled (and candidate-enabled (not running)))
         (stop-enabled running)
         (key-face (lambda (enabled)
                     (if enabled
                         'font-lock-keyword-face
                       'shadow))))
    (with-current-buffer buffer
      (org-ai-skills-control-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "org-ai-skills control\n\n")
        (insert (format "Status: %s\n" status))
        (insert (format "Progress: %s\n" progress))
        (insert (format "Heading: %s\n" heading))
        (insert (format "Task/Preset: %s%s%s\n"
                        task
                        (if (and (not (string-empty-p task))
                                 (not (string-empty-p preset)))
                            " / "
                          "")
                        preset))
        (insert (format "Selected candidate: %s\n\n" selected-id))
        (insert "Keys:\n")
        (insert (propertize "  s stop run" 'face (funcall key-face stop-enabled)) "\n")
        (insert (propertize "  g rerun" 'face (funcall key-face rerun-enabled)) "\n")
        (insert (propertize "  t adjust task/instruction" 'face (funcall key-face adjust-enabled)) "\n")
        (insert (propertize "  c select candidate (minibuffer)" 'face (funcall key-face candidate-enabled)) "\n")
        (insert (propertize "  a apply selected candidate" 'face (funcall key-face apply-enabled)) "\n")
        (insert (propertize "  d discard selected candidate" 'face (funcall key-face discard-enabled)) "\n")
        (insert (propertize "  r refresh" 'face (funcall key-face t)) "\n")
        (insert (propertize "  q close workspace" 'face (funcall key-face t)) "\n")
        (insert "\n")
        (insert (format "Candidates (%d):\n" (length candidates)))
        (if (null candidates)
            (insert "  (none)\n")
          (let* ((panel-width (max 24 (window-total-width (selected-window))))
                 (preview-width (- panel-width 12))
                 (idx 0))
            (dolist (candidate candidates)
              (insert (org-ai-skills--ui-candidate-list-display
                       candidate idx preview-width selected-id)
                      "\n")
              (setq idx (1+ idx)))))
        (goto-char (point-min))))))

(defun org-ai-skills--ui-set-status (status progress)
  "Update STATUS and PROGRESS in UI state."
  (org-ai-skills--ui-run-set :status status)
  (org-ai-skills--ui-run-set :progress progress)
  (org-ai-skills-ui-refresh-control-buffer))

(defun org-ai-skills-ui-open-workspace (&optional source-buffer)
  "Open two-column workspace for SOURCE-BUFFER and control panel."
  (interactive)
  (let* ((source (or source-buffer (current-buffer)))
         (control (org-ai-skills--ui-control-buffer))
         (already-open (get-buffer-window control)))
    (unless already-open
      (setq org-ai-skills--ui-window-configuration (current-window-configuration))
      (delete-other-windows)
      (let* ((left (selected-window))
             (total (window-total-width left))
             (half-width (max 24 (/ total 2)))
             (control-width (max 24
                                 (min org-ai-skills-ui-control-window-width
                                      half-width
                                      (max 24 (- total 20)))))
             (source-width (max 20 (- total control-width)))
             (right (selected-window))
             (left (split-window right source-width 'left)))
        (set-window-buffer left control)
        (set-window-buffer right source)
        (let ((current-left (window-total-width left)))
          (when (> current-left control-width)
            (ignore-errors
              (window-resize left (- control-width current-left) t t))))
        ;; On first activation, focus control panel for quick key-driven actions.
        (select-window left)))
    (org-ai-skills-ui-refresh-control-buffer)))

(defun org-ai-skills-ui-close-workspace ()
  "Close control workspace and restore previous windows."
  (interactive)
  (org-ai-skills--ui-clear-overlay)
  (let ((control (org-ai-skills--ui-control-buffer)))
    (when (buffer-live-p control)
      (when-let ((win (get-buffer-window control t)))
        (delete-window win))))
  (when (window-configuration-p org-ai-skills--ui-window-configuration)
    (set-window-configuration org-ai-skills--ui-window-configuration)
    (setq org-ai-skills--ui-window-configuration nil)))

(defun org-ai-skills--ui-start-run (run-state)
  "Start new UI RUN-STATE and render workspace."
  (org-ai-skills--ui-clear-overlay)
  (setq org-ai-skills--ui-run-state run-state)
  (when (and org-ai-skills-ui-auto-open
             (org-ai-skills--ui-run-get :interactive-run))
    (org-ai-skills-ui-open-workspace (org-ai-skills--ui-run-get :source-buffer)))
  (org-ai-skills--ui-set-overlay 'running)
  (org-ai-skills--ui-set-status 'running (or (org-ai-skills--ui-run-get :progress) "running"))
  org-ai-skills--ui-run-state)

(defun org-ai-skills--ui-stop-requested-p (run-id)
  "Return non-nil when RUN-ID has a stop request."
  (and (equal (org-ai-skills--ui-run-get :run-id) run-id)
       (org-ai-skills--ui-run-get :stop-requested)))

(defun org-ai-skills-ui-stop-run ()
  "Stop current run from control workspace."
  (interactive)
  (if (not (eq (org-ai-skills--ui-run-get :status) 'running))
      (message "org-ai-skills: stop unavailable (status: %s)"
               (or (org-ai-skills--ui-run-get :status) 'idle))
    (org-ai-skills--ui-run-set :stop-requested t)
    (org-ai-skills--ui-clear-overlay)
    (org-ai-skills--ui-set-status 'canceled "canceled")
    (message "org-ai-skills: stop requested")))

(defun org-ai-skills-ui-rerun ()
  "Re-run current task context."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: rerun unavailable while running")
    (let ((rerun-fn (org-ai-skills--ui-run-get :rerun-fn)))
      (unless (functionp rerun-fn)
        (org-ai-skills--signal-org-context-error "No rerun action available"))
      (org-ai-skills--ui-set-status 'running "rerun-dispatched")
      (org-ai-skills--ui-set-overlay 'running)
      (message "org-ai-skills: rerun dispatched")
      (funcall rerun-fn))))

(defun org-ai-skills-ui-adjust-task-or-instruction ()
  "Adjust planner task or rewrite instruction, then rerun."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: adjust unavailable while running")
    (let ((run-type (org-ai-skills--ui-run-get :run-type)))
    (pcase run-type
      ('planner
       (let* ((target (org-ai-skills--ui-run-get :target))
              (current-task (or (org-ai-skills--ui-run-get :task) ""))
              (task (read-string "Planner task: " current-task)))
         (org-ai-skills--ui-run-set
          :rerun-fn
          (lambda ()
            (interactive)
            (org-ai-skills-org-plan-and-run-subtree target task t)))
         (org-ai-skills-org-plan-and-run-subtree target task t)))
      ('rewrite
       (let* ((target (org-ai-skills--ui-run-get :target))
              (skill (org-ai-skills--ui-run-get :skill))
              (current-instruction (or (org-ai-skills--ui-run-get :instruction) ""))
              (instruction (read-string "Rewrite instruction: " current-instruction)))
         (org-ai-skills--ui-run-set :instruction instruction)
         (org-ai-skills--ui-run-set
          :rerun-fn
          (lambda ()
            (interactive)
            (org-ai-skills-org-rewrite-subtree target skill instruction t)))
         (org-ai-skills-org-rewrite-subtree target skill instruction t)))
      (_
       (org-ai-skills--signal-org-context-error "Unsupported run type"))))))

(defun org-ai-skills-ui-select-candidate ()
  "Select one candidate in minibuffer and cache it in UI state."
  (interactive)
  (let* ((slot-key (org-ai-skills--ui-run-get :slot-key))
         (candidate (org-ai-skills--read-slot-candidate slot-key nil)))
    (org-ai-skills--ui-run-set :selected-candidate candidate)
    ;; Decision: ready overlay clears immediately after candidate switch.
    (org-ai-skills--ui-clear-overlay)
    (org-ai-skills--ui-set-status 'ready "candidate-selected")
    candidate))

(defun org-ai-skills-ui-apply-selected-candidate ()
  "Apply selected candidate from UI state."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: apply unavailable while running")
    (let* ((candidate (or (org-ai-skills--ui-run-get :selected-candidate)
                          (org-ai-skills-ui-select-candidate)))
           (begin (org-ai-skills--ui-run-get :begin))
           (end (org-ai-skills--ui-run-get :end)))
      (unless candidate
        (org-ai-skills--signal-version-store-error "No selected candidate"))
      (org-ai-skills-org-apply-candidate-to-subtree
       (list :begin begin :end end)
       candidate)
      (org-ai-skills--ui-clear-overlay)
      (org-ai-skills--ui-set-status 'applied "applied"))))

(defun org-ai-skills-ui-discard-selected-candidate ()
  "Discard selected candidate from UI state."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: discard unavailable while running")
    (let* ((candidate (or (org-ai-skills--ui-run-get :selected-candidate)
                          (org-ai-skills-ui-select-candidate)))
           (slot-key (and candidate (plist-get candidate :slot-key)))
           (candidate-id (and candidate (plist-get candidate :candidate-id))))
      (unless candidate
        (org-ai-skills--signal-version-store-error "No selected candidate"))
      (org-ai-skills--update-candidate-status slot-key candidate-id "discarded")
      (org-ai-skills--ui-run-set :selected-candidate nil)
      (org-ai-skills--ui-clear-overlay)
      (org-ai-skills--ui-set-status 'ready "candidate-discarded")
      (message "org-ai-skills candidate discarded: %s" candidate-id))))

(defun org-ai-skills--signal-version-store-error (message)
  "Signal version store error with MESSAGE."
  (signal 'org-ai-skills-version-store-error (list message)))

(defun org-ai-skills--ensure-version-store-dir ()
  "Ensure candidate version store directory exists."
  (condition-case err
      (progn
        (make-directory org-ai-skills-version-store-dir t)
        org-ai-skills-version-store-dir)
    (error
     (org-ai-skills--signal-version-store-error
      (format "Failed to prepare version store dir: %s" (error-message-string err))))))

(defun org-ai-skills--candidate-id ()
  "Return a unique candidate id."
  (format "%s-%06x"
          (format-time-string "%Y%m%d%H%M%S%3N")
          (random #xFFFFFF)))

(defun org-ai-skills--subtree-begin-position (subtree)
  "Return integer begin position from SUBTREE."
  (let ((begin (plist-get subtree :begin)))
    (cond
     ((markerp begin) (marker-position begin))
     ((integerp begin) begin)
     (t nil))))

(defun org-ai-skills--ensure-subtree-slot-id (subtree)
  "Ensure SUBTREE has stable slot id; write back Org =:ID:= when possible."
  (let* ((buffer (current-buffer))
         (begin (org-ai-skills--subtree-begin-position subtree))
         (slot-id (plist-get subtree :slot-id)))
    (unless (stringp slot-id)
      (when (and begin (derived-mode-p 'org-mode))
        (save-excursion
          (goto-char begin)
          (unless (org-at-heading-p)
            (org-back-to-heading t))
          (setq slot-id (org-entry-get (point) "ID"))
          (unless (stringp slot-id)
            (setq slot-id (org-id-new))
            (org-entry-put (point) "ID" slot-id))))
      (unless (stringp slot-id)
        ;; Non-Org or marker-free callers keep compatibility with runtime-only id.
        (setq slot-id (format "runtime-%s" (org-ai-skills--candidate-id)))))
    (let* ((file-id (or (buffer-file-name buffer)
                        (format "buffer:%s" (buffer-name buffer))))
           (slot-key (format "%s|%s" file-id slot-id)))
      (append subtree
              (list :slot-id slot-id
                    :slot-file file-id
                    :slot-key slot-key)))))

(defun org-ai-skills--slot-store-file (slot-key)
  "Return store file path for SLOT-KEY."
  (expand-file-name
   (format "%s.jsonl" (secure-hash 'sha1 slot-key))
   (org-ai-skills--ensure-version-store-dir)))

(defun org-ai-skills--candidate-sort-key (candidate)
  "Return sorting key for CANDIDATE."
  (or (plist-get candidate :created-at) ""))

(defun org-ai-skills--write-slot-candidates (slot-key candidates)
  "Write CANDIDATES for SLOT-KEY."
  (let ((file (org-ai-skills--slot-store-file slot-key)))
    (condition-case err
        (let ((coding-system-for-write 'utf-8-unix))
          (with-temp-buffer
            (dolist (candidate candidates)
              (insert (json-serialize candidate))
              (insert "\n"))
            (write-region (point-min) (point-max) file nil 'silent)))
      (error
       (org-ai-skills--signal-version-store-error
        (format "Failed to write candidates: %s" (error-message-string err)))))))

(defun org-ai-skills--load-slot-candidates (slot-key)
  "Load candidate list for SLOT-KEY."
  (let ((file (org-ai-skills--slot-store-file slot-key))
        (items nil))
    (if (not (file-exists-p file))
        nil
      (condition-case err
          (let ((coding-system-for-read 'utf-8-unix))
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (while (not (eobp))
                (let ((line (string-trim (buffer-substring-no-properties
                                          (line-beginning-position)
                                          (line-end-position)))))
                  (unless (string-empty-p line)
                    (push (json-parse-string line
                                             :object-type 'plist
                                             :array-type 'list
                                             :null-object nil
                                             :false-object nil)
                          items)))
                (forward-line 1))))
        (error
         (org-ai-skills--signal-version-store-error
          (format "Failed to read candidates: %s" (error-message-string err)))))
      (sort items
            (lambda (a b)
              (string< (org-ai-skills--candidate-sort-key b)
                       (org-ai-skills--candidate-sort-key a)))))))

(defun org-ai-skills--persist-candidate (candidate)
  "Persist one CANDIDATE."
  (let* ((slot-key (plist-get candidate :slot-key))
         (items (org-ai-skills--load-slot-candidates slot-key)))
    (org-ai-skills--write-slot-candidates slot-key (cons candidate items))
    candidate))

(defun org-ai-skills--update-candidate-status (slot-key candidate-id status)
  "Update candidate status for SLOT-KEY and CANDIDATE-ID to STATUS."
  (let* ((items (org-ai-skills--load-slot-candidates slot-key))
         (updated
          (mapcar (lambda (item)
                    (if (equal (plist-get item :candidate-id) candidate-id)
                        (plist-put item :status status)
                      item))
                  items)))
    (org-ai-skills--write-slot-candidates slot-key updated)))

(defun org-ai-skills--candidate-display (candidate)
  "Return minibuffer display string for CANDIDATE."
  (let* ((status (or (plist-get candidate :status) "generated"))
         (created (or (plist-get candidate :created-at) ""))
         (task-id (or (plist-get candidate :task-id) ""))
         (text (or (plist-get candidate :output-text) ""))
         (preview (replace-regexp-in-string "[\n\r\t ]+" " " text)))
    (format "[%s] %s | %s | %s"
            status
            created
            task-id
            (truncate-string-to-width preview 80 nil nil t))))

(defun org-ai-skills--read-slot-candidate (slot-key &optional allow-skip)
  "Read one candidate for SLOT-KEY. When ALLOW-SKIP is non-nil, allow no apply."
  (let* ((items (org-ai-skills--load-slot-candidates slot-key))
         (pairs (mapcar (lambda (item)
                          (cons (org-ai-skills--candidate-display item) item))
                        items))
         (choice-list (append pairs
                              (when allow-skip
                                '(("Skip apply (candidate saved)" . nil)))))
         (_ (unless choice-list
              (org-ai-skills--signal-version-store-error
               "No candidates available for this slot")))
         (choice (completing-read "Candidate: "
                                  (mapcar #'car choice-list)
                                  nil t nil
                                  'org-ai-skills--candidate-selection-history)))
    (cdr (assoc choice choice-list))))

(defun org-ai-skills--record-generated-candidate (slot task-id source prompt rewritten-text)
  "Create and persist candidate for SLOT with TASK-ID, SOURCE, PROMPT, and REWRITTEN-TEXT."
  (org-ai-skills--persist-candidate
   (list :candidate-id (org-ai-skills--candidate-id)
         :created-at (format-time-string "%Y-%m-%dT%H:%M:%S%z")
         :slot-id (plist-get slot :slot-id)
         :slot-key (plist-get slot :slot-key)
         :slot-file (plist-get slot :slot-file)
         :slot-heading (plist-get slot :heading)
         :task-id task-id
         :source source
         :prompt-digest (secure-hash 'sha1 (or prompt ""))
         :model nil
         :provider nil
         :output-text rewritten-text
         :status "generated"
         :error nil)))

(defun org-ai-skills-org-apply-candidate-to-subtree (subtree candidate)
  "Apply CANDIDATE to SUBTREE and update persisted status."
  (org-ai-skills-org-apply-rewrite-result subtree (plist-get candidate :output-text))
  (org-ai-skills--update-candidate-status
   (plist-get candidate :slot-key)
   (plist-get candidate :candidate-id)
   "applied")
  (message "org-ai-skills candidate applied: %s"
           (plist-get candidate :candidate-id)))

(defun org-ai-skills-org-apply-slot-candidate (target)
  "Select one persisted candidate for TARGET slot and apply it."
  (interactive (list (org-ai-skills-org-read-rewrite-target)))
  (let* ((subtree (or target (org-ai-skills-org-resolve-subtree 'current)))
         (slot (org-ai-skills--ensure-subtree-slot-id subtree))
         (candidate (org-ai-skills--read-slot-candidate (plist-get slot :slot-key) nil)))
    (unless candidate
      (org-ai-skills--signal-version-store-error
       "No candidate available for selected slot"))
    (org-ai-skills-org-apply-candidate-to-subtree
     (list :begin (plist-get slot :begin)
           :end (plist-get slot :end))
     candidate)))

(defun org-ai-skills--parse-function-arg-names (arg-spec)
  "Parse ARG-SPEC string like \"(query date)\" into argument names."
  (let* ((raw (or arg-spec ""))
         (clean (replace-regexp-in-string "[()]" "" raw)))
    (split-string clean "[ \t\n,]+" t)))

(defun org-ai-skills--request-function-calls (request)
  "Collect function call specs from REQUEST contexts."
  (let ((calls nil)
        (skill-context (plist-get request :skill-context))
        (skill-contexts (plist-get request :skill-contexts)))
    (when skill-context
      (setq calls (append calls (or (plist-get skill-context :function-calls) nil))))
    (dolist (ctx skill-contexts)
      (setq calls (append calls (or (plist-get ctx :function-calls) nil))))
    (cl-remove-duplicates
     calls
     :test (lambda (a b)
             (equal (plist-get a :name) (plist-get b :name))))))

(defun org-ai-skills--function-call-to-gptel-tool (fn-spec)
  "Convert FN-SPEC into a gptel tool struct."
  (unless (fboundp 'gptel-make-tool)
    (org-ai-skills--signal-gptel-error
     "gptel-make-tool is unavailable in current gptel version"))
  (let* ((name (or (plist-get fn-spec :name) ""))
         (symbol (intern-soft name))
         (args (org-ai-skills--parse-function-arg-names (plist-get fn-spec :args)))
         (arg-description
          (lambda (arg-name)
            (let* ((key (intern (format ":%s" arg-name)))
                   (hint (plist-get fn-spec key)))
              (if (stringp hint)
                  hint
                (format "Argument %s for %s" arg-name name)))))
         (description
          (format "Skill function call: %s. When: %s"
                  name
                  (or (plist-get fn-spec :when) ""))))
    (unless (and symbol (fboundp symbol))
      (org-ai-skills--signal-function-call-error
       (format "Function call is not bound at dispatch time: %s" name)))
    (apply #'gptel-make-tool
           (list
            :name name
            :function symbol
            :description description
            :category "org-ai-skills"
            :confirm nil
            :include t
            :args (mapcar (lambda (arg-name)
                            (list :name arg-name
                                  :type 'string
                                  :description (funcall arg-description arg-name)
                                  :optional t))
                          args)))))

(defun org-ai-skills--request-gptel-tools (request)
  "Build gptel tool list from REQUEST."
  (mapcar #'org-ai-skills--function-call-to-gptel-tool
          (org-ai-skills--request-function-calls request)))

(defun org-ai-skills--resolve-request-role (request)
  "Return normalized request role symbol from REQUEST."
  (let ((role (or (plist-get request :request-role)
                  (if (eq (plist-get request :event-type) 'planner)
                      'planner
                    'execution))))
    (unless (memq role '(planner execution))
      (org-ai-skills--signal-gptel-error
       (format "Unsupported request role: %s" role)))
    role))

(defun org-ai-skills--resolve-role-model (role)
  "Return effective model override for ROLE, or nil for gptel default."
  (pcase role
    ('planner org-ai-skills-model-planner)
    ('execution org-ai-skills-model-execution)
    (_ (org-ai-skills--signal-gptel-error
        (format "Unsupported request role for model routing: %s" role)))))

(defun org-ai-skills--resolve-role-system-prompt (role)
  "Return effective system prompt string for ROLE."
  (let ((raw (pcase role
               ('planner org-ai-skills-system-prompt-planner)
               ('execution org-ai-skills-system-prompt-execution)
               (_ (org-ai-skills--signal-gptel-error
                   (format "Unsupported request role for system prompt routing: %s" role)))))
        (fallback (pcase role
                    ('planner org-ai-skills--default-system-prompt-planner)
                    ('execution org-ai-skills--default-system-prompt-execution))))
    (if (string-empty-p (or raw ""))
        fallback
      raw)))

(defun org-ai-skills--system-prompt-fingerprint (text)
  "Return short fingerprint string for system prompt TEXT."
  (substring (secure-hash 'sha1 (or text "")) 0 12))

(defun org-ai-skills--resolve-role-generation-settings (role)
  "Return generation settings plist for ROLE."
  (pcase role
    ('planner (list :temperature org-ai-skills-planner-temperature
                    :max-tokens org-ai-skills-planner-max-tokens))
    ('execution nil)
    (_ (org-ai-skills--signal-gptel-error
        (format "Unsupported request role for generation settings: %s" role)))))

(defun org-ai-skills--resolve-role-schema (role)
  "Return structured response schema for ROLE, or nil."
  (pcase role
    ('planner org-ai-skills--planner-response-schema)
    ('execution nil)
    (_ (org-ai-skills--signal-gptel-error
        (format "Unsupported request role for schema routing: %s" role)))))

(defun org-ai-skills-gptel-dispatch-rewrite (request callback)
  "Send rewrite REQUEST to gptel and run CALLBACK with response."
  (unless (or (featurep 'gptel) (org-ai-skills-require-gptel))
    (org-ai-skills--signal-gptel-error
     "gptel is unavailable; install or configure gptel first"))
  (unless (fboundp 'gptel-request)
    (org-ai-skills--signal-gptel-error
     "gptel-request is not available in current gptel version"))
  (let* ((role (org-ai-skills--resolve-request-role request))
         (effective-model (org-ai-skills--resolve-role-model role))
         (effective-system-prompt (org-ai-skills--resolve-role-system-prompt role))
         (effective-schema (org-ai-skills--resolve-role-schema role))
         (generation-settings (org-ai-skills--resolve-role-generation-settings role))
         (tools (org-ai-skills--request-gptel-tools request))
         (tool-names (mapcar (lambda (fn-spec) (plist-get fn-spec :name))
                             (org-ai-skills--request-function-calls request)))
         (logged-request (append request
                                 (list :request-role role
                                       :effective-model effective-model
                                       :effective-schema (if effective-schema t nil)
                                       :effective-system-prompt-fingerprint
                                       (org-ai-skills--system-prompt-fingerprint
                                        effective-system-prompt))
                                 (list :gptel-tool-names tool-names
                                       :gptel-use-tools (and tools t))))
         (logged-metadata nil)
         (wrapped-callback
          (lambda (&rest response)
            (let ((first (car response))
                  (info (cadr response)))
              (unless logged-metadata
                (when (and (listp info) (plist-member info :data))
                  (setq logged-metadata t)
                  (org-ai-skills--append-debug-entry
                   (list :event-type 'gptel-request-data
                         :request-role role
                         :effective-model effective-model
                         :effective-system-prompt-fingerprint
                         (org-ai-skills--system-prompt-fingerprint
                          effective-system-prompt)
                         :step-id (plist-get request :step-id)
                         :skill-ids (plist-get request :skill-ids)
                         :prompt "gptel request data payload"
                         :gptel-data (plist-get info :data)
                         :gptel-tool-names tool-names))))
              (when (and (consp first) (memq (car first) '(tool-call tool-result)))
                (org-ai-skills--append-debug-entry
                 (list :event-type (car first)
                       :request-role role
                       :effective-model effective-model
                       :effective-system-prompt-fingerprint
                       (org-ai-skills--system-prompt-fingerprint
                        effective-system-prompt)
                       :step-id (plist-get request :step-id)
                       :skill-ids (plist-get request :skill-ids)
                       :prompt (format "gptel callback event: %S" first))))
              (condition-case err
                  (apply callback response)
                (error
                 (org-ai-skills--append-debug-entry
                  (list :event-type 'callback-error
                        :request-role role
                        :effective-model effective-model
                        :effective-system-prompt-fingerprint
                        (org-ai-skills--system-prompt-fingerprint
                         effective-system-prompt)
                        :step-id (plist-get request :step-id)
                        :skill-ids (plist-get request :skill-ids)
                        :prompt (format "org-ai-skills callback error: %s"
                                        (error-message-string err))
                        :response-preview
                        (truncate-string-to-width (format "%S" first) 260 nil nil t)))
                 (signal (car err) (cdr err))))))))
    (org-ai-skills--append-debug-entry logged-request)
    (let ((gptel-tools tools)
          (gptel-use-tools (and tools t))
          (gptel-model (or effective-model gptel-model))
          (gptel-temperature (or (plist-get generation-settings :temperature)
                                 gptel-temperature))
          (gptel-max-tokens (or (plist-get generation-settings :max-tokens)
                                gptel-max-tokens)))
      (apply #'gptel-request
             (append
              (list (plist-get request :prompt)
                    :callback wrapped-callback
                    :system effective-system-prompt)
              (if effective-schema
                  (list :schema effective-schema)
                nil))))))

(defun org-ai-skills--interactive-rewrite-args ()
  "Read interactive arguments for `org-ai-skills-org-rewrite-subtree'."
  (let* ((target (org-ai-skills-org-read-rewrite-target))
         (skill (org-ai-skills-read-skill))
         (instruction (read-string "Rewrite instruction (optional): ")))
    (list target skill instruction)))

(defun org-ai-skills--interactive-plan-run-args ()
  "Read interactive arguments for `org-ai-skills-org-plan-and-run-subtree'."
  (let* ((target (org-ai-skills-org-read-rewrite-target))
         (task (read-string "Planner task: "
                            nil
                            'org-ai-skills--planner-task-history
                            org-ai-skills--last-planner-task)))
    (list target task)))

(defun org-ai-skills--interactive-plan-run-repeat-args ()
  "Read interactive arguments for planner rerun with last task."
  (let ((target (org-ai-skills-org-read-rewrite-target)))
    (list target)))

(defun org-ai-skills-read-planner-task-preset ()
  "Read one planner task preset and return (ID . TASK)."
  (unless org-ai-skills-planner-task-presets
    (signal 'org-ai-skills-planner-error
            (list "No planner task presets configured")))
  (let* ((ids (mapcar #'car org-ai-skills-planner-task-presets))
         (choice (completing-read "Planner preset: " ids nil t))
         (task (cdr (assoc choice org-ai-skills-planner-task-presets))))
    (unless (stringp task)
      (signal 'org-ai-skills-planner-error
              (list (format "Unknown planner preset: %s" choice))))
    (cons choice task)))

(defun org-ai-skills--interactive-plan-run-preset-args ()
  "Read interactive args for preset-based planner run."
  (let* ((target (org-ai-skills-org-read-rewrite-target))
         (preset (org-ai-skills-read-planner-task-preset)))
    (list target (car preset))))

(defun org-ai-skills-org-rewrite-subtree (target skill &optional instruction interactive-origin)
  "Rewrite Org TARGET subtree at point via gptel using SKILL.
When TARGET is nil, resolve current subtree."
  (interactive (org-ai-skills--interactive-rewrite-args))
  (let* ((interactive-run (or interactive-origin
                              (called-interactively-p 'interactive)))
         (subtree (or target (org-ai-skills-org-resolve-subtree 'current)))
         (slot (org-ai-skills--ensure-subtree-slot-id subtree))
         (request nil)
         (buffer (current-buffer))
         (dispatched nil)
         (run-id (org-ai-skills--candidate-id))
         ;; Markers keep target positions stable for async callback.
         (begin (copy-marker (plist-get slot :begin)))
         (end (copy-marker (plist-get slot :end))))
    (org-ai-skills--ui-start-run
     (list :run-id run-id
           :run-type 'rewrite
           :interactive-run interactive-run
           :status 'running
           :progress "generation"
           :target target
           :source-buffer buffer
           :begin begin
           :end end
           :heading (plist-get slot :heading)
           :slot-key (plist-get slot :slot-key)
           :slot-id (plist-get slot :slot-id)
           :skill skill
           :instruction instruction
           :task (or instruction "rewrite")
           :preset-id nil
           :selected-candidate nil
           :stop-requested nil
           :rerun-fn (lambda ()
                       (interactive)
                       (org-ai-skills-org-rewrite-subtree target skill instruction t))))
    (unwind-protect
        (progn
          (org-ai-skills-apply-skill-function-calls skill)
          (setq request (org-ai-skills-build-gptel-rewrite-request
                         skill slot instruction))
          (setq request (append request
                                (list :buffer-name (buffer-name buffer)
                                      :buffer-file (buffer-file-name buffer))))
          (org-ai-skills-gptel-dispatch-rewrite
           request
           (lambda (&rest response)
             (unwind-protect
                 (let ((raw (apply #'org-ai-skills--extract-gptel-response-text-if-ready response)))
                   (when raw
                     (if (org-ai-skills--ui-stop-requested-p run-id)
                         (org-ai-skills--ui-set-status 'canceled "canceled")
                     (let ((rewritten (org-ai-skills--sanitize-rewrite-output
                                       raw
                                       slot))
                           (candidate nil))
                       (setq candidate
                             (org-ai-skills--record-generated-candidate
                              slot
                              (or (plist-get request :goal) "rewrite")
                              "rewrite"
                              (plist-get request :prompt)
                              rewritten))
                       (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                         (org-ai-skills--ui-run-set :selected-candidate candidate))
                       (with-current-buffer buffer
                         (if (and interactive-run
                                  (markerp begin)
                                  (marker-buffer begin)
                                  (markerp end)
                                  (marker-buffer end))
                             (if org-ai-skills-auto-apply-generated-candidate
                                 (progn
                                   (org-ai-skills-org-apply-candidate-to-subtree
                                    (list :begin begin :end end)
                                    candidate)
                                   (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                                     (org-ai-skills--ui-clear-overlay)
                                     (org-ai-skills--ui-set-status 'applied "applied")))
                               (let ((selected (org-ai-skills--read-slot-candidate
                                                (plist-get slot :slot-key) t)))
                                 (when selected
                                   (org-ai-skills-org-apply-candidate-to-subtree
                                    (list :begin begin :end end)
                                    selected))
                                 (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                                   (org-ai-skills--ui-set-overlay 'ready)
                                   (org-ai-skills--ui-set-status 'ready "candidate-ready"))))
                           (message "org-ai-skills candidate saved for: %s"
                                    (plist-get slot :heading))
                           (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                             (org-ai-skills--ui-set-overlay 'ready)
                             (org-ai-skills--ui-set-status 'ready "candidate-ready")))))))
               (org-ai-skills-exclude-skill-function-calls skill)))))
          (setq dispatched t))
      (unless dispatched
        (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
          (org-ai-skills--ui-clear-overlay)
          (org-ai-skills--ui-set-status 'failed "dispatch-failed"))
        (org-ai-skills-exclude-skill-function-calls skill)))))

(defun org-ai-skills-org-plan-and-run-subtree (target task &optional interactive-origin preset-id)
  "Run planner-driven rewrite on TARGET subtree using TASK.
When INTERACTIVE-ORIGIN is non-nil, treat invocation as interactive for auto-apply flow."
  (interactive (org-ai-skills--interactive-plan-run-args))
  (when (string-empty-p (or task ""))
    (signal 'org-ai-skills-planner-error
            (list "Planner task cannot be empty")))
  (setq org-ai-skills--last-planner-task task)
  (let* ((interactive-run (or interactive-origin
                              (called-interactively-p 'interactive)))
         (subtree (or target (org-ai-skills-org-resolve-subtree 'current)))
         (slot (org-ai-skills--ensure-subtree-slot-id subtree))
         (buffer (current-buffer))
         (run-id (org-ai-skills--candidate-id))
         ;; Markers keep target positions stable for async callback.
         (begin (copy-marker (plist-get slot :begin)))
         (end (copy-marker (plist-get slot :end))))
    (org-ai-skills--ui-start-run
     (list :run-id run-id
           :run-type 'planner
           :interactive-run interactive-run
           :status 'running
           :progress "planning"
           :target target
           :source-buffer buffer
           :begin begin
           :end end
           :heading (plist-get slot :heading)
           :slot-key (plist-get slot :slot-key)
           :slot-id (plist-get slot :slot-id)
           :skill nil
           :instruction nil
           :task task
           :preset-id preset-id
           :selected-candidate nil
           :stop-requested nil
           :rerun-fn (lambda ()
                       (interactive)
                       (org-ai-skills-org-plan-and-run-subtree target task t preset-id))))
    (org-ai-skills-run-task-with-planner
     task
     slot
     nil
     (lambda (run-state)
       (if (org-ai-skills--ui-stop-requested-p run-id)
           (org-ai-skills--ui-set-status 'canceled "canceled")
         (let* ((raw (or (plist-get run-state :final-output) ""))
                (rewritten (org-ai-skills--sanitize-rewrite-output raw slot))
                (candidate (org-ai-skills--record-generated-candidate
                            slot
                            task
                            "planner"
                            task
                            rewritten)))
           (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
             (org-ai-skills--ui-run-set :selected-candidate candidate)
             (org-ai-skills--ui-set-status 'ready "candidate-ready"))
           (with-current-buffer buffer
             (if (and interactive-run
                      (markerp begin)
                      (marker-buffer begin)
                      (markerp end)
                      (marker-buffer end))
                 (if org-ai-skills-auto-apply-generated-candidate
                     (progn
                       (org-ai-skills-org-apply-candidate-to-subtree
                        (list :begin begin :end end)
                        candidate)
                       (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                         (org-ai-skills--ui-clear-overlay)
                         (org-ai-skills--ui-set-status 'applied "applied")))
                   (let ((selected (org-ai-skills--read-slot-candidate
                                    (plist-get slot :slot-key) t)))
                     (when selected
                       (org-ai-skills-org-apply-candidate-to-subtree
                        (list :begin begin :end end)
                        selected))
                     (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                       (org-ai-skills--ui-set-overlay 'ready)
                       (org-ai-skills--ui-set-status 'ready "candidate-ready"))))
               (message "org-ai-skills planner candidate saved for: %s (%s)"
                        (plist-get slot :heading)
                        (plist-get candidate :candidate-id))
               (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                 (org-ai-skills--ui-set-overlay 'ready)
                 (org-ai-skills--ui-set-status 'ready "candidate-ready"))))))))))

(defun org-ai-skills-org-plan-and-run-subtree-repeat-task (target)
  "Run planner-driven rewrite on TARGET using last planner task."
  (interactive (org-ai-skills--interactive-plan-run-repeat-args))
  (when (string-empty-p (or org-ai-skills--last-planner-task ""))
    (signal 'org-ai-skills-planner-error
            (list "No previous planner task; run org-ai-skills-org-plan-and-run-subtree first")))
  (org-ai-skills-org-plan-and-run-subtree target org-ai-skills--last-planner-task t nil))

(defun org-ai-skills-org-plan-and-run-subtree-preset (target preset-id)
  "Run planner-driven rewrite on TARGET using planner task PRESET-ID."
  (interactive (org-ai-skills--interactive-plan-run-preset-args))
  (let ((task (cdr (assoc preset-id org-ai-skills-planner-task-presets))))
    (unless (stringp task)
      (signal 'org-ai-skills-planner-error
              (list (format "Unknown planner preset: %s" preset-id))))
    (org-ai-skills-org-plan-and-run-subtree target task t preset-id)))

(defmacro org-ai-skills-define-plan-run-preset-command (command-name task &optional docstring)
  "Define COMMAND-NAME to run planner with fixed TASK.
Optional DOCSTRING overrides the generated command documentation."
  `(defun ,command-name (target)
     ,(or docstring (format "Run planner-driven rewrite with fixed task: %s" task))
     (interactive (list (org-ai-skills-org-read-rewrite-target)))
     (org-ai-skills-org-plan-and-run-subtree target ,task t nil)))

(defvar org-ai-skills-embark-org-heading-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "R") #'org-ai-skills-embark-rewrite-subtree-action)
    (define-key map (kbd "P") #'org-ai-skills-embark-plan-and-run-subtree-action)
    (define-key map (kbd "p") #'org-ai-skills-embark-plan-and-run-subtree-repeat-task-action)
    map)
  "Embark keymap for Org heading actions provided by org-ai-skills.")

(defun org-ai-skills-embark-rewrite-subtree-action (&optional _target)
  "Embark action adapter for `org-ai-skills-org-rewrite-subtree'."
  (interactive)
  (call-interactively #'org-ai-skills-org-rewrite-subtree))

(defun org-ai-skills-embark-plan-and-run-subtree-action (&optional _target)
  "Embark action adapter for `org-ai-skills-org-plan-and-run-subtree'."
  (interactive)
  (call-interactively #'org-ai-skills-org-plan-and-run-subtree))

(defun org-ai-skills-embark-plan-and-run-subtree-repeat-task-action (&optional _target)
  "Embark action adapter for `org-ai-skills-org-plan-and-run-subtree-repeat-task'."
  (interactive)
  (call-interactively #'org-ai-skills-org-plan-and-run-subtree-repeat-task))

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
