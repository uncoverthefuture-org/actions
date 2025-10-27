# Documentation Index

Welcome to Uncover Actions! This guide helps you navigate the documentation and find what you need.

## 📚 Documentation Structure

### For First-Time Users

Start here if you're new to Uncover Actions:

1. **[README.md](README.md)** - Overview and quick start
   - What Uncover Actions does
   - Available actions at a glance
   - Quick example

2. **[GETTING_STARTED.md](GETTING_STARTED.md)** - Step-by-step setup guide
   - Prerequisites
   - Server preparation
   - GitHub secrets configuration
   - Creating your first workflow
   - Troubleshooting common issues

### For Understanding How It Works

Dive deeper into the architecture:

3. **[ARCHITECTURE.md](ARCHITECTURE.md)** - Design and architecture
   - Why this design?
   - Directory structure
   - Execution flow with diagrams
   - Category definitions
   - Environment auto-detection
   - Domain derivation
   - SSH connection modes
   - Traefik routing
   - Error handling
   - Security considerations

### For Reference

Look up specific details:

4. **[VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md)** - Complete variable reference
   - All input parameters
   - All output variables
   - GitHub context variables
   - Environment variables
   - Common patterns

### For Specific Actions

Each action has its own README:

- `.github/actions/app/ssh-django-deploy/README.md` - Django deployment
- `.github/actions/app/ssh-laravel-deploy/README.md` - Laravel deployment
- `.github/actions/app/ssh-nextjs-deploy/README.md` - Next.js deployment
- `.github/actions/app/ssh-react-deploy/README.md` - React deployment
- `.github/actions/build/build-and-push/README.md` - Docker image building
- `.github/actions/infra/prepare-ubuntu-host/README.md` - Host preparation
- And more...

### For Examples

Real-world workflow examples:

- `.github/examples/deploy-django-app.yml` - Django CI/CD workflow
- `.github/examples/deploy-laravel-app.yml` - Laravel CI/CD workflow
- `.github/examples/deploy-nextjs-app.yml` - Next.js CI/CD workflow
- `.github/examples/deploy-react-app.yml` - React CI/CD workflow

## 🎯 Quick Navigation by Task

### "I want to deploy my Django API"

1. Read: [GETTING_STARTED.md](GETTING_STARTED.md) - Step 1-3
2. Copy: `.github/examples/deploy-django-app.yml`
3. Reference: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - Deployment Action Inputs
4. Details: `.github/actions/app/ssh-django-deploy/README.md`

### "I want to deploy my Next.js app"

1. Read: [GETTING_STARTED.md](GETTING_STARTED.md) - Step 1-3
2. Copy: `.github/examples/deploy-nextjs-app.yml`
3. Reference: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - Deployment Action Inputs
4. Details: `.github/actions/app/ssh-nextjs-deploy/README.md`

### "I want to understand how actions are organized"

1. Read: [ARCHITECTURE.md](ARCHITECTURE.md) - Directory Structure section
2. Read: [ARCHITECTURE.md](ARCHITECTURE.md) - Categories section
3. Reference: [README.md](README.md) - Available Actions tables

### "I want to know all available parameters"

1. Reference: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md)
2. Details: Specific action's README

### "I'm getting an error"

1. Check: [GETTING_STARTED.md](GETTING_STARTED.md) - Troubleshooting section
2. Check: [ARCHITECTURE.md](ARCHITECTURE.md) - Troubleshooting section
3. Check: Specific action's README - Troubleshooting section
4. Check: GitHub Actions workflow logs

### "I want to add a new action"

1. Read: [ARCHITECTURE.md](ARCHITECTURE.md) - Adding New Actions section
2. Reference: Existing action READMEs for patterns
3. Reference: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - Common patterns

## 📖 Documentation by Topic

### Setup & Configuration

- **Initial Setup**: [GETTING_STARTED.md](GETTING_STARTED.md) - Steps 1-3
- **Server Preparation**: [GETTING_STARTED.md](GETTING_STARTED.md) - Step 1
- **GitHub Secrets**: [GETTING_STARTED.md](GETTING_STARTED.md) - Step 2
- **Workflow Creation**: [GETTING_STARTED.md](GETTING_STARTED.md) - Step 3

