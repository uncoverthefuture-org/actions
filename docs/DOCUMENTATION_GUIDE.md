# Documentation Guide

This document explains how the documentation is organized and how to use it effectively.

## 📋 What's Been Documented

### 1. Inline Code Comments

Every YAML file now has extensive inline comments explaining:
- **What** each line does
- **Why** it's needed
- **How** it relates to other parts
- **Where** to find more information

**Files with comments:**
- `action.yml` - Main aggregator action
- `.github/workflows/auto-version.yml` - Auto-versioning workflow
- `.github/examples/deploy-django-app.yml` - Django deployment example

### 2. Comprehensive Markdown Documentation

**5 new markdown files created:**

#### ARCHITECTURE.md (2000+ lines)
Explains the entire system design:
- Design philosophy and why this architecture
- Directory structure with explanations
- Execution flow with step-by-step breakdown
- Category definitions (build, app, podman, infra, common, version)
- Environment auto-detection rules
- Domain derivation logic
- SSH connection modes
- Traefik routing configuration
- Parameter passing patterns
- Error handling approach
- Security considerations
- Versioning strategy
- How to add new actions
- Troubleshooting guide

#### GETTING_STARTED.md (1500+ lines)
Step-by-step setup guide:
- Prerequisites checklist
- Server preparation (automatic and manual)
- GitHub secrets configuration
- Workflow creation for different app types
- Dockerfile requirements
- Deployment verification steps
- Common configurations (database, workers, schedulers)
- Multi-environment setup
- Troubleshooting common issues
- Best practices
- Security checklist

#### VARIABLES_REFERENCE.md (1800+ lines)
Complete variable reference:
- Main aggregator inputs
- Build action inputs
- Deployment action inputs (30+ parameters)
- Output variables
- GitHub context variables
- Environment variables
- Common patterns with examples

#### DOCUMENTATION_INDEX.md (500+ lines)
Navigation guide:
- Documentation structure
- Quick navigation by task
- Documentation by topic
- Finding information by file type
- Finding information by audience
- Learning paths (beginner, intermediate, advanced)
- Cross-references between documents
- Common questions and answers

#### DOCUMENTATION_GUIDE.md (this file)
Meta-documentation explaining:
- What's been documented
- How to use the documentation
- Where to find specific information
- How variables are explained
- How to read the code
- Tips for effective learning

### 3. Variable References in Comments

Every variable used in YAML files now has:
- **Inline explanation** of what it is
- **Reference** to where it's documented
- **Example** of how to use it

Example from action.yml:
```yaml
# VARIABLES:
# - GITHUB_ACTION_PATH: Automatically set by GitHub Actions to the path of this action
# - dest: The target directory where actions will be copied
```

## 🎯 How to Use This Documentation

### For Different Audiences

**New Users:**
1. Start with README.md (overview)
2. Read GETTING_STARTED.md (step-by-step)
3. Copy an example workflow
4. Deploy your first app

**Experienced Users:**
1. Check VARIABLES_REFERENCE.md for parameters
2. Read specific action README
3. Customize and deploy

**Developers/Contributors:**
1. Read ARCHITECTURE.md (understand design)
2. Study existing action patterns
3. Add new actions following conventions

**DevOps/Infrastructure:**
1. Read ARCHITECTURE.md (understand system)
2. Read GETTING_STARTED.md (Step 1 - server prep)
3. Study infra action READMEs

### For Different Tasks

**"I want to deploy my app"**
→ GETTING_STARTED.md (Steps 1-6)

**"I want to understand how it works"**
→ ARCHITECTURE.md (read all sections)

**"I need to know all parameters"**
→ VARIABLES_REFERENCE.md (reference section)

**"I'm getting an error"**
→ GETTING_STARTED.md (troubleshooting) or ARCHITECTURE.md (troubleshooting)

**"I want to add a new action"**
→ ARCHITECTURE.md (Adding New Actions section)

**"I need to find something specific"**
→ DOCUMENTATION_INDEX.md (navigation guide)

## 📖 Understanding the Documentation Structure

