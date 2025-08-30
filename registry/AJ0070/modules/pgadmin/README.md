---
display_name: "pgAdmin"
description: "A web-based interface for managing PostgreSQL databases in your Coder workspace."
icon: "../../../../.icons/pgadmin.svg"
maintainer_github: "AJ0070"
verified: false
tags: ["database", "postgres", "pgadmin", "web-ide"]
---

# pgAdmin

This module adds a pgAdmin app to your Coder workspace, providing a powerful web-based interface for managing PostgreSQL databases.

It can be served on a Coder subdomain for easy access, or on `localhost` if you prefer to use port-forwarding.

```tf
module "pgadmin" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/AJ0070/pgadmin/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```
