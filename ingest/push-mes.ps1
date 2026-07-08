#Requires -Version 5.1
param([Parameter(Mandatory)][string]$Slug)

# Carregar .env
$envFile = Join-Path (Split-Path (Split-Path $MyInvocation.MyCommand.Path)) ".env"
Get-Content $envFile -Encoding UTF8 | Where-Object { $_ -match "^\s*([^#\s][^=]*)=(.*)" } | ForEach-Object {
    $k,$v = ($_ -split "=",2); [System.Environment]::SetEnvironmentVariable($k.Trim(),$v.Trim())
}
$URL = [System.Environment]::GetEnvironmentVariable("SUPABASE_URL")
$KEY = [System.Environment]::GetEnvironmentVariable("SUPABASE_SERVICE_ROLE_KEY")
if (-not $KEY) { $KEY = [System.Environment]::GetEnvironmentVariable("SUPABASE_PUBLISHABLE_KEY") }
$hdrs = @{
    "apikey" = $KEY
    "Authorization" = "Bearer $KEY"
    "Content-Type" = "application/json; charset=utf-8"
    "Prefer" = "resolution=merge-duplicates,return=minimal"
}

function HM($hm) {
    if (-not $hm -or $hm -eq "0:00") { return 0 }
    $p = "$hm" -split ":"
    return [int]$p[0] * 60 + [int]$p[1]
}

function Post($table, $row, $onConflict = "") {
    $uri = "$URL/rest/v1/$table"
    if ($onConflict) { $uri += "?on_conflict=$onConflict" }
    $json = $row | ConvertTo-Json -Depth 5 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    try {
        Invoke-RestMethod -Uri $uri -Method POST -Body $bytes -Headers $hdrs | Out-Null
    } catch {
        Write-Host "    FALHA [$table]: $($_.ErrorDetails.Message) | row: $json" -ForegroundColor Yellow
    }
}

$dataDir = Join-Path (Split-Path (Split-Path $MyInvocation.MyCommand.Path)) "data"
$mesFile = Join-Path $dataDir "meses\$Slug.json"
if (-not (Test-Path $mesFile)) { Write-Host "ERRO: $mesFile nao encontrado." -ForegroundColor Red; exit 1 }

$mes = Get-Content $mesFile -Encoding UTF8 | ConvertFrom-Json
Write-Host "Enviando $Slug ($($mes.competencia))..." -ForegroundColor Cyan

# ── 1. meses ──────────────────────────────────────────────────────
$totalChamados = 0
if ($mes.clientesTickets) {
    $mes.clientesTickets.PSObject.Properties | ForEach-Object { $totalChamados += [int]$_.Value }
}
$rowMes = [ordered]@{}
$rowMes["slug"] = $Slug
$rowMes["competencia"] = $mes.competencia
$rowMes["total_chamados"] = $totalChamados
$rowMes["fonte"] = "manual"
Post "meses" $rowMes
Write-Host "  meses OK"

# ── 2. recursos ───────────────────────────────────────────────────
if ($mes.recursos) {
    foreach ($r in $mes.recursos) {
        $capMin = [int]$r.cap * 60
        $trabMin = HM $r.trab
        $avulsaMin = HM $r.avulsa
        $rowR = [ordered]@{}
        $rowR["mes_slug"] = $Slug
        $rowR["nome"] = "$($r.nome)"
        $rowR["nivel"] = "$($r.nivel)"
        $rowR["equipe"] = "$($r.equipe)"
        $rowR["cap_minutos"] = $capMin
        $rowR["trab_minutos"] = $trabMin
        $rowR["avulsa_minutos"] = $avulsaMin
        Post "recursos" $rowR "mes_slug,nome"
    }
    Write-Host "  recursos OK ($($mes.recursos.Count))"
}

# ── 3. clientes ───────────────────────────────────────────────────
if ($mes.clientesHoras) {
    foreach ($prop in $mes.clientesHoras.PSObject.Properties) {
        $cli = $prop.Name
        $hmVal = $prop.Value
        $tickVal = 0
        if ($mes.clientesTickets -and $mes.clientesTickets.$cli) {
            $tickVal = [int]$mes.clientesTickets.$cli
        }
        $rowC = [ordered]@{}
        $rowC["mes_slug"] = $Slug
        $rowC["nome"] = "$cli"
        $rowC["horas_minutos"] = HM $hmVal
        $rowC["chamados"] = $tickVal
        Post "clientes" $rowC "mes_slug,nome"
    }
    Write-Host "  clientes OK"
}

# ── 4. premissas (uma vez, idempotente) ──────────────────────────
$premFile = Join-Path $dataDir "premissas.json"
if (Test-Path $premFile) {
    $pr = Get-Content $premFile -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $pr.clientes) {
        $rowP = [ordered]@{}
        $rowP["cliente"] = "$($p.nome)"
        $rowP["franquia_horas"] = [int]$p.franquia
        $rowP["valor_mensal"] = [decimal]$p.valorMensal
        Post "premissas" $rowP
    }
    Write-Host "  premissas OK"
}

# ── 5. skills (uma vez, idempotente) ─────────────────────────────
$skillsFile = Join-Path $dataDir "skills.json"
if (Test-Path $skillsFile) {
    $sk = Get-Content $skillsFile -Encoding UTF8 | ConvertFrom-Json
    foreach ($skillProp in $sk.skills.PSObject.Properties) {
        $skillName = $skillProp.Name
        foreach ($tecProp in $skillProp.Value.PSObject.Properties) {
            $rowS = [ordered]@{}
            $rowS["tecnico"] = "$($tecProp.Name)"
            $rowS["skill"] = "$skillName"
            $rowS["nivel"] = [int]$tecProp.Value
            Post "skills" $rowS "tecnico,skill"
        }
    }
    Write-Host "  skills OK"
}

# ── 6. SLA ────────────────────────────────────────────────────────
$slaFile = Join-Path $dataDir "sla.json"
if (Test-Path $slaFile) {
    $slaData = Get-Content $slaFile -Encoding UTF8 | ConvertFrom-Json
    $slaM = $slaData | Where-Object { $_.mes -eq $Slug }
    if ($slaM) {
        $rowSla = [ordered]@{}
        $rowSla["mes_slug"] = $Slug
        $rowSla["tma_minutos"] = [int]([double]$slaM.tma * 60)
        $rowSla["tmr_minutos"] = [int]([double]$slaM.tmr * 60)
        $rowSla["dentro_sla_pct"] = [int]$slaM.dentroSLA
        $rowSla["chamados_sla"] = [int]$slaM.chamadosSLA
        $rowSla["chamados_fora"] = [int]$slaM.chamadosFora
        Post "sla" $rowSla
        Write-Host "  sla OK"
    }
}

# ── 7. Satisfação ─────────────────────────────────────────────────
$satFile = Join-Path $dataDir "satisfacao.json"
if (Test-Path $satFile) {
    $satData = Get-Content $satFile -Encoding UTF8 | ConvertFrom-Json
    $satM = $satData | Where-Object { $_.mes -eq $Slug }
    if ($satM) {
        $rowSat = [ordered]@{}
        $rowSat["mes_slug"] = $Slug
        $rowSat["csat"] = [int]$satM.csat
        $rowSat["nps"] = [int]$satM.nps
        $rowSat["avaliacoes"] = [int]$satM.avaliacoes
        Post "satisfacao" $rowSat
        Write-Host "  satisfacao OK"
    }
}

Write-Host "Concluido: $Slug" -ForegroundColor Green
