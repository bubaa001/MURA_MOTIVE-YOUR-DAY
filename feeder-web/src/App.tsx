import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { isLoggedIn, listItems, fetchNextPage, reviewItem, bulkReview, syncApproved, submitManually, updateCandidate, setContentStatus, logout, me, listContent, createContent, updateContent, deleteContent, bulkContent, deleteCandidate, listPushCampaigns, createPushCampaign, sendPushCampaign, testPushCampaign, deletePushCampaign } from "./api";
import type { CandidatePatch, PushCampaign, PushPayload } from "./api";
import Login from "./Login";
import type { ContentPayload, ContentStatus, Item, ItemType, LiveItem, ManualSubmission, ReviewStatus } from "./types";

type Tab = "pending" | "approved" | "rejected";

export default function App() {
  const [loggedIn, setLoggedIn] = useState(isLoggedIn);
  return loggedIn
    ? <Dashboard onLogout={() => { logout(); setLoggedIn(false); }} />
    : <Login onLoggedIn={() => setLoggedIn(true)} />;
}

type StudioPage = "feed" | "queue" | "review" | "content" | "push" | "settings";

const NAV_LABELS: Record<StudioPage, string> = {
  feed: "Feed",
  queue: "Queue",
  review: "Review",
  content: "Live Content",
  push: "Push",
  settings: "Settings"
};

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const [page, setPage] = useState<StudioPage>("feed");
  const [createType, setCreateType] = useState<ItemType | null>(null);
  const [error, setError] = useState("");
  const [syncMsg, setSyncMsg] = useState("");
  const [pendingCount, setPendingCount] = useState(0);
  const [isSuperuser, setIsSuperuser] = useState(false);

  useEffect(() => {
    me().then((profile) => setIsSuperuser(profile.is_superuser)).catch(() => {});
  }, []);

  const refreshPending = useCallback(async () => {
    try {
      const pending = await listItems("pending");
      setPendingCount(pending.count);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }, []);

  useEffect(() => {
    refreshPending();
  }, [refreshPending]);

  async function handleSync() {
    setSyncMsg("Syncing…");
    try {
      const res = await syncApproved();
      const results = res.results ?? [];
      const wentLive = results.filter((r) => r.created).length;
      const skipped = results.filter((r) => r.ok && !r.created).length;
      const failed = results.filter((r) => !r.ok);
      let summary = res.submitted + " submitted · " + wentLive + " went live";
      if (skipped > 0) summary += " · " + skipped + " duplicate(s) skipped";
      if (failed.length > 0) {
        const details = failed.map((r) => "item #" + r.item_id + ": " + (r.error || "failed")).join("; ");
        summary += " · " + failed.length + " failed — " + details;
      }
      setSyncMsg(summary);
      refreshPending();
    } catch (err) {
      setSyncMsg("Sync failed: " + (err instanceof Error ? err.message : String(err)));
    }
    setTimeout(() => setSyncMsg(""), 8000);
  }

  return (
    <div className="app">
      <header>
        <div className="brand-lockup">
          <span className="brand-mark">M</span>
          <div><h1>TheFeeder</h1><span className="brand-subtitle">MURA publishing studio</span></div>
        </div>
        <div className="spacer" />
        {syncMsg && <span className="sync-msg">{syncMsg}</span>}
        <nav className="studio-nav" aria-label="Studio sections">
          {(Object.keys(NAV_LABELS) as StudioPage[]).map((entry) => <button key={entry} className={page === entry ? "active" : ""} onClick={() => setPage(entry)}>{NAV_LABELS[entry]}</button>)}
        </nav>
        <button onClick={onLogout}>Sign out</button>
        {isSuperuser
          ? <button className="primary" onClick={handleSync}>Sync approved → main app</button>
          : <span className="muted small" title="Syncing content live is restricted to the owner's account.">Only the owner can sync content live</span>}
      </header>
      {page !== "feed" && <div className="studio-intro">
        <div><p className="eyebrow">Human content studio</p><h2>Shape the next MURA moment.</h2><p className="muted">Write, review, and publish content without automated generation.</p></div>
        <div className="studio-stats"><span><strong>{pendingCount}</strong> pending</span></div>
      </div>}
      {error && <div className="error banner">{error}</div>}
      <main className="workspace">
        {page === "feed" && <FeedHome onAdd={setCreateType} />}
        {page === "content" && <ContentManager />}
        {page === "queue" && <CandidatesPane tab="pending" onChanged={refreshPending} />}
        {page === "review" && <CandidatesPane tab="approved" onChanged={refreshPending} />}
        {page === "push" && <PushManager />}
      </main>
      {createType && <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setCreateType(null); }}>
        <div className="create-modal" role="dialog" aria-modal="true" aria-labelledby="create-modal-title">
          <ManualFeedForm
            initialType={createType}
            onBack={() => setCreateType(null)}
            onSubmitted={() => { setCreateType(null); setPage("queue"); refreshPending(); }}
          />
        </div>
      </div>}
    </div>
  );
}

function FeedHome({ onAdd }: { onAdd: (type: ItemType) => void }) {
  const [pending, setPending] = useState(0);
  useEffect(() => {
    listItems("pending").then((res) => setPending(res.count)).catch(() => {});
  }, []);
  return <section className="feed-home">
    <div className="feed-hero">
      <div>
        <p className="eyebrow">Active queue</p>
        <h2>Shape the next <em>MURA</em> moment.</h2>
        <p className="muted">Choose a format to open its dedicated writing page.</p>
      </div>
      <span className="queue-label">{pending} candidates pending</span>
    </div>
    <div className="feed-grid">
      {TOPICS.map((entry) => <article className="feed-card" key={entry.value}>
        <div className="feed-card-top"><span className="topic-eyebrow">{entry.label}</span><span>+</span></div>
        <h3>{entry.eyebrow}</h3>
        <p>{entry.helper}</p>
        <button className="add-topic" onClick={() => onAdd(entry.value)}>Add {entry.label}<span>→</span></button>
      </article>)}
    </div>
  </section>;
}

