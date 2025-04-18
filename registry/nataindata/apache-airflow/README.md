---
display_name: airflow
description: A module that adds Apache Airflow in your Coder template
icon: ../../../../.icons/airflow.svg
maintainer_github: nataindata
partner_github: coder
verified: true
tags: [airflow, idea, web, helper]
---

# airflow

A module that adds Apache Airflow in your Coder template.

```tf
module "airflow" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/apache-airflow/coder"
  version  = "1.0.13"
  agent_id = coder_agent.main.id
}
```

![Airflow](../../.images/airflow.png)
