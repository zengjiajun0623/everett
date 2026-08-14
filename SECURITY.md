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
trail, including failures, lives in RUNBOOK.md, whose status log runs
through audit round 4 (6e96e89, the tip when this was written). If the
log's last entry is older than the commits you are reading, treat the
difference as unreviewed rather than as nothing having happened: the log
falling behind the tree is a defect this project has now recorded twice,
in rounds 3 and 4.

Not every gate has been negative-controlled, and RUNBOOK.md scopes which
have, job by job. Of the five CI jobs (.github/workflows/ci.yml), three
have a recorded mutation that turns them red: the consensus unit gates
(KawPow period 3→4), the constitution-vs-implementation gate (decay
constant 993→990, and an era off-by-one at the sweep's boundary blocks),
and the stratum sidecar gates (reverting the worker-name capture fails
the concurrency test under -race). The devnet end-to-end job and the
Lean proof job have nothing on record: no mutation has been shown to
make either fail. Read a green run on those two as "the checks passed",
not as "the checks were shown able to fail". The e2e job is the easiest
to over-credit, since it mines a real chain and audits supply wei-exact,
but none of the three recorded mutations reaches it.
