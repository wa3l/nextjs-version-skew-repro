#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

cleanup() {
  if [[ -f components/SharedContext.tsx.original ]]; then
    mv components/SharedContext.tsx.original components/SharedContext.tsx
  fi
  if [[ -f app/other/CountDisplay.tsx.original ]]; then
    mv app/other/CountDisplay.tsx.original app/other/CountDisplay.tsx
  fi
  kill $(jobs -p) 2>/dev/null || true
}
trap cleanup EXIT

# Kill anything on our ports and verify they are free
for p in 3000 3001 3002; do
  pids="$(lsof -ti :"$p" 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    echo "==> Port :$p in use, terminating PID(s): $pids"
    kill $pids 2>/dev/null || true
    sleep 1
    remaining="$(lsof -ti :"$p" 2>/dev/null || true)"
    if [[ -n "$remaining" ]]; then
      echo "==> Force killing remaining PID(s) on :$p: $remaining"
      kill -9 $remaining 2>/dev/null || true
      sleep 1
    fi
  fi
  if lsof -ti :"$p" >/dev/null 2>&1; then
    echo "ERROR: Could not free required port :$p"
    exit 1
  fi
done

echo "==> Installing dependencies..."
npm install --silent 2>/dev/null || npm install

echo "==> Resetting Next.js package to pristine (remove local patches/instrumentation)..."
rm -rf node_modules/next
npm install --silent next@16.1.5 --no-save 2>/dev/null || npm install next@16.1.5 --no-save

echo "==> Cleaning prior build artifacts..."
rm -rf .next .standalone-a .standalone-b

echo "==> Verifying Next.js internals are unpatched..."
if node -e "const fs=require('fs');const p='node_modules/next/dist/client/components/router-reducer/fetch-server-response.js';const s=fs.readFileSync(p,'utf8');const bad=['[1] Flight decoding STARTED','[2] Build ID check','buildIdMismatch','early header check','__VERSION_SKEW_EARLY_HEADER_CHECK__'];process.exit(bad.some(x=>s.includes(x))?0:1)"; then
  echo "ERROR: Detected patched/instrumented Next.js internals in node_modules. Aborting."
  exit 1
fi

cp components/SharedContext.tsx components/SharedContext.tsx.original
cp app/other/CountDisplay.tsx app/other/CountDisplay.tsx.original

echo ""
echo "==> Building Build A..."
NEXT_PUBLIC_BUILD_ID=build-a npx next build
cp -r .next/standalone .standalone-a
cp -r .next/static .standalone-a/.next/static
echo "    Build A saved."

echo ""
echo "==> Modifying SharedContext.tsx + CountDisplay.tsx for Build B..."
cat > components/SharedContext.tsx << 'PATCH'
"use client";

import { createContext, useContext, useState, type ReactNode } from "react";

interface CounterState {
  count: number;
  increment: () => void;
  decrement: () => void;
}

const CounterContext = createContext<CounterState | null>(null);

export function CounterProvider({ children }: { children: ReactNode }) {
  const [count, setCount] = useState(0);
  return (
    <CounterContext.Provider
      value={{
        count,
        increment: () => setCount((c) => c + 1),
        decrement: () => setCount((c) => c - 1),
      }}
    >
      {children}
    </CounterContext.Provider>
  );
}

export function useCounter() {
  const ctx = useContext(CounterContext);
  if (!ctx) throw new Error("useCounter must be used within CounterProvider");
  return ctx;
}

export function Counter() {
  const { count, increment, decrement } = useCounter();
  return (
    <div style={{ padding: 16, border: "1px solid #ccc", borderRadius: 8 }}>
      <h2>Counter: {count}</h2>
      <button onClick={decrement} style={{ marginRight: 8 }}>
        -
      </button>
      <button onClick={increment}>+</button>
    </div>
  );
}

export function formatCount(n: number): string {
  return `Current count is: ${n}`;
}

export function doubleCount(n: number): number {
  return n * 2;
}

// BUILD B ONLY: this export does not exist in Build A.
export function tripleCount(n: number): number {
  return n * 3;
}
PATCH

cat > app/other/CountDisplay.tsx << 'PATCH'
"use client";

import { formatCount, tripleCount, useCounter } from "@/components/SharedContext";

// Force use at module evaluation so missing export crashes immediately.
const BUILD_B_SENTINEL = tripleCount(2);

export function CountDisplay() {
  const { count } = useCounter();
  return (
    <div style={{ marginTop: 16, fontFamily: "monospace" }}>
      <p>formatCount({count}) = {formatCount(count)}</p>
      <p>tripleCount({count}) = {tripleCount(count)}</p>
      <p>sentinel = {BUILD_B_SENTINEL}</p>
    </div>
  );
}
PATCH

echo ""
echo "==> Building Build B..."
NEXT_PUBLIC_BUILD_ID=build-b npx next build
cp -r .next/standalone .standalone-b
cp -r .next/static .standalone-b/.next/static
echo "    Build B saved."

echo ""
echo "==> Detecting changed client chunk between Build A and Build B..."
manifest_a=".standalone-a/.next/server/app/other/page_client-reference-manifest.js"
manifest_b=".standalone-b/.next/server/app/other/page_client-reference-manifest.js"
chunk_a_path="$(node -e "const fs=require('fs');const vm=require('vm');const code=fs.readFileSync(process.argv[1],'utf8');const ctx={globalThis:{}};vm.runInNewContext(code,ctx);const m=ctx.globalThis.__RSC_MANIFEST['/other/page'];const arr=(m.entryJSFiles&&m.entryJSFiles['[project]/app/layout'])||[];if(!arr.length)process.exit(2);console.log(arr[0]);" "$manifest_a")"
chunk_b_path="$(node -e "const fs=require('fs');const vm=require('vm');const code=fs.readFileSync(process.argv[1],'utf8');const ctx={globalThis:{}};vm.runInNewContext(code,ctx);const m=ctx.globalThis.__RSC_MANIFEST['/other/page'];const arr=(m.entryJSFiles&&m.entryJSFiles['[project]/app/layout'])||[];if(!arr.length)process.exit(2);console.log(arr[0]);" "$manifest_b")"
chunk_a_file="$(basename "$chunk_a_path")"
chunk_b_file="$(basename "$chunk_b_path")"
echo "    Build A layout chunk: $chunk_a_file"
echo "    Build B layout chunk: $chunk_b_file"
if [[ "$chunk_a_file" == "$chunk_b_file" ]]; then
  echo "ERROR: Expected different chunk filenames between builds; cannot poison mapping deterministically."
  exit 1
fi

echo ""
echo "==> Starting Build A on :3001..."
PORT=3001 node .standalone-a/server.js &
sleep 2

echo "==> Starting Build B on :3002..."
PORT=3002 node .standalone-b/server.js &
sleep 2

echo ""
echo "==> Starting proxy on :3000 (Build A → Build B in 10s)..."
echo ""
echo "============================================================"
echo ""
echo "  1. Open http://localhost:3000 NOW"
echo "  2. Enable 'Preserve log' in DevTools Console"
echo "  3. Wait for the 'DEPLOYED' message below (~10 seconds)"
echo "  4. Then click 'Other Page' in the browser"
echo "  5. Watch for runtime errors like:"
echo "     - TypeError: ... is not a function"
echo "     - ChunkLoadError"
echo ""
echo "  Press Ctrl+C when done."
echo ""
echo "============================================================"
echo ""

node scripts/proxy.js 3001 3002 10 "$chunk_b_file" "$chunk_a_file"

wait
