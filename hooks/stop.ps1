# Stop hook — mark session end in today's notes

$LuluMemory = if ($env:LULU_MEMORY_DIR) { $env:LULU_MEMORY_DIR } else { "$env:USERPROFILE\Documents\Lulu_Memory" }
$SessionDir = "$LuluMemory\session_notes\lulu"
$today = Get-Date -Format "yyyy-MM-dd"
$SessionFile = "$SessionDir\$today.md"

if (Test-Path $SessionFile) {
    $now = Get-Date -Format "HH:mm"
    Add-Content $SessionFile ""
    Add-Content $SessionFile "---"
    Add-Content $SessionFile "_Session ended: ${now}_"
}
