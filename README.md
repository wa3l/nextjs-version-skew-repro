# Next.js rolling deploy version-skew repro

This repository demonstrates a real runtime failure window during rolling deploys:

1. Browser boots with **Build A** client runtime in memory.
2. Navigation fetch hits **Build B** and returns Build B Flight data.
3. Decoder/runtime resolves modules before build-id mismatch handling can recover.
4. Browser can throw fatal runtime errors (`TypeError`, `ChunkLoadError`) instead of cleanly reloading first.

## Versions

- **next**: 16.1.5
- **react**: 19.x
- **Node.js**: 20+

## Why this matters

In `fetch-server-response.js`, decode can start from `createFetch` before `flightResponse.b` is checked later in `fetchServerResponse`.

- decode path starts early (`createFromNextFetch(...)`)
- build-id mismatch check happens after awaiting decoded Flight payload

That ordering means incompatible modules/chunks can execute first.

## Reproduce the bug (fatal error)

```bash
./scripts/reproduce.sh
```

Then:

1. Open `http://localhost:3000` immediately.
2. In DevTools Console, enable **Preserve log**.
    <img width="828" height="182" alt="Screenshot 2026-02-26 at 4 31 54 PM" src="https://github.com/user-attachments/assets/e3249208-5ea9-4f93-b9ca-1a85d48a312c" />

4. Wait for deploy message (~10s).
5. Click **Other Page** (links use `prefetch={false}` so this is a fresh request).

Expected result:

- Fatal runtime error, typically:
  - `Uncaught TypeError: (0 , n.tripleCount) is not a function`
  - sometimes `ChunkLoadError` depending on environment

How this script forces skew:

- pre-deploy traffic -> Build A
- post-deploy traffic -> Build B
- one Build B chunk URL is intentionally served with Build A bytes to force incompatible bindings at module evaluation

## Demo patched behavior (no fatal error first)

```bash
./scripts/reproduce-fixed.sh
```

What this does:

1. Resets `node_modules/next`.
2. Applies `scripts/patch-fix.js` to Next internals:
   - defer decode in `createFetch`
   - check `x-build-id` before decoding in `fetchServerResponse`
3. Runs the same A->B deploy scenario, with proxy injecting `x-build-id`.

Expected result:

- client hard-navigates/reloads on mismatch
- console logs: `[version-skew-fix] Early build mismatch detected; forcing hard reload`
- no fatal `tripleCount is not a function` before recovery
- if nothing happens on click, hard refresh once and retry to ensure a fresh client state

## Scripts

- `scripts/reproduce.sh`: bug repro with deterministic fatal runtime break.
- `scripts/reproduce-fixed.sh`: patched Next demo path.
- `scripts/patch-fix.js`: applies early header-check patch to local `node_modules/next`.
- `scripts/proxy.js`: A/B switch proxy with optional poisoned chunk mapping and optional `x-build-id` header injection.