const TOPICS: Array<{
  value: ItemType;
  label: string;
  eyebrow: string;
  helper: string;
  textLabel: string;
  textPlaceholder: string;
  sourceLabel: string;
  sourcePlaceholder: string;
  tagsPlaceholder: string;
  year?: boolean;
}> = [
  { value: "quote", label: "Quote", eyebrow: "A line worth keeping", helper: "A short, stand-alone idea that can be read in one breath.", textLabel: "Quote", textPlaceholder: "Write the quote exactly as it should appear…", sourceLabel: "Author", sourcePlaceholder: "Author name", tagsPlaceholder: "discipline, courage, focus", year: true },
  { value: "motion_quote", label: "Motion quote", eyebrow: "For the Today carousel", helper: "A compact line with enough energy to work on motion.", textLabel: "Motion quote", textPlaceholder: "Write a short line for the Today screen…", sourceLabel: "Author", sourcePlaceholder: "Author name", tagsPlaceholder: "today, momentum, action", year: true },
  { value: "philosophy", label: "Philosophy", eyebrow: "A principle to practise", helper: "A clear rule or belief that helps someone live deliberately.", textLabel: "Principle", textPlaceholder: "State the principle, then make it concrete…", sourceLabel: "Thinker or source", sourcePlaceholder: "Thinker, book, or tradition", tagsPlaceholder: "stoicism, discipline, character" },
  { value: "word_of_the_day", label: "Word of the day", eyebrow: "One word, more depth", helper: "A useful term with meaning people can apply today.", textLabel: "Word and reflection", textPlaceholder: "Define the word and show how it can be lived…", sourceLabel: "Language or source", sourcePlaceholder: "Language, dictionary, or contributor", tagsPlaceholder: "vocabulary, wisdom, practice" },
  { value: "journal_story", label: "Journal story", eyebrow: "A story to carry", helper: "A lived moment, turning point, or prompt that invites reflection.", textLabel: "Story or prompt", textPlaceholder: "Tell the moment, the turning point, and what it opens up…", sourceLabel: "Person or story source", sourcePlaceholder: "Person, place, or contributor", tagsPlaceholder: "reflection, resilience, memory" },
  { value: "spiritual_insight", label: "Spiritual insight", eyebrow: "A deeper seeing", helper: "Faith-centred wisdom, scripture, or a truth worth contemplating.", textLabel: "Insight", textPlaceholder: "Write the insight clearly and leave room for reflection…", sourceLabel: "Scripture or source", sourcePlaceholder: "Book, chapter and verse, or contributor", tagsPlaceholder: "scripture, spirit, meaning" }
];

