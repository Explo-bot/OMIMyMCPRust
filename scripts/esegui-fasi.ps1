<#
.SYNOPSIS
    Esegue in sequenza con Claude Code le fasi di prompt\ (01..07) del progetto OMIMyMCP-rs.

.DESCRIPTION
    Per ogni fase lancia Claude Code con il prompt corrispondente, poi controlla in CLAUDE.md che la fase
    sia stata spuntata ("- [x] NN"). Le fasi già spuntate vengono saltate (salvo -Forza).

    Modalità interattiva (default): Claude Code si apre in modalità piano; si approva il piano, si segue il
    lavoro e si esce con /exit. Lo script controlla l'esito e propone di passare alla fase successiva, di
    riprendere la sessione, di saltare la fase o di fermarsi.

    Modalità automatica (-Automatica): Claude Code gira senza interfaccia (claude -p), senza fare domande,
    con l'output salvato in logs\fase-NN.log. Richiede Git for Windows (Claude Code usa Git Bash per i comandi).
    I passi che richiedono privilegi di amministratore restano manuali e sono annotati nelle note della fase.

.PARAMETER Da
    Prima fase da eseguire (1-7). Default 1.
.PARAMETER A
    Ultima fase da eseguire (1-7). Default 7.
.PARAMETER Automatica
    Esecuzione non interattiva (claude -p).
.PARAMETER Profilo
    Scelta dei modelli per fase (motivazioni in README §2.7):
      consigliato (default)  Opus per il codice, Sonnet per configurazione e documentazione
      massimo                Fable/best per le fasi più difficili (02, 03, 06): usa i crediti d'uso
      economico              opusplan (Opus pianifica, Sonnet esegue) e Sonnet, per piani con limiti stretti
.PARAMETER Modello
    Forza lo stesso modello per tutte le fasi (es. opus, sonnet, best), ignorando il profilo.
.PARAMETER Effort
    Forza lo stesso livello di ragionamento per tutte le fasi (low, medium, high, xhigh, max).
.PARAMETER MostraModelli
    Mostra la tabella fase -> modello/effort del profilo scelto ed esce.
.PARAMETER MaxTurni
    Solo in modalità automatica: numero massimo di turni per fase. Default 300.
.PARAMETER Forza
    Esegue anche le fasi già spuntate in CLAUDE.md.
.PARAMETER Push
    Dopo ogni fase completata esegue git push.
.PARAMETER SenzaConferma
    In modalità interattiva passa alla fase successiva senza chiedere conferma.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1 -Da 3 -A 5 -Modello opus -Push
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1 -Automatica -Da 1 -A 3
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1 -Profilo massimo -MostraModelli
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 7)][int]$Da = 1,
    [ValidateRange(1, 7)][int]$A = 7,
    [switch]$Automatica,
    [ValidateSet('consigliato', 'massimo', 'economico')][string]$Profilo = 'consigliato',
    [string]$Modello,
    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')][string]$Effort = '',
    [switch]$MostraModelli,
    [int]$MaxTurni = 300,
    [switch]$Forza,
    [switch]$Push,
    [switch]$SenzaConferma
)

$ErrorActionPreference = 'Stop'
# Output dei programmi esterni (claude, git) in UTF-8, così i log e gli accenti restano leggibili.
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$Fasi = @{   # tabella con chiavi intere: niente [ordered], che con un indice numerico lavora per posizione
    1 = @{ File = 'prompt/01_workspace_e_core.md'; Titolo = 'Workspace e libreria omi-core'; Admin = $false }
    2 = @{ File = 'prompt/02_importatore.md';      Titolo = 'Importatore omi-import';        Admin = $false }
    3 = @{ File = 'prompt/03_server_mcp.md';       Titolo = 'Server MCP omi-mcp';            Admin = $false }
    4 = @{ File = 'prompt/04_servizio_windows.md'; Titolo = 'Servizio Windows';              Admin = $true  }
    5 = @{ File = 'prompt/05_caddy_https.md';      Titolo = 'Caddy e HTTPS';                 Admin = $true  }
    6 = @{ File = 'prompt/06_collaudo.md';         Titolo = 'Collaudo';                      Admin = $true  }
    7 = @{ File = 'prompt/07_manuale_tecnico.md';  Titolo = 'Manuale tecnico e rilascio';    Admin = $false }
}

