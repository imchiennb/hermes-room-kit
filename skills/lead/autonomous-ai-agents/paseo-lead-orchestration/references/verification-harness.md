# Verification Harness — Proof-Only Peer Patterns

Applies when the peer's role is **proof only** (no product code changes): the peer runs a server, exercises HTTP endpoints, queries DB/cache directly, and captures real wire output.

## Discriminating Test Design

Do NOT assert only the default outcome — that proves nothing when the default and the target value are the same.

**Rule**: for every branch under test, exercise it with BOTH a value that matches the default AND a value that differs from the default. Only the differing-value assertion proves the branch actually wrote the requested role/state rather than silently falling through.

Example — an alternate input branch whose default role differs from the requested one:
```
 BAD:  add user B through the org branch with role=MEMBER → assert MEMBER  ← proves nothing (default == asserted)
 GOOD: add user B through the org branch with role=MEMBER → assert MEMBER  (matches the default: sanity only)
       add user C through the org branch with role=ADMIN  → assert ADMIN   (differs from the default → discriminating)
       add user D through the org branch with role=null   → assert MEMBER  (null = no patch; default preserved)
```

The null/omitted-role control is equally important: it proves the patch path is guarded (`if role != null`) and does not overwrite the default with `null` or `undefined`.

## Fixture Strategy for Auth-Gated APIs

When there is no login endpoint (or it is stubbed), mint JWTs directly:
```js
const jwt = require('<nm>/jsonwebtoken');
const token = jwt.sign(
  { id: userId, sub: userId, companyId, role: 'USER' },
  process.env.SERVER_JWT_SECRET,
  { expiresIn: '1h' }
);
```
Seed Mongo + Redis directly for fixtures rather than going through the API — avoids dependency on endpoints under test contaminating the fixture state.

Tag every inserted document with a sentinel field (e.g. `_roomTest: true`, `_testRun: '<scope>'`) for targeted cleanup:
```js
// cleanup — never use dropCollection or deleteMany without a filter
await col.deleteMany({ _roomTest: true });
```

## WebSocket Proof Requirements

A claim that a socket event was emitted is only evidence when:
1. A **real socket.io-client** connects before the action is triggered (not polled after).
2. The **raw engine.io wire frames** are captured (`IN 2["EVENT_NAME",{...}]`), not just the decoded event object.
3. **Negative controls** are run: the same action with the trigger condition NOT met must produce no event.
4. The **DB state after** is read directly from Mongo and matches the emitted payload.

Capture wire frames via:
```js
client.io.engine.on('packet', (p) => rawFrames.push(`IN  ${p.data}`));
client.io.engine.on('packetCreate', (p) => rawFrames.push(`OUT ${p.data}`));
```
Engine.io message type `2` = socket.io EVENT frame. Wire frames appear as `IN 2["EVENT_NAME",{payload}]`.

## Webhook HMAC Signing

Webhook endpoints typically require HMAC `X-Webhook-Signature` over `timestamp.body`:
```js
const body = JSON.stringify(payload);
const ts = Date.now().toString();
const sig = crypto.createHmac('sha256', process.env.WEBHOOK_SECRET)
  .update(`${ts}.${body}`).digest('hex');
// headers: 'X-Webhook-Timestamp': ts, 'X-Webhook-Signature': sig
```
Do NOT print WEBHOOK_SECRET or any credential; only print the signature prefix for evidence.

## Evidence Artifact Structure

Write all output to a JSON file (`/tmp/<scope>-evidence.json`) via `JSON.stringify(out, null, 2)` so the Lead can read it directly. The JSON must contain:
- `request`: method, URL, body (sanitized — no secrets), HTTP status, HTTP response body
- `socketFrame`: decoded event name + payload (or `null`)
- `rawSocketWire`: array of raw engine.io IN/OUT strings
- `dbAfter`: array of relevant document fields from Mongo
- `verdict`: `"PROVEN"` or `"NOT PROVEN"`
- `cleanup`: counts of deleted documents/keys, residual counts (must all be 0)

## Harness Placement

Harness scripts go in `/tmp/` ONLY — never in the repo, never in the worktree (even gitignored paths). The Lead verifies the artifact at `/tmp/<script>.js` and `/tmp/<scope>-evidence.json` without needing the peer to re-run.
