# Scale benchmark: 100000 items

Date: 2026-11-19T14:21:32Z
Machine: 18 cores, 128 GiB
Corpus: 100000 chunks of 500 to 2,000 characters (average 1256), vectors of 768 dimensions from a stub embedder.

| Measurement | Value | Limit | Result |
|---|---:|---:|---|
| search, limit = catalog size (max of 14 queries) | 85.0 ms | 300 ms | pass |
| update of 20 items (max of 10) | 11.0 ms | 100 ms | pass |
| start from the stored catalog | 1055.4 ms | 5000 ms | pass |
| search, median | 77.2 ms | | |
| update of 20 items, median | 10.6 ms | | |
| removal of 20 items | 2.8 ms | | |
| save after an update of 20 items, median (background) | 134.1 ms | | |
| build, embed and merge of the whole catalog (stub embedder) | 11721 ms | | |
| first snapshot after the build (background) | 716 ms | | |
| first search after the start | 67.6 ms | | |
| resident memory after the start (fresh process) | 1652 MiB | | |
| resident memory after the build (build process) | 1976 MiB | | |
| stored catalog | 864 MiB | | |

## Searches

| Query | Time | Matches |
|---|---:|---:|
| `orancre` | 72.5 ms | 100000 |
| `anhajo` | 70.5 ms | 100000 |
| `tecrefi` | 72.2 ms | 100000 |
| `exguindro orvine` | 79.0 ms | 100000 |
| `unan orexte` | 75.0 ms | 100000 |
| `isbriatin habrigu` | 76.1 ms | 100000 |
| `ingu stozo haexmi` | 73.4 ms | 100000 |
| `elzolozo unhakaat nezo` | 77.2 ms | 100000 |
| `hainzozo unan isel` | 78.9 ms | 100000 |
| `nerure uninnede vimika kaelor` | 78.3 ms | 100000 |
| `logu inatha zoatpa ha` | 77.6 ms | 100000 |
| `plaiste unhavi inatgu stokagu` | 85.0 ms | 100000 |
| `ishapla` | 70.8 ms | 100000 |
| `habriguJo failed` | 78.4 ms | 100000 |

Result: pass
