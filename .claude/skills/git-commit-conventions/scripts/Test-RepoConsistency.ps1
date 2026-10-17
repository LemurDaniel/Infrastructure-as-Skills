<#
.SYNOPSIS
    Pre-commit consistency checks for the Infrastructure-as-Skills repo.

.DESCRIPTION
    Read-only. Verifies the things that can actually go wrong in a Claude Code
    plugin repo whose content is Markdown and YAML:

      1. Secrets in tracked files. The repo is public and the origin URL embeds
         a PAT, so a pasted token is the realistic leak here.
      2. Skill structure: every skill directory carries a SKILL.md whose
         frontmatter name matches the directory and which has a description.
      3. The skill listing budget: each description within the 1,536-character
         cap, and the repo's total listing cost reported. This is the constraint
         that silently breaks skill triggering.
      4. Plugin manifest paths: every path in plugin.json's skills array exists,
         and every group directory holding a SKILL.md is declared. A missing
         path fails to load the plugin.
      5. Question sets: both naming identifier forms and the abbreviation
         declared, the Bicep one without an Azure:: prefix, unique ids,
         required/default not both set, why and renders present. A
         scope: deployment set names no resource and is exempt from the
         naming checks.

      6. Routing coverage: every resource's questions.yaml reachable from its family's
         routing.md (or the SKILL.md of the skill holding it), every family's
         routing.md linked from core/azure-resources, and no row pointing at a
         missing file.
      7. No CLAUDE.md inside the plugin directory - it is not loaded as context
         there and claude plugin validate warns about it.
      8. Broken relative links in tracked Markdown, and spaces in tracked paths.
      9. Manifests: runs 'claude plugin validate' on the plugin and on the
         marketplace when the CLI can be found - on PATH, or the binary the
         VS Code extension ships. It is the only check that reads plugin.json
         the way the loader does, which is why it is no longer left to memory.

    The YAML checks are regex-based, not a real parser. They catch the
    structural mistakes that happen in practice; they do not prove a question
    set is valid YAML.

    Check 9 runs `claude plugin validate` itself. If the CLI cannot be found it
    warns rather than passing quietly - an unchecked manifest is not a clean one.

.PARAMETER SkipLinks
    Skip the link check (it reads every tracked Markdown file).

.PARAMETER SkipSecrets
    Skip the secret scan (it reads every tracked text file).

.PARAMETER ListingBudget
    Character budget to report the skill listing against. Defaults to 2000,
    which is 1% of a 200k context window. Raise it to match your model if
    `/context` reports something different.

.EXAMPLE
    pwsh -NoProfile -File .claude/skills/git-commit-conventions/scripts/Test-RepoConsistency.ps1

.OUTPUTS
    Exit code 0 = ok (warnings allowed), 1 = at least one error.