# Modello ed effort per fase e per profilo (indice 1..7 = fase). Motivazioni in README §2.7.
#                     01          02       03       04          05        06          07
$Profili = @{
    consigliato = @{ Modello = @('', 'opus',     'opus',  'opus',  'opus',     'sonnet', 'opus',     'sonnet')
                     Effort  = @('', 'high',     'xhigh', 'xhigh', 'high',     'high',   'xhigh',    'high') }
    massimo     = @{ Modello = @('', 'opus',     'best',  'best',  'opus',     'opus',   'best',     'opus')
                     Effort  = @('', 'xhigh',    'xhigh', 'xhigh', 'xhigh',    'high',   'xhigh',    'high') }
    economico   = @{ Modello = @('', 'opusplan', 'opus',  'opus',  'opusplan', 'sonnet', 'opusplan', 'sonnet')
                     Effort  = @('', 'high',     'high',  'high',  'high',     'medium', 'high',     'medium') }
}

function Get-ModelloFase([int]$n) { if ($Modello) { return $Modello }; return $Profili[$Profilo].Modello[$n] }
function Get-EffortFase([int]$n)  { if ($Effort)  { return $Effort };  return $Profili[$Profilo].Effort[$n] }
# Modello di riserva se quello scelto è sovraccarico o non disponibile.
function Get-Riserva([string]$m) {
    switch -Regex ($m) {
        '^(best|fable)'    { return 'opus' }
        '^(opus|opusplan)' { return 'sonnet' }
        '^sonnet'          { return 'opus' }
        '^haiku'           { return 'sonnet' }
        default            { return '' }
    }
}
function Show-Modelli {
    Scrivi ('  {0,-4} {1,-30} {2,-10} {3,-7} {4}' -f 'Fase', 'Titolo', 'Modello', 'Effort', 'Riserva')
    for ($i = 1; $i -le 7; $i++) {
        $m = Get-ModelloFase $i
        Scrivi ('  {0,-4} {1,-30} {2,-10} {3,-7} {4}' -f ('{0:D2}' -f $i), $Fasi[$i].Titolo, $m, (Get-EffortFase $i), (Get-Riserva $m))
    }
}

# Permessi concessi in anticipo in modalità automatica (regole di Claude Code).
$StrumentiConsentiti = @(
    'Read', 'Edit', 'Write', 'Glob', 'Grep', 'WebFetch', 'WebSearch',
    'Bash(cargo *)', 'Bash(rustc *)', 'Bash(rustup *)',
    'Bash(git status *)', 'Bash(git diff *)', 'Bash(git add *)', 'Bash(git commit *)', 'Bash(git log *)',
    'Bash(ls *)', 'Bash(mkdir *)', 'Bash(cat *)', 'Bash(pwsh *)', 'Bash(powershell *)'
)

function Scrivi([string]$testo, [string]$colore = 'Gray') { Write-Host $testo -ForegroundColor $colore }

function Test-FaseCompletata([int]$n) {
    $riga = Select-String -Path 'CLAUDE.md' -Pattern ('^\s*- \[[xX]\] 0{0}\b' -f $n) -Quiet
    return [bool]$riga
}

