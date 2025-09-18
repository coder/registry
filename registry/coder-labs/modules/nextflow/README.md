---
display_name: Nextflow
description: A module that adds Nextflow to your Coder template.
icon: ../../../../.icons/nextflow.svg
verified: true
tags: [nextflow, workflow, hpc, bioinformatics]
---

# Nextflow

A module that adds Nextflow to your Coder template.

![Nextflow](../../.images/nextflow.png)

```tf
module "nextflow" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/nextflow/coder"
  version  = "0.9.0"
  agent_id = coder_agent.example.id
}
```
