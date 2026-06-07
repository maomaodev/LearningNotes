说明：代码部分以 spark 3.5.7 为例讲解。

# 1. Spark Shuffle 类型

在 Spark的 源码中，负责 Shuffle 过程的执行、计算和处理的组件主要就是 ShuffleManager，也即 Shuffle 管理器。而随着 Spark 的版本的发展，ShuffleManager 也在不断迭代，变得越来越先进。

**在 Spark 1.2 以前，默认的 Shuffle 计算引擎是 HashShuffleManager**。该 ShuffleManager 即 HashShuffleManager 有着一个非常严重的弊端，就是会产生大量的中间磁盘文件，进而由**大量的磁盘 IO 操作影响了性能**。

因此**在 Spark 1.2 以后的版本中，默认的 ShuffleManager 改成了 SortShuffleManager**。SortShuffleManager 相较于 HashShuffleManager 来说，有了一定的改进。主要就在于，每个 Task 在进行 Shuffle 操作时，虽然也会产生较多的临时磁盘文件，但是**最后会将所有的临时文件合并（merge）成一个磁盘文件，因此每个 Task 就只有一个磁盘文件**。在下一个 stage 的 shuffle read task 拉取自己的数据时，只要根据索引读取每个磁盘文件中的部分数据即可。

| Shuffle 类型                | 文件数量  |
| --------------------------- | --------- |
| 未优化的 HashShuffleManager | M × R     |
| 优化后的 HashShuffleManager | E x C × R |
| Base SortShuffleManager     | 2 × M     |
| Bypass SortShuffleManager   | 2 × M     |

注：M 表示 Map Task 数，R 表示 Reduce Task 数，E 表示 Executor 数，C 表示 Executor Core 数

## 1.1 HashShuffleManager

### 1.1.1 未经优化的 HashShuffleManager

下图说明了未经优化的 HashShuffleManager 的原理。这里我们先明确一个假设前提：每个 Executor 只有 1 个 CPU core，也就是说，无论这个 Executor 上分配多少个 task 线程，同一时间都只能执行一个 task 线程。

我们先从 shuffle write 开始说起。shuffle write 阶段，主要就是在一个 stage 结束计算之后，为了下一个 stage 可以执行 shuffle 类的算子（比如 reduceByKey），而将每个 task 处理的数据按 key 进行“分类”。**所谓“分类”，就是对相同的 key 执行 hash 算法，从而将相同 key 都写入同一个磁盘文件中，而每一个磁盘文件都只属于下游 stage 的一个 task**。在将数据写入磁盘之前，会先将数据写入内存缓冲中，当内存缓冲填满之后，才会溢写到磁盘文件中去。

那么每个执行 shuffle write 的 task，要为下一个 stage 创建多少个磁盘文件呢？很简单，**下一个 stage 的 task 有多少个，当前 stage 的每个 task 就要创建多少份磁盘文件**。比如下一个 stage 总共有 100 个 task，那么当前 stage 的每个 task 都要创建 100 份磁盘文件。如果当前 stage 有 50 个 task，总共有 10 个 Executor，每个 Executor 执行 5 个 Task，那么每个 Executor 上总共就要创建 500 个磁盘文件，所有 Executor 上会创建 5000 个磁盘文件。由此可见，**未经优化的 shuffle write 操作所产生的磁盘文件的数量是极其惊人的**。

接着我们来说说 shuffle read。shuffle read，通常就是一个 stage 刚开始时要做的事情。此时该 stage 的每一个 task 就需要将上一个 stage 的计算结果中的所有相同 key，从各个节点上通过网络都拉取到自己所在的节点上，然后进行 key 的聚合或连接等操作。由于 shuffle write 的过程中，task 给下游 stage 的每个 task 都创建了一个磁盘文件，因此 shuffle read 的过程中，每个 task 只要从上游 stage 的所有 task 所在节点上，拉取属于自己的那一个磁盘文件即可。

