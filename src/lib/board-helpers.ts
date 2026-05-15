import type { BoardCell, BoardToken } from "@/components/ui/board";

export function makeDiagonal(
  tokenA: BoardToken = "pink",
  tokenB: BoardToken = "blue",
): BoardCell[] {
  const cells: BoardCell[] = Array.from({ length: 36 }, () => null);
  [0, 7, 14, 21, 28].forEach((i) => (cells[i] = { token: tokenA }));
  [5, 10, 15].forEach((i) => (cells[i] = { token: tokenB }));
  cells[31] = { token: "butter" };
  cells[3] = { token: "butter" };
  return cells;
}

export function makeScattered(): BoardCell[] {
  const cells: BoardCell[] = Array.from({ length: 36 }, () => null);
  const picks: [number, BoardToken][] = [
    [2, "blue"],
    [8, "pink"],
    [14, "blue"],
    [20, "blue"],
    [26, "blue"],
    [11, "pink"],
    [17, "pink"],
    [23, "pink"],
    [4, "butter"],
    [33, "butter"],
    [29, "ink"],
    [30, "ink"],
  ];
  picks.forEach(([i, t]) => (cells[i] = { token: t }));
  return cells;
}
