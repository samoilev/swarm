# AGENTS.md

## Engineering Practices

### 1) Think Before Coding

No assume. No hide confusion. Show tradeoffs. Before build:

- State assumptions clear. Unsure → ask.
- Many readings exist → show all. No pick silent.
- Simpler way exist → say so. Push back when right.
- Unclear → stop. Name confusion. Ask.

### 2) Simplicity First

Min code solve problem. Nothing speculative.

- No feature beyond ask.
- No abstraction for single-use code.
- No "flexibility"/"configurability" not asked.
- No error handling for impossible case.
- Write 200 lines but 50 enough → rewrite.
- Ask: "Senior engineer call this overcomplicated?" Yes → simplify.

### 3) Surgical Changes

Touch only what must. Clean only own mess. Editing existing code:

- No "improve" nearby code, comment, format.
- No refactor what not broken.
- Match existing style, even if you differ.
- Notice unrelated dead code → mention. No delete.

When changes make orphans:

- Remove imports/vars/functions YOUR change made unused.
- No remove pre-existing dead code unless asked.
- Test: every changed line trace direct to user request.

### 4) Goal-Driven Execution

Define success criteria. Loop until verified. Turn tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

Multi-step task → state brief plan, check per step (`1. [step] → verify: [check]`). Strong criteria → loop independent. Weak criteria ("make it work") → need constant clarify.

### 5) No Security Theater (lessons from audit S5 / Trusted Types removal)

Control that *looks* protective but enforce nothing worse than none — make false confidence, hide real gap. From removing pass-through Trusted Types setup:

- **Verify a security control actually does something.** Identity/pass-through policies, force-allow fallbacks, "patch the sink so the block never fires" workarounds = theater. TT policies return input unchanged, innerHTML/outerHTML patches force-allowed *blocked* HTML — enforcement fully neutralized while look hardened.
- **Prefer removal over a half-measure.** Half-sanitizer worse than honest escaping discipline. Real defense = `FragForge.esc()`/server-side escaping before any innerHTML sink — keep consistent, no wrap in fake policy.
- **Before deleting accreted defensive code, read its git history.** `git log`/`git blame` reveal *why* added. TT patches accreted across several commits to keep site working *despite* directive — that history confirm directive enforce nothing. Decide removal vs genuine fix deliberate, not mechanical.
- **When you change a documented guardrail, update the guardrail in the same change** (see PSI guardrail #7) and add regression test lock new contract (e.g. live CSP-header assertion that no `trusted-types` directive ships).

## Core Principles

- **Intent First**: Every decision flow from match intent correct
- **No Laziness**: Find root ranking issue. No surface fix
- **Minimal Impact**: Edit touch only what necessary.