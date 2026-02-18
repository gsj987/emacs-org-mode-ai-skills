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

(defvar org-ai-skills--last-debug-entry nil
  "Last debug entry captured for gptel dispatch.")

(defvar org-ai-skills--last-planner-task nil
  "Last task string used by planner run commands.")

(defvar org-ai-skills--planner-task-history nil
  "Minibuffer history for planner task prompts.")

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
         ((and current (string-match "^[ \t]+\\([[:alnum:]-]+\\):\\s-*\\(.+\\)$" line))
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
         (outputs (org-ai-skills--parse-bullet-lines outputs-section))
         (contracts (org-ai-skills--parse-bullet-lines contracts-section))
         (requirements (org-ai-skills--parse-bullet-lines requirements-section))
         (function-calls (org-ai-skills--parse-function-calls function-calls-section)))
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
          :raw-sections (list :description description
                              :inputs inputs-section
                              :outputs outputs-section
                              :steps steps-section
                              :contracts contracts-section
                              :requirements requirements-section
                              :function-calls function-calls-section)
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

(defun org-ai-skills-parse-planner-response (text metadata-list)
  "Parse planner TEXT into normalized structure using METADATA-LIST."
  (let* ((json-object (org-ai-skills--extract-json-object text))
         (raw (json-parse-string
               json-object
               :object-type 'plist
               :array-type 'list
               :null-object nil
               :false-object nil))
         (known-skill-ids (mapcar (lambda (meta) (plist-get meta :skill-id))
                                  metadata-list))
         (candidates-raw (or (plist-get raw :candidates) nil))
         (plan-raw (or (plist-get raw :plan) nil))
         (replan-raw (or (org-ai-skills--plist-value raw :replan-signal :replan_signal)
                         nil)))
    (unless (and (listp plan-raw) plan-raw)
      (signal 'org-ai-skills-planner-error
              (list "Planner response must include non-empty plan")))
    (when (> (length plan-raw) org-ai-skills-planner-max-steps)
      (signal 'org-ai-skills-planner-error
              (list (format "Planner response exceeds max steps (%d > %d)"
                            (length plan-raw)
                            org-ai-skills-planner-max-steps))))
    (let* ((normalized-candidates
            (mapcar (lambda (candidate)
                      (org-ai-skills--normalize-planner-candidate candidate known-skill-ids))
                    candidates-raw))
           (normalized-steps
            (apply #'append
                   (mapcar (lambda (step)
                             (org-ai-skills--validate-planner-step
                              (org-ai-skills--normalize-planner-step step)
                              known-skill-ids))
                           plan-raw)))
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
   :function-calls (or (plist-get skill :function-calls) nil)
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
        (path (mapconcat #'identity (org-get-outline-path t t) "/")))
    (save-excursion
      (org-end-of-subtree t t)
      (list :begin begin
            :end (point)
            :level level
            :heading heading
            :path path
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
         (skill-context (org-ai-skills-build-skill-context skill subtree))
         (outputs (or (plist-get skill :outputs) nil))
         (contracts (or (plist-get skill :contracts) nil))
         (requirements (or (plist-get skill :requirements) nil))
         (function-calls (or (plist-get skill :function-calls) nil))
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
    (list :skill-id (plist-get base-payload :skill-id)
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
                   (requirements (plist-get skill :requirements)))
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
         (request (org-ai-skills-build-step-request step run-state loaded-skills)))
    (org-ai-skills-gptel-dispatch-rewrite
     request
     (lambda (&rest response)
       (let* ((raw (apply #'org-ai-skills--extract-gptel-response-text response))
              (output (org-ai-skills--extract-subtree-body raw))
              (updated-run-state (org-ai-skills--record-run-step run-state step output)))
         (funcall callback updated-run-state output))))))

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
       (let* ((text (apply #'org-ai-skills--extract-gptel-response-text response))
              (parsed (org-ai-skills-parse-planner-response text metadata)))
         (funcall callback parsed))))))

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
           (entry
            (concat
             (format "=== org-ai-skills gptel dispatch @ %s ===\n" timestamp)
             (format "Event: %s\n" event-type)
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
  (org-ai-skills--append-debug-entry request)
  (funcall #'gptel-request
           (plist-get request :prompt)
           :callback callback))

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
    (setq request (append request
                          (list :buffer-name (buffer-name buffer)
                                :buffer-file (buffer-file-name buffer))))
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

(defun org-ai-skills-org-plan-and-run-subtree (target task)
  "Run planner-driven rewrite on TARGET subtree using TASK."
  (interactive (org-ai-skills--interactive-plan-run-args))
  (when (string-empty-p (or task ""))
    (signal 'org-ai-skills-planner-error
            (list "Planner task cannot be empty")))
  (setq org-ai-skills--last-planner-task task)
  (let* ((subtree (or target (org-ai-skills-org-resolve-subtree 'current)))
         (buffer (current-buffer))
         ;; Markers keep target positions stable for async callback.
         (begin (copy-marker (plist-get subtree :begin)))
         (end (copy-marker (plist-get subtree :end))))
    (org-ai-skills-run-task-with-planner
     task
     subtree
     nil
     (lambda (run-state)
       (let* ((raw (or (plist-get run-state :final-output) ""))
              (rewritten (org-ai-skills--sanitize-rewrite-output raw subtree)))
         (with-current-buffer buffer
           (org-ai-skills-org-apply-rewrite-result
            (list :begin begin :end end)
            rewritten)
           (message "org-ai-skills planner rewrite applied for: %s"
                    (plist-get subtree :heading))))))))

(defun org-ai-skills-org-plan-and-run-subtree-repeat-task (target)
  "Run planner-driven rewrite on TARGET using last planner task."
  (interactive (org-ai-skills--interactive-plan-run-repeat-args))
  (when (string-empty-p (or org-ai-skills--last-planner-task ""))
    (signal 'org-ai-skills-planner-error
            (list "No previous planner task; run org-ai-skills-org-plan-and-run-subtree first")))
  (org-ai-skills-org-plan-and-run-subtree target org-ai-skills--last-planner-task))

(defun org-ai-skills-org-plan-and-run-subtree-preset (target preset-id)
  "Run planner-driven rewrite on TARGET using planner task PRESET-ID."
  (interactive (org-ai-skills--interactive-plan-run-preset-args))
  (let ((task (cdr (assoc preset-id org-ai-skills-planner-task-presets))))
    (unless (stringp task)
      (signal 'org-ai-skills-planner-error
              (list (format "Unknown planner preset: %s" preset-id))))
    (org-ai-skills-org-plan-and-run-subtree target task)))

(defmacro org-ai-skills-define-plan-run-preset-command (command-name task &optional docstring)
  "Define COMMAND-NAME to run planner with fixed TASK.
Optional DOCSTRING overrides the generated command documentation."
  `(defun ,command-name (target)
     ,(or docstring (format "Run planner-driven rewrite with fixed task: %s" task))
     (interactive (list (org-ai-skills-org-read-rewrite-target)))
     (org-ai-skills-org-plan-and-run-subtree target ,task)))

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
