说明：代码部分以 spark 3.5.7 为例讲解。

# 1. AppendOnlyMap

AppendOnlyMap 实际上是一个**只支持 record 添加和对 value 进行更新的 HashMap**。与 Java HashMap 采用“数组+链表”实现不同，**AppendOnlyMap 只使用数组来存储元素，它将键和值放在同一个数组中，具体来说，元素的顺序为 [k1, v1, k2, v2, ..., kn, vn]**。AppendOnlyMap 根据元素的 Hash 值确定存储位置，**如果存储元素时发生哈希冲突，则使用二次探测法（quadratic probing）解决**。第 i 次冲突时，探测位置在前一次基础上累加 `delta = i`，因此相对于初始位置 `pos` 的偏移量是三角数 `1 + 2 + ... + i = i * (i+1) / 2`，与 i² 同阶。再配合“表大小为 2 的幂”这一约束，能保证遍历表中所有槽位。

1. **扩容（`growTable` 方法）**：如果数组利用率达到 70%（负载因子），则扩张一倍，此时原来的 Hash 失效， 因此需要对所有 Key 进行 rehash。

2. **输出（`iterator` 方法）**：迭代 AppendOnlyMap 数组中的 record，从前到后扫描输出即可。

3. **排序（`destructiveSortedIterator` 方法）**：先将数组中所有的 record 转移到数组的前端（注意，原地操作破坏了 map 的有效性，不能再使用），用 begin 和 end 来标示起始位置，然后调用排序算法对 [begin, end] 中的 record 进行归并排序。**对于需要按 key 进行排序的操作，可以按照 key 值进行排序；对于其他操作，只按照 key 的哈希值进行排序即可**。

![AppendOnlyMap排序](./images/AppendOnlyMap排序.png)

```scala
// 一个为追加（append-only）场景优化的简单开放地址哈希表，其中键不会被移除，但每个键对应的值可以被修改
// 该实现使用二次探测（quadratic probing），并将哈希表大小设为 2 的幂，这能保证对每个键遍历表中所有位置（参见 http://en.wikipedia.org/wiki/Quadratic_probing）
// 该映射最多支持 375809638（0.7 * 2^29） 个元素
class AppendOnlyMap[K, V](initialCapacity: Int = 64)
  extends Iterable[(K, V)] with Serializable {

  import AppendOnlyMap._

  // 负载因子
  private val LOAD_FACTOR = 0.7
  // 哈希表大小设为2的幂（>= initialCapacity）
  private var capacity = nextPowerOf2(initialCapacity)
  // 掩码，hashCode & mask计算出元素存储位置
  private var mask = capacity - 1
  // 当前大小
  private var curSize = 0
  // 扩容阈值，当哈希表大小 > 0.7 * capacity，则扩容
  private var growThreshold = (LOAD_FACTOR * capacity).toInt

  // 将键和值放在同一个数组中（容量为 2 * capacity）以提高内存局部性；具体来说，元素的顺序为：
  // key0, value0, key1, value1, key2, value2，依此类推
  private var data = new Array[AnyRef](2 * capacity)

  // 对 null 键采用特殊处理，这样我们就可以在 data 中使用 null 来表示空项
  private var haveNullValue = false
  private var nullValue: V = null.asInstanceOf[V]

  // 由 destructiveSortedIterator 触发；底层的 data 数组可能不再可用
  private var destroyed = false
  private val destructionMessage = "Map state is invalid from destructive sorting!"

  // 获取给定键的值
  def apply(key: K): V = {
    assert(!destroyed, destructionMessage)
    val k = key.asInstanceOf[AnyRef]
    if (k.eq(null)) {
      return nullValue
    }
    // hashCode & mask计算出元素存储位置
    var pos = rehash(k.hashCode) & mask
    var i = 1
    while (true) {
      val curKey = data(2 * pos)
      // 引用相等或值相等，即定位成功
      if (k.eq(curKey) || k.equals(curKey)) {
        return data(2 * pos + 1).asInstanceOf[V]
      } else if (curKey.eq(null)) {
        return null.asInstanceOf[V]
      } else {
        // 当发生哈希冲突时，采用二次探测。每次冲突 delta = i（i 从 1 开始递增），
        // 探测位置在前一次 pos 基础上累加 delta，因此相对于初始 pos 偏移为 i*(i+1)/2（三角数序列）
        // 第 1 次冲突：delta = 1，pos = (pos + 1) & mask，相对初始偏移 1
        // 第 2 次冲突：delta = 2，pos = (pos + 1 + 2) & mask，相对初始偏移 3
        // 第 3 次冲突：delta = 3，pos = (pos + 1 + 2 + 3) & mask，相对初始偏移 6
        val delta = i
        pos = (pos + delta) & mask
        i += 1
      }
    }
    null.asInstanceOf[V]
  }

  // 为给定键设置值
  def update(key: K, value: V): Unit = {
    assert(!destroyed, destructionMessage)
    val k = key.asInstanceOf[AnyRef]
    // 键为null时，特殊处理
    if (k.eq(null)) {
      if (!haveNullValue) {
        incrementSize()
      }
      nullValue = value
      haveNullValue = true
      return
    }
    var pos = rehash(key.hashCode) & mask
    var i = 1
    while (true) {
      val curKey = data(2 * pos)
      if (curKey.eq(null)) {
        // 键尚未存在，追加
        data(2 * pos) = k
        data(2 * pos + 1) = value.asInstanceOf[AnyRef]
        incrementSize()  // 因为我们增加了一个新的键
        return
      } else if (k.eq(curKey) || k.equals(curKey)) {
        // 键已经存在，更新
        data(2 * pos + 1) = value.asInstanceOf[AnyRef]
        return
      } else {
        val delta = i
        pos = (pos + delta) & mask
        i += 1
      }
    }
  }

  // 将键的值设置为 updateFunc(hadValue, oldValue)，其中 oldValue 是该键的旧值（若存在），否则为 null；hadValue 为布尔值，表示是否存在旧值。返回更新后的新值。
  def changeValue(key: K, updateFunc: (Boolean, V) => V): V = {
    // 处理流程与update方法基本相同
    assert(!destroyed, destructionMessage)
    val k = key.asInstanceOf[AnyRef]
    if (k.eq(null)) {
      if (!haveNullValue) {
        incrementSize()
      }
      nullValue = updateFunc(haveNullValue, nullValue)
      haveNullValue = true
      return nullValue
    }
    var pos = rehash(k.hashCode) & mask
    var i = 1
    while (true) {
      val curKey = data(2 * pos)
      if (curKey.eq(null)) {
        val newValue = updateFunc(false, null.asInstanceOf[V])
        data(2 * pos) = k
        data(2 * pos + 1) = newValue.asInstanceOf[AnyRef]
        incrementSize()
        return newValue
      } else if (k.eq(curKey) || k.equals(curKey)) {
        val newValue = updateFunc(true, data(2 * pos + 1).asInstanceOf[V])
        data(2 * pos + 1) = newValue.asInstanceOf[AnyRef]
        return newValue
      } else {
        val delta = i
        pos = (pos + delta) & mask
        i += 1
      }
    }
    null.asInstanceOf[V] // 理论上永远不会到达（执行），但为了让编译器不报错而必须保留
  }

  // 来自 Iterable 的 iterator 方法
  override def iterator: Iterator[(K, V)] = {
    assert(!destroyed, destructionMessage)
    new Iterator[(K, V)] {
      var pos = -1

      // 获取 next() 应返回的下一个值；如果已完成迭代则返回 null
      def nextValue(): (K, V) = {
        if (pos == -1) {    // 将位置 -1 视为查看 null 值
          if (haveNullValue) {
            return (null.asInstanceOf[K], nullValue)
          }
          pos += 1
        }
        while (pos < capacity) {
          if (!data(2 * pos).eq(null)) {
            return (data(2 * pos).asInstanceOf[K], data(2 * pos + 1).asInstanceOf[V])
          }
          pos += 1
        }
        null
      }

      override def hasNext: Boolean = nextValue() != null

      override def next(): (K, V) = {
        val value = nextValue()
        if (value == null) {
          throw new NoSuchElementException("End of iterator")
        }
        pos += 1
        value
      }
    }
  }

  override def size: Int = curSize

  // 将表大小增加 1，如有必要，进行重新哈希
  private def incrementSize(): Unit = {
    curSize += 1
    if (curSize > growThreshold) {
      growTable()
    }
  }

  // 重新哈希，以更好地应对哈希函数在低位没有差异的情况
  private def rehash(h: Int): Int = Hashing.murmur3_32().hashInt(h).asInt()

  // 将哈希表的容量翻倍，并重新哈希
  protected def growTable(): Unit = {
    // capacity < MAXIMUM_CAPACITY (2^29) ，因此 capacity * 2 不会溢出
    val newCapacity = capacity * 2
    require(newCapacity <= MAXIMUM_CAPACITY, s"Can't contain more than ${growThreshold} elements")
    val newData = new Array[AnyRef](2 * newCapacity)
    val newMask = newCapacity - 1
    // 将所有旧值插入到新数组中。注意，由于旧键是唯一的，因此在插入时无需检查相等性
    var oldPos = 0
    while (oldPos < capacity) {
      if (!data(2 * oldPos).eq(null)) {
        val key = data(2 * oldPos)
        val value = data(2 * oldPos + 1)
        var newPos = rehash(key.hashCode) & newMask
        var i = 1
        var keepGoing = true
        while (keepGoing) {
          val curKey = newData(2 * newPos)
          if (curKey.eq(null)) {
            newData(2 * newPos) = key
            newData(2 * newPos + 1) = value
            keepGoing = false
          } else {
            val delta = i
            newPos = (newPos + delta) & newMask
            i += 1
          }
        }
      }
      oldPos += 1
    }
    data = newData
    capacity = newCapacity
    mask = newMask
    growThreshold = (LOAD_FACTOR * newCapacity).toInt
  }

  private def nextPowerOf2(n: Int): Int = {
    val highBit = Integer.highestOneBit(n)
    if (highBit == n) n else highBit << 1
  }

  // 返回按排序顺序遍历该 map 的迭代器。该方法通过就地重排（不使用额外内存）来产生有序迭代，因此代价是破坏原 map 的有效性
  def destructiveSortedIterator(keyComparator: Comparator[K]): Iterator[(K, V)] = {
    // 破坏了原 map 的有效性，不能再使用
    destroyed = true
    // 将键值对压缩排列到底层数组的前部（即移动到数组开头）
    var keyIndex, newIndex = 0
    while (keyIndex < capacity) {
      if (data(2 * keyIndex) != null) {
        data(2 * newIndex) = data(2 * keyIndex)
        data(2 * newIndex + 1) = data(2 * keyIndex + 1)
        newIndex += 1
      }
      keyIndex += 1
    }
    assert(curSize == newIndex + (if (haveNullValue) 1 else 0))

   	// 按照指定Comparator，对data进行排序。底层采用“稳定、自适应、迭代的归并排序”，参考 java.util.Comparator.TimSort 类实现
    new Sorter(new KVArraySortDataFormat[K, AnyRef]).sort(data, 0, newIndex, keyComparator)
    
		// 返回按排序顺序遍历该 map 的迭代器
    new Iterator[(K, V)] {
      var i = 0
      var nullValueReady = haveNullValue
      def hasNext: Boolean = (i < newIndex || nullValueReady)
      def next(): (K, V) = {
        if (nullValueReady) {
          nullValueReady = false
          (null.asInstanceOf[K], nullValue)
        } else {
          val item = (data(2 * i).asInstanceOf[K], data(2 * i + 1).asInstanceOf[V])
          i += 1
          item
        }
      }
    }
  }

  // 返回下一次插入是否会导致该 map 增长（例如触发扩容）
  def atGrowThreshold: Boolean = curSize == growThreshold
}

private object AppendOnlyMap {
  // 最大容量，需要乘以负载因子0.7
  val MAXIMUM_CAPACITY = (1 << 29)
}

```





