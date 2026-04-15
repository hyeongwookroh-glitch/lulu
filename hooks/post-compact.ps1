# PostCompact hook — re-inject critical context after context compaction

$RepoRoot = Split-Path -Parent $PSScriptRoot
$LuluMemory = if ($env:LULU_MEMORY_DIR) { $env:LULU_MEMORY_DIR } else { "$env:USERPROFILE\Documents\Lulu_Memory" }
$SessionDir = "$LuluMemory\session_notes\lulu"
$MemoryDir = "$RepoRoot\.claude\memory"

Write-Output "=== [Lulu PostCompact Recovery] ==="
Write-Output ""

# 1. Core persona
Write-Output "## Core Persona"
Write-Output ""
Get-Content "$RepoRoot\CLAUDE.md"
Write-Output ""

# 2. Checkpoint (working state)
$checkpointPaths = @("$LuluMemory\checkpoint.md", "$MemoryDir\checkpoint.md")
foreach ($cp in $checkpointPaths) {
    if (Test-Path $cp) {
        Write-Output "## Checkpoint (recovered --- act on this IMMEDIATELY)"
        Write-Output ""
        Get-Content $cp
        Write-Output ""
        Remove-Item $cp
        break
    }
}

# 3. Session notes (today)
$today = Get-Date -Format "yyyy-MM-dd"
$todayFile = "$SessionDir\$today.md"
if (Test-Path $todayFile) {
    Write-Output "## Session Notes ($today)"
    Write-Output ""
    Get-Content $todayFile
    Write-Output ""
}

# 4. Memory index
if (Test-Path "$MemoryDir\MEMORY.md") {
    Write-Output "## Memory Index"
    Write-Output ""
    Get-Content "$MemoryDir\MEMORY.md"
    Write-Output ""
}

Write-Output "=== [PostCompact Recovery Complete] ==="
