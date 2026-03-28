#!/usr/bin/env bash
# vault_paths.sh — Centralized vault path configuration
# Source this after env.sh. All scripts that write to vault should use these vars.

: "${VAULT_ROOT:=${HOME}/vault}"

# Top-level directories
VAULT_SYSTEM="${VAULT_ROOT}/00-System"
VAULT_INBOX="${VAULT_ROOT}/00-inbox"
VAULT_KNOWLEDGE="${VAULT_ROOT}/10-knowledge"
VAULT_EXPERTS="${VAULT_ROOT}/20-experts"
VAULT_PROJECTS="${VAULT_ROOT}/30-projects"
VAULT_LOG="${VAULT_ROOT}/40-log"

# Knowledge domain paths
VAULT_ACCOUNTING="${VAULT_KNOWLEDGE}/accounting"
VAULT_TAX="${VAULT_KNOWLEDGE}/tax"
VAULT_FINANCE="${VAULT_KNOWLEDGE}/finance"
VAULT_LEGAL="${VAULT_KNOWLEDGE}/legal"
VAULT_ECONOMICS="${VAULT_KNOWLEDGE}/economics"
VAULT_STRATEGY="${VAULT_KNOWLEDGE}/strategy"
VAULT_INVESTMENT="${VAULT_KNOWLEDGE}/investment"
VAULT_MEDICAL="${VAULT_KNOWLEDGE}/medical"
VAULT_RESEARCH="${VAULT_KNOWLEDGE}/research"
VAULT_TECH="${VAULT_KNOWLEDGE}/tech"
VAULT_AI="${VAULT_KNOWLEDGE}/ai"
VAULT_AI_AGENTS="${VAULT_KNOWLEDGE}/ai-agents"
VAULT_WRITING="${VAULT_KNOWLEDGE}/writing"
VAULT_MUSIC="${VAULT_KNOWLEDGE}/music"
VAULT_REAL_ESTATE="${VAULT_KNOWLEDGE}/real-estate"
VAULT_COST_ACCOUNTING="${VAULT_KNOWLEDGE}/cost_accounting"
VAULT_CREATIVE="${VAULT_KNOWLEDGE}/creative"

# Helper: resolve domain name to path
vault_domain_path() {
  local domain="${1:-research}"
  if [[ "$domain" == "inbox" ]]; then
    echo "${VAULT_INBOX}"
  else
    echo "${VAULT_KNOWLEDGE}/${domain}"
  fi
}

export VAULT_ROOT VAULT_SYSTEM VAULT_INBOX VAULT_KNOWLEDGE
export VAULT_EXPERTS VAULT_PROJECTS VAULT_LOG
