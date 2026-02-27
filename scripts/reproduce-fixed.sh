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

for p in 3000 3001 3002; do
  pids="$(lsof -ti :"$p" 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    kill $pids 2>/dev/null || true
    sleep 1
    remaining="$(lsof -ti :"$p" 2>/dev/null || true)"
    if [[ -n "$remaining" ]]; then
      kill -9 $remaining 2>/dev/null || true
      sleep 1
    fi
  fi
done

echo "==> Installing dependencies..."
npm install --silent 2>/dev/null || npm install

echo "==> Resetting Next.js package to pristine..."
rm -rf node_modules/next
npm install --silent next@16.1.5 --no-save 2>/dev/null || npm install next@16.1.5 --no-save

echo "==> Cleaning prior build artifacts..."
rm -rf .next .standalone-a .standalone-b

echo "==> Applying Next.js fix patch..."
node scripts/patch-fix.js

echo "==> Verifying patch is present..."
if ! node -e "const fs=require('fs');const p='node_modules/next/dist/client/components/router-reducer/fetch-server-response.js';const s=fs.readFileSync(p,'utf8');process.exit(s.includes('__VERSION_SKEW_EARLY_HEADER_CHECK__')?0:1)"; then
  echo "ERROR: Patch marker not found in Next.js runtime."
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
echo "==> Modifying app for Build B (incompatible export shape)..."
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

export function tripleCount(n: number): number {
  return n * 3;
}
PATCH

cat > app/other/CountDisplay.tsx << 'PATCH'
"use client";

import { formatCount, tripleCount, useCounter } from "@/components/SharedContext";

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
echo "==> Starting Build A on :3001..."
PORT=3001 node .standalone-a/server.js &
sleep 2

echo "==> Starting Build B on :3002..."
PORT=3002 node .standalone-b/server.js &
sleep 2

echo ""
echo "==> Starting proxy on :3000 (A -> B in 10s, with x-build-id headers)..."
echo ""
echo "============================================================"
echo ""
echo "  1. Open http://localhost:3000 NOW"
echo "  2. Enable 'Preserve log' in DevTools Console"
echo "  3. Wait for deploy message (~10 seconds)"
echo "  4. Click 'Other Page'"
echo "  5. Expected: hard reload to Build B, no fatal TypeError"
echo ""
echo "============================================================"
echo ""

node scripts/proxy.js 3001 3002 10 "" "" --build-id-headers

wait
