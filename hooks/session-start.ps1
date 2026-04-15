# SessionStart hook — load previous session context before first response

$RepoRoot = Split-Path -Parent $PSScriptRoot
$LuluMemory = if ($env:LULU_MEMORY_DIR) { $env:LULU_MEMORY_DIR } else { "$env:USERPROFILE\Documents\Lulu_Memory" }
$SessionDir = "$LuluMemory\session_notes\lulu"
$MemoryDir = "$RepoRoot\.claude\memory"

Write-Output "=== [Lulu Session Startup] ==="
Write-Output ""

# Ensure session note directory exists
if (!(Test-Path $SessionDir)) { New-Item -ItemType Directory -Path $SessionDir -Force | Out-Null }

# Session notes - most recent first, check Pending
Write-Output "## Session Notes"
Write-Output ""

$HasPending = $false
$files = Get-ChildItem "$SessionDir\*.md" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3

foreach ($f in $files) {
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match "### Pending") {
        Write-Output "### $($f.Name) --- HAS PENDING"
        $lines = Get-Content $f.FullName
        $show = $false
        $count = 0
        foreach ($line in $lines) {
            if ($line -match "^### Pending") { $show = $true }
            if ($show) {
                Write-Output $line
                $count++
                if ($count -ge 20) { break }
            }
        }
        Write-Output ""
        $HasPending = $true
    } else {
        Write-Output "### $($f.Name) --- no pending items"
    }
}

if ($HasPending) {
    Write-Output "Pending items found above. Address before new work."
    Write-Output ""
}

# Memory index
if (Test-Path "$MemoryDir\MEMORY.md") {
    Write-Output "## Memory Index"
    Write-Output ""
    Get-Content "$MemoryDir\MEMORY.md"
    Write-Output ""
}

Write-Output "=== [Session Startup Complete] ==="
