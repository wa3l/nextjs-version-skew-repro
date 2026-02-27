"use client";

import { useEffect, useState } from "react";

const STORAGE_KEY = "version-skew-errors";

export function ErrorCapture() {
  const [errors, setErrors] = useState<string[]>([]);

  useEffect(() => {
    const stored = sessionStorage.getItem(STORAGE_KEY);
    if (stored) {
      try {
        setErrors(JSON.parse(stored));
      } catch {}
    }

    const handler = (event: ErrorEvent) => {
      const entry = `[${new Date().toISOString()}] ${event.message} (${event.filename}:${event.lineno})`;
      const current = JSON.parse(
        sessionStorage.getItem(STORAGE_KEY) || "[]"
      ) as string[];
      current.push(entry);
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify(current));
      setErrors([...current]);
    };

    const rejectionHandler = (event: PromiseRejectionEvent) => {
      const msg =
        event.reason instanceof Error
          ? event.reason.message
          : String(event.reason);
      const entry = `[${new Date().toISOString()}] Unhandled rejection: ${msg}`;
      const current = JSON.parse(
        sessionStorage.getItem(STORAGE_KEY) || "[]"
      ) as string[];
      current.push(entry);
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify(current));
      setErrors([...current]);
    };

    window.addEventListener("error", handler);
    window.addEventListener("unhandledrejection", rejectionHandler);
    return () => {
      window.removeEventListener("error", handler);
      window.removeEventListener("unhandledrejection", rejectionHandler);
    };
  }, []);

  if (errors.length === 0) return null;

  return (
    <div
      style={{
        position: "fixed",
        bottom: 0,
        left: 0,
        right: 0,
        background: "#fee",
        border: "2px solid red",
        padding: 16,
        maxHeight: "40vh",
        overflow: "auto",
        fontFamily: "monospace",
        fontSize: 12,
        zIndex: 9999,
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          marginBottom: 8,
        }}
      >
        <strong>Captured Errors ({errors.length})</strong>
        <button
          onClick={() => {
            sessionStorage.removeItem(STORAGE_KEY);
            setErrors([]);
          }}
        >
          Clear
        </button>
      </div>
      {errors.map((e, i) => (
        <div key={i} style={{ marginBottom: 4 }}>
          {e}
        </div>
      ))}
    </div>
  );
}
