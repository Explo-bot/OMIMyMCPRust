# Fase 05: Caddy come reverse proxy HTTPS (facoltativo)

Rileggi `CLAUDE.md`. Questa fase produce solo configurazione, script e documentazione: Caddy **non** viene
incorporato nel binario.

## Quando serve

| Scenario | Serve Caddy? |
|---|---|
| Claude Code o Claude Desktop (tramite `mcp-remote`) sullo stesso PC | No: `http://localhost:8765/mcp` |
| Altri PC della LAN | No, oppure sì con `tls internal` se si vuole HTTPS |
| **Connettore personalizzato di claude.ai / Cowork** | **Sì**: il server dev'essere raggiungibile da Internet in HTTPS con un certificato valido |
| Prove veloci da Internet | In alternativa a Caddy, `cloudflared tunnel --url http://localhost:8765` |

Architettura consigliata:

```
Internet ──HTTPS:443──► Caddy (servizio "caddy") ──HTTP──► 127.0.0.1:8765 omi-mcp (servizio "OMIMyMCP") ──► omi.db
```

## 1. File da creare in `deploy/caddy/`

### `Caddyfile.internet.example` (dominio pubblico, Let's Encrypt automatico)
```caddyfile
{
	# certificati e stato in una cartella fissa (il servizio gira come LocalSystem)
	storage file_system C:/ProgramData/Caddy/data
	email {$OMI_ACME_EMAIL}
}

{$OMI_DOMINIO} {
	encode zstd gzip

	# facoltativo: limitare l'accesso a IP noti (es. gli indirizzi in uscita pubblicati da Anthropic)
	# @esterni not remote_ip 1.2.3.4/32
	# respond @esterni 403

	request_body {
		max_size 1MB
	}

	handle /mcp* {
		reverse_proxy 127.0.0.1:8765 {
			flush_interval -1      # niente buffering: necessario per le risposte in streaming (SSE)
			transport http {
				read_timeout 5m
			}
		}
	}
	handle /health {
		reverse_proxy 127.0.0.1:8765
	}
	handle {
		respond "OMIMyMCP - endpoint /mcp" 200
	}

	log {
		output file C:/ProgramData/Caddy/logs/omi-access.log {
			roll_size 10MiB
			roll_keep 10
		}
		format json
	}
}
```
Prima di consegnarlo, verifica la sintassi di ogni direttiva sulla documentazione di Caddy della versione
corrente (in particolare `request_body`, `transport http` e `log`) e correggi se serve. Se Caddy è
installato, esegui `caddy validate --config <file> --adapter caddyfile` con variabili d'ambiente di prova e
`caddy fmt --overwrite`.

### `Caddyfile.lan.example`
Lo stesso blocco con un nome host della LAN (es. `omi.lan`) e `tls internal`. Va spiegato che i client
devono considerare attendibile la CA locale di Caddy (`caddy trust`).

## 2. Script `deploy/windows/install-caddy.ps1`

Parametri: `-CaddyExe <percorso di caddy.exe già scaricato>`, `-Dominio`, `-Email`, `[-InstallDir "C:\Program Files\Caddy"]`, `[-ConfigDir "C:\ProgramData\Caddy"]`.

1. Non scarica nulla da solo: chiede il binario già scaricato da <https://caddyserver.com/download> (o dalle
   release ufficiali del progetto Caddy), e ne mostra l'hash SHA-256 da confrontare con quello pubblicato.
2. Copia `caddy.exe`, genera `ConfigDir\Caddyfile` dall'esempio sostituendo dominio ed email (oppure imposta
   le variabili `OMI_DOMINIO` e `OMI_ACME_EMAIL` a livello di sistema) e crea `data` e `logs`.
3. Esegue `caddy validate`.
4. Crea il servizio come indicato nella documentazione ufficiale di Caddy:
   `sc.exe create caddy start= auto binPath= "\"C:\Program Files\Caddy\caddy.exe\" run --config \"C:\ProgramData\Caddy\Caddyfile\" --adapter caddyfile"`,
   poi `sc.exe description caddy "Caddy - reverse proxy HTTPS per OMIMyMCP"`, la dipendenza
   `sc.exe config caddy depend= OMIMyMCP` e le azioni di riavvio con `sc.exe failure`. Fai attenzione agli
   spazi dopo `=` richiesti da `sc.exe` e alle virgolette nei percorsi.
5. Regole firewall per TCP 80 e 443 in ingresso (il challenge HTTP-01 di Let's Encrypt usa la porta 80).
6. Ricorda che il servizio OMIMyMCP va installato con `--bind 127.0.0.1 --trust-proxy` e **senza** `--firewall`.
7. `sc.exe start caddy` e verifica di `https://<dominio>/health`.

`uninstall.ps1 -RemoveCaddy` (fase 04) esegue `sc.exe stop caddy`, `sc.exe delete caddy`, rimuove le regole
firewall 80/443 e, solo con `-RemoveData`, `C:\ProgramData\Caddy`.

## 3. Requisiti di rete da documentare (per il manuale)

- Un nome DNS pubblico (record A/AAAA) che punti all'IP pubblico della macchina, oppure un servizio DNS dinamico.
- Inoltro delle porte 80 e 443 sul router o NAT verso la macchina; alcuni provider bloccano la porta 80 sulle
  linee domestiche, e in quel caso serve il challenge DNS (modulo DNS del provider, build personalizzata di
  Caddy) oppure il tunnel cloudflared.
- Collegamento a claude.ai: **Impostazioni → Connettori → Aggiungi connettore personalizzato** con URL
  `https://<dominio>/mcp`.
- Sicurezza: il server è in sola lettura ma espone dati soggetti alle condizioni dell'Agenzia delle Entrate
  (vedi `specifica/05_contesto_e_uso.md` §5). Opzioni: restrizione per IP in Caddy, token Bearer (per i
  client che lo supportano), autenticazione sul proxy. Indica chiaramente quali opzioni sono compatibili con
  i connettori di claude.ai, verificando la documentazione Anthropic corrente sui connettori personalizzati
  remoti (autenticazione supportata, IP in uscita).

## 4. Verifica

Senza dominio pubblico: avvia Caddy in locale con `Caddyfile.lan.example` (`localhost` + `tls internal`),
verifica con `curl -k https://localhost/health` e con una `tools/list` via `https://localhost/mcp`, controlla
che la risposta in streaming arrivi senza buffering e che nel log del server, con `--trust-proxy`, compaia
l'IP originale. Riporta l'esito o, se Caddy non è installato, segnala il passo come manuale.

Spunta la fase in `CLAUDE.md`.
