# Specifica 05: contesto d'uso, client, licenze

Informazioni da riportare nel manuale tecnico e nel README del progetto Rust.

## 1. Avvertenze

- Il software è fornito **"così com'è"**, senza garanzie; l'uso è a rischio dell'utente.
- Le quotazioni OMI hanno valore indicativo e **non sostituiscono la stima di un professionista**.
- Non esporre il server a Internet senza protezioni adeguate.
- Ogni risultato basato sui dati va accompagnato dalla fonte **"Agenzia delle Entrate - OMI"**.

## 2. Collegamento ai client MCP

L'endpoint è `http://<host>:<porta>/mcp` (HTTP *streamable*).

### claude.ai (web, app desktop e mobile, Cowork)
I connettori personalizzati vengono contattati dall'infrastruttura di Anthropic, quindi il server deve
essere raggiungibile **da Internet in HTTPS**; `localhost` non funziona.
1. Rendere il server raggiungibile in HTTPS (Caddy con un dominio, oppure per prove
   `cloudflared tunnel --url http://localhost:8765`, che fornisce un indirizzo `https://….trycloudflare.com`).
2. **Impostazioni → Connettori → Aggiungi connettore personalizzato** (nei piani Team/Enterprise lo aggiunge un
   amministratore), con un nome (es. `Quotazioni OMI`) e l'URL completo, es. `https://omi.esempio.it/mcp`.
3. Attivare il connettore nella conversazione dal menu degli strumenti.
I connettori dell'account sono disponibili anche nell'app desktop e in Cowork. Le opzioni di autenticazione
supportate dai connettori personalizzati vanno verificate nella documentazione Anthropic corrente.

### Claude Desktop con server locale
Tramite il bridge `mcp-remote` (richiede Node.js), in `claude_desktop_config.json`
(**Impostazioni → Sviluppatore → Modifica configurazione**):
```json
{
  "mcpServers": {
    "omi": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://localhost:8765/mcp"]
    }
  }
}
```
Con il token: aggiungere agli argomenti `"--header", "Authorization: Bearer <token>"`.

### Claude Code
```
claude mcp add --transport http omi http://localhost:8765/mcp
claude mcp add --transport http omi http://localhost:8765/mcp --header "Authorization: Bearer <token>"
claude mcp list
claude mcp remove omi
```
- Con `--scope user` il server è disponibile in tutti i progetti; con `--scope project` viene salvato in `.mcp.json`
  e condiviso con chi usa lo stesso repository (non metterci il token).
- In una sessione, `/mcp` mostra lo stato della connessione e l'elenco degli strumenti.
- Alla prima chiamata di ogni strumento Claude Code chiede il permesso; gli strumenti sono di sola lettura, quindi si
  possono consentire in modo permanente (regola `mcp__omi__*` nei permessi).

### Verifica e uso nelle conversazioni (tutti i client)
1. Domanda di prova: "Quali semestri OMI sono caricati?". Claude deve chiamare `elenco_semestri` e riportare
   semestri, numero di zone e fonte dei dati.
2. Seconda prova: "Cerca il comune di Asti nei dati OMI". Deve chiamare `cerca_comuni`.
3. Se Claude risponde senza chiamare gli strumenti: controllare che il connettore sia attivo nella conversazione
   (claude.ai, Cowork) o elencato da `/mcp` (Claude Code), oppure chiedere esplicitamente "usa il server OMI".

Consigli per domande affidabili:
- indicare il comune con la provincia quando il nome è ambiguo (es. "Samone (TO)"), oppure il codice catastale;
- indicare il semestre (`2025/2`) quando conta; se manca si usa l'ultimo caricato;
- per un indirizzo fornire le coordinate, oppure attivare MCP Cruscotto Italia (§3), che le ricava dallo stradario
  ANNCSU; il server OMI non converte gli indirizzi in coordinate;
- per le serie storiche chiedere di segnalare i cambi di descrizione della zona (revisioni della zonizzazione);
- chiedere sempre la citazione della fonte "Agenzia delle Entrate - OMI" nei documenti prodotti.

