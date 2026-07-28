# BRIVIBA UI Specification

The UI must match the reference render exactly.
Product requirements are defined in [../SPEC.md](../SPEC.md).

Reference image:

- [assets/BRIVIBA_UI_REFERENCE.jpeg](assets/BRIVIBA_UI_REFERENCE.jpeg)

## 1. Visual Target

The first screen is a browser window with:

- translucent macOS-style outer window;
- a left vertical Liquid Glass dock;
- a content area starting to the right of the dock;
- a floating top address field;
- separate circular navigation controls;
- separate right-side circular action controls;
- rounded visual language throughout.

The implementation must be measured against the reference image, not against a generic browser layout.

## 2. Window

Required:

- rounded window corners;
- soft shadow;
- native macOS traffic-light controls;
- translucent or glass-like chrome;
- no traditional top tab bar.

The main content must occupy most of the window.

## 3. Left Dock

Required:

- fixed vertical dock on the far left;
- Liquid Glass material;
- rounded container;
- vertically stacked icons;
- compact width;
- bottom utility icons.

Forbidden:

- expandable sidebar;
- text labels in the dock;
- nested side navigation;
- secondary side menu.

## 4. Top Controls

Required:

- Back button as a separate circular control;
- Forward button as a separate circular control;
- Reload button as a separate circular control;
- centered floating address field;
- right-side circular controls for mode/menu actions.

The address field must not be attached to a full-width toolbar strip.

## 5. Page-Aware Chrome Color

The top chrome must automatically adopt the current page color.

Color source:

- compute from the current website DOM;
- prefer dominant background and surface colors;
- update after navigation;
- update after major page theme changes if detectable.

The computed color must remain subtle and compatible with macOS glass.

## 6. Content Layout

The webpage content area begins below the floating controls and to the right of the dock.

Required:

- no extra toolbars;
- no top tabs;
- no status bar unless required by macOS/WebKit behavior;
- no persistent developer or debug UI.

## 7. Scaling

All UI dimensions must scale proportionally.

Required:

- layout works across supported macOS window sizes;
- controls preserve spacing relationships from the reference;
- text does not overlap controls;
- controls do not resize unpredictably on hover or state changes.

## 8. Iconography

Required:

- SF Symbols for system-style icons;
- consistent stroke weight;
- compact recognizable icons;
- no custom icon set unless a required SF Symbol does not exist.

## 9. Interaction

Required:

- Back navigates active tab backward;
- Forward navigates active tab forward;
- Reload reloads active tab;
- address field loads typed URLs or search input according to settings once search support exists;
- menu buttons open compact native menus.

Hover, active, disabled, and focused states must be implemented.

## 10. Acceptance Criteria

The UI is acceptable only when:

- a screenshot visually matches the reference composition;
- the left dock matches placement, size, and glass behavior;
- top controls are floating and separated;
- no top tab strip exists;
- no extra sidebar exists;
- WebKit content is visible and usable;
- window resizing preserves proportions.

