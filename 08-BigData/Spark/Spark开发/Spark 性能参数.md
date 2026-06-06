参数以 spark 3.4.2 为例，不同版本可能略有差异，表中加粗参数需要重要关注。

# 1. 内存 & CPU

| **参数名**                    | **默认值**                                                   | **说明**                                                     | **调优建议**                                                 |
| :---------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| **spark.driver.memory**       | 1g                                                           | Driver 进程的堆内存大小，命令行使用 --driver-memory。**运行 Driver 的容器的最大内存为 spark.driver.memoryOverhead 和 spark.driver.memory 的总和**。 | 当使用 collect 等算子将数据收集到 Driver 端，需要加大内存，否则容易造成 OOM。通常与 spark.driver.cores 保持 1:4 设置，或设置 1G - 4G 较为合适。 |
| spark.driver.memoryOverhead   | driverMemory * spark.driver.memoryOverheadFactor，最小 384m  | Driver 进程的非堆内存大小，非堆内存包括：堆外内存（spark.memory.offHeap.enabled=true 时）、其他 Driver 进程（如与 PySpark Driver 一起运行的 python 进程）使用的内存以及在同一容器中运行的其他非 Driver 进程使用的内存。注意，spark.driver.memoryOverheadFactor 默认值为 0.10。 | 建议保持默认值。                                             |
| **spark.executor.memory**     | 1g                                                           | Executor 进程的堆内存大小，命令行使用 --executor-memory。**运行 Executor 的容器的最大内存大小为 spark.executor.memory、spark.executor.memoryOverhead、spark.memory.offHeap.size 和 spark.executor.pyspark.memory 的总和**。 | num-executors * executor-memory < Yarn 资源队列最大内存，若与其他用户共享 Yarn 资源队列，则最好不要超过资源队列的 1/3 - 1/2。通常与 spark.executor.cores 保持 1:4 设置，或设置 4G - 8G 较为合适。 |
| spark.executor.memoryOverhead | executorMemory * spark.executor.memoryOverheadFactor，最小 384m | 为每个 Executor 分配的额外内存量，额外内存包括 PySpark Executor 内存（当未配置 spark.executor.pyspark.memory 时）和在同一容器中运行的其他非 Executor 进程使用的内存。注意，spark.executor.memoryOverheadFactor 默认值为 0.10。 | 建议保持默认值。                                             |
| spark.memory.offHeap.enabled  | false                                                        | 如果为 true，Spark 将尝试在某些操作中使用堆外内存。如果启用了堆外内存，则 spark.memory.offHeap.size 必须为正值。 | 建议保持默认值。                                             |
| spark.memory.offHeap.size     | 0                                                            | 堆外内存大小。                                               |                                                              |
| **spark.driver.cores**        | 1                                                            | Driver 进程使用的内核数，仅在 Cluster 模式下使用，命令行使用 --driver-cores。 | 建议保持默认值。                                             |
| **spark.executor.cores**      | 1（Yarn 模式）                                               | Executor 进程使用的内核数，命令行使用 --executor-cores。     | num-executors * executor-cores < Yarn 资源队列最大 vCores，若与其他用户共享 Yarn 资源队列，则最好不要超过资源队列的 1/3 - 1/2。通常设置 2 - 5 个较为合适。 |
| **spark.executor.instances**  | 2                                                            | 静态分配的 Executor 数量，命令行使用 --num-executors。       | 见 spark.executor.cores、spark.executor.memory 调优建议。    |
| spark.yarn.am.memory          | 512m                                                         | 在 Client 模式下，YARN Application Master 使用的内存量，单位使用小写后缀。在 Cluster 模式下，请使用 spark.driver.memory。 | 建议保持默认值。                                             |
| spark.yarn.am.memoryOverhead  | AM memory * 0.10，最小 384m                                  | 与 spark.driver.memoryOverhead 相同，但适用于 Client 模式下的 YARN Application Master。 | 建议保持默认值。                                             |