shuffle read 的拉取过程是一边拉取一边进行聚合的。每个 shuffle read task 都会有一个自己的 buffer 缓冲，每次都只能拉取与 buffer 缓冲相同大小的数据，然后通过内存中的一个 Map 进行聚合等操作。聚合完一批数据后，再拉取下一批数据，并放到 buffer 缓冲中进行聚合操作。以此类推，直到最后将所有数据到拉取完，并得到最终的结果。

![未经优化的 HashShuffleManager](</Users/maomao/study/learning-notes/08-BigData/Spark/Spark Core/images/未经优化的 HashShuffleManager.png>)



### 1.1.2 优化后的 HashShuffleManager

下图说明了优化后的 HashShuffleManager 的原理。这里说的优化，是指我们可以设置一个参数，spark.shuffle.consolidateFiles。该参数默认值为 false，将其设置为 true 即可开启优化机制。通常来说，如果我们使用 HashShuffleManager，那么都建议开启这个选项。

开启 consolidate 机制之后，在 shuffle write 过程中，task 就不是为下游 stage 的每个 task 创建一个磁盘文件了。此时会出现 shuffleFileGroup 的概念，**每个 shuffleFileGroup 会对应一批磁盘文件，磁盘文件的数量与下游 stage 的 task 数量是相同的**。一个 Executor 上有多少个 CPU core，就可以并行执行多少个 task。而第一批并行执行的每个 task 都会创建一个 shuffleFileGroup，并将数据写入对应的磁盘文件内。

当 Executor 的 CPU core 执行完一批 task，接着执行下一批 task 时，下一批 task 就会复用之前已有的 shuffleFileGroup，包括其中的磁盘文件。也就是说，此时 task 会将数据写入已有的磁盘文件中，而不会写入新的磁盘文件中。因此，consolidate 机制允许不同的 task 复用同一批磁盘文件，这样就可以有效将多个 task 的磁盘文件进行一定程度上的合并，从而大幅度减少磁盘文件的数量，进而提升 shuffle write 的性能。

假设第二个 stage 有 100 个 task，第一个 stage 有 50 个 task，总共还是有 10 个 Executor，每个 Executor 执行 5 个 task。那么原本使用未经优化的 HashShuffleManager 时，每个 Executor 会产生 500 个磁盘文件，所有  Executor 会产生 5000 个磁盘文件的。但是此时经过优化之后，每个 Executor 创建的磁盘文件的数量的计算公式为：**CPU core 的数量 \* 下一个 stage 的 task 数量**。也就是说，每个 Executor 此时只会创建 100 个磁盘文件，所有 Executor 只会创建 1000 个磁盘文件。

![优化后的 HashShuffleManager](</Users/maomao/study/learning-notes/08-BigData/Spark/Spark Core/images/优化后的 HashShuffleManager.png>)



## 1.2 SortShuffleManager

### 1.2.1 普通运行机制

下图说明了普通的 SortShuffleManager 的原理。在该模式下，数据会先写入一个内存数据结构中，此时根据不同的 shuffle 算子，可能选用不同的数据结构。如果是 reduceByKey 这种聚合类的 shuffle 算子，那么会选用 Map 数据结构（PartitionedAppendOnlyMap），一边通过 Map 进行聚合，一边写入内存；如果是 join 这种普通的 shuffle 算子，那么会选用 Array 数据结构（PartitionedPairBuffer），直接写入内存。接着，**每写一条数据进入内存数据结构之后，就会判断一下，是否达到了某个临界阈值。如果达到临界阈值的话，那么就会尝试将内存数据结构中的数据溢写到磁盘，然后清空内存数据结构**。

**在溢写到磁盘文件之前，会先根据 key 对内存数据结构中已有的数据进行排序**。排序过后，会分批将数据写入磁盘文件。默认的 batch 数量是 10000 条，也就是说，排序好的数据，会以每批 1 万条数据的形式分批写入磁盘文件。写入磁盘文件是通过 Java 的 BufferedOutputStream 实现的。BufferedOutputStream 是 Java 的缓冲输出流，首先会将数据缓冲在内存中，当内存缓冲满溢之后再一次写入磁盘文件中，这样可以减少磁盘 IO 次数，提升性能。

