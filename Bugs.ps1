<#
.SYNOPSIS
    Green Store - Assistente de Inicializacao de Jogos

.DESCRIPTION
    Ferramenta oficial da Green Store para atualizar e corrigir arquivos de inicializacao.
#>

param(
    [string]$IdJogo
)

# Forca o console a usar UTF8 (mantido por seguranca estrutural, mas sem acentos no texto)
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Green Store - Assistente de Jogos Steam"

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  +================================================================+" -ForegroundColor Green
    Write-Host "  |                       GREEN STORE AUTOMATION                   |" -ForegroundColor Green
    Write-Host "  |             Assistente de Atualizacao e Correcao de Jogos      |" -ForegroundColor Green
    Write-Host "  |                                                                |" -ForegroundColor Green
    Write-Host "  |         Baixando dados diretamente do Servidor Green Keys      |" -ForegroundColor DarkGreen
    Write-Host "  +================================================================+" -ForegroundColor Green
    Write-Host ""
}

function Write-ProgressBar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Label,
        [int]$Width = 40,
        [ConsoleColor]$Color = "Green"
    )

    $percent = if ($Total -gt 0) { [math]::Round(($Current / $Total) * 100) } else { 0 }
    $filled = [math]::Floor(($Current / [math]::Max($Total, 1)) * $Width)
    $empty = $Width - $filled

    $barFilled = "#" * $filled
    $barEmpty = "-" * $empty

    Write-Host ("`r  {0} [{1}" -f $Label, $barFilled) -NoNewline
    Write-Host $barEmpty -NoNewline -ForegroundColor DarkGray
    Write-Host ("] {0}% ({1}/{2})    " -f $percent, $Current, $Total) -NoNewline
}

function Write-Status {
    param([string]$Message, [ConsoleColor]$Color = "White")
    Write-Host "  [*] $Message" -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [+] $Message" -ForegroundColor Green
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "  [-] $Message" -ForegroundColor Red
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
}

function Exit-WithPrompt {
    Write-Host ""
    Write-Host "  Pressione qualquer tecla para sair..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

function Get-SteamPath {
    $registryPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )

    foreach ($path in $registryPaths) {
        try {
            $steamPath = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue).InstallPath
            if ($steamPath -and (Test-Path $steamPath)) {
                return $steamPath
            }
        } catch {}
    }
    return $null
}

function Get-DepotIdsFromLua {
    param([string]$LuaPath)

    $depots = @()
    if (-not (Test-Path $LuaPath)) { return $depots }
    
    $content = Get-Content -Path $LuaPath -ErrorAction SilentlyContinue

    foreach ($line in $content) {
        if ($line -match 'addappid\s*\(\s*(\d+)\s*,\s*\d+\s*,\s*"[a-fA-F0-9]+"') {
            $depotId = $matches[1]
            $depots += $depotId
        }
    }
    return $depots | Select-Object -Unique
}

function Get-AppInfo {
    param([string]$IdJogo)
    $url = "https://api.steamcmd.net/v1/info/$IdJogo"
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30
        return $response
    } catch {
        return $null
    }
}

function Get-ManifestIdForDepot {
    param([object]$AppInfo, [string]$IdJogo, [string]$DepotId)
    try {
        $depots = $AppInfo.data.$IdJogo.depots
        if ($depots.$DepotId -and $depots.$DepotId.manifests -and $depots.$DepotId.manifests.public) {
            return $depots.$DepotId.manifests.public.gid
        }
    } catch {}
    return $null
}

function Try-DownloadUrl {
    param(
        [string]$Url,
        [string]$OutputFile,
        [int]$MaxRetries,
        [string]$Label,
        [int]$RetryDelaySeconds = 3
    )

    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            if (Test-Path $OutputFile) {
                Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue
            }

            Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 120 -OutFile $OutputFile -ErrorAction Stop

            if (Test-Path $OutputFile) {
                $fileSize = (Get-Item $OutputFile).Length
                if ($fileSize -gt 0) {
                    return @{ Success = $true; Is404 = $false; Size = $fileSize; Attempts = $attempt }
                }
            }
            $lastError = "Arquivo recebido esta vazio"
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            if ($statusCode -eq 404) {
                if (Test-Path $OutputFile) { Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue }
                return @{ Success = $false; Is404 = $true; Error = "Nao encontrado (404)"; Attempts = $attempt }
            }
            $lastError = $_.Exception.Message
        }

        if ($attempt -lt $MaxRetries) {
            Write-Host "      Tentativa $attempt falhou ($Label): $lastError" -ForegroundColor DarkYellow
            Write-Host "      Repetindo em ${RetryDelaySeconds}s..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    return @{ Success = $false; Is404 = $false; Error = $lastError; Attempts = $MaxRetries }
}