### Deployment

- **Django**: [GETTING_STARTED.md](GETTING_STARTED.md) - Step 3 (Django API)
- **Next.js/React**: [GETTING_STARTED.md](GETTING_STARTED.md) - Step 3 (Next.js / React)
- **Laravel**: [GETTING_STARTED.md](GETTING_STARTED.md) - Step 3 (Laravel)
- **With Database**: [GETTING_STARTED.md](GETTING_STARTED.md) - Common Configurations
- **With Workers**: [GETTING_STARTED.md](GETTING_STARTED.md) - Common Configurations
- **Multiple Environments**: [GETTING_STARTED.md](GETTING_STARTED.md) - Common Configurations

### Architecture & Design

- **Overview**: [ARCHITECTURE.md](ARCHITECTURE.md) - Overview section
- **Design Philosophy**: [ARCHITECTURE.md](ARCHITECTURE.md) - Design Philosophy section
- **Directory Structure**: [ARCHITECTURE.md](ARCHITECTURE.md) - Directory Structure section
- **Execution Flow**: [ARCHITECTURE.md](ARCHITECTURE.md) - Execution Flow section
- **Categories**: [ARCHITECTURE.md](ARCHITECTURE.md) - Categories section
- **Environment Auto-Detection**: [ARCHITECTURE.md](ARCHITECTURE.md) - Environment Auto-Detection section
- **Domain Derivation**: [ARCHITECTURE.md](ARCHITECTURE.md) - Domain Derivation section
- **SSH Connection Modes**: [ARCHITECTURE.md](ARCHITECTURE.md) - SSH Connection Modes section
- **Traefik Routing**: [ARCHITECTURE.md](ARCHITECTURE.md) - Traefik Routing section

### Variables & Parameters

- **Main Aggregator**: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - Main Aggregator Inputs
- **Build Action**: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - Build Action Inputs
- **Deployment Action**: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - Deployment Action Inputs
- **Outputs**: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - Output Variables
- **GitHub Context**: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - GitHub Context Variables
- **Environment Variables**: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - Environment Variables

### Troubleshooting

- **General Troubleshooting**: [GETTING_STARTED.md](GETTING_STARTED.md) - Troubleshooting section
- **Architecture Troubleshooting**: [ARCHITECTURE.md](ARCHITECTURE.md) - Troubleshooting section
- **Action-Specific**: Check specific action's README

## 🔍 Finding Information

### By File Type

**YAML Files** (Workflows and Actions):
- Main aggregator: `action.yml` - Heavily commented
- Example workflows: `.github/examples/*.yml` - Heavily commented
- Auto-versioning: `.github/workflows/auto-version.yml` - Heavily commented
- Individual actions: `.github/actions/*/action.yml` - See action READMEs

**Markdown Files** (Documentation):
- `README.md` - Overview
- `ARCHITECTURE.md` - Design and architecture
- `GETTING_STARTED.md` - Setup guide
- `VARIABLES_REFERENCE.md` - Variable reference
- `DOCUMENTATION_INDEX.md` - This file
- `.github/actions/*/README.md` - Action-specific docs

### By Audience

**For Developers Using Actions**:
1. [README.md](README.md)
2. [GETTING_STARTED.md](GETTING_STARTED.md)
3. [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md)
4. Specific action README

**For DevOps/Infrastructure**:
1. [ARCHITECTURE.md](ARCHITECTURE.md)
2. [GETTING_STARTED.md](GETTING_STARTED.md) - Step 1
3. `.github/actions/infra/*/README.md`

**For Contributors/Maintainers**:
1. [ARCHITECTURE.md](ARCHITECTURE.md)
2. [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md)
3. Existing action READMEs (for patterns)
4. [ARCHITECTURE.md](ARCHITECTURE.md) - Adding New Actions section

## 📝 How to Read the Code

### Commented Files

The following files have extensive inline comments explaining what each line does:

1. **action.yml** - Main aggregator
   - Comments explain inputs, outputs, and execution flow
   - References to ARCHITECTURE.md and VARIABLES_REFERENCE.md

2. **.github/workflows/auto-version.yml** - Auto-versioning workflow
   - Comments explain each step and why it's needed
   - References to ARCHITECTURE.md

