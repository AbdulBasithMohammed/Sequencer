// Server-rendered SVG charts. No charting library and no client JS — these
// are static columns, and shipping a runtime for them would cost more than
// the whole admin page.
//
// Palette: brand blue #5b7cfa (slot 1) and pink #ff5c8a (slot 2), validated
// against the cream chart surface #fffbf3 — CVD separation ΔE 18.0 (protan),
// normal-vision ΔE 30.3, both well clear of the floors. Pink measures 2.85:1
// against that surface, under the 3:1 bar, so every non-zero column carries a
// visible value label; identity is never left to colour alone.

const SERIES_1 = "#5b7cfa"; // registered / primary
const SERIES_2 = "#ff5c8a"; // guests

type Segment = { value: number; color: string; name: string };
export type ColumnDatum = { day: string; segments: Segment[] };

function label(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

export function ColumnChart({
  data,
  empty,
  legend,
}: {
  data: ColumnDatum[];
  empty: string;
  legend?: { name: string; color: string }[];
}) {
  const totals = data.map((d) =>
    d.segments.reduce((sum, s) => sum + s.value, 0),
  );
  const peak = Math.max(...totals, 1);

  if (!totals.some((t) => t > 0)) {
    return <p className="py-6 text-sm text-ink-soft">{empty}</p>;
  }

  const SLOT = 26;
  const BAR = 16;
  const PLOT = 96;
  const TOP = 20; // room for value labels
  const BASE = TOP + PLOT;
  const H = BASE + 20; // room for date labels
  const W = data.length * SLOT;

  return (
    <figure className="m-0">
      {legend && legend.length > 1 ? (
        <div className="mb-2 flex flex-wrap gap-x-4 gap-y-1">
          {legend.map((l) => (
            <span key={l.name} className="flex items-center gap-1.5 text-xs text-ink-soft">
              <span
                className="inline-block h-2.5 w-2.5 rounded-[3px]"
                style={{ background: l.color }}
              />
              {l.name}
            </span>
          ))}
        </div>
      ) : null}

      <svg
        viewBox={`0 0 ${W} ${H}`}
        width="100%"
        height={H}
        preserveAspectRatio="xMidYMax meet"
        role="img"
        aria-label={`${data.length}-day trend, peak ${peak}`}
      >
        {/* Baseline — recessive, just enough to anchor the columns. */}
        <line
          x1="0"
          y1={BASE + 0.5}
          x2={W}
          y2={BASE + 0.5}
          stroke="var(--color-line)"
          strokeWidth="1"
        />

        {data.map((d, i) => {
          const total = totals[i];
          const x = i * SLOT + (SLOT - BAR) / 2;
          let cursor = BASE;

          return (
            <g key={d.day}>
              <title>
                {label(d.day)}:{" "}
                {d.segments.map((s) => `${s.value} ${s.name}`).join(", ")}
              </title>

              {d.segments.map((s) => {
                if (s.value <= 0) return null;
                // 2px surface gap between stacked segments so they read as
                // separate marks rather than one striped block.
                const h = Math.max((s.value / peak) * PLOT - 2, 2);
                const y = cursor - h;
                cursor = y - 2;
                return (
                  <rect
                    key={s.name}
                    x={x}
                    y={y}
                    width={BAR}
                    height={h}
                    rx="3"
                    fill={s.color}
                  />
                );
              })}

              {/* Relief for the sub-3:1 contrast warning: the number is
                  always legible even when the fill is not. */}
              {total > 0 ? (
                <text
                  x={x + BAR / 2}
                  y={cursor - 4}
                  textAnchor="middle"
                  fontSize="10"
                  fontWeight="600"
                  fill="var(--color-ink)"
                >
                  {total}
                </text>
              ) : null}

              {/* Every third day, so labels never collide. */}
              {i % 3 === 0 ? (
                <text
                  x={x + BAR / 2}
                  y={H - 6}
                  textAnchor="middle"
                  fontSize="9"
                  fill="var(--color-ink-soft)"
                >
                  {label(d.day)}
                </text>
              ) : null}
            </g>
          );
        })}
      </svg>
    </figure>
  );
}

export { SERIES_1, SERIES_2 };
