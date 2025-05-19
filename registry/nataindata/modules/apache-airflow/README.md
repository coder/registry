---
display_name: airflow
description: A module that adds Apache Airflow in your Coder template
icon: ../../../../.icons/airflow.svg
maintainer_github: nataindata
verified: true
tags: [airflow, ide, web]
---

# airflow

A module that adds Apache Airflow in your Coder template.

```tf
module "airflow" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/nataindata/apache-airflow/coder"
  version  = "1.0.14"
  agent_id = coder_agent.main.id
}
```

![Airflow](../../.images/airflow.png)
