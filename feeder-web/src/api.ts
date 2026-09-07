import type { ContentPayload, ContentStatus, Item, ItemType, LiveItem, Me, ManualSubmission, ReviewStatus } from "./types";

const API = "https://bubaa.pythonanywhere.com/api/v1";
const ACCESS_KEY = "feeder_access";
const REFRESH_KEY = "feeder_refresh";

export function isLoggedIn(): boolean {
  return !!localStorage.getItem(ACCESS_KEY);
}

export function logout(): void {
  localStorage.removeItem(ACCESS_KEY);
  localStorage.removeItem(REFRESH_KEY);
}

export async function login(username: string, password: string): Promise<void> {
  const res = await fetch(API + "/auth/token/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password })
  });
  if (!res.ok) throw new Error("Login failed — check your staff credentials.");
  const data = await res.json();
  localStorage.setItem(ACCESS_KEY, data.access);
  localStorage.setItem(REFRESH_KEY, data.refresh);
}

export async function registerEmployee(
  username: string,
  email: string,
  password: string,
  signupKey: string
): Promise<void> {
  const res = await fetch(API + "/auth/register/employee/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, email, password, signup_key: signupKey })
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const keyError = body.signup_key;
    throw new Error(
      (typeof keyError === "string" ? keyError : keyError?.[0]) ||
        body.detail ||
        "Registration failed."
    );
  }
  const data = await res.json();
  localStorage.setItem(ACCESS_KEY, data.access);
  localStorage.setItem(REFRESH_KEY, data.refresh);
}

async function refreshTokens(): Promise<boolean> {
  const refresh = localStorage.getItem(REFRESH_KEY);
  if (!refresh) {
    logout();
    window.location.reload();
    return false;
  }
  const res = await fetch(API + "/auth/token/refresh/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh })
  });
  if (!res.ok) {
    logout();
    window.location.reload();
    return false;
  }
  const data = await res.json();
  localStorage.setItem(ACCESS_KEY, data.access);
  return true;
}

async function request<T>(path: string, options: RequestInit = {}, retry = true): Promise<T> {
  const url = path.startsWith("http") ? path : API + path;
  const token = localStorage.getItem(ACCESS_KEY);
  const res = await fetch(url, {
    ...options,
    headers: {
      ...(options.headers || {}),
      ...(token ? { Authorization: "Bearer " + token } : {})
    }
  });
  if (res.status === 401 && retry && (await refreshTokens())) {
    return request<T>(path, options, false);
  }
  if (!res.ok) {
    let detail = res.statusText;
    try {
      const body = await res.json();
      detail = typeof body === "string" ? body : body.detail || JSON.stringify(body);
    } catch {
      /* keep statusText */
    }
    throw new Error(detail);
  }
  return res.status === 204 ? (undefined as T) : res.json();
}

// --- DRF pagination ----------------------------------------------------------
// Lists now return {count, next, previous, results}. page_size is capped at
// 200 by the backend, so "next" must be followed to see everything. The
// absolute `next` URL can be fetched directly by request().

interface Paginated<T> {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
}

function isPaginated<T>(data: T[] | Paginated<T>): data is Paginated<T> {
  return !Array.isArray(data) && typeof (data as Paginated<T>).results === "object";
}

export interface ListPage<T> {
  items: T[];
  count: number;
  next: string | null;
}

/** Fetch the first page of a paginated list, exposing count + the next URL. */
export async function fetchPage<T>(path: string): Promise<ListPage<T>> {
  const data = await request<T[] | Paginated<T>>(path);
  if (isPaginated(data)) {
    return { items: data.results, count: data.count, next: data.next };
  }
  return { items: data, count: data.length, next: null };
}

/** Fetch a subsequent page by its absolute `next` URL. */
export function fetchNextPage<T>(nextUrl: string): Promise<ListPage<T>> {
  return request<Paginated<T>>(nextUrl).then((data) => ({
    items: data.results,
    count: data.count,
    next: data.next
  }));
}

/** Follow `next` until it runs out (or maxPages is hit) and concatenate results. */
export async function fetchAll<T>(path: string, maxPages = 10): Promise<ListPage<T>> {
  const first = await fetchPage<T>(path);
  const items = [...first.items];
  let next = first.next;
  let pages = 1;
  while (next && pages < maxPages) {
    const page = await fetchNextPage<T>(next);
    items.push(...page.items);
    next = page.next;
    pages += 1;
  }
  return { items, count: first.count, next };
}

export function listItems(reviewStatus?: ReviewStatus): Promise<ListPage<Item>> {
  const qs = new URLSearchParams();
  if (reviewStatus) qs.set("review_status", reviewStatus);
  return fetchAll<Item>("/feeder/items/?" + qs.toString());
}

export function deleteCandidate(id: number): Promise<void> {
  return request("/feeder/items/" + id + "/", { method: "DELETE" });
}

export function reviewItem(id: number, review_status: ReviewStatus): Promise<Item> {
  return request<Item>("/feeder/items/" + id + "/", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ review_status })
  });
}

export interface CandidatePatch {
  type?: ItemType;
  text?: string;
  source?: string;
  year?: number | null;
  tags?: string[];
  image_url?: string;
  review_status?: ReviewStatus;
  note?: string;
}

