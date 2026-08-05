# 🧙‍♂️ Git-Wizard Ultimate (V1.1 Release)

> **The Ultimate Cross-Platform CLI Suite for Frictionless Git & GitHub Workflows.**  
> *Designed for absolute beginners and seasoned DevOps/DevSecOps engineers alike.*

---

## 🌟 Overview

**Git-Wizard Ultimate** transforms standard, error-prone Git operations into an intuitive, guided, and automated terminal experience. From generating ED25519 SSH keys and resolving push conflicts in 1-click to interactive arrow-key branch selection, working directory reset utilities, and full-color terminal PNG/ASCII rendering, **Git-Wizard Ultimate** handles the heavy lifting so developers can focus purely on building software.

---

## 🎨 Terminal Aesthetic & Branding

Git-Wizard Ultimate automatically renders high-density GitHub branding and celebration graphics right inside your terminal!

### 📌 Custom High-Density Octocat ASCII Header
```text
                                            @@@@@@@@@@@@                                            
                                      @@@@@@@@@@@@@@@@@@@@@@@@@                                     
                                 @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                 
                              @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                              
                           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                           
                         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                         
                       @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                       
                      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                      
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                   @@@@@@@@@@@      @@@@@@@@@@@@@@@@@@@@@@@@@@@@      @@@@@@@@@@@                   
                  @@@@@@@@@@@          @@@@@@          @@@@@@          @@@@@@@@@@@                  
                 @@@@@@@@@@@@                                          @@@@@@@@@@@@                 
                @@@@@@@@@@@@@                                          @@@@@@@@@@@@@                
               @@@@@@@@@@@@@@                                          @@@@@@@@@@@@@@               
              @@@@@@@@@@@@@@@@                                        @@@@@@@@@@@@@@@@              
              @@@@@@@@@@@@@@                                            @@@@@@@@@@@@@@              
              @@@@@@@@@@@@@                                              @@@@@@@@@@@@@              
             @@@@@@@@@@@@@@                                               @@@@@@@@@@@@@             
             @@@@@@@@@@@@@                                                @@@@@@@@@@@@@             
             @@@@@@@@@@@@@                                                @@@@@@@@@@@@@             
             @@@@@@@@@@@@@                                                @@@@@@@@@@@@@             
             @@@@@@@@@@@@@                                                @@@@@@@@@@@@@             
             @@@@@@@@@@@@@                                                @@@@@@@@@@@@@             
             @@@@@@@@@@@@@@                                              @@@@@@@@@@@@@@             
             @@@@@@@@@@@@@@                                              @@@@@@@@@@@@@@             
              @@@@@@@@@@@@@@                                            @@@@@@@@@@@@@@              
              @@@@@@@@@@@@@@@                                          @@@@@@@@@@@@@@@              
              @@@@@@@@@@@@@@@@@                                      @@@@@@@@@@@@@@@@@              
               @@@@@@@@@@@@@@@@@@                                  @@@@@@@@@@@@@@@@@@               
                @@@@@@@   @@@@@@@@@@                            @@@@@@@@@@@@@@@@@@@@                
                @@@@@@@@     @@@@@@@@@@`~~~~~~~~`              @@@@@@@@@@@@@@@@@@@@@@@                
====================================================================
         🧙‍♂️ GIT-WIZARD ULTIMATE - GITHUB WORKFLOW ENGINE           
====================================================================

```

### 🎉 "Everything Up-To-Date" Celebration Banner

When your working directory is clean or your code is fully pushed to GitHub, Git-Wizard rewards you with a custom celebration graphic:

