#!/usr/bin/env bash
# One-shot end-to-end proof of the stratum sidecar:
#   1. build + unit-test the sidecar
#   2. launch it against the KawPow DEVNET (asserted, never assumed)
#   3. verify it serves a well-formed mining.notify to a raw TCP client
#   4. point the RTX 3080 (pc3080) at it via a Windows scheduled task
#   5. mine for MINUTES minutes, sampling block height and difficulty
#   6. compare against the getwork baseline (churn + stalling)
#   7. stop the miner, write build/STRATUM_E2E_REPORT.md
#
# HERMETIC BY CONSTRUCTION (a DeepSeek-era audit found the old version
# could take down production): dedicated port 3334 (production Wheeler
# sidecar owns 3333 under launchd KeepAlive), the sidecar is killed by
# ITS OWN PID only (never pkill by name), the pc3080 miner is selected
# by command line (only the process dialing :3334; the production
# WheelerGPU miner on :3333 is untouchable), and the devnet's chain ID
# is asserted before any mining starts.
#
# Precondition: a KawPow devnet running with HTTP on :8555 and IPC at
# build/kawpow-dev/geth.ipc (scripts/boot_devnet.sh). The script FAILS
# LOUDLY if that chain is missing or is not chain ID 15537391.
#
# The miner URL scheme MUST be stratum+tcp:// (forces plain mode-0
# stratum). Bare stratum:// autodetects EthereumStratum/2.0.0 → NiceHash
# 1.0.0 → Eth-Proxy and never tries mode 0: the miner then hashes but
# wastes every solution ("Waiting for connection"). Cost one 12-min run
# to learn.
set -uo pipefail
export PATH="/opt/homebrew/bin:$PATH"
EVERETT="$HOME/everett"
LOG="$EVERETT/build/stratum-e2e.log"
REPORT="$EVERETT/build/STRATUM_E2E_REPORT.md"
MAC_IP=192.168.1.172
PAYOUT=0x3000000000000000000000000000000000000003
MINUTES="${MINUTES:-12}"
STRATUM_PORT=3334
DEV_RPC=http://127.0.0.1:8555
DEV_CHAINID=15537391
GETH="$EVERETT/build/core-geth/build/bin/geth"
[ -x "$GETH" ] || GETH="$EVERETT/build/ci/core-geth/build/bin/geth"
IPC="$EVERETT/build/kawpow-dev/geth.ipc"

say() { echo "[$(date +%H:%M:%S)] $*"; }

