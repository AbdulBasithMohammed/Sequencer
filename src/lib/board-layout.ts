// Canonical Jax/Goliath Sequence board, 10×10. Layout transcribed from a
// physical board. Corners are wild — any team's chip counts as part of a
// 5-in-a-row from any direction. Every non-jack card appears exactly twice;
// jacks are NEVER on the board (two-eyed jacks place anywhere, one-eyed
// jacks remove an opponent's chip).
//
// Card notation matches start_game's deck: rank (A,2-9,T,J,Q,K) + suit
// (D,C,H,S). T is "ten" — every card encodes as exactly 2 characters so
// the renderer can switch on shape uniformly.

export type BoardCard = string | null; // null = corner wild

export const BOARD_LAYOUT: BoardCard[][] = [
  [null, "2S", "3S", "4S", "5S", "6S", "7S", "8S", "9S", null],
  ["6C", "5C", "4C", "3C", "2C", "AH", "KH", "QH", "TH", "TS"],
  ["7C", "AS", "2D", "3D", "4D", "5D", "6D", "7D", "9H", "QS"],
  ["8C", "KS", "6C", "5C", "4C", "3C", "2C", "8D", "8H", "KS"],
  ["9C", "QS", "7C", "6H", "5H", "4H", "AH", "9D", "7H", "AS"],
  ["TC", "TS", "8C", "7H", "2H", "3H", "KH", "TD", "6H", "2D"],
  ["QC", "9S", "9C", "8H", "9H", "TH", "QH", "QD", "5H", "3D"],
  ["KC", "8S", "TC", "QC", "KC", "AC", "AD", "KD", "4H", "4D"],
  ["AC", "7S", "6S", "5S", "4S", "3S", "2S", "2H", "3H", "5D"],
  [null, "AD", "KD", "QD", "TD", "9D", "8D", "7D", "6D", null],
];

export function isCornerWild(row: number, col: number): boolean {
  return (row === 0 || row === 9) && (col === 0 || col === 9);
}

export type Suit = "D" | "C" | "H" | "S";
export type CardParts = {
  rank: string; // "A", "2".."9", "10", "J", "Q", "K"
  suit: Suit;
  symbol: "♦" | "♣" | "♥" | "♠";
  color: "red" | "black";
};

const SUIT_INFO: Record<Suit, { symbol: CardParts["symbol"]; color: CardParts["color"] }> = {
  D: { symbol: "♦", color: "red" },
  H: { symbol: "♥", color: "red" },
  C: { symbol: "♣", color: "black" },
  S: { symbol: "♠", color: "black" },
};

export function parseCard(card: string): CardParts {
  const rankChar = card[0];
  const suitChar = card[1] as Suit;
  const rank = rankChar === "T" ? "10" : rankChar;
  const info = SUIT_INFO[suitChar];
  return { rank, suit: suitChar, symbol: info.symbol, color: info.color };
}

// Unicode playing-card codepoints. Each suit has a block of 14 codepoints
// starting from the Ace. The rank order in Unicode is A, 2-10, J, Knight
// (we skip), Q, K — so Q is at +12 and K is at +13 (not +11/+12).
//
// On Apple devices these render as full-color playing-card emoji. On
// Windows / Linux they fall back to monochrome line drawings. Either way
// you get an actual card with pips / face illustrations, not just text.

const SUIT_BASE: Record<Suit, number> = {
  S: 0x1f0a1, // 🂡 Ace of Spades
  H: 0x1f0b1, // 🂱 Ace of Hearts
  D: 0x1f0c1, // 🃁 Ace of Diamonds
  C: 0x1f0d1, // 🃑 Ace of Clubs
};

const RANK_OFFSET: Record<string, number> = {
  A: 0,
  "2": 1,
  "3": 2,
  "4": 3,
  "5": 4,
  "6": 5,
  "7": 6,
  "8": 7,
  "9": 8,
  T: 9,
  J: 10,
  Q: 12,
  K: 13,
};

export function cardGlyph(card: string): string {
  const offset = RANK_OFFSET[card[0]];
  const base = SUIT_BASE[card[1] as Suit];
  return String.fromCodePoint(base + offset);
}

export type CardKind = "normal" | "two_eyed_jack" | "one_eyed_jack";

// Two-eyed jacks (♦J, ♣J) = wild place. One-eyed jacks (♠J, ♥J) = remove
// opponent chip. Every other card is "normal" — must match the tile.
export function classifyCard(card: string): CardKind {
  if (card === "JD" || card === "JC") return "two_eyed_jack";
  if (card === "JS" || card === "JH") return "one_eyed_jack";
  return "normal";
}

// A "dead" card is a non-jack whose two board positions are both already
// covered. The player may discard it as a free action ("dead-card swap")
// and draw a replacement before playing.
export function isDeadCard(
  card: string,
  boardCells: { team: number | null }[][],
): boolean {
  if (classifyCard(card) !== "normal") return false;
  for (let r = 0; r < 10; r++) {
    for (let c = 0; c < 10; c++) {
      if (BOARD_LAYOUT[r][c] === card && boardCells[r]?.[c]?.team == null) {
        return false;
      }
    }
  }
  return true;
}
