# START HERE — first run on a new machine

> **For Claude:** read this file top to bottom before anything else, then run the checklist below.
> **Do not begin story work.** The goal of this first session is only to get the environment
> verified and to confirm you understand how this project runs. Finish with the status report at the
> bottom and then wait for Jason.

---

## 1. What this project is

JCRC — Jewish Community Relations Council of New York. A Salesforce **Enterprise + NPSP** nonprofit
fundraising implementation, run for Mission Matters Group by **Jason Ott** (always the author name in
code and metadata headers).

Read these two files next; they are the actual rules of the road:

| File | What it gives you |
|------|-------------------|
| `CLAUDE.md` | The core development tenets. No guessing, CLI-first verification, documentation standards, profile-based security. |
| `JSI_Story_Workflow.md` | The 6-step playbook every `JSI-XX` story follows, plus the conventions cheat-sheet. |

Your **memory** carries the rest — the metadata gotchas, the story pipeline status, and Jason's
working preferences. If the memory restore in step 2 worked, you already have it.

## 2. Confirm the Claude context was restored

The bundle in `_ClaudeTransfer\` carries what git cannot: memory, transcripts, and gitignored
secrets. If Jason already ran the restore script, this is just a verification.

```powershell
# From the repo root. Safe to re-run; it backs up anything it would overwrite.
.\_ClaudeTransfer\Restore-OnThisPC.ps1
```

**Verify it took.** You should be able to answer these from memory, without reading files:
- What are the two active workstreams? (Gala Event Gifts, and JSI-123 Board Tracking)
- What is the rule about permission sets? (Don't create them — FLS goes on the `JCRC*` profiles)
- What does `RECORDTYPE` vs `RECORD_TYPE` mean in a report filter? (The former; the latter fails)

If you cannot, the memory did not land. Find the right folder and copy it in by hand:
```powershell
Get-ChildItem "$env:USERPROFILE\.claude\projects" | Where-Object Name -match 'JCRC-Dev'
```
That folder's name is derived from this repo's **absolute path**, so it is different on every
machine — never assume the name from the old PC.

## 3. Confirm the tooling

```powershell
sf --version          # Salesforce CLI — required
git --version
node --version        # only needed for lint/jest, not for metadata work
```

If `sf` is missing: <https://developer.salesforce.com/tools/salesforcecli>

**Run every `sf` command through PowerShell, not Git Bash** — Git Bash mangles the CLI path and
fails with `'C:\Program' is not recognized`.

## 4. Authenticate the orgs — these do NOT travel

Salesforce auth tokens are machine-bound and are deliberately **not** in the bundle. Both orgs must
be re-authenticated on this laptop. **The aliases must match exactly** (hyphen, not underscore) —
the allow-rules and every doc reference depend on them.

```powershell
sf org login web --alias JCRC-Dev  --instance-url https://test.salesforce.com    # SANDBOX - build target
sf org login web --alias JCRC-Prod --instance-url https://login.salesforce.com   # PRODUCTION
sf org list                                                                       # confirm both Connected
```

⚠️ `JCRC-Dev` is the **sandbox** — it needs `test.salesforce.com`. Using `login.salesforce.com` will
fail or, worse, authenticate the wrong org under the sandbox alias.

⚠️ ~25 other Mission Matters client orgs get authenticated on Jason's machines. **Always pass
`-o JCRC-Dev` explicitly.** Never rely on the default target-org.

## 5. Refresh local metadata from the org

Someone may have changed the org since this bundle was made — Jason does Flow Builder, App Builder
record pages, NPSP settings, and reports in the UI, and none of that is in the repo until it's
retrieved.

```powershell
# Preview first - writes nothing, prints what would come down
.\RetrieveSFLocal\Retrieve-FullOrg.ps1 -OrgAlias JCRC-Dev -ManifestOnly

# Then the real retrieve (a few minutes)
.\RetrieveSFLocal\Retrieve-FullOrg.ps1 -OrgAlias JCRC-Dev
```

Then **look at what changed** — this is the useful part, not the retrieve itself:

```powershell
git status --short
git diff --stat
```

- If the diff is empty, the org matches the repo. Say so.
- If there are changes, they are **org drift** — work done in the UI that was never committed.
  Summarize it for Jason. **Do not commit it** without asking; a metadata refresh belongs in its own
  commit, separate from story work, and some drift is deliberate.
- Known pre-existing drift to expect: `JCRC_Development.app-meta.xml` carries ~430 lines of
  record-page assignments made during the Constant Contact work, plus untracked
  `externalCredentials/` and `namedCredentials/` folders. Those are known and intentionally
  uncommitted — mention them, don't "fix" them.

## 6. Check where the work stands

`PROJECT_CONTEXT.md` is the single-file handoff snapshot — current state, both active workstreams,
and where to pick up. Read it. Your `project-jcrc-story-pipeline` memory has the per-story detail.

```powershell
git log --oneline -10
git status
```

## 7. Report and stop

Give Jason a short status:

1. Memory restored? (yes/no, how many files)
2. Both orgs authenticated and Connected?
3. Did the metadata retrieve show drift — and if so, what?
4. Current branch, HEAD commit, and whether it's in sync with `origin/main`
5. The two active workstreams and their next actions, from memory

**Then stop and wait.** Do not start a story, do not deploy, do not commit. Jason will say what's
next.

---

## How we run this project (the short version)

Full detail is in `JSI_Story_Workflow.md`. The parts that matter most:

- **No guessing.** Verify against the real org with the `sf` CLI and cite Salesforce docs. If a
  Salesforce Help page comes back as a JS-gated CSS shell, say so — Jason will pull the page for you.
- **Every story is a folder** `JSI-XX/` with dictation notes, the User Story pulled from Jira, and an
  Implementation Plan carrying a Build Log.
- **Definition of Done = user-facing outcomes**, never implementation specs. The "how" lives only in
  the Implementation Plan.
- **Security on the `JCRC*` profiles, not permission sets.** Deploy FLS *with* new fields or they're
  invisible to admins, reports, and the anonymous-Apex compiler. Full profiles aren't
  source-deployable in this org — use the additive minimal-profile technique (and remember it can
  only add permissions, never revoke).
- **Build in the sandbox** (`JCRC-Dev`). Verify with anonymous Apex inside
  `Database.setSavepoint()` → `Database.rollback(sp)` so no test data persists. **Never deploy to
  `JCRC-Prod` without an explicit instruction.**
- **Commit only the current story's files.** Stage explicit paths, never `git add -A` — parallel
  story threads land work concurrently. Push only when Jason asks.
- **Division of labor:** Jason does the UI/config himself — Flow Builder, NPSP Settings and
  Customizable Rollups, Lightning App Builder record pages and their record-type assignments, report
  builder, DLRS. Claude authors and deploys the version-controlled metadata.
- **Permissions:** Jason uses standard permission prompts on his machines. Do **not** add blanket
  bare-tool-name allow-rules to `.claude/settings.local.json`, and don't fan out to sub-agents that
  re-prompt him.

## Getting back to a previous conversation

The transcripts came along in the bundle, so you can pick up an old thread:

```powershell
claude --resume        # run in the repo folder, then choose the session
```
