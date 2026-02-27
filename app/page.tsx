import { Counter } from "@/components/SharedContext";

export const dynamic = "force-dynamic";

export default function Home() {
  return (
    <main>
      <h1>Home Page</h1>
      <p>Click &quot;Other Page&quot; in the nav to trigger a client-side RSC navigation.</p>
      <Counter />
    </main>
  );
}
