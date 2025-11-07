# Complete Project Guide - Uncover Actions

Master reference for the entire Uncover Actions project. This guide ties together all documentation and explains the complete project structure.

## 📚 Documentation Map

### Level 1: Start Here
- **README.md** - Project overview and quick start
- **QUICK_START.md** - 5-minute setup guide

### Level 2: Learn the Basics
- **GETTING_STARTED.md** - Step-by-step setup and deployment
- **ACTION_FILES_GUIDE.md** - Overview of all 37+ action files

### Level 3: Understand the System
- **ARCHITECTURE.md** - System design and how everything works
- **VARIABLES_REFERENCE.md** - Complete reference for all parameters

### Level 4: Navigate and Reference
- **DOCUMENTATION_INDEX.md** - Find what you need
- **DOCUMENTATION_GUIDE.md** - How to use the documentation
- **DOCUMENTATION_SUMMARY.md** - What was documented

### Level 5: Deep Dive
- Individual action READMEs (`.github/actions/*/README.md`)
- Commented YAML files (action.yml, workflows, examples)

---

## 🎯 Quick Navigation by Task

### "I want to deploy my app in 5 minutes"
1. Read: QUICK_START.md
2. Add GitHub secrets
3. Create workflow
4. Push and deploy

### "I want to understand the complete system"
1. Read: README.md
2. Read: ARCHITECTURE.md
3. Read: ACTION_FILES_GUIDE.md
4. Study: Specific action READMEs

### "I need to look up a parameter"
1. Check: VARIABLES_REFERENCE.md
2. Or: ACTION_FILES_GUIDE.md
3. Or: Specific action README

### "I'm getting an error"
1. Check: GETTING_STARTED.md - Troubleshooting
2. Check: ARCHITECTURE.md - Troubleshooting
3. Check: Specific action README
4. Check: GitHub Actions logs

### "I want to add a new action"
1. Read: ARCHITECTURE.md - Adding New Actions
2. Study: Existing action patterns
3. Follow: Naming conventions
4. Add: Documentation

### "I want to find something specific"
1. Use: DOCUMENTATION_INDEX.md
2. Or: Use Ctrl+F to search
3. Or: Check ACTION_FILES_GUIDE.md

---

## 📁 Project Structure

```
uactions/
├── README.md                          # Project overview
├── QUICK_START.md                     # 5-minute setup
├── GETTING_STARTED.md                 # Step-by-step guide
├── ARCHITECTURE.md                    # System design
├── VARIABLES_REFERENCE.md             # Parameter reference
├── ACTION_FILES_GUIDE.md              # All action files
├── DOCUMENTATION_INDEX.md             # Navigation guide
├── DOCUMENTATION_GUIDE.md             # How to use docs
├── DOCUMENTATION_SUMMARY.md           # What was documented
├── COMPLETE_PROJECT_GUIDE.md          # This file
│
├── action.yml                         # Main aggregator (commented)
├── LICENSE
│
├── .github/
│   ├── workflows/
│   │   ├── auto-version.yml          # Auto-versioning (commented)
│   │   └── [other workflows]
│   │
│   ├── examples/
│   │   ├── deploy-django-app.yml     # Django example (commented)
│   │   ├── deploy-laravel-app.yml
│   │   ├── deploy-nextjs-app.yml
│   │   ├── deploy-react-app.yml
│   │   └── [docker-compose examples]
│   │
│   └── actions/                      # 37+ action files
│       ├── app/                      # Application deployment (8 actions)
│       ├── build/                    # Docker building (2 actions)
│       ├── podman/                   # Container operations (5 actions)
│       ├── infra/                    # Infrastructure (6+ actions)
│       ├── common/                   # Shared utilities (15+ actions)
│       └── version/                  # Versioning (3 actions)
│
└── .gitignore
```

---

## 🔑 Key Concepts

### 1. Aggregator Pattern

The main `action.yml` acts as a router:
- User calls: `uncoverthefuture-org/actions@v1.0.41`
- Provides: `subaction` parameter
- Routes to: Appropriate dispatcher
- Dispatcher calls: Specific action

**Why?** Single version tag for entire suite.

**Reference**: ARCHITECTURE.md - Design Philosophy

---

### 2. Six Action Categories

| Category | Purpose | Count | Examples |
|----------|---------|-------|----------|
| **app** | Application deployment | 8 | ssh-django-deploy, ssh-nextjs-deploy |
| **build** | Docker image building | 2 | build-and-push |
| **podman** | Container operations | 5 | remote-podman-exec, podman-run-service |
| **infra** | Infrastructure setup | 6+ | prepare-ubuntu-host |
| **common** | Shared utilities | 15+ | route-category, print-help |
| **version** | Semantic versioning | 3 | compute-next, update-tags |