# 2. SizeTrackingAppendOnlyMap

SizeTrackingAppendOnlyMap 继承自 AppendOnlyMap，意味着它也是一个只支持 record 添加和对 value 进行更新的 HashMap，**同时它通过 SizeTracker 支持跟踪其估计的字节大小**。

```scala
// 一个仅追加的 map，跟踪其估计的字节大小
private[spark] class SizeTrackingAppendOnlyMap[K, V]
  extends AppendOnlyMap[K, V] with SizeTracker
{
  override def update(key: K, value: V): Unit = {
    super.update(key, value)
    super.afterUpdate()
  }

  override def changeValue(key: K, updateFunc: (Boolean, V) => V): V = {
    val newValue = super.changeValue(key, updateFunc)
    super.afterUpdate()
    newValue
  }

  override protected def growTable(): Unit = {
    super.growTable()
    resetSamples()
  }
}
```

**SizeTracker 是一个用于跟踪集合估计大小的接口，由于每次调用 `SizeEstimator.estimate(this)` 都比较昂贵（大约几毫秒级别），因此按照指数退避进行采样，采样频率随更新次数增加而降低，以摊销时间开销**。

1. **采样（`takeSample` 方法）**：昂贵操作，调用 `SizeEstimator.estimate(this)` 估计当前集合的内存大小，并将大小和当前更新次数封装为 Sample 对象加入队列，但队列只保留最近的两个采样点，用于 `estimateSize` 方法估计大小。下一次采样时机由 `nextSampleNum = ⌈numUpdates × SAMPLE_GROWTH_RATE⌉` 决定，其中 `SAMPLE_GROWTH_RATE = 1.1`，是一个**很缓慢的指数退避**：前期几乎每次更新都会采样（1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, …），随着更新次数变大才会逐渐稀疏，从而既保证估算精度，又摊销 `SizeEstimator` 的开销。
2. **估计大小（`estimateSize` 方法）**：廉价操作，**当前估计大小 = 最近一次采样的实际大小 + 估计增量**，其中，估计增量 = 每次更新的平均字节增量（来自最近两个采样点） * 自上次采样以来的更新次数。

```scala
// 一个通用接口，供集合跟踪其估计的字节大小
// 我们使用 SizeEstimator 按照缓慢的指数退避（exponential back-off）进行采样以摊销时间开销，因为每次调用 SizeEstimator 都比较昂贵（大约几毫秒级别）
private[spark] trait SizeTracker {

  import SizeTracker._

  // 控制用于决定采样速率的指数基数。例如，取值为 2 时表示我们会在第 1、2、4、8、… 个元素处进行采样
  private val SAMPLE_GROWTH_RATE = 1.1

  // 自上次调用 resetSamples() 以来的采样，仅保留最后两个样本用于外推
  private val samples = new mutable.Queue[Sample]

  // 在最近两次采样之间，每次更新的平均字节数
  private var bytesPerUpdate: Double = _

  // 自上次调用 resetSamples() 以来，对 map 的插入和更新总次数
  private var numUpdates: Long = _

  // numUpdates 达到该值时，我们将进行下一次采样
  private var nextSampleNum: Long = _

  resetSamples()

  // 重置迄今为止收集的样本，当集合大小发生显著变化后，应调用此方法
  protected def resetSamples(): Unit = {
    numUpdates = 1
    nextSampleNum = 1
    samples.clear()
    takeSample()
  }

  // 每次更新后调用的回调（Callback）
  protected def afterUpdate(): Unit = {
    numUpdates += 1
    if (nextSampleNum == numUpdates) {
      takeSample()
    }
  }

  // 对当前集合大小进行新的采样
  private def takeSample(): Unit = {
    samples.enqueue(Sample(SizeEstimator.estimate(this), numUpdates))
    // 仅使用最近两个样本进行外推
    if (samples.size > 2) {
      samples.dequeue()
    }
    val bytesDelta = samples.toList.reverse match {
      case latest :: previous :: tail =>
        (latest.size - previous.size).toDouble / (latest.numUpdates - previous.numUpdates)
      // 如果样本少于 2 个，则假定没有变化
      case _ => 0
    }
    bytesPerUpdate = math.max(0, bytesDelta)
    nextSampleNum = math.ceil(numUpdates * SAMPLE_GROWTH_RATE).toLong
  }

  // 估算集合的当前大小（以字节为单位），时间复杂度：O(1)
  def estimateSize(): Long = {
    assert(samples.nonEmpty)
    // 上次采样大小 + 最近两个样本进行外推的大小
    val extrapolatedDelta = bytesPerUpdate * (numUpdates - samples.last.numUpdates)
    (samples.last.size + extrapolatedDelta).toLong
  }
}

private object SizeTracker {
  case class Sample(size: Long, numUpdates: Long)
}
```





# 3. ExternalAppendOnlyMap

AppendOnlyMap 优点是能将聚合和排序结合在一起 ，缺点是只能使用内存，难以适用于内存不足的情况。为了解决这个问题，**Spark 基于 AppendOnlyMap 设计实现了基于内存 + 磁盘的 ExternalAppendOnlyMap，用于 Shuffle Read 端大规模数据聚合。同时，由于 Shuffle Write 端聚合需要考虑 partitionId，Spark 也设计了带有 partitionId 的 ExternalAppendOnlyMap，名为 PartitionedAppendOnlyMap，这两个数据结构功能类似**。

ExternalAppendOnlyMap 工作原理是，先持有一个 AppendOnlyMap 来不断**接收和聚合**新来的 record，AppendOnlyMap 快被装满时检查一下内存剩余空间是否可以扩展，可以则直接在内存中扩展，**否则对其中的 record 进行排序（排序是为了方便下一步全局聚合），然后将 record 都溢写到磁盘上**。因为 record 不断到来，可能会多次填满 AppendOnlyMap，所以这个溢写过程可以出现多次，最终形成多个溢写文件。**等 record 都处理完，ExternalAppendOnlyMap 将内存中 AppendOnlyMap 的数据与磁盘上溢写文件中的数据进行全局聚合**，得到最终结果。

1. **AppendOnlyMap 的大小估计（`SizeTrackingAppendOnlyMap` 类）**：AppendOnlyMap 数组里存放的是 key 和 value 的引用，并不是它们实际对象（object）的大小，且 value 会不断被更新，实际大小不断变化，什么时候会超过内存限制呢？Spark 设计了一个增量式的高效估算算法，复杂度是 O(1)，它会定期对当前 AppendOnlyMap 中的 record 进行抽样，然后精确计算这些 record 的总大小、总个数 、更新个数及平均值等，并作为历史统计值。之后，每当有 record 插入或更新时，会根据历史统计值和历史平均的变化值，增量估算 AppendOnlyMap 的总大小。

2. **溢写过程与排序（`spill` 方法）**：当 AppendOnlyMap 达到内存限制时，会将 record 排序后写入磁盘中。排序是为了方便下一步全局聚合时可以采用更高效的 merge-sort（外部排序 + 聚合），问题是根据什么对 record 进行排序呢？对于定义了按照 key 排序的 sortByKey 等操作，可以根据 record 的 key 进行排序，但是对于大部分操作，如 groupByKey，并没有定义 key 的排序方法。**因此，Spark 采用按照 key 的哈希值进行排序。**

   > 关于是否溢写的判定（`Spillable.maybeSpill`），有 3 个值得注意的设计：
   >
   > - **每读 32 条记录才检查一次**：判定条件 `elementsRead % 32 == 0 && currentMemory >= myMemoryThreshold`，避免每次插入都做一次 `estimateSize + acquireMemory` 调用。
   > - **先扩内存再溢写**：达到当前阈值时，会先尝试向 `TaskMemoryManager` 申请加倍内存（`amountToRequest = 2 * currentMemory - myMemoryThreshold`），申请到则继续在内存累加；申请不到才真正 spill。
   > - **元素数兜底**：还存在硬上限，参数 `spark.shuffle.spill.numElementsForceSpillThreshold`，默认 `Integer.MAX_VALUE`），用于防御性地强制溢写。

3. **全局聚合（`ExternalIterator` 类）**：**建立一个最小堆或最大堆，每次从各个溢写文件中读取前几个具有相同 key 哈希值的 record，然后与 AppendOnlyMap 中的 record 进行聚合，并输出聚合后的结果**。由于存在哈希冲突，即不同 key 具有相同哈希值，因此 Spark 会同时比较 key 的哈希值，以及实际值是否相等。下图中，Spark 分别从 4 个溢写文件中提取第 1 个 record，与还留在 AppendOnlyMap 中的第 1 个 record 组成最小堆，然后不断从最小堆中提取具有相同 key 的 record 进行聚合。接着，Spark 继续读取溢写文件及 AppendOnlyMap 中的 record 填充最小堆，直到所有 record 处理完成。由于每个溢写文件中的 record 是经过排序的，按顺序读取和聚合可以保证对每个 record 进行全局聚合。 

