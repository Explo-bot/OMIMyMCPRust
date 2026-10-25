#!/usr/bin/env bash
# Esegue in sequenza con Claude Code le fasi di prompt/ (01..07) del progetto OMIMyMCP-rs.
# Funziona su Linux, macOS, WSL e Git Bash per Windows.
#
# Per ogni fase lancia Claude Code con il prompt corrispondente, poi controlla in CLAUDE.md che la fase sia
# stata spuntata ("- [x] NN"). Le fasi già spuntate vengono saltate (salvo --forza).
#
# Ogni fase usa il modello e il livello di ragionamento (effort) adatti al suo lavoro, secondo il profilo:
#   consigliato (default)  Opus per il codice, Sonnet per configurazione e documentazione
#   massimo                Fable/best per le fasi più difficili (02, 03, 06): usa i crediti d'uso
#   economico              opusplan (Opus pianifica, Sonnet esegue) e Sonnet, per piani con limiti stretti
#
# Uso:
#   scripts/esegui-fasi.sh [--da N] [--a N] [--automatica] [--profilo consigliato|massimo|economico]
#                          [--modello NOME] [--effort LIVELLO] [--max-turni N]
#                          [--forza] [--push] [--senza-conferma] [--mostra-modelli] [--help]
#
# Esempi:
#   scripts/esegui-fasi.sh                         # tutte le fasi, interattivo, profilo consigliato
#   scripts/esegui-fasi.sh --da 3 --a 5 --push     # fasi 03-05, push dopo ogni fase
#   scripts/esegui-fasi.sh --profilo massimo       # Fable per le fasi 02, 03 e 06
#   scripts/esegui-fasi.sh --automatica --a 3      # fasi 01-03 senza interfaccia, log in logs/
#   scripts/esegui-fasi.sh --mostra-modelli        # tabella fase -> modello/effort e uscita
set -euo pipefail

DA=1
A=7
AUTOMATICA=0
MODELLO=""
EFFORT=""
PROFILO="consigliato"
MOSTRA_MODELLI=0
MAX_TURNI=300
FORZA=0
PUSH=0
SENZA_CONFERMA=0

uso() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --da) DA="$2"; shift 2 ;;
    --a) A="$2"; shift 2 ;;
    --automatica) AUTOMATICA=1; shift ;;
    --modello) MODELLO="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --profilo) PROFILO="$2"; shift 2 ;;
    --mostra-modelli) MOSTRA_MODELLI=1; shift ;;
    --max-turni) MAX_TURNI="$2"; shift 2 ;;
    --forza) FORZA=1; shift ;;
    --push) PUSH=1; shift ;;
    --senza-conferma) SENZA_CONFERMA=1; shift ;;
    -h|--help) uso; exit 0 ;;
    *) echo "Parametro non valido: $1" >&2; uso >&2; exit 1 ;;
  esac
done

[[ "$DA" =~ ^[1-7]$ && "$A" =~ ^[1-7]$ ]] || { echo "--da e --a devono essere compresi tra 1 e 7." >&2; exit 1; }
(( DA <= A )) || { echo "--da ($DA) non può essere maggiore di --a ($A)." >&2; exit 1; }
case "$PROFILO" in consigliato|massimo|economico) ;; *) echo "Profilo non valido: $PROFILO (consigliato, massimo, economico)." >&2; exit 1 ;; esac
[[ -z "$EFFORT" || "$EFFORT" =~ ^(low|medium|high|xhigh|max)$ ]] || { echo "Effort non valido: $EFFORT (low, medium, high, xhigh, max)." >&2; exit 1; }

FILE=( ""
  "prompt/01_workspace_e_core.md"
  "prompt/02_importatore.md"
  "prompt/03_server_mcp.md"
  "prompt/04_servizio_windows.md"
  "prompt/05_caddy_https.md"
  "prompt/06_collaudo.md"
  "prompt/07_manuale_tecnico.md" )
TITOLO=( ""
  "Workspace e libreria omi-core"
  "Importatore omi-import"
  "Server MCP omi-mcp"
  "Servizio Windows"
  "Caddy e HTTPS"
  "Collaudo"
  "Manuale tecnico e rilascio" )

# ------------------------------------------------------------------ modelli per fase
# Indice 1..7 = fase. Motivazioni in README §2.7.
#                 01        02      03      04        05      06        07
MOD_consigliato=( "" opus     opus    opus    opus      sonnet  opus      sonnet )
EFF_consigliato=( "" high     xhigh   xhigh   high      high    xhigh     high   )
MOD_massimo=(     "" opus     best    best    opus      opus    best      opus   )
EFF_massimo=(     "" xhigh    xhigh   xhigh   xhigh     high    xhigh     high   )
MOD_economico=(   "" opusplan opus    opus    opusplan  sonnet  opusplan  sonnet )
EFF_economico=(   "" high     high    high    high      medium  high      medium )

