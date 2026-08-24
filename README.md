# Hogwarts-Legacy-VR-Body-IK-Profile
VR body system for Hogwarts Legacy using UEVR. Adds a fully visible first-person body with hand IK, finger animations, leg animation, body calibration, head-mounted camera, crouching support, automatic bone detection, and dedicated support for broomstick and creature mounts.

# Hogwarts Legacy VR — First Person Profile + VR Body

**First Person Profile V1.08c + VR Body**

An enhanced VR profile for **Hogwarts Legacy using UEVR**, built upon the original First Person Profile by **jbusfield, Pande4360, DJ, markmon and letmein**.

The project expands the original first-person VR experience with a fully integrated virtual body, hand IK, animated legs, equipment synchronization, mounted gameplay support, body calibration and several VR-specific improvements.

> **For Epic Games:** Delete `EOSSDK-Win64-Shipping.dll` from the game directory to fix controller input issues.

---

# Original First Person Profile

This project is based on the **First Person Profile V1.08c**, originally developed by:

**jbusfield · Pande4360 · DJ · markmon · letmein**

The original profile introduced:

- Full first-person 6DOF motion controls
- Optional visible hands
- Optional gesture-based spell casting using the Glyph System
- Improved wand handling
- Spatial audio improvements
- Reduced wand detachment issues
- Removal of the UE4SS dependency

## V1.08c

### letmein

- Added the spatial audio fix.
- Added code intended to reduce the frequency of wand detachments.

## V1.0b

### markmon

- Re-enabled perfect wand accuracy without requiring offsets.

## V1.08

- Removed the UE4SS dependency.
- Previous installations must be removed or renamed before installing this version.

---

# VR Body

The VR Body system extends the original profile by adding a complete virtual body to the first-person VR experience.

The body uses an independent copy of the player's character mesh, including clothing and other attached meshes. Two Bone IK systems control the arms so that the virtual hands follow the VR controllers.

Existing finger animations are also reused, allowing the virtual hands to respond naturally to trigger, grip and thumb inputs.

---

# Main Features

## 🧍 Full VR Body

- Full visible first-person body
- Independent body mesh
- VR hand IK
- Animated fingers
- Animated legs
- Body position calibration
- Body rotation calibration
- Optional arms-only mode
- Body/head alignment
- Physical crouching support

## ✋ VR Hands & IK

- Hand tracking through Two Bone IK
- Arms follow the VR controllers
- Finger animations for trigger, grip and thumb
- Integrated with the original hand animation system

## 🦵 Legs & Body Movement

The VR body can use the game's leg animations while keeping the upper body and VR-controlled hands independent.

This allows the legs to retain natural Hogwarts Legacy animations without allowing the game's animation system to override the VR hand and arm positioning.

Supports:

- Physical crouching
- In-game crouching
- Eye-height calibration
- Body height adjustment
- Body rotation

---

# ⭐ Equipment Synchronization

One of the major improvements in this version is **automatic VR body reconstruction when equipment changes**.

When the player changes clothing or equipment, Hogwarts Legacy can change the meshes attached to the character.

The VR Body system rebuilds the virtual body so that it continues to match the player's current appearance.

This prevents problems such as:

- Old clothing remaining on the VR body
- Newly equipped clothing not appearing
- Missing character meshes
- Incomplete body reconstruction
- The VR body becoming visually different from the actual character

The system is designed to avoid unnecessary reconstruction when the body is already correctly built.

This is especially important because the VR body is an independent copy of the game's character mesh.

## 🔄 Manual Body Rebuild

The **VR Body** menu also includes a manual rebuild option.

This can be useful when:

- Equipment does not update correctly
- The body becomes incomplete
- A game transition leaves the body in an incorrect state
- The player wants to force the body to synchronize again

---

# 👂 Right-Hand Ear Grab — Body Rebuild

A special recovery mechanism has been added.

### Grab your right ear with the right VR hand.

This action triggers a **complete VR body reconstruction**.

The shortcut provides a quick way to recover the body without restarting the game and can prevent or fix certain body-related bugs caused by unusual game-state transitions.

It is designed as an easy-to-remember recovery gesture that can be performed during gameplay.

---

# 👀 VR Camera

The project includes an optional camera attached to the head of the virtual body.

This helps maintain proper alignment between:

- Head
- Neck
- Body
- VR view

Additional camera options include:

- Eye-height adjustment
- Looking-down camera movement
- Configurable camera advancement
- Mount-specific camera behavior

The camera system also respects situations where the game temporarily disables VR camera offsets, such as the Field Guide and equipment screens.

---

# 🐎 Mount Support

The VR Body includes dedicated handling for mounted gameplay.

Supported scenarios include:

- Broomsticks
- Hippogriffs
- Graphorns
- Other creature mounts

The player's own character mesh is used for the VR body while the system adapts the body to the mount's position and animation.

Mounted gameplay includes:

- VR hand IK
- Body positioning
- Animated legs
- Headset-following torso
- Spine posture adjustments
- Mount-specific body orientation

---

# 🧍 Mounted Posture

Some creatures place the player in a heavily reclined position.

The VR Body includes additional controls for correcting this posture.

Available adjustments include:

- Spine straightening
- Lateral spine adjustment
- Fine spine rotation
- Torso following the headset
- Sensitivity
- Dead zone
- Rotation limits

These settings allow the virtual body to remain visually aligned with the player's real-world position while riding.

---

# 🎬 First Person Cutscenes

The profile includes support for **First Person Cinematics**, but this feature has an important limitation.

### Recommended setting: **OFF**

The profile's cinematic system was designed around third-person cinematics.

When a cinematic starts, the profile temporarily:

- Restores the game's original character mesh
- Hides the VR hands
- Disables body/head-following behavior
- Disables certain VR controls
- Handles the transition back to the VR body

If **First Person Cinematics** is enabled, this cinematic handling is bypassed and several problems can occur, including:

- The original character mesh remaining visible
- UI attachments becoming incorrectly positioned
- Body and camera synchronization problems
- Incorrect view state after the cinematic

### ⚠️ Important

**Do not toggle First Person Cinematics ON or OFF while a cutscene is already playing.**

Changing this setting during a cinematic can cause the profile to enter an incorrect state and may require restarting the game.

The recommended configuration is to leave **First Person Cinematics disabled**.

After a cinematic ends, the VR body can be rebuilt to restore the correct state.

---

# ⚠️ Known Performance Issue

There is currently an **unknown issue that may cause performance degradation** in some situations.

The exact cause has not yet been identified.

If you experience an unexpected performance drop after using the profile, restarting the game may restore normal performance.

This issue is currently under investigation.

---

# ⚙️ VR Body Configuration

The profile adds a dedicated **VR Body** configuration interface inside UEVR.

Available options include:

- Enable VR Body
- Use Body Hands
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

Advanced settings provide additional control over camera, body movement and mounted posture.

---

# 🛠️ Other Improvements

## UEVR Initialization

Updated the UEVR initialization process to work correctly with the newer version of `uevrlib`.

This restores proper initialization of the profile configuration and required game hooks.

## Updated uevrlib

The profile's library files were updated to a newer version of `uevrlib`, including the IK functionality required by the VR Body system.

## Locomotion Compatibility

Improved compatibility with UEVR's **Locomotion: Head** setting.

The profile no longer unnecessarily overrides the UEVR locomotion configuration when the profile itself is not controlling locomotion.

## Field Guide & Equipment Camera

The VR camera system was updated so that the camera correctly respects situations where the game temporarily disables VR camera offsets.

This prevents the body camera from interfering with screens such as:

- Field Guide map
- Equipment screen

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

### jbusfield

Foundational development of the original First Person Profile and its first-person VR framework.

### Pande4360

Core profile development, VR integration and continued improvements to the Hogwarts Legacy VR experience.

### DJ

Contributions to the original profile and VR gameplay integration.

### markmon

Restored **perfect wand accuracy without offsets**.

### letmein

Added the **spatial audio fix** and improvements intended to reduce wand detachments.

---

# 🤖 Development

The VR Body system was **built with extensive assistance from AI**.

AI was used throughout development for:

- Lua programming
- UEVR integration
- Code architecture
- Debugging
- Reverse engineering assistance
- Problem solving
- Iterative code improvements
- Documentation

The implementation was developed through an iterative process combining **AI-assisted development with real gameplay testing** in Hogwarts Legacy VR.

---

# ❤️ Acknowledgements

This project builds upon the work of the original **First Person Profile** contributors and the wider UEVR community.

Special thanks to:

**jbusfield · Pande4360 · DJ · markmon · letmein**

for creating the foundation and improvements that made this expanded VR Body project possible.