function Download-Manifest {
    param(
        [string]$DepotId,
        [string]$ManifestId,
        [string]$OutputPath,
        [int]$RetryDelaySeconds = 3
    )

    $outputFile = Join-Path $OutputPath "${DepotId}_${ManifestId}.manifest"
    $githubUrl = "https://raw.githubusercontent.com/qwe213312/k25FCdfEOoEJ42S6/main/${DepotId}_${ManifestId}.manifest"

    $result = Try-DownloadUrl -Url $githubUrl -OutputFile $outputFile -MaxRetries 3 -Label "Green Mirror" -RetryDelaySeconds $RetryDelaySeconds

    if ($result.Success) {
        return @{ Success = $true; FilePath = $outputFile; Size = $result.Size; Attempts = $result.Attempts }
    }
    return @{ Success = $false; Error = $result.Error; Attempts = $result.Attempts }
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    else { return "$Bytes B" }
}

# ===========================================================================
# EXECUCAO PRINCIPAL
# ===========================================================================

Write-Header

while ($true) {

    if (-not $IdJogo) { $IdJogo = $env:APP_ID }
    if (-not $IdJogo) {
        $IdJogo = Read-Host "  Digite o codigo identificador do Jogo"
    }

    if ([string]::IsNullOrWhiteSpace($IdJogo) -or $IdJogo -notmatch '^\d+$') {
        Write-ErrorMsg "Um identificador de jogo valido e obrigatorio!"
        Exit-WithPrompt
    }

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor DarkGray
    Write-Host ""

    Write-Status "Localizando arquivos do sistema da Steam..."
    $steamPath = Get-SteamPath

    if (-not $steamPath) {
        Write-ErrorMsg "Nao foi possivel encontrar a pasta do sistema no computador!"
        Exit-WithPrompt
    }

    Write-Success "Sistema encontrado em: $steamPath"

    $luaPath = Join-Path $steamPath "config\stplug-in\$IdJogo.lua"
    Write-Status "Buscando arquivo de configuracao do jogo..."

    if (-not (Test-Path $luaPath)) {
        Write-Host ""
        Write-ErrorMsg "Configuracao local nao encontrada para este Jogo."
        Write-Host "  Certifique-se de que o jogo foi preparado na Green Store primeiro." -ForegroundColor Yellow
        Write-Host ""
        
        $continuarSemLua = Read-Host "  Deseja tentar buscar os dados diretamente do servidor online? (S/N)"
        if ($continuarSemLua -notin @("S","s","Sim","sim")) {
            Exit-WithPrompt
        }
    }

    Write-Status "Analisando estrutura de dados do jogo..."
    $depotIds = Get-DepotIdsFromLua -LuaPath $luaPath

    Write-Status "Requisitando dados do jogo ao servidor publico..."
    $appInfo = Get-AppInfo -IdJogo $IdJogo

    if (-not $appInfo -or $appInfo.status -ne "success") {
        Write-ErrorMsg "Falha ao obter as chaves de verificacao do jogo!"
        exit 1
    }
    Write-Success "Informacoes do jogo validadas com sucesso."
    Write-Host ""

    if ($depotIds.Count -eq 0) {
        Write-WarningMsg "Nenhum arquivo local mapeado. Tentando sincronizacao direta..."
        try {
            $apiDepots = $appInfo.data.$IdJogo.depots
            $depotIds = $apiDepots.psobject.properties.name | Where-Object { $_ -match '^\d+$' }
        } catch {}
    }

    if (-not $depotIds -or $depotIds.Count -eq 0) {
        Write-ErrorMsg "Nao foi possivel identificar os arquivos principais deste jogo!"
        exit 1
    }

    Write-Success "Total de $($depotIds.Count) parte(s) do jogo identificada(s)."
    Write-Host ""

    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | Codigos de Conteudo do Jogo:                                  |" -ForegroundColor DarkGray
    $depotList = ($depotIds -join ", ")
    if ($depotList.Length -gt 55) { $depotList = $depotList.Substring(0, 52) + "..." }
    $paddedDepotList = $depotList.PadRight(60)
    Write-Host "  | $paddedDepotList|" -ForegroundColor White
    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""

    Write-Status "Verificando chaves de acesso aos arquivos..."
    $downloadQueue = @()

    foreach ($depotId in $depotIds) {
        $manifestId = Get-ManifestIdForDepot -AppInfo $appInfo -IdJogo $IdJogo -DepotId $depotId
        if ($manifestId) {
            $downloadQueue += @{ DepotId = $depotId; ManifestId = $manifestId }
        }
    }

    if ($downloadQueue.Count -eq 0) {
        Write-WarningMsg "Nenhum arquivo correspondente liberado para download."
        exit 1
    }

    Write-Success "Pronto! $($downloadQueue.Count) arquivo(s) preparado(s) para atualizacao."
    Write-Host ""

    $depotCachePath = Join-Path $steamPath "depotcache"
    if (-not (Test-Path $depotCachePath)) {
        New-Item -ItemType Directory -Path $depotCachePath -Force | Out-Null
    }

    Write-Status "Diretorio de destino: $depotCachePath"
    Write-Host ""

    # ===========================================================================
    # SESSAO DE DOWNLOAD
    # ===========================================================================
    Write-Host "  ================================================================" -ForegroundColor DarkGray
    Write-Host "  INICIANDO ATUALIZACAO DOS ARQUIVOS" -ForegroundColor Green
    Write-Host ""

    $successCount = 0
    $skippedCount = 0
    $failedDepots = @()
    $totalSize = 0
    $startTime = Get-Date

    for ($i = 0; $i -lt $downloadQueue.Count; $i++) {
        $item = $downloadQueue[$i]
        $depotId = $item.DepotId
        $manifestId = $item.ManifestId

        Write-Host ""
        Write-ProgressBar -Current ($i) -Total $downloadQueue.Count -Label "Progresso Geral" -Color Green
        Write-Host ""
        Write-Host ""

        $existingFile = Join-Path $depotCachePath "${depotId}_${manifestId}.manifest"
        if (Test-Path $existingFile) {
            $existingSize = (Get-Item $existingFile).Length
            if ($existingSize -gt 0) {
                $skippedCount++
                $sizeStr = Format-FileSize -Bytes $existingSize
                Write-Host "  [=] Conteudo $depotId - Ja atualizado ($sizeStr), pulando." -ForegroundColor DarkGreen
                continue
            }
        }

        Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
        $depotLine = "Atualizando parte do Jogo: $depotId"
        Write-Host ("  | {0,-62}|" -f $depotLine) -ForegroundColor Green
        Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray

        $result = Download-Manifest -DepotId $depotId -ManifestId $manifestId -OutputPath $depotCachePath

        if ($result.Success) {
            $successCount++
            $totalSize += $result.Size
            $sizeStr = Format-FileSize -Bytes $result.Size
            $retryInfo = if ($result.Attempts -gt 1) { " [Tentativa $($result.Attempts)]" } else { "" }
            Write-Success "Parte $depotId - Sincronizada com sucesso ($sizeStr)$retryInfo"
        } else {
            $failedDepots += @{ DepotId = $depotId; ManifestId = $manifestId; Error = $result.Error }
            Write-ErrorMsg "Parte $depotId - Falhou apos $($result.Attempts) tentativas: $($result.Error)"
        }
    }

    Write-Host ""
    Write-ProgressBar -Current $downloadQueue.Count -Total $downloadQueue.Count -Label "Progresso Geral" -Color Green
    Write-Host ""

    $endTime = Get-Date
    $elapsed = $endTime - $startTime

    # ===========================================================================
    # RELATORIO FINAL
    # ===========================================================================
    Write-Host ""
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor DarkGray
    Write-Host "  PROCESSO CONCLUIDO" -ForegroundColor Green
    Write-Host ""
    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  |                         RESUMO GREEN STORE                    |" -ForegroundColor DarkGray
    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray

    Write-Host ("  |  {0,-60}|" -f "Atualizados:   $successCount partes") -ForegroundColor Green
    Write-Host ("  |  {0,-60}|" -f "Ignorados:     $skippedCount partes (Ja em dia)") -ForegroundColor DarkGreen

    $failedColor = if ($failedDepots.Count -gt 0) { "Red" } else { "Green" }
    Write-Host ("  |  {0,-60}|" -f "Falhas:        $($failedDepots.Count)") -ForegroundColor $failedColor
    Write-Host ("  |  {0,-60}|" -f "Total:         $($downloadQueue.Count) partes verificadas") -ForegroundColor White
    Write-Host ("  |  {0,-60}|" -f "Espaco Usado:  $(Format-FileSize -Bytes $totalSize)") -ForegroundColor White
    Write-Host ("  |  {0,-60}|" -f "Tempo Gasto:   $($elapsed.ToString('mm\:ss'))") -ForegroundColor White

    $outputText = "Destino:       $depotCachePath"
    if ($outputText.Length -gt 60) { $outputText = $outputText.Substring(0, 57) + "..." }
    Write-Host ("  |  {0,-60}|" -f $outputText) -ForegroundColor White
    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray

    if ($failedDepots.Count -gt 0) {
        Write-Host ""
        Write-Host "  ARQUIVOS QUE FALHARAM EM ATUALIZAR:" -ForegroundColor Red
        foreach ($failed in $failedDepots) {
            Write-Host "    Parte do Jogo: $($failed.DepotId)" -ForegroundColor Red
            Write-Host "    Motivo: $($failed.Error)" -ForegroundColor DarkRed
            Write-Host ""
        }
    }

    Write-Host ""
    Write-Host "  O que voce deseja fazer agora?" -ForegroundColor Green
    Write-Host ""
    Write-Host "    1. Processar outro Jogo" -ForegroundColor White
    Write-Host "    2. Sair da Ferramenta" -ForegroundColor White
    Write-Host ""
    do {
        $nextChoice = Read-Host "  Escolha uma opcao (1-2)"
    } while ($nextChoice -notin @("1","2"))

    if ($nextChoice -eq "2") { break }

    $IdJogo = $null
    Write-Header
    Write-Host ""

}

exit 0
