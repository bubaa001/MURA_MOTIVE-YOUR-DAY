---
name: Obsidian & Amber
colors:
  surface: '#131313'
  surface-dim: '#131313'
  surface-bright: '#393939'
  surface-container-lowest: '#0e0e0e'
  surface-container-low: '#1c1b1b'
  surface-container: '#201f1f'
  surface-container-high: '#2a2a2a'
  surface-container-highest: '#353534'
  on-surface: '#e5e2e1'
  on-surface-variant: '#d8c3ad'
  inverse-surface: '#e5e2e1'
  inverse-on-surface: '#313030'
  outline: '#a08e7a'
  outline-variant: '#534434'
  surface-tint: '#ffb95f'
  primary: '#ffc174'
  on-primary: '#472a00'
  primary-container: '#f59e0b'
  on-primary-container: '#613b00'
  inverse-primary: '#855300'
  secondary: '#6bd8cb'
  on-secondary: '#003732'
  secondary-container: '#29a195'
  on-secondary-container: '#00302b'
  tertiary: '#c7c8ff'
  on-tertiary: '#1000a9'
  tertiary-container: '#a7a9ff'
  on-tertiary-container: '#2b29bb'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#ffddb8'
  primary-fixed-dim: '#ffb95f'
  on-primary-fixed: '#2a1700'
  on-primary-fixed-variant: '#653e00'
  secondary-fixed: '#89f5e7'
  secondary-fixed-dim: '#6bd8cb'
  on-secondary-fixed: '#00201d'
  on-secondary-fixed-variant: '#005049'
  tertiary-fixed: '#e1e0ff'
  tertiary-fixed-dim: '#c0c1ff'
  on-tertiary-fixed: '#07006c'
  on-tertiary-fixed-variant: '#2f2ebe'
  background: '#131313'
  on-background: '#e5e2e1'
  surface-variant: '#353534'
typography:
  display-lg:
    fontFamily: Sora
    fontSize: 48px
    fontWeight: '800'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Sora
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Sora
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 34px
  headline-md:
    fontFamily: Sora
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  body-lg:
    fontFamily: Hanken Grotesk
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Hanken Grotesk
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: Hanken Grotesk
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.05em
  stat-lg:
    fontFamily: Sora
    fontSize: 36px
    fontWeight: '800'
    lineHeight: 44px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  container-padding: 24px
  gutter: 16px
  stack-sm: 12px
  stack-md: 24px
  stack-lg: 40px
---

## Brand & Style

The design system is engineered for a premium, high-energy self-motivation and discipline platform. It targets an adult audience seeking a "high-performance" lifestyle through a sophisticated and focused interface.

The aesthetic blends **Modern Corporate** precision with **Glassmorphism** and **Tactile** depth. The interface utilizes a "Night Mode" foundation to reduce cognitive load and emphasize focus. Emotional responses should range from the intense energy of a streak (Amber) to the disciplined calm of reflection (Teal). High-end finishes, such as subtle gradient fills and soft glows, distinguish the experience as a premium tool rather than a casual utility.

## Colors

This design system utilizes a deep charcoal base to create a high-contrast environment where performance metrics can shine.

- **Primary (Amber-Gold):** Used for "Energy" states, active streaks, and primary calls to action. It represents fire and momentum.
- **Secondary (Deep Teal):** Reserved for "Calm" states, meditation, prayer, or reflection modules.
- **Tertiary (Indigo):** Assigned to long-term "Goals" and intellectual pursuits.
- **Quaternary (Coral):** Specifically for "Health," vitality, and physical biometric data.
- **Neutral/Surface:** The background is a true #121212, while containers use a slightly elevated #1E1E1E with subtle glassmorphic properties to maintain depth.

## Typography

The typography strategy pairs the technical, geometric strength of **Sora** for headlines and data with the clean, contemporary legibility of **Hanken Grotesk** for functional text.

**Display and Stats:** Use Sora for all numbers and primary headings. The extra-bold weights communicate authority and progress. Tighten letter-spacing on larger sizes to maintain a dense, premium feel.

**Functional Text:** Use Hanken Grotesk for body copy and labels. Labels should be uppercase with generous letter-spacing to provide a modern, navigational clarity against the dark background.

## Layout & Spacing

The design system employs a **Fluid Grid** model with a focus on generous internal container padding to allow the glassmorphic effects to breathe.

- **Grid:** A 12-column system for desktop and a 4-column system for mobile.
- **Margins:** 24px horizontal margins on mobile to ensure content feels centered and prestigious.
- **Rhythm:** Spacing follows an 8px linear scale. Vertical stacking of cards should use "stack-md" (24px) to distinguish between different habit categories, while items within a card use "stack-sm" (12px).

## Elevation & Depth

Hierarchy is established through **Tonal Layering** and **Glassmorphism** rather than traditional heavy shadows.

- **Surface Levels:** The base is #121212. Cards sit on this base at #1E1E1E.
- **Glassmorphism:** Use a `backdrop-filter: blur(20px)` and a semi-transparent white border (8%) to simulate glass.
- **Soft Glows:** Active elements (like a burning streak) should emit a subtle, colored outer glow (`box-shadow`) matching their category color (e.g., Amber glow for streaks) with a high blur radius (32px+) and low opacity (20%).
- **Inner Depth:** Interactive states use a subtle inner shadow to create a "pressed" tactile feel during the habit completion animation.

## Shapes

The shape language is defined by large, organic radii that feel soft to the touch, contrasting with the "hard" discipline of the app's content.

- **Primary Cards:** Use a fixed 32px corner radius for a friendly, premium appearance.
- **Interactive Elements:** Buttons and input fields use a 16px radius.
- **Selection Indicators:** Use "Pill" shapes (full radius) for chips and progress bar caps to emphasize the fluid nature of growth.

## Components

### Progress Elements
- **Rings:** Use heavy stroke weights (8px-12px) with rounded caps. Primary progress rings should feature a subtle gradient following the arc.
- **Heatmaps:** Calendar squares for streaks use the 8px radius with color intensity increasing based on habit completion density.

### Tactile Cards
- All cards feature a 1px solid top-border (`rgba(255,255,255,0.1)`) to catch "light" from above.
- Backgrounds may contain a subtle diagonal linear gradient (from #1E1E1E to #252525).

### Habit Checklist
- Checklist items are high-height rows (64px+) with a custom checkbox that transforms into a "Check" icon with a scale-up bounce animation upon selection.
- Active items trigger a haptic pulse and a temporary glow effect.

### Bottom Navigation
- A floating "Glass" bar with a 32px radius. 
- Active states feature a vertical translation (move up 4px) and a soft glow of the primary color beneath the icon.

### Visual Assets
- **Icons:** Use a 2px stroke weight with rounded terminals.
- **Imagery:** Abstract illustrations should use "Mesh Gradients" mixing the primary and secondary colors against the charcoal background.