一个 task 将所有数据写入内存数据结构的过程中，**会发生多次磁盘溢写操作，也就会产生多个临时文件。最后会将之前所有的临时磁盘文件都进行合并，这就是 merge 过程**，此时会将之前所有临时磁盘文件中的数据读取出来，然后依次写入最终的磁盘文件之中。此外，由于一个 task 就只对应一个磁盘文件，也就意味着该 task 为下游 stage 的 task 准备的数据都在这一个文件中，因此**还会单独写一份索引文件，其中标识了下游各个 task 的数据在文件中的 start offset 与 end offset**。

SortShuffleManager 由于有一个磁盘文件 merge 的过程，因此大大减少了文件数量。比如第一个 stage 有 50 个 task，总共有 10 个 Executor，每个 Executor 执行 5 个 task，而第二个 stage 有 100 个 task。由于**每个 task 最终只有一个磁盘文件**，因此，此时每个 Executor 上只有 5 个磁盘文件，所有 Executor 只有 50 个磁盘文件（加上索引文件共有 100 个磁盘文件）。

![普通运行机制](</Users/maomao/study/learning-notes/08-BigData/Spark/Spark Core/images/普通运行机制.png>)



### 1.2.2 bypass 运行机制

下图说明了 bypass SortShuffleManager 的原理。bypass 运行机制的触发条件如下： **shuffle reduce task 数量小于等于 spark.shuffle.sort.bypassMergeThreshold 参数（默认 200）的值，且不是聚合类的 shuffle  算子（比如 reduceByKey）**。

此时 **task 会为每个下游 task 都创建一个临时磁盘文件**，并将数据按 key 进行 hash，然后根据 key 的 hash 值，将 key 写入对应的磁盘文件之中。当然，写入磁盘文件时也是先写入内存缓冲，缓冲写满之后再溢写到磁盘文件的。最后，同样会将所有临时磁盘文件都合并成一个磁盘文件，并创建一个单独的索引文件。

该过程的**磁盘写机制其实跟未经优化的 HashShuffleManager 是一模一样的，因为都要创建数量惊人的磁盘文件，只是在最后会做一个磁盘文件的合并而已**。因此少量的最终磁盘文件，也让该机制相对未经优化的 HashShuffleManager 来说，shuffle read 的性能会更好。

而**该机制与普通 SortShuffleManager 运行机制的不同在于：第一，磁盘写机制不同；第二，不会进行排序**。也就是说，启用该机制的最大好处在于，**shuffle write 过程中，不需要进行数据的排序操作，也就节省掉了这部分的性能开销**。

![bypass 运行机制](</Users/maomao/study/learning-notes/08-BigData/Spark/Spark Core/images/bypass 运行机制.png>)





# 2. Spark Shuffle 实现

## 2.1 Shuffle Write

Spark 作业运行过程中，最消耗性能的地方就是 Shuffle，而 Shuffle 的性能主要取决于落盘机制。在《Spark Core》介绍过，ShuffleMapTask 负责写，因此从 ShuffleMapTask 类的 runTask() 方法开始。这里针对不同的 ShuffleHandle，获取不同的 ShuffleWriter，它们分别是：

**1、不能有预聚和，且下游 RDD（reduce端）的分区数小于等于 spark.shuffle.sort.bypassMergeThreshold（默认 200）：BypassMergeSortShuffleHandle => BypassMergeSortShuffleWriter**

**2、序列化支持重定向操作，且不能有预聚和，且分区数量不能大于 16777216：SerializedShuffleHandle => UnsafeShuffleWriter**

**3、以上条件均不满足：BaseShuffleHandle => SortShuffleWriter**

