# CLAUDE.md

## Engineering Practices

### 1) Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs. Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2) Simplicity First

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.
- Ask: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3) Surgical Changes

Touch only what you must. Clean up only your own mess. When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.
- The test: every changed line should trace directly to the user's request.

### 4) Goal-Driven Execution

Define success criteria. Loop until verified. Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan with a check per step (`1. [step] → verify: [check]`). Strong success criteria let you loop independently; weak criteria ("make it work") require constant clarification.

### 5) No Security Theater (lessons from audit S5 / Trusted Types removal)

A control that *looks* protective but enforces nothing is worse than none — it creates false confidence and hides the real gap. Distilled from removing the pass-through Trusted Types setup:

- **Verify a security control actually does something.** Identity/pass-through policies, force-allow fallbacks, and "patch the sink so the block never fires" workarounds are theater. The TT policies returned input unchanged and the innerHTML/outerHTML patches force-allowed *blocked* HTML — enforcement was fully neutralized while appearing hardened.
- **Prefer removal over a half-measure.** A half-sanitizer is worse than honest escaping discipline. The real defense here is `FragForge.esc()`/server-side escaping before any innerHTML sink — keep that consistent rather than wrapping it in a fake policy.
- **Before deleting accreted defensive code, read its git history.** `git log`/`git blame` reveal *why* it was added. The TT patches accreted across several commits specifically to keep the site working *despite* the directive — that history is what confirmed the directive enforced nothing. Decide removal vs. a genuine fix deliberately, not mechanically.
- **When you change a documented guardrail, update the guardrail in the same change** (see PSI guardrail #7) and add a regression test that locks in the new contract (e.g., the live CSP-header assertion that no `trusted-types` directive ships).

## Core Principles

- **Intent First**: Every decision flows from matching intent correctly
- **No Laziness**: Find root ranking issues. No surface-level fixes
- **Minimal Impact**: Edits should only touch what's necessary.