function ManualFeedForm({ initialType, onBack, onSubmitted }: { initialType?: ItemType; onBack?: () => void; onSubmitted: () => void }) {
  const [type, setType] = useState<ItemType>(initialType ?? "quote");
  const [text, setText] = useState("");
  const [source, setSource] = useState("");
  const [year, setYear] = useState("");
  const [tags, setTags] = useState("");
  const [image, setImage] = useState<File | undefined>();
  const [imageUrl, setImageUrl] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const topic = TOPICS.find((entry) => entry.value === type) ?? TOPICS[0];
  const imagePreview = useMemo(() => image ? URL.createObjectURL(image) : null, [image]);
  useEffect(() => () => { if (imagePreview) URL.revokeObjectURL(imagePreview); }, [imagePreview]);
  function clearDraft() {
    setText("");
    setSource("");
    setYear("");
    setTags("");
    setImage(undefined);
    setImageUrl("");
    const input = document.getElementById("manual-image") as HTMLInputElement | null;
    if (input) input.value = "";
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const submission: ManualSubmission = {
      type,
      text: text.trim(),
      source: source.trim(),
      year: year ? Number(year) : undefined,
      tags: tags.split(",").map((tag) => tag.trim()).filter(Boolean),
      image,
      image_url: imageUrl.trim()
    };
    if (!submission.text) return;
    setBusy(true);
    setMessage("");
    try {
      await submitManually(submission);
      setText(""); setSource(""); setYear(""); setTags(""); setImage(undefined); setImageUrl("");
      const input = document.getElementById("manual-image") as HTMLInputElement | null;
      if (input) input.value = "";
      setMessage("Sent to the pending review queue.");
      onSubmitted();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "Could not save this submission.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="manual-feed card" onSubmit={submit}>
      <div className="section-heading">
        <div><p className="eyebrow">Human feed</p><h2 id={initialType ? "create-modal-title" : undefined}>Add a candidate</h2></div>
        <span className="queue-label">Review first</span>
      </div>
      {onBack && <button type="button" className="back-link" onClick={onBack}>← Back to feed</button>}
      {(() => {
        const editor = <>
          <div className="editor-heading"><p className="eyebrow">Writing card</p><h3>{topic.label}</h3><p className="field-help">{topic.helper}</p></div>
          <label htmlFor="manual-text">{topic.textLabel} <span aria-hidden="true">*</span></label>
          <textarea id="manual-text" value={text} onChange={(e) => setText(e.target.value)} maxLength={10000} required placeholder={topic.textPlaceholder} />
          <div className="field-meta"><span className="field-help">Keep the writing clear and ready for the app.</span><span>{text.length.toLocaleString()}/10,000</span></div>
          <label htmlFor="manual-source">{topic.sourceLabel} <span className="muted">(optional)</span></label>
          <input id="manual-source" value={source} onChange={(e) => setSource(e.target.value)} placeholder={topic.sourcePlaceholder} />
          {topic.year && <><label htmlFor="manual-year">Year <span className="muted">(optional)</span></label><input id="manual-year" type="number" min="0" max="2100" value={year} onChange={(e) => setYear(e.target.value)} placeholder="Example: 1937" /></>}
          <label htmlFor="manual-tags">Tags <span className="muted">(optional)</span></label>
          <input id="manual-tags" value={tags} onChange={(e) => setTags(e.target.value)} placeholder={topic.tagsPlaceholder} />
          <label htmlFor="manual-image-url">Artwork URL <span className="muted">(optional)</span></label>
          <input id="manual-image-url" value={imageUrl} onChange={(e) => setImageUrl(e.target.value)} placeholder="https://…/image.jpg" />
          <label htmlFor="manual-image">Or upload artwork <span className="muted">(optional)</span></label>
          <input id="manual-image" type="file" accept="image/*" onChange={(e) => setImage(e.target.files?.[0])} />
          <p className="field-help">Add optional background artwork for this topic card — a link or a file.</p>
          {imagePreview && <div className="draft-artwork" style={{ "--draft-image": `url("${imagePreview}")` } as React.CSSProperties}><img className="draft-image" src={imagePreview} alt="Selected artwork preview" /><span>Optional background artwork</span></div>}
          {message && <p className={message.startsWith("Sent") ? "success form-message" : "error form-message"} role="status">{message}</p>}
          <div className="form-actions"><button className="primary" disabled={busy || !text.trim()}>{busy ? "Sending…" : "Send to review"}</button><button type="button" onClick={clearDraft}>Clear draft</button></div>
          <p className="muted small">Human-written only. Nothing is published to MURA until a reviewer approves it and syncs approved items.</p>
        </>;
        return initialType ? <div className="topic-editor standalone-editor">{editor}</div> : (
      <div className="topic-grid" aria-label="MURA topics">
        {TOPICS.map((entry) => <div className={"topic-option" + (entry.value === type ? " expanded" : "")} key={entry.value}>
          <button type="button" className={"topic-card topic-" + entry.value + (entry.value === type ? " active" : "")} onClick={() => setType(entry.value)} aria-expanded={entry.value === type}>
            <span className="topic-eyebrow">{entry.eyebrow}</span><strong>{entry.label}</strong><span>{entry.helper}</span><span className="topic-open">{entry.value === type ? "Writing below" : "Open topic"}</span>
          </button>
          {entry.value === type && <div className="topic-editor">{editor}</div>}
        </div>)}
      </div>
      );
      })()}
    </form>
  );
}

function CandidatesPane({ tab, onChanged }: { tab: Tab; onChanged?: () => void }) {
  const [activeTab, setActiveTab] = useState<Tab>(tab);
  const [items, setItems] = useState<Item[]>([]);
  const [count, setCount] = useState(0);
  const [next, setNext] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");
  const [editing, setEditing] = useState<Item | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await listItems(activeTab);
      setItems(res.items);
      setCount(res.count);
      setNext(res.next);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, [activeTab]);

  useEffect(() => { load(); }, [load]);

  function flash(message: string) {
    setMsg(message);
    setTimeout(() => setMsg(""), 4000);
  }

  async function loadMore() {
    if (!next || loadingMore) return;
    setLoadingMore(true);
    setError("");
    try {
      const res = await fetchNextPage<Item>(next);
      setItems((prev) => {
        const seen = new Set(prev.map((i) => i.id));
        return [...prev, ...res.items.filter((i) => !seen.has(i.id))];
      });
      setCount(res.count);
      setNext(res.next);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoadingMore(false);
    }
  }

  async function decide(item: Item, reviewStatus: ReviewStatus) {
    try {
      await reviewItem(item.id, reviewStatus);
      setError("");
      setItems((prev) => prev.filter((i) => i.id !== item.id));
      setCount((c) => Math.max(0, c - 1));
      onChanged?.();
    } catch (err) {
      setError("Could not mark item #" + item.id + " as " + reviewStatus + ": " + (err instanceof Error ? err.message : String(err)));
    }
  }

  async function approveAllVisible() {
    const targets = items.map((i) => i.id);
    if (!targets.length) return;
    try {
      await bulkReview(targets, "approved");
      setError("");
      flash("Approved " + targets.length + " item(s).");
      await load();
      onChanged?.();
    } catch (err) {
      setError("Bulk approve failed: " + (err instanceof Error ? err.message : String(err)));
    }
  }

  async function remove(item: Item) {
    if (!window.confirm("Delete this candidate from the queue?")) return;
    try {
      await deleteCandidate(item.id);
      setError("");
      setItems((prev) => prev.filter((i) => i.id !== item.id));
      setCount((c) => Math.max(0, c - 1));
      onChanged?.();
    } catch (err) {
      setError("Could not delete item #" + item.id + ": " + (err instanceof Error ? err.message : String(err)));
    }
  }

  async function saveEdit(patch: CandidatePatch) {
    if (!editing) return;
    await updateCandidate(editing.id, patch);
    setEditing(null);
    flash("Saved changes to item #" + editing.id + ".");
    await load();
    onChanged?.();
  }

  return (
    <div className="card review">
      <div className="review-head">
        <h2>Review queue</h2>
        <div className="tabs">
          {(["pending", "approved", "rejected"] as Tab[]).map((t) => (
            <button key={t} className={t === activeTab ? "active" : ""} onClick={() => setActiveTab(t)}>
              {t[0].toUpperCase() + t.slice(1)}
            </button>
          ))}
        </div>
        <span className="queue-label">{count} {activeTab}</span>
        {activeTab === "pending" && (
          <button onClick={approveAllVisible} disabled={!items.length}>Approve all shown</button>
        )}
      </div>
      {error && <div className="error banner" role="alert">{error}</div>}
      {msg && <div className="success banner" role="status">{msg}</div>}
      {loading ? (
        <p className="muted">Loading…</p>
      ) : items.length === 0 ? (
        <p className="muted empty">No {activeTab} items.</p>
      ) : (
        <div className="items">
          {items.map((item) => (
            <ItemCard key={item.id} item={item} mode={activeTab} onDecide={decide} onDelete={remove} onEdit={setEditing} />
          ))}
        </div>
      )}
      {next && (
        <div className="load-more">
          <button className="secondary" onClick={loadMore} disabled={loadingMore || loading}>
            {loadingMore ? "Loading…" : "Load more — showing " + items.length + " of " + count}
          </button>
        </div>
      )}
      {editing && (
        <CandidateEditModal item={editing} onClose={() => setEditing(null)} onSave={saveEdit} />
      )}
    </div>
  );
}

