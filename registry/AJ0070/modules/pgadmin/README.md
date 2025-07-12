---
display_name: pgAdmin
description: A module to add pgAdmin to your Coder workspace for easy access to PostgreSQL databases.
icon: ../../../../.icons/postgres.svg
maintainer_github: AJ0070
verified: false
tags: [helper, database, postgres, pgadmin]
---

# pgAdmin

This module adds a pgAdmin app to your Coder workspace, providing a web-based interface for managing PostgreSQL databases.

```tf
module "pgadmin" {
  count    = data.coder_workspace.me.start_count
  source   = "[registry.coder.com/AJ0070/pgadmin/coder](https://registry.coder.com/AJ0070/pgadmin/coder)"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```