![ExternalAppendOnlyMap](./images/ExternalAppendOnlyMap.png)

ExternalAppendOnlyMap 详细工作流程如下：

1. **聚合阶段**：数据插入内存中的 SizeTrackingAppendOnlyMap，使用 `createCombiner` 和 `mergeValue` 函数进行聚合，实时监控内存使用，超过阈值时触发溢写磁盘。
2. **溢写处理**：对内存中的数据按 key 的哈希值进行排序，分批写入磁盘临时文件，创建 DiskMapIterator 管理磁盘数据。
3. **合并阶段**：ExternalIterator 创建优先队列，对于溢写文件与内存中的剩余数据，按哈希值顺序合并相同 key 的数据，使用 `mergeCombiners` 函数最终合并。

总结：ExternalAppendOnlyMap 是一个高性能的 HashMap，只支持数据插入和更新，但可以同时利用内存和磁盘对大规模数据进行聚合和排序，满足了 Shuffle Read 阶段数据聚合、排序的需求。

```scala
// 一个仅追加的 map，当没有足够空间让其继续增长时，会将已排序的内容溢写到磁盘。map 对数据执行两次处理：
// 1.将值合并为组合器（combiners），对其进行排序，并在必要时溢写到磁盘
// 2.从磁盘读取这些组合器（combiners），并将它们合并在一起
// 溢写阈值的设置权衡：如果阈值设置得过高，内存中的映射可能会占用超过可用内存的空间，导致 OOM。如果阈值设置得过低，则会频繁溢写并产生不必要的磁盘写入。与不溢写的 AppendOnlyMap 的正常情况相比，这可能导致性能下降
// K、V、C 分别表示键、值、组合器（用于存储相同键的所有值的聚合结果）
class ExternalAppendOnlyMap[K, V, C](
    createCombiner: V => C,	// 为第一个值创建初始组合器
    mergeValue: (C, V) => C,	// 将新值合并到现有组合器中
    mergeCombiners: (C, C) => C,	// 合并两个组合器（在溢写合并时使用）
    serializer: Serializer = SparkEnv.get.serializer,
    blockManager: BlockManager = SparkEnv.get.blockManager,
    context: TaskContext = TaskContext.get(),
    serializerManager: SerializerManager = SparkEnv.get.serializerManager)
  extends Spillable[SizeTracker](context.taskMemoryManager())
  with Serializable
  with Logging
  with Iterable[(K, C)] {

  // 存储当前内存中的键值对，使用 SizeTracker 跟踪内存使用情况
  @volatile private[collection] var currentMap = new SizeTrackingAppendOnlyMap[K, C]
  // 存储所有溢写到磁盘的数据文件迭代器
  private val spilledMaps = new ArrayBuffer[DiskMapIterator]
  private val sparkConf = SparkEnv.get.conf
  private val diskBlockManager = blockManager.diskBlockManager

  // 从序列化器读/写时对象批次的大小，参数 spark.shuffle.spill.batchSize 默认为 10000
  // 对象按批写入，每个批次使用独立的序列化流，这可以减少在反序列化流时构建的引用跟踪 map 的大小
  // 注意：将此值设置得过低会在序列化时引起过多复制，因为某些序列化器在对象数量每次翻倍时通过扩容+复制来增长其内部数据结构
  private val serializerBatchSize = sparkConf.get(config.SHUFFLE_SPILL_BATCH_SIZE)

  // 已溢写的总字节数
  private var _diskBytesSpilled = 0L
  def diskBytesSpilled: Long = _diskBytesSpilled

  // 参数 spark.shuffle.file.buffer 默认为 32k，表示每个 shuffle 文件输出流的内存缓冲区大小，单位为 KiB（除非另有说明），这些缓冲区可在创建中间 shuffle 文件时减少磁盘寻道和系统调用次数
  private val fileBufferSize = sparkConf.get(config.SHUFFLE_FILE_BUFFER_SIZE).toInt * 1024

  // 写指标
  private val writeMetrics: ShuffleWriteMetrics = new ShuffleWriteMetrics()

  // 到目前为止观测到的内存 map 的峰值大小（以字节为单位）
  private var _peakMemoryUsedBytes: Long = 0L
  def peakMemoryUsedBytes: Long = _peakMemoryUsedBytes

  // 按照 key 的哈希值排序
  private val keyComparator = new HashComparator[K]
  private val ser = serializer.newInstance()

  @volatile private var readingIterator: SpillableIterator = null

  // 此 map 到目前为止已溢写的文件数
  private[collection] def numSpills: Int = spilledMaps.size
 
  // 将给定的键和值插入到 map 中
  def insert(key: K, value: V): Unit = {
    insertAll(Iterator((key, value)))
  }

  // 将给定的键和值的迭代器插入到 map 中。当底层映射需要扩容时，检查全局 shuffle 内存池是否有足够空间。如果有，则为 map 扩容分配所需内存；否则，将内存中的 map 溢写到磁盘。前 trackMemoryThreshold 条目占用的 shuffle 内存不计入统计。
  def insertAll(entries: Iterator[Product2[K, V]]): Unit = {
    if (currentMap == null) {
      throw new IllegalStateException(
        "Cannot insert new elements into a map after calling iterator")
    }
    // 当前条目
    var curEntry: Product2[K, V] = null
    // 用于 map 的更新函数，我们在各个条目间重用它，以避免每次都分配新的闭包
    val update: (Boolean, C) => C = (hadVal, oldVal) => {
      if (hadVal) mergeValue(oldVal, curEntry._2) else createCombiner(curEntry._2)
    }

    while (entries.hasNext) {
      curEntry = entries.next()
      val estimatedSize = currentMap.estimateSize()
      if (estimatedSize > _peakMemoryUsedBytes) {
        _peakMemoryUsedBytes = estimatedSize
      }
      // 检查是否需要溢写，如果发生溢写，则创建新的 SizeTrackingAppendOnlyMap
      if (maybeSpill(currentMap, estimatedSize)) {
        currentMap = new SizeTrackingAppendOnlyMap[K, C]
      }
      // 通过 AppendOnlyMap 不断接收和聚合值
      currentMap.changeValue(curEntry._1, update)
      addElementsRead()
    }
  }

  // 对内存中 map 的现有内容进行排序，并将其溢写到磁盘上的临时文件
  override protected[this] def spill(collection: SizeTracker): Unit = {
    // 按照 key 的哈希值排序，然后溢写磁盘
    val inMemoryIterator = currentMap.destructiveSortedIterator(keyComparator)
    val diskMapIterator = spillMemoryIteratorToDisk(inMemoryIterator)
    spilledMaps += diskMapIterator
  }

  // 强制将当前内存中的集合溢写到磁盘以释放内存；当任务内存不足时，TaskMemoryManager 会调用此方法
  override protected[this] def forceSpill(): Boolean = {
    if (readingIterator != null) {
      val isSpilled = readingIterator.spill()
      if (isSpilled) {
        currentMap = null
      }
      isSpilled
    } else if (currentMap.size > 0) {
      spill(currentMap)
      currentMap = new SizeTrackingAppendOnlyMap[K, C]
      true
    } else {
      false
    }
  }

  // 将内存中的 Iterator 溢写到磁盘上的临时文件
  private[this] def spillMemoryIteratorToDisk(inMemoryIterator: Iterator[(K, C)])
      : DiskMapIterator = {
    val (blockId, file) = diskBlockManager.createTempLocalBlock()
    val writer = blockManager.getDiskWriter(blockId, file, ser, fileBufferSize, writeMetrics)
    var objectsWritten = 0

    // 按写入磁盘顺序的批次大小（字节）列表
    val batchSizes = new ArrayBuffer[Long]

    // 将磁盘写入器的内容刷新到磁盘，并更新相关的变量
    def flush(): Unit = {
      val segment = writer.commitAndGet()
      batchSizes += segment.length
      _diskBytesSpilled += segment.length
      objectsWritten = 0
    }

    var success = false
    try {
      while (inMemoryIterator.hasNext) {
        val kv = inMemoryIterator.next()
        writer.write(kv._1, kv._2)
        objectsWritten += 1

        if (objectsWritten == serializerBatchSize) {
          flush()
        }
      }
      if (objectsWritten > 0) {
        flush()
        writer.close()
      } else {
        writer.revertPartialWritesAndClose()
      }
      success = true
    } finally {
      if (!success) {
        // 这段代码路径仅在上面设置 success 之前抛出异常时才会执行；关闭我们的资源并让异常继续向上抛出
        writer.closeAndDelete()
      }
    }

    new DiskMapIterator(file, blockId, batchSizes)
  }

  // 返回一个用于遍历此 map 的破坏性迭代器。如果由于内存不足该迭代器被强制溢写到磁盘以释放内存，则它将从磁盘上的 map 中返回键值对
  def destructiveIterator(inMemoryIterator: Iterator[(K, C)]): Iterator[(K, C)] = {
    readingIterator = new SpillableIterator(inMemoryIterator)
    readingIterator.toCompletionIterator
  }

  // 返回一个会破坏原结构的迭代器，该迭代器将内存中的 map 与已溢写的 map 合并。如果未发生溢写，则直接返回内存 map 的迭代器
  override def iterator: Iterator[(K, C)] = {
    if (currentMap == null) {
      throw new IllegalStateException(
        "ExternalAppendOnlyMap.iterator is destructive and should only be called once.")
    }
    if (spilledMaps.isEmpty) {
      destructiveIterator(currentMap.iterator)	 // 只有内存数据
    } else {
      new ExternalIterator()	// 合并内存和磁盘数据
    }
  }

  private def freeCurrentMap(): Unit = {
    if (currentMap != null) {
      currentMap = null // 这样内存才可以被垃圾回收
      releaseMemory()
    }
  }

  // ===================================================================
  // 包括共 3 个迭代器，作用如下：
  // 1. ExternalIterator 使用堆来合并内存（SpillableIterator）、磁盘（DiskMapIterator）中的数据
  // 2. DiskMapIterator 从磁盘溢写文件中分批读取排序后的键值对数据
  // 3. SpillableIterator 若未发生溢写，遍历等价于 AppendOnlyMap.iterator；若发生溢写（由TaskMemoryManager触发），遍历等价于 DiskMapIterator
  // ===================================================================
  // 一个迭代器，将内存中的 map 与已溢写的 map 中的 (K, C) 对进行外部归并排序
  private class ExternalIterator extends Iterator[(K, C)] {

    // 使用优先队列（最小堆）来管理多个输入流，每个输入流对应一个 StreamBuffer，包含相同哈希码的键值对
    private val mergeHeap = new mutable.PriorityQueue[StreamBuffer]

    // 输入流既来自内存中的 map，也来自溢写磁盘的 map，所有输入流都转换为缓冲迭代器
    // 内存中的 sortedMap 是就地排序的，而已溢写的 spilledMaps 已经按哈希码排序
    private val sortedMap = destructiveIterator(
      currentMap.destructiveSortedIterator(keyComparator))
    private val inputStreams = (Seq(sortedMap) ++ spilledMaps).map(it => it.buffered)

    inputStreams.foreach { it =>
      val kcPairs = new ArrayBuffer[(K, C)]
      readNextHashCode(it, kcPairs)
      if (kcPairs.length > 0) {
        mergeHeap.enqueue(new StreamBuffer(it, kcPairs))
      }
    }

    // 填充缓冲区，读取来自给定迭代器的下一组具有相同哈希码的键
    // 我们按哈希码逐次读取流，以确保在合并时不会遗漏元素，假定给定的迭代器已按哈希码排序
    // it 表示要读取的迭代器，buf 表示用于写入结果的缓冲区
    private def readNextHashCode(it: BufferedIterator[(K, C)], buf: ArrayBuffer[(K, C)]): Unit = {
      if (it.hasNext) {
        var kc = it.next()
        buf += kc
        val minHash = hashKey(kc)
        while (it.hasNext && it.head._1.hashCode() == minHash) {
          kc = it.next()
          buf += kc
        }
      }
    }

    // 如果给定的缓冲区包含指定键的值，则将该值合并到 baseCombiner 中，并从缓冲区中移除对应的 (K, C) 对
    private def mergeIfKeyExists(key: K, baseCombiner: C, buffer: StreamBuffer): C = {
      var i = 0
      while (i < buffer.pairs.length) {
        val pair = buffer.pairs(i)
        // 注意，因为存在哈希冲突，所以这里进行实际的 key 值比较
        if (pair._1 == key) {
          // 注意：缓冲区中对于同一 key 最多只有一对键值对，因为我们在溢写之前总是在 map 内进行合并（insertAll方法更新值时，调用了createCombiner方法），所以在找到第一个匹配项后立即返回是安全的
          removeFromBuffer(buffer.pairs, i)
          return mergeCombiners(baseCombiner, pair._2)
        }
        i += 1
      }
      baseCombiner
    }

    // 以常数时间从 ArrayBuffer 中移除第 index 个元素，通过将另一个元素交换到该位置
    // 这样比 ArrayBuffer.remove 更高效，因为不需要移动数组中其余元素
    // 对于我们的数组缓冲区可行，因为我们不关心内部元素的顺序，只需在其中搜索某个键
    private def removeFromBuffer[T](buffer: ArrayBuffer[T], index: Int): T = {
      val elem = buffer(index)
      buffer(index) = buffer(buffer.size - 1)  // 如果 index == buffer.size - 1 也有效
      buffer.trimEnd(1)
      elem
    }

    // 如果仍存在包含未访问键值对的输入流，则返回 true
    override def hasNext: Boolean = mergeHeap.nonEmpty

    // 选择具有最小哈希值的键，然后将来自所有输入流中该键对应的所有值合并
    override def next(): (K, C) = {
      if (mergeHeap.isEmpty) {
        throw new NoSuchElementException
      }
      // 从 StreamBuffer 中选择最小哈希值的键
      val minBuffer = mergeHeap.dequeue()
      val minPairs = minBuffer.pairs
      val minHash = minBuffer.minKeyHash
      val minPair = removeFromBuffer(minPairs, 0)
      val minKey = minPair._1
      var minCombiner = minPair._2
      assert(hashKey(minPair) == minHash)

      // 对于所有可能包含此键的其他输入流（即键的哈希值与最小哈希值相同的流），将该流中对应的值合并进来
      val mergedBuffers = ArrayBuffer[StreamBuffer](minBuffer)
      while (mergeHeap.nonEmpty && mergeHeap.head.minKeyHash == minHash) {
        val newBuffer = mergeHeap.dequeue()
        minCombiner = mergeIfKeyExists(minKey, minCombiner, newBuffer)
        mergedBuffers += newBuffer
      }

      // 对每个已访问的流缓冲区重新填充；如果缓冲区非空，则将其重新加入队列
      mergedBuffers.foreach { buffer =>
        if (buffer.isEmpty) {
          readNextHashCode(buffer.iterator, buffer.pairs)
        }
        if (!buffer.isEmpty) {
          mergeHeap.enqueue(buffer)
        }
      }

      (minKey, minCombiner)
    }

    // 用于从按 key 哈希排序的 map 迭代器（内存中或磁盘上）流式读取的缓冲区
    // 每个缓冲区维护流中当前具有最低哈希码的所有键值对。如果发生哈希冲突，可能会有多个键
    // 注意，由于在溢写数据时我们每个键只写出一个值，因此每个键最多只有一个元素
    // StreamBuffer 按其流中当前可用的最小键哈希进行排序，以便可以将它们放入堆中并进行排序
    private class StreamBuffer(
        val iterator: BufferedIterator[(K, C)],
        val pairs: ArrayBuffer[(K, C)])
      extends Comparable[StreamBuffer] {

      def isEmpty: Boolean = pairs.length == 0

      // 如果该流中没有更多对，则无效
      def minKeyHash: Int = {
        assert(pairs.length > 0)
        hashKey(pairs.head)
      }

      override def compareTo(other: StreamBuffer): Int = {
        // 降序，因为 mutable.PriorityQueue 出队的是最大值，而不是最小值
        if (other.minKeyHash < minKeyHash) -1 else if (other.minKeyHash == minKeyHash) 0 else 1
      }
    }
  }

  // ===================================================================
  // 一个迭代器，从磁盘上的 map 中按排序顺序返回 (K, C) 对
  private class DiskMapIterator(file: File, blockId: BlockId, batchSizes: ArrayBuffer[Long])
    extends Iterator[(K, C)]
  {
    // 大小将是 batchSize.length + 1
    private val batchOffsets = batchSizes.scanLeft(0L)(_ + _)

    private var batchIndex = 0  // 当前批次
    private var fileStream: FileInputStream = null

    // 一个中间流，仅从单个批次读取，这可以防止上层流进行预取或其他任意行为
    private var deserializeStream: DeserializationStream = null
    private var batchIterator: Iterator[(K, C)] = null
    private var objectsRead = 0

    // 构建一个只从下一个批次读取的流
    private def nextBatchIterator(): Iterator[(K, C)] = {
      // 注意 batchOffsets.length = numBatches + 1，因为我们在上面进行了扫描；检查我们是否仍然位于有效的批次中
      if (batchIndex < batchOffsets.length - 1) {
        if (deserializeStream != null) {
          deserializeStream.close()
          fileStream.close()
          deserializeStream = null
          fileStream = null
        }

        val start = batchOffsets(batchIndex)
        fileStream = new FileInputStream(file)
        fileStream.getChannel.position(start)
        batchIndex += 1

        val end = batchOffsets(batchIndex)

        assert(end >= start, "start = " + start + ", end = " + end +
          ", batchOffsets = " + batchOffsets.mkString("[", ", ", "]"))
        // BufferedInputStream 缓冲提高读取效率
        val bufferedStream = new BufferedInputStream(ByteStreams.limit(fileStream, end - start))
        // wrapStream 处理加密和压缩数据
        val wrappedStream = serializerManager.wrapStream(blockId, bufferedStream)
        // DeserializationStream 反序列化数据
        deserializeStream = ser.deserializeStream(wrappedStream)
        deserializeStream.asKeyValueIterator.asInstanceOf[Iterator[(K, C)]]
      } else {
        // 没有更多批次了
        cleanup()
        null
      }
    }

    // 从反序列化流中返回下一个 (K, C) 对。如果当前批次已耗尽，则为下一个批次构建一个流并从中读取；如果没有更多的对，返回 null
    private def readNextItem(): (K, C) = {
      val item = batchIterator.next()
      objectsRead += 1
      if (objectsRead == serializerBatchSize) {
        objectsRead = 0
        batchIterator = nextBatchIterator()
      }
      item
    }

    override def hasNext: Boolean = {
      if (batchIterator == null) {
        // batchIterator 尚未初始化
        batchIterator = nextBatchIterator()
        if (batchIterator == null) {
          return false
        }
      }
      batchIterator.hasNext
    }

    override def next(): (K, C) = {
      if (!hasNext) {
        throw new NoSuchElementException
      }
      readNextItem()
    }

    private def cleanup(): Unit = {
      // ...
    }

    context.addTaskCompletionListener[Unit](context => cleanup())
  }

  // ===================================================================
  // 在内存不足时自动将数据溢写磁盘。若未发生溢写，遍历等价于 AppendOnlyMap.iterator；若发生溢写（由TaskMemoryManager触发），遍历等价于 DiskMapIterator
  private class SpillableIterator(var upstream: Iterator[(K, C)])
    extends Iterator[(K, C)] {

    private val SPILL_LOCK = new Object()

    private var cur: (K, C) = readNext()

    private var hasSpilled: Boolean = false

    def spill(): Boolean = SPILL_LOCK.synchronized {
      if (hasSpilled) {
        false
      } else {
        logInfo(s"Task ${context.taskAttemptId} force spilling in-memory map to disk and " +
          s"it will release ${org.apache.spark.util.Utils.bytesToString(getUsed())} memory")
        val nextUpstream = spillMemoryIteratorToDisk(upstream)
        assert(!upstream.hasNext)
        hasSpilled = true
        upstream = nextUpstream
        true
      }
    }

    private def destroy(): Unit = {
      freeCurrentMap()
      upstream = Iterator.empty
    }

    def toCompletionIterator: CompletionIterator[(K, C), SpillableIterator] = {
      CompletionIterator[(K, C), SpillableIterator](this, this.destroy)
    }

    def readNext(): (K, C) = SPILL_LOCK.synchronized {
      if (upstream.hasNext) {
        upstream.next()
      } else {
        null
      }
    }

    override def hasNext(): Boolean = cur != null

    override def next(): (K, C) = {
      val r = cur
      cur = readNext()
      r
    }
  }

  // 便捷函数，根据 key 对给定的 (K, C) 对进行哈希
  private def hashKey(kc: (K, C)): Int = ExternalAppendOnlyMap.hash(kc._1)
}

private[spark] object ExternalAppendOnlyMap {
  // 返回给定对象的哈希值。如果对象为 null，则返回一个特殊的哈希值
  private def hash[T](obj: T): Int = {
    if (obj == null) 0 else obj.hashCode()
  }

  // 一个比较器，根据 key 哈希值对任意 key 进行排序
  private class HashComparator[K] extends Comparator[K] {
    def compare(key1: K, key2: K): Int = {
      val hash1 = hash(key1)
      val hash2 = hash(key2)
      if (hash1 < hash2) -1 else if (hash1 == hash2) 0 else 1
    }
  }
}
```





