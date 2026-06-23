import { family } from "@/lib/mock";

/** SVG proximity radar mirroring the mobile Nest Mat. */
export default function Radar({ size = 320 }: { size?: number }) {
  const c = size / 2;
  const maxR = c - 6;
  const maxDist = 360;

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="select-none">
      <defs>
        <radialGradient id="nest" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#2ecc71" stopOpacity="0.25" />
          <stop offset="100%" stopColor="#2ecc71" stopOpacity="0" />
        </radialGradient>
        <linearGradient id="sweep" x1="50%" y1="50%" x2="100%" y2="50%">
          <stop offset="0%" stopColor="#2ecc71" stopOpacity="0.35" />
          <stop offset="100%" stopColor="#2ecc71" stopOpacity="0" />
        </linearGradient>
      </defs>

      {/* rings */}
      {[1, 2, 3, 4].map((i) => (
        <circle key={i} cx={c} cy={c} r={(maxR * i) / 4} fill="none" stroke="#2ecc71" strokeOpacity={0.2} />
      ))}
      {/* crosshairs */}
      <line x1={c} y1={0} x2={c} y2={size} stroke="#2ecc71" strokeOpacity={0.1} />
      <line x1={0} y1={c} x2={size} y2={c} stroke="#2ecc71" strokeOpacity={0.1} />

      {/* rotating sweep */}
      <g className="radar-sweep" style={{ transformOrigin: "center" }}>
        <path d={`M ${c} ${c} L ${size} ${c} A ${maxR} ${maxR} 0 0 0 ${c + maxR * Math.cos(-0.6)} ${c + maxR * Math.sin(-0.6)} Z`} fill="url(#sweep)" />
      </g>

      {/* home nest */}
      <circle cx={c} cy={c} r={22} fill="url(#nest)" />
      <text x={c} y={c + 7} textAnchor="middle" fontSize="20">🏠</text>

      {/* members */}
      {family.map((m) => {
        const r = Math.min(0.95, Math.max(0.12, m.distanceM / maxDist)) * maxR;
        const x = c + Math.cos(m.bearing) * r;
        const y = c + Math.sin(m.bearing) * r;
        return (
          <g key={m.id}>
            <circle cx={x} cy={y} r={16} fill={m.color} fillOpacity={0.18} />
            <circle cx={x} cy={y} r={13} fill="#101316" stroke={m.color} strokeWidth={2} />
            <text x={x} y={y + 3} textAnchor="middle" fontSize="9" fontWeight="bold" fill={m.color}>
              {m.initials}
            </text>
          </g>
        );
      })}
    </svg>
  );
}
