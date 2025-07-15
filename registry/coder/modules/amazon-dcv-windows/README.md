---
display_name: Amazon DCV Windows
description: Amazon DCV Server and Web Client for Windows
icon: ../../../../.icons/dcv.svg
verified: true
tags: [windows, amazon, dcv, web, desktop]
---

# Amazon DCV Windows

Amazon DCV is high performance remote display protocol that provides a secure way to deliver remote desktop and application streaming from any cloud or data center to any device, over varying network conditions.

![Amazon DCV on a Windows workspace](../../.images/amazon-dcv-windows.png)

Enable DCV Server and Web Client on Windows workspaces.

```tf
module "dcv" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/amazon-dcv-windows/coder"
  version  = "1.1.1"
  agent_id = resource.coder_agent.main.id
}

resource "coder_metadata" "dcv" {
  count       = data.coder_workspace.me.start_count
  resource_id = aws_instance.dev.id # id of the instance resource

  item {
    key   = "DCV client instructions"
    value = "Run `coder port-forward ${data.coder_workspace.me.name} -p ${module.dcv[count.index].port}` and connect to **localhost:${module.dcv[count.index].port}${module.dcv[count.index].web_url_path}**"
  }
  item {
    key   = "username"
    value = module.dcv[count.index].username
  }
  item {
    key       = "password"
    value     = module.dcv[count.index].password
    sensitive = true
  }
}
```

## License

Amazon DCV is free to use on AWS EC2 instances but requires a license for other cloud providers. Please see the instructions [here](https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-license.html#setting-up-license-ec2) for more information.