say "=== 0. assert the devnet (never mine against an assumed chain) ==="
CID=$(curl -s -m 5 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' "$DEV_RPC" \
  | grep -o '0x[0-9a-f]*' || true)
[ -n "$CID" ] || { say "FAIL: no devnet RPC at $DEV_RPC (boot one: scripts/boot_devnet.sh)"; exit 1; }
[ "$((CID))" = "$DEV_CHAINID" ] || { say "FAIL: $DEV_RPC is chain $((CID)), expected $DEV_CHAINID; refusing to mine an unintended chain"; exit 1; }
say "devnet OK: chain $DEV_CHAINID at $DEV_RPC"

say "=== 1. build + test sidecar ==="
cd "$EVERETT/stratum" || exit 1
go test . 2>&1 | tail -3 || { say "UNIT TESTS FAILED"; exit 1; }
go build -o "$EVERETT/build/kawpow-stratum-e2e" . || { say "BUILD FAILED"; exit 1; }

say "=== 2. launch sidecar on :$STRATUM_PORT (production owns :3333) ==="
nohup "$EVERETT/build/kawpow-stratum-e2e" -node "$DEV_RPC" -listen 0.0.0.0:$STRATUM_PORT > "$LOG" 2>&1 &
SIDECAR=$!
# Cleanup kills ONLY what this run started: our sidecar PID and, on
# pc3080, only the miner process whose command line dials :3334.
cleanup() {
  kill "$SIDECAR" 2>/dev/null || true
  ssh pc3080 "powershell -NoProfile -Command \"Get-CimInstance Win32_Process -Filter \\\"Name='kawpowminer.exe'\\\" | Where-Object {\$_.CommandLine -like '*:$STRATUM_PORT*'} | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }; schtasks /delete /tn EverettStratum /f\"" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 4
kill -0 "$SIDECAR" 2>/dev/null || { say "SIDECAR DIED AT START"; cat "$LOG"; exit 1; }
head -3 "$LOG"

say "=== 3. protocol smoke test (raw client) ==="
STRATUM_PORT=$STRATUM_PORT python3 - <<'PY'
import json, os, socket, sys
port = int(os.environ["STRATUM_PORT"])
s = socket.create_connection(("127.0.0.1", port), 5)
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

say "=== 4. start GPU miner on pc3080 (stratum, port $STRATUM_PORT) ==="
H0=$("$GETH" attach --exec 'eth.blockNumber' "$IPC" 2>/dev/null | tr -d '"')
D0=$("$GETH" attach --exec 'eth.getBlock(eth.blockNumber).difficulty' "$IPC" 2>/dev/null | tr -d '"')
[ -n "$H0" ] || { say "FAIL: cannot attach to devnet IPC at $IPC"; exit 1; }
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
# instance's process tree IS the miner. Stopping is PID-scoped in
# cleanup(): only the process dialing :3334 dies, never the production
# WheelerGPU miner on :3333.
cat > /tmp/mine_stratum.cmd <<CMDEOF
@echo off
C:\Users\Jiajun\kawpowminer\kawpowminer.exe -U -P stratum+tcp://$PAYOUT@$MAC_IP:$STRATUM_PORT 2>C:\Users\Jiajun\kawpowminer\strat-e2e.err
CMDEOF
sed -i '' 's/$/\r/' /tmp/mine_stratum.cmd 2>/dev/null || true
scp -q /tmp/mine_stratum.cmd pc3080:mine_stratum.cmd
# Clear any previous E2E task/miner (matched by :3334 command line only).
ssh pc3080 "schtasks /end /tn EverettStratum" >/dev/null 2>&1
ssh pc3080 "powershell -NoProfile -Command \"Get-CimInstance Win32_Process -Filter \\\"Name='kawpowminer.exe'\\\" | Where-Object {\$_.CommandLine -like '*:$STRATUM_PORT*'} | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }\"" >/dev/null 2>&1
ssh pc3080 "schtasks /create /f /tn EverettStratum /tr C:\Users\Jiajun\mine_stratum.cmd /sc once /st 00:00" >/dev/null 2>&1
ssh pc3080 "schtasks /run /tn EverettStratum" >/dev/null 2>&1
sleep 15
# Fail fast if the miner is not actually running: sampling without a
# miner produces a report that quietly measures nothing. Select by
# command line so a concurrently running production miner can never
# satisfy this check.
MINER_PID=$(ssh pc3080 "powershell -NoProfile -Command \"(Get-CimInstance Win32_Process -Filter \\\"Name='kawpowminer.exe'\\\" | Where-Object {\$_.CommandLine -like '*:$STRATUM_PORT*'}).ProcessId\"" 2>/dev/null | tr -d '\r\0 ')
[ -z "$MINER_PID" ] && { say "MINER FAILED TO START on pc3080 (no kawpowminer dialing :$STRATUM_PORT 15s after task run)"; exit 1; }
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
SUSPENDS=$(ssh pc3080 "powershell -NoProfile -Command \"(Get-Content \\\$env:USERPROFILE\\kawpowminer\\strat-e2e.err -ErrorAction SilentlyContinue | Select-String 'Suspend mining').Count\"" 2>/dev/null | tr -d '\r\0' | tail -1)
ACCEPTED=$(ssh pc3080 "powershell -NoProfile -Command \"(Get-Content \\\$env:USERPROFILE\\kawpowminer\\strat-e2e.err -ErrorAction SilentlyContinue | Select-String 'Accepted').Count\"" 2>/dev/null | tr -d '\r\0' | tail -1)
SPEED=$(ssh pc3080 "powershell -NoProfile -Command \"(Get-Content \\\$env:USERPROFILE\\kawpowminer\\strat-e2e.err -ErrorAction SilentlyContinue | Select-String 'Speed' | Select-Object -Last 1)\"" 2>/dev/null | tr -d '\r\0' | tail -1)
BLOCKS_LOGGED=$(grep -c "BLOCK:" "$LOG" 2>/dev/null) || BLOCKS_LOGGED=0

say "=== 7. stop miner + audit ==="
# PID-scoped stop (also runs in the EXIT trap; doing it here too keeps
# the audit below clean of mining races).
ssh pc3080 "powershell -NoProfile -Command \"Stop-Process -Id $MINER_PID -Force -ErrorAction SilentlyContinue; schtasks /delete /tn EverettStratum /f\"" >/dev/null 2>&1
AUDIT=$(RPC=$DEV_RPC EXPECT_CHAINID=$DEV_CHAINID python3 "$EVERETT/scripts/burn_audit.py" 2>&1 | tail -2)

cat > "$REPORT" <<EOF
# Stratum sidecar: end-to-end result

Run: $(date -u +"%Y-%m-%dT%H:%M:%SZ"), $MINUTES minutes, RTX 3080 (pc3080)
mining an Everett KawPow devnet through \`kawpow-stratum\` on :$STRATUM_PORT.

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
