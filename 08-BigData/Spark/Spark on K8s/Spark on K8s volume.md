# 1. Volume 存储

用户可以将以下类型的 K8s 卷挂载到 Driver 和 Executor Pod 中：

- **hostPath**：将宿主节点文件系统的文件或目录挂载到 Pod 中
- **emptyDir**：当 Pod 被调度到节点时创建的、初始为空的卷
- **nfs**：将已有的 NFS（网络文件系统）挂载到 Pod 中
- **persistentVolumeClaim**：将 PersistentVolume 挂载到 Pod 中

注：emptyDir 卷的存储介质（例如磁盘或 SSD）由承载 kubelet 根目录（通常为 /var/lib/kubelet）所在文件系统的介质决定。emptyDir 和 hostPath 卷可以使用的空间没有限制（emptyDir 可以设置 sizeLimit 字段限制大小），且容器与 Pod 之间没有隔离，参考：https://kubernetes.io/docs/concepts/storage/volumes/。

将上述任意类型的卷挂载到 Driver Pod 使用以下配置属性：

```shell
--conf spark.kubernetes.driver.volumes.[VolumeType].[VolumeName].mount.path=<mount path>
--conf spark.kubernetes.driver.volumes.[VolumeType].[VolumeName].mount.readOnly=<true|false>
--conf spark.kubernetes.driver.volumes.[VolumeType].[VolumeName].mount.subPath=<mount subPath>
```

其中 VolumeType 可以是 hostPath、emptyDir、nfs 或 persistentVolumeClaim 之一。VolumeName 是在 Pod 规范中 volumes 字段下使用的卷名称。每种支持的卷类型可能有其特定的配置选项，可以使用如下形式的配置属性来指定：

```shell
spark.kubernetes.driver.volumes.[VolumeType].[VolumeName].options.[OptionName]=<value>

# 例如，volume 名称为 images 的 nfs 的 server 和 path 可用如下属性指定：
spark.kubernetes.driver.volumes.nfs.images.options.server=example.com
spark.kubernetes.driver.volumes.nfs.images.options.path=/data

# 再例如，volume 名称为 checkpointpvc 的 persistentVolumeClaim 的 claim 名称可用如下属性指定：
spark.kubernetes.driver.volumes.persistentVolumeClaim.checkpointpvc.options.claimName=check-point-pvc-claim
```

将卷挂载到 Executor Pod 的配置属性前缀使用 spark.kubernetes.executor. 而不是 spark.kubernetes.driver.。例如，可以为每个 Executor 挂载一个按需动态创建的 PVC，这在启用动态分配（Dynamic Allocation）时很有用：

```shell
# 使用 OnDemand 作为 claim 名称，并用 storageClass 与 sizeLimit 等选项
spark.kubernetes.executor.volumes.persistentVolumeClaim.data.options.claimName=OnDemand
spark.kubernetes.executor.volumes.persistentVolumeClaim.data.options.storageClass=gp
spark.kubernetes.executor.volumes.persistentVolumeClaim.data.options.sizeLimit=500Gi
spark.kubernetes.executor.volumes.persistentVolumeClaim.data.mount.path=/data
spark.kubernetes.executor.volumes.persistentVolumeClaim.data.mount.readOnly=false
```

 

**基于 PVC 的 Executor Pod 分配**：由于磁盘是重要的资源类型之一，Spark Driver 通过一组配置提供了精细控制。例如，默认情况下，按需创建的 PVC 由 Executors 拥有，PVC 的生命周期与其所属的 Executor 紧密耦合。不过，可以通过以下选项让按需 PVC 由 Driver 拥有，并在 Spark 作业生命周期内被其他 Executors 重用，从而减少 PVC 创建/删除的开销：

```shell
spark.kubernetes.driver.ownPersistentVolumeClaim=true
spark.kubernetes.driver.reusePersistentVolumeClaim=true
```

另外，从 Spark 3.4 起，Spark Driver 支持基于 PVC 的 Executor 分配，这意味着 Spark 会统计作业可创建的 PVC 总数，并在 Driver 拥有的 PVC 达到最大数时暂停新 Executor 的创建。这有助于在 Executor 之间迁移现有 PVC 的过渡。

```shell
spark.kubernetes.driver.waitToReusePersistentVolumeClaim=true
```

 

# 2. 本地存储

**Spark 支持使用卷在 Shuffle 等操作期间做溢写（spill）。要将某个卷用作本地存储，该卷的名称应以 spark-local-dir- 开头**，例如：

```shell
--conf spark.kubernetes.driver.volumes.[VolumeType].spark-local-dir-[VolumeName].mount.path=<mount path>
--conf spark.kubernetes.driver.volumes.[VolumeType].spark-local-dir-[VolumeName].mount.readOnly=false
```

特别地，如果作业在 Executors 上需要大量的 Shuffle 和排序操作，你可以使用 persistent volume claim：

```shell
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-1.options.claimName=OnDemand
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-1.options.storageClass=gp
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-1.options.sizeLimit=500Gi
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-1.mount.path=/data
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-1.mount.readOnly=false
```

要通过内置的 KubernetesLocalDiskShuffleDataIO 插件启用 Shuffle 数据恢复功能，需要满足以下条件。你可能还希望同时启用 spark.kubernetes.driver.waitToReusePersistentVolumeClaim。

