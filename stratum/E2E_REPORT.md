# Stratum sidecar: end-to-end result

> ## CORRECTION NOTICE, 2026-08-14: three of the numbers below were never measured
>
> This report was written by `scripts/ship_stratum_e2e.sh` as it stood at
> commit 073c9f4. That version read every pc3080 metric over ssh through an
> over-escaped `\$env:USERPROFILE`, which PowerShell resolved to a path that
> does not exist; `Get-Content -ErrorAction SilentlyContinue` then returned
> nothing and the counts came back as 0 or empty no matter what the miner
> had actually done. Audit round 2 (commit 450a225) diagnosed it against the
> live 11,880-line miner log: 4,015 accepted shares where the old form
> returned 0. The report was never regenerated, so the numbers stand here
> marked rather than deleted.
>
> **Instrument error, not measurement** (stratum-sidecar column only):
>
> - **Mining suspensions: 0.** A null read. It happens to be the ideal
>   outcome, which is why nobody questioned it.
> - **Accepted-share log lines: 0.** A null read. The same run's real log
>   carried thousands of accepted shares.
> - **Last reported speed: empty.** A null read, and a row that could not
>   have populated even with correct escaping: kawpowminer writes no `Speed`
>   or `Mh/s` line to stderr at all (checked against that 11,880-line log).
>
> **Still valid**, because it came from the node itself over IPC or from the
> sidecar's own local log, neither of which touched the broken ssh path: the
> block count, the difficulty progression, the per-minute samples table, the
> sidecar's own BLOCK-line count, and the supply audit.
>
> Two further cautions. The `getwork baseline` column is a hard-coded
> literal in the harness, carried over from an earlier getwork session; this
> run measured none of it. And the log tail below records a miner disconnect
> at 14:27:15, so citing this run for "zero disconnects" overstates it.
>
> This report also predates the current harness, which reads the miner log
> with the correct escaping, replaces the never-populated speed row with an
> effective hashrate computed as accepted shares x share difficulty divided
> by elapsed time, and FAILS the run outright on zero blocks or zero
> accepted shares. Its output still goes to `build/STRATUM_E2E_REPORT.md`,
> which is gitignored, so refreshing this tracked file means copying that
> file over it after a clean run.

Run: 2026-08-13T18:27:16Z, 12 minutes, RTX 3080 (pc3080)
mining an Everett KawPow devnet through `kawpow-stratum`.

## Result

| Metric | getwork baseline (harness literal, not measured here) | stratum sidecar |
|---|---|---|
| Blocks produced | 253 then stalled | 1368 in 12 min |
| Mining suspensions | 936 | 0 (NOT MEASURED, see notice) |
| Accepted-share log lines | 0 (none reported) | 0 (NOT MEASURED, see notice) |
| Blocks logged by sidecar | n/a | 1479 |
| Difficulty | 131,072 → 4M then stalled | 131427 → 72890515 |
| Last reported speed | never reported | (NOT MEASURED, see notice) |

## Samples

| Minute | Height | Difficulty | Last 20 blocks |
|---|---|---|---|
| 1 | 1446 | 323023 | 20s |
| 2 | 1606 | 677231 | 20s |
| 3 | 1778 | 1501071 | 20s |
| 4 | 1935 | 3104121 | 20s |
| 5 | 2090 | 6360114 | 20s |
| 6 | 2239 | 12674625 | 20s |
| 7 | 2341 | 20320886 | 20s |
| 8 | 2422 | 29562633 | 20s |
| 9 | 2495 | 41444292 | 20s |
| 10 | 2538 | 50569641 | 20s |
| 11 | 2587 | 63441634 | 20s |
| 12 | 2617 | 72890515 | 20s |


## Supply audit after the run

```
blocks=2618 txs=0 uncles=263 burned=0 wei
PASS (no txs yet): reward accounting exact; send a tx to test the burn
```

## Sidecar log (tail)

```
2026/08/13 14:27:04 new job 00000557 height=2615 target=0000003b78b1d352...
2026/08/13 14:27:07 shares below block target: 1300 so far (expected under vardiff; sample: job 00000557 nonce=0x0002000007934306)
2026/08/13 14:27:07 BLOCK: job 00000557 height=2615 nonce=0x00020000080915ff from 0x3000000000000000000000000000000000000003
2026/08/13 14:27:08 new job 00000558 height=2616 target=0000003b3265fb16...
2026/08/13 14:27:08 BLOCK: job 00000558 height=2616 nonce=0x0002000000ef0c62 from 0x3000000000000000000000000000000000000003
2026/08/13 14:27:08 BLOCK: job 00000558 height=2616 nonce=0x0002000000f6557f from 0x3000000000000000000000000000000000000003
2026/08/13 14:27:08 new job 00000559 height=2617 target=0000003aec6d39a2...
2026/08/13 14:27:10 BLOCK: job 00000559 height=2617 nonce=0x000200000538af11 from 0x3000000000000000000000000000000000000003
2026/08/13 14:27:10 new job 0000055a height=2618 target=0000003aa6c72f8e...
2026/08/13 14:27:13 BLOCK: job 0000055a height=2618 nonce=0x00020000084bb3a3 from 0x3000000000000000000000000000000000000003
2026/08/13 14:27:13 new job 0000055b height=2619 target=0000003a61737e40...
2026/08/13 14:27:15 miner 192.168.1.158:50986 disconnected: scan err=read tcp 192.168.1.172:3333->192.168.1.158:50986: read: connection reset by peer
```