function Test-Amministratore {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PromptFase([int]$n, [bool]$auto) {
    $f = $Fasi[$n].File
    if ($auto) {
        return "Leggi $f ed eseguilo fino in fondo senza fare domande: dove la specifica è ambigua scegli la soluzione " +
               "più semplice e annotala in docs/DECISIONI.md. I passi che richiedono privilegi di amministratore, " +
               "software non installato o interventi dell'utente lasciali come passi manuali nelle note della fase in " +
               "CLAUDE.md. Al termine esegui cargo fmt, cargo clippy e cargo test, fai il commit e spunta la fase in CLAUDE.md."
    }
    return "Leggi $f ed eseguilo. Prima presentami il piano."
}

# Argomenti di modello per la fase $n (sempre un array, anche vuoto). Le opzioni non supportate dalla versione
# di Claude Code installata vengono omesse.
function Get-ArgModello([int]$n) {
    $m = Get-ModelloFase $n; $e = Get-EffortFase $n; $r = Get-Riserva $m
    $lista = New-Object System.Collections.Generic.List[string]
    if ($m) { $lista.Add('--model'); $lista.Add($m) }
    if ($e -and $script:SupportaEffort) { $lista.Add('--effort'); $lista.Add($e) }
    if ($r -and $script:SupportaRiserva) { $lista.Add('--fallback-model'); $lista.Add($r) }
    $forzature = @()
    if ($Modello) { $forzature += 'modello forzato' }
    if ($Effort) { $forzature += 'effort forzato' }
    $extra = if ($forzature) { ', ' + ($forzature -join ', ') } else { '' }
    $testoRiserva = if ($r) { ", riserva: $r" } else { '' }
    $testoEffort = if ($e) { $e } else { 'predefinito' }
    Scrivi "  modello: $m, effort: $testoEffort$testoRiserva (profilo $Profilo$extra)"
    if ($m -match '^(best|fable)') {
        Scrivi "  Fable consuma i crediti d'uso e la prima volta chiede un consenso: se la fase si blocca subito, avviare una volta 'claude --model fable' in modo interattivo." 'Yellow'
    }
    if ($m -like 'opusplan*' -and $Automatica) {
        Scrivi "  In modalità automatica non c'è la fase di piano: opusplan lavora interamente con Sonnet." 'Yellow'
    }
    return , $lista.ToArray()
}

function Invoke-GitPush {
    if (-not $Push) { return }
    Scrivi '  git push...' 'Cyan'
    git push
    if ($LASTEXITCODE -ne 0) { Scrivi '  ATTENZIONE: git push non riuscito, proseguo comunque.' 'Yellow' }
}

# ------------------------------------------------------------------ controlli iniziali

$radice = Split-Path -Parent $PSScriptRoot
Set-Location $radice
if (-not (Test-Path 'CLAUDE.md') -or -not (Test-Path 'prompt') -or -not (Test-Path 'specifica')) {
    throw "Cartella del progetto non valida: $radice (mancano CLAUDE.md, prompt\ o specifica\)."
}
if ($Da -gt $A) { throw "-Da ($Da) non può essere maggiore di -A ($A)." }
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw "Claude Code non trovato. Installarlo con: irm https://claude.ai/install.ps1 | iex"
}
if ($MostraModelli) { Scrivi "Profilo: $Profilo"; Show-Modelli; exit 0 }
$aiutoClaude = & { $ErrorActionPreference = 'Continue'; (claude --help 2>&1 | Out-String) }
$script:SupportaEffort = $aiutoClaude -match '--effort'
$script:SupportaRiserva = $aiutoClaude -match '--fallback-model'
if (-not $script:SupportaEffort) { Scrivi 'ATTENZIONE: questa versione di Claude Code non supporta --effort (aggiornare con: claude update).' 'Yellow' }
foreach ($cmd in 'git', 'cargo') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Scrivi "ATTENZIONE: '$cmd' non trovato nel PATH (vedi README, §1.2)." 'Yellow' }
}
if ($Automatica -and -not (Test-Path "$env:ProgramFiles\Git\bin\bash.exe") -and -not $env:CLAUDE_CODE_GIT_BASH_PATH) {
    Scrivi 'ATTENZIONE: Git Bash non trovato. In modalità automatica i permessi sono concessi per il tool Bash: installare Git for Windows (winget install Git.Git).' 'Yellow'
}
$admin = Test-Amministratore
New-Item -ItemType Directory -Force -Path 'logs' | Out-Null

Scrivi ''
Scrivi "OMIMyMCP-rs: esecuzione delle fasi $Da-$A in modalità $(if ($Automatica) { 'automatica' } else { 'interattiva' })" 'Green'
Scrivi "Cartella: $radice"
Scrivi "Modelli (profilo $Profilo):"; Show-Modelli
if (-not $admin) { Scrivi 'Terminale senza privilegi di amministratore: le prove di sistema delle fasi 04-06 resteranno manuali.' 'Yellow' }
Scrivi ''

# ------------------------------------------------------------------ ciclo delle fasi