# 4. PartitionedAppendOnlyMap

**PartitionedAppendOnlyMap 用于在 Shuffle Write 端对 record 进行聚合 （combine），它的功能和实现与 ExternalAppendOnlyMap 的功能和实现基本一样，唯一区别是它的 key 是“partitionId + key”**，这样既可以根据 partitionId 进行排序，也可以根据 partitionId + key 进行排 序，从而在 Shuffle Write 阶段可以进行聚合、排序和分区。

```scala
// 继承关系：PartitionedAppendOnlyMap -> SizeTrackingAppendOnlyMap -> AppendOnlyMap
// 实现了 WritablePartitionedPairCollection 的类，封装了一个 map，它的键是 (partitionID, K) 元组
private[spark] class PartitionedAppendOnlyMap[K, V]
  extends SizeTrackingAppendOnlyMap[(Int, K), V] with WritablePartitionedPairCollection[K, V] {

  def partitionedDestructiveSortedIterator(keyComparator: Option[Comparator[K]])
    : Iterator[((Int, K), V)] = {
    // 用于 (partitionID, K) 对的比较器，其中 partitionKeyComparator 按照 partitionID 和 key 进行排序；partitionComparator 仅按照 partitionID 进行排序
    val comparator = keyComparator.map(partitionKeyComparator).getOrElse(partitionComparator)
    // 底层调用 AppendOnlyMap 的 destructiveSortedIterator 方法
    destructiveSortedIterator(comparator)
  }

  def insert(partition: Int, key: K, value: V): Unit = {
    // 底层调用 AppendOnlyMap 的 update 方法
    update((partition, key), value)
  }
}
```

