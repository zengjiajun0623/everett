# Security

## Reporting

Consensus bugs, monetary-accounting discrepancies, or client
vulnerabilities: open a GitHub security advisory on this repo, or a
private report to the maintainer. Wheeler testnet coins are valueless;
demonstrations on Wheeler are welcome and encouraged.

## Upstream base and CVE posture

Everett is a small consensus delta on core-geth, pinned to a single
commit (`COREGETH_COMMIT` in docker/node.Dockerfile and
scripts/ci_prepare.sh; the consistency gate asserts the two never
diverge). The pinned tree carries go-ethereum 1.13.15 as its foundation
plus core-geth's own backports.

That base predates some upstream go-ethereum advisories whose fixes are
not yet visible in core-geth's tree (denial-of-service class, per
version-range analysis; details of several are undisclosed upstream).
Posture:

- The pin is bumped deliberately, never implicitly: a new upstream
  release is reviewed, the pin updated in both places, and every gate
  (schedule, DAA enumeration, KawPow vectors, Lean proofs, devnet e2e)
  re-run before adoption.
- The consensus delta itself does not touch networking or RLP paths,
  so upstream network-layer fixes port cleanly.
- Client maintenance funding is a documented structural question
  (GENESIS_SPEC §5 item 4): the constitution deliberately provides no
  treasury, so upstream tracking is patronage work, in the open.

## What is verified, and how

Every constitutional article is enforced by executable gates (CI on
every push) and, for the monetary schedule and difficulty filter, by
machine-checked proofs (fv/) and exhaustive enumeration. The full audit
trail, including failures, lives in RUNBOOK.md.