for ($n = $Da; $n -le $A; $n++) {
    $fase = $Fasi[$n]
    $nome = 'omi-fase-{0:D2}' -f $n
    Scrivi ('=== Fase {0:D2}: {1} ({2})' -f $n, $fase.Titolo, $fase.File) 'Cyan'

    if ((Test-FaseCompletata $n) -and -not $Forza) {
        Scrivi '  già spuntata in CLAUDE.md: salto (usare -Forza per rieseguirla).' 'DarkGray'
        continue
    }
    if (-not (Test-Path $fase.File)) { throw "File non trovato: $($fase.File)" }
    $ArgComuni = Get-ArgModello $n
    if ($fase.Admin -and -not $admin) { Scrivi '  Nota: questa fase contiene prove che richiedono un terminale come amministratore.' 'Yellow' }

    if ($Automatica) {
        $log = 'logs\fase-{0:D2}.log' -f $n
        Scrivi "  esecuzione non interattiva, log in $log ..."
        $argomenti = @('-p', (Get-PromptFase $n $true), '--permission-mode', 'acceptEdits', '--max-turns', "$MaxTurni",
                       '--output-format', 'text') + $ArgComuni + @('--allowedTools') + $StrumentiConsentiti
        # In Windows PowerShell 5.1 l'output su stderr di un programma esterno con ErrorActionPreference=Stop
        # interromperebbe lo script: durante la chiamata si usa Continue.
        $ErrorActionPreference = 'Continue'
        & claude @argomenti 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log
        $codice = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if (-not (Test-FaseCompletata $n)) {
            Scrivi ("  La fase {0:D2} non risulta completata (codice d'uscita {1}). Controllare {2}." -f $n, $codice, $log) 'Red'
            Scrivi ('  Per riprendere in modo interattivo: claude -c   oppure   scripts\esegui-fasi.ps1 -Da {0}' -f $n) 'Yellow'
            exit 1
        }
        Scrivi ('  Fase {0:D2} completata.' -f $n) 'Green'
        Invoke-GitPush
        continue
    }

    # modalità interattiva
    $argomenti = @('--permission-mode', 'plan', '-n', $nome) + $ArgComuni + @(Get-PromptFase $n $false)
    & claude @argomenti
    while (-not (Test-FaseCompletata $n)) {
        Scrivi ('  La fase {0:D2} non risulta spuntata in CLAUDE.md.' -f $n) 'Yellow'
        $scelta = Read-Host '  [R]iprendi la sessione, [N]uova sessione, [S]alta la fase, [F]ermati'
        switch -Regex ($scelta) {
            '^[rR]' { & claude -r $nome @ArgComuni }
            '^[nN]' {
                $ripresa = 'Riprendi la fase {0:D2} ({1}) da dove era rimasta: controlla lo stato del codice e dei test, poi continua.' -f $n, $fase.File
                & claude --permission-mode plan -n $nome @ArgComuni $ripresa
            }
            '^[sS]' { Scrivi '  Fase saltata.' 'DarkGray'; break }
            default { Scrivi 'Interrotto. Per ripartire da qui:' 'Yellow'; Scrivi ('  scripts\esegui-fasi.ps1 -Da {0}' -f $n); exit 0 }
        }
        if ($scelta -match '^[sS]') { break }
    }
    if (Test-FaseCompletata $n) {
        $commit = & { $ErrorActionPreference = 'Continue'; git log -1 --oneline 2>$null }
        Scrivi ('  Fase {0:D2} completata. Ultimo commit: {1}' -f $n, $commit) 'Green'
        Invoke-GitPush
    }
    if ($n -lt $A -and -not $SenzaConferma) {
        $ok = Read-Host ('  Passare alla fase {0:D2}? [S/n]' -f ($n + 1))
        if ($ok -match '^[nN]') { Scrivi ('Interrotto. Per ripartire: scripts\esegui-fasi.ps1 -Da {0}' -f ($n + 1)) 'Yellow'; exit 0 }
    }
}

Scrivi ''
Scrivi 'Esecuzione terminata. Stato delle fasi in CLAUDE.md:' 'Green'
Select-String -Path 'CLAUDE.md' -Pattern '^\s*- \[[ xX]\] 0\d' | ForEach-Object { Scrivi ('  ' + $_.Line.Trim()) }
