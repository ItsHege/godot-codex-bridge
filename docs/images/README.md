# Godot Codex Bridge - Media Asset Guidelines & Capture Plan

This directory stores authentic media assets (screenshots, diagrams, and visual verification artifacts) for project documentation and repository showcase.

## Capture Philosophy
- **Authentic Only:** Do not generate synthetic mockups, AI illustrations, or marketing composites. Every image must be captured directly from a real Godot 4 Editor session with the Godot Codex Bridge addon active.
- **Dark Theme:** Standard Godot 4 Editor dark theme.
- **Privacy First:** Never show personal home folders or absolute machine paths, private tokens/emails, or non-game desktop windows.

---

## Detailed Asset Capture Specifications

### 1. `01_editor_codex_dock.png`
- **Purpose:** Showcase the main Godot 4 Editor with the "Codex Tools" dock integrated natively into the right inspector area.
- **What Must Be Visible:**
  - Active Godot 4 editor main window with a 3D scene open (e.g. `minimal_3d_project`).
  - The "Codex Tools" dock panel visible and connected (showing heartbeat status and node tree).
  - Clean Godot 3D viewport displaying test meshes and lighting.
- **What Must NOT Be Visible:**
  - Absolute OS paths or user home folders; status bars should show clean `res://` paths.
  - Non-Godot window chrome or desktop background.
- **Recommended Dimensions:** 1920x1080 or 1600x900 (16:9 full editor view).
- **Prerequisites / Credit Requirement:** **0 credits required.** Can be captured locally by opening `godot-codex-bridge/examples/minimal_3d_project/project.godot` with the plugin enabled.

---

### 2. `02_chat_controls_dock.png`
- **Purpose:** Demonstrate the responsive in-editor conversational interface ("Codex Chat") docked alongside the scene, showing turn interaction, model selection, reasoning toggle, and diff review.
- **What Must Be Visible:**
  - Docked Codex Chat panel with transcript feed, input field, and action chips.
  - Model selection dropdown and connection status indicator.
  - A sample turn showing agent discussion of a Godot node or scene diff card.
- **What Must NOT Be Visible:**
  - Real API keys, account emails, billing or balance numbers, internal traceback noise.
- **Recommended Dimensions:** 800x1000 (focused panel crop) or 1200x800 (dock + viewport).
- **Prerequisites / Credit Requirement:** **0 credits required.** Can be captured using the local mock host runtime (`npm run host:dev` or `validate_visible_chat_editor.ps1 -Runtime mock`), or optionally with a live turn.

---

### 3. `03_bridge_permissions.png`
- **Purpose:** Illustrate the explicit security and permission architecture of the bridge (read-first philosophy, explicit toggles for live mutations, diff review, and screenshot capture).
- **What Must Be Visible:**
  - The "Bridge" / "Settings & Permissions" tab inside the editor dock.
  - Granular permission switches: Allow Screenshots, Allow Live Scene Mutation, Require Diff Approval Token, Native UndoRedo Integration, and RPC Port configuration.
- **What Must NOT Be Visible:**
  - Internal system secrets, raw port collision errors, personal directory paths.
- **Recommended Dimensions:** 700x900 (focused dock crop) or 1000x800.
- **Prerequisites / Credit Requirement:** **0 credits required.** Fully static addon UI tab in Godot Editor.

---

### 4. `04_eye_attach_annotation.png`
- **Purpose:** Showcase the signature "Eye Attach" visual grounding capability, where the user draws a bounding box over a 3D object in the viewport and attaches it directly as visual context to the prompt.
- **What Must Be Visible:**
  - 3D viewport with an interactive rectangular region overlay drawn around a 3D mesh.
  - The "Eye Attach" visual chip attached to the chat prompt input bar.
- **What Must NOT Be Visible:**
  - OS desktop background, unverified fallback screen captures, non-game editor popups.
- **Recommended Dimensions:** 1600x900 or 1280x720 (split viewport + dock).
- **Prerequisites / Credit Requirement:** **0 credits required.** The Eye Attach overlay and screenshot capture run purely locally inside the Godot addon via GDScript.

---

### 5. `05_multiview_verification.png`
- **Purpose:** Showcase automated multi-camera visual evidence capture (Front, Top, Side, Perspective orthographic/perspective render grid) used by Codex to evaluate spatial alignment and detect floating meshes.
- **What Must Be Visible:**
  - 4-quadrant composite render showing Front, Side, Top, and Perspective views of the active 3D scene with bounding box markers.
- **What Must NOT Be Visible:**
  - Temporary test harness timestamps, raw binary dumps, or messy error logs.
- **Recommended Dimensions:** 1200x800 or 1600x900 (4-quadrant layout).
- **Prerequisites / Credit Requirement:** **0 credits required.** Generated locally via the multi-view capture engine (`scripts/validate_multi_view_capture.ps1`).

---

## Summary of Capture Readiness

All 5 core screenshots can be captured **100% locally with 0 API credits** using the included minimal 3D test project and local mock daemon.
