# PreCompact hook — force checkpoint write before context compression

$LuluMemory = if ($env:LULU_MEMORY_DIR) { $env:LULU_MEMORY_DIR } else { "$env:USERPROFILE\Documents\Lulu_Memory" }
$Checkpoint = "$LuluMemory\checkpoint.md"

Write-Output "=== [Lulu PreCompact] ==="
Write-Output ""
Write-Output "Context compaction imminent."
Write-Output ""

if (Test-Path $Checkpoint) {
    Write-Output "## Previous Checkpoint (stale --- overwrite)"
    Get-Content $Checkpoint
    Write-Output ""
}

$now = Get-Date -Format "yyyy-MM-dd HH:mm"
Write-Output "MANDATORY: Write checkpoint BEFORE any other response."
Write-Output "Path: $Checkpoint"
Write-Output ""
Write-Output "Format:"
Write-Output '```'
Write-Output "# Checkpoint --- $now"
Write-Output "## Active Task"
Write-Output "{what you are currently doing}"
Write-Output "## Working State"
Write-Output "{key decisions made, files modified, blockers}"
Write-Output "## Next Step"
Write-Output "{immediate next action after recovery}"
Write-Output '```'
Write-Output ""
Write-Output "=== [Write checkpoint FIRST, then continue] ==="
