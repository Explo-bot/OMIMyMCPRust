# Specifica 03: geometria, arrotondamenti e normalizzazione dei testi

## 1. Modello

Una geometria è un **multipoligono**: lista di poligoni; ogni poligono è una lista di anelli; il primo
anello è il bordo esterno, gli altri sono buchi. Ogni anello è un vettore piatto di interi a 32 bit
`[x0, y0, x1, y1, …]` in **microgradi** WGS84 (`x = round_half_even(lon·1e6)`, `y = round_half_even(lat·1e6)`).
Costante `S = 1 000 000.0`.

## 2. Arrotondamento

Ovunque questa specifica dice "arrotondare" si intende **all'intero pari in caso di metà esatta**
(*banker's rounding*): in Rust `f64::round_ties_even()`, mai `f64::round()`.
Arrotondare a `d` decimali: `(x * 10^d).round_ties_even() / 10^d`, calcolato in `f64`.
Ne dipendono l'hash delle geometrie (e quindi la deduplicazione), i centroidi, le aree e le distanze.

## 3. Codifica binaria (`encode` / `decode`)

- Interi senza segno in **varint LEB128**: 7 bit per byte, bit alto = "continua", byte meno significativo per primo.
- Interi con segno in **zigzag**: `z = (v << 1) ^ (v >> 63)` su `i64`; inverso `v = (z >> 1) as i64 ^ -((z & 1) as i64)`.
- Formato:
  ```
  varint n_poligoni
  per ogni poligono:
      varint n_anelli
      per ogni anello:
          varint n_punti
          per ogni punto: zigzag(x - px), zigzag(y - py); poi px = x, py = y
  ```
  `px` e `py` partono da 0 e **non si azzerano** tra anelli e poligoni.
- `decode` deve restituire un errore (mai andare in panic) su un blob troncato o con varint oltre i 64 bit.
- **Vettore di test:** un poligono con un anello dei punti (1,2), (3,5), (0,0) → byte `01 01 03 02 04 04 06 05 09`.
- L'hash usato per la deduplicazione è `SHA-256(blob)` troncato ai primi 16 byte, salvato come BLOB.

## 4. Misure

Riprodurre le formule nell'ordine indicato, in `f64`, così i risultati coincidono al bit.

### bbox
Minimo e massimo di x e y su tutti gli anelli (in interi), poi divisi per `S` → `(min_lon, min_lat, max_lon, max_lat)`.

### Centroide e area (`centroid_and_area`)
```
a = cx = cy = 0
per ogni poligono, per ogni anello r con indice k (0 = esterno):
    n = numero di punti; se n < 3 passa al successivo
    x0 = ring[0]/S; y0 = ring[1]/S
    ra = rcx = rcy = 0
    per i in 0..n:
        j = (i + 1) % n
        xi = ring[2i]/S - x0;  yi = ring[2i+1]/S - y0
        xj = ring[2j]/S - x0;  yj = ring[2j+1]/S - y0
        cr = xi*yj - xj*yi
        ra += cr;  rcx += (xi + xj)*cr;  rcy += (yi + yj)*cr
    ra = ra / 2
    se |ra| < 1e-15 passa al successivo
    rcx = rcx / (6*ra) + x0;  rcy = rcy / (6*ra) + y0
    sa = |ra| * (k == 0 ? 1 : -1)
    a += sa;  cx += rcx*sa;  cy += rcy*sa
se |a| < 1e-15: restituisci (centro del bbox, area 0)
cx = cx / a;  cy = cy / a
km_lat = 111.32;  km_lon = 111.32 * cos(cy * π / 180)
area_km2 = a * km_lat * km_lon
restituisci (cx, cy, area_km2)
```

### Punto nel multipoligono (`contains(lon, lat)`)
```
x = lon * S;  y = lat * S
per ogni poligono:
    inside = false
    per ogni anello (n punti), per i = 0, j = n-1; i < n; j = i, i++:
        xi, yi = ring[2i], ring[2i+1];  xj, yj = ring[2j], ring[2j+1]   (come f64)
        se (yi > y) != (yj > y) e x < (xj - xi) * (y - yi) / (yj - yi) + xi: inside = !inside
    se inside: restituisci vero
restituisci falso
```

### Distanza dal bordo in metri (`distance_meters(lon, lat)`)
```
kx = 111320 * cos(lat * π / 180);  ky = 110540;  best = +∞ (f64::MAX)
per ogni anello, per ogni segmento (j → i) con lo stesso schema di indici:
    ax = (ring[2j]/S - lon) * kx;  ay = (ring[2j+1]/S - lat) * ky
    bx = (ring[2i]/S - lon) * kx;  by = (ring[2i+1]/S - lat) * ky
    dx = bx - ax;  dy = by - ay;  len = dx*dx + dy*dy
    t = len > 0 ? clamp(-(ax*dx + ay*dy) / len, 0, 1) : 0
    px = ax + t*dx;  py = ay + t*dy;  d = px*px + py*py
    best = min(best, d)
restituisci sqrt(best)
```

### GeoJSON
`{"type":"MultiPolygon","coordinates":[ poligoni → anelli → punti [lon, lat] ]}` con `lon = x/S`, `lat = y/S`.

## 5. Ricerca spaziale

Candidati per un punto con margine `m` gradi nel semestre di perimetri `gs`:
```sql
SELECT g.id, g.dati, zg.comune_amm, zg.zona, zg.link_zona
FROM geometria_rt rt
JOIN geometria g ON g.id=rt.id
JOIN zona_geo zg ON zg.geometria_id=rt.id AND zg.semestre=@gs
WHERE rt.min_lon<=@x+@m AND rt.max_lon>=@x-@m AND rt.min_lat<=@y+@m AND rt.max_lat>=@y-@m
```
Per ogni riga, nell'ordine restituito: geometria decodificata una sola volta per id (cache per richiesta);
`distanza = contains ? 0 : distance_meters`.

## 6. Normalizzazione dei nomi (`norm`)

Serve alla ricerca dei comuni. Algoritmo, carattere per carattere:

1. Sostituzioni: `À Á Â Ä Ã à á â ä ã` → `A`; `È É Ê Ë è é ê ë` → `E`; `Ì Í Î Ï ì í î ï` → `I`;
   `Ò Ó Ô Ö Õ ò ó ô ö õ` → `O`; `Ù Ú Û Ü ù ú û ü` → `U`; `Ç ç` → `C`; `Ñ ñ` → `N`. Qualunque altro carattere va
   in maiuscolo (se `to_uppercase()` produce più di un carattere, per esempio `ß`, si tiene il carattere originale).
2. I caratteri `'` `` ` `` `’` `´` `"` si eliminano.
3. Spazi bianchi (Unicode), `-`, `/`, `.` e `,` sono separatori: una sequenza di separatori diventa **un solo**
   spazio, mai all'inizio né alla fine.
4. Input vuoto o assente → stringa vuota.

Test: `"Sant'Antonio di Gallura"` → `"SANTANTONIO DI GALLURA"`; `"Forlì-Cesena"` → `"FORLI CESENA"`;
`"  Reggio   nell'Emilia "` → `"REGGIO NELLEMILIA"`; `"L'Aquila"` → `"LAQUILA"`.