**Reference**: ARCHITECTURE.md - Categories

---

### 3. Environment Auto-Detection

Git refs automatically map to environments:

```
main/master → production
staging → staging
develop → development
v1.2.3 (tag) → production
feature/* → development
```

**Override**: Provide `env_name` parameter

**Reference**: ARCHITECTURE.md - Environment Auto-Detection

---

### 4. Domain Derivation

Domains automatically computed from base domain:

```
base_domain: example.com
domain_prefix_prod: api
→ api.example.com (production)

domain_prefix_staging: api-staging
→ api-staging.example.com (staging)
```

**Override**: Provide `domain` parameter

**Reference**: ARCHITECTURE.md - Domain Derivation

---

### 5. Traefik Routing

Automatic HTTPS with Let's Encrypt:
- Containers labeled with Traefik rules
- Automatic certificate provisioning
- Reverse proxy configuration
- No manual vhost management

**Alternative**: Host port publishing if no domain

**Reference**: ARCHITECTURE.md - Traefik Routing

---

### 6. SSH Connection Modes

Three ways to connect:

| Mode | How | When |
|------|-----|------|
| **auto** | Try user, fallback to root | Default, recommended |
| **root** | Direct root connection | Root SSH enabled |
| **user** | Non-root with sudo | Passwordless sudo configured |

**Reference**: ARCHITECTURE.md - SSH Connection Modes

---

## 📊 Action Files Overview

### Primary User-Facing Actions (8)

1. **build-and-push** - Build and push Docker image
2. **ssh-django-deploy** - Deploy Django API
3. **ssh-django-api-deploy** - Deploy Django with Apache (deprecated)
4. **ssh-laravel-deploy** - Deploy Laravel app
5. **ssh-nextjs-deploy** - Deploy Next.js app
6. **ssh-react-deploy** - Deploy React app
7. **write-remote-env-file** - Write environment files
8. **prepare-ubuntu-host** - Prepare fresh server

### Infrastructure Actions (6+)

1. **prepare-ubuntu-host** - Full server setup
2. **apache-manage-vhost** - Apache vhost management (deprecated)
3. **certbot** - SSL certificate management
4. And more...

### Container Operations (5)

1. **remote-podman-exec** - Execute commands via SSH
2. **podman-login-pull** - Login and pull image
3. **podman-run-service** - Run long-lived service
4. **podman-stop-rm-container** - Stop and remove
5. And more...

### Internal Utilities (20+)

- Dispatchers (route to specific actions)
- Validators (check inputs)
- Normalizers (parse parameters)
- Helpers (print help, cleanup, etc.)

**Reference**: ACTION_FILES_GUIDE.md

---

## 🚀 Typical Deployment Flow

### Step 1: Build
```yaml
- uses: uncoverthefuture-org/actions@v1.0.41
  with:
    subaction: build-and-push
```
**What happens**:
- Builds Docker image
- Pushes to registry
- Detects environment from branch
- Returns: env_name, image_tag, deploy_enabled

### Step 2: Deploy
```yaml
- uses: uncoverthefuture-org/actions@v1.0.41
  with:
    subaction: ssh-django-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST }}",
        "ssh_key": "${{ secrets.SSH_KEY }}",
        "base_domain": "example.com"
      }
```
**What happens**:
- Connects via SSH
- Pulls image
- Runs migrations
- Starts container
- Configures Traefik

### Step 3: Verify
- Check GitHub Actions logs
- SSH into server and verify container
- Test domain in browser

**Reference**: GETTING_STARTED.md - Step 6

---

## 📝 Documentation by Topic

### Setup & Configuration
- GETTING_STARTED.md - Steps 1-3
- QUICK_START.md - 5-minute setup
- ACTION_FILES_GUIDE.md - prepare-ubuntu-host

### Deployment
- GETTING_STARTED.md - Step 3-6
- ACTION_FILES_GUIDE.md - Deployment actions
- Example workflows (commented)

### Parameters & Variables
- VARIABLES_REFERENCE.md - All parameters
- ACTION_FILES_GUIDE.md - Action-specific inputs
- Specific action READMEs

### Architecture & Design
- ARCHITECTURE.md - Complete system design
- DOCUMENTATION_GUIDE.md - Documentation structure
- Inline comments in action.yml

### Troubleshooting
- GETTING_STARTED.md - Troubleshooting section
- ARCHITECTURE.md - Troubleshooting section
- Specific action READMEs