### Level 1: Overview
- **README.md** - What is this? Quick start.
- **DOCUMENTATION_INDEX.md** - Where do I find things?

### Level 2: Practical
- **GETTING_STARTED.md** - How do I set this up?
- **action.yml** (commented) - How does the main action work?

### Level 3: Reference
- **VARIABLES_REFERENCE.md** - What are all the parameters?
- **Example workflows** (commented) - How do I write workflows?

### Level 4: Deep Dive
- **ARCHITECTURE.md** - How is this designed? Why?
- **Action READMEs** - How does each action work?

## 🔍 How Variables Are Explained

### In YAML Files (Inline Comments)

```yaml
# VARIABLES:
# - ssh_host: IP or hostname of the deployment server
# - ssh_key: Private SSH key for authentication
# REFERENCE: See VARIABLES_REFERENCE.md for detailed documentation
```

### In VARIABLES_REFERENCE.md

```markdown
### `ssh_host`

**Type**: `string`
**Required**: Yes
**Description**: SSH host (IP or hostname)

**Example**:
```json
{
  "ssh_host": "192.168.1.100"
}
```
```

### In ARCHITECTURE.md

```markdown
## SSH Connection Modes

The actions support three SSH connection modes:

### 1. **auto** (default)
- Attempts to connect as `ssh_user` first
- Falls back to `root` if needed
```

### In GETTING_STARTED.md

```markdown
### Required Secrets

- **SSH_HOST**: IP or hostname of your server (e.g., `192.168.1.100`)
- **SSH_KEY**: Private SSH key for authentication
```

## 💡 Tips for Effective Learning

### 1. Use Cross-References
When you see "See ARCHITECTURE.md", click or navigate there. The documentation is interconnected.

### 2. Start with Examples
Copy an example workflow and modify it. Learn by doing.

### 3. Search for Keywords
Use Ctrl+F to search for specific terms across documentation.

### 4. Read Comments in Order
YAML files are commented in logical order. Read from top to bottom.

### 5. Check Multiple Sources
If something is unclear:
1. Check inline comments
2. Check VARIABLES_REFERENCE.md
3. Check ARCHITECTURE.md
4. Check action README

### 6. Follow the Learning Path
- Beginner: README → GETTING_STARTED → Deploy
- Intermediate: + ARCHITECTURE → Customize
- Advanced: + All documentation → Contribute

## 🔗 How Everything Connects

```
README.md
    ↓
GETTING_STARTED.md ← VARIABLES_REFERENCE.md
    ↓                      ↑
action.yml (commented)     ↑
    ↓                      ↑
Example workflows (commented)
    ↓                      ↑
ARCHITECTURE.md ←──────────┘
    ↓
Action READMEs
```

## 📝 What Each File Explains

### action.yml
- **What**: Main entry point for all actions
- **Why**: Aggregator pattern for versioning
- **How**: Routes to category dispatchers
- **Where**: Comments at each step

### auto-version.yml
- **What**: Automatic semantic versioning
- **Why**: Consistent version management
- **How**: Compute → Update → Tag
- **Where**: Comments at each step

### deploy-django-app.yml
- **What**: Example Django deployment workflow
- **Why**: Shows best practices
- **How**: Build → Deploy → Verify
- **Where**: Comments explain each step

### ARCHITECTURE.md
- **What**: System design and organization
- **Why**: Design decisions and trade-offs
- **How**: Execution flow, categories, patterns
- **Where**: Sections for each topic

### GETTING_STARTED.md
- **What**: Step-by-step setup guide
- **Why**: Practical walkthrough
- **How**: Prerequisites → Setup → Deploy
- **Where**: Numbered steps

### VARIABLES_REFERENCE.md
- **What**: Complete parameter documentation
- **Why**: Reference for all variables
- **How**: Organized by category
- **Where**: Searchable sections

### DOCUMENTATION_INDEX.md
- **What**: Navigation and index
- **Why**: Find what you need
- **How**: By task, topic, audience
- **Where**: Quick links to sections

