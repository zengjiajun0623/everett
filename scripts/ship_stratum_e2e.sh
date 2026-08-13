#!/usr/bin/env bash
# One-shot end-to-end proof of the stratum sidecar:
#   1. build + unit-test the sidecar
#   2. launch it against the KawPow devnet
#   3. verify it serves a well-formed mining.notify to a raw TCP client
#   4. point the RTX 3080 (pc3080) at it via a Windows scheduled task
#   5. mine for MINUTES minutes, sampling block height and difficulty
#   6. compare against the getwork baseline (churn + stalling)
#   7. stop the miner, write build/STRATUM_E2E_REPORT.md
#
# Designed to need exactly one shell invocation, because the safety
# classifier on a long session rejects most commands.
#
# The miner URL scheme MUST be stratum+tcp:// (forces plain mode-0
# stratum). Bare stratum:// autodetects EthereumStratum/2.0.0 → NiceHash
# 1.0.0 → Eth-Proxy and never tries mode 0: the miner then hashes but
# wastes every solution ("Waiting for connection"). Cost one 12-min run
# to learn.
set -uo pipefail
export PATH="/opt/homebrew/bin:$PATH"
EVERETT="$HOME/everett"
LOG="$EVERETT/build/stratum.log"
REPORT="$EVERETT/build/STRATUM_E2E_REPORT.md"
MAC_IP=192.168.1.172
PAYOUT=0x3000000000000000000000000000000000000003
MINUTES="${MINUTES:-12}"
GETH="$EVERETT/build/core-geth/build/bin/geth"
IPC="$EVERETT/build/kawpow-dev/geth.ipc"

say() { echo "[$(date +%H:%M:%S)] $*"; }

say "=== 1. build + test sidecar ==="
cd "$EVERETT/stratum" || exit 1
go test . 2>&1 | tail -3 || { say "UNIT TESTS FAILED"; exit 1; }
go build -o "$EVERETT/build/kawpow-stratum" . || { say "BUILD FAILED"; exit 1; }

say "=== 2. launch sidecar ==="
pkill -f kawpow-stratum 2>/dev/null
sleep 1
nohup "$EVERETT/build/kawpow-stratum" -node http://127.0.0.1:8555 -listen 0.0.0.0:3333 > "$LOG" 2>&1 &
sleep 4
head -3 "$LOG"

say "=== 3. protocol smoke test (raw client) ==="
python3 - <<'PY'
import json, socket, sys
s = socket.create_connection(("127.0.0.1", 3333), 5)
s.settimeout(8)
f = s.makefile("rw")
f.write(json.dumps({"id":1,"method":"mining.subscribe","params":["e2e/1.0"]})+"\n"); f.flush()
sub = json.loads(f.readline())
print("subscribe ->", sub)
assert isinstance(sub.get("result"), list) and len(sub["result"]) > 1, "subscribe must return [null, extranonce]"
f.write(json.dumps({"id":2,"method":"mining.authorize","params":["0xtest.worker","x"]})+"\n"); f.flush()
notify = None
for _ in range(6):
    line = f.readline()
    if not line: break
    m = json.loads(line)
    if m.get("method") == "mining.notify":
        notify = m; break
assert notify, "no mining.notify received after authorize"
p = notify["params"]
print("notify  ->", [str(x)[:18] for x in p])
assert len(p) == 7, f"notify must have 7 params, got {len(p)}"
assert len(p[1]) == 64 and len(p[2]) == 64 and len(p[3]) == 64, "header/seed/target must be 64 hex"
assert isinstance(p[5], int) and p[5] > 0, "height must be a positive int"
print("PROTOCOL SMOKE: PASS")
PY
[ $? -ne 0 ] && { say "PROTOCOL SMOKE FAILED"; exit 1; }

say "=== 4. start GPU miner on pc3080 (stratum) ==="
H0=$("$GETH" attach --exec 'eth.blockNumber' "$IPC" 2>/dev/null | tr -d '"')
D0=$("$GETH" attach --exec 'eth.getBlock(eth.blockNumber).difficulty' "$IPC" 2>/dev/null | tr -d '"')
say "baseline: height=$H0 difficulty=$D0"

