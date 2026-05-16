"use client";

import { useEffect, useState, useTransition } from "react";
import {
  acceptFriendRequest,
  cancelFriendRequest,
  ignoreFriendRequest,
  searchUsers,
  sendFriendRequest,
  unfriend,
  unignoreUser,
  type SearchResult,
} from "./actions";

type FriendUser = { user_id: string; display_name: string; tag: string };
type RequestUser = FriendUser & { created_at: string };

export type FriendsData = {
  friends: FriendUser[];
  incoming: RequestUser[];
  sent: RequestUser[];
  ignored: FriendUser[];
};

export function FriendsClient({ data }: { data: FriendsData }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);

  // Debounced search.
  useEffect(() => {
    const trimmed = query.trim();
    if (!trimmed) {
      setResults([]);
      return;
    }
    setSearching(true);
    const handle = window.setTimeout(async () => {
      const data = await searchUsers(trimmed);
      setResults(data);
      setSearching(false);
    }, 250);
    return () => window.clearTimeout(handle);
  }, [query]);

  return (
    <div className="mx-auto flex w-full max-w-[760px] flex-col px-8 py-8">
      <div className="text-[13px] font-semibold text-ink-soft">Friends</div>
      <h1
        className="mt-1 font-display font-bold leading-none"
        style={{
          fontSize: "clamp(36px, 5vw, 48px)",
          letterSpacing: "-0.03em",
        }}
      >
        Your people.
      </h1>

      {/* Search */}
      <section className="mt-8">
        <label
          htmlFor="friend-search"
          className="text-[11px] font-semibold uppercase tracking-[0.18em] text-ink-soft"
        >
          Find someone
        </label>
        <input
          id="friend-search"
          type="text"
          autoComplete="off"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder='Try "alice" or "alice #ABC123"'
          className="mt-2 w-full rounded-2xl border border-line bg-canvas px-4 py-3 text-[15px] text-ink outline-none focus:border-ink"
        />
        {query.trim() && (
          <div className="mt-3 overflow-hidden rounded-2xl border border-line bg-surface">
            {searching && results.length === 0 ? (
              <EmptyRow text="Searching…" />
            ) : results.length === 0 ? (
              <EmptyRow text="No one matches that." />
            ) : (
              results.map((r) => <SearchRow key={r.user_id} row={r} />)
            )}
          </div>
        )}
      </section>

      <SectionList
        title="Your friends"
        empty="No friends yet — search above to add some."
        items={data.friends}
        renderActions={(u) => <UnfriendButton userId={u.user_id} />}
      />

      <SectionList
        title="Incoming requests"
        empty="No incoming requests."
        items={data.incoming}
        renderActions={(u) => (
          <>
            <AcceptButton userId={u.user_id} />
            <IgnoreButton userId={u.user_id} />
          </>
        )}
      />

      <SectionList
        title="Sent requests"
        empty="You haven't sent any requests."
        items={data.sent}
        renderActions={(u) => <CancelButton userId={u.user_id} />}
      />

      <SectionList
        title="Ignored"
        empty="Your ignore list is empty."
        items={data.ignored}
        renderActions={(u) => <UnignoreButton userId={u.user_id} />}
      />
    </div>
  );
}

// ─── Sections ──────────────────────────────────────────────────────────────

function SectionList<T extends FriendUser>({
  title,
  empty,
  items,
  renderActions,
}: {
  title: string;
  empty: string;
  items: T[];
  renderActions: (u: T) => React.ReactNode;
}) {
  return (
    <section className="mt-8">
      <h2 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-ink-soft">
        {title}
        <span className="ml-1.5 text-ink">{items.length}</span>
      </h2>
      <div className="mt-2 overflow-hidden rounded-2xl border border-line bg-surface">
        {items.length === 0 ? (
          <EmptyRow text={empty} />
        ) : (
          items.map((u) => (
            <UserRow
              key={u.user_id}
              display_name={u.display_name}
              tag={u.tag}
              actions={renderActions(u)}
            />
          ))
        )}
      </div>
    </section>
  );
}

function EmptyRow({ text }: { text: string }) {
  return (
    <div className="px-4 py-4 text-[13px] text-ink-soft">{text}</div>
  );
}

function UserRow({
  display_name,
  tag,
  actions,
}: {
  display_name: string;
  tag: string;
  actions: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-3 border-b border-line px-4 py-3 last:border-b-0">
      <div className="min-w-0 flex-1">
        <div className="truncate text-[14px] font-semibold text-ink">
          {display_name}{" "}
          <span className="font-mono font-normal text-ink-soft">#{tag}</span>
        </div>
      </div>
      <div className="flex items-center gap-2">{actions}</div>
    </div>
  );
}

// ─── Search-result row ─────────────────────────────────────────────────────

function SearchRow({ row }: { row: SearchResult }) {
  const actions =
    row.relationship === "friend" ? (
      <Pill>Friend</Pill>
    ) : row.relationship === "request_sent" ? (
      <Pill>Request sent</Pill>
    ) : row.relationship === "request_received" ? (
      <AcceptButton userId={row.user_id} />
    ) : row.relationship === "ignored" ? (
      <Pill>Ignored</Pill>
    ) : (
      <AddButton userId={row.user_id} />
    );

  return (
    <UserRow
      display_name={row.display_name}
      tag={row.tag}
      actions={actions}
    />
  );
}

function Pill({ children }: { children: React.ReactNode }) {
  return (
    <span className="rounded-full border border-line px-3 py-1 text-[11px] font-semibold text-ink-soft">
      {children}
    </span>
  );
}

// ─── Action buttons ────────────────────────────────────────────────────────

function ActionButton({
  label,
  onClick,
  variant = "outline",
}: {
  label: string;
  onClick: () => Promise<{ error: string | null }>;
  variant?: "primary" | "outline";
}) {
  const [pending, startTransition] = useTransition();
  const classes =
    variant === "primary"
      ? "bg-ink text-canvas hover:opacity-90"
      : "border border-line text-ink hover:bg-canvas";
  return (
    <button
      type="button"
      disabled={pending}
      onClick={() =>
        startTransition(async () => {
          await onClick();
        })
      }
      className={`rounded-full px-3 py-1.5 text-[12px] font-semibold transition-opacity disabled:opacity-50 ${classes}`}
    >
      {pending ? "…" : label}
    </button>
  );
}

function AddButton({ userId }: { userId: string }) {
  return (
    <ActionButton
      label="Add"
      variant="primary"
      onClick={() => sendFriendRequest(userId)}
    />
  );
}
function AcceptButton({ userId }: { userId: string }) {
  return (
    <ActionButton
      label="Accept"
      variant="primary"
      onClick={() => acceptFriendRequest(userId)}
    />
  );
}
function IgnoreButton({ userId }: { userId: string }) {
  return (
    <ActionButton label="Ignore" onClick={() => ignoreFriendRequest(userId)} />
  );
}
function CancelButton({ userId }: { userId: string }) {
  return (
    <ActionButton label="Cancel" onClick={() => cancelFriendRequest(userId)} />
  );
}
function UnfriendButton({ userId }: { userId: string }) {
  return <ActionButton label="Unfriend" onClick={() => unfriend(userId)} />;
}
function UnignoreButton({ userId }: { userId: string }) {
  return <ActionButton label="Unignore" onClick={() => unignoreUser(userId)} />;
}
