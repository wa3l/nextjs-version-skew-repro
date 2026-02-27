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

// BUILD_MARKER: exports below this line are modified by reproduce.sh