```scala
// 用于跟踪大小（size-tracking）的键值对集合的通用接口，这些集合：
// 1. 为每个键值对关联一个分区
// 2. 支持内存高效的排序迭代器
// 3. 支持 WritablePartitionedIterator，可将内容以字节形式直接写出到磁盘
private[spark] trait WritablePartitionedPairCollection[K, V] {
  // 向集合中插入一个带分区的键值对
  def insert(partition: Int, key: K, value: V): Unit

  // 先按分区 ID，后按给定比较器的顺序遍历数据，此操作可能会破坏底层集合
  def partitionedDestructiveSortedIterator(keyComparator: Option[Comparator[K]])
    : Iterator[((Int, K), V)]

  // 遍历数据并将元素写出而不是返回它们。先按分区 ID，后按给定比较器的顺序返回，这可能会破坏底层集合
  def destructiveSortedWritablePartitionedIterator(keyComparator: Option[Comparator[K]])
    : WritablePartitionedIterator[K, V] = {
    val it = partitionedDestructiveSortedIterator(keyComparator)
    new WritablePartitionedIterator[K, V](it)
  }
}

private[spark] object WritablePartitionedPairCollection {
  // 用于 (Int, K) 对的比较器，仅按分区 ID 对它们进行排序
  def partitionComparator[K]: Comparator[(Int, K)] = (a: (Int, K), b: (Int, K)) => a._1 - b._1

  // 用于 (Int, K) 对的比较器，按照分区 ID 和键对它们进行排序
  def partitionKeyComparator[K](keyComparator: Comparator[K]): Comparator[(Int, K)] =
    (a: (Int, K), b: (Int, K)) => {
      val partitionDiff = a._1 - b._1
      if (partitionDiff != 0) {
        partitionDiff
      } else {
        keyComparator.compare(a._2, b._2)
      }
    }
}

// 将元素写入 DiskBlockObjectWriter 的迭代器，而不是返回它们，每个元素都有一个关联的分区
private[spark] class WritablePartitionedIterator[K, V](it: Iterator[((Int, K), V)]) {
  private[this] var cur = if (it.hasNext) it.next() else null

  def writeNext(writer: PairsWriter): Unit = {
    // 只写入 key、value，不写入分区 ID
    writer.write(cur._1._2, cur._2)
    cur = if (it.hasNext) it.next() else null
  }

  def hasNext: Boolean = cur != null

  def nextPartition(): Int = cur._1._1
}
```





# 5. PartitionedPairBuffer

**PartitionedPairBuffer 用于 Shuffle Write 和 Shuffle Read 端排序，其本质是一个基于内存 + 磁盘的 Array**，随着数据添加，不断地扩容，当到达内存限制时，就将 Array 中的数据按照 partitionId 或 partitionId + key 进行排序，然后溢写到磁盘上，该过程可以进行多次，最后对内存中和磁盘上的数据进行全局排序，输出或者提供给下一个操作。

```scala
// 只追加（append-only）的键值对缓冲区，每个键值对都有对应的分区 ID，并跟踪其估计的字节大小
// 该缓冲区最多可容纳 (Integer.MAX_VALUE - 15) / 2 = 1073741816 个元素
private[spark] class PartitionedPairBuffer[K, V](initialCapacity: Int = 64)
  extends WritablePartitionedPairCollection[K, V] with SizeTracker
{
  import PartitionedPairBuffer._

  // 基本的可增长数组数据结构。我们使用单个 AnyRef 数组同时存放键和值，这样可以配合 KVArraySortDataFormat 对它们进行高效排序
  private var capacity = initialCapacity
  private var curSize = 0
  private var data = new Array[AnyRef](2 * initialCapacity)

  // 向缓冲区添加一个元素
  def insert(partition: Int, key: K, value: V): Unit = {
    if (curSize == capacity) {
      growArray()
    }
    // 键是 (partitionID, K) 的元组
    data(2 * curSize) = (partition, key.asInstanceOf[AnyRef])
    data(2 * curSize + 1) = value.asInstanceOf[AnyRef]
    curSize += 1
    afterUpdate()
  }

  // 因为已达到容量，将数组大小翻倍
  private def growArray(): Unit = {
    if (capacity >= MAXIMUM_CAPACITY) {
      throw new IllegalStateException(s"Can't insert more than ${MAXIMUM_CAPACITY} elements")
    }
    val newCapacity =
      if (capacity * 2 > MAXIMUM_CAPACITY) { // 溢出
        MAXIMUM_CAPACITY
      } else {
        capacity * 2
      }
    // 开辟新缓冲区，然后拷贝原缓冲区的数据
    val newArray = new Array[AnyRef](2 * newCapacity)
    System.arraycopy(data, 0, newArray, 0, 2 * capacity)
    data = newArray
    capacity = newCapacity
    resetSamples()
  }

  // 以给定顺序遍历数据。对于此类而言，这并不是真正的破坏性操作
  override def partitionedDestructiveSortedIterator(keyComparator: Option[Comparator[K]])
    : Iterator[((Int, K), V)] = {
    // 用于 (partitionID, K) 对的比较器，其中 partitionKeyComparator 按照 partitionID 和 key 进行排序；partitionComparator 仅按照 partitionID 进行排序
    val comparator = keyComparator.map(partitionKeyComparator).getOrElse(partitionComparator)
    // 按照指定 Comparator，对 data 进行排序。底层采用“稳定、自适应、迭代的归并排序”，参考 java.util.Comparator.TimSort 类实现
    new Sorter(new KVArraySortDataFormat[(Int, K), AnyRef]).sort(data, 0, curSize, comparator)
    iterator
  }

  private def iterator(): Iterator[((Int, K), V)] = new Iterator[((Int, K), V)] {
    var pos = 0

    override def hasNext: Boolean = pos < curSize

    override def next(): ((Int, K), V) = {
      if (!hasNext) {
        throw new NoSuchElementException
      }
      val pair = (data(2 * pos).asInstanceOf[(Int, K)], data(2 * pos + 1).asInstanceOf[V])
      pos += 1
      pair
    }
  }
}

private object PartitionedPairBuffer {
  // 最大容量：(Integer.MAX_VALUE - 15) / 2 = 1073741816
  // 原因：一些 JVM 无法分配长度为 Integer.MAX_VALUE 的数组，实际可分配的最大长度要小一些
  val MAXIMUM_CAPACITY: Int = ByteArrayMethods.MAX_ROUNDED_ARRAY_LENGTH / 2
}

```





# 6. ExternalSorter

实际上，**PartitionedAppendOnlyMap 和 PartitionedPairBuffer 只是基于内存的操作，它们必须配合 ExternalSorter 才能实现溢写磁盘、外部排序的功能**。ExternalSorter 的工作流程与 ExternalAppendOnlyMap 基本一样，详细工作流程如下：

1. **接收/聚合阶段**：我们反复填充内存数据缓冲区，**如果需要按键合并（combine）则使用 PartitionedAppendOnlyMap，否则使用 PartitionedPairBuffer**。为了避免对每个键多次调用分区器，我们将分区 ID 与每条记录一并存储（即将分区 ID 与键的元组作为 key 存储）。
2. **溢写阶段**：当缓冲区达到内存限制时，我们将其溢写到文件。**溢写文件前，缓冲区首先按分区 ID 排序（一定执行）**，是否还要在分区内对 key 排序，取决于 `aggregator` 与 `ordering` 是否提供。对于每个溢写文件，我们记录内存中每个分区的对象数量，这样在合并时就不必为每个元素都写出分区 ID。
      - 提供了 `ordering`（如 `sortByKey`），**则分区内按 `ordering` 给出的全序对 key 排序**；
      - 提供了 `aggregator` 但无 `ordering`（如 `reduceByKey`），**则分区内按 key 的哈希值排序（部分序，相等的哈希再在合并阶段做实际相等性比较）**；
      - 二者都未提供（如 map 端无 combine 的普通 shuffle），**则只按分区 ID 排序，不参与 key 比较**。
3. **合并阶段**：当用户请求迭代器或文件输出时，将合并所有已溢写的文件以及任何剩余的内存数据，合并时使用之前定义的相同排序顺序（除非排序和聚合同时被禁用）。如果需要按键聚合，我们要么使用 ordering 参数提供的全序，要么读取具有相同哈希值的键，并比较键实际值以合并对应的值。
4. **清理阶段**：用户应在结束时调用 stop() 来删除所有中间文件。