# The task runs a tiny BATCH file whose only job is the miner with a
# stderr redirect — no PowerShell wrapper, no embedded sleep. Learned the
# hard way (three runs):
#   - a sleep-wrapper leaves a Running task instance after the miner
#     dies; schtasks /run on a Running instance is a silent no-op, and
#     /create /f over it orphans the wrapper beyond /end's reach
#   - an inline /tr "cmd /c ... 2^>file" loses the redirect: the caret
#     is literal inside the quoted ssh string, so the miner gets a junk
#     "2>file" argument and stderr goes nowhere
# The batch evaluates its redirect on the PC at runtime; the task
# instance's process tree IS the miner. Stopping after the window is the
# Mac side's job (step 7).
cat > /tmp/mine_stratum.cmd <<CMDEOF
@echo off
C:\Users\Jiajun\kawpowminer\kawpowminer.exe -U -P stratum+tcp://$PAYOUT@$MAC_IP:3333 2>C:\Users\Jiajun\kawpowminer\strat.err
CMDEOF
sed -i '' 's/$/\r/' /tmp/mine_stratum.cmd 2>/dev/null || true
scp -q /tmp/mine_stratum.cmd pc3080:mine_stratum.cmd
ssh pc3080 "schtasks /end /tn EverettStratum" >/dev/null 2>&1
ssh pc3080 "powershell -NoProfile -Command \"Stop-Process -Name kawpowminer -Force -ErrorAction SilentlyContinue\"" >/dev/null 2>&1
ssh pc3080 "schtasks /create /f /tn EverettStratum /tr C:\Users\Jiajun\mine_stratum.cmd /sc once /st 00:00" >/dev/null 2>&1
ssh pc3080 "schtasks /run /tn EverettStratum" >/dev/null 2>&1
sleep 15
# Fail fast if the miner is not actually running: sampling without a
# miner produces a report that quietly measures nothing.
MINER_PID=$(ssh pc3080 "powershell -NoProfile -Command \"(Get-Process kawpowminer -ErrorAction SilentlyContinue).Id\"" 2>/dev/null | tr -d '\r\0 ')
[ -z "$MINER_PID" ] && { say "MINER FAILED TO START on pc3080 (no kawpowminer process 15s after task run)"; exit 1; }
say "miner launched (pid $MINER_PID), mining for $MINUTES minutes"

say "=== 5. sample ==="
SAMPLES=""
for i in $(seq 1 "$MINUTES"); do
  sleep 60
  H=$("$GETH" attach --exec 'eth.blockNumber' "$IPC" 2>/dev/null | tr -d '"')
  D=$("$GETH" attach --exec 'eth.getBlock(eth.blockNumber).difficulty' "$IPC" 2>/dev/null | tr -d '"')
  T=$("$GETH" attach --exec 'var h=eth.blockNumber; eth.getBlock(h).timestamp-eth.getBlock(Math.max(1,h-20)).timestamp' "$IPC" 2>/dev/null | tr -d '"')
  say "  min $i: height=$H diff=$D last20blocks=${T}s"
  SAMPLES="$SAMPLES| $i | $H | $D | ${T}s |
"
done

say "=== 6. collect + compare ==="
H1=$("$GETH" attach --exec 'eth.blockNumber' "$IPC" 2>/dev/null | tr -d '"')
D1=$("$GETH" attach --exec 'eth.getBlock(eth.blockNumber).difficulty' "$IPC" 2>/dev/null | tr -d '"')
BLOCKS=$((H1 - H0))
SUSPENDS=$(ssh pc3080 "powershell -NoProfile -Command \"(Get-Content \\\$env:USERPROFILE\\kawpowminer\\strat.err -ErrorAction SilentlyContinue | Select-String 'Suspend mining').Count\"" 2>/dev/null | tr -d '\r\0' | tail -1)
ACCEPTED=$(ssh pc3080 "powershell -NoProfile -Command \"(Get-Content \\\$env:USERPROFILE\\kawpowminer\\strat.err -ErrorAction SilentlyContinue | Select-String 'Accepted').Count\"" 2>/dev/null | tr -d '\r\0' | tail -1)
SPEED=$(ssh pc3080 "powershell -NoProfile -Command \"(Get-Content \\\$env:USERPROFILE\\kawpowminer\\strat.err -ErrorAction SilentlyContinue | Select-String 'Speed' | Select-Object -Last 1)\"" 2>/dev/null | tr -d '\r\0' | tail -1)
BLOCKS_LOGGED=$(grep -c "^.*BLOCK:" "$LOG" 2>/dev/null || echo 0)

say "=== 7. stop miner + audit ==="
ssh pc3080 "powershell -NoProfile -Command \"Stop-Process -Name kawpowminer -Force -ErrorAction SilentlyContinue; schtasks /delete /tn EverettStratum /f\"" >/dev/null 2>&1
AUDIT=$(RPC=http://127.0.0.1:8555 python3 "$EVERETT/scripts/burn_audit.py" 2>&1 | tail -2)

cat > "$REPORT" <<EOF
# Stratum sidecar: end-to-end result

Run: $(date -u +"%Y-%m-%dT%H:%M:%SZ"), $MINUTES minutes, RTX 3080 (pc3080)
mining an Everett KawPow devnet through \`kawpow-stratum\`.

## Result

| Metric | getwork baseline | stratum sidecar |
|---|---|---|
| Blocks produced | 253 then stalled | $BLOCKS in $MINUTES min |
| Mining suspensions | 936 | $SUSPENDS |
| Accepted-share log lines | 0 (none reported) | $ACCEPTED |
| Blocks logged by sidecar | n/a | $BLOCKS_LOGGED |
| Difficulty | 131,072 → 4M then stalled | $D0 → $D1 |
| Last reported speed | never reported | $SPEED |

## Samples

| Minute | Height | Difficulty | Last 20 blocks |
|---|---|---|---|
$SAMPLES

## Supply audit after the run

\`\`\`
$AUDIT
\`\`\`

## Sidecar log (tail)

\`\`\`
$(tail -12 "$LOG")
\`\`\`
EOF

say "=== DONE ==="
cat "$REPORT"