```text
          ,~-.
         (   ' )-.          ,~'`-.
      ,~' `   ' ) )        _(    _) )
     ( ( .--.===.--.    (   `    ' )
      `.%%.;::|888.#`.   `-'`~~=~'
      /%%/::::|8888\##\
     |%%/:::::|88888\##|
     |%%|:::::|88888|##|.,-.
     \%%|:::::|88888|##/    )_
      \%\:::::|88888/#/ ( `'   )
       \%\::::|8888/#/(  ,  -'`-.
   ,~-. `%\:::|888/#'(  (      ') )
  (   ) )_ `\__|__/'    `~-~=--~~='
 ( ` ')  ) [VVVVV]
(_(_.~~~'   \|_|/   hjw
            [XXX]
            `"""'

Everything up-to-date! Code is safe and synced on GitHub!

```

---

## 🚀 Key Capabilities Matrix

### 🔐 1. Identity, SSH & Remote URL Manager

* => **Global Config Manager:** Inspect and set `user.name` and `user.email` globally.
* => **Automated SSH Key Generator:** Auto-generates high-security **ED25519** SSH keypairs and displays the public key formatted for GitHub Settings.
* => **SSH Handshake Tester:** Performs direct authentication testing against `git@github.com`.
* => **Remote Repository URL Manager:** Inspect live remotes (`git remote -v`), overwrite/update remote targets with auto-sanitization (strips extra pasted command prefixes), and seamlessly convert between HTTPS and SSH protocols.

### 📦 2. Repository Setup, Status & Reset Engine

* => **1-Click Complete Setup:** Initializes repository, creates `main` branch, stages untracked files, prompts for commit messages, attaches remotes with guidance, and pushes upstream—all in one action.
* => **Working Directory Status Inspector:** Provides clean, pager-free output of staged, modified, and untracked files (`git status`).
* => **Interactive Git Reset & Undo Utility:** Allows developers to:
* Unstage all files (`git reset HEAD`).
* Discard all local uncommitted changes (`git checkout -- .`).
* Perform a **Soft Rollback** (Undo last commit while keeping staged work).
* Perform a **Hard Rollback** (Wipe last commit and local changes).


* => **Smart Conflict Push Resolver:** Automatically resolves rejected push attempts (`! [rejected] main -> main`) with 1-click **Rebase**, **Merge**, or **Force Push** strategy prompts.
* => **Tailored `.gitignore` Generator:** Interactively generates pre-configured `.gitignore` templates for Python, Node.js, Go, Docker, and .NET projects.

### 🌿 3. Advanced Interactive Branch Manager

* => **Pager-Free Branch Inspection:** Bypasses restrictive `less`/`q` terminal pagers so branch lists display directly on screen.
* => **Arrow-Key Branch Selector:** Switch local branches or purge feature branches using **Up/Down Arrow Keys** + **ENTER**—zero manual typing required!
* => **Dual Branch Purge:** Deletes feature branches locally **and** removes tracking branches from GitHub simultaneously with built-in safety safeguards.

### ✍️ 4. Conventional Commit Assistant

* => Standardizes commit formatting following industry guidelines (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`) with optional scope tags to keep repository logs clean and professional.

---

## 📁 Repository Structure

```text
Git_Wizard_Ultimate/
├── autorun.sh                     # Linux/macOS Master Launcher & chafa Auto-Installer
├── autorun.bat                    # Windows Master Launcher
├── README.md                      # Comprehensive Project Guide
├── assets/
│   └── octocat.png                # High-Res GitHub Terminal Logo
├── linux/
│   └── git-wizard.sh              # Master Linux CLI Orchestrator Engine
└── modules/
    ├── git-wizard.ps1             # Master Windows PowerShell Orchestrator
    ├── identity-engine.ps1        # Module 1: Identity & Remote URL Manager
    ├── repo-engine.ps1            # Module 2: Repo Setup, Status & Reset Engine
    ├── branch-engine.ps1          # Module 3: Advanced Interactive Branch Engine
    └── commit-engine.ps1          # Module 4: Conventional Commit Assistant

```

---

## 🛠️ Installation & Usage

### 🐧 On Linux / macOS (Ubuntu, Debian, Kali Linux, Fedora, CentOS, Arch)

1. Clone the repository:
```bash
git clone [https://github.com/ali4210/Git_Wizard_Ultimate.git](https://github.com/ali4210/Git_Wizard_Ultimate.git)
cd Git_Wizard_Ultimate

```


2. Make the launcher executable and run:
```bash
chmod +x autorun.sh
./autorun.sh

```



> *Note: On first launch, `autorun.sh` will prompt to auto-install `chafa` via your system's package manager to render full-color high-resolution PNG images in your terminal.*

---

### 🪟 On Windows 10 / 11

1. Clone or download the repository into your preferred workspace folder.
2. Open the `Git_Wizard_Ultimate` folder in File Explorer.
3. Double-click **`autorun.bat`**.

*(The batch launcher automatically bypasses PowerShell ExecutionPolicy and loads all engine modules seamlessly.)*

---

## 🤝 Contributing

Contributions, feature requests, and bug reports are welcome! Feel free to open an Issue or submit a Pull Request to make **Git-Wizard Ultimate** even better for developers worldwide.

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for details.

```

---