modello_fase() { if [[ -n "$MODELLO" ]]; then printf '%s' "$MODELLO"; else eval "printf '%s' \"\${MOD_${PROFILO}[$1]}\""; fi; }
effort_fase()  { if [[ -n "$EFFORT" ]];  then printf '%s' "$EFFORT";  else eval "printf '%s' \"\${EFF_${PROFILO}[$1]}\""; fi; }
# Modello di riserva se quello scelto è sovraccarico o non disponibile.
riserva_di() {
  case "$1" in
    best|fable*) printf 'opus' ;;
    opus*|opusplan*) printf 'sonnet' ;;
    sonnet*) printf 'opus' ;;
    haiku*) printf 'sonnet' ;;
    *) printf '' ;;
  esac
}

mostra_modelli() {
  printf '  %-4s %-30s %-10s %-7s %s\n' "Fase" "Titolo" "Modello" "Effort" "Riserva"
  for (( i = 1; i <= 7; i++ )); do
    local m; m=$(modello_fase "$i")
    printf '  %-4s %-30s %-10s %-7s %s\n' "$(printf '%02d' "$i")" "${TITOLO[$i]}" "$m" "$(effort_fase "$i")" "$(riserva_di "$m")"
  done
}

# Permessi concessi in anticipo in modalità automatica (regole di Claude Code).
STRUMENTI=( "Read" "Edit" "Write" "Glob" "Grep" "WebFetch" "WebSearch"
  "Bash(cargo *)" "Bash(rustc *)" "Bash(rustup *)"
  "Bash(git status *)" "Bash(git diff *)" "Bash(git add *)" "Bash(git commit *)" "Bash(git log *)"
  "Bash(ls *)" "Bash(mkdir *)" "Bash(cat *)" "Bash(pwsh *)" "Bash(powershell *)" )

colore() { if [[ -t 1 ]]; then printf '\033[%sm%s\033[0m\n' "$1" "$2"; else printf '%s\n' "$2"; fi; }
info()  { colore 36 "$1"; }
ok()    { colore 32 "$1"; }
warn()  { colore 33 "$1"; }
err()   { colore 31 "$1" >&2; }

fase_completata() { grep -Eq "^[[:space:]]*- \[[xX]\] 0$1([^0-9]|$)" CLAUDE.md; }

prompt_fase() {
  local f="${FILE[$1]}"
  if [[ "$2" == auto ]]; then
    printf '%s' "Leggi $f ed eseguilo fino in fondo senza fare domande: dove la specifica è ambigua scegli la soluzione più semplice e annotala in docs/DECISIONI.md. I passi che richiedono privilegi di amministratore, software non installato o interventi dell'utente lasciali come passi manuali nelle note della fase in CLAUDE.md. Al termine esegui cargo fmt, cargo clippy e cargo test, fai il commit e spunta la fase in CLAUDE.md."
  else
    printf '%s' "Leggi $f ed eseguilo. Prima presentami il piano."
  fi
}

# Argomenti di modello per la fase $1 (in MODEL_ARGS). Le opzioni non supportate dalla versione di Claude Code
# installata vengono omesse.
MODEL_ARGS=()
imposta_modello() {
  local m e r
  m=$(modello_fase "$1"); e=$(effort_fase "$1"); r=$(riserva_di "$m")
  MODEL_ARGS=()
  [[ -n "$m" ]] && MODEL_ARGS+=( --model "$m" )
  if [[ -n "$e" ]] && (( SUPPORTA_EFFORT )); then MODEL_ARGS+=( --effort "$e" ); fi
  if [[ -n "$r" ]] && (( SUPPORTA_RISERVA )); then MODEL_ARGS+=( --fallback-model "$r" ); fi
  echo "  modello: $m, effort: ${e:-predefinito}${r:+, riserva: $r} (profilo $PROFILO${MODELLO:+, modello forzato}${EFFORT:+, effort forzato})"
  if [[ "$m" == best || "$m" == fable* ]]; then
    warn "  Fable consuma i crediti d'uso e la prima volta chiede un consenso: se la fase si blocca subito, avviare una volta 'claude --model fable' in modo interattivo."
  fi
  if [[ "$m" == opusplan* ]] && (( AUTOMATICA )); then
    warn "  In modalità automatica non c'è la fase di piano: opusplan lavora interamente con Sonnet."
  fi
  return 0
}

git_push() {
  (( PUSH )) || return 0
  info "  git push..."
  git push || warn "  ATTENZIONE: git push non riuscito, proseguo comunque."
}

# ------------------------------------------------------------------ controlli iniziali

