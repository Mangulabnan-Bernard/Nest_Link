"use client";

import Link from "next/link";
import { useState } from "react";
import Radar from "@/components/Radar";
import { family, recentChirps, checklist as initialChecklist } from "@/lib/mock";

export default function Dashboard() {
  const [checklist, setChecklist] = useState(initialChecklist);
  const done = checklist.filter((c) => c.done).length;

  return (
    <div className="flex min-h-screen flex-col">
      {/* top bar */}
      <header className="flex items-center justify-between border-b border-line px-6 py-4">
        <div className="flex items-center gap-2 font-bold">
          <span>🪺</span>
          <span>Nest Link</span>
          <span className="ml-2 rounded-full bg-panel px-2 py-0.5 text-xs text-ink-dim">
            Parent dashboard
          </span>
        </div>
        <div className="flex items-center gap-4 text-sm">
          <Link href="/" className="text-ink-dim hover:text-ink">
            ← Home
          </Link>
          <div className="flex items-center gap-2">
            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-leaf font-bold text-canvas">
              ME
            </div>
            <span className="text-ink-dim">Tatay</span>
          </div>
        </div>
      </header>

      <main className="mx-auto grid w-full max-w-6xl flex-1 gap-6 p-6 lg:grid-cols-3">
        {/* family status */}
        <section className="lg:col-span-2">
          <h2 className="mb-3 text-lg font-bold">Family status</h2>
          <div className="grid gap-4 sm:grid-cols-3">
            {family.map((m) => (
              <div key={m.id} className="rounded-2xl border border-line bg-panel p-4">
                <div className="flex items-center gap-3">
                  <div
                    className="flex h-10 w-10 items-center justify-center rounded-full font-bold"
                    style={{ background: `${m.color}30`, color: m.color }}
                  >
                    {m.initials}
                  </div>
                  <div>
                    <div className="font-semibold">{m.name}</div>
                    <div className="flex items-center gap-1 text-xs text-ink-dim">
                      <span
                        className="h-2 w-2 rounded-full"
                        style={{ background: m.online ? "#2ecc71" : "#8a949e" }}
                      />
                      {m.online ? "Online" : m.viaMesh ? "On mesh" : "Offline"}
                    </div>
                  </div>
                </div>
                <div className="mt-3 rounded-lg bg-canvas-2 px-3 py-2 text-sm">
                  {m.status}
                </div>
                <div className="mt-2 text-xs text-ink-dim">
                  {m.distanceM}m away · {m.lastSeen}
                </div>
              </div>
            ))}
          </div>

          {/* recent chirps */}
          <h2 className="mb-3 mt-8 text-lg font-bold">Recent chirps</h2>
          <div className="space-y-2">
            {recentChirps.map((c, i) => (
              <div
                key={i}
                className="flex items-center justify-between rounded-xl border border-line bg-panel px-4 py-3"
              >
                <div>
                  <span className="font-semibold">{c.from}</span>
                  <span className="ml-3 text-ink-dim">{c.text}</span>
                </div>
                <div className="flex items-center gap-3 text-xs text-ink-dim">
                  {c.viaMesh && (
                    <span className="rounded-full bg-leaf/15 px-2 py-0.5 text-leaf">
                      via mesh
                    </span>
                  )}
                  {c.time}
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* right column: radar + checklist */}
        <aside className="space-y-6">
          <div className="rounded-2xl border border-line bg-canvas-2 p-4">
            <h2 className="mb-2 text-lg font-bold">Nest Mat</h2>
            <div className="flex justify-center">
              <Radar size={260} />
            </div>
            <p className="mt-2 text-center text-xs text-ink-dim">
              Offline proximity radar
            </p>
          </div>

          <div className="rounded-2xl border border-line bg-panel p-4">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-lg font-bold">Survival checklist</h2>
              <span className="text-sm font-semibold text-leaf">
                {done}/{checklist.length}
              </span>
            </div>
            <div className="mb-3 h-1.5 overflow-hidden rounded-full bg-canvas-2">
              <div
                className="h-full bg-leaf transition-all"
                style={{ width: `${(done / checklist.length) * 100}%` }}
              />
            </div>
            <ul className="space-y-2">
              {checklist.map((item, i) => (
                <li key={i}>
                  <label className="flex cursor-pointer items-center gap-3 text-sm">
                    <input
                      type="checkbox"
                      checked={item.done}
                      onChange={() =>
                        setChecklist((prev) =>
                          prev.map((p, j) => (j === i ? { ...p, done: !p.done } : p))
                        )
                      }
                      className="h-4 w-4 accent-leaf"
                    />
                    <span className={item.done ? "text-ink-dim line-through" : ""}>
                      {item.text}
                    </span>
                    <span className="ml-auto text-xs text-ink-dim">{item.by}</span>
                  </label>
                </li>
              ))}
            </ul>
          </div>
        </aside>
      </main>
    </div>
  );
}
