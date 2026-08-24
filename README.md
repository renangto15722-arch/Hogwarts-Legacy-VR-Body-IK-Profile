# Hogwarts-Legacy-VR-Body-IK-Profile
VR body system for Hogwarts Legacy using UEVR. Adds a fully visible first-person body with hand IK, finger animations, leg animation, body calibration, head-mounted camera, crouching support, automatic bone detection, and dedicated support for broomstick and creature mounts.

# Hogwarts Legacy VR — First Person Profile + VR Body

An enhanced VR profile for **Hogwarts Legacy using UEVR**, built upon the original First Person Profile by **jbusfield, Pande4360, DJ, markmon and letmein**.

This project expands the original VR experience with a full first-person body, animated hands and legs, improved equipment synchronization, mounted gameplay support, body calibration and several VR improvements.

> **For Epic Games:** Delete `EOSSDK-Win64-Shipping.dll` from the game directory to fix controller input issues.

---

# Original First Person Profile

This project is based on **First Person Profile V1.08c**, originally developed by:

**jbusfield · Pande4360 · DJ · markmon · letmein**

The original profile introduced:

- Full first-person 6DOF motion controls
- Optional visible hands
- Gesture-based spell casting using the Glyph System
- Improved wand handling
- Spatial audio improvements
- Reduced wand detachment issues
- Removal of the UE4SS dependency

## V1.08c

### letmein

- Added the spatial audio fix.
- Added improvements that may reduce wand detachments.

## V1.0b

### markmon

- Re-enabled perfect wand accuracy without offsets.

## V1.08

- Removed the UE4SS dependency.

---

# VR Body

The VR Body expands the original profile by adding a complete virtual body to the first-person VR experience.

## Features

### 🧍 Full VR Body

- Full visible body in first person
- Visible arms and hands
- Animated fingers
- Animated legs
- Body height and position calibration
- Optional arms-only mode
- Physical crouching support

### ✋ VR Hands

Your virtual hands follow your VR controllers and include finger movements for actions such as gripping and using the trigger.

### 🦵 Legs

The body can display natural leg movement while keeping the VR hands and upper body properly controlled.

---

# ⭐ Equipment Synchronization

One of the main improvements in this version is **automatic VR body reconstruction when your equipment changes**.

When you change clothing or other equipment, the VR body is rebuilt to match your character's current appearance.

This helps prevent:

- Old clothing remaining on the VR body
- New equipment not appearing
- Missing body parts
- The VR body becoming out of sync with your character

The system also avoids unnecessary rebuilds when the body is already correctly synchronized.

## 🔄 Manual Body Rebuild

A **Rebuild Body** option is available in the VR Body menu.

You can use it if:

- Equipment does not update correctly
- The body becomes incomplete
- A game transition leaves the body in an incorrect state
- You simply want to force the body to synchronize again

---

# 👂 Right-Hand Ear Grab

A special recovery gesture is available:

### Grab your right ear with your right VR hand.

This triggers a **VR body rebuild**.

It provides a quick way to recover from certain body-related issues without restarting the game and can help prevent or fix bugs caused by unusual game transitions.

---

# 👀 VR Camera

The VR Body includes an optional camera system that keeps your view aligned with the virtual body.

Available options include:

- Eye height
- Looking down
- Camera positioning
- Body/head alignment

Additional camera controls are available under **Advanced Settings**.

---

# 🐎 Mount Support

The VR Body supports mounted gameplay, including:

- Broomsticks
- Hippogriffs
- Graphorns
- Other creature mounts

The body adapts to the player's position and posture while riding.

Mounted gameplay includes:

- VR hands
- Body positioning
- Animated legs
- Head following
- Spine and posture adjustments

Additional mount and posture controls are available under **Advanced Settings**.

---

# 🎬 First Person Cinematics

**First Person Cinematics works correctly with the profile.**

You can enable or disable the option normally when you are not in a cutscene.

### ⚠️ Important

**Do not turn First Person Cinematics ON or OFF while a cutscene is currently playing.**

Changing the setting during an active cutscene can cause the profile to enter an incorrect state and may lead to visual or camera issues.

For the best experience, choose your preferred setting **before or after** the cutscene instead of changing it while the cutscene is running.

---

# ⚠️ Known Performance Issue

There is currently an **unknown issue that may cause a loss of performance in some situations**.

The exact cause has not yet been identified.

If you experience an unexpected performance drop, restarting the game may restore normal performance.

This issue is still under investigation.

---

# ⚙️ VR Body Settings

The **VR Body** menu contains the main settings needed to configure the body.

These include:

- Enable/Disable VR Body
- Body Hands
- Arms Only
- Arm Height
- Eye Height
- Leg Animation
- Crouching
- Camera Settings
- Body Rotation
- Head Following
- Mount Settings
- Rebuild Body
- Restore Defaults

## 🔄 Restore Default Settings

If you want to restore the original settings, the **VR Body** menu includes a **Restore Defaults** button.

This button restores the default values included with the mod, allowing you to quickly return to the original recommended configuration without manually changing each setting.

## Advanced Settings

Some more advanced options are hidden under **Advanced Settings** to keep the main menu simple.

These include additional controls for:

- Camera behavior
- Body movement
- Leg behavior
- Mount posture
- Spine adjustments
- Other fine-tuning options

For most users, the default settings should be sufficient.

---

# 📦 Installation

## Automated Installation

**UEVR Deluxe**

https://uevrdeluxe.org/

## Manual Installation

1. Download **UEVR Nightly 1096**:

https://github.com/praydog/UEVR-nightly/releases/tag/nightly-01096-d2927803471d65327a70fc306c36325cb8cae75b

2. Delete the contents of:

```text
AppData\Roaming\UnrealVRMod\HogwartsLegacy
```

3. Download and import the Hogwarts Legacy profile through UEVR.

4. For best results, inject the profile **after shader loading**.

5. Keep **Camera Relative Targeting** enabled in the game settings.

6. For the Epic Games version, delete:

```text
EOSSDK-Win64-Shipping.dll
```

from the Hogwarts Legacy game directory if controller input is not working.

---

# 👥 Credits

## Original First Person Profile

**jbusfield · Pande4360 · DJ · markmon · letmein**

### Contributions

- **jbusfield, Pande4360 & DJ** — Original First Person Profile and VR improvements
- **markmon** — Perfect wand accuracy without offsets
- **letmein** — Spatial audio fix and wand detachment improvements

---

# 🤖 Development

The VR Body system was **developed with extensive assistance from AI**.

AI was used throughout development for:

- Programming
- Debugging
- Problem solving
- UEVR integration
- Code improvements
- Documentation

The project was developed through an iterative process combining **AI-assisted development with real gameplay testing** in Hogwarts Legacy VR.

---

# ❤️ Acknowledgements

This project builds upon the work of the original **First Person Profile** contributors and the wider UEVR community.

Special thanks to:

**jbusfield · Pande4360 · DJ · markmon · letmein**

for creating the foundation and improvements that made this expanded VR Body project possible.