RADICE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RADICE"
[[ -f CLAUDE.md && -d prompt && -d specifica ]] || { err "Cartella del progetto non valida: $RADICE"; exit 1; }
command -v claude >/dev/null || { err "Claude Code non trovato. Installarlo con: curl -fsSL https://claude.ai/install.sh | bash"; exit 1; }
if (( MOSTRA_MODELLI )); then echo "Profilo: $PROFILO"; mostra_modelli; exit 0; fi
AIUTO_CLAUDE=$(claude --help 2>&1 || true)
SUPPORTA_EFFORT=0; [[ "$AIUTO_CLAUDE" == *--effort* ]] && SUPPORTA_EFFORT=1
SUPPORTA_RISERVA=0; [[ "$AIUTO_CLAUDE" == *--fallback-model* ]] && SUPPORTA_RISERVA=1
(( SUPPORTA_EFFORT )) || warn "ATTENZIONE: questa versione di Claude Code non supporta --effort (aggiornare con: claude update)."
for c in git cargo; do command -v "$c" >/dev/null || warn "ATTENZIONE: '$c' non trovato nel PATH (vedi README, §1.2)."; done
mkdir -p logs

echo
ok "OMIMyMCP-rs: esecuzione delle fasi $DA-$A in modalità $( (( AUTOMATICA )) && echo automatica || echo interattiva )"
echo "Cartella: $RADICE"
echo "Modelli (profilo $PROFILO):"; mostra_modelli
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) warn "Git Bash su Windows: per le prove di sistema delle fasi 04-06 aprire Git Bash come amministratore." ;;
  *) warn "Sistema non Windows: le prove del servizio Windows (fase 04) resteranno passi manuali." ;;
esac
echo

# ------------------------------------------------------------------ ciclo delle fasi

for (( n = DA; n <= A; n++ )); do
  nome=$(printf 'omi-fase-%02d' "$n")
  info "$(printf '=== Fase %02d: %s (%s)' "$n" "${TITOLO[$n]}" "${FILE[$n]}")"

  if fase_completata "$n" && (( ! FORZA )); then
    echo "  già spuntata in CLAUDE.md: salto (usare --forza per rieseguirla)."
    continue
  fi
  [[ -f "${FILE[$n]}" ]] || { err "File non trovato: ${FILE[$n]}"; exit 1; }
  imposta_modello "$n"

  if (( AUTOMATICA )); then
    log=$(printf 'logs/fase-%02d.log' "$n")
    echo "  esecuzione non interattiva, log in $log ..."
    set +e
    claude -p "$(prompt_fase "$n" auto)" --permission-mode acceptEdits --max-turns "$MAX_TURNI" \
      --output-format text --allowedTools "${STRUMENTI[@]}" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} 2>&1 | tee "$log"
    codice=${PIPESTATUS[0]}
    set -e
    if ! fase_completata "$n"; then
      err "$(printf "  La fase %02d non risulta completata (codice d'uscita %s). Controllare %s." "$n" "$codice" "$log")"
      warn "  Per riprendere in modo interattivo: claude -c   oppure   scripts/esegui-fasi.sh --da $n"
      exit 1
    fi
    ok "$(printf '  Fase %02d completata.' "$n")"
    git_push
    continue
  fi

  # modalità interattiva
  claude --permission-mode plan -n "$nome" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$(prompt_fase "$n" interattiva)" || true
  while ! fase_completata "$n"; do
    warn "$(printf '  La fase %02d non risulta spuntata in CLAUDE.md.' "$n")"
    read -r -p "  [R]iprendi la sessione, [N]uova sessione, [S]alta la fase, [F]ermati: " scelta
    case "$scelta" in
      [rR]*) claude -r "$nome" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} || true ;;
      [nN]*) claude --permission-mode plan -n "$nome" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
               "$(printf 'Riprendi la fase %02d (%s) da dove era rimasta: controlla lo stato del codice e dei test, poi continua.' "$n" "${FILE[$n]}")" || true ;;
      [sS]*) echo "  Fase saltata."; break ;;
      *) warn "Interrotto. Per ripartire da qui: scripts/esegui-fasi.sh --da $n"; exit 0 ;;
    esac
  done
  if fase_completata "$n"; then
    ok "$(printf '  Fase %02d completata. Ultimo commit: %s' "$n" "$(git log -1 --oneline 2>/dev/null || true)")"
    git_push
  fi
  if (( n < A && ! SENZA_CONFERMA )); then
    read -r -p "$(printf '  Passare alla fase %02d? [S/n] ' $((n + 1)))" risposta
    if [[ "$risposta" =~ ^[nN] ]]; then warn "Interrotto. Per ripartire: scripts/esegui-fasi.sh --da $((n + 1))"; exit 0; fi
  fi
done

echo
ok "Esecuzione terminata. Stato delle fasi in CLAUDE.md:"
grep -E '^[[:space:]]*- \[[ xX]\] 0[0-9]' CLAUDE.md | sed 's/^[[:space:]]*/  /'
