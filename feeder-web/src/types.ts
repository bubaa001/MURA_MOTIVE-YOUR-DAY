export type ReviewStatus = "pending" | "approved" | "rejected";
export type ItemType = "quote" | "motion_quote" | "philosophy" | "word_of_the_day" | "journal_story" | "spiritual_insight";

export interface Item {
  id: number;
  type: ItemType;
  text: string;
  source: string;
  year?: number | null;
  tags: string[];
  image?: string | null;
  image_url: string;
  review_status: ReviewStatus;
  synced: boolean;
  created_at: string;
  updated_at?: string;
  note?: string;
  submitted_by_name?: string;
  reviewed_by_name?: string;
  reviewed_at?: string | null;
}

export interface ManualSubmission {
  type: ItemType;
  text: string;
  source?: string;
  year?: number;
  tags?: string[];
  image?: File;
  image_url?: string;
}

export type ContentStatus = "published" | "draft" | "archived";

export interface ContentProvenance {
  feeder_item_id: number;
  book: string | null;
  review_status: ReviewStatus;
}

export interface LiveItem {
  id: number;
  type: ItemType;
  text: string;
  source: string;
  year?: number | null;
  tags: string[];
  status: ContentStatus;
  image?: string | null;
  image_url: string;
  created_at: string;
  updated_at: string;
  provenance: ContentProvenance | null;
}

export interface Me {
  id: number;
  username: string;
  is_staff: boolean;
  is_superuser: boolean;
}

export interface ContentPayload {
  type: ItemType;
  text: string;
  source?: string;
  year?: number;
  tags?: string[];
  status?: ContentStatus;
  image_url?: string;
  image?: File;
  remove_image?: boolean;
}