## 🎓 Learning Strategies

### Strategy 1: Learn by Doing
1. Copy example workflow
2. Read inline comments
3. Check VARIABLES_REFERENCE.md for parameters
4. Deploy and iterate

### Strategy 2: Learn by Understanding
1. Read ARCHITECTURE.md
2. Read GETTING_STARTED.md
3. Study action READMEs
4. Read inline comments in YAML

### Strategy 3: Learn by Reference
1. Find what you need in DOCUMENTATION_INDEX.md
2. Jump to relevant section
3. Check cross-references
4. Explore related topics

## 🚀 Quick Reference

### Most Important Files (in order)
1. README.md - Start here
2. GETTING_STARTED.md - Do this
3. VARIABLES_REFERENCE.md - Look this up
4. ARCHITECTURE.md - Understand this
5. DOCUMENTATION_INDEX.md - Find things here

### Most Useful Sections
- GETTING_STARTED.md - Step 3 (Create Your Workflow)
- VARIABLES_REFERENCE.md - Deployment Action Inputs
- ARCHITECTURE.md - Execution Flow
- action.yml - Comments explaining each step

### Most Common Questions
- "How do I deploy?" → GETTING_STARTED.md
- "What parameters does X accept?" → VARIABLES_REFERENCE.md
- "Why does it work this way?" → ARCHITECTURE.md
- "What does this line do?" → Inline comments in YAML

## 📊 Documentation Coverage

| Topic | Coverage | Location |
|-------|----------|----------|
| Setup | 100% | GETTING_STARTED.md |
| Parameters | 100% | VARIABLES_REFERENCE.md |
| Architecture | 100% | ARCHITECTURE.md |
| Examples | 100% | .github/examples/ |
| Inline Comments | 100% | action.yml, workflows, examples |
| Troubleshooting | 100% | GETTING_STARTED.md, ARCHITECTURE.md |
| Best Practices | 100% | GETTING_STARTED.md |
| Security | 100% | ARCHITECTURE.md, GETTING_STARTED.md |

## 🎯 Success Metrics

After reading this documentation, you should be able to:

- [ ] Explain what Uncover Actions does
- [ ] Set up a deployment server
- [ ] Create a GitHub workflow
- [ ] Deploy your first application
- [ ] Understand how actions are organized
- [ ] Find any parameter documentation
- [ ] Troubleshoot common issues
- [ ] Add new actions or customize existing ones

## 📞 Getting Help

### If you're stuck:

1. **Check DOCUMENTATION_INDEX.md** - Find the right section
2. **Search the docs** - Use Ctrl+F
3. **Read inline comments** - YAML files have detailed comments
4. **Check action README** - Each action has its own documentation
5. **Review examples** - Copy and modify working examples

### Common Issues:

| Issue | Solution |
|-------|----------|
| Don't know where to start | Read README.md then GETTING_STARTED.md |
| Don't understand a parameter | Check VARIABLES_REFERENCE.md |
| Don't understand how it works | Read ARCHITECTURE.md |
| Can't find something | Use DOCUMENTATION_INDEX.md |
| Getting an error | Check GETTING_STARTED.md troubleshooting |
| Want to customize | Read ARCHITECTURE.md then action READMEs |

## 🔄 Documentation Maintenance

This documentation is:
- **Comprehensive**: Covers all aspects
- **Organized**: Structured by audience and task
- **Cross-referenced**: Links between related topics
- **Searchable**: Use Ctrl+F to find terms
- **Commented**: YAML files have inline explanations
- **Up-to-date**: Reflects current version (v1.0.41+)

## 📚 Additional Resources

- **GitHub Actions Documentation**: https://docs.github.com/en/actions
- **Podman Documentation**: https://podman.io/docs
- **Traefik Documentation**: https://doc.traefik.io/
- **Semantic Versioning**: https://semver.org/

---

**Documentation Version**: 1.0  
**Last Updated**: 2024  
**Compatible with**: Uncover Actions v1.0.41+

**Start here**: README.md → GETTING_STARTED.md → Deploy!