```scala
ShuffleMapTask
  runTask()
    // 特定分区的写入过程，它控制从ShuffleManager获取的ShuffleWriter的生命周期，并触发RDD计算，最后返回该任务的MapStatus
    dep.shuffleWriterProcessor.write(...)
      // 获取一个ShuffleHandle
      dep.shuffleHandle
        // 继承关系：SortShuffleManager -> ShuffleManager，这里实际调用SortShuffleManager.registerShuffle()方法
        _rdd.context.env.shuffleManager.registerShuffle(shuffleId, this)
          // 1.不能有map端预聚和，且下游RDD（reduce端）的分区数小于等于200（参数spark.shuffle.sort.bypassMergeThreshold指定）
          if (SortShuffleWriter.shouldBypassMergeSort(conf, dependency))
            new BypassMergeSortShuffleHandle[K, V](...)
          // 2.序列化支持重定向操作，且不能有预聚和，且分区数量不能大于16777216
          // 当前只有KryoSerializer支持重定向操作，除非用户提供的注册器关闭了重定向（autoReset）
          else if (SortShuffleManager.canUseSerializedShuffle(dependency))
            new SerializedShuffleHandle[K, V](...)
          // 3.以上条件均不满足
          else new BaseShuffleHandle()
      // 根据不同的ShuffleHandle，获取不同的Writer。SortShuffleManager重写了该方法，新版本已经不存在HashShuffleManager
      // 继承关系：UnsafeShuffleWriter、BypassMergeSortShuffleWriter、SortShuffleWriter -> ShuffleWriter
      writer = manager.getWriter[Any, Any](...)
        case SerializedShuffleHandle => new UnsafeShuffleWriter(...)
        case BypassMergeSortShuffleHandle => new BypassMergeSortShuffleWriter(...)
        case BaseShuffleHandle => new SortShuffleWriter(...) 
      writer.write(...)
```



### 2.1.1 SortShuffleWriter

```scala
SortShuffleWriter
  write(records: Iterator[Product2[K, V]])
    // 若有map端预聚合，入参指定dep.aggregator（聚合器）、dep.keyOrdering（排序器）；
    // 否则入参指定None，因为此时不在意每个分区内key是否有序，如果执行的是sortByKey，那么分区内排序将在reduce端完成
    sorter = new ExternalSorter[K, V, C](...)
    // 1.详细介绍参考《Spark Shuffle 数据结构》
    sorter.insertAll()
      shouldCombine = aggregator.isDefined
      // 1.1 若有map端预聚合，map类型是PartitionedAppendOnlyMap，根据key=(partition, key)更新value，最大支持0.7×2^29=375809638，当达到指定容量时，会将map中的数据溢写到磁盘
      // PartitionedAppendOnlyMap是一个经过优化的哈希表，支持向map中追加数据，以及修改key对应的value，但不支持删除某个key及其对应的value
      if (shouldCombine)
        // 内存接收数据 + map端预聚合
        map.changeValue((getPartition(kv._1), kv._1), update)
        maybeSpillCollection(usingMap = true)
          // 如果需要，将当前的内存集合溢写到磁盘，在溢写之前，尝试获取更多的内存
          maybeSpill(map, estimatedSize)
            // elementsRead表示当前存储在内存中的记录总数，currentMemory表示对map/buffer中总记录数据大小的估算，myMemoryIhreshold由参数spark.shuffle.spill.initialMemoryThreshold决定，默认5MB
            // 当满足条件时，尝试向MemoryManager申请内存。如果能申请到，则不进行落盘，而是继续向map/buffer中存储数据；如果申请不到，则将map/buffer中的数据溢写磁盘文件
            if (elementsRead % 32 == 0 && currentMemory >= myMemoryThreshold)
              val amountToRequest = 2 * currentMemory - myMemoryThreshold
              val granted = acquireMemory(amountToRequest)
              myMemoryThreshold += granted
              shouldSpill = currentMemory >= myMemoryThreshold
            // 发生溢写
            if (shouldSpill)
              spill()
                // ExternalSorter类，先按照分区排序，分区内按照key或key的哈希值排序
                destructiveSortedWritablePartitionedIterator()
                  partitionedDestructiveSortedIterator()
                spillMemoryIteratorToDisk()
                  // 生成临时溢写文件
                  diskBlockManager.createTempShuffleBlock()
                // 记录临时溢写文件
                spills += spillFile
              releaseMemory()
      // 1.2 若没有map端预聚合，buffer类型是PartitionedPairBuffer，其本质是内存数组，(partition, key)与value相邻存储，前者存偶数下标，后者存奇数下标
      // PartitionedPairBuffer初始分配2*64=128，每次扩容为当前容量的2倍，最多支持(Integer.MAX_VALUE - 15)/2个键值对
      else
        // 内存接收数据
        buffer.insert(getPartition(kv._1), kv._1, kv._2.asInstanceOf[C])
        // 后续调用流程与前面类似
        maybeSpillCollection(usingMap = false)
    // 2.合并溢写文件
    sorter.writePartitionedMapOutput()
      // 若存在溢写文件，则合并溢写和内存中的数据；否则只需处理内存中的数据，条件spills.isEmpty
      this.partitionedIterator
        // 合并溢写和内存中的数据
        merge(...)
          // 使用归并排序，实现上使用优先队列PriorityQueue
          mergeSort(...)
    // 3.提交写入，并返回每个分区写入的字节数
    mapOutputWriter.commitAllPartitions()
      // 以原子操作提交数据和元数据文件，使用现有文件或用新文件替换它们。有两类元数据文件：索引文件、校验和文件（可选）
      blockResolver.writeMetadataFileAndCommit(...)
        // 获取临时数据/索引文件，改名为正式数据/索引文件
        indexFile = getIndexFile(shuffleId, mapId)
        dataFile = getDataFile(shuffleId, mapId)
        // 每个Executor只有一个IndexShuffleBlockResolver，同步确保了以下检查和重命名是原子操作
        this.synchronized
          // 即indexTmp.renameTo(indexFile)
          tmpFile.renameTo(targetFile)
          dataTmp.renameTo(dataFile)
```



