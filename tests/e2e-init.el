;;; e2e-init.el --- Minimal live gptel init for E2E -*- lexical-binding: t; -*-

;; Usage:
;; emacs -Q --batch \
;;   -l tests/e2e-init.el \
;;   -l tests/e2e-tests.el \
;;   -f ert-run-tests-batch-and-exit

;; Prefer source over stale bytecode in batch E2E runs.
(setq load-prefer-newer t)

(add-to-list 'load-path
             (expand-file-name "../elisp"
                               (file-name-directory (or load-file-name buffer-file-name))))
(require 'org-ai-skills)

;; Ensure gptel checkout is reachable in -Q mode.
(let ((gptel-dir (expand-file-name "~/.emacs.d/straight/repos/gptel/")))
  (when (file-directory-p gptel-dir)
    (add-to-list 'load-path gptel-dir)))

;; Configure your gptel backend here.
;; Keep endpoint generic for open-source safety.
(require 'gptel)
(require 'gptel-curl)
(require 'gptel-openai)
(require 'gptel-org)
(require 'auth-source)
(require 'subr-x)
(require 'cl-lib)

(defvar org-ai-skills-e2e-openrouter-tool-provider-order
  (let ((raw (getenv "ORG_AI_SKILLS_OPENROUTER_TOOL_PROVIDER_ORDER")))
    (or (and (stringp raw)
             (not (string-empty-p raw))
             (split-string raw "," t "[[:space:]]+"))
        '("atlas-cloud/fp8" "alibaba")))
  "Provider slug order for OpenRouter tool-call runs.
Defaults to qwen/qwen3-8b endpoints known to support tools in this project.
Can be overridden by ORG_AI_SKILLS_OPENROUTER_TOOL_PROVIDER_ORDER.")

(defvar org-ai-skills-e2e-openrouter-tool-request-params
  (if org-ai-skills-e2e-openrouter-tool-provider-order
      `(:provider (:require_parameters t
                   :allow_fallbacks :json-false
                   :order ,(vconcat org-ai-skills-e2e-openrouter-tool-provider-order)))
    '(:provider (:require_parameters t
                 :allow_fallbacks :json-false)))
  "OpenRouter request params used for tool-call E2E coverage tests.")

(defun org-ai-skills-e2e--plist-remove-key (plist key)
  "Return PLIST with KEY removed."
  (let ((result nil))
    (while plist
      (let ((k (car plist))
            (v (cadr plist)))
        (unless (eq k key)
          (setq result (plist-put result k v))))
      (setq plist (cddr plist)))
    result))

(defun org-ai-skills-e2e--strip-parallel-tool-calls (request-data)
  "Remove unsupported :parallel_tool_calls from REQUEST-DATA for E2E."
  (if (and (listp request-data)
           (plist-member request-data :parallel_tool_calls))
      (org-ai-skills-e2e--plist-remove-key request-data :parallel_tool_calls)
    request-data))

(setq gptel-model 'qwen/qwen3-8b)
(setq gptel-backend
      (gptel-make-openai
       "OpenRouter"
       :host "openrouter.ai"
       :endpoint "/api/v1/chat/completions"
       :stream nil
       :key (auth-source-pick-first-password :host "openrouter.ai")
       :models '(qwen/qwen3-8b)))

;; Some OpenRouter endpoints reject the OpenAI-compatible
;; :parallel_tool_calls field even when tool calling is supported.
;; Strip it in E2E to keep tool-call coverage focused on actual tool flow.
(advice-add 'gptel--request-data :filter-return
            #'org-ai-skills-e2e--strip-parallel-tool-calls)

;; Keep BDD/E2E profile explicit and lightweight.
(setq org-ai-skills-e2e-model-profile "qwen/qwen3-8b")
(setq org-ai-skills-bdd-live-timeout-seconds 180)
(setq org-ai-skills-bdd-live-setup-function nil)
;; Disable tool-use in E2E live run for providers/routes without tool support.
(setq org-ai-skills-enable-core-read-tools nil)
(setq org-ai-skills-enable-core-provider-tools nil)
(setq org-ai-skills-enable-skill-function-calls t)
(setq org-ai-skills-gptel-request-params nil)
;; Tool-call coverage test reuses default skill function-call setting and
;; applies provider routing params per test.