```scala
/**
 * 对若干类型为 (K, V) 的键值对进行排序并在必要时合并，生成类型为 (K, C) 的键-合并器结果对。
 * 先使用 Partitioner 将键分组到分区，然后可选地在每个分区内使用自定义 Comparator 对键进行排序。
 * 可以输出一个包含所有分区的单一分区化文件，但为每个分区指定不同的字节范围，适用于 shuffle 拉取。
 * 如果禁用了合并（combining），则类型 C 必须等于 V，在最后我们会进行类型转换。
 *
 * 注意：尽管 ExternalSorter 是一个相当通用的排序器，但它的一些配置与基于排序的 shuffle 使用紧密相关
 * （例如块压缩由 spark.shuffle.compress 控制）。如果在非 shuffle 的场景中使用 ExternalSorter，
 * 可能需要重新审视这些配置是否合适。
 *
 * @param aggregator 可选的 Aggregator，提供用于合并数据的函数
 * @param partitioner 可选的 Partitioner，如果提供，则先按分区 ID 排序，再按键排序
 * @param ordering 可选的 Ordering，用于在每个分区内对键进行排序；应当是全序（total ordering）
 * @param serializer 在溢写到磁盘时使用的序列化器
 *
 * 注意：如果提供了 Ordering，我们将始终使用它进行排序，因此只有在确实希望输出键有序时才提供它。
 * 例如在没有 map 端合并的 map 任务中，通常希望传入 None 以避免额外排序。另一方面，如果需要做合并，
 * 提供 Ordering 比不提供更高效。
 *
 * 用户与该类的交互方式如下：
 * 1. 实例化一个 ExternalSorter。
 * 2. 使用 insertAll() 插入一组记录。
 * 3. 请求一个 iterator() 来遍历已排序/已聚合的记录，或者调用 writePartitionedMapOutput()
 *    来创建一个包含已排序/已聚合输出的文件，以供 Spark 的基于排序的 shuffle 使用。
 */
private[spark] class ExternalSorter[K, V, C](
    context: TaskContext,
    aggregator: Option[Aggregator[K, V, C]] = None,
    partitioner: Option[Partitioner] = None,
    ordering: Option[Ordering[K]] = None,
    serializer: Serializer = SparkEnv.get.serializer)
  extends Spillable[WritablePartitionedPairCollection[K, C]](context.taskMemoryManager())
  with Logging with ShuffleChecksumSupport {

  private val conf = SparkEnv.get.conf
	// 分区数，若未提供 partitioner，则分区数为1，此时不需要进行分区
  private val numPartitions = partitioner.map(_.numPartitions).getOrElse(1)
  private val shouldPartition = numPartitions > 1
  private def getPartition(key: K): Int = {
    if (shouldPartition) partitioner.get.getPartition(key) else 0
  }

  private val blockManager = SparkEnv.get.blockManager
  private val diskBlockManager = blockManager.diskBlockManager
  private val serializerManager = SparkEnv.get.serializerManager
  private val serInstance = serializer.newInstance()

  // 参数 spark.shuffle.file.buffer 默认为 32k，表示每个 shuffle 文件输出流的内存缓冲区大小，单位为 KiB（除非另有说明），这些缓冲区可在创建中间 shuffle 文件时减少磁盘寻道和系统调用次数
  private val fileBufferSize = conf.get(config.SHUFFLE_FILE_BUFFER_SIZE).toInt * 1024
  // 从序列化器读/写时对象批次的大小，参数 spark.shuffle.spill.batchSize 默认为 10000
  // 对象按批写入，每个批次使用独立的序列化流，这可以减少在反序列化流时构建的引用跟踪 map 的大小
  private val serializerBatchSize = conf.get(config.SHUFFLE_SPILL_BATCH_SIZE)

  // 在溢写之前用于在内存中存储对象的数据结构。取决于是否设置了 Aggregator，要么把对象放进
  // PartitionedAppendOnlyMap 以便合并，要么把它们存放在 PartitionedPairBuffer 数组缓冲区中
  @volatile private var map = new PartitionedAppendOnlyMap[K, C]
  @volatile private var buffer = new PartitionedPairBuffer[K, C]

  // 已溢写的总字节数
  private var _diskBytesSpilled = 0L
  def diskBytesSpilled: Long = _diskBytesSpilled

  // 到目前为止观测到的内存 map 的峰值大小（以字节为单位）
  private var _peakMemoryUsedBytes: Long = 0L
  def peakMemoryUsedBytes: Long = _peakMemoryUsedBytes

  @volatile private var isShuffleSort: Boolean = true
  private val forceSpillFiles = new ArrayBuffer[SpilledFile]
  @volatile private var readingIterator: SpillableIterator = null

  private val partitionChecksums = createPartitionChecksums(numPartitions, conf)
  def getChecksums: Array[Long] = getChecksumValues(partitionChecksums)

  // 用于在分区内对键进行排序/聚合的比较器。如果用户未提供全序（total ordering），可以使用键的哈希值
  // 来生成一个部分有序（partial ordering）。部分有序含义是：相等键 comparator.compare(k, k) = 0，
  // 但也可能存在不同的键被判为相等（返回 0），因此后续需要额外的步骤来判断真正的相等性
  private val keyComparator: Comparator[K] = ordering.getOrElse((a: K, b: K) => {
    val h1 = if (a == null) 0 else a.hashCode()
    val h2 = if (b == null) 0 else b.hashCode()
    if (h1 < h2) -1 else if (h1 == h2) 0 else 1
  })

  private def comparator: Option[Comparator[K]] = {
    // 如果既没有 aggregator 也没有 ordering，我们会忽略 keyComparator 这个比较器
    if (ordering.isDefined || aggregator.isDefined) {
      Some(keyComparator)
    } else {
      None
    }
  }

  // 一个溢写文件的信息。包括序列化器写出时每个批的字节大小数组，以及每个分区在该文件中元素数量，
  // 这些信息在合并时用于高效地定位分区
  private[this] case class SpilledFile(
    file: File,
    blockId: BlockId,
    serializerBatchSizes: Array[Long],
    elementsPerPartition: Array[Long])
  
  // 存储所有已溢写的数据文件的信息
  private val spills = new ArrayBuffer[SpilledFile]
  // 到目前为止该排序器已溢写的文件数量
  private[spark] def numSpills: Int = spills.size

  // ===================================================================
  // 接收/聚合阶段
  def insertAll(records: Iterator[Product2[K, V]]): Unit = {
    val shouldCombine = aggregator.isDefined

    if (shouldCombine) {
      // 需要聚合，则使用 AppendOnlyMap 在内存中先合并数值
      val mergeValue = aggregator.get.mergeValue
      val createCombiner = aggregator.get.createCombiner
      var kv: Product2[K, V] = null
      val update = (hadValue: Boolean, oldValue: C) => {
        if (hadValue) mergeValue(oldValue, kv._2) else createCombiner(kv._2)
      }
      while (records.hasNext) {
        addElementsRead()
        kv = records.next()
        map.changeValue((getPartition(kv._1), kv._1), update)
        maybeSpillCollection(usingMap = true)
      }
    } else {
      // 不需要聚合，则将值放入 PartitionedPairBuffer 缓冲区中
      while (records.hasNext) {
        addElementsRead()
        val kv = records.next()
        buffer.insert(getPartition(kv._1), kv._1, kv._2.asInstanceOf[C])
        maybeSpillCollection(usingMap = false)
      }
    }
  }

  // ===================================================================
  // 溢写阶段，如果需要，则将当前内存集合溢写到磁盘。usingMap 表示当前使用 map 还是 buffer
  private def maybeSpillCollection(usingMap: Boolean): Unit = {
    var estimatedSize = 0L
    if (usingMap) {
      estimatedSize = map.estimateSize()
      if (maybeSpill(map, estimatedSize)) {
        map = new PartitionedAppendOnlyMap[K, C]
      }
    } else {
      estimatedSize = buffer.estimateSize()
      if (maybeSpill(buffer, estimatedSize)) {
        buffer = new PartitionedPairBuffer[K, C]
      }
    }

    if (estimatedSize > _peakMemoryUsedBytes) {
      _peakMemoryUsedBytes = estimatedSize
    }
  }

  // 将内存集合溢写到一个已排序的文件以便后续合并使用，并把该文件加入 spills 以便之后查找
  // collection 表示正在使用的集合，无论 map 或 buffer，它们都会先按照分区分区 ID 对元素排序，
  // 然后可选地再按键排序，参考 WritablePartitionedPairCollection.partitionKeyComparator 
  override protected[this] def spill(collection: WritablePartitionedPairCollection[K, C]): Unit = {
    val inMemoryIterator = collection.destructiveSortedWritablePartitionedIterator(comparator)
    val spillFile = spillMemoryIteratorToDisk(inMemoryIterator)
    spills += spillFile
  }

  // 强制将当前内存集合溢写到磁盘以释放内存，该方法将在 TaskMemoryManager 在任务内存不足时调用
  override protected[this] def forceSpill(): Boolean = {
    if (isShuffleSort) {
      false
    } else {
      assert(readingIterator != null)
      val isSpilled = readingIterator.spill()
      if (isSpilled) {
        map = null
        buffer = null
      }
      isSpilled
    }
  }

  // 将内存迭代器的内容溢写到磁盘上的临时文件
  private[this] def spillMemoryIteratorToDisk(inMemoryIterator: WritablePartitionedIterator[K, C])
      : SpilledFile = {
    // 由于这些文件可能在 shuffle 期间被读取，它们的压缩必须由 spark.shuffle.compress 控制
    // 而不是 spark.shuffle.spill.compress，因此这里需要使用 createTempShuffleBlock；
    // 参见 SPARK-3426 获取更多背景信息
    val (blockId, file) = diskBlockManager.createTempShuffleBlock()

    // 下面这些变量在每次 flush 后会被重置
    var objectsWritten: Long = 0
    val spillMetrics: ShuffleWriteMetrics = new ShuffleWriteMetrics
    val writer: DiskBlockObjectWriter =
      blockManager.getDiskWriter(blockId, file, serInstance, fileBufferSize, spillMetrics)

    // 以写出磁盘顺序记录的批大小（字节）
    val batchSizes = new ArrayBuffer[Long]
    // 每个分区中包含的元素数量
    val elementsPerPartition = new Array[Long](numPartitions)

    // 将磁盘写入器（writer）的内容刷新到磁盘，并更新相关变量。writer 在该过程结束时会被提交（commit）
    def flush(): Unit = {
      val segment = writer.commitAndGet()
      batchSizes += segment.length
      _diskBytesSpilled += segment.length
      objectsWritten = 0
    }

    var success = false
    try {
      while (inMemoryIterator.hasNext) {
        val partitionId = inMemoryIterator.nextPartition()
        require(partitionId >= 0 && partitionId < numPartitions,
          s"partition Id: ${partitionId} should be in the range [0, ${numPartitions})")
        inMemoryIterator.writeNext(writer)
        elementsPerPartition(partitionId) += 1
        objectsWritten += 1
        // 对象按批（默认 10000）写入
        if (objectsWritten == serializerBatchSize) {
          flush()
        }
      }
      if (objectsWritten > 0) {
        flush()
        writer.close()
      } else {
        writer.revertPartialWritesAndClose()
      }
      success = true
    } finally {
      if (!success) {
        writer.closeAndDelete()
      }
    }

    SpilledFile(file, blockId, batchSizes.toArray, elementsPerPartition)
  }

  // ===================================================================
  // 合并阶段，入口方法为：iterator() 或 writePartitionedMapOutput()
  // 合并一系列已排序的文件，返回分区迭代器，然后是每个分区内部元素的迭代器，该方法可用于写出新文件或将数据返回给用户
  // 返回一个按分区分组的迭代器。对于每个分区，我们返回一个迭代器用于遍历该分区的内容，这些分区应按顺序访问（不能在不读取前面分区的情况下，跳过到后面的分区），保证按分区 ID 的顺序返回每个分区的键值对
  private def merge(spills: Seq[SpilledFile], inMemory: Iterator[((Int, K), C)])
      : Iterator[(Int, Iterator[Product2[K, C]])] = {
    val readers = spills.map(new SpillReader(_))
    val inMemBuffered = inMemory.buffered
    (0 until numPartitions).iterator.map { p =>
      val inMemIterator = new IteratorForPartition(p, inMemBuffered)
      val iterators = readers.map(_.readNextPartition()) ++ Seq(inMemIterator)
      if (aggregator.isDefined) {
        // 在分区间进行部分聚合（partial aggregation）
        (p, mergeWithAggregation(
          iterators, aggregator.get.mergeCombiners, keyComparator, ordering.isDefined))
      } else if (ordering.isDefined) {
        // 没有 aggregator，但提供了 ordering（例如 sortByKey 中的 reduce 任务），仅对元素进行排序而不尝试合并
        (p, mergeSort(iterators, ordering.get))
      } else {
        (p, iterators.iterator.flatten)
      }
    }
  }

  // 使用给定键比较器对一组 (K, C) 迭代器执行归并排序
  private def mergeSort(iterators: Seq[Iterator[Product2[K, C]]], comparator: Comparator[K])
      : Iterator[Product2[K, C]] = {
    val bufferedIters = iterators.filter(_.hasNext).map(_.buffered)
    type Iter = BufferedIterator[Product2[K, C]]
    // 使用反向比较（compare(y,x)），因为 PriorityQueue 弹出的是最大元素
    val heap = new mutable.PriorityQueue[Iter]()(
      (x: Iter, y: Iter) => comparator.compare(y.head._1, x.head._1))
    heap.enqueue(bufferedIters: _*)  // 只包含 hasNext = true 的迭代器
    new Iterator[Product2[K, C]] {
      override def hasNext: Boolean = heap.nonEmpty

      override def next(): Product2[K, C] = {
        if (!hasNext) {
          throw new NoSuchElementException
        }
        val firstBuf = heap.dequeue()
        val firstPair = firstBuf.next()
        if (firstBuf.hasNext) {
          heap.enqueue(firstBuf)
        }
        firstPair
      }
    }
  }

  // 合并一组已经按键排序的 (K, C) 迭代器，通过对每个键的值进行聚合来合并它们
  // 假设每个迭代器都使用给定的比较器按键排序。如果比较器不是全序（例如我们按哈希值排序，
  // 不同的键也可能比较相等），我们仍然会通过对那些被比较器判为相等的键做相等性测试来合并它们的值
  private def mergeWithAggregation(
      iterators: Seq[Iterator[Product2[K, C]]],
      mergeCombiners: (C, C) => C,
      comparator: Comparator[K],
      totalOrder: Boolean)
      : Iterator[Product2[K, C]] = {
    if (!totalOrder) {
      // 比较器只是部分有序（例如按哈希值比较），这意味着不同的键可能被判为相等，
      // 为处理这种情况，我们需要一次性读取比较器认为相等的所有键，然后逐个比较它们的真实相等性
      val it = new Iterator[Iterator[Product2[K, C]]] {
        val sorted = mergeSort(iterators, comparator).buffered

        // 重用的缓冲以减少内存分配
        val keys = new ArrayBuffer[K]
        val combiners = new ArrayBuffer[C]

        override def hasNext: Boolean = sorted.hasNext

        override def next(): Iterator[Product2[K, C]] = {
          if (!hasNext) {
            throw new NoSuchElementException
          }
          keys.clear()
          combiners.clear()
          val firstPair = sorted.next()
          keys += firstPair._1
          combiners += firstPair._2
          val key = firstPair._1
          while (sorted.hasNext && comparator.compare(sorted.head._1, key) == 0) {
            val pair = sorted.next()
            var i = 0
            var foundKey = false
            while (i < keys.size && !foundKey) {
              if (keys(i) == pair._1) {
                combiners(i) = mergeCombiners(combiners(i), pair._2)
                foundKey = true
              }
              i += 1
            }
            if (!foundKey) {
              keys += pair._1
              combiners += pair._2
            }
          }

          // 注意：这里返回的是一个元素迭代器，因为部分有序情况下可能会有多个键被标记为相等；
          // 在外层会对其做 flatten 操作以得到扁平的 (K, C) 迭代器
          keys.iterator.zip(combiners.iterator)
        }
      }
      it.flatten
    } else {
      // 我们有全序（comparator 即为 ordering.get），因此相同键的对象是连续的
      new Iterator[Product2[K, C]] {
        val sorted = mergeSort(iterators, comparator).buffered

        override def hasNext: Boolean = sorted.hasNext

        override def next(): Product2[K, C] = {
          if (!hasNext) {
            throw new NoSuchElementException
          }
          val elem = sorted.next()
          val k = elem._1
          var c = elem._2
          while (sorted.hasNext && sorted.head._1 == k) {
            val pair = sorted.next()
            c = mergeCombiners(c, pair._2)
          }
          (k, c)
        }
      }
    }
  }

  // 用于按分区逐个读取已溢写文件的内部类，期望按分区顺序请求所有分区
  private[this] class SpillReader(spill: SpilledFile) {
    // 序列化批偏移量，长度为 batchSize.length + 1
    val batchOffsets = spill.serializerBatchSizes.scanLeft(0L)(_ + _)

    // 跟踪当前处于哪个分区和哪个批流，这些将是我们下次要读取元素的索引
    // 我们还会存储最后读取的分区，以便 readNextPartition() 能判断其来源分区
    var partitionId = 0
    var indexInPartition = 0L
    var batchId = 0
    var indexInBatch = 0
    var lastPartitionId = 0

    skipToNextPartition()

    // 只读取单个批的中间文件和反序列化流（deserializer streams）
    // 这可以防止高层流进行预取（pre-fetching）或其他任意行为
    var fileStream: FileInputStream = null
    var deserializeStream = nextBatchStream()  // 也会设置 fileStream

    var nextItem: (K, C) = null
    var finished = false

    // 构造一个只读取下一个批的流
    def nextBatchStream(): DeserializationStream = {
      // 注意 batchOffsets.length = numBatches + 1（因为上面做了 scanLeft），检查是否仍在有效批中
      if (batchId < batchOffsets.length - 1) {
        if (deserializeStream != null) {
          deserializeStream.close()
          fileStream.close()
          deserializeStream = null
          fileStream = null
        }

        val start = batchOffsets(batchId)
        fileStream = new FileInputStream(spill.file)
        fileStream.getChannel.position(start)
        batchId += 1

        val end = batchOffsets(batchId)

        assert(end >= start, "start = " + start + ", end = " + end +
          ", batchOffsets = " + batchOffsets.mkString("[", ", ", "]"))

        val bufferedStream = new BufferedInputStream(ByteStreams.limit(fileStream, end - start))

        val wrappedStream = serializerManager.wrapStream(spill.blockId, bufferedStream)
        serInstance.deserializeStream(wrappedStream)
      } else {
        cleanup()
        null
      }
    }

    // 如果到达当前分区的结尾，则更新 partitionId，并可能跳过中间的空分区
    private def skipToNextPartition(): Unit = {
      while (partitionId < numPartitions &&
          indexInPartition == spill.elementsPerPartition(partitionId)) {
        partitionId += 1
        indexInPartition = 0L
      }
    }

    // 从反序列化流返回下一个 (K, C) 对，并更新 partitionId、indexInPartition、indexInBatch 等以匹配其位置。如果当前批读取完毕，则构造下一个批的流并从中读取。如果没有更多对，返回 null。
    private def readNextItem(): (K, C) = {
      if (finished || deserializeStream == null) {
        return null
      }
      val k = deserializeStream.readKey().asInstanceOf[K]
      val c = deserializeStream.readValue().asInstanceOf[C]
      lastPartitionId = partitionId
      // 如果本批读完，开始读取下一个批
      indexInBatch += 1
      if (indexInBatch == serializerBatchSize) {
        indexInBatch = 0
        deserializeStream = nextBatchStream()
      }
      // 更新正在读取的元素所在的分区位置
      indexInPartition += 1
      skipToNextPartition()
      // 如果我们已经读完最后一个分区，记录 finished
      if (partitionId == numPartitions) {
        finished = true
        if (deserializeStream != null) {
          deserializeStream.close()
        }
      }
      (k, c)
    }

    var nextPartitionToRead = 0

    def readNextPartition(): Iterator[Product2[K, C]] = new Iterator[Product2[K, C]] {
      val myPartition = nextPartitionToRead
      nextPartitionToRead += 1

      override def hasNext: Boolean = {
        if (nextItem == null) {
          nextItem = readNextItem()
          if (nextItem == null) {
            return false
          }
        }
        assert(lastPartitionId >= myPartition)
        // 检查我们仍在正确的分区；注意 readNextItem 在 EOF 时会返回 null，因此会在上面返回 false
        lastPartitionId == myPartition
      }

      override def next(): Product2[K, C] = {
        if (!hasNext) {
          throw new NoSuchElementException
        }
        val item = nextItem
        nextItem = null
        item
      }
    }

    // 清理打开的流并将其置于不能再读取数据的状态
    def cleanup(): Unit = {
      // ...
    }
  }

  // 返回一个破坏性（destructive）的迭代器用于迭代该 map 的条目
  // 如果该迭代器在内存不足时被强制溢写到磁盘，它会从磁盘中的 map 返回键值对
  def destructiveIterator(memoryIterator: Iterator[((Int, K), C)]): Iterator[((Int, K), C)] = {
    if (isShuffleSort) {
      memoryIterator
    } else {
      readingIterator = new SpillableIterator(memoryIterator)
      readingIterator
    }
  }

  // 返回一个按分区分组并按所需 aggregator 聚合后的数据迭代器。对于每个分区，返回一个用于遍历该分区内容的迭代器，这些分区应按顺序访问（不能跳过前面的分区），保证按分区 ID 的顺序返回每个分区的键值对
  // 目前我们一次性合并所有溢写文件，但也可以修改为支持分层合并（hierarchical merging）
  def partitionedIterator: Iterator[(Int, Iterator[Product2[K, C]])] = {
    val usingMap = aggregator.isDefined
    val collection: WritablePartitionedPairCollection[K, C] = if (usingMap) map else buffer
    if (spills.isEmpty) {
      // 特殊情况：如果只有内存数据，则不需要合并流，也许甚至只需按分区 ID 排序（不按键排序）
      if (ordering.isEmpty) {
        // 用户未请求键排序，因此只按分区 ID 排序，不按键排序
        groupByPartition(destructiveIterator(collection.partitionedDestructiveSortedIterator(None)))
      } else {
        // 需要同时按分区 ID 和键进行排序
        groupByPartition(destructiveIterator(
          collection.partitionedDestructiveSortedIterator(Some(keyComparator))))
      }
    } else {
      // 合并已溢写和内存数据
      merge(spills.toSeq, destructiveIterator(
        collection.partitionedDestructiveSortedIterator(comparator)))
    }
  }

  // 返回一个聚合（由 aggregator 指定）的扁平数据迭代器
  def iterator: Iterator[Product2[K, C]] = {
    isShuffleSort = false
    partitionedIterator.flatMap(pair => pair._2)
  }

  // 将所有添加到该 ExternalSorter 的数据写入一个 map output writer（将字节推送到任意后端存储）
  // 该方法由 SortShuffleWriter 调用。返回每个分区在文件中的长度数组（以字节为单位），由 map output tracker 使用
  def writePartitionedMapOutput(
      shuffleId: Int,
      mapId: Long,
      mapOutputWriter: ShuffleMapOutputWriter,
      writeMetrics: ShuffleWriteMetricsReporter): Unit = {
    if (spills.isEmpty) {
      // 只有内存数据的情况
      val collection = if (aggregator.isDefined) map else buffer
      val it = collection.destructiveSortedWritablePartitionedIterator(comparator)
      while (it.hasNext) {
        val partitionId = it.nextPartition()
        var partitionWriter: ShufflePartitionWriter = null
        var partitionPairsWriter: ShufflePartitionPairsWriter = null
        TryUtils.tryWithSafeFinally {
          partitionWriter = mapOutputWriter.getPartitionWriter(partitionId)
          val blockId = ShuffleBlockId(shuffleId, mapId, partitionId)
          partitionPairsWriter = new ShufflePartitionPairsWriter(
            partitionWriter,
            serializerManager,
            serInstance,
            blockId,
            writeMetrics,
            if (partitionChecksums.nonEmpty) partitionChecksums(partitionId) else null)
          while (it.hasNext && it.nextPartition() == partitionId) {
            it.writeNext(partitionPairsWriter)
          }
        } {
          if (partitionPairsWriter != null) {
            partitionPairsWriter.close()
          }
        }
      }
    } else {
      // 必须执行合并排序；通过按分区获取迭代器并直接写出所有内容
      for ((id, elements) <- this.partitionedIterator) {
        val blockId = ShuffleBlockId(shuffleId, mapId, id)
        var partitionWriter: ShufflePartitionWriter = null
        var partitionPairsWriter: ShufflePartitionPairsWriter = null
        TryUtils.tryWithSafeFinally {
          partitionWriter = mapOutputWriter.getPartitionWriter(id)
          partitionPairsWriter = new ShufflePartitionPairsWriter(
            partitionWriter,
            serializerManager,
            serInstance,
            blockId,
            writeMetrics,
            if (partitionChecksums.nonEmpty) partitionChecksums(id) else null)
          if (elements.hasNext) {
            for (elem <- elements) {
              partitionPairsWriter.write(elem._1, elem._2)
            }
          }
        } {
          if (partitionPairsWriter != null) {
            partitionPairsWriter.close()
          }
        }
      }
    }

    context.taskMetrics().incMemoryBytesSpilled(memoryBytesSpilled)
    context.taskMetrics().incDiskBytesSpilled(diskBytesSpilled)
    context.taskMetrics().incPeakExecutionMemory(peakMemoryUsedBytes)
  }

  def stop(): Unit = {
    spills.foreach(s => s.file.delete())
    spills.clear()
    forceSpillFiles.foreach(s => s.file.delete())
    forceSpillFiles.clear()
    if (map != null || buffer != null || readingIterator != null) {
      map = null // 使 GC 能回收内存
      buffer = null // 使 GC 能回收内存
      readingIterator = null // 使 GC 能回收内存
      releaseMemory()
    }
  }

  // 给定一个假定已经按分区 ID 排序的 ((partition, key), combiner) 流，将属于同一分区的对分组到子迭代器中。参数 data 表示一个元素迭代器，假定已按分区 ID 排序
  private def groupByPartition(data: Iterator[((Int, K), C)])
      : Iterator[(Int, Iterator[Product2[K, C]])] =
  {
    val buffered = data.buffered
    (0 until numPartitions).iterator.map(p => (p, new IteratorForPartition(p, buffered)))
  }

  // 一个迭代器，只从底层带缓冲流中读取给定分区 ID 的元素，假定该分区是下一个要读取的分区。用于方便地从内存集合返回分区化的迭代器。
  private[this] class IteratorForPartition(partitionId: Int, data: BufferedIterator[((Int, K), C)])
    extends Iterator[Product2[K, C]]
  {
    override def hasNext: Boolean = data.hasNext && data.head._1._1 == partitionId

    override def next(): Product2[K, C] = {
      if (!hasNext) {
        throw new NoSuchElementException
      }
      val elem = data.next()
      (elem._1._2, elem._2)
    }
  }

  private[this] class SpillableIterator(var upstream: Iterator[((Int, K), C)])
    extends Iterator[((Int, K), C)] {

    private val SPILL_LOCK = new Object()

    private var nextUpstream: Iterator[((Int, K), C)] = null

    private var cur: ((Int, K), C) = readNext()

    private var hasSpilled: Boolean = false

    def spill(): Boolean = SPILL_LOCK.synchronized {
      if (hasSpilled) {
        false
      } else {
        val inMemoryIterator = new WritablePartitionedIterator[K, C](upstream)
        logInfo(s"Task ${TaskContext.get().taskAttemptId} force spilling in-memory map to disk " +
          s"and it will release ${org.apache.spark.util.Utils.bytesToString(getUsed())} memory")
        val spillFile = spillMemoryIteratorToDisk(inMemoryIterator)
        forceSpillFiles += spillFile
        val spillReader = new SpillReader(spillFile)
        nextUpstream = (0 until numPartitions).iterator.flatMap { p =>
          val iterator = spillReader.readNextPartition()
          iterator.map(cur => ((p, cur._1), cur._2))
        }
        hasSpilled = true
        true
      }
    }

    def readNext(): ((Int, K), C) = SPILL_LOCK.synchronized {
      if (nextUpstream != null) {
        upstream = nextUpstream
        nextUpstream = null
      }
      if (upstream.hasNext) {
        upstream.next()
      } else {
        null
      }
    }

    override def hasNext(): Boolean = cur != null

    override def next(): ((Int, K), C) = {
      val r = cur
      cur = readNext()
      r
    }
  }
}
```





