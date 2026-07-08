#Requires -Version 5.1
<#
  push-mes.ps1 — Envia dados de um mês (a partir de data\meses\AAAA-MM.json) para o Supabase.
  Chamado pelo Claude Code após extrair os números dos PDFs.

  Uso: .\push-mes.ps1 -Slug 2026-06
#>
param([Parameter(Mandatory)][string]$Slug)
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path $MyInvocation.MyCommand.Path

$envFile = Join-Path (Split-Path $scriptDir) ".env"
Get-Content $envFile | Where-Object { $_ -match "^\s*([^#\s][^=]*)=(.*)$" } | ForEach-Object {
    $k,$v = $_ -split "=",2; [System.Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim())
}
$URL = [System.Environment]::GetEnvironmentVariable("SUPABASE_URL")
$KEY = [System.Environment]::GetEnvironmentVariable("SUPABASE_SERVICE_ROLE_KEY")
if (-not $KEY) { $KEY = [System.Environment]::GetEnvironmentVariable("SUPABASE_PUBLISHABLE_KEY") }

$hdrs = @{ "apikey" = $KEY; "Authorization" = "Bearer $KEY"; "Content-Type" = "application/json"; "Prefer" = "resolution=merge-duplicates,return=minimal" }

function SB-Upsert($table, $obj) {
    $body = ($obj | ConvertTo-Json -Depth 10 -Compress)
    Invoke-RestMethod -Uri "$URL/rest/v1/$table" -Method POST -Body $body -Headers $hdrs | Out-Null
}

function HM-ToMin($hm) {
    if (-not $hm -or $hm -eq "0:00") { return 0 }
    $p = $hm -split ":"
    return [int]$p[0] * 60 + [int]$p[1]
}

$dataDir = Join-Path (Split-Path $scriptDir) "data"
$mesFile = Join-Path $dataDir "meses\$Slug.json"
if (-not (Test-Path $mesFile)) { Write-Host "ERRO: $mesFile não encontrado." -ForegroundColor Red; exit 1 }

$mes = Get-Content $mesFile -Encoding UTF8 | ConvertFrom-Json
Write-Host "Enviando $Slug ($($mes.competencia)) para Supabase..." -ForegroundColor Cyan

# 1. Mês
$totalChamados = 0
if ($mes.clientesTickets) {
    $mes.clientesTickets.PSObject.Properties | ForEach-Object { $totalChamados += [int]$_.Value }
}
SB-Upsert "meses" @{ slug = $Slug; competencia = $mes.competencia; total_chamados = $totalChamados; fonte = "manual" }
Write-Host "  meses OK"

# 2. Recursos
if ($mes.recursos) {
    $mes.recursos | ForEach-Object {
        SB-Upsert "recursos" @{
            mes_slug = $Slug; nome = $_.nome; nivel = $_.nivel; equipe = $_.equipe
            cap_minutos    = (HM-ToMin ($_.cap.ToString() + ":00"))
            trab_minutos   = (HM-ToMin $_.trab)
            avulsa_minutos = (HM-ToMin $_.avulsa)
        }
    }
    Write-Host "  recursos OK ($($mes.recursos.Count))"
}

# 3. Clientes (horas + tickets)
if ($mes.clientesHoras) {
    $mes.clientesHoras.PSObject.Properties | ForEach-Object {
        $cli = $_.Name; $hm = $_.Value
        $tick = 0
        if ($mes.clientesTickets -and $mes.clientesTickets.$cli) { $tick = [int]$mes.clientesTickets.$cli }
        SB-Upsert "clientes" @{ mes_slug = $Slug; nome = $cli; horas_minutos = (HM-ToMin $hm); chamados = $tick }
    }
    Write-Host "  clientes OK"
}

# 4. Skills (uma vez — idempotente)
$skillsFile = Join-Path $dataDir "skills.json"
if (Test-Path $skillsFile) {
    $sk = Get-Content $skillsFile -Encoding UTF8 | ConvertFrom-Json
    $sk.skills.PSObject.Properties | ForEach-Object {
        $skill = $_.Name
        $_.Value.PSObject.Properties | ForEach-Object {
            SB-Upsert "skills" @{ tecnico = $_.Name; skill = $skill; nivel = [int]$_.Value }
        }
    }
    Write-Host "  skills OK"
}

# 5. Premissas (uma vez)
$premFile = Join-Path $dataDir "premissas.json"
if (Test-Path $premFile) {
    $pr = Get-Content $premFile -Encoding UTF8 | ConvertFrom-Json
    $pr.clientes | ForEach-Object {
        SB-Upsert "premissas" @{ cliente = $_.nome; franquia_horas = [int]$_.franquia; valor_mensal = [decimal]$_.valorMensal }
    }
    Write-Host "  premissas OK"
}

# 6. SLA
$slaFile = Join-Path $dataDir "sla.json"
if (Test-Path $slaFile) {
    $sla = Get-Content $slaFile -Encoding UTF8 | ConvertFrom-Json
    $slaM = $sla | Where-Object { $_.mes -eq $Slug }
    if ($slaM) {
        SB-Upsert "sla" @{
            mes_slug       = $Slug
            tma_minutos    = [int]($slaM.tma * 60)
            tmr_minutos    = [int]($slaM.tmr * 60)
            dentro_sla_pct = [int]$slaM.dentroSLA
            chamados_sla   = [int]$slaM.chamadosSLA
            chamados_fora  = [int]$slaM.chamadosFora
        }
        Write-Host "  sla OK"
    }
}

# 7. Satisfação
$satFile = Join-Path $dataDir "satisfacao.json"
if (Test-Path $satFile) {
    $sat = Get-Content $satFile -Encoding UTF8 | ConvertFrom-Json
    $satM = $sat | Where-Object { $_.mes -eq $Slug }
    if ($satM) {
        SB-Upsert "satisfacao" @{ mes_slug = $Slug; csat = [int]$satM.csat; nps = [int]$satM.nps; avaliacoes = [int]$satM.avaliacoes }
        Write-Host "  satisfacao OK"
    }
}

Write-Host "Concluído: $Slug carregado no Supabase." -ForegroundColor Green