export function updateCandidate(id: number, patch: CandidatePatch): Promise<Item> {
  return request<Item>("/feeder/items/" + id + "/", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch)
  });
}

export function bulkReview(ids: number[], review_status: "approved" | "rejected"): Promise<void> {
  return request("/feeder/items/bulk-review/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ids, review_status })
  });
}

export interface SyncItemResult {
  item_id: number;
  content_id: number | null;
  created: boolean;
  ok: boolean;
  error?: string;
}

export interface SyncResponse {
  submitted: number;
  synced: number;
  results: SyncItemResult[];
}

export function syncApproved(): Promise<SyncResponse> {
  return request("/feeder/items/sync/", { method: "POST" });
}

export function submitManually(submission: ManualSubmission): Promise<{ item: Item }> {
  if (submission.image) {
    const form = new FormData();
    form.append("type", submission.type);
    form.append("text", submission.text);
    form.append("source", submission.source || "");
    if (submission.year) form.append("year", String(submission.year));
    form.append("tags", JSON.stringify(submission.tags || []));
    form.append("image_url", submission.image_url || "");
    form.append("image", submission.image);
    return request("/feeder/items/manual-submit/", { method: "POST", body: form });
  }
  return request("/feeder/items/manual-submit/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(submission)
  });
}

// --- Live content (staff studio: load, edit, archive/restore, delete) -------

export function me(): Promise<Me> {
  return request<Me>("/me/");
}

export function listContent(filter: { type?: string; status?: string; q?: string } = {}): Promise<ListPage<LiveItem>> {
  const qs = new URLSearchParams();
  if (filter.type) qs.set("type", filter.type);
  if (filter.status) qs.set("status", filter.status);
  if (filter.q) qs.set("q", filter.q);
  return fetchAll<LiveItem>("/feeder/content/?" + qs.toString());
}

function contentForm(payload: ContentPayload): FormData | string {
  const tags = payload.tags || [];
  if (payload.image) {
    const form = new FormData();
    form.append("type", payload.type);
    form.append("text", payload.text);
    form.append("source", payload.source || "");
    if (payload.year) form.append("year", String(payload.year));
    // DRF JSONField needs tags as ONE JSON-encoded string in form data.
    form.append("tags", JSON.stringify(tags));
    form.append("status", payload.status || "draft");
    form.append("image_url", payload.image_url || "");
    if (payload.remove_image) form.append("remove_image", "true");
    form.append("image_file", payload.image);
    return form;
  }
  const body: Record<string, unknown> = {
    type: payload.type,
    text: payload.text,
    source: payload.source || "",
    tags,
    status: payload.status || "draft",
    image_url: payload.image_url || ""
  };
  if (payload.year) body.year = payload.year;
  if (payload.remove_image) body.remove_image = true;
  return JSON.stringify(body);
}

export function createContent(payload: ContentPayload): Promise<LiveItem> {
  const body = contentForm(payload);
  return request<LiveItem>("/feeder/content/", {
    method: "POST",
    headers: body instanceof FormData ? undefined : { "Content-Type": "application/json" },
    body
  });
}

export function updateContent(id: number, payload: ContentPayload): Promise<LiveItem> {
  const body = contentForm(payload);
  return request<LiveItem>("/feeder/content/" + id + "/", {
    method: "PATCH",
    headers: body instanceof FormData ? undefined : { "Content-Type": "application/json" },
    body
  });
}

/** Status-only PATCH (server ignores published for non-superusers). */
export function setContentStatus(id: number, status: ContentStatus): Promise<LiveItem> {
  return request<LiveItem>("/feeder/content/" + id + "/", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ status })
  });
}

export function deleteContent(id: number): Promise<void> {
  return request("/feeder/content/" + id + "/", { method: "DELETE" });
}

export function bulkContent(ids: number[], action: string): Promise<{ updated?: number; deleted?: number }> {
  return request("/feeder/content/bulk/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ids, action })
  });
}
// --- Push campaigns (studio broadcasts via Signo) ---------------------------

export interface PushCampaign {
  id: number;
  title: string;
  body: string;
  schedule: "now" | "daily" | "weekly";
  send_time: string;
  weekday: number | null;
  is_active: boolean;
  last_sent_date: string | null;
  created_at: string;
}

export interface PushPayload {
  title: string;
  body: string;
  schedule: "now" | "daily" | "weekly";
  send_time?: string;
  weekday?: number | null;
  is_active?: boolean;
}

export function listPushCampaigns(): Promise<PushCampaign[]> {
  return fetchAll<PushCampaign>("/feeder/push/").then((page) => page.items);
}

export function createPushCampaign(payload: PushPayload): Promise<PushCampaign> {
  return request<PushCampaign>("/feeder/push/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
}

export function updatePushCampaign(id: number, payload: Partial<PushPayload>): Promise<PushCampaign> {
  return request<PushCampaign>("/feeder/push/" + id + "/", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
}

export function sendPushCampaign(id: number): Promise<{ delivered: number; event_id?: string }> {
  return request("/feeder/push/" + id + "/send/", { method: "POST" });
}

export function deletePushCampaign(id: number): Promise<void> {
  return request("/feeder/push/" + id + "/", { method: "DELETE" });
}

export function testPushCampaign(id: number): Promise<{ delivered: number; event_id?: string; in_app: boolean }> {
  return request("/feeder/push/" + id + "/test/", { method: "POST" });
}
