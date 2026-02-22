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

;; Forward declarations for dynamically bound gptel variables.
;; These are defined by gptel at runtime; declaring here avoids lexical
;; fallback behavior when tests stub `gptel-request' without loading gptel.
(defvar gptel-model nil)
(defvar gptel-temperature nil)
(defvar gptel-max-tokens nil)
(defvar gptel-tools nil)
(defvar gptel-use-tools nil)

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

(defcustom org-ai-skills-debug-property-retention nil
  "When non-nil, append subtree property-retention match diagnostics to debug buffer.
Requires `org-ai-skills-debug-enabled' to be non-nil."
  :type 'boolean
  :group 'org-ai-skills)

(defcustom org-ai-skills-debug-buffer-name "*org-ai-skills-debug*"
  "Buffer name used for org-ai-skills debug logs."
  :type 'string
  :group 'org-ai-skills)

(defcustom org-ai-skills-debug-filter-level nil
  "Optional log level filter for debug inspection commands.
When nil, include all levels."
  :type '(choice (const :tag "All levels" nil)
                 (const :tag "Debug" debug)
                 (const :tag "Info" info)
                 (const :tag "Warn" warn)
                 (const :tag "Error" error))
  :group 'org-ai-skills)

(defcustom org-ai-skills-debug-filter-step nil
  "Optional step/stage filter for debug inspection commands.
When nil, include all steps and stages."
  :type '(choice (const :tag "All steps/stages" nil)
                 (string :tag "Step or stage id"))
  :group 'org-ai-skills)

(defcustom org-ai-skills-org-code-block-max-retries 2
  "Maximum retries for autonomous Org code-block debug loops."
  :type 'integer
  :group 'org-ai-skills)

(defcustom org-ai-skills-org-code-block-executors
  '(("sh" . org-ai-skills--execute-shell-src-block)
    ("bash" . org-ai-skills--execute-shell-src-block)
    ("shell" . org-ai-skills--execute-shell-src-block)
    ("emacs-lisp" . org-ai-skills--execute-elisp-src-block)
    ("elisp" . org-ai-skills--execute-elisp-src-block))
  "Language to executor mapping for Org src block execution."
  :type '(alist :key-type string :value-type function)
  :group 'org-ai-skills)

(defcustom org-ai-skills-org-code-block-append-metadata t
  "When non-nil, append execution metadata comments below executed src blocks."
  :type 'boolean
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

(defcustom org-ai-skills-proposal-store-dir
  (expand-file-name "~/.emacs.d/skills/proposals/")
  "Directory for persisted proposal artifacts."
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

(defcustom org-ai-skills-enable-core-read-tools t
  "When non-nil, expose core buffer/file read tools on every gptel request."
  :type 'boolean
  :group 'org-ai-skills)

(defcustom org-ai-skills-core-read-max-chars 20000
  "Default max characters returned by core read tools."
  :type 'integer
  :group 'org-ai-skills)

(defcustom org-ai-skills-enable-core-provider-tools t
  "When non-nil, expose phase-1 core provider command tools on execution requests."
  :type 'boolean
  :group 'org-ai-skills)

(defun org-ai-skills--default-core-provider-allowed-paths ()
  "Return nil-safe default allowed root list for core provider commands."
  (let* ((anchor (or load-file-name
                     (buffer-file-name)
                     default-directory
                     temporary-file-directory))
         (base-dir (if (and (stringp anchor) (file-directory-p anchor))
                       anchor
                     (and (stringp anchor) (file-name-directory anchor))))
         (fallback (or base-dir default-directory temporary-file-directory "/tmp/")))
    (list (expand-file-name ".." fallback))))

(defcustom org-ai-skills-core-provider-allowed-commands
  '(file-read file-list file-search shell-exec python-exec org-babel-exec)
  "Allowed phase-1 core provider command types."
  :type '(repeat (choice (const file-read)
                         (const file-list)
                         (const file-search)
                         (const shell-exec)
                         (const python-exec)
                         (const org-babel-exec)))
  :group 'org-ai-skills)

(defcustom org-ai-skills-core-provider-allowed-paths
  (org-ai-skills--default-core-provider-allowed-paths)
  "Allowed directory roots for phase-1 core provider commands."
  :type '(repeat string)
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

(defcustom org-ai-skills-observability-now-function #'current-time
  "Function used to read current time for observability metrics."
  :type 'function
  :group 'org-ai-skills)

(defcustom org-ai-skills-observability-cost-per-1k-input-tokens nil
  "Optional estimated USD cost per 1k input tokens when provider omits cost."
  :type '(choice (const :tag "No local estimate" nil)
                 (number :tag "USD per 1k input tokens"))
  :group 'org-ai-skills)

(defcustom org-ai-skills-observability-cost-per-1k-output-tokens nil
  "Optional estimated USD cost per 1k output tokens when provider omits cost."
  :type '(choice (const :tag "No local estimate" nil)
                 (number :tag "USD per 1k output tokens"))
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
(define-error 'org-ai-skills-execution-error "Code block execution error")

(define-error 'org-ai-skills-version-store-error "Version store error")
(define-error 'org-ai-skills-proposal-store-error "Proposal store error")
(define-error 'org-ai-skills-safety-error "Runtime safety constraint violation")

(defvar org-ai-skills--last-debug-entry nil
  "Last debug entry captured for gptel dispatch.")

(defvar org-ai-skills--debug-events nil
  "Raw debug events, newest first.
Each entry is a plist with at least :timestamp, :event-type, :log-level,
:step-id, :stage-id, :request, and :entry.")

(defvar org-ai-skills--last-planner-task nil
  "Last task string used by planner run commands.")

(defvar org-ai-skills--planner-task-history nil
  "Minibuffer history for planner task prompts.")

(defvar org-ai-skills--active-skill-function-calls nil
  "Alist mapping active skill-id to function call specs.")

(defvar org-ai-skills--skill-defined-function-symbols nil
  "Alist mapping skill-id to function symbols defined from skill code blocks.")

(defvar org-ai-skills-core-provider-command-registry nil
  "Alist mapping phase-1 core provider command type symbols to handler functions.")

(defvar org-ai-skills--core-provider-context-directory nil
  "Current request-scoped default directory for phase-1 core provider commands.")

(defvar org-ai-skills--candidate-selection-history nil
  "Minibuffer history for candidate selection prompts.")

(defvar org-ai-skills--proposal-selection-history nil
  "Minibuffer history for proposal selection prompts.")

(defconst org-ai-skills-control-buffer-name "*org-ai-skills-control*"
  "Buffer name for runtime control panel.")

(defconst org-ai-skills-dag-buffer-name "*org-ai-skills-dag*"
  "Buffer name for execution DAG view.")

(defconst org-ai-skills-proposal-preview-buffer-name "*org-ai-skills-proposal*"
  "Buffer name for proposal preview.")

(defvar org-ai-skills--ui-window-configuration nil
  "Window configuration captured before opening control workspace.")

(defvar org-ai-skills--ui-run-state nil
  "Runtime UI state for current run and control workspace.")

(defvar org-ai-skills-control-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "s") #'org-ai-skills-ui-stop-run)
    (define-key map (kbd "g") #'org-ai-skills-ui-rerun)
    (define-key map (kbd "t") #'org-ai-skills-ui-adjust-task-or-instruction)
    (define-key map (kbd "v") #'org-ai-skills-ui-show-dag)
    (define-key map (kbd "c") #'org-ai-skills-ui-select-candidate)
    (define-key map (kbd "a") #'org-ai-skills-ui-apply-selected-candidate)
    (define-key map (kbd "d") #'org-ai-skills-ui-discard-selected-candidate)
    (define-key map (kbd "x") #'org-ai-skills-ui-extract-pattern-proposal)
    (define-key map (kbd "p") #'org-ai-skills-ui-select-proposal)
    (define-key map (kbd "y") #'org-ai-skills-ui-approve-selected-proposal)
    (define-key map (kbd "n") #'org-ai-skills-ui-reject-selected-proposal)
    (define-key map (kbd "m") #'org-ai-skills-ui-apply-selected-proposal)
    (define-key map (kbd "M") #'org-ai-skills-ui-apply-selected-proposal-to-skill-file)
    (define-key map (kbd "v") #'org-ai-skills-ui-preview-selected-proposal)
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

(defun org-ai-skills--container-values (container)
  "Return child values from CONTAINER for recursive scans."
  (cond
   ((hash-table-p container)
    (let ((vals nil))
      (maphash (lambda (_k v) (push v vals)) container)
      vals))
   ((and (listp container)
         (or (null container) (listp (cdr container)))
         (consp (car container))
         (not (keywordp (caar container))))
    (mapcar #'cdr container))
   ((and (listp container)
         (or (null container) (listp (cdr container)))
         (keywordp (car container)))
    (let ((vals nil)
          (tail (cdr container)))
      (while tail
        (push (car tail) vals)
        (setq tail (cddr tail)))
      (nreverse vals)))
   ((and (listp container)
         (or (null container) (listp (cdr container))))
    container)
   (t nil)))

(defun org-ai-skills--key-variants (key)
  "Return likely key variants for KEY across plist/alist/json forms."
  (let* ((name (cond
                ((keywordp key) (substring (symbol-name key) 1))
                ((symbolp key) (symbol-name key))
                (t (format "%s" key))))
         (dash (replace-regexp-in-string "_" "-" name))
         (under (replace-regexp-in-string "-" "_" name))
         (camel (let ((parts (split-string under "_" t)))
                  (if (null parts)
                      name
                    (concat (downcase (car parts))
                            (mapconcat (lambda (part)
                                         (if (string-empty-p part)
                                             ""
                                           (concat (upcase (substring part 0 1))
                                                   (downcase (substring part 1)))))
                                       (cdr parts)
                                       "")))))
         (variants nil))
    (dolist (raw (delete-dups (list name dash under camel)))
      (push raw variants)
      (push (intern raw) variants)
      (push (intern (concat ":" raw)) variants))
    (delete-dups (nreverse variants))))

(defun org-ai-skills--lookup-key (container key)
  "Lookup KEY in CONTAINER across plist/alist/hash-table key variants."
  (let ((miss (make-symbol "miss")))
    (catch 'found
      (dolist (variant (org-ai-skills--key-variants key))
        (let ((value
               (cond
                ((hash-table-p container)
                 (gethash variant container miss))
                ((and (listp container)
                      (consp (car container))
                      (not (keywordp (caar container))))
                 (let ((pair (assoc variant container)))
                   (if pair (cdr pair) miss)))
                ((and (listp container)
                      (or (keywordp variant) (symbolp variant)))
                 (let ((pv (plist-get container variant)))
                   (if (null pv) miss pv)))
                (t miss))))
          (unless (eq value miss)
            (throw 'found value))))
      nil)))

(defun org-ai-skills--plist-value (plist &rest keys)
  "Return first non-nil value in PLIST-like structure matching KEYS."
  (let ((value nil))
    (while (and keys (null value))
      (setq value (org-ai-skills--lookup-key plist (car keys)))
      (setq keys (cdr keys)))
    value))

(defun org-ai-skills--find-first-value-recursive (object keys &optional depth)
  "Return first value in OBJECT matching KEYS via bounded recursive scan."
  (let ((depth (or depth 4)))
    (when (>= depth 0)
      (or (apply #'org-ai-skills--plist-value object keys)
          (let ((found nil)
                (children (org-ai-skills--container-values object)))
            (while (and children (null found))
              (setq found
                    (org-ai-skills--find-first-value-recursive
                     (car children)
                     keys
                     (1- depth)))
              (setq children (cdr children)))
            found)))))

(defun org-ai-skills--usage-observed-p (usage)
  "Return non-nil when normalized USAGE includes any numeric signal."
  (or (numberp (plist-get usage :input-tokens))
      (numberp (plist-get usage :output-tokens))
      (numberp (plist-get usage :total-tokens))
      (numberp (plist-get usage :estimated-cost-usd))))

(defun org-ai-skills--usage-score (usage)
  "Return completeness score for normalized USAGE."
  (+ (if (numberp (plist-get usage :input-tokens)) 1 0)
     (if (numberp (plist-get usage :output-tokens)) 1 0)
     (if (numberp (plist-get usage :total-tokens)) 2 0)
     (if (numberp (plist-get usage :estimated-cost-usd)) 1 0)))

(defun org-ai-skills--select-provider-usage-source (first info current-source)
  "Return best provider-usage source from callback FIRST/INFO/CURRENT-SOURCE."
  (let* ((candidates (list (and (listp info) (plist-get info :data))
                           (and (listp info) (plist-get info :usage))
                           info
                           first
                           current-source))
         (best current-source)
         (best-usage (org-ai-skills--normalize-provider-usage current-source))
         (best-score (org-ai-skills--usage-score best-usage)))
    (dolist (candidate candidates)
      (let ((usage (org-ai-skills--normalize-provider-usage candidate)))
        (when (and candidate (org-ai-skills--usage-observed-p usage))
          (let ((score (org-ai-skills--usage-score usage)))
            (when (> score best-score)
              (setq best candidate
                    best-usage usage
                    best-score score))))))
    (if (org-ai-skills--usage-observed-p best-usage)
        best
      current-source)))

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

(defun org-ai-skills--planner-fallback-step-from-candidates (candidates)
  "Build one fallback planner step from CANDIDATES.
Returns nil when no candidate is available."
  (let ((first (car candidates)))
    (when (and (listp first) (plist-get first :skill-id))
      (list :step-id "fallback-step-1"
            :goal "Execute best matching skill from planner candidates"
            :skills (list (plist-get first :skill-id))
            :input-from '("task")
            :expected-output "Initial transformed output draft"
            :composition-reason
            "Auto-generated fallback because planner returned an empty plan"))))

(defun org-ai-skills--planner-fallback-skill-id-from-metadata (metadata)
  "Pick one fallback skill id from planner METADATA."
  (let* ((pick
          (or
           (seq-find
            (lambda (item)
              (and (string= (plist-get (plist-get item :tags) :invocation) "suggest")
                   (string= (plist-get (plist-get item :tags) :effect) "pure")))
            metadata)
           (seq-find
            (lambda (item)
              (string= (plist-get (plist-get item :tags) :invocation) "suggest"))
            metadata)
           (car metadata))))
    (plist-get pick :skill-id)))

(defun org-ai-skills--planner-fallback-response-from-metadata (metadata)
  "Build fallback planner response from METADATA."
  (let ((skill-id (org-ai-skills--planner-fallback-skill-id-from-metadata metadata)))
    (when (and (stringp skill-id) (not (string-empty-p skill-id)))
      (list :candidates (list (list :skill-id skill-id
                                    :why "Fallback from metadata due to empty planner plan/candidates"
                                    :score 0.0))
            :plan (list (list :step-id "fallback-step-1"
                              :goal "Execute metadata fallback skill"
                              :skills (list skill-id)
                              :input-from '("task")
                              :expected-output "Initial transformed output draft"
                              :composition-reason
                              "Auto-generated fallback from metadata because planner returned empty plan and candidates"))
            :replan-signal (list :enabled nil :condition "")))))

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
              nil))
         (normalized-candidates
          (mapcar (lambda (candidate)
                    (org-ai-skills--normalize-planner-candidate candidate known-skill-ids))
                  candidates-raw)))
    (unless (listp plan-raw)
      (signal 'org-ai-skills-planner-error
              (list "Planner response must include plan list")))
    (when (and (not allow-empty-plan)
               (null effective-plan-raw))
      (let ((fallback-step
             (org-ai-skills--planner-fallback-step-from-candidates
              normalized-candidates)))
        (when fallback-step
          (setq effective-plan-raw (list fallback-step)))))
    (when (and (not allow-empty-plan) (null effective-plan-raw))
      (signal 'org-ai-skills-planner-error
              (list "Planner response must include non-empty plan")))
    (when (> (length effective-plan-raw) org-ai-skills-planner-max-steps)
      (signal 'org-ai-skills-planner-error
              (list (format "Planner response exceeds max steps (%d > %d)"
                            (length effective-plan-raw)
                            org-ai-skills-planner-max-steps))))
    (let* ((normalized-steps
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
                         :purpose (plist-get subtree :purpose)
                         :source-file-path (plist-get subtree :source-file-path)
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

(defun org-ai-skills--signal-execution-error (message)
  "Signal Org code block execution error with MESSAGE."
  (signal 'org-ai-skills-execution-error (list message)))

(defun org-ai-skills--require-org-mode ()
  "Ensure current buffer is an Org buffer."
  (unless (derived-mode-p 'org-mode)
    (org-ai-skills--signal-org-context-error
     "Current buffer is not in org-mode")))

(defun org-ai-skills--normalize-src-language (language)
  "Return normalized Org src LANGUAGE string."
  (downcase (string-trim (or language ""))))

(defun org-ai-skills--src-block-plist (element)
  "Convert Org ELEMENT src-block to normalized plist."
  (unless (eq (org-element-type element) 'src-block)
    (org-ai-skills--signal-execution-error "Element is not a src block"))
  (list :language (org-ai-skills--normalize-src-language
                   (org-element-property :language element))
        :parameters (or (org-element-property :parameters element) "")
        :begin (org-element-property :begin element)
        :end (org-element-property :end element)
        :contents-begin (org-element-property :contents-begin element)
        :contents-end (org-element-property :contents-end element)
        :body (or (org-element-property :value element) "")))

(defun org-ai-skills-org-src-block-at-point (&optional position)
  "Return src block plist at POSITION or current point."
  (org-ai-skills--require-org-mode)
  (save-excursion
    (when position
      (goto-char position))
    (let* ((context (org-element-context))
           (block (if (eq (org-element-type context) 'src-block)
                      context
                    (org-element-lineage context '(src-block) t))))
      (unless (eq (org-element-type block) 'src-block)
        (org-ai-skills--signal-execution-error "Point is not inside an Org src block"))
      (org-ai-skills--src-block-plist block))))

(defun org-ai-skills-org-collect-src-blocks ()
  "Collect all executable src blocks from current Org buffer."
  (org-ai-skills--require-org-mode)
  (org-element-map (org-element-parse-buffer) 'src-block
    (lambda (element)
      (org-ai-skills--src-block-plist element))))

(defun org-ai-skills--resolve-src-block-executor (language)
  "Resolve executor function for src LANGUAGE."
  (let* ((lang (org-ai-skills--normalize-src-language language))
         (entry (assoc-string lang org-ai-skills-org-code-block-executors t))
         (executor (cdr entry)))
    (unless (functionp executor)
      (org-ai-skills--signal-execution-error
       (format "Unsupported or unavailable src block language: %s" lang)))
    executor))

(defun org-ai-skills--coerce-retry-count (value)
  "Coerce retry VALUE into bounded integer."
  (let ((n (cond
            ((integerp value) value)
            ((and (stringp value) (string-match-p "^[0-9]+$" value))
             (string-to-number value))
            (t org-ai-skills-org-code-block-max-retries))))
    (max 0 n)))

(defun org-ai-skills--execute-shell-src-block (block)
  "Execute shell src BLOCK and return structured result plist."
  (let* ((script (or (plist-get block :body) ""))
         (script-file (make-temp-file "org-ai-skills-shell-script-"))
         (stderr-file (make-temp-file "org-ai-skills-shell-err-"))
         (stdout-buf (generate-new-buffer " *org-ai-skills-shell-out*"))
         (started-at (float-time))
         (exit-value nil)
         (stderr "")
         (stdout ""))
    (unwind-protect
        (progn
          (with-temp-file script-file
            (insert script))
          (setq exit-value
                (process-file shell-file-name
                              script-file
                              (list stdout-buf stderr-file)
                              nil
                              "--noprofile"
                              "--norc"))
          (setq stdout (with-current-buffer stdout-buf (buffer-string)))
          (setq stderr (with-temp-buffer
                         (insert-file-contents stderr-file)
                         (buffer-string))))
      (when (buffer-live-p stdout-buf)
        (kill-buffer stdout-buf))
      (when (file-exists-p script-file)
        (delete-file script-file))
      (when (file-exists-p stderr-file)
        (delete-file stderr-file)))
    (when (stringp exit-value)
      (setq stderr (concat stderr
                           (if (string-empty-p stderr) "" "\n")
                           (format "Process terminated by signal: %s" exit-value)))
      (setq exit-value 1))
    (list :exit-code (or exit-value 1)
          :stdout stdout
          :stderr stderr
          :duration-ms (truncate (* 1000 (- (float-time) started-at))))))

(defun org-ai-skills--execute-elisp-src-block (block)
  "Execute emacs-lisp src BLOCK and return structured result plist."
  (let* ((body (or (plist-get block :body) ""))
         (started-at (float-time))
         (stdout "")
         (stderr "")
         (exit-code 0))
    (condition-case err
        (let ((value nil))
          (setq stdout
                (with-output-to-string
                  (setq value
                        (eval (read (concat "(progn\n" body "\n)")) t))))
          (when (string-empty-p stdout)
            (setq stdout (if (null value) "" (format "%S" value)))))
      (error
       (setq exit-code 1)
       (setq stderr (error-message-string err))))
    (list :exit-code exit-code
          :stdout stdout
          :stderr stderr
          :duration-ms (truncate (* 1000 (- (float-time) started-at))))))

(defun org-ai-skills--default-execution-evaluator (result _prompt)
  "Default execution evaluator for RESULT.
_PROMPT is ignored in the default evaluator."
  (if (= (or (plist-get result :exit-code) 1) 0)
      (list :ok t :reason "")
    (list :ok nil :reason (or (plist-get result :stderr) "non-zero exit"))))

(defun org-ai-skills--evaluate-execution-result (result prompt evaluator)
  "Evaluate execution RESULT for PROMPT using EVALUATOR."
  (let* ((fn (or evaluator #'org-ai-skills--default-execution-evaluator))
         (evaluation (funcall fn result prompt))
         (ok (if (plist-get evaluation :ok) t nil))
         (reason (or (plist-get evaluation :reason) "")))
    (list :ok ok :reason reason :evaluation evaluation)))

(defun org-ai-skills--execution-metadata-text (result)
  "Render RESULT metadata into an Org comment block."
  (let ((timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
    (concat
     "#+BEGIN_COMMENT\n"
     "org-ai-skills execution metadata\n"
     (format "timestamp: %s\n" timestamp)
     (format "language: %s\n" (or (plist-get result :language) ""))
     (format "status: %s\n" (or (plist-get result :status) 'failed))
     (format "attempt: %s\n" (or (plist-get result :attempt) 1))
     (format "exit_code: %s\n" (or (plist-get result :exit-code) 1))
     (format "duration_ms: %s\n" (or (plist-get result :duration-ms) 0))
     (format "meets_prompt: %s\n" (if (plist-get result :meets-prompt) "t" "nil"))
     (format "evaluation_reason: %s\n" (or (plist-get result :evaluation-reason) ""))
     "stdout:\n"
     (or (plist-get result :stdout) "")
     "\n"
     "stderr:\n"
     (or (plist-get result :stderr) "")
     "\n#+END_COMMENT\n")))

(defun org-ai-skills-org-append-src-block-execution-metadata (result)
  "Append execution RESULT metadata below the related src block."
  (org-ai-skills--require-org-mode)
  (let ((block-end (or (plist-get result :block-end)
                       (plist-get result :end))))
    (unless (integer-or-marker-p block-end)
      (org-ai-skills--signal-execution-error "Result missing block-end position"))
    (save-excursion
      (goto-char block-end)
      (insert "\n" (org-ai-skills--execution-metadata-text result)))))

(defun org-ai-skills-org-set-src-block-body (block new-body)
  "Replace src BLOCK body with NEW-BODY text and return refreshed block plist."
  (org-ai-skills--require-org-mode)
  (let* ((refreshed (org-ai-skills-org-src-block-at-point (plist-get block :begin)))
         (block-begin (plist-get refreshed :begin))
         (block-end (plist-get refreshed :end))
         (contents-begin nil)
         (contents-end nil))
    (save-excursion
      (goto-char block-begin)
      (unless (re-search-forward "^[ \t]*#\\+begin_src\\b.*$" block-end t)
        (org-ai-skills--signal-execution-error
         "Cannot locate #+begin_src line for body update"))
      (forward-line 1)
      (setq contents-begin (point))
      (unless (re-search-forward "^[ \t]*#\\+end_src\\b" block-end t)
        (org-ai-skills--signal-execution-error
         "Cannot locate #+end_src line for body update"))
      (beginning-of-line)
      (setq contents-end (point)))
    (save-excursion
      (goto-char contents-begin)
      (delete-region contents-begin contents-end)
      (insert (if (string-suffix-p "\n" new-body)
                  new-body
                (concat new-body "\n"))))
    (org-ai-skills-org-src-block-at-point contents-begin)))

(defun org-ai-skills-org-execute-src-block
    (&optional block prompt evaluator attempt append-metadata)
  "Execute one Org src BLOCK and return structured result.
When BLOCK is nil, resolve the src block at point."
  (let* ((src (or block (org-ai-skills-org-src-block-at-point)))
         (language (plist-get src :language))
         (executor (org-ai-skills--resolve-src-block-executor language))
         (raw (funcall executor src))
         (judgement (org-ai-skills--evaluate-execution-result raw prompt evaluator))
         (result (append
                  src
                  raw
                  (list :attempt (or attempt 1)
                        :language language
                        :prompt (or prompt "")
                        :status (if (plist-get judgement :ok) 'success 'failed)
                        :meets-prompt (plist-get judgement :ok)
                        :evaluation-reason (plist-get judgement :reason)
                        :evaluation (plist-get judgement :evaluation)))))
    (when append-metadata
      (org-ai-skills-org-append-src-block-execution-metadata result))
    result))

(defun org-ai-skills-org-run-src-block-auto-debug
    (prompt repair-fn &optional block evaluator options)
  "Run bounded execute/evaluate/repair loop for Org src BLOCK.
PROMPT is user intent text. REPAIR-FN receives context plist and returns new body.
When BLOCK is nil, resolve src block at point.
EVALUATOR receives (RESULT PROMPT) and returns plist with :ok and :reason.
OPTIONS plist supports keys:
- :max-retries integer (default `org-ai-skills-org-code-block-max-retries')
- :apply-fixes boolean (default t)
- :append-metadata boolean (default `org-ai-skills-org-code-block-append-metadata')."
  (unless (functionp repair-fn)
    (org-ai-skills--signal-execution-error "repair-fn must be callable"))
  (let* ((src (or block (org-ai-skills-org-src-block-at-point)))
         (max-retries (org-ai-skills--coerce-retry-count
                       (plist-get options :max-retries)))
         (append-metadata
          (if (plist-member options :append-metadata)
              (if (plist-get options :append-metadata) t nil)
            org-ai-skills-org-code-block-append-metadata))
         (apply-fixes
          (if (plist-member options :apply-fixes)
              (if (plist-get options :apply-fixes) t nil)
            t))
         (attempt 1)
         (history nil)
         (current src)
         (done nil)
         (final nil))
    (while (and (not done) (<= attempt (1+ max-retries)))
      (let* ((result (org-ai-skills-org-execute-src-block
                      current
                      prompt
                      evaluator
                      attempt
                      append-metadata))
             (entry (list :attempt attempt
                          :body (plist-get current :body)
                          :result result)))
        (push entry history)
        (if (plist-get result :meets-prompt)
            (setq done t
                  final (list :status 'success
                              :attempt-count attempt
                              :final-result result
                              :history (reverse history)))
          (if (>= attempt (1+ max-retries))
              (setq done t
                    final (list :status 'failed
                                :attempt-count attempt
                                :final-result result
                                :history (reverse history)))
            (let* ((context (list :prompt (or prompt "")
                                  :attempt attempt
                                  :max-retries max-retries
                                  :language (plist-get current :language)
                                  :body (plist-get current :body)
                                  :result result
                                  :history (reverse history)))
                   (next-body (funcall repair-fn context)))
              (unless (and (stringp next-body)
                           (not (string-empty-p next-body)))
                (org-ai-skills--signal-execution-error
                 "repair-fn must return non-empty src block body text"))
              (if apply-fixes
                  (setq current (org-ai-skills-org-set-src-block-body current next-body))
                (setq current (plist-put (copy-sequence current) :body next-body)))
              (setq attempt (1+ attempt)))))))
    final))

(defun org-ai-skills-org-execute-src-block-at-point (&optional prompt)
  "Interactive helper to execute Org src block at point."
  (interactive
   (list (read-string "Prompt expectation (optional): ")))
  (let ((result (org-ai-skills-org-execute-src-block
                 nil
                 prompt
                 nil
                 1
                 org-ai-skills-org-code-block-append-metadata)))
    (message "org-ai-skills block %s (exit=%s)"
             (plist-get result :status)
             (plist-get result :exit-code))
    result))

(defun org-ai-skills--subtree-at-heading-point ()
  "Return subtree plist at heading point.
Caller must ensure point is at a valid Org heading."
  (let ((begin (point))
        (level (org-outline-level))
        (heading (org-get-heading t t t t))
        (path (mapconcat #'identity (org-ai-skills--heading-path-at-point) "/"))
        (purpose (or (org-entry-get (point) "PURPOSE" t)
                     (org-ai-skills--file-keyword-value "PURPOSE")
                     ""))
        (source-file-path (or (org-entry-get (point) "SOURCE_FILE_PATH" t)
                              (org-ai-skills--file-keyword-value "SOURCE_FILE_PATH"))))
    (save-excursion
      (org-end-of-subtree t t)
      (list :begin begin
            :end (point)
            :level level
            :heading heading
            :path path
            :purpose purpose
            :source-file-path source-file-path
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

(defun org-ai-skills--file-keyword-value (keyword)
  "Return first file-level KEYWORD value in current Org buffer, or nil."
  (let* ((key (upcase keyword))
         (items (car (org-collect-keywords (list key))))
         (values (cdr items))
         (first (car values)))
    (when (stringp first)
      (string-trim first))))

(defun org-ai-skills--trim-path-punctuation (text)
  "Trim common trailing punctuation from TEXT path token."
  (replace-regexp-in-string "[),.;:!?，。；：！？）]+\\'" "" (or text "")))

(defun org-ai-skills--normalize-existing-directory (path)
  "Return normalized directory hint for PATH.
Prefer existing paths; when unavailable, return expanded absolute/tilde hint."
  (when (and (stringp path) (not (string-empty-p path)))
    (let* ((trimmed (org-ai-skills--trim-path-punctuation path))
           (abs (expand-file-name trimmed)))
      (cond
       ((file-directory-p abs) abs)
       ((file-exists-p abs) (file-name-directory abs))
       ((string-match-p "\\`\\(?:~\\|/\\)" trimmed) abs)
       (t nil)))))

(defun org-ai-skills--extract-directory-from-purpose (purpose)
  "Extract first existing directory path candidate from PURPOSE text."
  (when (and (stringp purpose) (not (string-empty-p purpose)))
    (let ((start 0)
          (found nil))
      (while (and (not found)
                  (string-match "\\(?:~\\|/\\)[A-Za-z0-9._~/-]*[A-Za-z0-9_~/-]" purpose start))
        (setq found (org-ai-skills--normalize-existing-directory
                     (match-string 0 purpose)))
        (setq start (match-end 0)))
      found)))

(defun org-ai-skills--resolve-working-directory (subtree)
  "Resolve preferred working directory from SUBTREE context.
Priority: purpose path hint, explicit source path, then nil."
  (let* ((purpose (plist-get subtree :purpose))
         (source-file-path (plist-get subtree :source-file-path))
         (from-purpose (org-ai-skills--extract-directory-from-purpose purpose))
         (from-source (org-ai-skills--normalize-existing-directory source-file-path)))
    (or from-purpose from-source nil)))

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
         (skill-id (plist-get skill :skill-id))
         (default-constraints (org-ai-skills--skill-default-rewrite-constraints skill-id))
         (working-directory (org-ai-skills--resolve-working-directory subtree))
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
                  "\nPurpose: "
                  (or (plist-get subtree :purpose) "")
                  "\nSource file path: "
                  (or (plist-get subtree :source-file-path) "")
                  "\nWorking directory hint: "
                  (or working-directory "")
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
                  "- Keep Org syntax valid.\n"
                  (if (plist-get default-constraints :preserve-headlines)
                      "- Keep every headline line unchanged at all levels.\n"
                    "")
                  (if (plist-get default-constraints :omit-property-drawers)
                      "- Do not output any property drawer block.\n"
                    "")
                  "\n"
                  (if (and (stringp skill-id)
                           (string= skill-id org-ai-skills--compose-skill-id))
                      "For composition, derive a concise summary internally first, then expand section-by-section.\n\n"
                    "")
                  "Rewrite the following Org subtree:\n\n"
                  (org-ai-skills--rewrite-context-text skill subtree))))
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
          :source-file-path (plist-get subtree :source-file-path)
          :working-directory working-directory
          :source-text (plist-get subtree :text)
          :rewrite-constraints default-constraints
          :skill-context skill-context
          :prompt rewrite-prompt)))

(defun org-ai-skills--run-state-latest-output (run-state)
  "Return latest step output from RUN-STATE."
  (or (plist-get run-state :latest-output)
      (let ((steps (plist-get run-state :steps)))
        (when steps
          (plist-get (car (last steps)) :output)))))

(defun org-ai-skills--observability-now-ms ()
  "Return current timestamp in milliseconds for observability events."
  (let ((now (funcall org-ai-skills-observability-now-function)))
    (truncate
     (* 1000.0
        (cond
         ((numberp now) now)
         ((listp now) (float-time now))
         (t (float-time (current-time))))))))

(defun org-ai-skills--run-state-append-timing-event (run-state stage-id start-ms end-ms
                                                               &optional extra-fields)
  "Append timing event to RUN-STATE for STAGE-ID from START-MS to END-MS.
EXTRA-FIELDS is a plist merged into the event."
  (let* ((events (or (plist-get run-state :events) nil))
         (event (append (list :stage-id stage-id
                              :start-ms start-ms
                              :end-ms end-ms
                              :duration-ms (max 0 (- end-ms start-ms)))
                        extra-fields)))
    (plist-put (copy-sequence run-state) :events (append events (list event)))))

(defun org-ai-skills--run-state-record-plan (run-state plan &optional revision source)
  "Record PLAN snapshot into RUN-STATE with REVISION and SOURCE."
  (let* ((rev (or revision (or (plist-get run-state :plan-revision) 1)))
         (entry (list :plan-revision rev
                      :source (or source 'planner)
                      :plan plan))
         (history (or (plist-get run-state :plan-revisions) nil))
         (last-entry (car (last history)))
         (same-as-last
          (and last-entry
               (= (or (plist-get last-entry :plan-revision) 0) rev)
               (equal (plist-get last-entry :source) (plist-get entry :source))
               (equal (plist-get last-entry :plan) plan))))
    (plist-put
     (plist-put (plist-put run-state :active-plan plan)
                :latest-plan plan)
     :plan-revisions
     (if same-as-last
         history
       (append history (list entry))))))

(defun org-ai-skills-build-execution-dag (run-state &optional plan include-events)
  "Build execution DAG model from RUN-STATE and optional PLAN.
When INCLUDE-EVENTS is non-nil, render one node per timing event occurrence."
  (let* ((plan (or plan
                   (plist-get run-state :active-plan)
                   (plist-get run-state :latest-plan)
                   nil))
         (steps (or (plist-get run-state :steps) nil))
         (events (or (plist-get run-state :events) nil))
         (step-table (make-hash-table :test #'equal))
         (metric-table (make-hash-table :test #'equal))
         (plan-step-ids (mapcar (lambda (step)
                                  (format "%s" (or (plist-get step :step-id) "")))
                                plan))
         (nodes nil)
         (edges nil))
    (dolist (step steps)
      (puthash (format "%s" (or (plist-get step :step-id) "")) step step-table))
    (dolist (event events)
      (when (and (eq (plist-get event :stage-id) 'execution.step)
                 (plist-get event :step-id))
        (let* ((step-id (format "%s" (plist-get event :step-id)))
               (prev (or (gethash step-id metric-table)
                         (list :duration-ms 0
                               :input-tokens 0
                               :output-tokens 0
                               :total-tokens 0
                               :estimated-cost-usd 0.0)))
               (usage (or (plist-get event :usage) nil)))
          (puthash
           step-id
           (list :duration-ms (+ (or (plist-get prev :duration-ms) 0)
                                 (or (plist-get event :duration-ms) 0))
                 :input-tokens (+ (or (plist-get prev :input-tokens) 0)
                                  (or (plist-get usage :input-tokens) 0))
                 :output-tokens (+ (or (plist-get prev :output-tokens) 0)
                                   (or (plist-get usage :output-tokens) 0))
                 :total-tokens (+ (or (plist-get prev :total-tokens) 0)
                                  (or (plist-get usage :total-tokens) 0))
                 :estimated-cost-usd (+ (or (plist-get prev :estimated-cost-usd) 0.0)
                                        (or (plist-get event :estimated-cost-usd) 0.0)))
           metric-table))))
    (if include-events
        (let ((occurrence-table (make-hash-table :test #'equal))
              (prev-node-id nil))
          (dolist (event events)
            (let* ((stage-id (or (plist-get event :stage-id) 'unknown))
                   (stage-name (format "%s" stage-id))
                   (count (1+ (or (gethash stage-name occurrence-table) 0)))
                   (raw-step-id (plist-get event :step-id))
                   (step-id (and raw-step-id (format "%s" raw-step-id)))
                   (event-node-id
                    (format "%s%s#%d"
                            stage-name
                            (if step-id (format ":%s" step-id) "")
                            count))
                   (usage (or (plist-get event :usage) nil))
                   (resolved-step (and step-id (gethash step-id step-table)))
                   (status (cond
                            ((eq (plist-get event :status) 'error) 'failure)
                            ((eq (plist-get event :status) 'failed) 'failure)
                            ((eq (plist-get event :status) 'running) 'running)
                            (t 'success)))
                   (skills (or (plist-get event :skill-ids)
                               (plist-get resolved-step :skills)
                               nil))
                   (goal (or (plist-get resolved-step :goal) ""))
                   (metrics (list :duration-ms (or (plist-get event :duration-ms) 0)
                                  :input-tokens (or (plist-get usage :input-tokens) 0)
                                  :output-tokens (or (plist-get usage :output-tokens) 0)
                                  :total-tokens (or (plist-get usage :total-tokens) 0)
                                  :estimated-cost-usd
                                  (or (plist-get event :estimated-cost-usd) 0.0))))
              (puthash stage-name count occurrence-table)
              (push (list :id event-node-id
                          :goal goal
                          :skills skills
                          :status status
                          :dependencies (if prev-node-id (list prev-node-id) nil)
                          :metrics metrics)
                    nodes)
              (when prev-node-id
                (push (list :from prev-node-id :to event-node-id) edges))
              (setq prev-node-id event-node-id))))
      (let ((seen-step-ids nil))
        (dolist (step plan)
          (let* ((step-id (format "%s" (or (plist-get step :step-id) "")))
                 (done (gethash step-id step-table))
                 (status (cond
                          ((null done) 'pending)
                          ((memq (plist-get done :status) '(done success)) 'success)
                          ((eq (plist-get done :status) 'failed) 'failure)
                          (t 'running)))
                 (deps (seq-filter
                        (lambda (dep)
                          (member dep plan-step-ids))
                        (mapcar #'format
                                (or (plist-get step :input-from) nil))))
                 (metrics (or (gethash step-id metric-table)
                              (list :duration-ms 0
                                    :input-tokens 0
                                    :output-tokens 0
                                    :total-tokens 0
                                    :estimated-cost-usd 0.0))))
            (unless (member step-id seen-step-ids)
              (push step-id seen-step-ids)
              (push (list :id step-id
                          :goal (or (plist-get step :goal) "")
                          :skills (or (plist-get step :skills) nil)
                          :status status
                          :dependencies deps
                          :metrics metrics)
                    nodes)
              (dolist (dep deps)
                (push (list :from dep :to step-id) edges)))))
        (dolist (step steps)
          (let ((step-id (format "%s" (or (plist-get step :step-id) ""))))
            (unless (member step-id plan-step-ids)
              (push (list :id step-id
                          :goal (or (plist-get step :goal) "")
                          :skills (or (plist-get step :skills) nil)
                          :status (if (memq (plist-get step :status) '(done success))
                                      'success
                                    'failure)
                          :dependencies nil
                          :metrics (or (gethash step-id metric-table)
                                       (list :duration-ms 0
                                             :input-tokens 0
                                             :output-tokens 0
                                             :total-tokens 0
                                             :estimated-cost-usd 0.0)))
                    nodes))))))
    (list :nodes (nreverse nodes)
          :edges (nreverse edges))))

(defun org-ai-skills-render-execution-dag-text (dag)
  "Render DAG model as compact human-readable text."
  (let ((nodes (or (plist-get dag :nodes) nil))
        (edges (or (plist-get dag :edges) nil)))
    (concat
     (format "Execution DAG\nNodes: %d  Edges: %d\n\n"
             (length nodes) (length edges))
     (if (null nodes)
         "No DAG nodes available.\n"
       (mapconcat
        (lambda (node)
          (let* ((id (plist-get node :id))
                 (status (plist-get node :status))
                 (deps (or (plist-get node :dependencies) nil))
                 (skills (or (plist-get node :skills) nil))
                 (metrics (or (plist-get node :metrics) nil)))
            (format "- [%s] %s\n  deps: %s\n  skills: %s\n  metrics: %dms, in:%d out:%d total:%d cost:$%.6f\n"
                    status
                    id
                    (if deps (string-join deps ", ") "-")
                    (if skills (string-join skills ", ") "-")
                    (or (plist-get metrics :duration-ms) 0)
                    (or (plist-get metrics :input-tokens) 0)
                    (or (plist-get metrics :output-tokens) 0)
                    (or (plist-get metrics :total-tokens) 0)
                    (or (plist-get metrics :estimated-cost-usd) 0.0))))
        nodes
        "\n")))))

(defun org-ai-skills-ui-show-dag (&optional run-state)
  "Show execution DAG for RUN-STATE or current UI planner run."
  (interactive)
  (let* ((state (or run-state
                    (org-ai-skills--ui-run-get :planner-run-state)
                    org-ai-skills--ui-run-state))
         (plan (or (plist-get state :active-plan)
                   (plist-get state :latest-plan)
                   nil))
         (dag (org-ai-skills-build-execution-dag state plan (and (plist-get state :events) t)))
         (buffer (get-buffer-create org-ai-skills-dag-buffer-name)))
    (if (and (null (plist-get dag :nodes))
             (null (plist-get dag :edges)))
        (message "No execution DAG available for current run")
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "Run id: %s\nPlan revision: %s\n\n"
                          (or (plist-get state :run-id) "")
                          (or (plist-get state :plan-revision) "")))
          (insert (org-ai-skills-render-execution-dag-text dag))
          (goto-char (point-min))
          (special-mode))
        (pop-to-buffer buffer)))))

(defun org-ai-skills--normalize-provider-usage (provider-data)
  "Normalize PROVIDER-DATA into usage plist with token/cost fields.
Returns plist with keys:
- :input-tokens
- :output-tokens
- :total-tokens
- :estimated-cost-usd"
  (let* ((provider-data
          (cond
           ((stringp provider-data)
            (condition-case nil
                (json-parse-string provider-data :object-type 'plist :array-type 'list)
              (error provider-data)))
           (t provider-data)))
         (usage (or (org-ai-skills--find-first-value-recursive
                     provider-data
                     '(:usage :usage-metadata :usage_metadata :token-usage :token_usage)
                     4)
                    provider-data))
         (input (or (org-ai-skills--find-first-value-recursive
                     usage
                     '(:input-tokens :prompt-tokens :input_tokens :prompt_tokens
                       :prompt-eval-count :prompt_eval_count
                       :input-token-count :input_token_count
                       :prompt-token-count :prompt_token_count)
                     3)
                    (org-ai-skills--find-first-value-recursive
                     provider-data
                     '(:input-tokens :prompt-tokens :input_tokens :prompt_tokens
                       :prompt-eval-count :prompt_eval_count
                       :input-token-count :input_token_count
                       :prompt-token-count :prompt_token_count)
                     4)))
         (output (or (org-ai-skills--find-first-value-recursive
                      usage
                      '(:output-tokens :completion-tokens :output_tokens :completion_tokens
                        :eval-count :eval_count
                        :output-token-count :output_token_count
                        :completion-token-count :completion_token_count)
                      3)
                     (org-ai-skills--find-first-value-recursive
                      provider-data
                      '(:output-tokens :completion-tokens :output_tokens :completion_tokens
                        :eval-count :eval_count
                        :output-token-count :output_token_count
                        :completion-token-count :completion_token_count)
                      4)))
         (total (or (org-ai-skills--find-first-value-recursive
                     usage
                     '(:total-tokens :total_tokens :tokens
                       :total-token-count :total_token_count)
                     3)
                    (org-ai-skills--find-first-value-recursive
                     provider-data
                     '(:total-tokens :total_tokens :tokens
                       :total-token-count :total_token_count)
                     4)))
         (cost (or (org-ai-skills--find-first-value-recursive
                    usage
                    '(:estimated-cost-usd :cost-usd :total-cost
                      :estimated_cost :total_cost :cost)
                    3)
                   (org-ai-skills--find-first-value-recursive
                    provider-data
                    '(:estimated-cost-usd :cost-usd :total-cost
                      :estimated_cost :total_cost :cost)
                    4)))
         (input-n (and (numberp input) input))
         (output-n (and (numberp output) output))
         (total-n (cond
                   ((numberp total) total)
                   ((or input-n output-n) (+ (or input-n 0) (or output-n 0)))
                   (t nil)))
         (estimated-cost
          (cond
           ((numberp cost) cost)
           ((and (numberp org-ai-skills-observability-cost-per-1k-input-tokens)
                 (numberp org-ai-skills-observability-cost-per-1k-output-tokens)
                 input-n output-n)
            (+ (* (/ input-n 1000.0) org-ai-skills-observability-cost-per-1k-input-tokens)
               (* (/ output-n 1000.0) org-ai-skills-observability-cost-per-1k-output-tokens)))
           (t nil))))
    (list :input-tokens input-n
          :output-tokens output-n
          :total-tokens total-n
          :estimated-cost-usd estimated-cost)))

(defun org-ai-skills--run-state-accumulate-usage (run-state usage)
  "Accumulate normalized USAGE into RUN-STATE aggregate metrics."
  (let* ((metrics (or (plist-get run-state :metrics) nil))
         (usage-totals (or (plist-get metrics :usage-totals) nil))
         (prev-input (or (plist-get usage-totals :input-tokens) 0))
         (prev-output (or (plist-get usage-totals :output-tokens) 0))
         (prev-total (or (plist-get usage-totals :total-tokens) 0))
         (prev-cost (or (plist-get usage-totals :estimated-cost-usd) 0.0))
         (next-input (+ prev-input (or (plist-get usage :input-tokens) 0)))
         (next-output (+ prev-output (or (plist-get usage :output-tokens) 0)))
         (next-total (+ prev-total (or (plist-get usage :total-tokens) 0)))
         (next-cost (+ prev-cost (or (plist-get usage :estimated-cost-usd) 0.0)))
         (next-totals (list :input-tokens next-input
                            :output-tokens next-output
                            :total-tokens next-total
                            :estimated-cost-usd next-cost)))
    (plist-put run-state :metrics (plist-put metrics :usage-totals next-totals))))

(defun org-ai-skills-build-step-request (step run-state loaded-skills)
  "Build one execution request from STEP, RUN-STATE, and LOADED-SKILLS."
  (let* ((task (or (plist-get run-state :task) ""))
         (subtree (plist-get run-state :subtree))
         (working-directory (or (plist-get run-state :working-directory)
                                (org-ai-skills--resolve-working-directory subtree)))
         (compose-step-p
          (seq-some (lambda (skill)
                      (string= (plist-get skill :skill-id) org-ai-skills--compose-skill-id))
                    loaded-skills))
         (input-text (or (org-ai-skills--run-state-latest-output run-state)
                         (plist-get subtree :text)
                         ""))
         (effective-input
          (if compose-step-p
              (concat
               "Outline summary (compact context):\n"
               (org-ai-skills--compose-outline-summary input-text))
            input-text))
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
           (format "Source file path: %s\n\n"
                   (or (plist-get subtree :source-file-path) ""))
           (format "Working directory hint: %s\n\n"
                   (or working-directory ""))
           (if compose-step-p
               (concat
                "Strict compose constraints:\n"
                "- Keep all headline lines unchanged at all levels.\n"
                "- Do not output property drawers.\n"
                "- Internally summarize outline first, then expand each heading.\n\n")
             "")
           "Selected skills:\n"
           skill-block
           "\nInput content:\n\n"
           effective-input)))
    (list :event-type 'step-execution
          :request-role 'execution
          :step-id (plist-get step :step-id)
          :skill-ids (plist-get step :skills)
          :composition-reason (or (plist-get step :composition-reason) "")
          :plan-revision (or (plist-get run-state :plan-revision) 1)
          :source-file-path (plist-get subtree :source-file-path)
          :working-directory working-directory
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
         (stage-start-ms (org-ai-skills--observability-now-ms))
         (loaded-skills (mapcar (lambda (skill-id)
                                  (org-ai-skills-load-skill-by-id skill-id directory))
                                skill-ids))
         (request nil)
         (dispatched nil)
         (failed nil))
    (unwind-protect
        (progn
          (dolist (skill loaded-skills)
            (org-ai-skills-apply-skill-function-calls skill))
          (setq request (org-ai-skills-build-step-request step run-state loaded-skills))
          (org-ai-skills-gptel-dispatch-rewrite
           request
           (lambda (&rest response)
             (unwind-protect
                 (unless failed
                   (condition-case err
                       (let ((raw (apply #'org-ai-skills--extract-gptel-response-text-if-ready response)))
                         (let ((first (car response))
                               (info (cadr response)))
                           (setq request
                                 (plist-put
                                  request
                                  :provider-data
                                  (org-ai-skills--select-provider-usage-source
                                   first info (plist-get request :provider-data)))))
                         (when raw
                           (let* ((output (org-ai-skills--extract-subtree-body raw))
                                  (usage (org-ai-skills--normalize-provider-usage
                                          (plist-get request :provider-data)))
                                  (updated-run-state (org-ai-skills--record-run-step run-state step output))
                                  (stage-end-ms (org-ai-skills--observability-now-ms))
                                  (timed-run-state
                                   (org-ai-skills--run-state-append-timing-event
                                    updated-run-state
                                    'execution.step
                                    stage-start-ms
                                    stage-end-ms
                                    (list :status 'success
                                          :step-id (plist-get step :step-id)
                                          :skill-ids (plist-get step :skills)
                                          :plan-revision (or (plist-get run-state :plan-revision) 1)
                                          :usage usage
                                          :estimated-cost-usd
                                          (plist-get usage :estimated-cost-usd))))
                                  (metered-run-state
                                   (org-ai-skills--run-state-accumulate-usage timed-run-state usage)))
                             (funcall callback metered-run-state output))))
                     (org-ai-skills-gptel-error
                      (setq failed t)
                      (let* ((message (error-message-string err))
                             (stage-end-ms (org-ai-skills--observability-now-ms))
                             (usage (org-ai-skills--normalize-provider-usage
                                     (plist-get request :provider-data)))
                             (timed-run-state
                              (org-ai-skills--run-state-append-timing-event
                               run-state
                               'execution.step
                               stage-start-ms
                               stage-end-ms
                               (list :status 'error
                                     :step-id (plist-get step :step-id)
                                     :skill-ids (plist-get step :skills)
                                     :plan-revision (or (plist-get run-state :plan-revision) 1)
                                     :usage usage
                                     :estimated-cost-usd
                                     (plist-get usage :estimated-cost-usd)
                                     :error message)))
                             (metered-run-state
                              (org-ai-skills--run-state-accumulate-usage timed-run-state usage)))
                        (funcall callback (plist-put metered-run-state :fatal-error message) nil)))))
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
  "Request planner plan using TASK, METADATA, and RUN-STATE.
CALLBACK receives (PLANNER-RESPONSE UPDATED-RUN-STATE)."
  (let ((request (org-ai-skills-build-planner-request task metadata run-state))
        (request-start-ms (org-ai-skills--observability-now-ms))
        (planner-text "")
        (provider-data nil)
        (done nil))
    (org-ai-skills-gptel-dispatch-rewrite
     request
     (lambda (&rest response)
       (unless done
         (let ((first (car response))
               (info (cadr response))
               (text (apply #'org-ai-skills--extract-gptel-response-text-if-ready response)))
           (setq provider-data
                 (org-ai-skills--select-provider-usage-source
                  first info provider-data))
           (when (and (eq first t)
                      (not done)
                      (not (string-empty-p planner-text)))
             (signal 'org-ai-skills-planner-error
                     (list
                      "Planner response ended before complete JSON payload was received")))
           (when text
             (setq planner-text (concat planner-text text))
             (let ((parse-start-ms (org-ai-skills--observability-now-ms)))
               (condition-case err
                   (let* ((parsed (org-ai-skills-parse-planner-response
                                   planner-text metadata
                                   (and (listp (plist-get run-state :steps))
                                        (plist-get run-state :steps))))
                           (parse-end-ms (org-ai-skills--observability-now-ms))
                           (usage (org-ai-skills--normalize-provider-usage provider-data))
                           (timed-run-state
                            (org-ai-skills--run-state-append-timing-event
                             (org-ai-skills--run-state-append-timing-event
                              run-state
                              'planning.parse
                              parse-start-ms
                              parse-end-ms
                              (list :status 'success
                                    :plan-revision (or (plist-get run-state :plan-revision) 1)
                                    :usage usage
                                    :estimated-cost-usd
                                    (plist-get usage :estimated-cost-usd)))
                             'planning.request
                             request-start-ms
                             parse-end-ms
                             (list :status 'success
                                   :plan-revision (or (plist-get run-state :plan-revision) 1)
                                   :usage usage
                                   :estimated-cost-usd
                                   (plist-get usage :estimated-cost-usd))))
                           (metered-run-state
                            (org-ai-skills--run-state-accumulate-usage timed-run-state usage)))
                     (setq done t
                           run-state metered-run-state)
                     (funcall callback parsed metered-run-state))
                  (org-ai-skills-planner-error
                   (let ((msg (error-message-string err)))
                    ;; Some backends emit chunked planner text even when stream is off.
                    ;; Keep accumulating until JSON is complete.
                    (unless (or (string-match-p "End of file while parsing JSON" msg)
                                (string-match-p "does not contain a JSON object" msg))
                       (let* ((error-end-ms (org-ai-skills--observability-now-ms))
                              (usage (org-ai-skills--normalize-provider-usage provider-data))
                              (timed-run-state
                               (org-ai-skills--run-state-append-timing-event
                                run-state
                                'planning.request
                                request-start-ms
                                error-end-ms
                                (list :status 'error
                                      :plan-revision (or (plist-get run-state :plan-revision) 1)
                                      :usage usage
                                      :estimated-cost-usd
                                      (plist-get usage :estimated-cost-usd)
                                      :error msg))))
                         (setq run-state (org-ai-skills--run-state-accumulate-usage
                                          timed-run-state usage)))
                       (signal (car err) (cdr err))))))))))))))

(defun org-ai-skills--run-plan-steps (task metadata run-state plan callback &optional directory)
  "Run PLAN steps recursively for TASK and METADATA.
Invoke CALLBACK with final run-state when done."
  (let* ((run-state (org-ai-skills--run-state-record-plan
                     run-state
                     plan
                     (or (plist-get run-state :plan-revision) 1)
                     'active))
         (pending (org-ai-skills--filter-pending-steps plan run-state)))
    (if (null pending)
        (funcall callback
                 (plist-put run-state :final-output
                            (org-ai-skills--run-state-latest-output run-state)))
      (org-ai-skills-execute-plan-step
       (car pending)
       run-state
       (lambda (updated-run-state _output)
         (cond
          ((plist-get updated-run-state :fatal-error)
           (funcall callback updated-run-state))
          ((not org-ai-skills-planner-auto-replan)
           (org-ai-skills--run-plan-steps
            task metadata updated-run-state (cdr pending) callback directory))
          (t
           (org-ai-skills--request-planner-plan
            task
            metadata
            updated-run-state
            (lambda (planner-response replanned-run-state)
              (let ((revised-plan
                     (org-ai-skills-maybe-replan replanned-run-state planner-response)))
                (if revised-plan
                    (let* ((next-revision (1+ (or (plist-get replanned-run-state
                                                             :plan-revision)
                                                 1)))
                           (next-state
                            (org-ai-skills--run-state-record-plan
                             (plist-put
                              (plist-put replanned-run-state
                                         :plan-revision
                                         next-revision)
                              :replans (1+ (or (plist-get replanned-run-state :replans) 0)))
                             revised-plan
                             next-revision
                             'replan)))
                      (org-ai-skills--run-plan-steps
                       task metadata next-state revised-plan callback directory))
                  (org-ai-skills--run-plan-steps
                   task metadata replanned-run-state (cdr pending) callback directory))))))))
       directory))))

(defun org-ai-skills-run-task-with-planner (task subtree &optional options callback)
  "Run TASK on SUBTREE using autonomous planner flow.
OPTIONS is a plist; CALLBACK receives final run-state."
  (let* ((directory (or (plist-get options :directory) org-ai-skills-skill-dir))
         (working-directory (or (plist-get options :working-directory)
                                (org-ai-skills--resolve-working-directory subtree)))
         (metadata (org-ai-skills-load-skill-metadata directory))
         (run-state (list :run-id (format-time-string "%Y%m%d%H%M%S")
                          :task task
                          :subtree subtree
                          :working-directory working-directory
                          :metadata-snapshot metadata
                          :plan-revision 1
                          :replans 0
                          :steps nil
                          :latest-output nil
                          :final-output nil
                          :metrics (list :usage-totals
                                         (list :input-tokens 0
                                               :output-tokens 0
                                               :total-tokens 0
                                               :estimated-cost-usd 0.0))
                          :events nil))
         (final-callback (or callback (lambda (_state) nil))))
    (org-ai-skills--request-planner-plan
     task
     metadata
     run-state
     (lambda (planner-response planned-run-state)
       (let* ((plan (plist-get planner-response :plan))
              (planned-state (org-ai-skills--run-state-record-plan
                              planned-run-state
                              plan
                              (or (plist-get planned-run-state :plan-revision) 1)
                              'initial)))
         (org-ai-skills--run-plan-steps task metadata planned-state plan final-callback directory))))
    run-state))

(defun org-ai-skills--append-debug-entry (request)
  "Append one debug REQUEST entry when debug mode is enabled."
  (when org-ai-skills-debug-enabled
    (let* ((timestamp (format-time-string "%Y-%m-%d %H:%M:%S %z"))
           (source (plist-get (plist-get request :skill-context) :source-subtree))
           (event-type (or (plist-get request :event-type) 'rewrite))
           (log-level (org-ai-skills--normalize-debug-log-level
                       (or (plist-get request :log-level)
                           (org-ai-skills--default-debug-log-level event-type))))
           (stage-id (format "%s"
                             (or (plist-get request :stage-id)
                                 (symbol-name event-type))))
           (step-id (format "%s" (or (plist-get request :step-id) "")))
           (request-role (or (plist-get request :request-role) ""))
           (effective-model (or (plist-get request :effective-model) ""))
           (system-fingerprint (or (plist-get request :effective-system-prompt-fingerprint) ""))
           (entry
            (concat
             (format "=== org-ai-skills gptel dispatch @ %s ===\n" timestamp)
             (format "Log level: %s\n" log-level)
             (format "Event: %s\n" event-type)
             (format "Stage id: %s\n" stage-id)
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
             (format "Step id: %s\n" step-id)
             (format "Skill ids: %s\n" (or (plist-get request :skill-ids) ""))
             (format "Composition reason: %s\n" (or (plist-get request :composition-reason) ""))
             "Prompt:\n"
             (or (plist-get request :prompt) "")
             "\n\nRequest plist:\n"
             (pp-to-string request)
             "\n")))
      (push (list :timestamp timestamp
                  :event-type event-type
                  :log-level log-level
                  :step-id step-id
                  :stage-id stage-id
                  :request request
                  :entry entry)
            org-ai-skills--debug-events)
      (setq org-ai-skills--last-debug-entry entry)
      (with-current-buffer (get-buffer-create org-ai-skills-debug-buffer-name)
        (goto-char (point-max))
        (insert entry)))))

(defun org-ai-skills--default-debug-log-level (event-type)
  "Return default log level symbol for EVENT-TYPE."
  (pcase event-type
    ((or 'callback-error 'planner-error 'execution-error) 'error)
    ((or 'planner-warning 'execution-warning) 'warn)
    ((or 'property-retention 'gptel-request-data 'tool-call 'tool-result) 'debug)
    (_ 'info)))

(defun org-ai-skills--normalize-debug-log-level (level)
  "Return normalized debug log LEVEL symbol."
  (cond
   ((memq level '(debug info warn error)) level)
   ((stringp level)
    (let ((parsed (intern-soft (downcase level))))
      (if (memq parsed '(debug info warn error))
          parsed
        'info)))
   (t 'info)))

(defun org-ai-skills-debug-filter-events (&optional level step-or-stage)
  "Return debug events filtered by LEVEL and STEP-OR-STAGE.
LEVEL is one of `debug', `info', `warn', `error', or nil for all.
STEP-OR-STAGE matches event :step-id or :stage-id when non-nil."
  (let* ((level (and level (org-ai-skills--normalize-debug-log-level level)))
         (needle (and step-or-stage (format "%s" step-or-stage))))
    (seq-filter
     (lambda (event)
       (and (or (null level)
                (eq level (plist-get event :log-level)))
            (or (null needle)
                (string= needle (format "%s" (or (plist-get event :step-id) "")))
                (string= needle (format "%s" (or (plist-get event :stage-id) ""))))))
     (nreverse (copy-sequence org-ai-skills--debug-events)))))

(defun org-ai-skills-debug-show-filtered (&optional level step-or-stage)
  "Show debug entries filtered by LEVEL and STEP-OR-STAGE.
When LEVEL or STEP-OR-STAGE are nil, use configured filter variables."
  (interactive)
  (let* ((level (or level org-ai-skills-debug-filter-level))
         (step-or-stage (or step-or-stage org-ai-skills-debug-filter-step))
         (events (org-ai-skills-debug-filter-events level step-or-stage)))
    (if (null events)
        (message "No org-ai-skills debug entries match level=%s step/stage=%s"
                 (or level "all")
                 (or step-or-stage "all"))
      (with-current-buffer (get-buffer-create org-ai-skills-debug-buffer-name)
        (erase-buffer)
        (insert (format "Filtered debug entries: level=%s step/stage=%s count=%d\n\n"
                        (or level "all")
                        (or step-or-stage "all")
                        (length events)))
        (dolist (event events)
          (insert (plist-get event :entry)))
        (goto-char (point-min))
        (pop-to-buffer (current-buffer))))))

(defun org-ai-skills-debug-set-filter (&optional level step-or-stage)
  "Set debug inspection filters to LEVEL and STEP-OR-STAGE.
Passing nil clears each corresponding filter."
  (interactive)
  (setq org-ai-skills-debug-filter-level level
        org-ai-skills-debug-filter-step step-or-stage)
  (message "org-ai-skills debug filter level=%s step/stage=%s"
           (or org-ai-skills-debug-filter-level "all")
           (or org-ai-skills-debug-filter-step "all")))

(defun org-ai-skills--append-property-retention-debug (phase payload)
  "Append property-retention debug entry with PHASE and PAYLOAD."
  (when (and org-ai-skills-debug-enabled
             org-ai-skills-debug-property-retention)
    (org-ai-skills--append-debug-entry
     (list :event-type 'property-retention
           :log-level 'debug
           :stage-id 'property-retention
           :request-role 'execution
           :prompt (format "property-retention %s" phase)
           :phase phase
           :payload payload
           :buffer-name (buffer-name)
           :buffer-file (buffer-file-name)))))

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

(defun org-ai-skills--parse-provider-tool-result (raw-result)
  "Parse RAW-RESULT into provider plist when possible."
  (cond
   ((and (listp raw-result)
         (plist-member raw-result :ok))
    raw-result)
   ((stringp raw-result)
    (condition-case nil
        (let ((parsed (car (read-from-string raw-result))))
          (when (and (listp parsed)
                     (plist-member parsed :ok))
            parsed))
      (error nil)))
   (t nil)))

(defun org-ai-skills--tool-name-from-result-item (item)
  "Extract tool name string from one gptel tool result ITEM."
  (let ((tool (car-safe item)))
    (cond
     ((and (listp tool)
           (eq (car-safe tool) 'gptel-tool))
      (or (cadr tool) "unknown-tool"))
     (t
      (let ((text (format "%S" tool)))
        (if (string-match "#s(gptel-tool\\s-+\\([^[:space:])]+\\)" text)
            (match-string 1 text)
          "unknown-tool"))))))

(defun org-ai-skills--extract-tool-result-errors (&rest response)
  "Extract provider tool errors from gptel callback RESPONSE.
Return list of error plists, each with :tool-name, :error-kind and :error-message."
  (let ((first (car response))
        (errors nil))
    (when (and (consp first)
               (eq (car first) 'tool-result))
      (dolist (item (cdr first))
        (let* ((raw-result (nth 2 item))
               (parsed (org-ai-skills--parse-provider-tool-result raw-result))
               (error-kind (and parsed (plist-get parsed :error-kind))))
          (when (and parsed
                     (plist-member parsed :ok)
                     (null (plist-get parsed :ok))
                     (stringp error-kind)
                     (not (string-empty-p error-kind)))
            (push (list :tool-name (org-ai-skills--tool-name-from-result-item item)
                        :error-kind error-kind
                        :error-message (or (plist-get parsed :error-message)
                                           "Provider tool execution failed"))
                  errors)))))
    (nreverse errors)))

(defun org-ai-skills--format-tool-result-error-message (tool-errors)
  "Format TOOL-ERRORS list into one user-visible error message."
  (let* ((first (car tool-errors))
         (tool-name (or (plist-get first :tool-name) "unknown-tool"))
         (error-kind (or (plist-get first :error-kind) "unknown-error"))
         (error-message (or (plist-get first :error-message) "tool execution failed")))
    (format "Provider tool failed (%s, %s): %s"
            tool-name error-kind error-message)))

(defun org-ai-skills--extract-gptel-response-text-if-ready (&rest response)
  "Return text when RESPONSE is a final text callback, else nil.
Interim callback events such as tool-call, tool-result, reasoning chunks,
or stream completion markers are ignored and return nil."
  (let ((first (car response))
        (tool-errors (apply #'org-ai-skills--extract-tool-result-errors response)))
    (when tool-errors
      (org-ai-skills--signal-gptel-error
       (org-ai-skills--format-tool-result-error-message tool-errors)))
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
  (if (eq (plist-get subtree :context-mode) 'buffer)
      (org-ai-skills--strip-markdown-fences (or rewritten-text ""))
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
      (org-ai-skills--normalize-subtree-levels with-heading target-level))))

(defun org-ai-skills--strip-property-drawers-from-text (text)
  "Return TEXT with Org property drawers removed."
  (with-temp-buffer
    (insert (or text ""))
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*:PROPERTIES:[ \t]*$" nil t)
      (let ((start (line-beginning-position)))
        (if (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
            (delete-region start
                           (min (point-max)
                                (1+ (line-end-position))))
          ;; Unclosed drawer: drop from :PROPERTIES: to end of buffer.
          (delete-region start (point-max)))))
    (buffer-string)))

(defun org-ai-skills--strip-indented-property-drawers-from-text (text)
  "Return TEXT with only indented pseudo property drawers removed.
Keep valid non-indented drawers intact."
  (with-temp-buffer
    (insert (or text ""))
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]+:PROPERTIES:[ \t]*$" nil t)
      (let ((start (line-beginning-position)))
        (if (re-search-forward "^[ \t]+:END:[ \t]*$" nil t)
            (delete-region start
                           (min (point-max)
                                (1+ (line-end-position))))
          (delete-region start (point-max)))))
    (buffer-string)))

(defun org-ai-skills--org-heading-lines (text)
  "Return all Org heading lines from TEXT."
  (let ((lines nil))
    (with-temp-buffer
      (insert (or text ""))
      (goto-char (point-min))
      (while (re-search-forward "^\\*+\\s-+.*$" nil t)
        (push (buffer-substring-no-properties
               (line-beginning-position)
               (line-end-position))
              lines)))
    (nreverse lines)))

(defun org-ai-skills--enforce-rewrite-constraints (rewritten-text subtree constraints)
  "Apply rewrite CONSTRAINTS to REWRITTEN-TEXT for SUBTREE."
  (let ((result (or rewritten-text "")))
    (when (plist-get constraints :omit-property-drawers)
      (setq result (org-ai-skills--strip-property-drawers-from-text result)))
    (when (and (plist-get constraints :preserve-headlines)
               (not (eq (plist-get subtree :context-mode) 'buffer)))
      (let ((expected (org-ai-skills--org-heading-lines (plist-get subtree :text)))
            (actual (org-ai-skills--org-heading-lines result)))
        (unless (equal expected actual)
          (org-ai-skills--signal-org-context-error
           "Strict rewrite rejected: headline lines changed"))))
    result))

(defconst org-ai-skills--strict-rewrite-guard
  (concat
   "Strict constraints:\n"
   "- Keep every headline line unchanged at all levels (same stars and same text).\n"
   "- Do not add/remove/reorder headlines.\n"
   "- Do not output any property drawer block (:PROPERTIES: ... :END:).\n"
   "- Only rewrite paragraph/list content under existing headings.")
  "Guard instruction used by strict rewrite command.")

(defconst org-ai-skills--compose-skill-id "article-compose-from-outline"
  "Skill id used for article composition from approved outline.")

(defun org-ai-skills--strict-rewrite-instruction (instruction)
  "Build strict rewrite instruction string from optional INSTRUCTION."
  (if (string-empty-p (or instruction ""))
      org-ai-skills--strict-rewrite-guard
    (concat org-ai-skills--strict-rewrite-guard
            "\n\nAdditional instruction:\n"
            instruction)))

(defun org-ai-skills--skill-default-rewrite-constraints (skill-id)
  "Return default rewrite constraints for SKILL-ID."
  (if (and (stringp skill-id)
           (string= skill-id org-ai-skills--compose-skill-id))
      '(:preserve-headlines t :omit-property-drawers t)
    nil))

(defun org-ai-skills--merge-rewrite-constraints (base override)
  "Merge BASE and OVERRIDE rewrite constraints plists."
  (let ((result (copy-sequence (or base nil))))
    (while override
      (setq result (plist-put result (car override) (cadr override)))
      (setq override (cddr override)))
    result))

(defun org-ai-skills--compose-outline-summary (text)
  "Build compact outline summary from Org TEXT."
  (with-temp-buffer
    (insert (or text ""))
    (goto-char (point-min))
    (let ((parts nil))
      (while (re-search-forward "^\\(\\*+\\)\\s-+\\(.*\\)$" nil t)
        (let ((heading (format "%s %s" (match-string 1) (match-string 2)))
              (purpose nil)
              (source-path nil)
              (start (line-end-position))
              (end (save-excursion
                     (if (re-search-forward "^\\*+\\s-+" nil t)
                         (line-beginning-position)
                       (point-max)))))
          (save-excursion
            (goto-char start)
            (when (re-search-forward "^[ \t]*:PURPOSE:[ \t]*\\(.*\\)$" end t)
              (setq purpose (string-trim (match-string 1))))
            (goto-char start)
            (when (re-search-forward "^[ \t]*:SOURCE_FILE_PATH:[ \t]*\\(.*\\)$" end t)
              (setq source-path (string-trim (match-string 1)))))
          (push (concat heading
                        (if (and (stringp purpose) (not (string-empty-p purpose)))
                            (format "\n  PURPOSE: %s" purpose)
                          "")
                        (if (and (stringp source-path) (not (string-empty-p source-path)))
                            (format "\n  SOURCE_FILE_PATH: %s" source-path)
                          ""))
                parts)))
      (string-join (nreverse parts) "\n"))))

(defun org-ai-skills--rewrite-context-text (skill subtree)
  "Return context text used in rewrite prompt for SKILL and SUBTREE."
  (let* ((skill-id (plist-get skill :skill-id))
         (full (or (plist-get subtree :text) "")))
    (if (and (stringp skill-id)
             (string= skill-id org-ai-skills--compose-skill-id))
        (concat
         "Outline summary (compact context):\n"
         (org-ai-skills--compose-outline-summary full)
         "\n\nGeneration guidance:\n"
         "- First internally derive a concise article-level summary from the outline.\n"
         "- Then expand section-by-section using the existing headings only.\n"
         "- Keep heading lines unchanged.\n")
      full)))

(defun org-ai-skills--run-state-has-skill-id-p (run-state skill-id)
  "Return non-nil when RUN-STATE contains SKILL-ID in completed steps."
  (let ((steps (or (plist-get run-state :steps) nil))
        (hit nil))
    (while (and steps (not hit))
      (setq hit (member skill-id (or (plist-get (car steps) :skills) nil)))
      (setq steps (cdr steps)))
    hit))

(defun org-ai-skills--run-state-last-step-skill-ids (run-state)
  "Return skill id list from final completed step in RUN-STATE."
  (let ((steps (or (plist-get run-state :steps) nil))
        (last-skills nil))
    (dolist (step steps)
      (let ((skills (plist-get step :skills)))
        (when (listp skills)
          (setq last-skills skills))))
    last-skills))

(defun org-ai-skills--planner-run-state-target-skill-id (run-state)
  "Return target skill id inferred from planner RUN-STATE."
  (let ((skills (org-ai-skills--run-state-last-step-skill-ids run-state)))
    (when (and (listp skills) (> (length skills) 0))
      (car (last skills)))))

(defun org-ai-skills--planner-run-state-skill-file (run-state skill-id)
  "Return skill file path for SKILL-ID from planner RUN-STATE metadata."
  (let ((meta (seq-find
               (lambda (entry)
                 (equal (plist-get entry :skill-id) skill-id))
               (or (plist-get run-state :metadata-snapshot) nil))))
    (and meta (plist-get meta :file))))

(defun org-ai-skills--resolve-target-skill-from-ui-run-state (ui-run-state)
  "Resolve target skill binding plist from UI-RUN-STATE.
Return plist with :skill-id, :skill-file, and :source; return nil when unknown."
  (let* ((rewrite-skill (plist-get ui-run-state :skill))
         (rewrite-skill-id (and (consp rewrite-skill)
                                (plist-get rewrite-skill :skill-id)))
         (rewrite-skill-file (and (consp rewrite-skill)
                                  (plist-get rewrite-skill :file))))
    (cond
     ((stringp (plist-get ui-run-state :target-skill-id))
      (list :skill-id (plist-get ui-run-state :target-skill-id)
            :skill-file (plist-get ui-run-state :target-skill-file)
            :source "ui-state"))
     ((stringp rewrite-skill-id)
      (list :skill-id rewrite-skill-id
            :skill-file rewrite-skill-file
            :source "rewrite"))
     (t
      (let* ((planner-state (plist-get ui-run-state :planner-run-state))
             (planner-skill-id (and (consp planner-state)
                                    (org-ai-skills--planner-run-state-target-skill-id planner-state)))
             (planner-skill-file (and (stringp planner-skill-id)
                                      (org-ai-skills--planner-run-state-skill-file planner-state planner-skill-id))))
        (when (stringp planner-skill-id)
          (list :skill-id planner-skill-id
                :skill-file planner-skill-file
                :source "planner-last-step")))))))

(defun org-ai-skills--planner-constraints-for-run-state (run-state)
  "Return rewrite constraints inferred from final completed step of RUN-STATE."
  (let ((skills (org-ai-skills--run-state-last-step-skill-ids run-state))
        (merged nil))
    (dolist (skill-id skills)
      (setq merged
            (org-ai-skills--merge-rewrite-constraints
             merged
             (org-ai-skills--skill-default-rewrite-constraints skill-id))))
    merged))

(defun org-ai-skills--org-front-matter-end (text)
  "Return end position of leading Org file front matter in TEXT."
  (with-temp-buffer
    (insert (or text ""))
    (goto-char (point-min))
    (while (and (not (eobp))
                (looking-at-p
                 (concat
                  "\\(?:[ \t]*\\)$"
                  "\\|^#\\+[[:alnum:]_@-]+:"
                  "\\|^#[ \t]")))
      (forward-line 1))
    (point)))

(defun org-ai-skills--extract-org-front-matter (text)
  "Extract leading Org file front matter from TEXT."
  (let ((end (org-ai-skills--org-front-matter-end text)))
    (substring (or text "") 0 (max 0 (1- end)))))

(defun org-ai-skills--strip-org-front-matter (text)
  "Strip leading Org file front matter from TEXT."
  (let* ((source (or text ""))
         (end (org-ai-skills--org-front-matter-end source)))
    (if (> end (length source))
        ""
      (substring source (max 0 (1- end))))))

(defun org-ai-skills--merge-buffer-rewrite-preserving-front-matter (existing rewritten)
  "Merge EXISTING and REWRITTEN text while preserving existing file front matter."
  (let* ((front (string-trim-right
                 (org-ai-skills--extract-org-front-matter existing)))
         (body (string-trim-left
                (org-ai-skills--strip-org-front-matter rewritten))))
    (if (string-empty-p front)
        rewritten
      (if (string-empty-p body)
          (concat front "\n")
        (concat front "\n\n" body)))))

(defun org-ai-skills--collect-subtree-explicit-properties (begin end keys)
  "Collect explicit KEYS property values from headings in region BEGIN..END."
  (let ((entries nil)
        (end-pos (if (markerp end) (marker-position end) end))
        (index 0)
        (level-index (make-hash-table :test #'eql)))
    (save-excursion
      (save-restriction
        (narrow-to-region begin end-pos)
        (goto-char (point-min))
        (when (org-at-heading-p)
          (while (org-at-heading-p)
            (setq index (1+ index))
            (let ((path (mapconcat #'identity (org-get-outline-path t t) "\x1f"))
                  (title (or (org-get-heading t t t t) ""))
                  (level (org-outline-level))
                  (level-pos 0)
                  (props nil))
              (setq level-pos (1+ (or (gethash level level-index) 0)))
              (puthash level level-pos level-index)
              (dolist (key keys)
                (let ((value (org-entry-get (point) key nil)))
                  (when (and (stringp value)
                             (not (string-empty-p value)))
                    (push (cons key value) props))))
              (when props
                (push (list :index index
                            :path path
                            :title title
                            :level level
                            :level-pos level-pos
                            :props props)
                      entries)))
            (outline-next-heading)))))
    (org-ai-skills--append-property-retention-debug
     "collect"
     (list :begin begin
           :end end
           :keys keys
           :entry-count (length entries)
           :entries (cl-subseq entries 0 (min (length entries) 20))))
    (nreverse entries)))

(defun org-ai-skills--string-similarity (left right)
  "Return normalized similarity score in [0,1] for LEFT and RIGHT."
  (let* ((a (downcase (or left "")))
         (b (downcase (or right "")))
         (max-len (max (length a) (length b))))
    (if (= max-len 0)
        1.0
      (- 1.0 (/ (float (string-distance a b)) max-len)))))

(defun org-ai-skills--restore-subtree-explicit-properties (begin end keys entries)
  "Restore explicit KEYS from ENTRIES onto matching headings in BEGIN..END."
  (when entries
    (let* ((end-pos (if (markerp end) (marker-position end) end))
           (path-table (make-hash-table :test #'equal))
           (title-table (make-hash-table :test #'equal))
           (level-title-table (make-hash-table :test #'equal))
           (order-table (make-hash-table :test #'equal))
           (used (make-hash-table :test #'equal))
           (decisions nil))
      (dolist (entry entries)
        (let* ((path (plist-get entry :path))
               (title (or (plist-get entry :title) ""))
               (level (plist-get entry :level))
               (level-pos (plist-get entry :level-pos))
               (order-key (format "%d|%d" level level-pos))
               (level-title-key (format "%d|%s" level (downcase title))))
          (puthash path entry path-table)
          (puthash order-key entry order-table)
          (puthash title (cons entry (gethash title title-table)) title-table)
          (puthash level-title-key
                   (cons entry (gethash level-title-key level-title-table))
                   level-title-table)))
      (save-excursion
        (save-restriction
          (narrow-to-region begin end-pos)
          (goto-char (point-min))
          (let ((level-index (make-hash-table :test #'eql)))
            (when (org-at-heading-p)
              (while (org-at-heading-p)
                (let* ((path (mapconcat #'identity (org-get-outline-path t t) "\x1f"))
                       (title (or (org-get-heading t t t t) ""))
                       (level (org-outline-level))
                       (level-pos (1+ (or (gethash level level-index) 0)))
                       (order-key (format "%d|%d" level level-pos))
                       (level-title-key (format "%d|%s" level (downcase title)))
                       (path-match (gethash path path-table))
                       (title-matches (gethash title title-table))
                       (title-match (and (= (length title-matches) 1)
                                         (car title-matches)))
                       (level-title-matches (gethash level-title-key level-title-table))
                       (level-title-match (and (= (length level-title-matches) 1)
                                               (car level-title-matches)))
                       (order-match (gethash order-key order-table))
                       (fuzzy-match
                        (let ((best nil)
                              (best-score 0.0))
                          (dolist (candidate entries)
                            (when (and (= (plist-get candidate :level) level)
                                       (not (gethash (plist-get candidate :index) used)))
                              (let ((score (org-ai-skills--string-similarity
                                            title
                                            (plist-get candidate :title))))
                                (when (> score best-score)
                                  (setq best-score score)
                                  (setq best candidate)))))
                          (when (>= best-score 0.6) best)))
                       (match-strategy 'unmatched)
                       (saved nil)
                       (restored-keys nil))
                  (setq saved
                        (cond
                         ((and path-match
                               (not (gethash (plist-get path-match :index) used)))
                          (setq match-strategy 'path)
                          path-match)
                         ((and level-title-match
                               (not (gethash (plist-get level-title-match :index) used)))
                          (setq match-strategy 'exact-level-title)
                          level-title-match)
                         ((and title-match
                               (not (gethash (plist-get title-match :index) used)))
                          (setq match-strategy 'title)
                          title-match)
                         ((and order-match
                               (not (gethash (plist-get order-match :index) used)))
                          (setq match-strategy 'level-order)
                          order-match)
                         ((and fuzzy-match
                               (not (gethash (plist-get fuzzy-match :index) used)))
                          (setq match-strategy 'fuzzy-level-title)
                          fuzzy-match)
                         (t nil)))
                  (puthash level level-pos level-index)
                  (when saved
                    (puthash (plist-get saved :index) t used)
                    (dolist (key keys)
                      (let ((saved-value (cdr (assoc key (plist-get saved :props))))
                            (current-value (org-entry-get (point) key nil)))
                        (when (and (stringp saved-value)
                                   (or (null current-value)
                                       (string-empty-p current-value)))
                          (org-entry-put (point) key saved-value)
                          (push key restored-keys)))))
                  (push (list :path path
                              :title title
                              :level level
                              :strategy match-strategy
                              :restored (nreverse restored-keys))
                        decisions)
                  (outline-next-heading)))))))
      (org-ai-skills--append-property-retention-debug
       "restore"
       (list :begin begin
             :end end
             :keys keys
             :entry-count (length entries)
             :decision-count (length decisions)
             :decisions (nreverse
                         (cl-subseq decisions 0 (min (length decisions) 40))))))))

(defun org-ai-skills--ensure-subtree-heading-ids (begin end)
  "Ensure all headings in BEGIN..END have explicit :ID:."
  (let ((end-pos (if (markerp end) (marker-position end) end)))
    (save-excursion
      (save-restriction
        (narrow-to-region begin end-pos)
        (goto-char (point-min))
        (when (org-at-heading-p)
          (while (org-at-heading-p)
            (unless (org-entry-get (point) "ID" nil)
              (org-entry-put (point) "ID" (org-id-new)))
            (outline-next-heading)))))))

(defun org-ai-skills--consume-leading-property-drawers ()
  "Consume leading blank lines/property drawers and return collected properties.
Return value is an alist of (KEY . VALUE) extracted from consumed drawers."
  (let ((continue t))
    (let ((props nil))
      (while continue
        (while (and (not (eobp))
                    (looking-at-p "^[ \t]*$"))
          (forward-line 1))
        (if (and (not (eobp))
                 (looking-at-p "^[ \t]*:PROPERTIES:[ \t]*$"))
            (progn
              (forward-line 1)
              (while (and (not (eobp))
                          (not (looking-at-p "^[ \t]*:END:[ \t]*$")))
                (when (looking-at "^[ \t]*:\\([^:\n]+\\):[ \t]*\\(.*\\)$")
                  (let* ((key (match-string 1))
                         (value (string-trim (or (match-string 2) ""))))
                    (when (and (stringp key) (not (string-empty-p key)))
                      (setq props (assq-delete-all key props))
                      (push (cons key value) props))))
                (forward-line 1))
              (when (looking-at-p "^[ \t]*:END:[ \t]*$")
                (forward-line 1)))
          (setq continue nil)))
      (nreverse props))))

(defun org-ai-skills-org-apply-rewrite-result (subtree rewritten-text)
  "Replace SUBTREE region with REWRITTEN-TEXT.
Preserve target heading and property drawer by replacing subtree body."
  (let ((cleaned-text (org-ai-skills--strip-indented-property-drawers-from-text
                       rewritten-text)))
    (unless (stringp cleaned-text)
      (org-ai-skills--signal-org-context-error "Rewritten text must be a string"))
    (let ((begin (plist-get subtree :begin))
          (end (plist-get subtree :end)))
      (unless (and begin end (<= begin end))
        (org-ai-skills--signal-org-context-error
         "Invalid subtree range for rewrite"))
      (if (eq (plist-get subtree :context-mode) 'buffer)
          (let* ((preserve-keys '("PURPOSE" "SOURCE_FILE_PATH"))
                 (existing (buffer-substring-no-properties begin end))
                 (merged (org-ai-skills--merge-buffer-rewrite-preserving-front-matter
                          existing
                          cleaned-text))
                 (saved-props nil)
                 (saved-begin nil)
                 (new-begin nil)
                 (new-end nil))
            (save-excursion
              (org-fold-core-ignore-modifications
               (goto-char begin)
               (when (re-search-forward "^\\*+\\s-+" end t)
                 (setq saved-begin (line-beginning-position))
                 (setq saved-props
                       (org-ai-skills--collect-subtree-explicit-properties
                        saved-begin end preserve-keys)))
               (delete-region begin end)
               (goto-char begin)
               (setq new-begin (point))
               (insert merged)
               (setq new-end (point))
               (unless (or (bolp) (string-suffix-p "\n" merged))
                 (insert "\n")
                 (setq new-end (point)))
               (when saved-props
                 (goto-char new-begin)
                 (when (re-search-forward "^\\*+\\s-+" new-end t)
                   (org-ai-skills--restore-subtree-explicit-properties
                    (line-beginning-position) new-end preserve-keys saved-props))))))
        (let ((new-body "")
              (existing-heading-line "")
              (existing-drawer "")
              (generated-leading-props nil)
              (preserve-keys '("PURPOSE" "SOURCE_FILE_PATH"))
              (saved-props nil)
              (new-end nil))
          (with-temp-buffer
            (insert cleaned-text)
            (goto-char (point-min))
            (if (re-search-forward "^\\*+\\s-+" nil t)
                (progn
                  (beginning-of-line)
                  (forward-line 1)
                  (setq generated-leading-props
                        (org-ai-skills--consume-leading-property-drawers))
                  (setq new-body (buffer-substring-no-properties (point) (point-max))))
              (setq new-body cleaned-text)))
          (setq new-body (replace-regexp-in-string "\\`\n+" "" (or new-body "")))
          (save-excursion
            (org-fold-core-ignore-modifications
             (goto-char begin)
             (unless (org-at-heading-p)
               (org-back-to-heading t))
             (setq saved-props
                   (org-ai-skills--collect-subtree-explicit-properties
                    begin end preserve-keys))
             (setq existing-heading-line
                   (format "%s %s"
                           (make-string (org-outline-level) ?*)
                           (org-get-heading t t t t)))
             (forward-line 1)
             (when (looking-at-p "^[ \t]*:PROPERTIES:[ \t]*$")
               (let ((drawer-start (point)))
                 (when (re-search-forward "^[ \t]*:END:[ \t]*$" end t)
                   (forward-line 1)
                   (setq existing-drawer
                         (buffer-substring-no-properties drawer-start (point))))))
             (delete-region begin end)
             (insert existing-heading-line "\n" existing-drawer new-body)
             (unless (or (bolp) (string-suffix-p "\n" new-body))
               (insert "\n"))
             (goto-char begin)
             (unless (org-at-heading-p)
               (org-back-to-heading t))
             ;; Preserve extra generated properties without duplicating drawers.
             (dolist (pair generated-leading-props)
               (let ((key (car pair))
                     (value (cdr pair)))
                 (when (and (stringp key)
                            (stringp value)
                            (not (string-empty-p value))
                            (string-empty-p (or (org-entry-get (point) key nil) "")))
                   (org-entry-put (point) key value))))
             (org-end-of-subtree t t)
             (setq new-end (point))
             (org-ai-skills--restore-subtree-explicit-properties
              begin new-end preserve-keys saved-props)
             (org-ai-skills--ensure-subtree-heading-ids begin new-end))))))))
(defun org-ai-skills--buffer-scope-target ()
  "Return whole-buffer scope target plist."
  (let ((source-file (org-ai-skills--file-keyword-value "SOURCE_FILE_PATH"))
        (buffer-file (buffer-file-name))
        (name (buffer-name)))
    (list :begin (point-min)
          :end (point-max)
          :level 0
          :heading (or source-file buffer-file name)
          :path (or source-file buffer-file name)
          :purpose (or (org-ai-skills--file-keyword-value "PURPOSE") "")
          :source-file-path source-file
          :context-mode 'buffer
          :levels-up 0
          :text (buffer-substring-no-properties (point-min) (point-max)))))

(defun org-ai-skills-org-collect-context-candidates ()
  "Collect subtree rewrite scope candidates from current heading upward.
Return an alist where each item is (DISPLAY . SUBTREE-PLIST)."
  (org-ai-skills--require-org-mode)
  (save-excursion
    (org-with-wide-buffer
      (let ((buffer-item
             (cons (format "[buffer] %s" (or (buffer-file-name) (buffer-name)))
                   (org-ai-skills--buffer-scope-target))))
        (if (org-before-first-heading-p)
            (list buffer-item)
          (unless (org-at-heading-p)
            (org-back-to-heading t))
          (let ((items (list buffer-item))
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
            (nreverse items)))))))

(defun org-ai-skills-org-read-rewrite-target ()
  "Read rewrite target scope from minibuffer with preview."
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

;; Ensure key bindings are refreshed even when map already exists in a live session.
(define-key org-ai-skills-control-mode-map (kbd "s") #'org-ai-skills-ui-stop-run)
(define-key org-ai-skills-control-mode-map (kbd "g") #'org-ai-skills-ui-rerun)
(define-key org-ai-skills-control-mode-map (kbd "t") #'org-ai-skills-ui-adjust-task-or-instruction)
(define-key org-ai-skills-control-mode-map (kbd "v") #'org-ai-skills-ui-show-dag)
(define-key org-ai-skills-control-mode-map (kbd "c") #'org-ai-skills-ui-select-candidate)
(define-key org-ai-skills-control-mode-map (kbd "a") #'org-ai-skills-ui-apply-selected-candidate)
(define-key org-ai-skills-control-mode-map (kbd "d") #'org-ai-skills-ui-discard-selected-candidate)
(define-key org-ai-skills-control-mode-map (kbd "q") #'org-ai-skills-ui-close-workspace)
(define-key org-ai-skills-control-mode-map (kbd "r") #'org-ai-skills-ui-refresh-control-buffer)

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
         (error-detail (org-ai-skills--ui-run-get :error-detail))
         (error-text (when (and (stringp error-detail)
                                (not (string-empty-p error-detail)))
                       (replace-regexp-in-string "[\n\r\t]+" " " error-detail)))
         (running (eq status 'running))
         (run-type (org-ai-skills--ui-run-get :run-type))
         (task (or (org-ai-skills--ui-run-get :task) ""))
         (preset (or (org-ai-skills--ui-run-get :preset-id) ""))
         (slot-key (org-ai-skills--ui-run-get :slot-key))
         (candidates (if (stringp slot-key)
                         (org-ai-skills--load-slot-candidates slot-key)
                       nil))
         (proposals (if (stringp slot-key)
                        (condition-case nil
                            (org-ai-skills--load-proposals slot-key)
                          (org-ai-skills-proposal-store-error nil))
                      nil))
         (heading (or (org-ai-skills--ui-run-get :heading) ""))
         (selected (org-ai-skills--ui-run-get :selected-candidate))
         (selected-id (or (and selected (plist-get selected :candidate-id)) "none"))
         (selected-proposal (org-ai-skills--ui-run-get :selected-proposal))
         (selected-proposal-id (or (and selected-proposal
                                        (plist-get selected-proposal :proposal-id))
                                   "none"))
         (rerun-enabled (and (functionp (org-ai-skills--ui-run-get :rerun-fn))
                             (not running)))
         (adjust-enabled (and (memq run-type '(planner rewrite))
                              (not running)))
         (candidate-enabled (and (listp candidates) (> (length candidates) 0)))
         (apply-enabled (and candidate-enabled (not running)))
         (discard-enabled (and candidate-enabled (not running)))
         (dag-state (or (org-ai-skills--ui-run-get :planner-run-state)
                        org-ai-skills--ui-run-state))
         (dag-enabled
          (or (plist-get dag-state :active-plan)
              (plist-get dag-state :latest-plan)
              (plist-get dag-state :plan-revisions)
              (plist-get dag-state :steps)
              (plist-get dag-state :events)))
         (extract-enabled (and candidate-enabled (not running)))
         (proposal-enabled (and (listp proposals) (> (length proposals) 0)))
         (preview-enabled (and proposal-enabled (not running)))
         (approve-enabled (and proposal-enabled
                               (not running)
                               (let ((status* (and selected-proposal
                                                   (plist-get selected-proposal :status))))
                                 (equal status* "proposed"))))
         (reject-enabled (and proposal-enabled
                              (not running)
                              (let ((status* (and selected-proposal
                                                  (plist-get selected-proposal :status))))
                                (member status* '("proposed" "approved")))))
         (proposal-apply-enabled (and proposal-enabled
                                     (not running)
                                     (let ((status* (and selected-proposal
                                                         (plist-get selected-proposal :status))))
                                       (equal status* "approved"))))
         (proposal-file-apply-enabled proposal-apply-enabled)
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
        (when (and (eq status 'failed) error-text)
          (insert (format "Error: %s\n" error-text)))
        (insert (format "Heading: %s\n" heading))
        (insert (format "Task/Preset: %s%s%s\n"
                        task
                        (if (and (not (string-empty-p task))
                                 (not (string-empty-p preset)))
                            " / "
                          "")
                        preset))
        (insert (format "Selected candidate: %s\n" selected-id))
        (insert (format "Selected proposal: %s\n\n" selected-proposal-id))
        (insert "Keys:\n")
        (insert (propertize "  s stop run" 'face (funcall key-face stop-enabled)) "\n")
        (insert (propertize "  g rerun" 'face (funcall key-face rerun-enabled)) "\n")
        (insert (propertize "  t adjust task/instruction" 'face (funcall key-face adjust-enabled)) "\n")
        (insert (propertize "  v view DAG" 'face (funcall key-face dag-enabled)) "\n")
        (insert (propertize "  c select candidate (minibuffer)" 'face (funcall key-face candidate-enabled)) "\n")
        (insert (propertize "  a apply selected candidate" 'face (funcall key-face apply-enabled)) "\n")
        (insert (propertize "  d discard selected candidate" 'face (funcall key-face discard-enabled)) "\n")
        (insert (propertize "  x extract pattern proposal (manual)" 'face (funcall key-face extract-enabled)) "\n")
        (insert (propertize "  p select proposal (minibuffer)" 'face (funcall key-face proposal-enabled)) "\n")
        (insert (propertize "  v preview selected proposal" 'face (funcall key-face preview-enabled)) "\n")
        (insert (propertize "  y approve selected proposal" 'face (funcall key-face approve-enabled)) "\n")
        (insert (propertize "  n reject selected proposal" 'face (funcall key-face reject-enabled)) "\n")
        (insert (propertize "  m apply selected proposal" 'face (funcall key-face proposal-apply-enabled)) "\n")
        (insert (propertize "  M apply proposal to target skill file (confirm)" 'face (funcall key-face proposal-file-apply-enabled)) "\n")
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
        (insert "\n")
        (insert (format "Proposals (%d):\n" (length proposals)))
        (if (null proposals)
            (insert "  (none)\n")
          (let ((idx 0))
            (dolist (proposal proposals)
              (let* ((proposal-id (or (plist-get proposal :proposal-id) ""))
                     (status* (or (plist-get proposal :status) "proposed"))
                     (status-mark (pcase status*
                                    ("approved" "Y")
                                    ("rejected" "N")
                                    ("applied" "M")
                                    (_ "P")))
                     (selected-mark (if (equal proposal-id selected-proposal-id) "*" " "))
                     (source-id (or (plist-get proposal :source-candidate-id) "")))
                (insert (format " %s%02d [%s] %s (%s)\n"
                                selected-mark
                                (1+ idx)
                                status-mark
                                proposal-id
                                source-id)))
              (setq idx (1+ idx)))))
        (goto-char (point-min))))))

(defun org-ai-skills--ui-set-status (status progress)
  "Update STATUS and PROGRESS in UI state."
  (org-ai-skills--ui-run-set :status status)
  (org-ai-skills--ui-run-set :progress progress)
  (unless (eq status 'failed)
    (org-ai-skills--ui-run-set :error-detail nil))
  (org-ai-skills-ui-refresh-control-buffer))

(defun org-ai-skills--ui-set-failure (progress error-detail)
  "Set failed status PROGRESS with ERROR-DETAIL for control panel."
  (org-ai-skills--ui-run-set :error-detail
                             (if (and (stringp error-detail)
                                      (not (string-empty-p error-detail)))
                                 (string-trim error-detail)
                               nil))
  (org-ai-skills--ui-set-status 'failed progress))

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
  (setq org-ai-skills--ui-run-state (plist-put run-state :error-detail nil))
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
    (let ((rerun-fn (org-ai-skills--ui-run-get :rerun-fn))
          (source-buffer (org-ai-skills--ui-source-buffer)))
      (unless (functionp rerun-fn)
        (org-ai-skills--signal-org-context-error "No rerun action available"))
      (unless (buffer-live-p source-buffer)
        (org-ai-skills--signal-org-context-error
         "No source Org buffer is available for rerun"))
      (org-ai-skills--ui-set-status 'running "rerun-dispatched")
      (org-ai-skills--ui-set-overlay 'running)
      (message "org-ai-skills: rerun dispatched")
      (with-current-buffer source-buffer
        (funcall rerun-fn)))))

(defun org-ai-skills-ui-adjust-task-or-instruction ()
  "Adjust planner task or rewrite instruction, then rerun."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: adjust unavailable while running")
    (let ((run-type (org-ai-skills--ui-run-get :run-type))
          (source-buffer (org-ai-skills--ui-source-buffer)))
      (unless (buffer-live-p source-buffer)
        (org-ai-skills--signal-org-context-error
         "No source Org buffer is available for adjustment"))
      (pcase run-type
        ('planner
         (let* ((current-task (or (org-ai-skills--ui-run-get :task) ""))
                (task (read-string "Planner task: " current-task)))
           (org-ai-skills--ui-run-set
            :rerun-fn
            (lambda ()
              (interactive)
              (with-current-buffer source-buffer
                (let ((target (org-ai-skills--ui-current-target)))
                  (org-ai-skills-plan-run target task t)))))
           (with-current-buffer source-buffer
             (let ((target (org-ai-skills--ui-current-target)))
               (org-ai-skills-plan-run target task t)))))
        ('rewrite
         (let* ((skill (org-ai-skills--ui-run-get :skill))
                (constraints (org-ai-skills--ui-run-get :rewrite-constraints))
                (current-instruction (or (org-ai-skills--ui-run-get :instruction) ""))
                (instruction (read-string "Rewrite instruction: " current-instruction)))
           (org-ai-skills--ui-run-set :instruction instruction)
           (org-ai-skills--ui-run-set
            :rerun-fn
            (lambda ()
              (interactive)
              (with-current-buffer source-buffer
                (let ((target (org-ai-skills--ui-current-target)))
                  (org-ai-skills-org-rewrite-subtree
                   target skill instruction t constraints)))))
           (with-current-buffer source-buffer
             (let ((target (org-ai-skills--ui-current-target)))
               (org-ai-skills-org-rewrite-subtree
                target skill instruction t constraints)))))
        (_
         (org-ai-skills--signal-org-context-error "Unsupported run type"))))))

(defun org-ai-skills-ui-select-candidate ()
  "Select one candidate in minibuffer and cache it in UI state."
  (interactive)
  (let* ((slot-key (org-ai-skills--ui-run-get :slot-key))
         (candidate nil))
    (unless (and (stringp slot-key)
                 (not (string-empty-p slot-key)))
      (org-ai-skills--signal-version-store-error
       "No candidate slot key in current run; generate or select a valid run target first"))
    (setq candidate (org-ai-skills--read-slot-candidate slot-key nil))
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
           (source-buffer (org-ai-skills--ui-source-buffer)))
      (unless candidate
        (org-ai-skills--signal-version-store-error "No selected candidate"))
      (unless (buffer-live-p source-buffer)
        (org-ai-skills--signal-org-context-error
         "No source Org buffer is available for apply"))
      (with-current-buffer source-buffer
        (let ((target (org-ai-skills--ui-current-target)))
        (unless target
          (org-ai-skills--signal-org-context-error "No apply target available"))
        (org-ai-skills-org-apply-candidate-to-subtree
         target
           candidate)))
      (org-ai-skills--ui-clear-overlay)
      (org-ai-skills--ui-set-status 'applied "applied"))))

(defun org-ai-skills--ui-source-buffer ()
  "Return source buffer for current UI run state, or nil when unavailable."
  (let* ((source-buffer (org-ai-skills--ui-run-get :source-buffer))
         (target (org-ai-skills--ui-current-target))
         (begin (or (plist-get target :begin)
                    (org-ai-skills--ui-run-get :begin)))
         (end (or (plist-get target :end)
                  (org-ai-skills--ui-run-get :end))))
    (cond
     ((buffer-live-p source-buffer) source-buffer)
     ((and (markerp begin)
           (buffer-live-p (marker-buffer begin)))
      (marker-buffer begin))
     ((and (markerp end)
           (buffer-live-p (marker-buffer end)))
      (marker-buffer end))
     (t nil))))

(defun org-ai-skills--ui-current-target ()
  "Return current UI target, reconstructing from runtime state when missing."
  (let ((target (org-ai-skills--ui-run-get :target)))
    (if (consp target)
        target
      (let ((begin (org-ai-skills--ui-run-get :begin))
            (end (org-ai-skills--ui-run-get :end))
            (context-mode (org-ai-skills--ui-effective-context-mode))
            (heading (org-ai-skills--ui-run-get :heading)))
        (when (and begin end)
          (list :begin begin
                :end end
                :context-mode context-mode
                :heading heading))))))

(defun org-ai-skills--ui-effective-context-mode ()
  "Return effective context mode inferred from UI run state."
  (let ((context-mode (org-ai-skills--ui-run-get :context-mode))
        (target (org-ai-skills--ui-run-get :target))
        (slot-id (org-ai-skills--ui-run-get :slot-id))
        (begin (org-ai-skills--ui-run-get :begin))
        (end (org-ai-skills--ui-run-get :end)))
    (cond
     ((memq context-mode '(buffer current upper-level)) context-mode)
     ((and (consp target) (memq (plist-get target :context-mode)
                                '(buffer current upper-level)))
      (plist-get target :context-mode))
     ((equal slot-id "buffer-root") 'buffer)
     ((and (integer-or-marker-p begin)
           (integer-or-marker-p end)
           (= (if (markerp begin) (marker-position begin) begin) (point-min))
           (= (if (markerp end) (marker-position end) end) (point-max)))
      'buffer)
     (t 'current))))

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

(defun org-ai-skills--find-heading-by-id (slot-id)
  "Return heading position for SLOT-ID in current Org buffer, or nil."
  (when (and (derived-mode-p 'org-mode)
             (stringp slot-id)
             (not (string-empty-p slot-id)))
    (save-excursion
      (goto-char (point-min))
      (let ((regexp (format "^[ \t]*:ID:[ \t]*%s[ \t]*$"
                            (regexp-quote slot-id)))
            (found nil))
        (while (and (not found) (re-search-forward regexp nil t))
          (condition-case nil
              (progn
                (org-back-to-heading t)
                (setq found (point)))
            (error nil)))
        found))))

(defun org-ai-skills--resolve-subtree-from-slot (slot source-buffer)
  "Resolve latest subtree target from SLOT in SOURCE-BUFFER.
Prefer slot-id based lookup, then fall back to marker range in SLOT."
  (when (buffer-live-p source-buffer)
    (with-current-buffer source-buffer
      (let* ((context-mode (or (plist-get slot :context-mode) 'current))
             (slot-id (plist-get slot :slot-id))
             (heading-pos (and (not (eq context-mode 'buffer))
                               (org-ai-skills--find-heading-by-id slot-id))))
        (cond
         ((eq context-mode 'buffer)
          (append (org-ai-skills--buffer-scope-target)
                  (list :slot-id slot-id
                        :slot-file (plist-get slot :slot-file)
                        :slot-key (plist-get slot :slot-key))))
         (heading-pos
          (goto-char heading-pos)
          (append (org-ai-skills--subtree-at-heading-point)
                  (list :context-mode context-mode
                        :levels-up (or (plist-get slot :levels-up) 0)
                        :path (mapconcat #'identity (org-ai-skills--heading-path-at-point) "/")
                        :slot-id slot-id
                        :slot-file (plist-get slot :slot-file)
                        :slot-key (plist-get slot :slot-key))))
         (t
          (let ((begin (plist-get slot :begin))
                (end (plist-get slot :end)))
            (when (and (markerp begin) (marker-buffer begin)
                       (markerp end) (marker-buffer end))
              (list :begin begin
                    :end end
                    :context-mode context-mode
                    :levels-up (or (plist-get slot :levels-up) 0)
                    :heading (or (plist-get slot :heading) "")
                    :slot-id slot-id
                    :slot-file (plist-get slot :slot-file)
                    :slot-key (plist-get slot :slot-key))))))))))

(defun org-ai-skills--ensure-subtree-slot-id (subtree)
  "Ensure SUBTREE has stable slot id; write back Org =:ID:= when possible."
  (let* ((begin-raw (plist-get subtree :begin))
         (buffer (cond
                  ((and (markerp begin-raw) (marker-buffer begin-raw))
                   (marker-buffer begin-raw))
                  ((and (bufferp (plist-get subtree :source-buffer))
                        (buffer-live-p (plist-get subtree :source-buffer)))
                   (plist-get subtree :source-buffer))
                  (t (current-buffer))))
         (begin (org-ai-skills--subtree-begin-position subtree))
         (context-mode (plist-get subtree :context-mode))
         (slot-id (plist-get subtree :slot-id)))
    (unless (stringp slot-id)
      (when (and begin
                 (not (eq context-mode 'buffer)))
        (with-current-buffer buffer
          (when (derived-mode-p 'org-mode)
            (save-excursion
              (goto-char begin)
              (unless (org-at-heading-p)
                (org-back-to-heading t))
              (setq slot-id (org-entry-get (point) "ID"))
              (unless (stringp slot-id)
                (setq slot-id (org-id-new))
                (org-entry-put (point) "ID" slot-id))))))
      (when (and (not (stringp slot-id))
                 (eq context-mode 'buffer))
        (setq slot-id "buffer-root"))
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
  (let ((slot-key (plist-get candidate :slot-key))
        (candidate-id (plist-get candidate :candidate-id)))
    (org-ai-skills-org-apply-rewrite-result subtree (plist-get candidate :output-text))
    (if (and (stringp slot-key)
             (not (string-empty-p slot-key))
             (stringp candidate-id)
             (not (string-empty-p candidate-id)))
        (org-ai-skills--update-candidate-status
         slot-key
         candidate-id
         "applied")
      (message "org-ai-skills: apply succeeded but candidate status not persisted (missing slot metadata)")))
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
           :end (plist-get slot :end)
           :context-mode (plist-get slot :context-mode))
     candidate)))

(defun org-ai-skills--core-provider-timestamp ()
  "Return current timestamp string for core provider result metadata."
  (format-time-string "%Y-%m-%dT%H:%M:%S%z"))

(defun org-ai-skills--core-provider-result (command-type cwd ok &rest props)
  "Build normalized core provider payload.
COMMAND-TYPE identifies the command, CWD is command context, OK is boolean, and PROPS
contains additional plist keys."
  (append (list :ok ok
                :command-type command-type
                :cwd cwd
                :timestamp (org-ai-skills--core-provider-timestamp))
          props))

(defun org-ai-skills--core-provider-normalize-max-count (n fallback)
  "Coerce N to positive integer, defaulting to FALLBACK."
  (let ((value (cond
                ((integerp n) n)
                ((and (stringp n) (string-match-p "^[0-9]+$" n))
                 (string-to-number n))
                (t fallback))))
    (max 1 value)))

(defun org-ai-skills--core-provider-allowed-command-p (command-type)
  "Return non-nil when COMMAND-TYPE is allowed."
  (memq command-type org-ai-skills-core-provider-allowed-commands))

(defun org-ai-skills--core-provider-effective-allowed-paths ()
  "Return effective allowed roots, including request-scoped working directory."
  (let ((paths (copy-sequence org-ai-skills-core-provider-allowed-paths)))
    (when (and (stringp org-ai-skills--core-provider-context-directory)
               (file-directory-p org-ai-skills--core-provider-context-directory))
      (push org-ai-skills--core-provider-context-directory paths))
    (cl-remove-duplicates
     (mapcar #'expand-file-name
             (seq-filter (lambda (path)
                           (and (stringp path)
                                (not (string-empty-p path))))
                         paths))
     :test #'string=)))

(defun org-ai-skills--core-provider-path-in-allowed-root-p (path)
  "Return non-nil when PATH is within `org-ai-skills-core-provider-allowed-paths'."
  (let ((abs (expand-file-name path)))
    (seq-some
     (lambda (root)
       (let ((root-dir (file-name-as-directory (expand-file-name root))))
         (or (string= abs (directory-file-name root-dir))
             (file-in-directory-p abs root-dir))))
     (org-ai-skills--core-provider-effective-allowed-paths))))

(defun org-ai-skills--core-provider-check-access (command-type path)
  "Return normalized failure payload when COMMAND-TYPE or PATH is disallowed.
Return nil when both checks pass."
  (let ((abs (expand-file-name path)))
    (cond
     ((not (org-ai-skills--core-provider-allowed-command-p command-type))
      (org-ai-skills--core-provider-result
       command-type abs nil
       :error-kind "command-not-allowed"
       :error-message (format "Command type is not allowed: %s" command-type)))
     ((not (org-ai-skills--core-provider-path-in-allowed-root-p abs))
      (org-ai-skills--core-provider-result
       command-type abs nil
       :error-kind "path-not-allowed"
       :error-message (format "Path is outside allowed roots: %s" abs)
       :allowed-paths (org-ai-skills--core-provider-effective-allowed-paths)))
     (t nil))))

(defun org-ai-skills--core-provider-run-process (program args cwd)
  "Run PROGRAM with ARGS in CWD and return normalized process metadata plist."
  (let ((stdout-buffer (generate-new-buffer " *org-ai-skills-core-provider-stdout*"))
        (stderr-file (make-temp-file "org-ai-skills-core-provider-stderr-")))
    (unwind-protect
        (let ((default-directory cwd))
          (condition-case err
              (let ((exit-code (apply #'process-file
                                      program
                                      nil
                                      (list stdout-buffer stderr-file)
                                      nil
                                      args)))
                (list :ok (zerop exit-code)
                      :exit-code exit-code
                      :stdout (with-current-buffer stdout-buffer
                                (buffer-string))
                      :stderr (with-temp-buffer
                                (insert-file-contents stderr-file)
                                (buffer-string))))
            (error
             (list :ok nil
                   :exit-code -1
                   :stdout ""
                   :stderr (error-message-string err)))))
      (kill-buffer stdout-buffer)
      (ignore-errors (delete-file stderr-file)))))

(defun org-ai-skills-core-provider-register-command (command-type function-symbol)
  "Register FUNCTION-SYMBOL as provider handler for COMMAND-TYPE."
  (setq org-ai-skills-core-provider-command-registry
        (assq-delete-all command-type org-ai-skills-core-provider-command-registry))
  (push (cons command-type function-symbol) org-ai-skills-core-provider-command-registry))

(defun org-ai-skills-core-provider-dispatch (command-type &rest args)
  "Dispatch COMMAND-TYPE with ARGS through provider registry."
  (let ((handler (cdr (assoc command-type org-ai-skills-core-provider-command-registry))))
    (unless (and handler (fboundp handler))
      (org-ai-skills--signal-function-call-error
       (format "No registered core provider command for type: %s" command-type)))
    (apply handler args)))

(defun org-ai-skills-core-provider-read-file (file-path &optional max-chars)
  "Read FILE-PATH under allowed roots and return normalized payload."
  (unless (and (stringp file-path) (not (string-empty-p file-path)))
    (org-ai-skills--signal-function-call-error
     "file_path is required for org-ai-skills-core-provider-read-file"))
  (let* ((abs (expand-file-name file-path))
         (guard (org-ai-skills--core-provider-check-access 'file-read abs)))
    (if guard
        guard
      (if (not (file-readable-p abs))
          (org-ai-skills--core-provider-result
           'file-read (file-name-directory abs) nil
           :target-path abs
           :error-kind "file-not-readable"
           :error-message (format "Source file is not readable: %s" abs))
        (let ((content (with-temp-buffer
                         (insert-file-contents abs)
                         (buffer-string))))
          (org-ai-skills--core-provider-result
           'file-read (file-name-directory abs) t
           :target-path abs
           :content (org-ai-skills--slice-string-by-chars content max-chars)))))))

(defun org-ai-skills-core-provider-list-files (&optional directory max-results)
  "List files under DIRECTORY with optional MAX-RESULTS."
  (let* ((dir (expand-file-name (or directory
                                    org-ai-skills--core-provider-context-directory
                                    default-directory)))
         (guard (org-ai-skills--core-provider-check-access 'file-list dir)))
    (if guard
        guard
      (if (not (file-directory-p dir))
          (org-ai-skills--core-provider-result
           'file-list dir nil
           :error-kind "directory-not-found"
           :error-message (format "Directory does not exist: %s" dir))
        (let* ((entries (directory-files dir nil directory-files-no-dot-files-regexp))
               (limit (org-ai-skills--core-provider-normalize-max-count max-results 200))
               (normalized
                (mapcar (lambda (name)
                          (let ((abs (expand-file-name name dir)))
                            (if (file-directory-p abs)
                                (concat name "/")
                              name)))
                        entries))
               (limited (seq-take normalized limit)))
          (org-ai-skills--core-provider-result
           'file-list dir t
           :entries limited
           :entry-count (length limited)
           :truncated (> (length normalized) limit)))))))

(defun org-ai-skills-core-provider-search-files (query &optional directory max-results)
  "Search QUERY in DIRECTORY and return normalized match payload."
  (unless (and (stringp query) (not (string-empty-p query)))
    (org-ai-skills--signal-function-call-error
     "query is required for org-ai-skills-core-provider-search-files"))
  (let* ((dir (expand-file-name (or directory
                                    org-ai-skills--core-provider-context-directory
                                    default-directory)))
         (guard (org-ai-skills--core-provider-check-access 'file-search dir)))
    (if guard
        guard
      (if (not (file-directory-p dir))
          (org-ai-skills--core-provider-result
           'file-search dir nil
           :error-kind "directory-not-found"
           :error-message (format "Directory does not exist: %s" dir))
        (let* ((limit (org-ai-skills--core-provider-normalize-max-count max-results 100))
               (rg (executable-find "rg"))
               (proc (if rg
                         (org-ai-skills--core-provider-run-process
                          rg
                          (list "--line-number" "--no-heading" "--color" "never" query)
                          dir)
                       (org-ai-skills--core-provider-run-process
                        "grep"
                        (list "-R" "-n" "-I" query ".")
                        dir)))
               (stdout (or (plist-get proc :stdout) ""))
               (lines (split-string stdout "\n" t))
               (matches (seq-take lines limit)))
          (org-ai-skills--core-provider-result
           'file-search dir (plist-get proc :ok)
           :query query
           :matches matches
           :match-count (length matches)
           :truncated (> (length lines) limit)
           :exit-code (plist-get proc :exit-code)
           :stdout stdout
           :stderr (plist-get proc :stderr)))))))

(defun org-ai-skills-core-provider-shell-exec (command &optional directory)
  "Execute shell COMMAND in DIRECTORY and return normalized payload."
  (unless (and (stringp command) (not (string-empty-p command)))
    (org-ai-skills--signal-function-call-error
     "command is required for org-ai-skills-core-provider-shell-exec"))
  (let* ((cwd (expand-file-name (or directory
                                    org-ai-skills--core-provider-context-directory
                                    default-directory)))
         (guard (org-ai-skills--core-provider-check-access 'shell-exec cwd)))
    (if guard
        guard
      (let ((proc (org-ai-skills--core-provider-run-process
                   shell-file-name
                   (list shell-command-switch command)
                   cwd)))
        (org-ai-skills--core-provider-result
         'shell-exec cwd (plist-get proc :ok)
         :command command
         :exit-code (plist-get proc :exit-code)
         :stdout (plist-get proc :stdout)
         :stderr (plist-get proc :stderr))))))

(defun org-ai-skills-core-provider-python-exec (code &optional directory)
  "Execute Python CODE in DIRECTORY and return normalized payload."
  (unless (and (stringp code) (not (string-empty-p code)))
    (org-ai-skills--signal-function-call-error
     "code is required for org-ai-skills-core-provider-python-exec"))
  (let* ((cwd (expand-file-name (or directory
                                    org-ai-skills--core-provider-context-directory
                                    default-directory)))
         (guard (org-ai-skills--core-provider-check-access 'python-exec cwd)))
    (if guard
        guard
      (let ((python (or (executable-find "python3")
                        (executable-find "python"))))
        (if (not python)
            (org-ai-skills--core-provider-result
             'python-exec cwd nil
             :error-kind "python-not-found"
             :error-message "python3/python executable not found")
          (let ((proc (org-ai-skills--core-provider-run-process python (list "-c" code) cwd)))
            (org-ai-skills--core-provider-result
             'python-exec cwd (plist-get proc :ok)
             :code code
             :python python
             :exit-code (plist-get proc :exit-code)
             :stdout (plist-get proc :stdout)
             :stderr (plist-get proc :stderr))))))))

(defun org-ai-skills-core-provider-org-babel-exec (language body &optional directory)
  "Execute Org Babel src block using LANGUAGE and BODY in DIRECTORY."
  (unless (and (stringp language) (not (string-empty-p language)))
    (org-ai-skills--signal-function-call-error
     "language is required for org-ai-skills-core-provider-org-babel-exec"))
  (unless (stringp body)
    (org-ai-skills--signal-function-call-error
     "body must be a string for org-ai-skills-core-provider-org-babel-exec"))
  (let* ((cwd (expand-file-name (or directory
                                    org-ai-skills--core-provider-context-directory
                                    default-directory)))
         (guard (org-ai-skills--core-provider-check-access 'org-babel-exec cwd)))
    (if guard
        guard
      (let ((default-directory cwd))
        (condition-case err
            (let ((result
                   (with-temp-buffer
                     (org-mode)
                     (insert (format "#+begin_src %s\n%s\n#+end_src\n" language body))
                     (goto-char (point-min))
                     (re-search-forward "^#\\+begin_src" nil t)
                     (let ((org-confirm-babel-evaluate nil))
                       (org-babel-execute-src-block)))))
              (org-ai-skills--core-provider-result
               'org-babel-exec cwd t
               :language language
               :result (if (stringp result)
                           result
                         (format "%S" result))))
          (error
           (org-ai-skills--core-provider-result
            'org-babel-exec cwd nil
            :language language
            :error-kind "org-babel-execution-error"
            :error-message (error-message-string err))))))))

(defun org-ai-skills-core-provider-register-default-commands ()
  "Register phase-1 default core provider command handlers."
  (setq org-ai-skills-core-provider-command-registry nil)
  (org-ai-skills-core-provider-register-command 'file-read #'org-ai-skills-core-provider-read-file)
  (org-ai-skills-core-provider-register-command 'file-list #'org-ai-skills-core-provider-list-files)
  (org-ai-skills-core-provider-register-command 'file-search #'org-ai-skills-core-provider-search-files)
  (org-ai-skills-core-provider-register-command 'shell-exec #'org-ai-skills-core-provider-shell-exec)
  (org-ai-skills-core-provider-register-command 'python-exec #'org-ai-skills-core-provider-python-exec)
  (org-ai-skills-core-provider-register-command 'org-babel-exec #'org-ai-skills-core-provider-org-babel-exec)
  org-ai-skills-core-provider-command-registry)

(org-ai-skills-core-provider-register-default-commands)

(defun org-ai-skills--signal-proposal-store-error (message)
  "Signal proposal store error with MESSAGE."
  (signal 'org-ai-skills-proposal-store-error (list message)))

(defun org-ai-skills--ensure-proposal-store-dir ()
  "Ensure proposal artifact store directory exists."
  (condition-case err
      (progn
        (make-directory org-ai-skills-proposal-store-dir t)
        org-ai-skills-proposal-store-dir)
    (error
     (org-ai-skills--signal-proposal-store-error
      (format "Failed to prepare proposal store dir: %s" (error-message-string err))))))

(defun org-ai-skills--proposal-id ()
  "Return a unique proposal artifact id."
  (format "proposal-%s-%06x"
          (format-time-string "%Y%m%d%H%M%S%3N")
          (random #xFFFFFF)))

(defun org-ai-skills--proposal-store-file (proposal-id)
  "Return proposal store file path for PROPOSAL-ID."
  (expand-file-name
   (format "%s.json" proposal-id)
   (org-ai-skills--ensure-proposal-store-dir)))

(defun org-ai-skills--persist-proposal (proposal)
  "Persist one PROPOSAL artifact as JSON."
  (let* ((proposal-id (or (plist-get proposal :proposal-id)
                          (org-ai-skills--signal-proposal-store-error
                           "Proposal artifact missing proposal-id")))
         (file (org-ai-skills--proposal-store-file proposal-id)))
    (condition-case err
        (let ((coding-system-for-write 'utf-8-unix))
          (with-temp-buffer
            (insert (json-serialize proposal))
            (insert "\n")
            (write-region (point-min) (point-max) file nil 'silent))
          proposal)
      (error
       (org-ai-skills--signal-proposal-store-error
        (format "Failed to write proposal artifact: %s" (error-message-string err)))))))

(defun org-ai-skills--proposal-audit-file ()
  "Return proposal audit log file path."
  (expand-file-name
   "audit-log.jsonl"
   (org-ai-skills--ensure-proposal-store-dir)))

(defun org-ai-skills--append-proposal-audit-event (proposal-id action &optional note)
  "Append proposal audit event for PROPOSAL-ID ACTION and optional NOTE."
  (let ((file (org-ai-skills--proposal-audit-file))
        (entry (list :event-id (org-ai-skills--candidate-id)
                     :proposal-id proposal-id
                     :action action
                     :note (or note "")
                     :actor (or user-login-name "")
                     :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                     :run-id (or (org-ai-skills--ui-run-get :run-id) "")
                     :slot-key (or (org-ai-skills--ui-run-get :slot-key) ""))))
    (condition-case err
        (let ((coding-system-for-write 'utf-8-unix))
          (with-temp-buffer
            (insert (json-serialize entry))
            (insert "\n")
            (write-region (point-min) (point-max) file t 'silent)))
      (error
       (org-ai-skills--signal-proposal-store-error
        (format "Failed to append proposal audit event: %s"
                (error-message-string err)))))))

(defun org-ai-skills--load-proposal (proposal-id)
  "Load persisted proposal artifact by PROPOSAL-ID."
  (let ((file (org-ai-skills--proposal-store-file proposal-id)))
    (unless (file-exists-p file)
      (org-ai-skills--signal-proposal-store-error
       (format "Proposal not found: %s" proposal-id)))
    (condition-case err
        (let ((coding-system-for-read 'utf-8-unix))
          (json-parse-string
           (with-temp-buffer
             (insert-file-contents file)
             (buffer-string))
           :object-type 'plist
           :array-type 'list
           :null-object nil
           :false-object nil))
      (error
       (org-ai-skills--signal-proposal-store-error
        (format "Failed to read proposal artifact: %s" (error-message-string err)))))))

(defun org-ai-skills--proposal-sort-key (proposal)
  "Return sorting key for PROPOSAL."
  (or (plist-get proposal :created-at) ""))

(defun org-ai-skills--load-proposals (&optional slot-key)
  "Load persisted proposal artifacts, optionally filtered by SLOT-KEY."
  (let* ((dir (org-ai-skills--ensure-proposal-store-dir))
         (files (sort (file-expand-wildcards (expand-file-name "proposal-*.json" dir) t)
                      #'string<))
         (items nil))
    (dolist (file files)
      (condition-case err
          (let* ((coding-system-for-read 'utf-8-unix)
                 (proposal (json-parse-string
                            (with-temp-buffer
                              (insert-file-contents file)
                              (buffer-string))
                            :object-type 'plist
                            :array-type 'list
                            :null-object nil
                            :false-object nil)))
            (when (or (null slot-key)
                      (equal (plist-get proposal :source-slot-key) slot-key))
              (push proposal items)))
        (error
         (org-ai-skills--signal-proposal-store-error
          (format "Failed to read proposal artifact: %s" (error-message-string err))))))
    (sort items
          (lambda (a b)
            (string< (org-ai-skills--proposal-sort-key b)
                     (org-ai-skills--proposal-sort-key a))))))

(defun org-ai-skills--proposal-display (proposal)
  "Return minibuffer display string for PROPOSAL."
  (format "[%s] %s | %s | %s"
          (or (plist-get proposal :status) "proposed")
          (or (plist-get proposal :created-at) "")
          (or (plist-get proposal :proposal-id) "")
          (or (plist-get proposal :source-candidate-id) "")))

(defun org-ai-skills--read-proposal (&optional slot-key)
  "Read one proposal, filtered by SLOT-KEY when non-nil."
  (let* ((items (org-ai-skills--load-proposals slot-key))
         (pairs (mapcar (lambda (item)
                          (cons (org-ai-skills--proposal-display item) item))
                        items))
         (_ (unless pairs
              (org-ai-skills--signal-proposal-store-error
               "No proposals available for current slot")))
         (choice (completing-read "Proposal: "
                                  (mapcar #'car pairs)
                                  nil t nil
                                  'org-ai-skills--proposal-selection-history)))
    (cdr (assoc choice pairs))))

(defun org-ai-skills--proposal-transition-allowed-p (current-status next-status)
  "Return non-nil when CURRENT-STATUS can transition to NEXT-STATUS."
  (member next-status
          (pcase current-status
            ("proposed" '("approved" "rejected"))
            ("approved" '("applied" "rejected"))
            ("rejected" '("approved"))
            (_ nil))))

(defun org-ai-skills--proposal-skill-path-p (path)
  "Return non-nil when PATH is under `org-ai-skills-skill-dir'."
  (and (stringp path)
       (file-in-directory-p (expand-file-name path)
                            (expand-file-name org-ai-skills-skill-dir))))

(defun org-ai-skills--assert-proposal-safe-apply (proposal)
  "Signal when PROPOSAL implies runtime mutation under skill spec directory."
  (let* ((target-skill-file (plist-get proposal :target-skill-file))
         (raw-files (plist-get proposal :proposed-files))
         (files (cond
                 ((vectorp raw-files) (append raw-files nil))
                 ((listp raw-files) raw-files)
                 (t nil)))
         (unsafe-files (seq-filter #'org-ai-skills--proposal-skill-path-p files)))
    (when (or (org-ai-skills--proposal-skill-path-p target-skill-file)
              (and (listp unsafe-files) (> (length unsafe-files) 0)))
      (signal 'org-ai-skills-safety-error
              (list "Runtime apply cannot mutate files under skills/; proposal must remain artifact-only")))))

(defun org-ai-skills--proposal-build-skill-file-patch-block (proposal)
  "Build org text block appended to target skill file for PROPOSAL."
  (let* ((proposal-id (or (plist-get proposal :proposal-id) ""))
         (target-skill-id (or (plist-get proposal :target-skill-id) ""))
         (source-candidate-id (or (plist-get proposal :source-candidate-id) ""))
         (rationale (or (plist-get proposal :rationale) ""))
         (patterns (plist-get proposal :patterns))
         (steps (org-ai-skills--proposal-seq->list (plist-get patterns :steps)))
         (checks (org-ai-skills--proposal-seq->list (plist-get patterns :checks)))
         (failure (org-ai-skills--proposal-seq->list (plist-get patterns :failure-handling)))
         (heuristics (org-ai-skills--proposal-seq->list (plist-get patterns :heuristics))))
    (with-temp-buffer
      (insert "\n** Extracted Pattern Proposal: " proposal-id "\n")
      (insert ":PROPERTIES:\n")
      (insert ":TARGET_SKILL_ID: " target-skill-id "\n")
      (insert ":SOURCE_PROPOSAL_ID: " proposal-id "\n")
      (insert ":SOURCE_CANDIDATE_ID: " source-candidate-id "\n")
      (insert ":CAPTURED_AT: " (format-time-string "%Y-%m-%dT%H:%M:%S%z") "\n")
      (insert ":END:\n\n")
      (insert "Rationale:\n")
      (insert "- " rationale "\n\n")
      (insert "Steps:\n")
      (if steps
          (dolist (item steps) (insert "- " item "\n"))
        (insert "- (none)\n"))
      (insert "\nChecks:\n")
      (if checks
          (dolist (item checks) (insert "- " item "\n"))
        (insert "- (none)\n"))
      (insert "\nFailure handling:\n")
      (if failure
          (dolist (item failure) (insert "- " item "\n"))
        (insert "- (none)\n"))
      (insert "\nHeuristics:\n")
      (if heuristics
          (dolist (item heuristics) (insert "- " item "\n"))
        (insert "- (none)\n"))
      (buffer-string))))

(defun org-ai-skills--append-proposal-to-target-skill-file (proposal)
  "Append PROPOSAL-derived patch block to its bound target skill file."
  (let* ((proposal-id (or (plist-get proposal :proposal-id) ""))
         (target-file (or (plist-get proposal :target-skill-file) "")))
    (unless (and (stringp target-file) (not (string-empty-p target-file)))
      (org-ai-skills--signal-proposal-store-error
       "Proposal does not specify target skill file"))
    (unless (org-ai-skills--proposal-skill-path-p target-file)
      (org-ai-skills--signal-proposal-store-error
       (format "Target skill file is outside skills directory: %s" target-file)))
    (unless (file-exists-p target-file)
      (org-ai-skills--signal-proposal-store-error
       (format "Target skill file does not exist: %s" target-file)))
    (let ((marker (format ":SOURCE_PROPOSAL_ID: %s" proposal-id)))
      (with-temp-buffer
        (insert-file-contents target-file)
        (goto-char (point-min))
        (when (re-search-forward (regexp-quote marker) nil t)
          (org-ai-skills--signal-proposal-store-error
           (format "Proposal already applied to target skill file: %s" proposal-id)))))
    (let ((block (org-ai-skills--proposal-build-skill-file-patch-block proposal)))
      (condition-case err
          (let ((coding-system-for-write 'utf-8-unix))
            (with-temp-buffer
              (insert-file-contents target-file)
              (goto-char (point-max))
              (unless (bolp) (insert "\n"))
              (insert block)
              (write-region (point-min) (point-max) target-file nil 'silent)))
        (error
         (org-ai-skills--signal-proposal-store-error
          (format "Failed to apply proposal to target skill file: %s"
                  (error-message-string err))))))))

(defun org-ai-skills--proposal-transition (proposal next-status &optional note apply-mode)
  "Transition PROPOSAL to NEXT-STATUS with NOTE and APPLY-MODE when applied."
  (let* ((proposal-id (or (plist-get proposal :proposal-id)
                          (org-ai-skills--signal-proposal-store-error
                           "Proposal artifact missing proposal-id")))
         (current-status (or (plist-get proposal :status) "proposed")))
    (unless (org-ai-skills--proposal-transition-allowed-p current-status next-status)
      (org-ai-skills--signal-proposal-store-error
       (format "Invalid proposal transition: %s -> %s" current-status next-status)))
    (when (and (equal next-status "applied")
               (or (null apply-mode) (equal apply-mode "artifact-only")))
      (org-ai-skills--assert-proposal-safe-apply proposal))
    (let* ((updated (copy-sequence proposal))
           (timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
      (setq updated (plist-put updated :status next-status))
      (pcase next-status
        ((or "approved" "rejected")
         (setq updated
               (plist-put updated :review
                          (list :decision next-status
                                :reviewed-at timestamp
                                :reviewed-by (or user-login-name "")
                                :note (or note "")))))
        ("applied"
         (setq updated
               (plist-put updated :application
                          (list :mode (or apply-mode "artifact-only")
                                :applied-at timestamp
                                :applied-by (or user-login-name "")
                                :note (or note ""))))))
      (org-ai-skills--persist-proposal updated)
      (org-ai-skills--append-proposal-audit-event proposal-id next-status note)
      updated)))

(defun org-ai-skills--ui-effective-proposal ()
  "Return selected proposal, or latest slot proposal when none selected."
  (or (org-ai-skills--ui-run-get :selected-proposal)
      (car (org-ai-skills--load-proposals (org-ai-skills--ui-run-get :slot-key)))))

(defun org-ai-skills--proposal-seq->list (value)
  "Return VALUE as a list when it is a sequence, else nil."
  (cond
   ((vectorp value) (append value nil))
   ((listp value) value)
   (t nil)))

(defun org-ai-skills--ui-proposal-preview-buffer ()
  "Return proposal preview buffer."
  (get-buffer-create org-ai-skills-proposal-preview-buffer-name))

(defun org-ai-skills--insert-proposal-pattern-section (title items)
  "Insert proposal pattern section TITLE for sequence ITEMS."
  (insert (format "%s:\n" title))
  (if (null items)
      (insert "  (none)\n")
    (dolist (item items)
      (insert (format "  - %s\n" item)))))

(defun org-ai-skills--normalize-pattern-line (line)
  "Normalize extracted LINE for proposal pattern artifacts."
  (string-trim
   (replace-regexp-in-string "^[ \t]*[-+*0-9.()]+[ \t]*" "" (or line ""))))

(defun org-ai-skills--collect-pattern-lines (text regexp &optional limit)
  "Collect normalized lines from TEXT matching REGEXP up to LIMIT."
  (let ((max-lines (or limit 5))
        (results nil))
    (dolist (raw-line (split-string (or text "") "\n"))
      (let ((line (string-trim raw-line)))
        (when (and (not (string-empty-p line))
                   (string-match-p regexp line)
                   (< (length results) max-lines))
          (push (org-ai-skills--normalize-pattern-line line) results))))
    (nreverse results)))

(defun org-ai-skills--extract-pattern-groups (text)
  "Extract reusable pattern groups from candidate TEXT."
  (list
   :steps (vconcat (org-ai-skills--collect-pattern-lines text "^[ \t]*\\(?:[-+*]\\|[0-9]+[.)]\\)" 6))
   :checks (vconcat (org-ai-skills--collect-pattern-lines text
                                                          "\\b\\(check\\|verify\\|validate\\|assert\\|ensure\\|must\\)\\b"
                                                          5))
   :failure-handling (vconcat (org-ai-skills--collect-pattern-lines text
                                                                    "\\b\\(fail\\|error\\|retry\\|fallback\\|recover\\|rollback\\)\\b"
                                                                    5))
   :heuristics (vconcat (org-ai-skills--collect-pattern-lines text
                                                              "\\b\\(prefer\\|avoid\\|if\\b.*\\bthen\\|when\\|unless\\)\\b"
                                                              5))))

(defun org-ai-skills--proposal-confidence (patterns)
  "Return extraction confidence float from PATTERNS."
  (let* ((groups (list (plist-get patterns :steps)
                       (plist-get patterns :checks)
                       (plist-get patterns :failure-handling)
                       (plist-get patterns :heuristics)))
         (non-empty (seq-count (lambda (group) (and (sequencep group) (> (length group) 0)))
                               groups)))
    (/ non-empty 4.0)))

(defun org-ai-skills--proposal-risk-level (patterns)
  "Return risk level string inferred from extracted PATTERNS."
  (cond
   ((and (= (length (plist-get patterns :steps)) 0)
         (= (length (plist-get patterns :checks)) 0)
         (= (length (plist-get patterns :failure-handling)) 0)
         (= (length (plist-get patterns :heuristics)) 0))
    "high")
   ((and (> (length (plist-get patterns :checks)) 0)
         (> (length (plist-get patterns :failure-handling)) 0))
    "low")
   (t "medium")))

(defun org-ai-skills--extract-pattern-proposal-from-candidate (candidate run-state)
  "Build and persist one pattern proposal artifact from CANDIDATE and RUN-STATE."
  (let* ((proposal-id (org-ai-skills--proposal-id))
         (output-text (or (plist-get candidate :output-text) ""))
         (target-skill (org-ai-skills--resolve-target-skill-from-ui-run-state run-state))
         (target-skill-id (and (consp target-skill) (plist-get target-skill :skill-id)))
         (target-skill-file (and (consp target-skill) (plist-get target-skill :skill-file)))
         (_ (unless (stringp target-skill-id)
              (org-ai-skills--signal-proposal-store-error
               "Cannot extract proposal: target skill is missing in previous run context")))
         (patterns (org-ai-skills--extract-pattern-groups output-text))
         (confidence (org-ai-skills--proposal-confidence patterns))
         (risk (org-ai-skills--proposal-risk-level patterns))
         (rationale
                  (format "Manual extraction from candidate %s (%s groups, confidence %.2f)."
                  (or (plist-get candidate :candidate-id) "unknown")
                  (seq-count (lambda (group) (and (sequencep group) (> (length group) 0)))
                             (list (plist-get patterns :steps)
                                   (plist-get patterns :checks)
                                   (plist-get patterns :failure-handling)
                                   (plist-get patterns :heuristics)))
                  confidence))
         (proposal
          (list :proposal-id proposal-id
                :created-at (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                :type "skill-pattern-proposal"
                :status "proposed"
                :extraction-mode "manual-control-panel"
                :source-run-id (or (plist-get run-state :run-id) "")
                :source-run-type (if (plist-get run-state :run-type)
                                     (format "%s" (plist-get run-state :run-type))
                                   "")
                :source-task (or (plist-get run-state :task) "")
                :source-slot-key (or (plist-get candidate :slot-key) "")
                :source-slot-id (or (plist-get candidate :slot-id) "")
                :source-slot-file (or (plist-get candidate :slot-file) "")
                :source-slot-heading (or (plist-get candidate :slot-heading) "")
                :source-candidate-id (or (plist-get candidate :candidate-id) "")
                :source-candidate-created-at (or (plist-get candidate :created-at) "")
                :prompt-digest (or (plist-get candidate :prompt-digest) "")
                :target-skill-id target-skill-id
                :target-skill-file (or target-skill-file "")
                :target-skill-source (or (plist-get target-skill :source) "")
                :application-mode "artifact-only"
                :proposed-files []
                :patterns patterns
                :rationale rationale
                :confidence confidence
                :risk risk
                :review nil)))
    (org-ai-skills--persist-proposal proposal)))

(defun org-ai-skills--ui-effective-candidate-for-extraction ()
  "Return selected candidate, or latest slot candidate when none selected."
  (or (org-ai-skills--ui-run-get :selected-candidate)
      (let* ((slot-key (org-ai-skills--ui-run-get :slot-key))
             (items (and (stringp slot-key)
                         (org-ai-skills--load-slot-candidates slot-key))))
        (car items))))

(defun org-ai-skills-ui-extract-pattern-proposal ()
  "Extract reusable patterns manually and persist a proposal artifact."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: extract unavailable while running")
    (let ((candidate (org-ai-skills--ui-effective-candidate-for-extraction)))
      (unless candidate
        (org-ai-skills--signal-version-store-error
         "No candidate available for manual pattern extraction"))
      (let ((proposal (org-ai-skills--extract-pattern-proposal-from-candidate
                       candidate
                       org-ai-skills--ui-run-state)))
        (org-ai-skills--ui-run-set :selected-candidate candidate)
        (org-ai-skills--ui-run-set :selected-proposal proposal)
        (org-ai-skills--ui-clear-overlay)
        (org-ai-skills--ui-set-status 'ready "pattern-proposal-extracted")
        (message "org-ai-skills proposal extracted: %s"
                 (plist-get proposal :proposal-id))))))

(defun org-ai-skills-ui-select-proposal ()
  "Select one proposal in minibuffer and cache it in UI state."
  (interactive)
  (let* ((slot-key (org-ai-skills--ui-run-get :slot-key))
         (proposal (org-ai-skills--read-proposal slot-key)))
    (org-ai-skills--ui-run-set :selected-proposal proposal)
    (org-ai-skills--ui-set-status 'ready "proposal-selected")
    proposal))

(defun org-ai-skills-ui-approve-selected-proposal ()
  "Approve selected proposal from UI state."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: proposal approve unavailable while running")
    (let* ((proposal (or (org-ai-skills--ui-run-get :selected-proposal)
                         (org-ai-skills-ui-select-proposal)))
           (updated (org-ai-skills--proposal-transition proposal "approved")))
      (org-ai-skills--ui-run-set :selected-proposal updated)
      (org-ai-skills--ui-set-status 'ready "proposal-approved")
      (message "org-ai-skills proposal approved: %s"
               (plist-get updated :proposal-id)))))

(defun org-ai-skills-ui-reject-selected-proposal ()
  "Reject selected proposal from UI state."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: proposal reject unavailable while running")
    (let* ((proposal (or (org-ai-skills--ui-run-get :selected-proposal)
                         (org-ai-skills-ui-select-proposal)))
           (updated (org-ai-skills--proposal-transition proposal "rejected")))
      (org-ai-skills--ui-run-set :selected-proposal updated)
      (org-ai-skills--ui-set-status 'ready "proposal-rejected")
      (message "org-ai-skills proposal rejected: %s"
               (plist-get updated :proposal-id)))))

(defun org-ai-skills-ui-apply-selected-proposal ()
  "Apply selected approved proposal from UI state."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: proposal apply unavailable while running")
    (let* ((proposal (or (org-ai-skills--ui-run-get :selected-proposal)
                         (org-ai-skills-ui-select-proposal)))
           (updated (org-ai-skills--proposal-transition proposal "applied")))
      (org-ai-skills--ui-run-set :selected-proposal updated)
      (org-ai-skills--ui-set-status 'ready "proposal-applied")
      (message "org-ai-skills proposal applied (artifact-only): %s"
               (plist-get updated :proposal-id)))))

(defun org-ai-skills-ui-apply-selected-proposal-to-skill-file ()
  "Apply selected approved proposal to bound target skill file with confirmation."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: skill-file apply unavailable while running")
    (let* ((proposal (or (org-ai-skills--ui-run-get :selected-proposal)
                         (org-ai-skills-ui-select-proposal)))
           (proposal-id (or (plist-get proposal :proposal-id) ""))
           (target-file (or (plist-get proposal :target-skill-file) ""))
           (status* (or (plist-get proposal :status) "proposed")))
      (unless (equal status* "approved")
        (org-ai-skills--signal-proposal-store-error
         (format "Proposal must be approved before skill-file apply (current: %s)" status*)))
      (unless (yes-or-no-p
               (format "Apply proposal %s to skill file %s? "
                       proposal-id target-file))
        (org-ai-skills--signal-proposal-store-error "Skill-file apply canceled"))
      (org-ai-skills--append-proposal-to-target-skill-file proposal)
      (let ((updated (org-ai-skills--proposal-transition
                      proposal
                      "applied"
                      "applied-to-skill-file"
                      "skill-file-append")))
        (org-ai-skills--ui-run-set :selected-proposal updated)
        (org-ai-skills--ui-set-status 'ready "proposal-applied-skill-file")
        (message "org-ai-skills proposal applied to skill file: %s"
                 (plist-get updated :proposal-id))))))

(defun org-ai-skills-ui-preview-selected-proposal ()
  "Preview selected proposal details in a read-only buffer."
  (interactive)
  (if (eq (org-ai-skills--ui-run-get :status) 'running)
      (message "org-ai-skills: proposal preview unavailable while running")
    (let* ((proposal (or (org-ai-skills--ui-run-get :selected-proposal)
                         (org-ai-skills-ui-select-proposal)))
           (patterns (plist-get proposal :patterns))
           (review (plist-get proposal :review))
           (application (plist-get proposal :application))
           (buffer (org-ai-skills--ui-proposal-preview-buffer)))
      (org-ai-skills--ui-run-set :selected-proposal proposal)
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "org-ai-skills proposal preview\n\n")
          (insert (format "Proposal ID: %s\n" (or (plist-get proposal :proposal-id) "")))
          (insert (format "Status: %s\n" (or (plist-get proposal :status) "")))
          (insert (format "Type: %s\n" (or (plist-get proposal :type) "")))
          (insert (format "Created: %s\n" (or (plist-get proposal :created-at) "")))
          (insert (format "Target skill: %s\n" (or (plist-get proposal :target-skill-id) "")))
          (insert (format "Target skill file: %s\n" (or (plist-get proposal :target-skill-file) "")))
          (insert (format "Target source: %s\n" (or (plist-get proposal :target-skill-source) "")))
          (insert (format "Source candidate: %s\n" (or (plist-get proposal :source-candidate-id) "")))
          (insert (format "Slot: %s\n" (or (plist-get proposal :source-slot-key) "")))
          (insert (format "Confidence: %s\n" (or (plist-get proposal :confidence) "")))
          (insert (format "Risk: %s\n\n" (or (plist-get proposal :risk) "")))
          (insert "Rationale:\n")
          (insert (format "  %s\n\n" (or (plist-get proposal :rationale) "")))
          (org-ai-skills--insert-proposal-pattern-section
           "Steps"
           (org-ai-skills--proposal-seq->list (plist-get patterns :steps)))
          (insert "\n")
          (org-ai-skills--insert-proposal-pattern-section
           "Checks"
           (org-ai-skills--proposal-seq->list (plist-get patterns :checks)))
          (insert "\n")
          (org-ai-skills--insert-proposal-pattern-section
           "Failure handling"
           (org-ai-skills--proposal-seq->list (plist-get patterns :failure-handling)))
          (insert "\n")
          (org-ai-skills--insert-proposal-pattern-section
           "Heuristics"
           (org-ai-skills--proposal-seq->list (plist-get patterns :heuristics)))
          (insert "\nReview metadata:\n")
          (if (consp review)
              (insert (format "%s\n" (pp-to-string review)))
            (insert "  (none)\n"))
          (insert "\nApplication metadata:\n")
          (if (consp application)
              (insert (format "%s\n" (pp-to-string application)))
            (insert "  (none)\n"))
          (insert "\nRaw proposal:\n")
          (insert (pp-to-string proposal))
          (goto-char (point-min))
          (special-mode)))
      (display-buffer buffer)
      (org-ai-skills--ui-set-status 'ready "proposal-previewed")
      proposal)))

(defun org-ai-skills--parse-function-arg-names (arg-spec)
  "Parse ARG-SPEC string like \"(query date)\" into argument names."
  (let* ((raw (or arg-spec ""))
         (clean (replace-regexp-in-string "[()]" "" raw)))
    (split-string clean "[ \t\n,]+" t)))

(defun org-ai-skills--coerce-max-chars (max-chars)
  "Coerce MAX-CHARS into bounded integer."
  (let ((n (cond
            ((integerp max-chars) max-chars)
            ((and (stringp max-chars)
                  (string-match-p "^[0-9]+$" max-chars))
             (string-to-number max-chars))
            (t org-ai-skills-core-read-max-chars))))
    (max 1 n)))

(defun org-ai-skills--slice-string-by-chars (text max-chars)
  "Return TEXT truncated to MAX-CHARS if needed."
  (let ((limit (org-ai-skills--coerce-max-chars max-chars)))
    (if (<= (length text) limit)
        text
      (substring text 0 limit))))

(defun org-ai-skills-read-buffer (&optional buffer_name start end)
  "Read text from BUFFER_NAME with optional START and END positions.
When BUFFER_NAME is nil/empty, use current buffer.
START and END are 1-based positions and are clamped to buffer bounds."
  (let* ((target (if (and (stringp buffer_name)
                          (not (string-empty-p buffer_name)))
                     (get-buffer buffer_name)
                   (current-buffer))))
    (unless (buffer-live-p target)
      (org-ai-skills--signal-function-call-error
       (format "Buffer not found: %s" (or buffer_name ""))))
    (with-current-buffer target
      (let* ((beg (max (point-min)
                       (cond
                        ((integerp start) start)
                        ((and (stringp start)
                              (string-match-p "^[0-9]+$" start))
                         (string-to-number start))
                        (t (point-min)))))
             (fin (min (point-max)
                       (cond
                        ((integerp end) end)
                        ((and (stringp end)
                              (string-match-p "^[0-9]+$" end))
                         (string-to-number end))
                        (t (point-max))))))
        (when (> beg fin)
          (setq beg fin))
        (buffer-substring-no-properties beg fin)))))

(defun org-ai-skills-read-file (&optional file_path max_chars)
  "Read source file content from FILE_PATH with optional MAX_CHARS limit."
  (unless (and (stringp file_path) (not (string-empty-p file_path)))
    (org-ai-skills--signal-function-call-error
     "file_path is required for org-ai-skills-read-file"))
  (let* ((abs (expand-file-name file_path))
         (raw (if (file-readable-p abs)
                  (with-temp-buffer
                    (insert-file-contents abs)
                    (buffer-string))
                (org-ai-skills--signal-function-call-error
                 (format "Source file is not readable: %s" abs)))))
    (org-ai-skills--slice-string-by-chars raw max_chars)))

(defconst org-ai-skills--core-read-function-calls
  '((:name "org-ai-skills-read-buffer"
     :when "when current/named buffer context is needed"
     :args "(buffer_name start end)"
     :buffer_name "optional buffer name; empty means current buffer"
     :start "optional 1-based start position"
     :end "optional 1-based end position")
    (:name "org-ai-skills-read-file"
     :when "when source material is in an external file path"
     :args "(file_path max_chars)"
     :file_path "absolute or project-relative source file path"
     :max_chars "optional maximum characters to return"))
  "Core always-available read tool specs.")

(defconst org-ai-skills--core-provider-function-calls
  '((:name "org-ai-skills-core-provider-read-file"
     :when "when file content is needed under allowed roots"
     :args "(file_path max_chars)"
     :file_path "absolute or relative file path"
     :max_chars "optional maximum characters to return")
    (:name "org-ai-skills-core-provider-list-files"
     :when "when exploring entries under one folder"
     :args "(directory max_results)"
     :directory "absolute or relative directory path"
     :max_results "optional max entry count")
    (:name "org-ai-skills-core-provider-search-files"
     :when "when locating functions/usages by text query"
     :args "(query directory max_results)"
     :query "search pattern text"
     :directory "absolute or relative directory path"
     :max_results "optional max match count")
    (:name "org-ai-skills-core-provider-shell-exec"
     :when "when command-line inspection or scripts are required"
     :args "(command directory)"
     :command "shell command string"
     :directory "absolute or relative working directory path")
    (:name "org-ai-skills-core-provider-python-exec"
     :when "when quick Python experiments are required"
     :args "(code directory)"
     :code "python code string for python -c"
     :directory "absolute or relative working directory path")
    (:name "org-ai-skills-core-provider-org-babel-exec"
     :when "when running Org Babel code blocks for experiments"
     :args "(language body directory)"
     :language "Org Babel language name (example: emacs-lisp)"
     :body "source code body"
     :directory "absolute or relative working directory path"))
  "Core phase-1 provider tool specs.")

(defun org-ai-skills--request-function-calls (request &optional role)
  "Collect function call specs from REQUEST contexts.
When ROLE is `planner', return nil because planner must not use tools."
  (let ((request-role (or role (org-ai-skills--resolve-request-role request))))
    (if (eq request-role 'planner)
        nil
      (let ((calls nil)
            (skill-context (plist-get request :skill-context))
            (skill-contexts (plist-get request :skill-contexts)))
        (when org-ai-skills-enable-core-read-tools
          (setq calls (append calls org-ai-skills--core-read-function-calls)))
        (when org-ai-skills-enable-core-provider-tools
          (setq calls (append calls org-ai-skills--core-provider-function-calls)))
        (when skill-context
          (setq calls (append calls (or (plist-get skill-context :function-calls) nil))))
        (dolist (ctx skill-contexts)
          (setq calls (append calls (or (plist-get ctx :function-calls) nil))))
        (cl-remove-duplicates
         calls
         :test (lambda (a b)
                 (equal (plist-get a :name) (plist-get b :name))))))))

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

(defun org-ai-skills--request-gptel-tools (request &optional role)
  "Build gptel tool list from REQUEST and ROLE."
  (let ((calls (org-ai-skills--request-function-calls request role)))
    (if (or (null calls) (fboundp 'gptel-make-tool))
        (delq nil (mapcar #'org-ai-skills--function-call-to-gptel-tool calls))
      nil)))

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
         (working-directory (plist-get request :working-directory))
         (tools (org-ai-skills--request-gptel-tools request role))
         (tool-names (mapcar (lambda (fn-spec) (plist-get fn-spec :name))
                             (org-ai-skills--request-function-calls request role)))
         (logged-request (append request
                                 (list :request-role role
                                       :effective-model effective-model
                                       :effective-schema (if effective-schema t nil)
                                       :effective-working-directory working-directory
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
    (let ((org-ai-skills--core-provider-context-directory working-directory)
          (gptel-tools tools)
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

(defun org-ai-skills--interactive-rewrite-strict-args ()
  "Read interactive arguments for strict rewrite command."
  (let* ((target (org-ai-skills-org-read-rewrite-target))
         (skill (org-ai-skills-read-skill))
         (instruction (read-string "Strict rewrite addendum (optional): ")))
    (list target skill instruction)))

(defun org-ai-skills--interactive-plan-args ()
  "Read interactive arguments for `org-ai-skills-plan-run'."
  (let* ((target (org-ai-skills-org-read-rewrite-target))
         (task (read-string "Planner task: "
                            nil
                            'org-ai-skills--planner-task-history
                            org-ai-skills--last-planner-task)))
    (list target task)))

(defun org-ai-skills--interactive-plan-repeat-args ()
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

(defun org-ai-skills--interactive-plan-preset-args ()
  "Read interactive args for preset-based planner run."
  (let* ((target (org-ai-skills-org-read-rewrite-target))
         (preset (org-ai-skills-read-planner-task-preset)))
    (list target (car preset))))

(defun org-ai-skills-org-rewrite-subtree
    (target skill &optional instruction interactive-origin constraints)
  "Rewrite Org TARGET subtree at point via gptel using SKILL.
When TARGET is nil, resolve current subtree."
  (interactive (org-ai-skills--interactive-rewrite-args))
  (let* ((interactive-run (or interactive-origin
                              (called-interactively-p 'interactive)))
         (subtree (or target (org-ai-skills-org-resolve-subtree 'current)))
         (slot (org-ai-skills--ensure-subtree-slot-id subtree))
         (working-directory (org-ai-skills--resolve-working-directory slot))
         (effective-constraints
          (org-ai-skills--merge-rewrite-constraints
           (org-ai-skills--skill-default-rewrite-constraints
            (plist-get skill :skill-id))
           constraints))
         (request nil)
         (buffer (current-buffer))
         (dispatched nil)
         (failed nil)
         (run-id (org-ai-skills--candidate-id))
         (begin (copy-marker (plist-get slot :begin)))
         (end (copy-marker (plist-get slot :end))))
    (org-ai-skills--ui-start-run
     (list :run-id run-id
           :run-type 'rewrite
           :interactive-run interactive-run
           :status 'running
           :progress "generation"
           :target slot
           :source-buffer buffer
           :begin begin
           :end end
           :context-mode (plist-get slot :context-mode)
           :heading (plist-get slot :heading)
           :slot-key (plist-get slot :slot-key)
           :slot-id (plist-get slot :slot-id)
           :target-skill-id (plist-get skill :skill-id)
           :target-skill-file (plist-get skill :file)
           :skill skill
           :instruction instruction
           :working-directory working-directory
           :rewrite-constraints effective-constraints
           :task (or instruction "rewrite")
           :preset-id nil
           :selected-candidate nil
           :stop-requested nil
           :rerun-fn (lambda ()
                       (interactive)
                       (let ((latest (or (org-ai-skills--resolve-subtree-from-slot slot buffer)
                                         slot)))
                         (org-ai-skills-org-rewrite-subtree
                          latest skill instruction t effective-constraints)))))
    (unwind-protect
        (progn
          (org-ai-skills-apply-skill-function-calls skill)
          (setq request (org-ai-skills-build-gptel-rewrite-request
                         skill slot instruction))
          (setq request (append request
                                (list :buffer-name (buffer-name buffer)
                                      :buffer-file (buffer-file-name buffer)
                                      :working-directory working-directory)))
          (org-ai-skills-gptel-dispatch-rewrite
           request
           (lambda (&rest response)
             (unwind-protect
                 (unless failed
                   (let (raw)
                     (condition-case err
                         (setq raw (apply #'org-ai-skills--extract-gptel-response-text-if-ready response))
                       (org-ai-skills-gptel-error
                        (setq failed t)
                        (message "%s" (error-message-string err))
                        (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                          (org-ai-skills--ui-clear-overlay)
                          (org-ai-skills--ui-set-failure
                           "tool-error"
                           (error-message-string err)))))
                     (when raw
                       (if (org-ai-skills--ui-stop-requested-p run-id)
                           (org-ai-skills--ui-set-status 'canceled "canceled")
                         (let* ((rewritten (org-ai-skills--sanitize-rewrite-output raw slot))
                                (candidate nil)
                                (apply-target
                                 (or (org-ai-skills--resolve-subtree-from-slot slot buffer)
                                     (and (markerp begin)
                                          (marker-buffer begin)
                                          (markerp end)
                                          (marker-buffer end)
                                          (list :begin begin
                                                :end end
                                                :context-mode (plist-get slot :context-mode))))))
                           (setq rewritten
                                 (org-ai-skills--enforce-rewrite-constraints
                                  rewritten slot effective-constraints))
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
                             (if apply-target
                                 (if org-ai-skills-auto-apply-generated-candidate
                                     (progn
                                       (org-ai-skills-org-apply-candidate-to-subtree
                                        apply-target
                                        candidate)
                                       (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                                         (org-ai-skills--ui-clear-overlay)
                                         (org-ai-skills--ui-set-status 'applied "applied")))
                                   (if interactive-run
                                       (let ((selected (org-ai-skills--read-slot-candidate
                                                        (plist-get slot :slot-key) t)))
                                         (when selected
                                           (org-ai-skills-org-apply-candidate-to-subtree
                                            apply-target
                                            selected))
                                         (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                                           (org-ai-skills--ui-set-overlay 'ready)
                                           (org-ai-skills--ui-set-status 'ready "candidate-ready")))
                                     (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                                       (org-ai-skills--ui-set-overlay 'ready)
                                       (org-ai-skills--ui-set-status 'ready "candidate-ready"))))
                               (message "org-ai-skills candidate saved for: %s"
                                        (plist-get slot :heading))
                               (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                                 (org-ai-skills--ui-set-overlay 'ready)
                                 (org-ai-skills--ui-set-status 'ready "candidate-ready"))))))))
               (org-ai-skills-exclude-skill-function-calls skill)))))
          (setq dispatched t))
      (unless dispatched
        (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
          (org-ai-skills--ui-clear-overlay)
          (org-ai-skills--ui-set-failure
           "dispatch-failed"
           "Failed to dispatch rewrite request to gptel"))
        (org-ai-skills-exclude-skill-function-calls skill)))))

(defun org-ai-skills-org-rewrite-subtree-strict
    (target skill &optional instruction interactive-origin)
  "Rewrite TARGET with strict structure constraints."
  (interactive (org-ai-skills--interactive-rewrite-strict-args))
  (org-ai-skills-org-rewrite-subtree
   target
   skill
   (org-ai-skills--strict-rewrite-instruction instruction)
   interactive-origin
   '(:preserve-headlines t
     :omit-property-drawers t)))

(defun org-ai-skills-plan-run (target task &optional interactive-origin preset-id)
  "Run planner-driven rewrite on TARGET subtree using TASK.
When INTERACTIVE-ORIGIN is non-nil, treat invocation as interactive for auto-apply flow."
  (interactive (org-ai-skills--interactive-plan-args))
  (when (string-empty-p (or task ""))
    (signal 'org-ai-skills-planner-error
            (list "Planner task cannot be empty")))
  (setq org-ai-skills--last-planner-task task)
  (let* ((interactive-run (or interactive-origin
                              (called-interactively-p 'interactive)))
         (subtree (or target (org-ai-skills-org-resolve-subtree 'current)))
         (slot (org-ai-skills--ensure-subtree-slot-id subtree))
         (working-directory (org-ai-skills--resolve-working-directory slot))
         (buffer (current-buffer))
         (run-id (org-ai-skills--candidate-id))
         (begin (copy-marker (plist-get slot :begin)))
         (end (copy-marker (plist-get slot :end))))
    (org-ai-skills--ui-start-run
     (list :run-id run-id
           :run-type 'planner
           :interactive-run interactive-run
           :status 'running
           :progress "planning"
           :target slot
           :source-buffer buffer
           :begin begin
           :end end
           :context-mode (plist-get slot :context-mode)
           :heading (plist-get slot :heading)
           :slot-key (plist-get slot :slot-key)
           :slot-id (plist-get slot :slot-id)
           :target-skill-id nil
           :target-skill-file nil
           :skill nil
           :instruction nil
           :task task
           :working-directory working-directory
           :preset-id preset-id
           :selected-candidate nil
           :stop-requested nil
           :rerun-fn (lambda ()
                       (interactive)
                       (let ((latest (or (org-ai-skills--resolve-subtree-from-slot slot buffer)
                                         slot)))
                         (org-ai-skills-plan-run latest task t preset-id)))))
    (org-ai-skills-run-task-with-planner
     task
     slot
     (list :working-directory working-directory)
     (lambda (run-state)
       (if (org-ai-skills--ui-stop-requested-p run-id)
           (org-ai-skills--ui-set-status 'canceled "canceled")
         (let ((fatal-error (plist-get run-state :fatal-error)))
           (if (stringp fatal-error)
               (progn
                 (message "%s" fatal-error)
                 (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                   (org-ai-skills--ui-run-set :planner-run-state run-state)
                   (org-ai-skills--ui-clear-overlay)
                   (org-ai-skills--ui-set-failure "tool-error" fatal-error)))
             (let* ((raw (or (plist-get run-state :final-output) ""))
                    (planner-constraints (org-ai-skills--planner-constraints-for-run-state run-state))
                    (rewritten (org-ai-skills--sanitize-rewrite-output raw slot))
                    (candidate (org-ai-skills--record-generated-candidate
                                slot
                                task
                                "planner"
                                task
                                (org-ai-skills--enforce-rewrite-constraints
                                 rewritten slot planner-constraints)))
                    (apply-target (or (org-ai-skills--resolve-subtree-from-slot slot buffer)
                                    (and (markerp begin)
                                         (marker-buffer begin)
                                         (markerp end)
                                         (marker-buffer end)
                                         (list :begin begin
                                               :end end
                                               :context-mode (plist-get slot :context-mode))))))
               (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                 (let* ((target-skill-id (org-ai-skills--planner-run-state-target-skill-id run-state))
                        (target-skill-file (and (stringp target-skill-id)
                                                (org-ai-skills--planner-run-state-skill-file
                                                 run-state target-skill-id))))
                   (org-ai-skills--ui-run-set :target-skill-id target-skill-id)
                   (org-ai-skills--ui-run-set :target-skill-file target-skill-file))
                 (org-ai-skills--ui-run-set :planner-run-state run-state)
                 (org-ai-skills--ui-run-set :selected-candidate candidate)
                 (org-ai-skills--ui-set-status 'ready "candidate-ready"))
               (with-current-buffer buffer
                 (if apply-target
                     (if org-ai-skills-auto-apply-generated-candidate
                         (progn
                           (org-ai-skills-org-apply-candidate-to-subtree apply-target candidate)
                           (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                             (org-ai-skills--ui-clear-overlay)
                             (org-ai-skills--ui-set-status 'applied "applied")))
                       (if interactive-run
                           (let ((selected (org-ai-skills--read-slot-candidate
                                            (plist-get slot :slot-key) t)))
                             (when selected
                               (org-ai-skills-org-apply-candidate-to-subtree apply-target selected))
                             (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                               (org-ai-skills--ui-set-overlay 'ready)
                               (org-ai-skills--ui-set-status 'ready "candidate-ready")))
                         (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                           (org-ai-skills--ui-set-overlay 'ready)
                           (org-ai-skills--ui-set-status 'ready "candidate-ready"))))
                   (message "org-ai-skills planner candidate saved for: %s (%s)"
                            (plist-get slot :heading)
                            (plist-get candidate :candidate-id))
                   (when (equal (org-ai-skills--ui-run-get :run-id) run-id)
                     (org-ai-skills--ui-set-overlay 'ready)
                     (org-ai-skills--ui-set-status 'ready "candidate-ready"))))))))))))

(defun org-ai-skills-plan-repeat-task (target)
  "Run planner-driven rewrite on TARGET using last planner task."
  (interactive (org-ai-skills--interactive-plan-repeat-args))
  (when (string-empty-p (or org-ai-skills--last-planner-task ""))
    (signal 'org-ai-skills-planner-error
            (list "No previous planner task; run org-ai-skills-plan-run first")))
  (org-ai-skills-plan-run target org-ai-skills--last-planner-task t nil))

(defun org-ai-skills-plan-run-preset (target preset-id)
  "Run planner-driven rewrite on TARGET using planner task PRESET-ID."
  (interactive (org-ai-skills--interactive-plan-preset-args))
  (let ((task (cdr (assoc preset-id org-ai-skills-planner-task-presets))))
    (unless (stringp task)
      (signal 'org-ai-skills-planner-error
              (list (format "Unknown planner preset: %s" preset-id))))
    (org-ai-skills-plan-run target task t preset-id)))

(defmacro org-ai-skills-define-plan-run-preset-command (command-name task &optional docstring)
  "Define COMMAND-NAME to run planner with fixed TASK.
Optional DOCSTRING overrides the generated command documentation."
  `(defun ,command-name (target)
     ,(or docstring (format "Run planner-driven rewrite with fixed task: %s" task))
     (interactive (list (org-ai-skills-org-read-rewrite-target)))
     (org-ai-skills-plan-run target ,task t nil)))

(defvar org-ai-skills-embark-org-heading-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "R") #'org-ai-skills-embark-rewrite-subtree-action)
    (define-key map (kbd "P") #'org-ai-skills-embark-plan-run-action)
    (define-key map (kbd "p") #'org-ai-skills-embark-plan-repeat-task-action)
    map)
  "Embark keymap for Org heading actions provided by org-ai-skills.")

(defun org-ai-skills-embark-rewrite-subtree-action (&optional _target)
  "Embark action adapter for `org-ai-skills-org-rewrite-subtree'."
  (interactive)
  (call-interactively #'org-ai-skills-org-rewrite-subtree))

(defun org-ai-skills-embark-plan-run-action (&optional _target)
  "Embark action adapter for `org-ai-skills-plan-run'."
  (interactive)
  (call-interactively #'org-ai-skills-plan-run))

(defun org-ai-skills-embark-plan-repeat-task-action (&optional _target)
  "Embark action adapter for `org-ai-skills-plan-repeat-task'."
  (interactive)
  (call-interactively #'org-ai-skills-plan-repeat-task))

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
