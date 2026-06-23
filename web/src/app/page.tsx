import Link from "next/link";
import Radar from "@/components/Radar";
import { features, techBadges } from "@/lib/mock";

export default function Home() {
  return (
    <main className="flex-1">
      {/* nav */}
      <header className="sticky top-0 z-10 border-b border-line bg-canvas/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
          <div className="flex items-center gap-2 font-bold text-lg">
            <span>🪺</span>
            <span>Nest Link</span>
          </div>
          <nav className="flex items-center gap-6 text-sm text-ink-dim">
            <a href="#features" className="hover:text-ink">Features</a>
            <a href="#how" className="hover:text-ink">How it works</a>
            <Link
              href="/dashboard"
              className="rounded-full bg-leaf px-4 py-2 font-semibold text-canvas hover:bg-leaf/90"
            >
              Dashboard demo
            </Link>
          </nav>
        </div>
      </header>

      {/* hero */}
      <section className="mx-auto grid max-w-6xl items-center gap-10 px-6 py-20 md:grid-cols-2">
        <div>
          <span className="inline-flex items-center gap-2 rounded-full border border-line bg-panel px-3 py-1 text-xs text-leaf">
            <span className="h-2 w-2 rounded-full bg-leaf glow-leaf" />
            Works with zero internet
          </span>
          <h1 className="mt-6 text-5xl font-extrabold leading-tight tracking-tight">
            Stay linked,
            <br />
            <span className="text-leaf">even offline.</span>
          </h1>
          <p className="mt-5 max-w-md text-lg text-ink-dim">
            Nest Link keeps your family connected and safe when the towers go
            down — messages, locations, and check-ins hop phone-to-phone over an
            offline mesh, then sync to the cloud the moment a signal returns.
          </p>
          <div className="mt-8 flex gap-4">
            <Link
              href="/dashboard"
              className="rounded-full bg-leaf px-6 py-3 font-semibold text-canvas hover:bg-leaf/90"
            >
              View the dashboard →
            </Link>
            <a
              href="#how"
              className="rounded-full border border-line px-6 py-3 font-semibold hover:border-leaf"
            >
              How the mesh works
            </a>
          </div>
        </div>
        <div className="flex justify-center">
          <div className="rounded-3xl border border-line bg-canvas-2 p-6 glow-leaf">
            <Radar size={300} />
            <p className="mt-2 text-center text-xs text-ink-dim">
              Offline proximity radar · live in the app
            </p>
          </div>
        </div>
      </section>

      {/* features */}
      <section id="features" className="border-t border-line bg-canvas-2/40 py-20">
        <div className="mx-auto max-w-6xl px-6">
          <h2 className="text-center text-3xl font-bold">Three premium family utilities</h2>
          <p className="mx-auto mt-3 max-w-xl text-center text-ink-dim">
            Each one runs on the same offline mesh infrastructure underneath.
          </p>
          <div className="mt-12 grid gap-6 md:grid-cols-3">
            {features.map((f) => (
              <div
                key={f.key}
                className="rounded-2xl border border-line bg-panel p-6 transition hover:border-leaf"
              >
                <div className="text-3xl">{f.icon}</div>
                <div className="mt-4 flex items-center gap-2">
                  <h3 className="text-xl font-bold">{f.name}</h3>
                  <span className="rounded-full bg-leaf/15 px-2 py-0.5 text-xs text-leaf">
                    {f.tag}
                  </span>
                </div>
                <p className="mt-3 text-sm text-ink-dim">{f.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* how it works */}
      <section id="how" className="py-20">
        <div className="mx-auto max-w-6xl px-6">
          <h2 className="text-center text-3xl font-bold">How a Chirp gets home with no signal</h2>
          <div className="mt-12 grid gap-6 md:grid-cols-3">
            {[
              { n: "1", t: "Store", d: "Your phone encrypts the message and holds onto it — no tower needed.", i: "🔒" },
              { n: "2", t: "Carry", d: "When a family member passes nearby, the encrypted packet hops onto their phone over Wi-Fi Direct.", i: "🚶" },
              { n: "3", t: "Forward", d: "It keeps hopping device-to-device until it reaches the right person. Then it chirps.", i: "🪺" },
            ].map((s) => (
              <div key={s.n} className="rounded-2xl border border-line bg-panel p-6">
                <div className="flex items-center gap-3">
                  <span className="flex h-9 w-9 items-center justify-center rounded-full bg-leaf font-bold text-canvas">
                    {s.n}
                  </span>
                  <span className="text-2xl">{s.i}</span>
                </div>
                <h3 className="mt-4 text-lg font-bold">{s.t}</h3>
                <p className="mt-2 text-sm text-ink-dim">{s.d}</p>
              </div>
            ))}
          </div>

          {/* tech badges */}
          <div className="mt-14 flex flex-wrap justify-center gap-3">
            {techBadges.map((b) => (
              <span
                key={b}
                className="rounded-full border border-line bg-canvas-2 px-4 py-2 text-sm text-ink-dim"
              >
                {b}
              </span>
            ))}
          </div>
        </div>
      </section>

      {/* footer */}
      <footer className="border-t border-line py-10 text-center text-sm text-ink-dim">
        <p>🪺 Nest Link — keeping families linked, online or off.</p>
        <Link href="/dashboard" className="mt-2 inline-block text-leaf hover:underline">
          Open the parent dashboard →
        </Link>
      </footer>
    </main>
  );
}
