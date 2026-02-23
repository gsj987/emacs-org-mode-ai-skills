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

(setq gptel-model 'meta-llama/llama-3.2-3b-instruct)
(setq gptel-backend
      (gptel-make-openai
       "OpenRouter"
       :host "openrouter.ai"
       :endpoint "/api/v1/chat/completions"
       :stream nil
       :key (auth-source-pick-first-password :host "openrouter.ai")
       :models '(meta-llama/llama-3.2-3b-instruct)))

;; Keep BDD/E2E profile explicit and lightweight.
(setq org-ai-skills-e2e-model-profile "meta-llama/llama-3.2-3b-instruct")
(setq org-ai-skills-bdd-live-timeout-seconds 180)
(setq org-ai-skills-bdd-live-setup-function nil)
;; Disable tool-use in E2E live run for providers/routes without tool support.
(setq org-ai-skills-enable-core-read-tools nil)
(setq org-ai-skills-enable-core-provider-tools nil)
