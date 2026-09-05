"""Seed the ContentItem hub with starter material.

Quotes: Think and Grow Rich (Napoleon Hill) — short excerpts only.
Prayers: The Game of Life and How to Play It (Florence Scovel Shinn) plus
KJV scripture. The Shinn book is public domain; scripture (KJV) likewise.
Even so, entries are deliberately kept to short excerpts/adaptations so the
corpus stays safe for the eventual multi-user/paid product.

Idempotent: running twice will not duplicate items.
"""
from django.core.management.base import BaseCommand

from content.models import ContentItem

QUOTES = [
    ("Whatever the mind of man can conceive and believe, it can achieve.", "Think and Grow Rich", ["belief", "vision"]),
    ("Every adversity carries with it the seed of an equal or greater benefit.", "Think and Grow Rich", ["adversity", "persistence"]),
    ("The starting point of all achievement is desire. Weak desire brings weak results.", "Think and Grow Rich", ["desire"]),
    ("Patience, persistence and perspiration make an unbeatable combination for success.", "Think and Grow Rich", ["persistence"]),
    ("A goal is a dream with a deadline.", "Think and Grow Rich", ["goals"]),
    ("Do not wait. The time will never be just right.", "Think and Grow Rich", ["action"]),
    ("Strength and growth come only through continuous effort and struggle.", "Think and Grow Rich", ["effort", "discipline"]),
    ("If you cannot do great things yourself, remember that you may do small things in a great way.", "Think and Grow Rich", ["action"]),
    ("The way of success is the way of continuous pursuit of knowledge.", "Think and Grow Rich", ["learning"]),
    ("Fears are nothing more than states of mind.", "Think and Grow Rich", ["fear", "mindset"]),
    ("You are the master of your destiny. You can influence, direct and control your own environment.", "Think and Grow Rich", ["ownership"]),
    ("Procrastination is the bad habit of putting off until the day after tomorrow what should have been done the day before yesterday.", "Think and Grow Rich", ["discipline", "procrastination"]),
]

PRAYERS = [
    ("The game of life is the game of boomerangs. Our thoughts, deeds and words return to us sooner or later, with astounding accuracy.", "The Game of Life and How to Play It", ["thought", "reciprocity"]),
    ("Man's word is his wand, filled with magic and power.", "The Game of Life and How to Play It", ["word", "faith"]),
    ("Fear is only inverted faith; it is faith in evil instead of good.", "The Game of Life and How to Play It", ["fear", "faith"]),
    ("Infinite Spirit, open the way — let there be no delays and no hindrances.", "The Game of Life and How to Play It (adapted)", ["open-the-way", "trust"]),
    ("Faith is the substance of things hoped for, the evidence of things not seen.", "Hebrews 11:1 (KJV)", ["faith", "scripture"]),
    ("Whatsoever ye desire, when ye pray, believe that ye receive them, and ye shall have them.", "Mark 11:24 (KJV)", ["prayer", "abundance", "scripture"]),
    ("As he thinketh in his heart, so is he.", "Proverbs 23:7 (KJV)", ["thought", "scripture"]),
    ("Be not afraid, only believe.", "Mark 5:36 (KJV)", ["courage", "scripture"]),
]

PHILOSOPHIES = [
    ("Discipline equals freedom.", "Jocko Willink", ["discipline"]),
    ("The impediment to action advances action. What stands in the way becomes the way.", "Marcus Aurelius, Meditations", ["stoicism", "obstacles"]),
    ("We are what we repeatedly do. Excellence, then, is not an act, but a habit.", "Will Durant, summarizing Aristotle", ["excellence", "habits"]),
    ("Never miss twice. Missing once is an accident; missing twice is the beginning of a new (bad) habit.", "MURA principle", ["habits", "consistency"]),
    ("Amor fati — not merely bear what is necessary, but love it.", "Nietzsche / Stoics", ["acceptance"]),
    ("Do fewer things, done better.", "MURA principle", ["focus"]),
    ("Small daily deposits — of money, of effort, of character — compound into fortunes.", "MURA principle", ["compounding", "wealth"]),
    ("Memento mori: remember you must die — so today matters.", "Stoic memento", ["perspective"]),
]

# Short, energetic lines for the Today motion carousel and home-screen widget.
MOTION_QUOTES = [
    ("One rep more than yesterday.", "MURA", ["momentum"]),
    ("You are exactly where your habits put you.", "MURA", ["habits", "ownership"]),
    ("Discipline is choosing what you want most over what you want now.", "MURA", ["discipline", "focus"]),
    ("The alarm clock is a yes to your future.", "MURA", ["morning", "commitment"]),
    ("Small steps every day make giants.", "MURA", ["consistency"]),
    ("Own the morning, own the day.", "MURA", ["morning", "routine"]),
    ("Your future self is watching. Make them proud.", "MURA", ["vision", "commitment"]),
    ("Don't count the days. Make the days count.", "MURA", ["action", "purpose"]),
    ("Action cures fear.", "MURA", ["courage", "action"]),
    ("The only bad workout is the one that didn't happen.", "MURA", ["health", "consistency"]),
    ("Win the first hour, and the day follows.", "MURA", ["morning", "focus"]),
    ("Be the hardest worker in the room — silently.", "MURA", ["work", "humility"]),
]


class Command(BaseCommand):
    help = "Seed quotes/prayers/philosophies into the ContentItem hub."

    def handle(self, *args, **options):
        created = skipped = 0
        batches = (
            ("quote", QUOTES),
            # Prayers are authored as spiritual insights now (no prayer slot).
            ("spiritual_insight", PRAYERS),
            ("philosophy", PHILOSOPHIES),
            ("motion_quote", MOTION_QUOTES),
        )
        for type_name, rows in batches:
            for text, source, tags in rows:
                _, was_created = ContentItem.objects.get_or_create(
                    type=type_name,
                    text=text,
                    defaults={"source": source, "tags": tags},
                )
                if was_created:
                    created += 1
                else:
                    skipped += 1
        self.stdout.write(self.style.SUCCESS(f"Seeded {created} new content items ({skipped} already present)."))
