import type { Metadata } from "next";
import Link from "next/link";
import { CounterProvider } from "@/components/SharedContext";
import { ErrorCapture } from "@/components/ErrorCapture";

export const metadata: Metadata = {
  title: "Next.js Version Skew Repro",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui, sans-serif", padding: 24 }}>
        <nav style={{ marginBottom: 24, display: "flex", gap: 16 }}>
          <Link href="/" prefetch={false}>
            Home
          </Link>
          <Link href="/other" prefetch={false}>
            Other Page
          </Link>
        </nav>
        <CounterProvider>{children}</CounterProvider>
        <ErrorCapture />
      </body>
    </html>
  );
}
