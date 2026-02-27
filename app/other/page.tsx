import { Counter } from "@/components/SharedContext";
import { CountDisplay } from "./CountDisplay";

export const dynamic = "force-dynamic";

export default function OtherPage() {
  return (
    <main>
      <h1>Other Page</h1>
      <p>This page also uses SharedContext exports.</p>
      <Counter />
      <CountDisplay />
    </main>
  );
}