Prova degli strumenti senza Claude: `npx @modelcontextprotocol/inspector`, trasporto "Streamable HTTP",
URL `http://localhost:8765/mcp` (con l'intestazione `Authorization` se il token è attivo).

## 3. Uso combinato con MCP Cruscotto Italia

Il server MCP pubblico di AgID **Cruscotto Italia** (<https://www.dati.gov.it/sviluppatori/mcp-cruscotto-italia>,
endpoint `https://cruscotto-italia-mcp.agid.workers.dev/mcp`) espone dati pubblici per ogni comune italiano
(ISTAT, MEF, ISPRA, PNRR e altre fonti). Usato insieme a OMIMyMCP permette, per esempio, di ricavare le
coordinate di un indirizzo dallo stradario ANNCSU e passarle a `zona_da_coordinate`, oppure di confrontare
prezzi e redditi IRPEF. Collegamento con Claude Code:
```
claude mcp add --transport http cruscotto-italia https://cruscotto-italia-mcp.agid.workers.dev/mcp
```
I dati di Cruscotto Italia hanno licenze proprie (prevalentemente CC-BY 4.0), da citare insieme alla fonte OMI.

## 4. Esempi di domande (per il manuale)

- "Ho un appartamento di 95 m² in buono stato in via Nizza 150 a Torino. In che zona OMI si trova e qual è
  l'intervallo di valore di compravendita e di affitto mensile secondo l'ultimo semestre?"
- "Elenca le zone OMI di Bergamo con le quotazioni delle abitazioni civili in stato normale, dalla più cara alla più economica."
- "Mostrami l'andamento dal 2004 a oggi delle quotazioni delle abitazioni civili nella zona B12 di Milano."
- "Quali zone OMI si trovano entro 1,5 km da Piazza del Campo a Siena?"
- "Per le zone centrali (fascia B) di Bologna calcola il rendimento lordo annuo da affitto delle abitazioni civili."

## 5. Licenze

### Codice
Licenza **Apache License 2.0**. Il file `LICENSE` contiene il testo integrale della licenza (scaricabile da
<https://www.apache.org/licenses/LICENSE-2.0.txt>). Il file `NOTICE` riporta:
```
OMIMyMCP-rs - Server MCP per le quotazioni immobiliari OMI (implementazione Rust)
Copyright 2026 Explobot

Distribuito con licenza Apache License, Version 2.0.
Chi ridistribuisce questo software o opere derivate deve riportare il presente avviso,
come previsto dalla sezione 4(d) della licenza.

Dati
I dati delle quotazioni immobiliari e dei perimetri delle zone OMI, e il database da essi derivato,
NON sono coperti da questa licenza. Fonte dei dati: Agenzia Entrate - OMI.
Sono soggetti alle condizioni d'uso dell'Agenzia delle Entrate:
https://www.agenziaentrate.gov.it/portale/schede/fabbricatiterreni/omi/banche-dati/quotazioni-immobiliari/condizioni-contrattuali-qi

Componenti di terze parti
<elenco delle crate usate con licenza, generato a fine progetto>
- SQLite (pubblico dominio) - https://sqlite.org
```

### Dati OMI
Il progetto **non contiene né distribuisce dati OMI**. I dati restano soggetti alle condizioni contrattuali e
d'uso dell'Agenzia delle Entrate (link sopra), che non associa una licenza aperta standard. In sintesi:
- le informazioni sono di proprietà esclusiva dell'Agenzia delle Entrate;
- è obbligatorio citare la fonte **"Agenzia delle Entrate - OMI"**, anche per dati elaborati;
- l'elaborazione per uso proprio è consentita;
- non è consentito vendere, affittare, trasferire o cedere a terzi i contenuti della banca dati: il database
  prodotto è a uso di chi ha scaricato i dati e **non va condiviso né pubblicato**;
- l'Agenzia avverte che revisioni delle zone e dei metodi hanno prodotto salti di quotazione tra semestri:
  le serie storiche vanno confrontate con cautela;
- esporre il server a terzi significa rendere loro accessibili i dati: va valutato alla luce di queste condizioni.
