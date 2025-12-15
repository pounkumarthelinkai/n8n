# PowerShell script to monitor workflow execution
# Run this after manually triggering the workflow in GitHub

Write-Host "=== Monitoring n8n CI/CD Workflow ===" -ForegroundColor Cyan
Write-Host ""

# Check DEV VPS Export Status
Write-Host "Checking DEV VPS export status..." -ForegroundColor Yellow
$devExport = ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118 "ls -t /srv/n8n/migration-temp/n8n_export_*.tar.gz 2>/dev/null | head -1"
if ($devExport) {
    Write-Host "✓ Latest export package: $devExport" -ForegroundColor Green
    $exportSize = ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118 "du -h $devExport | cut -f1"
    Write-Host "  Size: $exportSize" -ForegroundColor Gray
} else {
    Write-Host "⚠ No export packages found yet" -ForegroundColor Yellow
}

Write-Host ""

# Check DEV Export Logs
Write-Host "Latest DEV export log:" -ForegroundColor Yellow
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118 "tail -5 /srv/n8n/logs/export_*.log 2>/dev/null | tail -5" | ForEach-Object {
    Write-Host "  $_" -ForegroundColor Gray
}

Write-Host ""

# Check PROD VPS Import Status
Write-Host "Checking PROD VPS import status..." -ForegroundColor Yellow
$prodImport = ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144 "ls -t /srv/n8n/logs/import_*.log 2>/dev/null | head -1"
if ($prodImport) {
    Write-Host "✓ Latest import log found" -ForegroundColor Green
    Write-Host "Latest PROD import log:" -ForegroundColor Yellow
    ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144 "tail -5 $prodImport" | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Gray
    }
} else {
    Write-Host "⚠ No import logs found yet (import may not have started)" -ForegroundColor Yellow
}

Write-Host ""

# Check PROD n8n Status
Write-Host "Checking PROD n8n container status..." -ForegroundColor Yellow
$prodStatus = ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144 "docker ps | grep n8n"
if ($prodStatus -match "healthy|Up") {
    Write-Host "✓ PROD n8n is running" -ForegroundColor Green
} else {
    Write-Host "⚠ PROD n8n status unclear" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Monitoring Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Check GitHub Actions for workflow status" -ForegroundColor White
Write-Host "2. Review logs if any errors occurred" -ForegroundColor White
Write-Host "3. Verify workflows in PROD n8n UI: https://n8n-prod.thelinkai.com" -ForegroundColor White