```shell
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-1.mount.path=/data/spark-x/executor-x
spark.shuffle.sort.io.plugin.class=org.apache.spark.shuffle.KubernetesLocalDiskShuffleDataIO
```

**如果没有将任何卷设置为本地存储，Spark 会使用临时的临时空间在 Shuffle 等操作期间做溢写。当使用 K8s 作为资源管理器时，Pod 会为 spark.local.dir 或环境变量 SPARK_LOCAL_DIRS 列表中的每个目录创建并挂载一个 emptyDir 卷。如果没有显式指定目录，则会创建一个默认目录并进行相应配置。**

emptyDir 卷使用 K8s 的 ephemeral storage 特性，并且不会在 Pod 生命周期之外持久化，也就是说**当 Pod 由于任何原因从节点移除时，emptyDir 卷中的数据将被永久删除**。与 emptyDir 不同，hostPath 卷的数据持久化在宿主机，但是使用 hostPath 卷会带来许多安全风险，应尽量避免使用，例如可以定义一个 local PersistentVolume，并改用该卷。参考：https://kubernetes.io/docs/concepts/storage/volumes/。

```shell
# 第一种：使用默认emptyDir类型，Shuffle配置多个盘
spark.local.dir=/data/shuffle,/data1/shuffle

# 第二种：使用hostPath类型，配置多个盘（Shuffle使用时，名称必须以“spark-local-dir-”开头）
spark.kubernetes.executor.volumes.hostPath.spark-local-dir-[VolumeName].mount.readOnly=false
spark.kubernetes.executor.volumes.hostPath.spark-local-dir-[VolumeName].mount.path=/data/shuffle
spark.kubernetes.executor.volumes.hostPath.spark-local-dir-[VolumeName].options.path=/data/shuffle

# 第三种：使用PVC类型，底层PV类型取决于K8s环境
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-[VolumeName].options.claimName=OnDemand;
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-[VolumeName].options.storageClass=tceinf-csi-loopdevice;
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-[VolumeName].options.sizeLimit=500Gi;
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-[VolumeName].mount.path=/data;
spark.kubernetes.executor.volumes.persistentVolumeClaim.spark-local-dir-[VolumeName].mount.readOnly=false
```

 

**使用内存作为本地存储**：emptyDir 卷默认使用节点的 backing 存储作为临时存储，这在某些计算环境中可能不合适。例如，如果你的节点无本地磁盘而使用网络挂载的远程存储，很多 Executors 对远程存储做 IO 可能会降低性能。

在这种情况下，你可能希望在配置中设置 `spark.kubernetes.local.dirs.tmpfs=true`，这将使 emptyDir 卷配置为 tmpfs（即基于内存的卷）。当这样配置时，Spark 的本地存储使用会计入 Pod 的内存使用，因此你可能需要通过增加 `spark.{driver,executor}.memoryOverheadFactor` 的值来提高内存请求，以适应该变化。

```shell
private[spark] class LocalDirsFeatureStep(
    conf: KubernetesConf,
    defaultLocalDir: String = s"/var/data/spark-${UUID.randomUUID}")
  extends KubernetesFeatureConfigStep {
  // 参数spark.kubernetes.local.dirs.tmpfs，默认为false
  // 如果为true，创建emptyDir卷的介质为内存，这可能会提升性能，但会计入Pod的内存限制，所以可能需要申请更多内存
  private val useLocalDirTmpFs = conf.get(KUBERNETES_LOCAL_DIRS_TMPFS)

  override def configurePod(pod: SparkPod): SparkPod = {
    var localDirs = randomize(pod.container.getVolumeMounts.asScala
      .filter(_.getName.startsWith("spark-local-dir-"))
      .map(_.getMountPath))
    var localDirVolumes: Seq[Volume] = Seq()
    var localDirVolumeMounts: Seq[VolumeMount] = Seq()

    // 如果设置了以“spark-local-dir-”开头的卷，则不会创建emptyDir卷
    if (localDirs.isEmpty) {
      // Pod会为spark.local.dir或环境变量SPARK_LOCAL_DIRS列表中的每个目录创建并挂载一个emptyDir卷
      // 若未设置spark.local.dir或SPARK_LOCAL_DIRS，则默认为：/var/data/spark-${UUID.randomUUID}
      val resolvedLocalDirs = Option(conf.sparkConf.getenv("SPARK_LOCAL_DIRS"))
        .orElse(conf.getOption("spark.local.dir"))
        .getOrElse(defaultLocalDir)
        .split(",")
      randomize(resolvedLocalDirs)
      localDirs = resolvedLocalDirs.toSeq
      localDirVolumes = resolvedLocalDirs
        .zipWithIndex
        .map { case (_, index) =>
          new VolumeBuilder()
            .withName(s"spark-local-dir-${index + 1}")
            // 卷类型为emptyDir，且卷的介质可设置为内存
            .withNewEmptyDir()
              .withMedium(if (useLocalDirTmpFs) "Memory" else null)
            .endEmptyDir()
            .build()
        }

      // ...
    }
    
    // ...
  }
}
```

 

# 3. 参考

1. [Running Spark on Kubernetes](https://spark.apache.org/docs/latest/running-on-kubernetes.html)
2. [K8s Volumes](https://kubernetes.io/docs/concepts/storage/volumes/)