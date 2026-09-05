import type { ContentPayload, Item, LiveItem, Me, ManualSubmission, ReviewStatus } from "./types";

const API = "/api/v1";
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
  password: string
): Promise<void> {
  const res = await fetch(API + "/auth/register/employee/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, email, password })
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.signup_key?.[0] || body.detail || "Registration failed.");
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
  const token = localStorage.getItem(ACCESS_KEY);
  const res = await fetch(API + path, {
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

export function listItems(reviewStatus?: ReviewStatus): Promise<Item[]> {
  const qs = new URLSearchParams();
  if (reviewStatus) qs.set("review_status", reviewStatus);
  return request<Item[] | { results: Item[] }>("/feeder/items/?" + qs.toString()).then(normalizeList);
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

export function bulkReview(ids: number[], review_status: "approved" | "rejected"): Promise<void> {
  return request("/feeder/items/bulk-review/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ids, review_status })
  });
}

export function syncApproved(): Promise<{ submitted: number; synced: number }> {
  return request("/feeder/items/sync/", { method: "POST" });
}

export function submitManually(submission: ManualSubmission): Promise<{ item: Item }> {
  if (submission.image) {
    const form = new FormData();
    form.append("type", submission.type);
    form.append("text", submission.text);
    form.append("source", submission.source || "");
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

function normalizeList<T>(data: T[] | { results: T[] }): T[] {
  return Array.isArray(data) ? data : data.results;
}

// --- Live content (staff studio: load, edit, archive/restore, delete) -------

export function me(): Promise<Me> {
  return request<Me>("/me/");
}

export function listContent(filter: { type?: string; status?: string; q?: string } = {}): Promise<LiveItem[]> {
  const qs = new URLSearchParams();
  if (filter.type) qs.set("type", filter.type);
  if (filter.status) qs.set("status", filter.status);
  if (filter.q) qs.set("q", filter.q);
  qs.set("page_size", "1000");
  return request<LiveItem[] | { results: LiveItem[] }>("/feeder/content/?" + qs.toString()).then(normalizeList);
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
  return request<PushCampaign[] | { results: PushCampaign[] }>("/feeder/push/?page_size=100").then(normalizeList);
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