3. **.github/examples/deploy-django-app.yml** - Django deployment example
   - Comments explain each step and configuration options
   - References to GETTING_STARTED.md and VARIABLES_REFERENCE.md

### Understanding Variables

When you see a variable like `${{ steps.build.outputs.env_name }}`:

1. `steps.build` - Refers to a step with `id: build`
2. `.outputs` - Accesses the step's outputs
3. `.env_name` - The specific output variable

**Find it in**: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - Output Variables section

### Understanding Inputs

When you see an input like `ssh_host`:

1. Look in: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md)
2. Find the section: "Deployment Action Inputs"
3. Look for: `ssh_host`
4. See: Type, Required, Default, Description, Example

## 🎓 Learning Path

### Beginner

1. Read: [README.md](README.md) (5 min)
2. Read: [GETTING_STARTED.md](GETTING_STARTED.md) (15 min)
3. Copy: Example workflow (5 min)
4. Deploy: Follow the guide (30 min)

**Total**: ~1 hour to first deployment

### Intermediate

1. Read: [ARCHITECTURE.md](ARCHITECTURE.md) (20 min)
2. Reference: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) (10 min)
3. Read: Specific action README (10 min)
4. Customize: Your workflow (15 min)

**Total**: ~1 hour to customized deployment

### Advanced

1. Study: [ARCHITECTURE.md](ARCHITECTURE.md) - All sections (30 min)
2. Study: Multiple action READMEs (30 min)
3. Reference: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - All sections (20 min)
4. Contribute: Add new action or feature (varies)

**Total**: ~2 hours to deep understanding

## 🔗 Cross-References

### From action.yml

- See ARCHITECTURE.md for: Execution flow, categories, design philosophy
- See VARIABLES_REFERENCE.md for: Input/output definitions
- See GETTING_STARTED.md for: Setup instructions

### From ARCHITECTURE.md

- See VARIABLES_REFERENCE.md for: Detailed parameter descriptions
- See GETTING_STARTED.md for: Practical setup steps
- See action READMEs for: Specific action details

### From GETTING_STARTED.md

- See VARIABLES_REFERENCE.md for: All available parameters
- See ARCHITECTURE.md for: Understanding how it works
- See action READMEs for: Specific action documentation

### From VARIABLES_REFERENCE.md

- See ARCHITECTURE.md for: Context and design
- See GETTING_STARTED.md for: Practical examples
- See action READMEs for: Action-specific parameters

## 📞 Getting Help

### If you can't find what you need:

1. **Check the index**: This file (DOCUMENTATION_INDEX.md)
2. **Search the docs**: Use Ctrl+F to search
3. **Check action README**: Each action has detailed documentation
4. **Check GitHub issues**: Search for similar problems
5. **Check workflow logs**: GitHub Actions provides detailed logs

### Common Questions

**Q: How do I set up my first deployment?**
A: See [GETTING_STARTED.md](GETTING_STARTED.md)

**Q: What parameters does ssh-django-deploy accept?**
A: See [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md) - Deployment Action Inputs

**Q: How does environment auto-detection work?**
A: See [ARCHITECTURE.md](ARCHITECTURE.md) - Environment Auto-Detection section

**Q: Why do I need to prepare and restore bundled actions?**
A: See [ARCHITECTURE.md](ARCHITECTURE.md) - Execution Flow section

**Q: How do I add a new action?**
A: See [ARCHITECTURE.md](ARCHITECTURE.md) - Adding New Actions section

## 📊 Documentation Statistics

- **Total Documentation Files**: 5 markdown files
- **Total Commented YAML Files**: 3 files
- **Total Lines of Documentation**: 2000+
- **Total Code Examples**: 50+
- **Total Variables Documented**: 100+

## 🎯 Next Steps

1. **Start Here**: [README.md](README.md)
2. **Then Setup**: [GETTING_STARTED.md](GETTING_STARTED.md)
3. **Then Deploy**: Use example workflow
4. **Then Learn**: [ARCHITECTURE.md](ARCHITECTURE.md)
5. **Then Reference**: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md)

---

**Last Updated**: 2024
**Documentation Version**: 1.0
**Compatible with**: Uncover Actions v1.0.41+
