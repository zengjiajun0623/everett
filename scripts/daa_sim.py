#!/usr/bin/env python3
"""DAA shock simulator for the G3 decision: Byzantium DAA vs LWMA-45.

Deterministic: solvetime = difficulty / hashrate (expected value). This is
the right tool for comparing adjustment *dynamics*; Poisson jitter changes
the noise floor, not the convergence shape.

Byzantium (EIP-100, bomb excluded, no uncles):
    adj = max(1 - solvetime // 9, -99);  D += (D // 2048) * adj;  D >= 131072
LWMA-45 (zawy12 LWMA-1 style), target T = 13 s:
    weighted mean solvetime over last N blocks (linear weights, recent heavy),
    next_D = avg_D * T / t_weighted, solvetimes clamped to [1, 6T].
"""

MIN_DIFF = 131_072
TARGET = 13
N = 45


def byzantium_next(d, st):
    adj = max(1 - st // 9, -99)
    return max(d + (d // 2048) * adj, MIN_DIFF)


def lwma_next(diffs, sts):
    n = len(sts)
    weights = range(1, n + 1)
    tw = sum(w * min(max(st, 1), 6 * TARGET) for w, st in zip(weights, sts))
    tw /= sum(weights)
    avg_d = sum(diffs) / n
    return max(int(avg_d * TARGET / max(tw, 1)), MIN_DIFF)




# --- ASERT (decision v2) ---------------------------------------------------
ASERT_TAU = 1800

def asert_next(d, st):
    """Relative ASERT: D * 2^(-(st-T)/tau), exponent capped to one
    halving/doubling per block, st clamped to [1, 6*tau]."""
    x = (min(max(st, 1), 6 * ASERT_TAU) - TARGET) / ASERT_TAU
    x = max(-1.0, min(1.0, x))
    return max(int(d * 2 ** (-x)), MIN_DIFF)


def simulate(name, daa, d0, phases, max_blocks=30_000):
    """phases: list of (n_blocks, hashrate). Returns metrics + trace summary."""
    d, t = d0, 0.0
    diffs, sts = [d0] * N, [TARGET] * N
    conv_at, conv_time, streak = None, None, 0
    max_st, blocks = 0.0, 0
    for n_blocks, h in phases:
        for _ in range(n_blocks):
            st = max(1, round(d / h))
            t += st
            blocks += 1
            max_st = max(max_st, st)
            if 9 <= st <= 18:
                streak += 1
                if streak >= 50 and conv_at is None:
                    conv_at, conv_time = blocks, t
            else:
                streak = 0
                conv_at = conv_at  # reset only the streak, keep first conv
            if daa == "byz":
                d = byzantium_next(d, st)
            elif daa == "asert":
                d = asert_next(d, st)
            else:
                diffs.append(d)
                sts.append(st)
                diffs, sts = diffs[-N:], sts[-N:]
                d = lwma_next(diffs, sts)
            if blocks >= max_blocks:
                break
    return {
        "name": name,
        "daa": daa,
        "conv_blocks": conv_at,
        "conv_hours": round(conv_time / 3600, 2) if conv_time else None,
        "max_solvetime_min": round(max_st / 60, 1),
        "final_blocktime": round(d / phases[-1][1], 1),
    }


CPU, GPU, FLEET = 500_000, 90_000_000, 9_000_000_000  # 0.5 MH/s, 90 MH/s, 9 GH/s

SCENARIOS = [
    # A: devnet-style start at min difficulty, one 3080 arrives at block 10
    ("A_flood_gpu", MIN_DIFF, [(10, CPU), (30_000, GPU)]),
    # B: production overshoot: genesis 0x100000000, only one 3080 shows up
    ("B_overshoot", 0x100000000, [(30_000, GPU)]),
    # C: rental exodus: fleet at equilibrium (D ~= FLEET*13), 90% leaves
    ("C_exodus", FLEET * TARGET, [(30_000, FLEET // 10)]),
    # D: NiceHash wave: 10x hashrate for 300 blocks, then gone (repeat 3x)
    ("D_waves", GPU * TARGET, [(300, GPU * 10), (300, GPU)] * 3 + [(2000, GPU)]),
]

print(f"{'scenario':<14}{'daa':<6}{'conv_blocks':<13}{'conv_hours':<12}"
      f"{'max_solve_min':<15}{'final_bt_s':<10}")
for name, d0, phases in SCENARIOS:
    for daa in ("byz", "lwma", "asert"):
        m = simulate(name, daa, d0, phases)
        print(f"{m['name']:<14}{m['daa']:<6}{str(m['conv_blocks']):<13}"
              f"{str(m['conv_hours']):<12}{m['max_solvetime_min']:<15}"
              f"{m['final_blocktime']:<10}")
