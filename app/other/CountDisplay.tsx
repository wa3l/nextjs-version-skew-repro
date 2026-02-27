"use client";

import { formatCount, doubleCount, useCounter } from "@/components/SharedContext";

export function CountDisplay() {
  const { count } = useCounter();
  return (
    <div style={{ marginTop: 16, fontFamily: "monospace" }}>
      <p>formatCount({count}) = {formatCount(count)}</p>
      <p>doubleCount({count}) = {doubleCount(count)}</p>
    </div>
  );
}