注 1：参数 spark.executor.memoryOverhead 与 spark.memory.offHeap.size 区别，在 Spark 2.4.0 之前，Executor 非堆内存 = spark.executor.memoryOverhead（如果指定了参数 spark.memory.offHeap.size，需要手动将其添加到 Yarn 的 memoryOverhead 中）；在 Spark 2.4.0 至 Spark 3.0.0 之前，Executor 非堆内存 = spark.executor.memoryOverhead（同前） + spark.executor.pyspark.memory；**自 Spark 3.0.0 开始，Executor 非堆内存 = spark.executor.memoryOverhead + spark.memory.offHeap.size + spark.executor.pyspark.memory**，具体可参考[说明](https://stackoverflow.com/questions/58666517/difference-between-spark-yarn-executor-memoryoverhead-and-spark-memory-offhea/61723456#61723456)。

注 2：参数 spark.driver.memory 与 spark.yarn.am.memory 区别，Yarn Cluster 模式，ApplicationMaster 在任意一台 NodeManager 上启动，此方式 ApplicationMaster 包含 Driver，AM 内存为：spark.driver.memory + spark.driver.memoryOverhead；Yarn Client 模式，Driver 在提交任务的节点启动，而 ApplicationMaster 在任意一台 NodeManager 上启动，此方式 Driver 和 AM 是分开的，AM 内存为：spark.yarn.am.memory + spark.yarn.am.memoryOverhead。

注 3：**Yarn UI 上显示的【Allocated Memory MB】包括 Container 的堆内和堆外内存，且受到参数 yarn.scheduler.minimum-allocation-mb（默认 1024M）、spark.dynamicAllocation.enabled（默认 false）影响**。例如，当设置 --conf spark.dynamicAllocation.enabled=false --conf spark.executor.instances=2 --conf spark.driver.memory=6G --conf spark.executor.memory=4G --conf spark.memory.offHeap.enabled=true --conf spark.memory.offHeap.size=2G  ，那么 Allocated Memory MB = 2 * ( 4 + 2 + ⌈4 * 0.1⌉ ) + ( 6 + ⌈6 * 0.1⌉ ) = 21G。



# 2. 动态分配

| **参数名**                                  | **默认值**                           | **说明**                                                     | **调优建议**                                                 |
| :------------------------------------------ | :----------------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| **spark.dynamicAllocation.enabled**         | false                                | 是否启用动态资源分配，动态资源分配可根据工作负载上下调整应用程序注册的 Executor 数量。更多详情，请参阅[说明](https://spark.apache.org/docs/3.4.2/job-scheduling.html#dynamic-resource-allocation)。这需要设置 spark.shuffle.service.enabled 或 spark.dynamicAllocation.shuffleTracking.enabled。 | 可让用户免于烦琐的 Executor 数目的预估和设置，增加业务运行的稳定性，提高集群资源的利用率，建议设置为 true。 |
| spark.shuffle.service.enabled               | false                                | 是否启用 ESS。该服务会保留 Executor 写入的 Shuffle 文件，这样就可以安全地移除 Executor，或者在 Executor 发生故障时继续进行 Shuffle。更多信息，请参阅[说明](https://spark.apache.org/docs/3.4.2/job-scheduling.html#configuration-and-setup)。 | 建议设置为 true。                                            |
| spark.dynamicAllocation.initialExecutors    | spark.dynamicAllocation.minExecutors | 如果启用动态分配，要运行 Executor 的初始数量。如果设置了 --num-executors（或 spark.executor.instances）且大于此值，则会将其用作初始 Executor 数量。 | 参数较小时，任务需要等待向 Yarn 申请资源，造成任务运行有较长的爬坡阶段；参数较大时，对于不需要那么多 Executor 的任务来说，会造成资源浪费。该参数值的选取可以根据历史任务 Executor 数目的统计，按照二八原则来设置，例如 80% 历史业务的 Executor 数目都不大于参数值。若无法确认历史任务的 Executor ，建议先设置为 1。 |
| spark.dynamicAllocation.minExecutors        | 0                                    | 如果启用动态分配，Executor 数量的下限。                      | 建议与 spark.dynamicAllocation.initialExecutors 保持一致。   |
| spark.dynamicAllocation.maxExecutors        | infinity（无穷大）                   | 如果启用动态分配，Executor 数量的上限。                      | 为了防止大业务独占资源，造成小任务没有资源的情况，需要将该参数值设置为一个合理值，如 200。 |
| spark.dynamicAllocation.executorIdleTimeout | 60s                                  | 如果启用动态分配，且某个 Executor 的空闲时间超过这一期限，则该 Executor 将被移除。 | 参数较小时，利于集群资源共享，但会影响业务执行时，在 Executor 被删除后，可能需要重新申请新的 Executor 来执行任务；参数较大时，不利于资源共享，若一些较大的任务占用资源，迟迟不释放，就会造成其他任务得不到资源。建议保持默认值。 |

 

# 3. 自适应查询 AQE

| **参数名**                                                  | **默认值**                           | **说明**                                                     | **调优建议**                                                 |
| :---------------------------------------------------------- | :----------------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| **spark.sql.adaptive.enabled**                              | true                                 | 是否启用 AQE，在查询执行过程中，根据准确的运行时统计数据重新优化查询计划。 | 建议保持默认值。                                             |
| **spark.sql.adaptive.advisoryPartitionSizeInBytes**         | 64 MB                                | 自适应优化期间 Shuffle 分区的建议大小，它在 Spark 合并小的 Shuffle 分区或拆分倾斜的 Shuffle 分区时生效。 |                                                              |
| spark.sql.adaptive.coalescePartitions.enabled               | true                                 | 当启用 AQE 且该值为 true 时，Spark 将根据目标大小（由 spark.sql.adaptive.advisoryPartitionSizeInBytes 指定）合并连续的 Shuffle 分区，以避免过多的小任务。 | 建议保持默认值。                                             |
| **spark.sql.adaptive.coalescePartitions.parallelismFirst**  | true                                 | 该值为 true 时，Spark 在合并 Shuffle 分区时会忽略 spark.sql.adaptive.advisoryPartitionSizeInBytes 指定的目标大小，而只尊重 spark.sql.adaptive.coalescePartitions.minPartitionSize 指定的最小分区大小，以最大化并行性。这是为了避免在启用 AQE 执行时出现性能下降。 | 官方建议将此配置设为 false，并遵守 spark.sql.adaptive.advisoryPartitionSizeInBytes 指定的目标分区大小。 |
| spark.sql.adaptive.coalescePartitions.minPartitionSize      | 1MB                                  | 合并后 Shuffle 分区的最小大小。其值最多为 spark.sql.adaptive.advisoryPartitionSizeInBytes 的 20%。当目标大小在分区合并过程中被忽略（默认情况）时，这个值就非常有用。 |                                                              |
| spark.sql.adaptive.coalescePartitions.initialPartitionNum   | spark.sql.shuffle.partitions         | 合并前的初始 Shuffle 分区数。只有同时启用 spark.sql.adaptive.enabled 和 spark.sql.adaptive.coalescePartitions.enabled 时，此配置才会生效。 | 建议保持默认值。                                             |
| spark.sql.adaptive.autoBroadcastJoinThreshold               | spark.sql.autoBroadcastJoinThreshold | 当任何 Join 方的运行时统计数据小于该值时，AQE 会将 Sort-Merge Join 连接转换为 Broadcast Hash Join。注意，此配置仅在 AQE 中使用。 | 建议保持默认值。                                             |
| spark.sql.adaptive.maxShuffledHashJoinLocalMapThreshold     | 0                                    | 如果该值不小于 spark.sql.adaptive.consultativePartitionSizeInBytes，且所有分区的大小都不大于该配置，则无论 spark.sql.join.preferSortMergeJoin 的值如何，AQE 会将 Sort-Merge Join 转换为 Shuffle Hash Join。 |                                                              |
| spark.sql.adaptive.skewJoin.enabled                         | true                                 | 当启用 AQE 且该值为 true 时，Spark 会通过拆分（必要时复制）倾斜分区来动态处理 Sort-Merge Join 中的倾斜。 | 建议保持默认值。                                             |
| spark.sql.adaptive.skewJoin.skewedPartitionThresholdInBytes | 256MB                                | 如果分区的大小大于此阈值，且大于 spark.sql.adaptive.skewJoin.skewedPartitionFactor 乘以分区大小中值，则该分区被视为倾斜分区。理想情况下，此配置应大于 spark.sql.adaptive.consultivePartitionSizeInBytes。 |                                                              |

 

# 4. Shuffle

| **参数名**                    | **默认值** | **说明**                                                     | **调优建议**                                                 |
| :---------------------------- | :--------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| spark.shuffle.file.buffer     | 32k        | 每个 Shuffle 文件输出流的内存缓冲区大小，这些缓冲区可减少创建中间 Shuffle 文件时的磁盘寻道和系统调用次数。 | 若内存资源充足，可适当调大该参数（如 64k、128k），从而减少 Shuffle Write 溢写磁盘的次数，进而减少磁盘IO次数，提升性能。 |
| spark.reducer.maxSizeInFlight | 48m        | 从每个 Reduce 任务中同时获取的 Map 输出的最大大小。由于每个输出都需要我们创建一个缓冲区来接收，这代表了每个 Reduce 任务的固定内存开销，因此除非有大量内存，否则请将其保持在较小的范围内。 | 若内存资源充足，可适当调大该参数（如 96m、128m），从而减少 Shuffle Read 拉取数据的次数，进而减少网络传输的次数，提升性能。 |
| spark.shuffle.io.maxRetries   | 3          | (仅限 Netty）自动重试因 IO 相关异常而失败的最大拉取次数。这种重试逻辑有助于在出现长时间 GC 停顿或瞬时网络连接问题时稳定大型 Shuffle。 | 对于特别耗时的大型 Shuffle 操作，可适当调大该参数（如 60），以避免长时间 GC 停顿或瞬时网络连接问题导致数据拉取失败。 |
| spark.shuffle.io.retryWait    | 5s         | (仅限 Netty）重试拉取之间的等待时间。重试造成的最大延迟默认为 15 秒，计算公式为 maxRetries * retryWait。 | 对于特别耗时的大型 Shuffle 操作，可适当调大该参数（如 60s），有助于稳定大型 Shuffle。 |
| spark.shuffle.push.enabled    | false      | 设为 true 可在客户端启用基于推送的 Shuffle 功能，并与服务器端标志 spark.shuffle.push.server.mergedShuffleFileManagerImpl 配合使用。 | 官方说明基于推送的 Shuffle 可提高长时间运行的作业/查询的性能，因为在 Shuffle 过程中会涉及大量磁盘 I/O。但目前，它不太适合处理较少 Shuffle 数据的快速运行作业/查询。建议在涉及大量 Shuffle 时开启。 |

 

# 5. Spark SQL

| **参数名**                                                  | **默认值** | **说明**                                                     | **调优建议**                                                 |
| :---------------------------------------------------------- | :--------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| **spark.sql.shuffle.partitions**                            | 200        | 为连接或聚合而 Shuffle 数据时使用的默认分区数。              | 官方建议参数值为 num-executors * executor-cores 的 2-3 倍较为合适。 |
| **spark.sql.autoBroadcastJoinThreshold**                    | 10MB       | 配置执行 Join 时向所有 Worker 节点广播的表的最大大小。将该值设置为-1，可以禁用广播。**注意，目前只有运行了 ANALYZE TABLE <tableName> COMPUTE STATISTICS NOSCAN 命令的 Hive Metastore 表和直接在数据文件上计算统计数据的基于文件的数据源表才支持统计数据**。 | 若内存资源充足，可适当调大该参数（如 64M），以提高 Join 效率。 |
| **spark.sql.broadcastTimeout**                              | 300        | 广播的超时时间（秒）。                                       | 建议根据广播大小进行相应调整。                               |
| spark.sql.optimizer.runtime.bloomFilter.enabled             | true       | 该值为 true 时，如果 Shuffle Join 的一侧有选择性谓词，会尝试在另一侧插入 Bloom Filter，以减少 Shuffle 数据量。 | Spark 3.4 之前默认为 false，建议设置为 true。                |
| spark.sql.optimizer.runtimeFilter.semiJoinReduction.enabled | false      | 该值为 true 时，如果 Shuffle Join 的一侧有选择性谓词，会尝试在另一侧插入 Semi Join，以减少 Shuffle 数据量。 |                                                              |
| spark.sql.files.maxPartitionBytes                           | 128MB      | 读取文件时打包到单个分区的最大字节数。此配置仅在使用 Parquet、JSON 和 ORC 等基于文件的源时有效。 | 建议保持默认值。                                             |
| spark.sql.cbo.enabled                                       | false      | 是否启用基于成本的优化（Cost-Based Optimization，CBO）。CBO 可以基于表和列的统计信息，进行一系列估算，最终选择出最优的查询计划，比如：Build 侧选择、Join 类型优化、多表 Join 顺序优化等。Spark 自 2.2.0 支持 CBO，之前都使用基于规则的优化器（Rule-Based Optimization，RBO）。 | CBO 目前有许多限制，比如，数据统计信息缺失，统计信息不准确，UDF 成本估计困难等。因此，Spark 3.3.0 基于运行时统计信息实现了 AQE，可以动态调整 Join 类型。建议设置为 false，若要启用该功能，需确保相关表和列的统计信息已经生成，并定期更新和维护，同时调整 spark.sql.cbo.joinReorder.enabled 等 CBO 相关配置。 |
| spark.sql.parquet.writeLegacyFormat                         | false      | 该值为 true 时，数据将以 Spark 1.4 及更早版本的方式写入，例如，十进制值将以 Apache Parquet 的固定长度字节数组格式写入，而 Apache Hive 和 Apache Impala 等其他系统都使用这种格式。该值为 false 时，则使用 Parquet 中较新的格式，例如，小数将以基于 int 的格式写入。 | 官方建议如果 Parquet 输出要用于不支持这种较新格式的系统，则应设置为 true。 |

注 1：使用 ANALYZE TABLE 语句可收集表的统计信息，基本语法请参阅[说明](https://spark.apache.org/docs/3.4.2/sql-ref-syntax-aux-analyze-table.html)。

 

# 6. 其它参数

| **参数名**                    | **默认值**                                                   | **说明**                                                     | **调优建议**                                                 |
| :---------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| **spark.default.parallelism** | 对于 reduceByKey 和 join 等 Shuffle 操作，取决于父 RDD 中的最大分区数。对于无父 RDD 的并行化等操作，则取决于集群管理器，Yarn 模式下为所有 Executor 节点的内核数与 2 的最大值 | 当用户未设置时，由 join、reduceByKey 和 parallelize 等转换返回的 RDD 中的默认分区数。 | 官方建议参数值为 num-executors * executor-cores 的 2-3 倍较为合适。 |
| spark.locality.wait           | 3s                                                           | 在放弃并在本地化程度较低的节点上启动任务之前，等待启动数据本地化任务的时间。相同的等待时间将用于跨越多个本地化级别（进程本地化 process-local、节点本地化 node-local、机架本地化 rack-local、然后是任意级别），还可以通过设置 spark.locality.wait.node 等自定义每个级别的等待时间。 | 官方建议如果任务时间较长，本地性较差，则应增加这一设置，但默认设置通常效果不错。 |
| spark.speculation             | false                                                        | 该值为 true 时，会启用 Task 的推测执行。这意味着，如果某个 Task 执行缓慢时，Spark 会启动一个备份 Task 来替代，哪个 Task 先完成，就取该 Task 的结果，并 Kill 掉另一个 Task。 | 推测执行本质是以空间换时间，但 Task 执行缓慢的原因有很多，若推测 Task 也变为缓慢 Task，则会导致情况进一步恶化。对于集群内有不同性能的机器，或执行慢的 Task 集中在同一个机器，建议设置为 true。 |
| spark.speculation.quantile    | 0.75                                                         | 在启用对特定 Stage 的推测执行之前，必须完成的 Task 比例。    |                                                              |
| spark.serializer              | org.apache.spark.serializer.JavaSerializer                   | 用于序列化需要通过网络发送或需要以序列化形式缓存对象的类。默认的 Java 序列化适用于任何可序列化的 Java 对象，但速度较慢。 | 官方建议在需要速度时使用 org.apache.spark.serializer.KryoSerializer 并配置 Kryo 序列化，可以是 org.apache.spark.Serializer 的任何子类。 |
| spark.kryo.unsafe             | true                                                         | 是否使用基于不安全的 Kryo 序列化器，使用基于不安全的 IO 可以大大提高速度。 |                                                              |
|                               |                                                              |                                                              |                                                              |

注 1：spark.sql.shuffle.partitions 与 spark.default.parallelism 区别，前者是在连接和聚合时使用，适用于 SQL；后者只适用于原始 RDD，如果正在执行的任务不是连接或聚合，且使用的是 DataFrame，那么上述参数均不会有任何影响，若实在分不清两者差别，可以同时设置，具体可参考[说明](https://stackoverflow.com/questions/45704156/what-is-the-difference-between-spark-sql-shuffle-partitions-and-spark-default-pa)。

 

# 7. 关联组件参数

| **参数名**                                             | **默认值**                                                   | **说明**                                                     | **调优建议**                                                 |
| :----------------------------------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| spark.yarn.shuffle.stopOnFailure                       | [ yarn-site.xml ]false                                       | 当 Spark Shuffle 服务初始化失败时，是否停止 NodeManager。这可以防止在 Spark Shuffle 服务未运行的 NodeManager 上运行容器导致的应用程序故障。 | 建议保持默认值。                                             |
| spark.shuffle.push.server.mergedShuffleFileManagerImpl | [ yarn-site.xml ]org.apache.spark.network.shuffle.NoOpMergedShuffleFileManager | 管理基于推送 Shuffle 的 MergedShuffleFileManager 实现类名。默认情况下，服务器端禁用基于推送的 Shuffle。若要启用，将此配置设置为 org.apache.spark.network.shuffle.RemoteBlockPushResolver。更多信息，请参阅[说明](https://spark.apache.org/docs/3.4.2/configuration.html#push-based-shuffle-overview)。 | 建议在涉及大量 Shuffle 时开启。                              |
| yarn.nodemanager.local-dirs                            | [ yarn-site.xml ]${hadoop.tmp.dir}/nm-local-dir              | 存储本地化文件的目录列表。应用程序的本地化文件目录位于 ${yarn.nodemanager.local-dirs}/usercache/${user}/appcache/application_${appid}，单个容器的工作目录（称为 container_${contid}）将是该目录的子目录。 | Spark 会将 Shuffle 数据写在此目录，如果只配置一个盘，当 Shuffle 数据较多时，会影响整个 Shuffle 读写性能，需要配置成多个盘。 |
| yarn.nodemanager.log-dirs                              | [ yarn-site.xml ]${yarn.log.dir}/userlogs                    | 存储容器日志的目录列表。应用程序的本地化日志目录位于 ${yarn.nodemanager.log-dirs}/application_${appid}，单个容器的日志目录（称为 container_{$contid}） 将是该目录的子目录，每个容器目录都将包含由该容器生成的 stderr、stdin 和 syslog 文件。 | 同样需要配置多个盘，如果只配置一个盘，有可能任务较多时，日志会把磁盘写满。 |
| YARN_NODEMANAGER_HEAPSIZE                              | [ yarn-env.sh ]HADOOP_HEAPSIZE_MAX                           | 指定 NodeManager 的最大堆大小。这个值将被 HADOOP_OPTS或 YARN_NODEMANAGER_OPTS 中指定的 Xmx 设置覆盖，默认值与 HADOOP_HEAPSIZE_MAX（mapred-env.sh，默认 1000MB）相同。 | Spark ESS 是附属在 NodeManger 上的一个服务，随 NodeManger 一起启动，若 NodeManger JVM 内存配置太小，会影响 ESS 的稳定性。建议该值大于等于 4G。 |
| yarn.nodemanager.resource.memory-mb                    | [ yarn-site.xml ]-1                                          | 可分配给容器的物理内存（单位：MB）。如果设置为-1，且 yarn.nodemanager.resource.detect-hardware-capabilities 为 true，则会自动计算（适用于 Windows 和 Linux）。在其他情况下，默认值为 8192MB。 | 建议节点总内存的 80%，预留部分内存。                         |
| yarn.scheduler.maximum-allocation-mb                   | [ yarn-site.xml ]8192                                        | RM 中**单个容器**可申请的最大内存（单位：MB），大于此值的内存申请将引发 InvalidResourceRequestException。 | 建议节点总内存的 80%，最大不超过 yarn.nodemanager.resource.memory-mb。 |
| yarn.nodemanager.resource.cpu-vcores                   | [ yarn-site.xml ]-1                                          | 可分配给容器的 vcores 数量。RM 调度器在为容器分配资源时使用此值，它不用于限制 YARN 容器使用的 CPU 数量。如果设置为 -1，且 yarn.nodemanager.resource.detect-hardware-capabilities 为 true，则在 Windows 和 Linux 环境下，该值将根据硬件自动确定。在其他情况下，vcores 数量默认为 8。 | 建议节点总核数的 90%，预留部分 Core。                        |
| yarn.scheduler.minimum-allocation-mb                   | [ yarn-site.xml ]1024                                        | 在 RM 中，每个容器请求的最小分配内存，以 MB 为单位，低于此内存请求的值将被设置为此属性的值。此外，配置内存小于此值的 Node Manager 将被 Resource Manager 关闭。 | 建议保持默认值。                                             |

 

# 8. 参数调优

## 8.1 辅助调优

有以下几个辅助调优工具。

**1、集群资源指标**：包括 CPU、内存、硬盘、网络**。**

**2、Spark History Server（SHS）**：重点关注 Jobs（包括 Job 状态、数量、Event Timeline，以及包含的 Stage 汇总信息）、Stages（包括 Stage 读取/写入/Shuffle Write/Shuffle Read 数据量，以及包含的 Task 汇总信息）、Executors（包括内存、磁盘、内核数使用情况，以及 Task 和 Shuffle 信息）、SQL（包括 Job、执行计划等信息），具体参考 [WEB-UI 说明](https://spark.apache.org/docs/3.4.2/web-ui.html)、[监控页面简介（译自官网）](https://iwiki.woa.com/p/4009688377#监控页面简介)。

**3、EXPLAIN 执行计划**：EXPLAIN 语句用于为 SQL 提供逻辑/物理计划，默认只提供有关物理计划的信息。语法为：`EXPLAIN [ EXTENDED | CODEGEN | COST | FORMATTED ] statement`，具体参考 [EXPLAIN 说明](https://spark.apache.org/docs/3.4.2/sql-ref-syntax-qry-explain.html#syntax)。其中 Parsed Logical Plan 表示未解析的逻辑计划，Analyzed Logical Plan 表示解析后的逻辑计划，Optimized Logical Plan  表示优化后的逻辑计划，Physical Plan 表示物理计划。物理计划中，常见类型节点含义如下表所示。

| **类型节点**      | **说明**                                                     |
| :---------------- | :----------------------------------------------------------- |
| HashAggregate     | 数据聚合，一般 HashAggregate 成对出现，第一个 HashAggregate 是将执行节点本地的数据进行局部聚合，另一个 HashAggregate 是将各个分区的数据进一步进行聚合计算。 |
| Exchange          | 数据 Shuffle，表示需要在集群上移动数据，很多时候 HashAggregate 会以 Exchange 分隔开来。 |
| Project           | 投影操作，即选择列，如 select name, age…。                   |
| BroadcastHashJoin | 基于广播方式进行 HashJoin。                                  |

**4、任务日志（Yarn & 本地）**：主要获取 Driver 日志，Cluster 模式日志位于 Yarn，Client 默认日志位于本地。

 

## 8.2 调优思路

可以用下面三个公式来近似估计 Spark 任务的执行时间：

- 任务执行时间 ≈ (任务计算总时间 + Shuffle 总时间 + GC 总时间) / 任务有效并行度
- 任务有效并行度 ≈ min(任务并行度, Partition 分区数) / (数据倾斜度 * 计算倾斜度)
- 任务并行度 ≈ Executor 数量 * 每个 Executor 的 Core 数量 = num-executors * executor-cores

可以用下面二个公式来说明 Spark 在 Executor 上的内存分配：

- Executor 申请的内存 ≈ 堆内内存（堆内内存由多个 Core 共享） + 非堆内存
- 堆内内存 ≈ Storage 内存 + Execution 内存 + Other 内存

**调优思路是用已定参数确认未定参数，用易定参数确定难定参数**。依照上面几个公式，调优顺序一般为：

1、**确认 spark.default.parallelism 及 spark.sql.shuffle.partitions**。Spark 读取 HDFS 文件初始 RDD 分区数为 HDFS 切片数量，约等于输入数据量 / BlockSize，其中 BlockSize 默认 128M。Spark 处理中间数据时，窄依赖算子生成的子 RDD 分区数等于父 RDD 分区数，宽依赖算子由于发生了 Shuffle，生成的子 RDD 分区数由分区器决定，若用户通过 repartition、coalesce、reduceByKey 等算子指定了分区数，则子 RDD 分区数为指定的分区数，否则为父 RDD 中最大分区数与默认分区数（spark.sql.shuffle.partitions、spark.default.parallelism）的最大值。**Spark 最后按照每个分区对应一个文件写入 HDFS，注意，自适应查询有合并分区的功能**。由于 HDFS 要求文件大小尽量接近 BlockSize 大小，以减少存储空间的开销和提高文件系统的性能，因此每个分区处理的数据量大致为 128M ~ 1G，这里上限 1G 是因为每个分区对应一个 Task，并由 Executor 一个 Core 处理，由于多个 Core 共享 Executor 内存，设置过大将导致 Executor 内存不足，数据溢写磁盘，从而导致任务运行缓慢。**因此，分区数设置主要考量输出数据的规模，一般可以设置为：输出数据量 / (128M ~ 1G)**。若无法估计输出数据量，建议先保持默认值 200，然后根据任务运行情况调整。

2、**确认 num-executors 及 executor-cores**。**根据经验实践，executor-cores 设置为 2 ~ 5 较为合理，然后遵循官方建议，分区数为 num-executors \* executor-cores 的 2-3 倍较为合适，计算出 num-executors**。**如果要充分利用集群资源进行性能测试，可以根据 Yarn 队列最大 vCores \* (0.8 ~ 0.9) / executor-core 计算出 num-executors，但如果与其他用户共享 Yarn 资源队列，则按照资源队列的 1/3 - 1/2 进行估算，然后根据前面的官方建议，反向确认分区数**。注意，Yarn 集群资源 vCore 及 Memory 可查看 Yarn UI，分别由以下参数计算得来：yarn.nodemanager.resource.cpu-vcores * NM 节点数、yarn.nodemanager.resource.memory-mb * NM 节点数。

3、**确认 executor-memory。如果要充分利用集群资源进行性能测试，可以根据 Yarn 队列最大 Memory \* (0.8 ~ 0.9) / num-executors - spark.memory.offHeap.size（spark.memory.offHeap.enabled 为 true 时） - spark.executor.memoryOverhead 计算出 executor-memory，但如果与其他用户共享 Yarn 资源队列，则按照资源队列的 1/3 - 1/2 进行估算**。注意，executor-memory 不能超过 yarn.scheduler.maximum-allocation-mb 设置的值，因为该值限制了单个容器可申请的最大内存。

4、**其他参数根据运行情况调整**。比如，Shuffle 过程发生 OOM 或 GC 耗时过长，可考虑增加 executor-memory 或减少 executor-core，必要时增加非堆内存，避免频繁 GC，还可考虑开启 Push-based Shuffle；数据倾斜可参考 [Spark 性能优化指南——高级篇](https://tech.meituan.com/2016/05/12/spark-tuning-pro.html)；其他优化，包括：小表广播、自适应查询 AQE、动态分区裁剪、布隆过滤，可参考《Spark 开发规范》以及《Spark 功能特性》。

5、**针对 Spark 任务的启动优化**。比如：修改参数 spark.sql.extensions 关闭 Ranger 鉴权；新增参数 spark.yarn.jars 或 spark.yarn.archive 将 Spark Jars 内置在 HDFS 中，减少上传 Jar 包的时间；以及使用 Kyuubi 会话提交任务。

 

 

# 9. 参考

1. [Spark 官网 - Spark Configuration](https://spark.apache.org/docs/3.4.2/configuration.html)
2. [Spark 官网 - tuning](https://spark.apache.org/docs/3.4.2/tuning.html)
3. [Spark 官网 - SQL Syntax](https://spark.apache.org/docs/3.4.2/sql-ref-syntax.html)
4. [Hadoop 官网 - yarn-default.xml](https://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-common/yarn-default.xml)
5. [iwiki - Spark 开发规范](https://iwiki.woa.com/p/4009688377)
6. [iwiki - Hadoop集群小文件治理方案](https://iwiki.woa.com/p/4009138690)
8. [Spark 调优原理](https://github.com/lyhue1991/eat_pyspark_in_10_days/blob/master/3-1,Spark性能调优方法.md)
9. [Spark 性能优化指南——高级篇](https://tech.meituan.com/2016/05/12/spark-tuning-pro.html)
10. [Difference between "spark.yarn.executor.memoryOverhead" and "spark.memory.offHeap.size"](https://stackoverflow.com/questions/58666517/difference-between-spark-yarn-executor-memoryoverhead-and-spark-memory-offhea/61723456#61723456)
11. [Difference between "spark.sql.shuffle.partitions" and "spark.default.parallelism"](https://stackoverflow.com/questions/45704156/what-is-the-difference-between-spark-sql-shuffle-partitions-and-spark-default-pa)

 