### 2.1.2 BypassMergeSortShuffleWriter

```scala
BypassMergeSortShuffleWriter
  write(Iterator<Product2<K, V>> records)
    // DiskBlockObjectWriter数组，针对每个分区，对应写一个临时文件
    partitionWriters = new DiskBlockObjectWriter[numPartitions]
    for (int i = 0; i < numPartitions; i++)
      partitionWriters[i] = blockManager.getDiskWriter()
    // 根据key获取对应分区，然后写入分区对应的文件
    while (records.hasNext())
      final Product2<K, V> record = records.next();
      final K key = record._1();
      partitionWriters[partitioner.getPartition(key)].write(key, record._2());
    // 将所有分区文件合并为一个单独的组合文件
    writePartitionedData(mapOutputWriter)
      // 后续调用流程与SortShuffleWriter相同
      mapOutputWriter.commitAllPartitions(...)
```



### 2.1.3 UnsafeShuffleWriter

```scala
UnsafeShuffleWriter
  write(...)
    insertRecordIntoSorter(records.next())
      // 将记录写入Shuffle Sorter
      sorter.insertRecord(...)
        // 内存存储的数据大于等于spark.shuffle.spill.numElementsForceSpillThreshold，默认Integer.MAX_VALUE
        if (inMemSorter.numRecords() >= numElementsForSpillThreshold)
          // 溢写磁盘，释放内存
          spill()
        // 检查inMemSorter中的LongArray是否有足够内存容纳新数据生成的指针，并在需要时扩展数组的大小，如果无法获得所需的空间，则会将内存中的数据溢写到磁盘
        growPointerArrayIfNecessary()
        // 检查当前的内存空间能否存储新的数据（加上存储数据长度的4/8字节），并在需要时申请新的内存页，如果无法获得所请求的内存，则会进行溢写操作
        acquireNewPageIfNecessary
        // 插入要进行排序的记录
        inMemSorter.insertRecord(recordAddress, partitionId)
```



## 2.2 Shuffle Read





# 参考

1. 《大数据处理框架 Apache Spark 设计与实现》
1. [Spark性能优化指南——基础篇](https://tech.meituan.com/2016/04/29/spark-tuning-basic.html)、[Spark性能优化指南——高级篇](https://tech.meituan.com/2016/05/12/spark-tuning-pro.html)