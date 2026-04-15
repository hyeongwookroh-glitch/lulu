# PostToolUseFailure hook — track consecutive tool errors, warn on diminishing returns

$AgentName = "lulu"
$ErrorFile = "$env:TEMP\${AgentName}_consecutive_errors.txt"

$Count = 0
if (Test-Path $ErrorFile) {
    $Count = [int](Get-Content $ErrorFile -ErrorAction SilentlyContinue)
}
$Count++
$Count | Out-File -FilePath $ErrorFile -NoNewline

if ($Count -ge 3) {
    Write-Output ""
    Write-Output "⚠️ $Count consecutive tool errors. You may be repeating the same approach."
    Write-Output "Try a different method or re-analyze the problem."
    Write-Output ""
}