function ItemCard({
  item,
  mode,
  onDecide,
  onDelete,
  onEdit
}: {
  item: Item;
  mode: Tab;
  onDecide: (item: Item, status: ReviewStatus) => Promise<void>;
  onDelete?: (item: Item) => void;
  onEdit?: (item: Item) => void;
}) {
  const ref = useRef<HTMLDivElement>(null);

  function flash(kind: "approve" | "reject") {
    ref.current?.classList.add(kind === "approve" ? "flash-ok" : "flash-no");
  }

  function decide(reviewStatus: ReviewStatus, kind: "approve" | "reject") {
    flash(kind); // instant feedback; undone if the request fails
    Promise.resolve(onDecide(item, reviewStatus)).catch(() => {
      ref.current?.classList.remove("flash-ok", "flash-no");
    });
  }

  function onKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    if (mode !== "pending") return;
    if (e.key === "ArrowRight") { e.preventDefault(); decide("approved", "approve"); }
    if (e.key === "ArrowLeft") { e.preventDefault(); decide("rejected", "reject"); }
  }

  return (
    <div
      ref={ref}
      className={"item-card item-" + item.type + (item.image ? " has-artwork" : "")}
      style={item.image ? { "--item-image": `url("${item.image}")` } as React.CSSProperties : undefined}
      tabIndex={mode === "pending" ? 0 : undefined}
      onKeyDown={onKeyDown}
    >
      <span className={"badge t-" + item.type}>{item.type}</span>
      {item.synced && <span className="badge synced">synced</span>}
      <blockquote>"{item.text}"</blockquote>
      {item.image && <img className="item-image" src={item.image} alt="" />}
      <div className="meta">
        <span>{item.source}</span>
        {item.year != null && <span className="muted">{item.year}</span>}
        {item.tags.length > 0 && <span className="tags">{item.tags.join(", ")}</span>}
      </div>
      <div className="actions">
        {mode === "pending" && (
          <>
            <button className="good" onClick={() => decide("approved", "approve")}>Approve →</button>
            <button className="bad" onClick={() => decide("rejected", "reject")}>← Reject</button>
          </>
        )}
        {onEdit && <button onClick={() => onEdit(item)}>Edit</button>}
        {onDelete && <button className="bad" onClick={() => onDelete(item)}>Delete</button>}
      </div>
      {mode === "pending" && <p className="muted small hint">Focus this card, then use ← reject · → approve</p>}
    </div>
  );
}

