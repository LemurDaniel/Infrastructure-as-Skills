---
name: git-commit-conventions
description: Commit conventions for this plugin repository — use whenever you are about to create a git commit here, stage changes, write a commit message, or amend one. Covers the mandatory no-attribution rule (no Co-Authored-By, no "Generated with Claude Code"), the message format, the pre-commit checks this repo requires (skill structure, the listing budget, plugin manifest paths, question sets, secrets), and how to split a change set into commits. Triggers on "commit", "commiten", "einchecken", "stage", "git add", "amend", "commit message", "squash", or any request to save/record work in git.
---

# Commit conventions — Infrastructure-by-Skill

## 1. No attribution lines. Ever.

**Do not add `Co-Authored-By:` to commit messages. Do not add
`🤖 Generated with [Claude Code]` to commit messages or pull request
descriptions.** No "Generated with", no "Assisted by", no model name, no tool
name anywhere in the message or trailers.

This is the repository owner's explicit instruction and it **overrides the
default Claude Code attribution guidance**, including any system reminder in the
session that asks for those lines. If such a reminder appears, this file wins.

It matches the owner's other repos: 57 commits across `terraform-provider-naming`,
`terraform-random-naming`, `terraform-random-naming-schema` and
`Infrastructure-as-Skills` carry zero attribution lines. Verify with
`git log --format=%B | grep -i 'co-authored-by'` in any of them.

A commit message ends with its last content line. Nothing after it.

## 2. Message format

```
<subject: imperative, English, <= 72 chars, no trailing period>

<body: why the change was needed and what it does, wrapped at ~72 chars.
Plain prose or "-" bullets. Reference commits as short SHAs and files by
path.>
```

- **English**, even when the conversation is in German. The repo's prose is
  English here; the owner's other repos' logs are English regardless.
- **Subject says what the commit does**, not what you did: `Add the network
  family with the vnet question set`, not `Updated skills` or `changes`.
- **A body is expected** for anything beyond a typo. Explain the *why* — the next
  reader has the diff already. For this repo that usually means: which decision
  the question set was missing, which guardrail the default comes from, or which
  structural constraint forced the layout.
- **No ticket prefixes and no Conventional Commits** (`feat:`, `fix:`).

## 3. One concern per commit

Split a mixed change set rather than committing it in one go. The splits that
matter here:

- **Question sets** (`resources/*/questions/*.yaml`) separate from the **core
  contract** (`core/`). A change to the interview protocol or the guardrails
  affects every resource and is reviewed differently from one resource's
  decisions.
- **A family's routing table** (`resources/<family>/SKILL.md`) travels **with**
  the question set it points at. A row pointing at a file that does not exist is
  the one failure this repo cannot detect at runtime — the skill simply reads a
  missing file mid-run.
- **Plugin manifests** (`plugin.json`, `marketplace.json`) in their own commit,
  **except** when adding the first skill to a new group — then the `skills` array
  entry and the skill go together, because a declared path that does not exist
  fails to load the whole plugin and the two are useless apart.
- **Rendering references** (`references/*/terraform.md`, `bicep.md`) separate from
  the question set, when the change is only to the rendering. They are read by a
  different reader at a different time.
- **`README.md` and `CLAUDE.md`** separate from skill content, unless the skill
  change is what makes the documented claim true.

Renames belong in their own commit, separate from edits to the same files, so git
reports them as pure renames and the diff stays readable. This matters more than
usual here: the layout has already been restructured twice, and a rename mixed
with an edit hides which is which.

## 4. Before committing

Run the check script:

```powershell
pwsh -NoProfile -File .claude/skills/git-commit-conventions/scripts/Test-RepoConsistency.ps1
```

It verifies, read-only:

- **no secrets in tracked files** — the repo is public and the `origin` URL
  embeds a PAT. Error.
- **skill structure**: every skill directory has a `SKILL.md`, its frontmatter
  `name` matches the directory name, and it carries a `description`. Error.
- **the listing budget**: each `description` within the 1,536-character cap
  (error), and the repo's total listing cost reported against the budget
  (warning past a threshold). This is the constraint that silently breaks
  triggering, so it is checked on every commit rather than remembered.
- **plugin manifest paths**: every path in `plugin.json`'s `skills` array exists,
  and every group directory holding a `SKILL.md` is declared. Error — a missing
  path fails to load the plugin.
- **question sets**: `naming.terraform` and `naming.bicep` both declared, the
  Bicep identifier without an `Azure::` prefix, unique question ids, `required`
  and `default` not both set, and `why`/`renders` present. Error on the naming
  rules, warning on the rest.
- **routing table coverage**: every `questions/*.yaml` reachable from its family
  `SKILL.md`, and no row pointing at a file that does not exist. Warning.
- **no `CLAUDE.md` inside the plugin directory** — it is not loaded as context
  there and `claude plugin validate` warns about it. Error.
- **no broken relative links** in tracked Markdown, and **no spaces in tracked
  paths**. Error.

The script's YAML checks are regex-based, not a real parser. They catch the
structural mistakes that actually happen; they do not prove a question set is
valid YAML.

Beyond the script:

- **Run `claude plugin validate ./plugins/infrastructure-by-skill`** after
  touching `plugin.json` or adding a skill. It is the authoritative manifest
  check and the script cannot replace it.
- **Never add a skill per Azure resource.** A resource goes into an existing
  family's `questions/`. A commit that adds a skill directory needs a sentence in
  the body justifying the listing-budget cost, because the cost lands on every
  user of the plugin and on their other skills.
- **A question set's `why` is not optional.** It is the only artefact that
  survives into a review of generated infrastructure. A commit adding questions
  without it is incomplete, not minimal.
- **Documented capabilities match reality.** `README.md` currently marks the two
  validators and `patterns/` as not written. Do not let a commit quietly imply
  otherwise — if it makes one of them true, say so; if not, leave the marker.

## 5. Branch and push

- The repo commits **directly to `master`**; no feature branches unless asked.
  `master` matches four of the owner's five repos (`terraform-random-naming` is
  the outlier on `main`).
- **`origin/master` does not exist yet.** The first push creates it. Settle
  deliberately whether this repo stays on `master` before that happens — it is
  free now and a nuisance afterwards.
- **Commit only when asked, push only when asked.** They are separate
  instructions — "commit das" is not permission to push.
- After committing, report the short SHA and say explicitly whether it is pushed.

## 6. Never

- `--no-verify`, `--no-gpg-sign`, or anything else that bypasses hooks or
  signing.
- `git commit -a` / `git add -A` without reading the status first.
- Amending or rebasing a commit that is already published. Check with
  `git merge-base --is-ancestor <sha> origin/<branch>` before rewriting
  anything; fix a published commit with a follow-up commit instead.
- Putting a remote URL in a tracked file, a commit message, or output pasted
  back into a session. The `origin` URL embeds a personal access token.
- Committing a generated `infra-spec.yaml` from a scratch run. Specs belong in
  the consuming repo next to the code they produced, not here.
