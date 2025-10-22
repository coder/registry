---
display_name: "NFS K8s Deployment"
description: "Mount an NFS share to a Coder K8s workspace"
icon: "../../../../.icons/folder.svg"
verified: false
tags: ["kubernetes", "shared-dir", "nfs"]
---

# NFS K8s Deployment

This template provisions a Coder workspace as a Kubernetes Deployment, with an NFS share mounted
as a volume. The NFS share will synchronize the server-side files onto the client (Coder workspace)
When you stop the Coder workspace and rebuild, the NFS share will be re-mounted, and the changes persisted.

Note the `volume` and `volume_mount` blocks in the deployment and container spec,
respectively:

```terraform
resource "kubernetes_deployment" "main" {
  spec {
    template {
      spec {
        container {
          volume_mount {
            mount_path = data.coder_parameter.nfs_mount_path.value # mount path in the container
            name       = "nfs-share"
          }
        }
        volume {
          name = "nfs-share"
          nfs {
            path   = data.coder_parameter.nfs_mount_path.value # path to be exported from the server
            server = data.coder_parameter.nfs_server.value     # server IP address
          }
        }
      }
    }
  }
}
```

## server-side configuration

1. Create an NFS mount on the server for the clients to access:

   ```console
   export NFS_MNT_PATH=/mnt/nfs_share
   # Create directory to shaare
   sudo mkdir -p $NFS_MNT_PATH
   # Assign UID & GIDs access
   sudo chown -R uid:gid $NFS_MNT_PATH
   sudo chmod 777 $NFS_MNT_PATH
   ```

1. Grant access to the client by updating the `/etc/exports` file, which
   controls the directories shared with remote clients. See
   [Red Hat's docs for more information about the configuration options](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/5/html/deployment_guide/s1-nfs-server-config-exports).

   ```console
   # Provides read/write access to clients accessing the NFS from any IP address.
   /mnt/nfs_share  *(rw,sync,no_subtree_check)
   ```

1. Export the NFS file share directory. You must do this every time you change
   `/etc/exports`.

   ```console
   sudo exportfs -a
   sudo systemctl restart <nfs-package>
   ```