# 7. 总结

在 Spark Shuffle 机制中，典型的数据操作如下表所示。注意，在 Shuffle Write 端，目前只支持 Combine 功能，并不支持按 Key 排序功能。当然，未来有些数据操作可能同时需要这两个功能，所以，Shuffle 框架还是需要支持全部的功能。

| 包含 ShuffleDependency 的操作                                | Shuffle Write 端 Combine | Shuffle Write 端按 Key 排序 | Shuffle Read 端 Combine | Shuffle Read 端按 Key 排序 |
| ------------------------------------------------------------ | :----------------------: | :-------------------------: | :---------------------: | :------------------------: |
| partitionBy                                                  |            Ⅹ             |              Ⅹ              |            Ⅹ            |             Ⅹ              |
| groupByKey、cogroup、join、coalesce、intersection、subtract、subtractByKey |            Ⅹ             |              Ⅹ              |            √            |             Ⅹ              |
| reduceByKey、aggregateByKey、combineByKey、foldByKey、distinct |            √             |              Ⅹ              |            √            |             Ⅹ              |
| sortByKey、sortBy、repartitionAndSortWithinPartitions        |            Ⅹ             |              Ⅹ              |            Ⅹ            |             √              |
| 未来系统可能支持的或用户自定义的数据操作                     |            √             |              √              |            √            |             √              |

Spark 设计的这三种数据结构完美匹配了 Shuffle 机制中的操作需求，如下表所示。

| 名称                                      | 数据结构类型         | 功能                                                        |
| ----------------------------------------- | -------------------- | ----------------------------------------------------------- |
| PartitionedAppendOnlyMap + ExternalSorter | 类似 HashMap + Array | 用于 Shuffle Write 端聚合及排序，包含 partitionId           |
| ExternalAppendOnlyMap                     | 类似 HashMap + Array | 用于 Shuffle Read 端聚合及排序，不包含 partitionId          |
| PartitionedPairBuffer + ExternalSorter    | 类似 Array           | 用于 Shuffle Write 和 Shuffle Read 端排序，包含 partitionId |





# 参考

1. 《大数据处理框架 Apache Spark 设计与实现》