---

## 🎓 Learning Paths

### Path 1: Quick Start (30 minutes)
1. QUICK_START.md (5 min)
2. Add GitHub secrets (5 min)
3. Create workflow (10 min)
4. Deploy (10 min)

### Path 2: Complete Setup (2 hours)
1. README.md (10 min)
2. GETTING_STARTED.md (30 min)
3. ACTION_FILES_GUIDE.md (20 min)
4. Deploy and verify (60 min)

### Path 3: Deep Understanding (4 hours)
1. ARCHITECTURE.md (45 min)
2. ACTION_FILES_GUIDE.md (30 min)
3. VARIABLES_REFERENCE.md (30 min)
4. Study specific action READMEs (60 min)
5. Explore inline comments (30 min)

### Path 4: Contributing (6+ hours)
1. Complete Path 3
2. Study multiple action implementations
3. Understand dispatcher pattern
4. Add new action following conventions
5. Add documentation

---

## 🔗 How Everything Connects

```
README.md (Overview)
    ↓
QUICK_START.md (5-min setup)
    ↓
GETTING_STARTED.md (Complete setup)
    ↓
ACTION_FILES_GUIDE.md (What actions exist)
    ↓
ARCHITECTURE.md (How it works)
    ↓
VARIABLES_REFERENCE.md (All parameters)
    ↓
Specific action READMEs (Deep dive)
    ↓
Inline comments in YAML (Code level)
```

---

## 💡 Pro Tips

### 1. Use Example Workflows
Copy `.github/examples/deploy-django-app.yml` and modify for your needs.

### 2. Check Inline Comments
YAML files have extensive comments explaining what each line does.

### 3. Search the Docs
Use Ctrl+F to search across documentation.

### 4. Reference Tables
VARIABLES_REFERENCE.md has organized tables for quick lookup.

### 5. Cross-References
Most docs link to related sections. Follow the links!

### 6. Action READMEs
Each action has its own README with specific documentation.

---

## 🎯 Success Checklist

After using this documentation, you should be able to:

- [ ] Explain what Uncover Actions does
- [ ] Set up a deployment server
- [ ] Create a GitHub workflow
- [ ] Deploy your first application
- [ ] Understand how actions are organized
- [ ] Find any parameter documentation
- [ ] Troubleshoot common issues
- [ ] Customize actions for your needs
- [ ] Add new actions or features
- [ ] Understand the complete system design

---

## 📞 Quick Reference

### Most Important Files
1. README.md - Start here
2. QUICK_START.md - 5-minute setup
3. GETTING_STARTED.md - Complete setup
4. ACTION_FILES_GUIDE.md - All actions
5. ARCHITECTURE.md - How it works

### Most Useful Sections
- GETTING_STARTED.md - Step 3 (Create Workflow)
- VARIABLES_REFERENCE.md - Deployment Inputs
- ARCHITECTURE.md - Execution Flow
- ACTION_FILES_GUIDE.md - Primary Actions

### Most Common Questions
- "How do I deploy?" → GETTING_STARTED.md
- "What parameters?" → VARIABLES_REFERENCE.md
- "How does it work?" → ARCHITECTURE.md
- "What actions exist?" → ACTION_FILES_GUIDE.md
- "What does this do?" → Inline comments in YAML

---

## 📊 Documentation Statistics

| Metric | Count |
|--------|-------|
| Documentation files | 10 |
| Total markdown lines | 7500+ |
| Commented YAML files | 3 |
| Total comment lines | 350+ |
| Code examples | 50+ |
| Variables documented | 100+ |
| Parameters documented | 30+ |
| Action files | 37+ |
| Sections | 120+ |
| Cross-references | 250+ |

---

## 🚀 Next Steps

1. **Start**: README.md
2. **Quick Setup**: QUICK_START.md
3. **Complete Setup**: GETTING_STARTED.md
4. **Explore**: ACTION_FILES_GUIDE.md
5. **Understand**: ARCHITECTURE.md
6. **Reference**: VARIABLES_REFERENCE.md
7. **Navigate**: DOCUMENTATION_INDEX.md
8. **Deploy**: Your first application!

---

## 📚 Additional Resources

- **GitHub Actions**: https://docs.github.com/en/actions
- **Podman**: https://podman.io/docs
- **Traefik**: https://doc.traefik.io/
- **Semantic Versioning**: https://semver.org/

---

**Documentation Version**: 1.0  
**Last Updated**: 2024  
**Compatible with**: Uncover Actions v1.0.41+

**Start here**: README.md → QUICK_START.md → Deploy!
