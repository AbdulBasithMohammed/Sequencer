"use client";

import { useOptimistic, useTransition } from "react";
import {
  DndContext,
  type DragEndEvent,
  PointerSensor,
  TouchSensor,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import { SoftButton } from "@/components/ui/button";
import { SoftPill } from "@/components/ui/pill";
import { LeaveButton } from "./leave-button";
import { ShareButton } from "./share-button";
import {
  addBotAction,
  banPlayerAction,
  kickPlayerAction,
  removeBotAction,
  setBotDifficultyAction,
  setReadyAction,
  setTargetSequencesAction,
  setTeamAction,
  setTeamLayoutAction,
  setTurnSecondsAction,
  startGameAction,
  swapTeamsAction,
  transferHostAction,
  unbanPlayerAction,
} from "./actions";

// ─── Types ──────────────────────────────────────────────────────────────────

export type TokenColor = "pink" | "blue" | "butter" | "mint" | "ink";

export type Player = {
  seat_index: number;
  user_id: string;
  team: number | null;
  ready: boolean;
  joined_at: string;
  token_color: TokenColor;
  display_name: string | null;
  is_bot: boolean;
  bot_difficulty: string | null;
};

export type Ban = {
  user_id: string;
  display_name: string | null;
};

export type Room = {
  id: string;
  code: string;
  host_id: string;
  target_players: number;
  team_layout: string;
  status: string;
  turn_seconds: number;
  target_sequences: number | null;
};

// ─── Constants ──────────────────────────────────────────────────────────────

const TEAM_COLOR: Record<number, string> = {
  1: "var(--color-pink)",
  2: "var(--color-blue)",
  3: "var(--color-mint)",
};

const LAYOUT_OPTIONS: Record<number, string[]> = {
  6: ["3v3", "2v2v2"],
  12: ["6v6", "4v4v4"],
};

const TURN_SECONDS_PRESETS = [30, 45, 60, 90, 120];

const BOT_DIFFICULTIES: { value: string; label: string }[] = [
  { value: "rookie", label: "Rookie" },
  { value: "medium", label: "Medium" },
  { value: "ace", label: "Ace" },
];

function teamsForLayout(layout: string): number[] {
  switch (layout) {
    case "1v1v1":
    case "2v2v2":
    case "4v4v4":
      return [1, 2, 3];
    default:
      return [1, 2];
  }
}

// ─── Optimistic reducer ────────────────────────────────────────────────────

type OptimisticAction =
  | { type: "set_team"; userId: string; team: number }
  | { type: "swap_teams"; userA: string; userB: string }
  | { type: "set_ready"; userId: string; ready: boolean }
  | { type: "set_token_color"; userId: string; color: TokenColor }
  | { type: "set_bot_difficulty"; userId: string; difficulty: string }
  | { type: "remove"; userId: string };

function playersReducer(state: Player[], action: OptimisticAction): Player[] {
  switch (action.type) {
    case "set_team":
      return state.map((p) =>
        p.user_id === action.userId ? { ...p, team: action.team } : p,
      );
    case "swap_teams": {
      const a = state.find((p) => p.user_id === action.userA);
      const b = state.find((p) => p.user_id === action.userB);
      if (!a || !b) return state;
      return state.map((p) => {
        if (p.user_id === action.userA) return { ...p, team: b.team };
        if (p.user_id === action.userB) return { ...p, team: a.team };
        return p;
      });
    }
    case "set_ready":
      return state.map((p) =>
        p.user_id === action.userId ? { ...p, ready: action.ready } : p,
      );
    case "set_token_color":
      return state.map((p) =>
        p.user_id === action.userId
          ? { ...p, token_color: action.color }
          : p,
      );
    case "set_bot_difficulty":
      return state.map((p) =>
        p.user_id === action.userId
          ? { ...p, bot_difficulty: action.difficulty }
          : p,
      );
    case "remove":
      return state.filter((p) => p.user_id !== action.userId);
  }
}

// ─── Main component ────────────────────────────────────────────────────────

export function LobbyClient({
  room,
  players,
  bans,
  currentUserId,
}: {
  room: Room;
  players: Player[];
  bans: Ban[];
  currentUserId: string;
}) {
  const [optimisticPlayers, addOptimistic] = useOptimistic(
    players,
    playersReducer,
  );
  const [optimisticRoom, addRoomOptimistic] = useOptimistic(
    room,
    (state: Room, patch: Partial<Room>): Room => ({ ...state, ...patch }),
  );
  const [, startTransition] = useTransition();

  const meIsHost = optimisticRoom.host_id === currentUserId;
  const layoutTeams = teamsForLayout(optimisticRoom.team_layout);
  const teamCapacity = Math.floor(
    optimisticRoom.target_players / layoutTeams.length,
  );
  const validLayouts = LAYOUT_OPTIONS[optimisticRoom.target_players] ?? null;

  // Sensors: small distance threshold on pointer (so clicking buttons doesn't
  // start a drag), longer delay on touch.
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor, {
      activationConstraint: { delay: 200, tolerance: 5 },
    }),
  );

  // ─── Action wiring ────────────────────────────────────────────────────

  function fd(fields: Record<string, string>): FormData {
    const f = new FormData();
    for (const [k, v] of Object.entries(fields)) f.set(k, v);
    return f;
  }

  const handleSetTeam = (userId: string, team: number) => {
    if (team < 1 || team > 3) return;
    startTransition(async () => {
      addOptimistic({ type: "set_team", userId, team });
      await setTeamAction(fd({ roomId: room.id, userId, team: String(team) }));
    });
  };

  const handleSetReady = (ready: boolean) => {
    startTransition(async () => {
      addOptimistic({ type: "set_ready", userId: currentUserId, ready });
      await setReadyAction(fd({ roomId: room.id, ready: String(ready) }));
    });
  };

  const handleKick = (userId: string) => {
    startTransition(async () => {
      addOptimistic({ type: "remove", userId });
      await kickPlayerAction(fd({ roomId: room.id, userId }));
    });
  };

  const handleAddBot = () => {
    startTransition(async () => {
      await addBotAction(fd({ roomId: room.id, difficulty: "medium" }));
    });
  };

  const handleRemoveBot = (seat: number, userId: string) => {
    startTransition(async () => {
      addOptimistic({ type: "remove", userId });
      await removeBotAction(fd({ roomId: room.id, seat: String(seat) }));
    });
  };

  const handleSetBotDifficulty = (
    seat: number,
    userId: string,
    difficulty: string,
  ) => {
    startTransition(async () => {
      addOptimistic({ type: "set_bot_difficulty", userId, difficulty });
      await setBotDifficultyAction(
        fd({ roomId: room.id, seat: String(seat), difficulty }),
      );
    });
  };

  const handleBan = (userId: string) => {
    startTransition(async () => {
      addOptimistic({ type: "remove", userId });
      await banPlayerAction(fd({ roomId: room.id, userId }));
    });
  };

  const handleTransferHost = (userId: string) => {
    startTransition(async () => {
      await transferHostAction(fd({ roomId: room.id, userId }));
    });
  };

  const handleSetLayout = (layout: string) => {
    startTransition(async () => {
      addRoomOptimistic({ team_layout: layout });
      await setTeamLayoutAction(fd({ roomId: room.id, layout }));
    });
  };

  const handleUnban = (userId: string) => {
    startTransition(async () => {
      await unbanPlayerAction(fd({ roomId: room.id, userId }));
    });
  };

  const handleSetTurnSeconds = (seconds: number) => {
    startTransition(async () => {
      addRoomOptimistic({ turn_seconds: seconds });
      await setTurnSecondsAction(
        fd({ roomId: room.id, seconds: String(seconds) }),
      );
    });
  };

  const handleSetTargetSequences = (n: number | null) => {
    startTransition(async () => {
      addRoomOptimistic({ target_sequences: n });
      await setTargetSequencesAction(
        fd({ roomId: room.id, n: n === null ? "" : String(n) }),
      );
    });
  };

  const handleSwapTeams = (userA: string, userB: string) => {
    if (userA === userB) return;
    startTransition(async () => {
      addOptimistic({ type: "swap_teams", userA, userB });
      await swapTeamsAction(fd({ roomId: room.id, userA, userB }));
    });
  };

  const handleDragEnd = (event: DragEndEvent) => {
    if (!event.over) return;
    const userId = String(event.active.id);
    const overId = String(event.over.id);
    const player = optimisticPlayers.find((p) => p.user_id === userId);
    if (!player) return;

    // Dropped on another player chip → swap their teams (if different).
    if (overId.startsWith("player-")) {
      const targetUserId = overId.slice(7);
      if (targetUserId === userId) return;
      const target = optimisticPlayers.find((p) => p.user_id === targetUserId);
      if (!target) return;
      if (player.team === target.team) return;
      handleSwapTeams(userId, targetUserId);
      return;
    }

    // Dropped on an empty team zone → move (capacity-checked).
    if (overId.startsWith("team-")) {
      const targetTeam = Number(overId.slice(5));
      if (player.team === targetTeam) return;
      const occupants = optimisticPlayers.filter(
        (p) => p.team === targetTeam && p.user_id !== userId,
      ).length;
      if (occupants >= teamCapacity) return;
      handleSetTeam(userId, targetTeam);
    }
  };

  // ─── Derived state ────────────────────────────────────────────────────

  const me = optimisticPlayers.find((p) => p.user_id === currentUserId);
  const nonHostPlayers = optimisticPlayers.filter(
    (p) => p.user_id !== room.host_id,
  );
  const nonHostReadyCount = nonHostPlayers.filter((p) => p.ready).length;
  const everyTeamHasAPlayer = layoutTeams.every((t) =>
    optimisticPlayers.some((p) => p.team === t),
  );
  const noTeamOverCapacity = layoutTeams.every(
    (t) =>
      optimisticPlayers.filter((p) => p.team === t).length <= teamCapacity,
  );
  const canStart =
    optimisticPlayers.length >= 2 &&
    nonHostReadyCount === nonHostPlayers.length &&
    everyTeamHasAPlayer &&
    noTeamOverCapacity;
  const roomIsFull = optimisticPlayers.length >= optimisticRoom.target_players;

  return (
    <>
      {/* Room code hero */}
      <div className="flex flex-col items-center text-center">
        <SoftPill>
          <span
            aria-hidden
            className="inline-block h-2 w-2 rounded-full bg-mint"
            style={{ boxShadow: "0 0 0 4px rgba(123,216,181,0.2)" }}
          />
          <span>
            {optimisticPlayers.length} / {optimisticRoom.target_players}{" "}
            players · {optimisticRoom.team_layout}
          </span>
        </SoftPill>

        <div className="mt-5 text-[12px] font-semibold uppercase tracking-[0.2em] text-ink-soft">
          Room code
        </div>
        <div
          className="mt-1 font-mono font-bold leading-none text-ink"
          style={{
            fontSize: "clamp(56px, 8vw, 80px)",
            letterSpacing: "0.08em",
          }}
        >
          {room.code}
        </div>
        <div className="mt-4 flex justify-center">
          <ShareButton code={room.code} />
        </div>

        <RoomSettings
          room={optimisticRoom}
          layoutTeams={layoutTeams}
          validLayouts={validLayouts}
          meIsHost={meIsHost}
          onSetLayout={handleSetLayout}
          onSetTurnSeconds={handleSetTurnSeconds}
          onSetTargetSequences={handleSetTargetSequences}
        />

        {meIsHost && (
          <p className="mt-3 text-[11px] text-ink-soft">
            Drag a player between teams to reassign, or onto a teammate to swap.
          </p>
        )}
      </div>

      {/* Team zones — explicit `id` on DndContext makes the library's internal
          IDs deterministic across SSR + hydration (otherwise Safari flags it). */}
      <DndContext
        id="lobby-dnd"
        sensors={sensors}
        onDragEnd={handleDragEnd}
      >
        <div
          className={`mt-8 grid gap-3 grid-cols-1 ${
            layoutTeams.length === 3 ? "sm:grid-cols-3" : "sm:grid-cols-2"
          }`}
        >
          {layoutTeams.map((team) => (
            <TeamZone
              key={team}
              team={team}
              players={optimisticPlayers
                .filter((p) => p.team === team)
                .sort((a, b) => a.seat_index - b.seat_index)}
              capacity={teamCapacity}
              currentUserId={currentUserId}
              hostId={room.host_id}
              meIsHost={meIsHost}
              onKick={handleKick}
              onBan={handleBan}
              onTransferHost={handleTransferHost}
              onRemoveBot={handleRemoveBot}
              onSetBotDifficulty={handleSetBotDifficulty}
            />
          ))}
        </div>
      </DndContext>

      {/* Banned list — host only */}
      {meIsHost && bans.length > 0 && (
        <div className="mt-8 rounded-2xl border border-line bg-surface p-5">
          <h3 className="font-display text-[15px] font-bold tracking-tight">
            Banned ({bans.length})
          </h3>
          <p className="mt-1 text-[12px] text-ink-soft">
            These players can&apos;t rejoin until you unban them.
          </p>
          <ul className="mt-3 flex flex-col gap-2">
            {bans.map((b) => (
              <li
                key={b.user_id}
                className="flex items-center justify-between rounded-xl border border-line bg-canvas px-3 py-2"
              >
                <span className="text-[13px] font-semibold text-ink">
                  {b.display_name ?? "(unknown)"}
                </span>
                <button
                  type="button"
                  onClick={() => handleUnban(b.user_id)}
                  className="rounded-full border border-line bg-canvas px-3 py-1 text-[11px] font-semibold text-ink hover:bg-line"
                >
                  Unban
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Bottom bar */}
      <div className="mt-8 flex flex-wrap items-center justify-between gap-3">
        <LeaveButton roomId={room.id} />

        {meIsHost ? (
          // Status text first: its width changes with every roster/ready
          // update, and leading the right-aligned group lets it grow into
          // the empty middle — the two buttons stay pinned in place. The
          // Start button keeps one fixed label for the same reason.
          <div className="flex items-center gap-3">
            <span className="text-[13px] whitespace-nowrap text-ink-soft">
              {nonHostPlayers.length === 0
                ? "Waiting for players…"
                : canStart
                  ? "Everyone’s ready"
                  : `${nonHostReadyCount} of ${nonHostPlayers.length} ready`}
            </span>
            <SoftButton
              type="button"
              variant="outline"
              onClick={handleAddBot}
              disabled={roomIsFull}
            >
              <span aria-hidden>+</span> Add bot
            </SoftButton>
            <form action={startGameAction}>
              <input type="hidden" name="code" value={room.code} />
              <SoftButton type="submit" variant="primary" disabled={!canStart}>
                Start game
              </SoftButton>
            </form>
          </div>
        ) : me ? (
          <SoftButton
            type="button"
            variant={me.ready ? "primary" : "outline"}
            onClick={() => handleSetReady(!me.ready)}
            className="min-w-[160px] justify-center"
            trailing={me.ready ? <span aria-hidden>✓</span> : null}
          >
            {me.ready ? "Ready" : "Mark ready"}
          </SoftButton>
        ) : null}
      </div>
    </>
  );
}

// ─── RoomSettings ──────────────────────────────────────────────────────────
//
// One row of pill-pickers for the host (layout, turn timer, win target).
// Non-hosts see the same row as read-only chips.

function RoomSettings({
  room,
  layoutTeams,
  validLayouts,
  meIsHost,
  onSetLayout,
  onSetTurnSeconds,
  onSetTargetSequences,
}: {
  room: Room;
  layoutTeams: number[];
  validLayouts: string[] | null;
  meIsHost: boolean;
  onSetLayout: (layout: string) => void;
  onSetTurnSeconds: (seconds: number) => void;
  onSetTargetSequences: (n: number | null) => void;
}) {
  // 3 teams always need exactly 1 sequence; hide the picker entirely.
  const showSeqPicker = layoutTeams.length === 2;
  const defaultSeq = layoutTeams.length === 3 ? 1 : 2;
  const effectiveSeq = room.target_sequences ?? defaultSeq;

  return (
    <div className="mt-5 flex flex-wrap items-center justify-center gap-x-5 gap-y-3">
      {validLayouts && (
        <SettingPicker
          label="Layout"
          options={validLayouts.map((opt) => ({ label: opt, value: opt }))}
          value={room.team_layout}
          onChange={(v) => onSetLayout(String(v))}
          disabled={!meIsHost}
        />
      )}
      <SettingPicker
        label="Turn timer"
        options={TURN_SECONDS_PRESETS.map((s) => ({
          label: `${s}s`,
          value: s,
        }))}
        value={room.turn_seconds}
        onChange={(v) => onSetTurnSeconds(Number(v))}
        disabled={!meIsHost}
      />
      {showSeqPicker && (
        <SettingPicker
          label="Win at"
          options={[
            { label: "1 seq", value: 1 },
            { label: "2 seqs", value: 2 },
          ]}
          value={effectiveSeq}
          onChange={(v) => onSetTargetSequences(Number(v))}
          disabled={!meIsHost}
        />
      )}
    </div>
  );
}

function SettingPicker<T extends string | number>({
  label,
  options,
  value,
  onChange,
  disabled,
}: {
  label: string;
  options: { label: string; value: T }[];
  value: T;
  onChange: (v: T) => void;
  disabled: boolean;
}) {
  return (
    <div className="inline-flex items-center gap-2">
      <span className="text-[11px] font-semibold uppercase tracking-[0.14em] text-ink-soft">
        {label}
      </span>
      <div className="inline-flex items-center gap-0.5 rounded-xl border border-line bg-surface p-0.5">
        {options.map((opt) => {
          const active = value === opt.value;
          if (disabled) {
            if (!active) return null;
            return (
              <span
                key={String(opt.value)}
                className="rounded-[10px] bg-ink px-2.5 py-1 text-[12px] font-semibold text-canvas"
              >
                {opt.label}
              </span>
            );
          }
          return (
            <button
              key={String(opt.value)}
              type="button"
              onClick={() => onChange(opt.value)}
              className={`rounded-[10px] px-2.5 py-1 text-[12px] font-semibold transition-colors ${
                active ? "bg-ink text-canvas" : "text-ink-soft hover:text-ink"
              }`}
            >
              {opt.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ─── TeamZone ──────────────────────────────────────────────────────────────

function TeamZone({
  team,
  players,
  capacity,
  currentUserId,
  hostId,
  meIsHost,
  onKick,
  onBan,
  onTransferHost,
  onRemoveBot,
  onSetBotDifficulty,
}: {
  team: number;
  players: Player[];
  capacity: number;
  currentUserId: string;
  hostId: string;
  meIsHost: boolean;
  onKick: (userId: string) => void;
  onBan: (userId: string) => void;
  onTransferHost: (userId: string) => void;
  onRemoveBot: (seat: number, userId: string) => void;
  onSetBotDifficulty: (seat: number, userId: string, difficulty: string) => void;
}) {
  const { setNodeRef, isOver } = useDroppable({ id: `team-${team}` });

  return (
    <div
      ref={setNodeRef}
      className={`flex flex-col gap-2 rounded-2xl border-[1.5px] bg-canvas/40 p-3 transition-colors ${
        isOver ? "border-ink bg-canvas" : "border-line"
      }`}
    >
      <div className="mb-1 flex items-center gap-2 px-1">
        <div
          className="h-3 w-3 rounded-full"
          style={{ background: TEAM_COLOR[team] }}
        />
        <h3 className="font-display text-[13px] font-bold uppercase tracking-wider">
          Team {team}
        </h3>
        <span className="ml-auto text-[11px] font-semibold text-ink-soft">
          {players.length} / {capacity}
        </span>
      </div>

      {players.map((p) => (
        <DraggablePlayerCard
          key={p.user_id}
          player={p}
          isHost={p.user_id === hostId}
          isYou={p.user_id === currentUserId}
          meIsHost={meIsHost}
          onKick={onKick}
          onBan={onBan}
          onTransferHost={onTransferHost}
          onRemoveBot={onRemoveBot}
          onSetBotDifficulty={onSetBotDifficulty}
        />
      ))}

      {Array.from(
        { length: Math.max(0, capacity - players.length) },
        (_, i) => (
          <EmptySlot key={`empty-${i}`} team={team} />
        ),
      )}
    </div>
  );
}

// ─── DraggablePlayerCard ───────────────────────────────────────────────────

function DraggablePlayerCard({
  player,
  isHost,
  isYou,
  meIsHost,
  onKick,
  onBan,
  onTransferHost,
  onRemoveBot,
  onSetBotDifficulty,
}: {
  player: Player;
  isHost: boolean;
  isYou: boolean;
  meIsHost: boolean;
  onKick: (userId: string) => void;
  onBan: (userId: string) => void;
  onTransferHost: (userId: string) => void;
  onRemoveBot: (seat: number, userId: string) => void;
  onSetBotDifficulty: (seat: number, userId: string, difficulty: string) => void;
}) {
  const {
    attributes,
    listeners,
    setNodeRef: setDragRef,
    transform,
    isDragging,
  } = useDraggable({
    id: player.user_id,
    disabled: !meIsHost,
  });
  const { setNodeRef: setDropRef, isOver: isSwapOver } = useDroppable({
    id: `player-${player.user_id}`,
    disabled: !meIsHost,
  });

  const setNodeRef = (el: HTMLElement | null) => {
    setDragRef(el);
    setDropRef(el);
  };

  const dragStyle = transform
    ? {
        transform: `translate3d(${transform.x}px, ${transform.y}px, 0)`,
      }
    : undefined;

  const name = player.display_name ?? "Player";
  const initial = name[0]?.toUpperCase() ?? "?";
  const avatarColor = player.team
    ? TEAM_COLOR[player.team]
    : "var(--color-ink-soft)";

  // Spread drag props only when host so non-hosts get normal pointer events
  // on their inline buttons (color picker etc.).
  const dragProps = meIsHost ? { ...listeners, ...attributes } : {};

  return (
    <div
      ref={setNodeRef}
      style={{
        ...dragStyle,
        zIndex: isDragging ? 50 : undefined,
      }}
      className={`rounded-xl border bg-surface p-3 transition-colors ${
        isSwapOver && !isDragging
          ? "border-ink ring-2 ring-ink/20"
          : "border-line"
      } ${isDragging ? "opacity-50 shadow-lg" : ""} ${
        meIsHost ? "cursor-grab active:cursor-grabbing" : ""
      }`}
      {...dragProps}
    >
      <div className="flex items-center gap-2.5">
        <div
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg font-display text-[14px] font-bold text-canvas"
          style={{ background: avatarColor }}
        >
          {initial}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex min-w-0 items-center gap-1.5">
            <span
              className="truncate text-[14px] font-bold"
              title={name}
            >
              {name}
            </span>
            {isHost && (
              <span className="shrink-0 rounded-full bg-butter px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-ink">
                Host
              </span>
            )}
            {player.is_bot && (
              <span className="shrink-0 rounded-full bg-ink-soft px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-canvas">
                Bot
              </span>
            )}
            {isYou && (
              <span className="shrink-0 rounded-full bg-ink px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-canvas">
                You
              </span>
            )}
            {player.ready && !isHost && (
              <span className="shrink-0 rounded-full bg-mint px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-ink">
                Ready
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Action row — always rendered with a fixed min-height so every card
          is the same height regardless of who's viewing it. */}
      <div
        className="mt-2 flex min-h-[26px] flex-wrap gap-1.5 pl-11"
        onPointerDown={(e) => e.stopPropagation()}
      >
        {meIsHost && !isYou && player.is_bot && (
          <>
            <div className="inline-flex items-center gap-0.5 rounded-full border border-line bg-canvas p-0.5">
              {BOT_DIFFICULTIES.map((d) => {
                const active =
                  (player.bot_difficulty ?? "medium") === d.value;
                return (
                  <button
                    key={d.value}
                    type="button"
                    onClick={() =>
                      onSetBotDifficulty(
                        player.seat_index,
                        player.user_id,
                        d.value,
                      )
                    }
                    className={`rounded-full px-2 py-0.5 text-[10px] font-semibold transition-colors ${
                      active
                        ? "bg-ink text-canvas"
                        : "text-ink-soft hover:text-ink"
                    }`}
                  >
                    {d.label}
                  </button>
                );
              })}
            </div>
            <button
              type="button"
              onClick={() => onRemoveBot(player.seat_index, player.user_id)}
              className="rounded-full border border-pink/40 bg-canvas px-2.5 py-1 text-[10px] font-semibold text-pink hover:bg-pink/10"
            >
              Remove
            </button>
          </>
        )}
        {meIsHost && !isYou && !player.is_bot && (
          <>
            <button
              type="button"
              onClick={() => onTransferHost(player.user_id)}
              className="rounded-full border border-line bg-canvas px-2.5 py-1 text-[10px] font-semibold text-ink hover:bg-line"
            >
              Make host
            </button>
            <button
              type="button"
              onClick={() => onKick(player.user_id)}
              className="rounded-full border border-pink/40 bg-canvas px-2.5 py-1 text-[10px] font-semibold text-pink hover:bg-pink/10"
            >
              Kick
            </button>
            <button
              type="button"
              onClick={() => onBan(player.user_id)}
              className="rounded-full bg-pink px-2.5 py-1 text-[10px] font-semibold text-canvas hover:bg-pink/90"
            >
              Ban
            </button>
          </>
        )}
      </div>
    </div>
  );
}

// ─── EmptySlot ─────────────────────────────────────────────────────────────

function EmptySlot({ team }: { team: number }) {
  return (
    <div className="rounded-xl border border-dashed border-line bg-surface p-3">
      <div className="flex items-center gap-2.5">
        <div
          className="h-9 w-9 shrink-0 rounded-lg opacity-30"
          style={{ background: TEAM_COLOR[team] }}
        />
        <div className="min-w-0 flex-1">
          <span className="text-[14px] font-bold text-ink-soft">
            Waiting for player…
          </span>
        </div>
      </div>
      {/* Spacer matches DraggablePlayerCard's action row so heights line up. */}
      <div className="mt-2 min-h-[26px]" aria-hidden />
    </div>
  );
}
