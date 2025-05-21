# 🚀 AutoGitFlow Context Menu Script

Tired of typing the same Git commands over and over? **AutoGitFlow** brings Git automation to your fingertips—right from the Windows Explorer context menu.

---

## ✨ Features

- Adds **"AutoGitFlow"** to the right-click menu for folders and their backgrounds.
- **Smart Git Detection:**
  - Detects existing repositories.
  - If missing, offers to **Initialize** or **Clone** a repository via GUI.
- **Automates Git Workflow:**
  - Shows status and recent commits.
  - Detects uncommitted/unpushed changes.
  - Pulls remote changes (with confirmation).
  - Stages changes (`git add .`).
  - Prompts for commit message (GUI dialog with default).
  - Commits and optionally pushes to `origin`.
- GUI dialogs and message boxes built using WPF for a native Windows feel.

---

## 🧰 Prerequisites

- Windows 10 or newer
- Built-in PowerShell

---

## ⚙️ Installation

1. Choose the registry file:
   - `AutoGitFlow_admin.reg` (Admin)
   - `AutoGitFlow_user.reg` (Non-admin)
2. Double-click the `.reg` file to add the context menu entry.

---

## ▶️ Usage

1. Open Windows File Explorer.
2. Right-click **on a folder** or its **background**.
3. Select **"AutoGitFlow"**.
4. Follow the interactive prompts.

---

## ❌ Uninstallation

Run the matching uninstall `.reg` file:
- `AutoGitFlow_admin_uninstall.reg`
- `AutoGitFlow_user_uninstall.reg`

---

## 📝 Notes

- The full PowerShell script is embedded in the registry `HKEY_LOCAL_MACHINE\Software\LongQT-sea\git_auto_workflow_script`
- The context menu icon depends on Git for Windows being installed at the default path.

---

Made with ☕ and frustration by someone who loves automation.