function CandidateEditModal({
  item,
  onClose,
  onSave
}: {
  item: Item;
  onClose: () => void;
  onSave: (patch: CandidatePatch) => Promise<void>;
}) {
  const [type, setType] = useState<ItemType>(item.type);
  const [text, setText] = useState(item.text);
  const [source, setSource] = useState(item.source ?? "");
  const [year, setYear] = useState(item.year != null ? String(item.year) : "");
  const [tags, setTags] = useState((item.tags ?? []).join(", "));
  const [imageUrl, setImageUrl] = useState(item.image_url ?? "");
  const [note, setNote] = useState(item.note ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit() {
    if (!text.trim() || busy) return;
    setBusy(true);
    setError("");
    try {
      await onSave({
        type,
        text: text.trim(),
        source: source.trim(),
        year: year ? Number(year) : null,
        tags: tags.split(",").map((t) => t.trim()).filter(Boolean),
        image_url: imageUrl.trim(),
        note: note.trim()
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="editor-modal" role="dialog" aria-modal="true" aria-labelledby="candidate-edit-title">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Candidate</p>
            <h2 id="candidate-edit-title">Edit item #{item.id}</h2>
          </div>
          <button className="back-link" onClick={onClose}>← Close</button>
        </div>

        <label>Type</label>
        <select value={type} onChange={(e) => setType(e.target.value as ItemType)}>
          {(Object.keys(CONTENT_TYPE_LABELS) as ItemType[]).map((t) => <option key={t} value={t}>{CONTENT_TYPE_LABELS[t]}</option>)}
        </select>

        <label>Text <span aria-hidden="true">*</span></label>
        <textarea value={text} onChange={(e) => setText(e.target.value)} maxLength={10000} rows={6} placeholder="Write the item exactly as it should appear…" />

        <div className="editor-grid">
          <div>
            <label>Source <span className="muted">(optional)</span></label>
            <input value={source} onChange={(e) => setSource(e.target.value)} placeholder="Author, book, or scripture ref" />
          </div>
          <div>
            <label>Year <span className="muted">(optional)</span></label>
            <input type="number" min="0" max="2100" value={year} onChange={(e) => setYear(e.target.value)} placeholder="1937" />
          </div>
        </div>

        <label>Tags <span className="muted">(comma separated)</span></label>
        <input value={tags} onChange={(e) => setTags(e.target.value)} placeholder="discipline, faith, resilience" />

        <label>Artwork URL <span className="muted">(optional)</span></label>
        <input value={imageUrl} onChange={(e) => setImageUrl(e.target.value)} placeholder="https://…/image.jpg" />

        <label>Review note <span className="muted">(optional)</span></label>
        <textarea value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} rows={2} placeholder="Why this candidate matters — visible to other reviewers…" />

        {error && <div className="error form-message" role="status">{error}</div>}

        <div className="form-actions">
          <button className="primary" disabled={busy || !text.trim()} onClick={submit}>{busy ? "Saving…" : "Save changes"}</button>
          <button onClick={onClose}>Cancel</button>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Live Content — full control over everything the app shows (load, edit,
// archive/restore, delete, publish-now for the owner).
// ---------------------------------------------------------------------------
const CONTENT_TYPE_LABELS: Record<ItemType, string> = {
  quote: "Quote",
  motion_quote: "Motion quote",
  philosophy: "Philosophy",
  word_of_the_day: "Word of the day",
  journal_story: "Journal story",
  spiritual_insight: "Spiritual insight"
};

const CONTENT_STATUS_LABELS: Record<ContentStatus, string> = {
  published: "Live",
  draft: "Draft",
  archived: "Archived"
};

function ContentManager() {
  const [items, setItems] = useState<LiveItem[]>([]);
  const [count, setCount] = useState(0);
  const [next, setNext] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");
  const [filterType, setFilterType] = useState<"" | ItemType>("");
  const [filterStatus, setFilterStatus] = useState<"" | ContentStatus>("");
  const [q, setQ] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [editing, setEditing] = useState<LiveItem | null>(null);
  const [creating, setCreating] = useState(false);
  const [isSuperuser, setIsSuperuser] = useState(false);
  const [tick, setTick] = useState(0);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await listContent({
        type: filterType || undefined,
        status: filterStatus || undefined,
        q: q || undefined
      });
      setItems(res.items);
      setCount(res.count);
      setNext(res.next);
      setError("");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, [filterType, filterStatus, q, tick]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    me().then((profile) => setIsSuperuser(profile.is_superuser)).catch(() => {});
  }, []);

  function flash(message: string) {
    setMsg(message);
    setTimeout(() => setMsg(""), 5000);
  }

  function refresh() { setTick((t) => t + 1); }

  async function loadMore() {
    if (!next || loadingMore) return;
    setLoadingMore(true);
    setError("");
    try {
      const res = await fetchNextPage<LiveItem>(next);
      setItems((prev) => {
        const seen = new Set(prev.map((i) => i.id));
        return [...prev, ...res.items.filter((i) => !seen.has(i.id))];
      });
      setCount(res.count);
      setNext(res.next);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoadingMore(false);
    }
  }

  function toggle(id: number) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  const allSelected = items.length > 0 && items.every((i) => selected.has(i.id));
  function toggleAll() {
    setSelected(allSelected ? new Set() : new Set(items.map((i) => i.id)));
  }

  async function runBulk(action: "archive" | "restore" | "draft" | "delete") {
    const ids = [...selected];
    if (!ids.length) return;
    try {
      const res = await bulkContent(ids, action);
      setError("");
      flash(action === "delete"
        ? "Deleted " + (res.deleted ?? 0) + " item(s)."
        : "Updated " + (res.updated ?? 0) + " item(s) → " + action + ".");
      setSelected(new Set());
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function archiveOne(item: LiveItem) {
    try {
      await bulkContent([item.id], "archive");
      setError("");
      flash("Archived item #" + item.id + ".");
      refresh();
    } catch (err) {
      setError("Could not archive item #" + item.id + ": " + (err instanceof Error ? err.message : String(err)));
    }
  }

  async function publishOne(item: LiveItem) {
    try {
      await setContentStatus(item.id, "published");
      setError("");
      flash("Published item #" + item.id + ".");
      refresh();
    } catch (err) {
      setError("Could not publish item #" + item.id + ": " + (err instanceof Error ? err.message : String(err)));
    }
  }

  async function handleDelete(item: LiveItem) {
    if (!window.confirm("Permanently delete this " + item.type + "? This cannot be undone.")) return;
    try {
      await deleteContent(item.id);
      setError("");
      flash("Deleted.");
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleSave(payload: ContentPayload, id?: number) {
    try {
      if (id) await updateContent(id, payload); else await createContent(payload);
      setError("");
      flash(id ? "Saved." : "Created.");
      setEditing(null);
      setCreating(false);
      refresh();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      throw new Error(message);
    }
  }

  async function handleSendToReview(payload: ContentPayload) {
    try {
      await submitManually({
        type: payload.type,
        text: payload.text,
        source: payload.source,
        year: payload.year,
        tags: payload.tags,
        image: payload.image
      });
      setError("");
      flash("Sent to the pending review queue.");
      setCreating(false);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      throw new Error(message);
    }
  }

  const published = items.filter((i) => i.status === "published").length;
  const drafts = items.filter((i) => i.status === "draft").length;
  const archived = items.filter((i) => i.status === "archived").length;

  return (
    <section className="content-manager">
      <div className="studio-intro">
        <div>
          <p className="eyebrow">Live content</p>
          <h2>Everything the app shows, under your control.</h2>
          <p className="muted">Load, edit, archive, restore or delete any item. Archives hide it from the app; deletes are permanent.</p>
        </div>
        <div className="studio-stats">
          <span><strong>{published}</strong> live</span>
          <span><strong>{drafts}</strong> draft</span>
          <span><strong>{archived}</strong> archived</span>
          <span><strong>{count}</strong> item{count === 1 ? "" : "s"} total</span>
          <button className="primary" onClick={() => setCreating(true)}>+ New item</button>
        </div>
      </div>

      <div className="content-toolbar">
        <input className="content-search" type="search" placeholder="Search text or source…" value={searchInput}
          onChange={(e) => setSearchInput(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") setQ(searchInput.trim()); }} />
        <select value={filterType} onChange={(e) => setFilterType(e.target.value as "" | ItemType)} aria-label="Filter by type">
          <option value="">All types</option>
          {(Object.keys(CONTENT_TYPE_LABELS) as ItemType[]).map((t) => <option key={t} value={t}>{CONTENT_TYPE_LABELS[t]}</option>)}
        </select>
        <select value={filterStatus} onChange={(e) => setFilterStatus(e.target.value as "" | ContentStatus)} aria-label="Filter by status">
          <option value="">All statuses</option>
          <option value="published">Live</option>
          <option value="draft">Draft</option>
          <option value="archived">Archived</option>
        </select>
        <button className="secondary" onClick={() => { setFilterType(""); setFilterStatus(""); setQ(""); setSearchInput(""); }}>Clear</button>
        {selected.size > 0 && (
          <span className="bulk-bar">
            <strong>{selected.size}</strong> selected ·
            <button onClick={() => runBulk("archive")}>Archive</button>
            <button onClick={() => runBulk("draft")}>Draft</button>
            {isSuperuser && <button onClick={() => runBulk("restore")}>Publish</button>}
            <button className="bad" onClick={() => { if (window.confirm("Permanently delete " + selected.size + " item(s)?")) runBulk("delete"); }}>Delete</button>
          </span>
        )}
      </div>

      {msg && <div className="success banner">{msg}</div>}
      {error && <div className="error banner">{error}</div>}

      <div className="content-list">
        <div className="content-row content-head">
          <label className="check"><input type="checkbox" checked={allSelected} onChange={toggleAll} aria-label="Select all" /></label>
          <span className="c-type">Type</span>
          <span className="c-text">Content</span>
          <span className="c-meta">Source · tags</span>
          <span className="c-status">Status</span>
          <span className="c-updated">Updated</span>
          <span className="c-actions">Actions</span>
        </div>
        {loading ? <p className="muted empty">Loading…</p>
          : items.length === 0 ? <p className="muted empty">Nothing here yet. Use + New item or the Feed tab to add content.</p>
          : items.map((item) => (
            <div key={item.id} className={"content-row" + (selected.has(item.id) ? " selected" : "")}>
              <label className="check"><input type="checkbox" checked={selected.has(item.id)} onChange={() => toggle(item.id)} aria-label={"Select " + item.id} /></label>
              <span className="c-type"><span className={"badge t-" + item.type}>{CONTENT_TYPE_LABELS[item.type]}</span></span>
              <span className="c-text" title={item.text}>
                {item.text.length > 140 ? item.text.slice(0, 140) + "…" : item.text}
                {item.provenance && <span className="provenance" title={"From TheFeeder item #" + item.provenance.feeder_item_id}>via {item.provenance.book || "feeder"}</span>}
              </span>
              <span className="c-meta muted">{item.source || "—"}{item.tags.length > 0 && <span className="tags"> · {item.tags.join(", ")}</span>}</span>
              <span className="c-status"><span className={"status st-" + item.status}>{CONTENT_STATUS_LABELS[item.status]}</span></span>
              <span className="c-updated muted small">{new Date(item.updated_at).toLocaleDateString()}</span>
              <span className="c-actions">
                <button onClick={() => setEditing(item)}>Edit</button>
                {item.status === "published"
                  ? <button onClick={() => archiveOne(item)}>Archive</button>
                  : isSuperuser
                    ? <button className="good" onClick={() => publishOne(item)} title="Publish now (owner only)">Publish</button>
                    : <span className="muted small">{CONTENT_STATUS_LABELS[item.status].toLowerCase()}</span>}
                <button className="bad" onClick={() => handleDelete(item)}>Delete</button>
              </span>
            </div>
          ))}
        {next && (
          <div className="load-more">
            <button className="secondary" onClick={loadMore} disabled={loadingMore || loading}>
              {loadingMore ? "Loading…" : "Load more — showing " + items.length + " of " + count}
            </button>
          </div>
        )}
      </div>

      {(editing || creating) && (
        <ContentEditorModal
          initial={editing}
          isSuperuser={isSuperuser}
          onClose={() => { setEditing(null); setCreating(false); }}
          onSave={handleSave}
          onSendToReview={handleSendToReview}
        />
      )}
    </section>
  );
}

function ContentEditorModal({
  initial,
  isSuperuser,
  onClose,
  onSave,
  onSendToReview
}: {
  initial: LiveItem | null;
  isSuperuser: boolean;
  onClose: () => void;
  onSave: (payload: ContentPayload, id?: number) => Promise<void>;
  onSendToReview: (payload: ContentPayload) => Promise<void>;
}) {
  const isEdit = initial !== null;
  const [type, setType] = useState<ItemType>(initial?.type ?? "journal_story");
  const [text, setText] = useState(initial?.text ?? "");
  const [source, setSource] = useState(initial?.source ?? "");
  const [year, setYear] = useState(initial?.year ? String(initial.year) : "");
  const [tags, setTags] = useState((initial?.tags ?? []).join(", "));
  const [status, setStatus] = useState<ContentStatus>(initial?.status ?? "draft");
  const [imageUrl, setImageUrl] = useState(initial?.image_url ?? "");
  const [imageFile, setImageFile] = useState<File | undefined>();
  const [removeImage, setRemoveImage] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const imagePreview = useMemo(() => imageFile ? URL.createObjectURL(imageFile) : null, [imageFile]);
  useEffect(() => () => { if (imagePreview) URL.revokeObjectURL(imagePreview); }, [imagePreview]);

  function buildPayload(): ContentPayload {
    return {
      type,
      text: text.trim(),
      source: source.trim(),
      year: year ? Number(year) : undefined,
      tags: tags.split(",").map((t) => t.trim()).filter(Boolean),
      status,
      image_url: imageUrl.trim(),
      image: imageFile,
      remove_image: removeImage
    };
  }

  async function submit(save: (payload: ContentPayload, id?: number) => Promise<void>) {
    if (!text.trim() || busy) return;
    setBusy(true);
    setError("");
    try {
      await save(buildPayload(), isEdit ? initial.id : undefined);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="editor-modal" role="dialog" aria-modal="true" aria-labelledby="editor-modal-title">
        <div className="section-heading">
          <div>
            <p className="eyebrow">{isEdit ? "Edit live content" : "New content"}</p>
            <h2 id="editor-modal-title">{isEdit ? "Edit item #" + initial.id : "Write a new item"}</h2>
          </div>
          <button className="back-link" onClick={onClose}>← Close</button>
        </div>

        <label>Type</label>
        <select value={type} onChange={(e) => setType(e.target.value as ItemType)}>
          {(Object.keys(CONTENT_TYPE_LABELS) as ItemType[]).map((t) => <option key={t} value={t}>{CONTENT_TYPE_LABELS[t]}</option>)}
        </select>

        <label>Content <span aria-hidden="true">*</span></label>
        <textarea value={text} onChange={(e) => setText(e.target.value)} maxLength={10000} rows={6} placeholder="Write or paste the item exactly as it should appear in the app…" />

        <div className="editor-grid">
          <div>
            <label>Source <span className="muted">(optional)</span></label>
            <input value={source} onChange={(e) => setSource(e.target.value)} placeholder="Author, book, or scripture ref" />
          </div>
          <div>
            <label>Year <span className="muted">(optional)</span></label>
            <input type="number" min="0" max="2100" value={year} onChange={(e) => setYear(e.target.value)} placeholder="1937" />
          </div>
        </div>

        <label>Tags <span className="muted">(comma separated)</span></label>
        <input value={tags} onChange={(e) => setTags(e.target.value)} placeholder="discipline, faith, resilience" />

        <label>Artwork URL <span className="muted">(optional)</span></label>
        <input value={imageUrl} onChange={(e) => setImageUrl(e.target.value)} placeholder="https://…/image.jpg" />

        <label>Upload artwork <span className="muted">(replaces URL)</span></label>
        <input type="file" accept="image/*" onChange={(e) => { setImageFile(e.target.files?.[0]); if (e.target.files?.[0]) setRemoveImage(false); }} />
        {(imagePreview || (initial?.image && !imageFile)) && (
          <div className="draft-artwork" style={{ "--draft-image": "url(" + JSON.stringify(imagePreview || initial?.image) + ")" } as React.CSSProperties}>
            <img className="draft-image" src={imagePreview || initial?.image || ""} alt="Current artwork" />
            <button type="button" className="secondary" onClick={() => { setImageFile(undefined); setRemoveImage(true); }}>Remove artwork</button>
          </div>
        )}

        <label>Status</label>
        <select value={status} onChange={(e) => setStatus(e.target.value as ContentStatus)} disabled={!isSuperuser && status === "published"}>
          <option value="published" disabled={!isSuperuser}>Live (visible in app)</option>
          <option value="draft">Draft (hidden)</option>
          <option value="archived">Archived (hidden)</option>
        </select>
        {!isSuperuser && <p className="muted small">Only the owner can publish instantly. Your entries save as drafts.</p>}

        {error && <div className="error form-message" role="status">{error}</div>}

        <div className="form-actions">
          {isEdit ? (
            <>
              <button className="primary" disabled={busy || !text.trim()} onClick={() => submit(onSave)}>{busy ? "Saving…" : "Save changes"}</button>
              <button onClick={onClose}>Cancel</button>
            </>
          ) : (
            <>
              {isSuperuser && <button className="primary" disabled={busy || !text.trim()} onClick={() => submit((p, id) => onSave({ ...p, status: "published" as ContentStatus }, id))}>{busy ? "Publishing…" : "Publish now"}</button>}
              <button disabled={busy || !text.trim()} onClick={() => submit((p, id) => onSave({ ...p, status: "draft" as ContentStatus }, id))}>Save draft</button>
              <button disabled={busy || !text.trim()} onClick={() => submit((p) => onSendToReview({ ...p, status: "draft" as ContentStatus }))}>Send to review</button>
              <button onClick={onClose}>Cancel</button>
            </>
          )}
        </div>
        {!isEdit && <p className="muted small">Publish now = instantly live (owner only). Send to review = goes through the pending queue first.</p>}
      </div>
    </div>
  );
}


// ---------------------------------------------------------------------------
// Push — compose broadcast notifications (Signo, free) and send now or on a
// natural schedule (daily morning / chosen weekday).
// ---------------------------------------------------------------------------
const WEEKDAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const PRESET_PUSHES: PushPayload[] = [
  { title: "Own the first hour", body: "It's morning. Win the first hour and the day follows. What is the ONE thing you'll do first?", schedule: "daily", send_time: "06:30" },
  { title: "Sunday reflection", body: "Before the week turns — what moved you, what did you learn, what will you carry forward? Journal three lines.", schedule: "weekly", send_time: "08:00", weekday: 6 }
];

function PushManager() {
  const [items, setItems] = useState<PushCampaign[]>([]);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");
  const [err, setErr] = useState("");

  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [schedule, setSchedule] = useState<PushPayload["schedule"]>("now");
  const [sendTime, setSendTime] = useState("06:30");
  const [weekday, setWeekday] = useState(6);

  const load = useCallback(async () => {
    try {
      setItems(await listPushCampaigns());
      setErr("");
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  function flash(m: string) {
    setMsg(m);
    setTimeout(() => setMsg(""), 5000);
  }

  function resetForm() {
    setTitle(""); setBody(""); setSchedule("now"); setSendTime("06:30"); setWeekday(6);
  }

  function applyPreset(p: PushPayload) {
    setTitle(p.title); setBody(p.body || ""); setSchedule(p.schedule);
    setSendTime(p.send_time || "06:30"); setWeekday(p.weekday ?? 6);
  }

  async function saveAndMaybeSend(sendNow: boolean) {
    if (!title.trim()) { setErr("Give the notification a title."); return; }
    setBusy(true); setErr(""); setMsg("");
    try {
      const payload: PushPayload = {
        title: title.trim(),
        body: body.trim(),
        schedule,
        send_time: sendTime || undefined,
        weekday: schedule === "weekly" ? weekday : null
      };
      const created = await createPushCampaign(payload);
      if (sendNow) {
        const res = await sendPushCampaign(created.id);
        flash("Sent to " + (res.delivered ?? 0) + " device(s).");
      } else {
        flash("Saved" + (schedule === "now" ? " — press Send to deliver it" : " — will send on schedule."));
      }
      resetForm();
      await load();
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function sendOne(c: PushCampaign) {
    if (!window.confirm("Send \"" + c.title + "\" to every device now?")) return;
    setBusy(true);
    try {
      const res = await sendPushCampaign(c.id);
      flash("Sent: " + (res.delivered ?? 0) + " device(s).");
      await load();
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function testOne(c: PushCampaign) {
    setBusy(true);
    try {
      const res = await testPushCampaign(c.id);
      flash("Test sent to " + (res.delivered ?? 0) + " device(s) and your in-app feed.");
      await load();
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function removeOne(c: PushCampaign) {
    if (!window.confirm("Delete this campaign?")) return;
    await deletePushCampaign(c.id).catch((e) => setErr(e.message));
    await load();
  }

  function scheduleLabel(c: PushCampaign): string {
    if (c.schedule === "daily") return "Daily " + c.send_time;
    if (c.schedule === "weekly") return "Weekly " + (c.weekday != null ? WEEKDAY_LABELS[c.weekday] : "?") + " " + c.send_time;
    return "Send once";
  }

  return (
    <section className="content-manager">
      <div className="studio-intro">
        <div>
          <p className="eyebrow">Push notifications</p>
          <h2>Tell people something worth opening MURA for.</h2>
          <p className="muted">Broadcasts go out free via Signo. Start naturally — morning kick, Sunday reflection, streak nudges.</p>
        </div>
        <div className="studio-stats">
          <button className="primary" disabled={busy || !title.trim()} onClick={() => saveAndMaybeSend(true)}>{busy ? "Sending…" : "Send now"}</button>
          <button disabled={busy || !title.trim()} onClick={() => saveAndMaybeSend(false)}>Save</button>
        </div>
      </div>

      {msg && <div className="success banner">{msg}</div>}
      {err && <div className="error banner">{err}</div>}

      <div className="content-toolbar">
        <span className="muted">Start from a natural template:</span>
        {PRESET_PUSHES.map((p, i) => (
          <button key={i} className="secondary" onClick={() => applyPreset(p)}>{p.title}</button>
        ))}
      </div>

      <form className="manual-feed card" onSubmit={(e) => { e.preventDefault(); saveAndMaybeSend(false); }}>
        <label>Title <span aria-hidden="true">*</span></label>
        <input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={120} placeholder="Own the first hour" />
        <label>Body</label>
        <textarea value={body} onChange={(e) => setBody(e.target.value)} maxLength={500} rows={3} placeholder="What should the notification say?" />
        <div className="editor-grid">
          <div>
            <label>Schedule</label>
            <select value={schedule} onChange={(e) => setSchedule(e.target.value as PushPayload["schedule"])}>
              <option value="now">Send once, now</option>
              <option value="daily">Daily (every morning)</option>
              <option value="weekly">Weekly (chosen day)</option>
            </select>
          </div>
          {schedule !== "now" && (
            <>
              <div>
                <label>Time</label>
                <input type="time" value={sendTime} onChange={(e) => setSendTime(e.target.value)} />
              </div>
              {schedule === "weekly" && (
                <div>
                  <label>Day</label>
                  <select value={weekday} onChange={(e) => setWeekday(Number(e.target.value))}>
                    {WEEKDAY_LABELS.map((d, i) => <option key={d} value={i}>{d}</option>)}
                  </select>
                </div>
              )}
            </>
          )}
        </div>
        <p className="muted small">"Send now" delivers to every device immediately. Daily/Weekly campaigns send only when the server's scheduled task runs — until it fires, use the "Send" button on a campaign to deliver it reliably.</p>
      </form>

      <h3 className="push-heading">Campaigns</h3>
      <div className="content-list">
        {items.length === 0 && <p className="muted empty">No campaigns yet.</p>}
        {items.map((c) => (
          <div key={c.id} className="content-row" style={{ gridTemplateColumns: "1fr 10rem 9rem 8rem" }}>
            <span className="c-text">
              <strong>{c.title}</strong>
              {c.body && <span className="provenance">{c.body}</span>}
            </span>
            <span className="c-meta muted">{scheduleLabel(c)}</span>
            <span className="c-status"><span className={"status " + (c.last_sent_date ? "st-done" : "st-draft")}>{c.last_sent_date ? "Last sent " + c.last_sent_date : "Not sent"}</span></span>
            <span className="c-actions">
              <button onClick={() => testOne(c)} title="Deliver now and show in your in-app feed">Test</button>
              <button onClick={() => sendOne(c)}>Send</button>
              <button className="bad" onClick={() => removeOne(c)}>Delete</button>
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}


