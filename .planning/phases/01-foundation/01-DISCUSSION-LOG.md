# Phase 1: Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-17
**Phase:** 1-Foundation
**Areas discussed:** Terragrunt directory layout, CT bootstrap approach, State bucket bootstrap, Pre-flight script scope

---

## Terragrunt Directory Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Environment-keyed | live/management/us-east-1/ct-bootstrap/ — mirrors Terragrunt best practices, scales cleanly | |
| Flat | management/ct-bootstrap/, management/aft/ — simpler, fewer dirs | ✓ |

**User's choice:** Flat
**Notes:** Simpler structure preferred for this org size.

---

## CT Bootstrap Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Manual console + IaC wrapper | Deploy CT via console, then data sources to capture IDs | ✓ |
| Full IaC via resource | aws_controltower_landing_zone resource — research flagged as risky | |

**User's choice:** Manual console + IaC wrapper
**Notes:** CT manages itself via StackSets; IaC wrapper captures outputs only, does not manage CT state.

---

## State Bucket Bootstrap

| Option | Description | Selected |
|--------|-------------|----------|
| Bootstrap script | scripts/bootstrap-state.sh via aws CLI — one-time manual step | ✓ |
| Terragrunt auto-create | remote_state with create_before_destroy | |
| Local backend then migrate | Apply with local backend first, then migrate | |

**User's choice:** Bootstrap script
**Notes:** Clean separation — state infra exists before Terragrunt runs.

---

## Pre-flight Script Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Hard block (exit 1) | Fails loudly on any blocker — forces fix before CT deploy | ✓ |
| Warn + report | Prints report, exits 0 — operator decides | |

**User's choice:** Hard block (exit 1)
**Notes:** No ambiguity — if the script fails, nothing proceeds.

---

## Claude's Discretion

- OU registration tooling (dedicated Terragrunt unit vs other approach)
- Pre-flight script language (Bash assumed, Python acceptable)

## Deferred Ideas

None.
