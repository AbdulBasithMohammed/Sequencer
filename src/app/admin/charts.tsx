"use client";

import { useEffect, useRef, useState } from "react";

// Responsive column chart drawn at 1:1.
//
// The previous version used a fixed 720-unit viewBox scaled to 100% width.
// Inside a half-width card that is roughly a 0.64 scale factor, so a
// font-size of 9 rendered at about 5.7 real pixels — unreadable. Bars
// tolerate being scaled; text does not.
//
// So: measure the container with a ResizeObserver and render the SVG at
// its true pixel size. One viewBox unit is one CSS pixel, so 11px type is
// 11px on screen at any card width.
//
// Palette: brand blue #5b7cfa and pink #ff5c8a, validated against the
// cream surface #fffbf3 — CVD separation 18.0 (protan), normal-vision
// 30.3. Pink is 2.85:1 on that surface, under the 3:1 bar, so the chart
// ships a table view and a legend; identity never rests on colour alone.

export const SERIES_1 = "#5b7cfa";
export const SERIES_2 = "#ff5c8a";

const H = 240;
const M = { top: 14, right: 10, bottom: 30, left: 38 };

export type Series = { name: string; color: string; values: number[] };

function fmtDay(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

// Axis maxima people can read: 1/2/5 x 10^n, never 7 or 13.
function niceMax(v: number) {
  if (v <= 4) return 4;
  const pow = Math.pow(10, Math.floor(Math.log10(v)));
  for (const m of [1, 2, 2.5, 5, 10]) {
    const candidate = m * pow;
    if (candidate >= v) return candidate;
  }
  return 10 * pow;
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
  const ref = useRef<HTMLDivElement>(null);
  const [w, setW] = useState(0);
  const [hover, setHover] = useState<number | null>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) =>
      setW(Math.floor(entry.contentRect.width)),
    );
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const n = days.length;
  const totals = days.map((_, i) =>
    series.reduce((sum, s) => sum + (s.values[i] ?? 0), 0),
  );
  const hasData = totals.some((t) => t > 0);

  const plotW = Math.max(w - M.left - M.right, 10);
  const plotH = H - M.top - M.bottom;
  const max = niceMax(Math.max(...totals, 1));
  const slot = plotW / Math.max(n, 1);
  const bar = Math.max(Math.min(slot * 0.62, 40), 2);
  const y = (v: number) => M.top + plotH - (v / max) * plotH;

  // Four ticks including zero — enough to read a level, few enough to
  // stay out of the way.
  const ticks = [0, max * 0.25, max * 0.5, max * 0.75, max];

  // Thin the date labels to whatever actually fits: ~54px per label.
  const labelEvery = Math.max(1, Math.ceil(n / Math.max(plotW / 54, 1)));

  return (
    <figure className="m-0">
      {series.length > 1 ? (
        <div className="mb-3 flex flex-wrap gap-x-4 gap-y-1">
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

      <div ref={ref} className="relative w-full" style={{ height: H }}>
        {!hasData ? (
          <p className="pt-10 text-sm text-ink-soft">{empty}</p>
        ) : w > 0 ? (
          <>
            {hover !== null ? (
              <div
                className="pointer-events-none absolute z-10 min-w-[132px] rounded-xl border border-line bg-surface px-3 py-2 text-xs shadow-lg"
                style={{
                  left: Math.min(
                    Math.max(M.left + slot * (hover + 0.5) - 66, 0),
                    Math.max(w - 132, 0),
                  ),
                  top: 0,
                }}
              >
                <div className="mb-1 font-medium">{fmtDay(days[hover])}</div>
                {series.map((s) => (
                  <div key={s.name} className="flex items-center gap-2">
                    <span
                      className="inline-block h-2 w-2 shrink-0 rounded-[2px]"
                      style={{ background: s.color }}
                    />
                    <span className="text-ink-soft">{s.name}</span>
                    <span className="ml-auto font-semibold tabular-nums">
                      {s.values[hover] ?? 0}
                    </span>
                  </div>
                ))}
                {series.length > 1 ? (
                  <div className="mt-1 flex items-center gap-2 border-t border-line pt-1">
                    <span className="text-ink-soft">Total</span>
                    <span className="ml-auto font-semibold tabular-nums">
                      {totals[hover]}
                    </span>
                  </div>
                ) : null}
              </div>
            ) : null}

            <svg
              width={w}
              height={H}
              viewBox={`0 0 ${w} ${H}`}
              onMouseLeave={() => setHover(null)}
              role="img"
              aria-label={`${n}-day trend, maximum ${Math.max(...totals)}`}
            >
              {/* Gridlines and value axis */}
              {ticks.map((t) => (
                <g key={t}>
                  <line
                    x1={M.left}
                    y1={y(t)}
                    x2={w - M.right}
                    y2={y(t)}
                    stroke="var(--color-line)"
                    strokeWidth={1}
                  />
                  <text
                    x={M.left - 8}
                    y={y(t) + 4}
                    textAnchor="end"
                    fontSize="11"
                    fill="var(--color-ink-soft)"
                  >
                    {Number.isInteger(t) ? t : t.toFixed(1)}
                  </text>
                </g>
              ))}

              {days.map((day, i) => {
                const x = M.left + i * slot + (slot - bar) / 2;
                let cursor = y(0);
                const active = hover === null || hover === i;

                return (
                  <g key={day}>
                    {hover === i ? (
                      <rect
                        x={M.left + i * slot}
                        y={M.top}
                        width={slot}
                        height={plotH}
                        fill="var(--color-line)"
                        opacity={0.35}
                      />
                    ) : null}

                    {series.map((s) => {
                      const v = s.values[i] ?? 0;
                      if (v <= 0) return null;
                      const h = Math.max((v / max) * plotH - 2, 2);
                      const top = cursor - h;
                      cursor = top - 2;
                      return (
                        <rect
                          key={s.name}
                          x={x}
                          y={top}
                          width={bar}
                          height={h}
                          rx={Math.min(3, bar / 2)}
                          fill={s.color}
                          opacity={active ? 1 : 0.4}
                        />
                      );
                    })}

                    {i % labelEvery === 0 ? (
                      <text
                        x={M.left + i * slot + slot / 2}
                        y={H - 10}
                        textAnchor="middle"
                        fontSize="11"
                        fill="var(--color-ink-soft)"
                      >
                        {fmtDay(day)}
                      </text>
                    ) : null}

                    <rect
                      x={M.left + i * slot}
                      y={M.top}
                      width={slot}
                      height={plotH}
                      fill="transparent"
                      onMouseEnter={() => setHover(i)}
                    />
                  </g>
                );
              })}

              <line
                x1={M.left}
                y1={y(0)}
                x2={w - M.right}
                y2={y(0)}
                stroke="var(--color-ink-soft)"
                strokeWidth={1}
              />
            </svg>
          </>
        ) : null}
      </div>

      {hasData ? (
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
                      <td className="py-1">{fmtDay(d)}</td>
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
      ) : null}
    </figure>
  );
}
