# 🧙‍♂️ Git-Wizard Ultimate (V1.0 Release)

An automated, cross-platform CLI utility suite designed to make Git and GitHub workflows effortless for both complete beginners and professional DevOps engineers.

---

## 🚀 Key Features

### 🔐 1. Identity & SSH Connection Hub
- **Config Manager:** Quickly set or inspect global `user.name` and `user.email`.
- **SSH Key Generator:** Auto-generates modern **ED25519** SSH keys and prints public keys formatted for GitHub.
- **Connection Tester:** Tests SSH handshake directly against `git@github.com`.
- **Remote Protocol Switcher:** Toggle remote URLs between HTTPS and SSH on the fly.

### 📦 2. Repository Setup & Smart Conflict Push Engine
- **1-Click Repository Setup:** Initializes repository, creates standard `main` branch, stages files, crafts initial commit, attaches remotes, and pushes in a single step.
- **Smart Conflict Push Resolver:** Automatically resolves rejected pushes (`! [rejected] main -> main`) with 1-click **Rebase**, **Merge**, or **Force Push** choices.
- **Tailored `.gitignore` Generator:** Automatically creates template `.gitignore` files for Python, Node.js, Go, Docker, and .NET.

### 🌿 3. Advanced Branch & Remote Manager
- **Branch Matrix:** Displays colorized local and remote branch tracking status.
- **Publish & Track:** Creates new branches and publishes them upstream with tracking (`-u origin`) automatically.
- **Dual Branch Purge:** Deletes feature branches locally **and** purges them from GitHub simultaneously with safety safeguards.

### ✍️ 4. Conventional Commit Assistant
- Standardizes commit messages using standard classifications (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`) to maintain clean, professional git logs.

---

## 📁 Repository Structure

```text
Git_Wizard_Ultimate/
├── autorun.sh                     # Universal Master Launcher (Linux/macOS)
├── autorun.bat                    # Universal Master Launcher (Windows)
├── README.md                      # Project Documentation
├── linux/
│   └── git-wizard.sh              # Linux Master Engine
└── modules/
    ├── git-wizard.ps1             # Windows Master PowerShell Entry
    ├── identity-engine.ps1        # Module 1: Identity & SSH Manager
    ├── repo-engine.ps1            # Module 2: Repo Setup & Conflict Push
    ├── branch-engine.ps1          # Module 3: Advanced Branch Manager
    └── commit-engine.ps1          # Module 4: Conventional Commit Assistant
```


## 🛠️ Usage Instructions

🐧 On Linux / macOS
```Bash
chmod +x autorun.sh
./autorun.sh
```
## 🪟 On Windows
Double-click autorun.bat in Windows File Explorer.

## 📄 License
This project is open-source under the MIT License.


---

==>> NEXT STEPS

You now have a complete, production-ready, modular cross-platform codebase for **Git-Wizard Ultimate V1.0**! 

Test it on both your Linux terminal (`./autorun.sh`) and Windows machine (`autorun.bat`), commit it to your GitHub repository, and let me know if you want to add any extra features!