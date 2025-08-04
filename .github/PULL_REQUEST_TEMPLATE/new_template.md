---
name: 📋 New Template
about: Add a new template to the registry
---

Closes #

## Description

<!-- Briefly describe what this template provides and which use case it solves -->

## Template Information

**Path:** `registry/[namespace]/templates/[template-name]`  
**Platform:** <!-- e.g., Docker, AWS, GCP, Kubernetes, etc. -->  
**Target audience:** <!-- e.g., Web developers, Data scientists, etc. -->

## Infrastructure Details

<!-- Describe the infrastructure this template creates -->

**Resources created:**
- Resource type 1
- Resource type 2

**Estimated costs:** $X.XX/month (or "Free" for local resources)

**Prerequisites:**
- Prerequisite 1
- Prerequisite 2

## Testing & Validation

- [ ] Template tested with Coder (`coder templates push test-template -d .`)
- [ ] Infrastructure provisions successfully
- [ ] Agent connects and workspace functions correctly
- [ ] All registry modules work as expected
- [ ] Documentation is complete and accurate

## Checklist

- [ ] `main.tf` - Complete Terraform configuration
- [ ] `README.md` - Documentation with proper frontmatter
- [ ] Namespace avatar added (if new namespace)
- [ ] Icon path is correct
- [ ] Tags are descriptive and relevant
- [ ] Infrastructure requirements documented
- [ ] Variables table is complete
- [ ] Troubleshooting section included

## Registry Modules Used

<!-- List any registry modules included in this template -->

- [ ] `coder/code-server` - VS Code in browser
- [ ] `coder/git-config` - Git configuration
- [ ] Other modules: 

## Related Issues

<!-- Link related issues or write "None" if not applicable -->
