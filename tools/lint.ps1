<#
.SYNOPSIS
    Run luacheck over the addon locally, matching CI (.github/workflows/lint.yml).

.DESCRIPTION
    There is no Lua/luacheck install on Windows, so this wraps the linter in a
    Docker container (the pipelinecomponents/luacheck image). The repo's
    .luacheckrc (std = "lua51") drives the rules, so results match the CI run.

    First run pulls the image (~a few MB); afterwards it is cached and instant.

.PARAMETER Paths
    Files/dirs to check, relative to the repo root. Defaults to "." (whole repo).

.EXAMPLE
    tools\lint.ps1                 # lint everything, same as CI
    tools\lint.ps1 HealerManaBars.lua
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Paths = @('.')
)

$ErrorActionPreference = 'Stop'

# Run from the repo root regardless of the caller's working directory, so the
# volume mount and the .luacheckrc lookup always resolve to the project.
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error 'docker not found on PATH. Install Docker Desktop, or use the standalone luacheck.exe (see AGENTS.md → Linting).'
    }
    # Fail early with a clear message if the daemon is not running, instead of a
    # cryptic "npipe" connect error from `docker run`.
    docker info --format '{{.ServerVersion}}' *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Docker daemon is not reachable. Start Docker Desktop and try again.'
    }

    docker run --rm -v "${repo}:/code" -w /code `
        --entrypoint luacheck pipelinecomponents/luacheck @Paths

    # Surface luacheck's exit code to the caller / CI (1 = warnings, 2 = errors).
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
