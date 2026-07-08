#Requires -Version 5.1
<#
  watch.ps1 — Vigia a pasta Base\ e registra novos arquivos no Supabase (ingest_log).
  Deixe rodando numa janela do PowerShell. Quando novo PDF chegar, abre Claude Code
  na sessão SeniorsBI e eu processo automaticamente.

  Uso: .\watch.ps1
#>
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path $MyInvocation.MyCommand.Path

# Carregar .env
$envFile = Join-Path (Split-Path $scriptDir) ".env"
if (-not (Test-Path $envFile)) {
    Write-Host "ERRO: .env não encontrado. Copie .env.example para .env e preencha." -ForegroundColor Red
    exit 1
}
Get-Content $envFile | Where-Object { $_ -match "^\s*([^#\s][^=]*)=(.*)$" } | ForEach-Object {
    $k,$v = $_ -split "=",2; [System.Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim())
}

$BASE_PATH = [System.Environment]::GetEnvironmentVariable("BASE_PATH")
$SB_URL    = [System.Environment]::GetEnvironmentVariable("SUPABASE_URL")
$SB_KEY    = [System.Environment]::GetEnvironmentVariable("SUPABASE_PUBLISHABLE_KEY")

if (-not (Test-Path $BASE_PATH)) { New-Item -ItemType Directory -Force $BASE_PATH | Out-Null }

function Push-IngestLog($arquivo, $status = "pendente") {
    $body = @{ arquivo = $arquivo; status = $status } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "$SB_URL/rest/v1/ingest_log" `
            -Method POST -Body $body -ContentType "application/json" `
            -Headers @{ "apikey" = $SB_KEY; "Authorization" = "Bearer $SB_KEY"; "Prefer" = "return=minimal" }
    } catch { Write-Host "  [WARN] Supabase unavailable: $_" -ForegroundColor Yellow }
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $BASE_PATH
$watcher.IncludeSubdirectories = $true
$watcher.Filter = "*.*"
$watcher.EnableRaisingEvents = $true

$onCreated = Register-ObjectEvent $watcher "Created" -Action {
    $f = $Event.SourceEventArgs.FullPath
    $nome = $Event.SourceEventArgs.Name
    Write-Host "$(Get-Date -Format 'HH:mm:ss') NOVO ARQUIVO: $nome" -ForegroundColor Cyan
    Push-IngestLog $f "pendente"
    Write-Host "  -> Registrado no Supabase. Abra Claude Code para processar." -ForegroundColor Green
}

Write-Host "Vigiando: $BASE_PATH" -ForegroundColor Green
Write-Host "Pressione Ctrl+C para parar.`n"

try { while ($true) { Start-Sleep 5 } }
finally {
    Unregister-Event -SourceIdentifier $onCreated.Name
    $watcher.Dispose()
    Write-Host "Watcher encerrado."
}
