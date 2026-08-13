# Stratum sidecar: end-to-end result

Run: 2026-08-13T18:27:16Z, 12 minutes, RTX 3080 (pc3080)
mining an Everett KawPow devnet through `kawpow-stratum`.

## Result

| Metric | getwork baseline | stratum sidecar |
|---|---|---|
| Blocks produced | 253 then stalled | 1368 in 12 min |
| Mining suspensions | 936 | 0 |
| Accepted-share log lines | 0 (none reported) | 0 |
| Blocks logged by sidecar | n/a | 1479 |
| Difficulty | 131,072 → 4M then stalled | 131427 → 72890515 |
| Last reported speed | never reported |  |

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