#>
[CmdletBinding()]
param(
    [switch]$SkipLinks,
    [switch]$SkipSecrets,
    [int]$ListingBudget = 2000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (git rev-parse --show-toplevel 2>$null)
if (-not $repo) { Write-Host 'Not inside a git repository.' -ForegroundColor Red; exit 1 }
$repo = $repo.Trim()
Push-Location $repo
try {
    $errors   = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    Write-Host "`nPlugin repo consistency check - $repo" -ForegroundColor Cyan
    Write-Host ('-' * 70)

    $tracked = @(git ls-files)
    if ($tracked.Count -eq 0) {
        Write-Host '[info] nothing tracked yet - checks run against the index only' -ForegroundColor DarkYellow
    }

    $pluginRoot = Join-Path $repo 'plugins/infrastructure-as-skills'

    # Parse a SKILL.md frontmatter into name/description.
    function Get-SkillFrontmatter {
        param([string]$Path)
        $raw = Get-Content -LiteralPath $Path -Raw
        $fm = [regex]::Match($raw, '(?s)\A---\r?\n(.*?)\r?\n---')
        if (-not $fm.Success) { return $null }
        $block = $fm.Groups[1].Value
        # description may wrap across lines; take everything up to the next top-level key.
        # .NET's (?m)$ matches before \n only, so a CRLF file would carry the \r into the name.
        $nameMatch = [regex]::Match($block, '(?m)^name:[ \t]*(\S[^\r\n]*?)[ \t]*\r?$')
        $descMatch = [regex]::Match($block, '(?sm)^description:[ \t]*(.+?)(?=\r?\n[A-Za-z_][A-Za-z0-9_-]*:|\z)')
        [pscustomobject]@{
            Name        = $nameMatch.Groups[1].Value
            Description = if ($descMatch.Success) { ($descMatch.Groups[1].Value -replace '\s+', ' ').Trim() } else { '' }
        }
    }

    # Every SKILL.md shipped in the plugin (repo-maintenance skills under
    # .claude/ are not part of the listing a consumer gets).
    $skillFiles = @()
    if (Test-Path -LiteralPath $pluginRoot) {
        $skillFiles = @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue)
    }

    # --- 1. secrets in tracked files -----------------------------------------
    if ($SkipSecrets) {
        Write-Host '[skip] secret scan'
    } else {
        $secretPatterns = @(
            @{ Name = 'private key block';  Pattern = '-----BEGIN (RSA |OPENSSH |EC |PGP )?PRIVATE KEY' }
            @{ Name = 'bearer token';       Pattern = '(?i)\bbearer\s+[A-Za-z0-9\-_\.=]{20,}' }
            @{ Name = 'JWT';                Pattern = '\beyJ[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,}\.' }
            # The value has to look like a credential, not like the next word in
            # a sentence: prose such as "anything else secret: deployment
            # outputs are readable" otherwise matches. So require a digit, a
            # symbol common in encoded secrets, or real length.
            @{ Name = 'assigned secret';    Pattern = '(?i)\b(password|passwd|pwd|secret|client_secret|api[_-]?key|access[_-]?key)\b\s*[:=]\s*["'']?(?=[^\s"''<>{}$]*(?:\d|[+/=_.\-]))[^\s"''<>{}$]{8,}|(?i)\b(password|passwd|pwd|secret|client_secret|api[_-]?key|access[_-]?key)\b\s*[:=]\s*["'']?[^\s"''<>{}$]{16,}' }
            @{ Name = 'Azure storage key';  Pattern = '(?i)AccountKey\s*=\s*[A-Za-z0-9+/=]{20,}' }
            @{ Name = 'GitHub token';       Pattern = '\bgh[pousr]_[A-Za-z0-9]{20,}' }
            @{ Name = 'remote URL w/ creds';Pattern = '(?i)https://[^\s/@:]+:[^\s/@]+@(github|dev\.azure)\.com' }
            @{ Name = 'connection string';  Pattern = '(?i)(mongodb|postgres(ql)?|mysql|amqps?)://[^\s:/@]+:[^\s/@]+@' }
            @{ Name = 'real subscription';  Pattern = '(?i)\bsubscription_id\s*[:=]\s*["'']?(?!0{8})[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' }
        )
        # Placeholders the skills legitimately contain. Applied to the matched
        # span, not the whole line, so a real secret beside the word "example"
        # is still caught.
        $placeholder = '(?i)(\{\{?\s*\w+\s*\}?\}|<[^>\r\n]{1,40}>|\$\{?\w+\}?|xxx+|\*\*\*+|REDACTED|PLACEHOLDER|CHANGEME|0{8}-0{4})'

        $textExt = @('.md', '.json', '.yml', '.yaml', '.ps1', '.sh', '.py', '.txt', '.env', '.ini', '.cfg', '.toml', '.tf', '.bicep')
        $candidates = @($tracked | Where-Object { $textExt -contains [System.IO.Path]::GetExtension($_).ToLowerInvariant() })

        $hits = [System.Collections.Generic.List[string]]::new()
        foreach ($f in $candidates) {
            if (-not (Test-Path -LiteralPath $f)) { continue }
            $lineNo = 0
            foreach ($line in (Get-Content -LiteralPath $f)) {
                $lineNo++
                foreach ($p in $secretPatterns) {
                    $m = [regex]::Match($line, $p.Pattern)
                    if ($m.Success) {
                        if ($m.Value -match $placeholder) { continue }
                        $hits.Add("${f}:${lineNo}  [$($p.Name)]")
                        break
                    }
                }
            }
        }

        if ($hits.Count -eq 0) {
            Write-Host "[ ok ] secret scan - $($candidates.Count) text file(s), nothing found" -ForegroundColor Green
        } else {
            Write-Host "[fail] secret scan - $($hits.Count) suspicious line(s)" -ForegroundColor Red
            foreach ($h in $hits) { Write-Host "         $h" -ForegroundColor DarkGray }
            $errors.Add("$($hits.Count) line(s) look like a committed credential. Replace with a placeholder and rotate the real value.")
        }
    }

    # --- 2. skill structure ---------------------------------------------------
    if ($skillFiles.Count -eq 0) {
        Write-Host '[info] no skills in the plugin yet' -ForegroundColor DarkYellow
    } else {
        $structureOk = $true
        foreach ($sf in $skillFiles) {
            $dirName = Split-Path -Leaf (Split-Path -Parent $sf.FullName)
            $rel = [System.IO.Path]::GetRelativePath($repo, $sf.FullName) -replace '\\', '/'
            $meta = Get-SkillFrontmatter -Path $sf.FullName

            if ($null -eq $meta) {
                Write-Host "[fail] $rel has no YAML frontmatter" -ForegroundColor Red
                $errors.Add("$rel has no frontmatter - name and description decide when the skill triggers.")
                $structureOk = $false
                continue
            }
            if ($meta.Name -ne $dirName) {
                Write-Host "[fail] $rel - name '$($meta.Name)' does not match directory '$dirName'" -ForegroundColor Red
                $errors.Add("$rel frontmatter name '$($meta.Name)' must equal its directory name '$dirName'.")
                $structureOk = $false
            }
            if ([string]::IsNullOrWhiteSpace($meta.Description)) {
                Write-Host "[fail] $rel has no description" -ForegroundColor Red
                $errors.Add("$rel needs a description - it is the triggering mechanism.")
                $structureOk = $false
            }
        }
        if ($structureOk) {
            Write-Host "[ ok ] skill structure - $($skillFiles.Count) skill(s)" -ForegroundColor Green
        }
    }

    # --- 3. the skill listing budget -----------------------------------------
    if ($skillFiles.Count -gt 0) {
        $cap = 1536
        $total = 0
        $overCap = [System.Collections.Generic.List[string]]::new()
        $rows = [System.Collections.Generic.List[string]]::new()

        foreach ($sf in $skillFiles) {
            $meta = Get-SkillFrontmatter -Path $sf.FullName
            if ($null -eq $meta) { continue }
            $len = $meta.Description.Length
            $total += $meta.Name.Length + $len
            $rows.Add(('         {0,-20} {1,5}' -f $meta.Name, $len))
            if ($len -gt $cap) { $overCap.Add("$($meta.Name) ($len chars)") }
        }

        if ($overCap.Count -gt 0) {
            Write-Host "[fail] $($overCap.Count) description(s) over the $cap-character cap" -ForegroundColor Red
            foreach ($o in $overCap) { Write-Host "         $o" -ForegroundColor DarkGray }
            $errors.Add("A description past $cap characters is truncated regardless of budget. Put the key use case first and cut the rest.")
        }

        $pct = [math]::Round(100 * $total / $ListingBudget, 0)
        $msg = "listing cost - $total chars across $($skillFiles.Count) skill(s), $pct% of a $ListingBudget budget"
        if ($total -gt $ListingBudget) {
            Write-Host "[warn] $msg" -ForegroundColor Yellow
            foreach ($r in $rows) { Write-Host $r -ForegroundColor DarkGray }
            $warnings.Add("The listing exceeds the assumed budget, so Claude Code may drop descriptions - which silently stops those skills from triggering. Check /context and /doctor, shorten descriptions, or move keyword terms into the single azure-resources description rather than adding skills.")
        } elseif ($pct -ge 70) {
            Write-Host "[warn] $msg" -ForegroundColor Yellow
            $warnings.Add("The listing is near its budget. Shorten descriptions before adding a skill - families are not skills and should not become them.")
        } else {
            Write-Host "[ ok ] $msg" -ForegroundColor Green
        }
    }

    # --- 4. plugin manifest paths --------------------------------------------
    $manifest = Join-Path $pluginRoot '.claude-plugin/plugin.json'
    if (-not (Test-Path -LiteralPath $manifest)) {
        Write-Host '[info] no plugin.json' -ForegroundColor DarkYellow
    } else {
        $json = $null
        try { $json = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json } catch {
            Write-Host "[fail] plugin.json does not parse: $($_.Exception.Message)" -ForegroundColor Red
            $errors.Add('plugin.json is not valid JSON, so the plugin cannot load.')
        }

        if ($null -ne $json) {
            $declared = @()
            if ($json.PSObject.Properties.Name -contains 'skills') { $declared = @($json.skills) }

            $missing = [System.Collections.Generic.List[string]]::new()
            foreach ($d in $declared) {
                $p = Join-Path $pluginRoot ($d -replace '^\./', '')
                if (-not (Test-Path -LiteralPath $p)) { $missing.Add($d) }
            }

            # Any directory directly under the plugin root that holds skills but
            # is not declared would not be scanned.
            $groupDirs = @(
                Get-ChildItem -LiteralPath $pluginRoot -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notin @('.claude-plugin', 'skills') } |
                    Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue).Count -gt 0 }
            )
            $undeclared = [System.Collections.Generic.List[string]]::new()
            foreach ($g in $groupDirs) {
                $norm = @($declared | ForEach-Object { ($_ -replace '^\./', '') -replace '/$', '' })
                if ($norm -notcontains $g.Name) { $undeclared.Add($g.Name) }
            }

            if ($missing.Count -eq 0 -and $undeclared.Count -eq 0) {
                Write-Host "[ ok ] plugin manifest - $($declared.Count) declared scan path(s), all present" -ForegroundColor Green
            }
            if ($missing.Count -gt 0) {
                Write-Host "[fail] $($missing.Count) declared skills path(s) do not exist" -ForegroundColor Red
                foreach ($m in $missing) { Write-Host "         $m" -ForegroundColor DarkGray }
                $errors.Add('A declared skills path that does not exist fails to load the whole plugin. Remove the entry, or add it in the same commit as the first skill in that group.')
            }
            if ($undeclared.Count -gt 0) {
                Write-Host "[fail] $($undeclared.Count) group director(ies) hold skills but are not declared" -ForegroundColor Red
                foreach ($u in $undeclared) { Write-Host "         $u/" -ForegroundColor DarkGray }
                $errors.Add("The skills/ scan is one level deep and does not recurse, so an undeclared group directory loads nothing. Add it to plugin.json's skills array.")
            }
        }
    }

    # --- 5. question sets -----------------------------------------------------
    $questionSets = @()
    if (Test-Path -LiteralPath $pluginRoot) {
        $questionSets = @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -ErrorAction SilentlyContinue |
            # Two shapes: a resource directory holding questions.yaml
            # (resources/<family>/<resource>/questions.yaml), and a set held by a
            # skill (core/iac-authoring/questions/deployment.yaml). Missing the
            # first shape makes every resource check pass vacuously.
            Where-Object {
                $p = $_.FullName -replace '\\', '/'
                $p -match '/questions/[^/]+\.ya?ml$' -or $p -match '/[^/]+/questions\.ya?ml$'
            })
    }

    if ($questionSets.Count -eq 0) {
        Write-Host '[info] no question sets yet' -ForegroundColor DarkYellow
    } else {
        $qErrors   = [System.Collections.Generic.List[string]]::new()
        $qWarnings = [System.Collections.Generic.List[string]]::new()
        $qCount    = 0

        foreach ($qs in $questionSets) {
            $rel = [System.IO.Path]::GetRelativePath($repo, $qs.FullName) -replace '\\', '/'
            $raw = Get-Content -LiteralPath $qs.FullName -Raw

            # A deployment-scoped set answers for the whole deployment and names
            # no resource, so the naming identifiers do not apply to it.
            $isDeployment = [regex]::IsMatch($raw, '(?m)^\s*scope:\s*deployment\s*$')

            if (-not $isDeployment) {
                $tfName = [regex]::Match($raw, '(?m)^\s*terraform:\s*"?([^"\r\n]+)"?\s*$')
                $bcName = [regex]::Match($raw, '(?m)^\s*bicep:\s*"?([^"\r\n]+)"?\s*$')
                $abbrev = [regex]::Match($raw, '(?m)^\s*abbreviation:\s*"?([^"\r\n]+)"?\s*$')

                if (-not $tfName.Success) { $qErrors.Add("$rel - naming.terraform not declared") }
                if (-not $bcName.Success) { $qErrors.Add("$rel - naming.bicep not declared") }
                if (-not $abbrev.Success) { $qErrors.Add("$rel - naming.abbreviation not declared; the Bicep side assembles the name from vars and has no other source for the prefix") }
                if ($bcName.Success -and $bcName.Groups[1].Value -match '^\s*\w+::') {
                    $qErrors.Add("$rel - naming.bicep carries a cloud prefix ('$($bcName.Groups[1].Value.Trim())'); the Bicep resource type takes none")
                }
                if ($tfName.Success -and $tfName.Groups[1].Value -notmatch '::') {
                    $qErrors.Add("$rel - naming.terraform is missing the '<Provider>::' prefix ('$($tfName.Groups[1].Value.Trim())')")
                }
            }

            # Per-entry structural rules. Split on the "- id:" boundaries, which
            # catch both group entries and question entries - a group carries
            # title: and questions: and has none of the per-question fields, so
            # it is skipped rather than reported as an incomplete question.
            $blocks = @([regex]::Split($raw, '(?m)^\s*-\s+id:\s*') | Select-Object -Skip 1)
            $questionBlocks = @($blocks | Where-Object {
                -not ([regex]::IsMatch($_, '(?m)^\s+title:') -and [regex]::IsMatch($_, '(?m)^\s+questions:'))
            })

            # Question ids must be unique within the set.
            $ids = @($questionBlocks | ForEach-Object { ([regex]::Match($_, '^(\S+)')).Groups[1].Value })
            $dupes = @($ids | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
            if ($dupes.Count -gt 0) {
                $qErrors.Add("$rel - duplicate question id(s): $($dupes -join ', '). Ids are referenced by pattern pre-answers and written to the spec.")
            }

            $qCount += $questionBlocks.Count

            foreach ($b in $questionBlocks) {
                $qid = ([regex]::Match($b, '^(\S+)')).Groups[1].Value
                if (-not [regex]::IsMatch($b, '(?m)^\s+ask:')) {
                    $qWarnings.Add("$rel - '$qid' has no ask, so there is no question to put to the user")
                }
                $hasDefault  = [regex]::IsMatch($b, '(?m)^\s+default:')
                $hasRequired = [regex]::IsMatch($b, '(?m)^\s+required:\s*true')
                # Inherited from the deployment set, so it needs no default of its own.
                $hasInherit  = [regex]::IsMatch($b, '(?m)^\s+from_deployment:')
                if ($hasDefault -and $hasRequired) {
                    $qErrors.Add("$rel - '$qid' sets both required: true and a default. A required question is one with no safe default.")
                }
                if ($hasInherit -and ($hasDefault -or $hasRequired)) {
                    $qErrors.Add("$rel - '$qid' sets from_deployment together with a default or required. The deployment answer is the default; a second one here is the ambiguity this field exists to remove.")
                }
                if (-not $hasDefault -and -not $hasRequired -and -not $hasInherit) {
                    $qWarnings.Add("$rel - '$qid' has neither a default, required: true, nor from_deployment, so it is unclear whether it gets asked")
                }
                if (-not [regex]::IsMatch($b, '(?m)^\s+why:')) {
                    $qWarnings.Add("$rel - '$qid' has no why. It is the only artefact that survives into a review.")
                }
                if (-not [regex]::IsMatch($b, '(?m)^\s+renders:')) {
                    $qWarnings.Add("$rel - '$qid' has no renders, so a review cannot map code back to this decision")
                }
            }
        }

        if ($qErrors.Count -eq 0) {
            Write-Host "[ ok ] question sets - $($questionSets.Count) file(s), $qCount question(s)" -ForegroundColor Green
        } else {
            Write-Host "[fail] question sets - $($qErrors.Count) problem(s)" -ForegroundColor Red
            foreach ($e in $qErrors) { Write-Host "         $e" -ForegroundColor DarkGray }
            $errors.Add("$($qErrors.Count) question-set error(s). The naming identifiers differ between targets and a wrong one renders a wrong name.")
        }
        if ($qWarnings.Count -gt 0) {
            Write-Host "[warn] question sets - $($qWarnings.Count) incomplete question(s)" -ForegroundColor Yellow
            foreach ($w in $qWarnings | Select-Object -First 15) { Write-Host "         $w" -ForegroundColor DarkGray }
            if ($qWarnings.Count -gt 15) { Write-Host "         ... and $($qWarnings.Count - 15) more" -ForegroundColor DarkGray }
            $warnings.Add('Questions missing why/renders, or with neither a default nor required. Judge whether the omission is intended.')
        }
    }

    # --- 6. routing coverage --------------------------------------------------
    if ($questionSets.Count -gt 0) {
        $routeIssues = [System.Collections.Generic.List[string]]::new()
        $families = @($questionSets | ForEach-Object { Split-Path -Parent (Split-Path -Parent $_.FullName) } | Sort-Object -Unique)

        # A resource family routes through routing.md and is not a skill - the
        # azure-resources skill is the single trigger for all of them. A question
        # set inside a skill (the deployment set in iac-authoring) routes through
        # that skill's SKILL.md.
        $azureResources = Join-Path $pluginRoot 'core/azure-resources/SKILL.md'
        $routerBody = if (Test-Path -LiteralPath $azureResources) { Get-Content -LiteralPath $azureResources -Raw } else { '' }

        foreach ($famDir in $families) {
            $famRel = [System.IO.Path]::GetRelativePath($repo, $famDir) -replace '\\', '/'
            $router = Join-Path $famDir 'routing.md'
            if (-not (Test-Path -LiteralPath $router)) { $router = Join-Path $famDir 'SKILL.md' }
            $routerLeaf = Split-Path -Leaf $router

            if (-not (Test-Path -LiteralPath $router)) {
                $routeIssues.Add("$famRel has question sets but neither routing.md nor SKILL.md to route to them")
                continue
            }

            # A family nobody routes into is unreachable however good its table is.
            if ($routerLeaf -eq 'routing.md') {
                $famName = Split-Path -Leaf $famDir
                if ($routerBody -notmatch [regex]::Escape("resources/$famName/routing.md")) {
                    $routeIssues.Add("core/azure-resources/SKILL.md never links resources/$famName/routing.md - the whole family is unreachable")
                }
            }

            $body = Get-Content -LiteralPath $router -Raw
            foreach ($qs in @($questionSets | Where-Object { (Split-Path -Parent (Split-Path -Parent $_.FullName)) -eq $famDir })) {
                # Every resource set is named questions.yaml, so the file name
                # alone matches any row; the resource directory is what identifies it.
                $token = if ($qs.Name -match '^questions\.ya?ml$') {
                    "$(Split-Path -Leaf (Split-Path -Parent $qs.FullName))/$($qs.Name)"
                } else {
                    "questions/$($qs.Name)"
                }
                if ($body -notmatch [regex]::Escape($token)) {
                    $routeIssues.Add("$famRel/$routerLeaf never mentions $token - the resource is unreachable")
                }
            }
            # Rows pointing at a question set that does not exist, in either
            # shape. The lookbehind keeps a path-qualified reference out - a link
            # to core/iac-authoring/questions/deployment.yaml names another
            # skill's set and is not a route into this family.
            foreach ($m in [regex]::Matches($body, '(?<![\w./-])questions/([A-Za-z0-9._-]+\.ya?ml)')) {
                $target = Join-Path $famDir (Join-Path 'questions' $m.Groups[1].Value)
                if (-not (Test-Path -LiteralPath $target)) {
                    $routeIssues.Add("$famRel/$routerLeaf routes to questions/$($m.Groups[1].Value), which does not exist")
                }
            }
            foreach ($m in [regex]::Matches($body, '(?<![\w./-])([a-z0-9][a-z0-9-]*)/questions\.ya?ml')) {
                $target = Join-Path $famDir (Join-Path $m.Groups[1].Value 'questions.yaml')
                if (-not (Test-Path -LiteralPath $target)) {
                    $routeIssues.Add("$famRel/$routerLeaf routes to $($m.Groups[1].Value)/questions.yaml, which does not exist")
                }
            }
        }

        if ($routeIssues.Count -eq 0) {
            Write-Host "[ ok ] routing - every question set reachable from its routing table" -ForegroundColor Green
        } else {
            Write-Host "[warn] routing - $($routeIssues.Count) issue(s)" -ForegroundColor Yellow
            foreach ($r in $routeIssues) { Write-Host "         $r" -ForegroundColor DarkGray }
            $warnings.Add('A routing row pointing at a missing file is the one failure this repo cannot detect at runtime - the skill reads a missing file mid-run.')
        }
    }

    # --- 7. no CLAUDE.md inside the plugin -----------------------------------
    if (Test-Path -LiteralPath $pluginRoot) {
        $strays = @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -Filter 'CLAUDE.md' -ErrorAction SilentlyContinue)
        if ($strays.Count -eq 0) {
            Write-Host '[ ok ] no CLAUDE.md inside the plugin directory' -ForegroundColor Green
        } else {
            Write-Host "[fail] $($strays.Count) CLAUDE.md inside the plugin directory" -ForegroundColor Red
            foreach ($s in $strays) { Write-Host "         $([System.IO.Path]::GetRelativePath($repo, $s.FullName))" -ForegroundColor DarkGray }
            $errors.Add('A CLAUDE.md in the plugin is not loaded as context and claude plugin validate warns about it. Instructions that must reach Claude belong in a skill; repo guidance belongs in the root CLAUDE.md.')
        }
    }

    # --- 8. relative links + spaces in paths ---------------------------------
    if ($SkipLinks) {
        Write-Host '[skip] relative links'
    } else {
        $mdFiles = @($tracked | Where-Object { $_ -like '*.md' })
        $broken = [System.Collections.Generic.List[string]]::new()

        foreach ($md in $mdFiles) {
            if (-not (Test-Path -LiteralPath $md)) { continue }
            $dir = Split-Path -Parent $md
            if ([string]::IsNullOrEmpty($dir)) { $dir = '.' }

            # Strip fenced blocks and inline code: a skill legitimately shows
            # "](target)" as an example, which is not a link.
            $text = Get-Content -LiteralPath $md -Raw
            $text = [regex]::Replace($text, '(?s)```.*?```', '')
            $text = [regex]::Replace($text, '`[^`\r\n]*`', '')

            foreach ($m in [regex]::Matches($text, '\]\(([^)]+)\)')) {
                $target = $m.Groups[1].Value.Trim()
                if ($target -match '^(https?:|mailto:|#)') { continue }
                $target = ($target -split '\s+')[0]
                $target = ($target -split '#')[0]
                if ([string]::IsNullOrWhiteSpace($target)) { continue }
                $target = [uri]::UnescapeDataString($target)
                if (-not (Test-Path -LiteralPath (Join-Path $dir $target))) { $broken.Add("$md  ->  $target") }
            }
        }

        if ($broken.Count -eq 0) {
            Write-Host "[ ok ] relative links - $($mdFiles.Count) Markdown file(s), none broken" -ForegroundColor Green
        } else {
            Write-Host "[fail] relative links - $($broken.Count) broken" -ForegroundColor Red
            foreach ($b in $broken) { Write-Host "         $b" -ForegroundColor DarkGray }
            $errors.Add("$($broken.Count) broken relative link(s) in tracked Markdown.")
        }
    }

    $spaced = @($tracked | Where-Object { $_ -match ' ' })
    if ($spaced.Count -eq 0) {
        Write-Host '[ ok ] no spaces in tracked paths' -ForegroundColor Green
    } else {
        Write-Host "[fail] $($spaced.Count) tracked path(s) contain a space" -ForegroundColor Red
        foreach ($s in $spaced) { Write-Host "         $s" -ForegroundColor DarkGray }
        $errors.Add("$($spaced.Count) tracked path(s) contain a space (breaks the shell and PowerShell helpers).")
    }

    # --- 9. the authoritative manifest check ---------------------------------
    # `claude plugin validate` is the only check that reads the manifest the way
    # the loader does. The CLI is often not on PATH - the VS Code extension ships
    # its own binary - so look there before reporting it as unchecked.
    # StrictMode: a missing command returns nothing, and .Source on nothing throws.
    $cli = $null
    $cmd = @(Get-Command claude -ErrorAction SilentlyContinue)
    if ($cmd.Count -gt 0 -and $cmd[0].PSObject.Properties['Source']) { $cli = $cmd[0].Source }
    if (-not $cli) {
        $extGlobs = @(
            "$env:USERPROFILE\.vscode\extensions\anthropic.claude-code-*\resources\native-binary\claude.exe",
            "$env:USERPROFILE\.vscode-insiders\extensions\anthropic.claude-code-*\resources\native-binary\claude.exe",
            "$env:USERPROFILE\.cursor\extensions\anthropic.claude-code-*\resources\native-binary\claude.exe",
            "$env:USERPROFILE\.claude\local\claude*",
            "$env:APPDATA\npm\claude.cmd"
        )
        foreach ($g in $extGlobs) {
            $hit = @(Get-Item -Path $g -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1)
            if ($hit.Count -gt 0) { $cli = $hit[0].FullName; break }
        }
    }

    if (-not $cli) {
        Write-Host "[warn] manifests - 'claude' not found, so the authoritative check did not run" -ForegroundColor Yellow
        $warnings.Add("claude plugin validate could not run - the CLI is not on PATH and no bundled binary was found. It is the only check that reads plugin.json the way the loader does.")
    } else {
        $out = & $cli plugin validate $pluginRoot 2>&1
        $code = $LASTEXITCODE
        $mOut = & $cli plugin validate $repo 2>&1
        $mCode = $LASTEXITCODE

        if ($code -eq 0 -and $mCode -eq 0) {
            Write-Host "[ ok ] manifests - plugin and marketplace validate" -ForegroundColor Green
            # Advice lines do not change the verdict, but they are worth seeing.
            foreach ($line in @($out + $mOut)) {
                if ("$line" -match '^\s*❯') { Write-Host "       $line" -ForegroundColor DarkGray }
            }
        } else {
            Write-Host '[fail] manifests - claude plugin validate reported a problem' -ForegroundColor Red
            foreach ($line in @($out + $mOut)) { Write-Host "         $line" -ForegroundColor DarkGray }
            $errors.Add('claude plugin validate failed. A manifest the loader rejects means the plugin does not load at all.')
        }
    }

    Write-Host ('-' * 70)

    foreach ($w in $warnings) { Write-Host "  ! $w" -ForegroundColor Yellow }
    foreach ($e in $errors)   { Write-Host "  X $e" -ForegroundColor Red }

    if ($errors.Count -gt 0) {
        Write-Host "`n$($errors.Count) error(s) - fix before committing.`n" -ForegroundColor Red
        exit 1
    }
    if ($warnings.Count -gt 0) {
        Write-Host "`nNo errors, $($warnings.Count) warning(s) to judge.`n" -ForegroundColor Yellow
        exit 0
    }
    Write-Host "`nAll checks passed.`n" -ForegroundColor Green
    exit 0
}
finally {
    Pop-Location
}
