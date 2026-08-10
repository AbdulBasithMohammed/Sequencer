"use client";

import { useState } from "react";

// Density-adaptive SVG trend chart with a hover layer.
//
// The viewBox width is FIXED and the slot width is derived from the point
// count, so 7 days and 180 days both fill the same box — bars thin out
// instead of the chart growing off-screen and scaling down into hairlines.
// Label interval and value labels back off as density rises.
//
// Palette: brand blue #5b7cfa and pink #ff5c8a, validated against the
// cream surface #fffbf3 — CVD separation 18.0 (protan), normal-vision
// 30.3. Pink is 2.85:1 against that surface, under the 3:1 bar, so the
// chart ships a table view (and value labels when sparse enough to fit);
// identity never rests on colour alone.

export const SERIES_1 = "#5b7cfa";
export const SERIES_2 = "#ff5c8a";

const W = 720;
const PLOT = 110;
const TOP = 18;
const BASE = TOP + PLOT;
const H = BASE + 18; // room for the date labels below the baseline

export type Series = { name: string; color: string; values: number[] };

function fmt(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

export function TrendChart({
  days,
  series,
  empty,
}: {
  days: string[];
  series: Series[];
  empty: string;
}) {
  const [hover, setHover] = useState<number | null>(null);

  const n = days.length;
  const totals = days.map((_, i) =>
    series.reduce((sum, s) => sum + (s.values[i] ?? 0), 0),
  );
  const peak = Math.max(...totals, 1);

  if (!totals.some((t) => t > 0)) {
    return <p className="py-8 text-sm text-ink-soft">{empty}</p>;
  }

  const slot = W / n;
  const bar = Math.max(Math.min(slot - Math.min(slot * 0.35, 10), 34), 2);
  // Below ~16 points there is room for a number over every column; past
  // that they collide, and the table view carries the exact figures.
  const showValues = n <= 16;
  const labelEvery = Math.ceil(n / 8);

  return (
    <figure className="m-0">
      {series.length > 1 ? (
        <div className="mb-2 flex flex-wrap gap-x-4 gap-y-1">
          {series.map((s) => (
            <span
              key={s.name}
              className="flex items-center gap-1.5 text-xs text-ink-soft"
            >
              <span
                className="inline-block h-2.5 w-2.5 rounded-[3px]"
                style={{ background: s.color }}
              />
              {s.name}
            </span>
          ))}
        </div>
      ) : null}

      <div className="relative">
        {hover !== null && totals[hover] > 0 ? (
          <div
            className="pointer-events-none absolute z-10 -translate-x-1/2 -translate-y-full rounded-xl border border-line bg-surface px-2.5 py-1.5 text-xs shadow-lg"
            style={{ left: `${((hover + 0.5) / n) * 100}%`, top: 0 }}
          >
            <div className="font-medium">{fmt(days[hover])}</div>
            {series.map((s) => (
              <div key={s.name} className="flex items-center gap-1.5">
                <span
                  className="inline-block h-2 w-2 rounded-[2px]"
                  style={{ background: s.color }}
                />
                <span className="text-ink-soft">{s.name}</span>
                <span className="ml-auto font-semibold tabular-nums">
                  {s.values[hover] ?? 0}
                </span>
              </div>
            ))}
          </div>
        ) : null}

        <svg
          viewBox={`0 0 ${W} ${H}`}
          width="100%"
          height={H}
          preserveAspectRatio="xMidYMax meet"
          role="img"
          aria-label={`${n}-day trend, peak ${peak}`}
          onMouseLeave={() => setHover(null)}
        >
          <line
            x1="0"
            y1={BASE + 0.5}
            x2={W}
            y2={BASE + 0.5}
            stroke="var(--color-line)"
          />

          {days.map((day, i) => {
            const x = i * slot + (slot - bar) / 2;
            let cursor = BASE;
            const total = totals[i];

            return (
              <g key={day}>
                {series.map((s) => {
                  const v = s.values[i] ?? 0;
                  if (v <= 0) return null;
                  // 2px surface gap so stacked segments read as separate
                  // marks rather than one striped block.
                  const h = Math.max((v / peak) * PLOT - 2, 2);
                  const y = cursor - h;
                  cursor = y - 2;
                  return (
                    <rect
                      key={s.name}
                      x={x}
                      y={y}
                      width={bar}
                      height={h}
                      rx={Math.min(3, bar / 2)}
                      fill={s.color}
                      opacity={hover === null || hover === i ? 1 : 0.45}
                    />
                  );
                })}

                {showValues && total > 0 ? (
                  <text
                    x={x + bar / 2}
                    y={cursor - 4}
                    textAnchor="middle"
                    fontSize="10"
                    fontWeight="600"
                    fill="var(--color-ink)"
                  >
                    {total}
                  </text>
                ) : null}

                {i % labelEvery === 0 ? (
                  <text
                    x={x + bar / 2}
                    y={H - 4}
                    textAnchor="middle"
                    fontSize="9"
                    fill="var(--color-ink-soft)"
                  >
                    {fmt(day)}
                  </text>
                ) : null}

                {/* Hit target — full height and the whole slot, so the
                    hover works on near-empty days too. */}
                <rect
                  x={i * slot}
                  y={0}
                  width={slot}
                  height={BASE}
                  fill="transparent"
                  onMouseEnter={() => setHover(i)}
                />
              </g>
            );
          })}
        </svg>
      </div>

      {/* Required relief for the sub-3:1 series colour, and the
          accessibility table view. Also the only readable form of the
          data at 90-day density. */}
      <details className="mt-1">
        <summary className="cursor-pointer text-[11px] text-ink-soft">
          Show data
        </summary>
        <div className="mt-2 max-h-56 overflow-y-auto">
          <table className="w-full text-left text-xs">
            <thead>
              <tr className="text-ink-soft">
                <th className="py-1 font-medium">Day</th>
                {series.map((s) => (
                  <th key={s.name} className="py-1 font-medium">
                    {s.name}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {days
                .map((d, i) => ({ d, i }))
                .filter(({ i }) => totals[i] > 0)
                .reverse()
                .map(({ d, i }) => (
                  <tr key={d} className="border-t border-line">
                    <td className="py-1">{fmt(d)}</td>
                    {series.map((s) => (
                      <td key={s.name} className="py-1 tabular-nums">
                        {s.values[i] ?? 0}
                      </td>
                    ))}
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </details>
    </figure>
  );
}
