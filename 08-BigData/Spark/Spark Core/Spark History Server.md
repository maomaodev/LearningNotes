说明：代码部分以 spark 3.4.2 为例讲解。**Spark History Server（简称 SHS） 与 Spark UI 的区别：前者针对的是已经完成的应用，后者针对的是实时运行的应用**。

# 1. 前置知识

1、**SparkListenerEvent 是一个特质（trait），表示在 Spark 作业执行过程中发生的 Event 事件**。它的子类有很多，每个子类对应一种特定类型的事件。

```scala
trait SparkListenerEvent {
  // 是否将此事件输出到EventLog
  protected[spark] def logEvent: Boolean = true
}

// Job开始事件
case class SparkListenerJobStart(...) extends SparkListenerEvent
// Job结束事件
case class SparkListenerJobEnd(...) extends SparkListenerEvent

// Stage提交事件
case class SparkListenerStageSubmitted(...) extends SparkListenerEvent
// Stage完成事件
case class SparkListenerStageCompleted(...) extends SparkListenerEvent

// Task开始事件
case class SparkListenerTaskStart(...) extends SparkListenerEvent
// Task结束事件
case class SparkListenerTaskEnd(...) extends SparkListenerEvent

// ...
```

 

2、**SparkListener 是一个抽象类，用于监听 Spark 作业执行过程中发生的 Event 事件**。它定义了一系列的空方法，每个方法对应一种特定类型的事件。通过实现 SparkListener 接口，可以在事件触发时执行特定的操作，例如监控作业的运行状态、记录性能指标、处理错误和异常等。

```scala
// SparkListenerInterface是一个用于监听Spark调度程序事件的接口，大多数应用程序可能应该直接扩展
// SparkListener或SparkFirehoseListener，SparkListener对所有回调都有空实现。
abstract class SparkListener extends SparkListenerInterface {
  // Job开始时调用
  override def onJobStart(jobStart: SparkListenerJobStart): Unit = { }
  // Job结束时调用
  override def onJobEnd(jobEnd: SparkListenerJobEnd): Unit = { }
  
  // Stage提交时调用
  override def onStageSubmitted(stageSubmitted: SparkListenerStageSubmitted): Unit = { }
  // Stage完成时调用
  override def onStageCompleted(stageCompleted: SparkListenerStageCompleted): Unit = { }

  // Task开始时调用
  override def onTaskStart(taskStart: SparkListenerTaskStart): Unit = { }
  // Task结束时调用
  override def onTaskEnd(taskEnd: SparkListenerTaskEnd): Unit = { }
  
  // ...
}
```

 

3、**EventLoggingListener 类继承自 SparkListener 抽象类，它通过 EventLogFileWriter 将 Spark 作业执行过程中发生的事件（SparkListenerEvent）记录到持久化存储**，如 HDFS、S3 或本地文件系统，这些记录的 EventLog 可用于分析和诊断 Spark 作业的性能和问题，以及在 SHS 中回放作业的执行历史。**EventLogFileWriter 包括两个子类：SingleEventLogFileWriter 和 RollingEventLogFilesWriter，后者将滚动 EventLog 文件，而非单个庞大的 EventLog 文件，参数 spark.eventLog.rolling.enabled，Spark 4.0 之前默认为 false，Spark 4.0 及之后默认为 true。**

```scala
// EventLog通过以下可配置参数进行指定：
// spark.eventLog.enabled：是否启用Event记录，默认false
// spark.eventLog.dir：Event记录的目录路径，默认本地路径/tmp/spark-events
// spark.eventLog.logBlockUpdates.enabled：是否记录块更新，默认false
// spark.eventLog.logStageExecutorMetrics：是否记录stage executor指标，默认false
private[spark] class EventLoggingListener(...) extends SparkListener with Logging {
  // logWriter类型为EventLogFileWriter，它负责将Spark作业执行过程中发生的事件（SparkListenerEvent）记录到持久化存储
  // 继承关系：SingleEventLogFileWriter、RollingEventLogFilesWriter -> EventLogFileWriter
  private[scheduler] val logWriter: EventLogFileWriter = EventLogFileWriter(...)
  
  // SparkContext调用，在指定日志目录下，创建日志文件 
  def start(): Unit = {
    // 由EventLogFileWriter具体子类初始化
    logWriter.start()
    initEventLog()
  }
  
  // 以JSON格式记录日志
  private def logEvent(event: SparkListenerEvent, flushLogger: Boolean = false): Unit = {
    val eventJson = JsonProtocol.sparkEventToJsonString(event)
    // 由EventLogFileWriter具体子类写入
    logWriter.writeEvent(eventJson, flushLogger)
  }
  
  // 实现SparkListener抽象类的方法
  override def onTaskStart(event: SparkListenerTaskStart): Unit = logEvent(event)
  
  // ...
}
```

 

4、**AppListingListener 类同样继承自 SparkListener 抽象类，它通过 EventLogFileReader 类读取、解析 EventLog 文件（与 EventLogFileWriter 类写入相对应），从中提取出有关 Spark 作业执行的详细信息**。**EventLogFileReader** **同样包括两个子类：SingleFileEventLogFileReader 和 RollingEventLogFilesFileReader，后者将滚动 EventLog 文件，而非单个庞大的 EventLog 文件。**

```scala
private[history] class AppListingListener(
    reader: EventLogFileReader,
    clock: Clock,
    haltEnabled: Boolean) extends SparkListener {
  // ...
}

abstract class EventLogFileReader(
    protected val fileSystem: FileSystem,
    val rootPath: Path) {
  // 返回EventLog文件的最后一个索引。RollingEventLog有值，SingleFileEventLog为None
  def lastIndex: Option[Long]
  
  // 返回EventLog文件的最后一个索引的文件大小。SingleFileEventLog为文件本身大小
  def fileSizeForLastIndex: Long
  
  // 返回Application是否已完成
  def completed: Boolean
  
  // 仅当低层输入流为DFSInputStream时，返回EventLog文件的最后一个索引（SingleFileEventLog文件本身）的文件大小，否则返回None
  def fileSizeForLastIndexForDFS: Option[Long]
  
  // 返回EventLog文件的最后一个索引（SingleFileEventLog文件本身）的修改时间
  def modificationTime: Long
  
  // 对传入的文件进行压缩，并将压缩后的数据写入传入的ZipOutputStream
  // 每个文件作为一个新的ZipEntry写入，其名称即为被压缩文件的名称
  def zipEventLogFiles(zipStream: ZipOutputStream): Unit

  // 返回所有可用的EventLog文件
  def listEventLogFiles: Seq[FileStatus]

  // 返回简短的压缩名称，如果未压缩，则为None
  def compressionCodec: Option[String]

  // 返回所有EventLog文件的大小
  def totalSize: Long
}
```

 

5、**ListenerBus 是一个特质（trait），定义了事件监听和分发的框架。它提供了基本的方法，如添加监听器（addListener）、移除监听器（removeListener）、将事件分发到所有注册的监听器（postToAll），**其中 postToAll 方法调用 doPostEvent 方法将事件分发到指定的监听器，而具体的事件分发逻辑由 ListenerBus 子类来完成。

```scala
private[spark] trait ListenerBus[L <: AnyRef, E] extends Logging {
  // listenersPlusTimers类型为CopyOnWriteArrayList，线程安全
  private[this] val listenersPlusTimers = new CopyOnWriteArrayList[(L, Option[Timer])]
  
  // 添加监听器，监听事件
  final def addListener(listener: L): Unit = {
    listenersPlusTimers.add((listener, getTimer(listener)))
  }
  
  // 删除监听器，它不会收到任何事件
  final def removeListener(listener: L): Unit = {
    listenersPlusTimers.asScala.find(_._1 eq listener).foreach { listenerAndTimer =>
      listenersPlusTimers.remove(listenerAndTimer)
    }
  }
  
  // 将事件分发到所有注册的监听器，postToAll调用方应保证在同一线程中为所有事件调用postToAll
  def postToAll(event: E): Unit = {
    val iter = listenersPlusTimers.iterator
    while (iter.hasNext) {
      // ...
    }
  }
  
  // 将事件分发到指定的监听器，由子类实现
  protected def doPostEvent(listener: L, event: E): Unit
}
```

 

6、**SparkListenerBus 特质继承自 ListenerBus 特质，它实现了父类 doPostEvent 方法，将 SparkListenerEvent 重放（relay）给** **SparkListener。SparkListenerBus 包括两个子类：ReplayListenerBus 用于从序列化的 Event 数据中重放事件**；AsyncEventQueue 是事件的异步队列，发布到此队列的所有事件都将传递到单独线程中的子监听器。

```scala
// 继承关系：ReplayListenerBus、AsyncEventQueue -> SparkListenerBus -> ListenerBus
private[spark] trait SparkListenerBus extends ListenerBus[SparkListenerInterface, SparkListenerEvent] {
  
  protected override def doPostEvent(
      listener: SparkListenerInterface,
      event: SparkListenerEvent): Unit = {
    event match {
      case stageSubmitted: SparkListenerStageSubmitted =>
        listener.onStageSubmitted(stageSubmitted)
      case stageCompleted: SparkListenerStageCompleted =>
        listener.onStageCompleted(stageCompleted)
      // ...
  }
}
```

 

 

# 2. SHS 启动流程

1、命令行提交：start-history-server.sh 脚本用于启动 SHS，其调用过程与 spark-submit 类似。前面已经介绍过，spark-class 会调用 org.apache.spark.launcher.Main 工具类，将参数进行解析后，执行返回的命令。因此，**整个调用过程是，start-history-server.sh 调用 spark-daemon.sh，spark-daemon.sh 再调用 spark-class 脚本，设置进程优先级，并在后台启动 Java 进程**。最后执行的命令类似：`java -cp ${class_path} org.apache.spark.deploy.history.HistoryServer ${args}`。注意，**如果 log4j2.properties 文件配置了日志输出 Console，将会被重定向到 xxx.out 文件，SHS 每次重启滚动一次日志，默认保留 5 个，参考 spark-daemon.sh 脚本**。

 

2、从 HistoryServer 类的 main() 方法开始，该类首先通过反射生成 FsHistoryProvider 类实例；然后初始化 HistoryServer，**调用 Jetty API 设置处理 restful 请求的资源，例如扫描** `org.apache.spark.status.api.v1` **包下面的类，用于处理以 /api 为前缀的 restful 请求**；然后调用 Jetty API 完成服务的端口监听与启动；最后**由 FsHistoryProvider 启动两个定时任务，即 EventLog 文件解析任务和 EventLog 文件清理任务，两个任务共用同一个大小为 1 的线程池，避免出现并发问题（后面详细介绍）**。

```scala
// 继承关系：HistoryServer -> WebUI
HistoryServer
  main(argStrings: Array[String])
    // provider默认为FsHistoryProvider，它用于读取和解析存储在HDFS上EventLog文件，为用户提供一个可视化界面
    val providerName = ... classOf[FsHistoryProvider]
    // 通过反射生成FsHistoryProvider类实例，继承关系：FsHistoryProvider -> ApplicationHistoryProvider
    provider = Utils.classForName[ApplicationHistoryProvider](providerName).getConstructor(...).newInstance(...)
    // 参数：spark.history.ui.port，默认18080
    val port = conf.get(History.HISTORY_SERVER_UI_PORT)
    val server = new HistoryServer(conf, provider, securityManager, port)
      // 缓存的application，参数spark.history.retainedApplications，默认为50
      val appCache = new ApplicationCache(...)
        // 底层使用guava的LoadingCache实现
        val appCache: LoadingCache[CacheKey, CacheEntry]
      // 初始化HistoryServer，这将启动一个后台线程，该线程定期将此UI上显示的信息与指定基目录中的EventLog同步
      initialize()
        // ApiRootResource类提供Spark应用程序指标的主要入口点
        ApiRootResource.getServletHandler(this)
          // jetty自动解析org.apache.spark.status.api.v1包下面的类，用于处理/api请求
          jerseyContext.setContextPath("/api")
          holder.setInitParameter(ServerProperties.PROVIDER_PACKAGES, "org.apache.spark.status.api.v1")
        attachHandler(...)
          serverInfo.foreach(_.addHandler(handler, securityManager))
            // 往ContextHandlerCollection中加入ServletContextHandler，用来处理restful api
            val gzipHandler = new GzipHandler()
            gzipHandler.setHandler(handler)
            rootHandler.addHandler(gzipHandler)
        // loaderServlet类型为HttpServlet，用于处理/history/*请求
        contextHandler.setContextPath(HistoryServer.UI_PATH_PREFIX)
        contextHandler.addServlet(new ServletHolder(loaderServlet), "/*")
        // 同上，往ContextHandlerCollection中加入ServletContextHandler
        attachHandler(contextHandler)

    server.bind()
      super.bind()
        // 启动Jetty服务器
        val server = initServer()
          val server = startJettyServer(...)
        // ServerInfo类包含ContextHandlerCollection属性类型，它持有一系列Handler对象，同时能起到路由器的作用
        serverInfo = Some(server)
        logInfo(s"Bound $className to $hostName, and started at $webUrl")
    // 实际调用的是FsHistoryProvider类
    provider.start()
      initThread = initialize()
        // 启动两个定时任务，即EventLog文件解析任务、EventLog文件清理任务，两个任务共用同一个线程池，
        // 线程池大小必须为1，否则在EventLog文件解析任务、EventLog文件清理任务之间将出现有关fs和应用程序的并发问题
        startPolling()
          pool.scheduleWithFixedDelay(getRunner(() => checkForLogs()), ...)
          // 参数spark.history.fs.cleaner.enabled，默认false
          pool.scheduleWithFixedDelay(getRunner(() => cleanLogs()), ...)
```

 

3、**FsHistoryProvider 有几个比较重要的属性，其中属性 listing 类型为 KVStore，它通过键值对的形式存储 spark 作业的各种元数据**。当一个 Spark 作业正在运行时，Driver 会将作业的元数据写入到 KVStore 中，然后 Spark UI 可以从 KVStore 中读取这些元数据，显示作业的实时状态和进度。当作业完成后，这些元数据会被写入到 EventLog 中，并由 SHS 读取和解析，重建作业的执行历史。注意，这里的 KVStore 不是同一个，因为 Spark UI 与 SHS 在不同的进程中。

```scala
FsHistoryProvider
  // 属性listing类型为KVStore，它通过键值对的形式存储spark application的各种元数据，包括两类：
  // 1.<LogPath, LogInfo>，其中key为Event Log的文件存储路径，value为Event Log的元数据（参见LogInfo类定义）
  // 2.<AppId, ApplicationInfoWrapper>，其中key为Application ID，value为Application的元数据（参见ApplicationInfoWrapper类定义）
  // 注意，listing存储的是参数spark.history.fs.logDirectory目录下所有application的元数据，而不仅仅是SHS页面上的application，
  // 当删除spark.history.fs.logDirectory目录下的EventLog文件时，也会同步删除listing存储的对应application的元数据
  val listing: KVStore = { ... }
    // KVStore是个接口，具体实现包括：InMemoryStore、HybridStore、RocksDB、LevelDB
    // 若参数spark.history.store.path为空（默认为空），则listing定义为InMemoryStore，否则定义为ROCKSDB或LEVELDB，
    // 这取决于参数spark.history.store.hybridStore.diskBackend，默认为ROCKSDB（基于LEVELDB构建，读写性能更好）
    KVUtils.createKVStore(storePath, live = false, conf)

  // 属性diskManager类型为HistoryServerDiskManager，该类用于跟踪SHS磁盘使用情况，允许在使用量超过可配置阈值时，从磁盘中删除应用程序数据
  // 该类的目标不是保证使用量永远不会超过阈值，由于应用程序数据的写入方式，磁盘使用率可能会暂时升高，但最终它应该回落到阈值以下
  // 若参数spark.history.store.path不为空（默认为空），则进行初始化
  val diskManager = storePath.map { ... }
    new HistoryServerDiskManager(conf, path, listing, clock)

  // 属性memoryManager类型为HistoryServerMemoryManager，该类用于跟踪SHS内存使用情况
  private var memoryManager: HistoryServerMemoryManager = null
  // 若参数spark.history.store.hybridStore.enabled为true（默认为false），则进行初始化
  if (hybridStoreEnabled)
    memoryManager = new HistoryServerMemoryManager(conf)
```

 

4、**FsHistoryProvider 类 checkForLogs 方法负责 EventLog 文件解析，它将 EventLog 文件每一行的 JSON 字符串反序列化，生成对应的事件 Event，这些事件最终会被发布到所有向 ReplayListenerBus 注册过的监听器（Listener）中，由监听器处理其关心的事件**。比如，这里 AppListingListener 监听器关心的事件就包括：应用启动（onApplicationStart）、应用结束（onApplicationEnd）、环境属性更新（onEnvironmentUpdate）等。以 onApplicationStart 为例，首先 AppListingListener 会更新 application、attempt 的字段，之后 SHS 会通知其对应的现有 UI 无效，并将 Application 元信息和 EventLog 元信息写入 listing 数据库中。

注意，参数 `spark.history.fs.inProgressOptimization.enabled` 默认为 true，表示开启 in-progress EventLog 文件优化处理（参考：[SPARK-6951](https://issues.apache.org/jira/browse/SPARK-6951)）。即对于未完成的 Application（EventLog 文件去掉压缩后缀后，以 .inprogress 结尾），AppListingListener 在处理并解析到 onApplicationStart 启动事件后，就会停止解析后续事件，从而跳过处理 onApplicationEnd 结束事件（更新 attempt endTime、completed 等字段）。当前端请求 `http://xxx/api/v1/applications/?status=[completed|running]` 时，SHS 需要判断 Application 的状态：`app.attempts.isEmpty || !app.attempts.head.completed`（参考 ApplicationListResource 类），即当 Application 的 attempt 为空或 attempt completed 为 false，SHS 认为 Application 处于 running 状态。**这意味着，开启参数** `spark.history.fs.inProgressOptimization.enabled`**，可能导致未能重命名 EventLog，但已完成的 Application，被误认为 in-progress**。

那么 EventLog 文件的 .inprogress 后缀什么时候移除的呢？正常情况下，调用流程为：SparkContext.close -> EventLoggingListener.stop -> EventLogFileWriter.stop，最终完成 EventLog 文件重命名，去掉 .inprogress 后缀。但当任务 OOM 或被杀死时，这个调用流程可能不会执行，**因此仅从后缀名判断 Application 是否运行结束，是不够准确的。同样的，SHS 判断的标准是：解析到 EventLog 文件包含 SparkListenerApplicationEnd 事件，在上述异常情况下，也是不够准确的**。

```scala
FsHistoryProvider
  // EventLog文件解析任务，尽量重用内存中已有的数据，不读取自上次检查日志以来未发生更新的应用。每个周期最多处理
  // spark.history.fs.update.batchSize(默认Int.MaxValue)作业，以防该过程运行时间过长，从而阻塞新EventLog文件的更新
  checkForLogs()
    // 参数spark.history.fs.logDirectory表示EventLog存储目录，列出该目录下的文件（包括目录）
    fs.listStatus(new Path(logDir))...
      // ①过滤掉没有权限读取的文件
      .filter { ... isAccessible(entry.getPath) }
      // ②过滤掉当前正在处理的文件
      .filter { ... isProcessing(entry.getPath) }
      // 根据文件实例化EventLogFileReader：若文件不是目录，且文件名不以.开头，则使用SingleFileEventLogFileReader；
      // 若文件是目录，且目录名以eventlog_v2_开头，则使用RollingEventLogFilesFileReader
      .flatMap { ... EventLogFileReader(fs, entry) }
      // ③过滤掉获取modificationTime失败的文件
      .filter {... reader.modificationTime}
      // ④过滤掉大小未变化的文件（简单理解，实际比较复杂）
      // 从listing读取当前文件LogInfo元信息，若不存在，说明SHS当前未跟踪该文件，进入catch流程：
      //   检查EventLog文件是否已过期，若已过期，则直接删除；若没有过期，则listing写入LogInfo元信息，后续解析
      // 若listing存在该文件LogInfo元信息，则调用shouldReloadLog方法，比较listing记录的文件大小与当前读取的文件大小
      //   若大小未发生变化，则过滤掉文件，暂不解析。有一种特殊情况也暂不解析：文件大小发生变化 && listing读取的LogInfo元信息中appId已定义
      //   && 使用SingleFileEventLog && 参数spark.history.fs.inProgressOptimization.enabled为true（参考：SPARK-6951，参数表示
      //   开启in-progress EventLog优化处理，这可能导致未能重命名EventLog，但已完成的Application，被误认为in-progress，默认为true），
      //   也就是说，在使用SingleFileEventLog的默认情况下，对于in-progress Application，SHS只要解析到appId这个基本信息，后续就不解析了
      .filter {... shouldReloadLog(info, reader) }

    // 对于上述过滤后需要解析的文件，逐个提交线程池处理
    updated.foreach { ... submitLogProcessTask() }
      // 记录正在处理的文件路径，这样可以异步执行重放日志，并确保checkForLogs不会重复处理
      processing(rootPath)
      // replayExecutor是固定大小的线程池，参数spark.history.fs.numReplayThreads，默认为可获取核心数的25%
      replayExecutor.submit(task)
        // 注意此时参数enableOptimizations为true
        mergeApplicationListing(entry, newLastScanTime, true)
          // 重放给定的EventLog文件，将应用程序保存在listing数据库中
          doMergeApplicationListing(...)
            doMergeApplicationListingInternal(...)
              // EventLog文件去掉压缩后缀后，若以.inprogress结尾，则表示Application未完成；否则为已完成
              val appCompleted = reader.completed
              // 以下情况，开启Listener监听器暂停重放的功能：
              // ①Application未完成 && spark.history.fs.inProgressOptimization.enabled为true
              // ②spark.history.fs.endEventReparseChunkSize大于0（参考：SPARK-6951，参数表示在EventLog文件末尾解析多少字节
              //   以查找结束事件，用于跳过EventLog文件中不必要的部分来加速Application列表的生成，设置为0禁用此功能，默认1m）
              val shouldHalt = enableOptimizations && ((!appCompleted && fastInProgressParsing) || reparseChunkSize > 0)
              // 继承关系：ReplayListenerBus -> SparkListenerBus -> SparkListenerBus
              // ReplayListenerBus用于从序列化的Event数据中重放事件
              val bus = new ReplayListenerBus()
              // 继承关系：AppListingListener -> SparkListener，AppListingListener监听的事件包括：
              // onApplicationStart、onApplicationEnd、onEnvironmentUpdate等
              val listener = new AppListingListener(reader, clock, shouldHalt)
              // 向ReplayListenerBus注册AppListingListener监听器
              bus.addListener(listener)

              logInfo(s"Parsing $logPath for listing data...")
              // 解析Application EventLog文件
              parseAppEventLogs()
                logFiles.foreach { file => ... }
                // 如果ReplayListenerBus出现某些错误或暂停重放，则停止重放下一个EventLog文件
                  if (continueReplay)
                    // 按照给定流中维护的顺序重放每个事件，该流每行包含一个JSON编码的SparkListenerEvent
                    continueReplay = replayBus.replay(...)
                      // replay重方法，它接受行的迭代器而不是InputStream
                      replay(...)
                        // 将事件发布给所有已注册的监听器。注意，这里将捕获HaltReplayException停止重放异常，返回false
                        postToAll(JsonProtocol.sparkEventFromJson(parse(currentLine)))
                          // 实际调用SparkListenerBus子类实现，将事件发布给指定的监听器，监听器负责处理
                          doPostEvent(listener, event)
              // ①如果启用了上述功能，即当有足够的信息来创建listing条目时，监听器将暂停解析
              // 但是当Application完成或快速解析被禁用时，我们仍然需要重放日志文件直到末尾，以尝试找到Application的结束事件
              // 与逐行读取和解析不同，这段代码会从底层流中跳过字节，使其定位到EventLog文件末尾附近的位置
              // ②由于Application的结束事件是在某些Spark子系统（如调度器）仍然活跃时写入的，因此无法保证结束事件是日志中的最后一条记录
              // 因此，为了安全起见，代码使用可配置的块大小在文件末尾重新解析，如果仍未找到所需的数据，则稍后重新解析整个日志
              // ③注意，在压缩文件中跳过字节仍然不是一种廉价的操作，但与ReplayListenerBus执行的常规日志解析相比，仍然有一些小的性能提升
              val lookForEndEvent = shouldHalt && (appCompleted || !fastInProgressParsing)
              if (lookForEndEvent && listener.applicationInfo.isDefined)
                // 寻找结束事件，将跳过EventLog文件的(lastFile.getLen - spark.history.fs.endEventReparseChunkSize)字节
                val target = lastFile.getLen - reparseChunkSize
                bus.replay(source, lastFile.getPath.toString, !appCompleted, eventsFilter)
              logInfo(s"Finished parsing $logPath")

              listener.applicationInfo match
                case Some(app) if !lookForEndEvent || app.attempts.head.info.completed =>
                  // 在这种情况下，我们要么不关心结束事件，要么已经找到了它。因此，listing数据是有效的
                  // 使给定Application attempt的现有UI无效
                  invalidateUI(...)
                  // 将Application的元数据(ApplicationInfoWrapper)写入listing数据库
                  addListing(app)
                    listing.write(newAppInfo)
                  // 将Event Log的元数据（LogInfo）写入listing数据库
                  listing.write(LogInfo(...))
                case Some(_) =>
                  // 在这种情况下，attempt仍未标记为已完成，但预期已完成。
                  // 这可能意味着结束事件早于配置的阈值，因此再次调用该方法以重新解析整个日志
                  logInfo(s"Reparsing $logPath since end event was not found.")
                  // 注意此时参数enableOptimizations为true
                  doMergeApplicationListingInternal(reader, scanTime, enableOptimizations = false, ...)
                case _ =>
                  // 如果Application尚未将其AppID写入日志，仍将该条目记录在listing数据库中，并使用空ID
                  // 如果Application在配置的最大日志期限后没有取得进展，这将使日志符合删除条件
                  listing.write(LogInfo(...))
```

 

5、**FsHistoryProvider 类 cleanLogs 方法负责 EventLog 文件清理，主要处理如下三种情况**：①如果 EventLog 保留时间超过 spark.history.fs.cleaner.maxAge，则逐一清理每个 application 所有已完成attempts；②删除没有有效application，且保留时间超过spark.history.fs.cleaner.maxAge的EventLog文件；③如果EventLog文件数大于spark.history.fs.cleaner.maxNum，则逐一清理每个application所有已完成attempts

```scala
FsHistoryProvider
  // EventLog文件清理任务，根据用户定义的清理策略（保留时间、保留个数）进行删除
  cleanLogs()
    // 参数spark.history.fs.cleaner.maxAge，默认为7天
    val maxTime = clock.getTimeMillis() - conf.get(MAX_LOG_AGE_S) * 1000
    // 参数spark.history.fs.cleaner.maxNum，默认为Int.MaxValue
    val maxNum = conf.get(MAX_LOG_NUM)

    // ①如果EventLog保留时间超过spark.history.fs.cleaner.maxAge，则逐一清理每个application所有已完成attempts
    val expired = KVUtils.viewToSeq(listing.view(classOf[ApplicationInfoWrapper])
      .index("oldestAttempt").reverse().first(maxTime))
      // oldestAttempt索引，表示按照lastUpdated排序
      @JsonIgnore @KVIndexParam("oldestAttempt")
      def oldestAttempt(): Long = attempts.map(_.info.lastUpdated.getTime()).min
    // application可能会有多次attempts，其中一些可能还不需要删除，remaining、toDelete分别表示需要保留、删除的attempts
    expired.foreach { app => ... deleteAttemptLogs(app, remaining, toDelete) }
      // listing删除attempt对应的LogInfo信息
      listing.delete(classOf[LogInfo], logPath.toString())
      // 删除attempt对应的EventLog文件
      deleteLog(fs, logPath)
        deleted = fs.delete(log, true)
      // 若remaining为空，表示所有attempt都过期，listing将删除application对应的ApplicationInfoWrapper信息
      if (remaining.isEmpty)
        listing.delete(app.getClass(), app.id)

    // ②删除没有有效application，且保留时间超过spark.history.fs.cleaner.maxAge的EventLog文件
    val stale = KVUtils.viewToSeq(listing.view(classOf[LogInfo])
      .index("lastProcessed").reverse().first(maxTime), Int.MaxValue) { ... }
    stale.filterNot(isProcessing).foreach { ... }
      // 若application id为空，删除这个无效/损坏的EventLog文件，同时删除listing对应的LogInfo信息
      if (log.appId.isEmpty)
        logInfo(s"Deleting invalid / corrupt event log ${log.logPath}")
        deleteLog(fs, new Path(log.logPath))
        listing.delete(classOf[LogInfo], log.logPath)

    // ③如果EventLog文件数大于spark.history.fs.cleaner.maxNum，则逐一清理每个application所有已完成attempts
    val num = KVUtils.size(listing.view(classOf[LogInfo]).index("lastProcessed"))
    var count = num - maxNum
    if (count > 0)
      KVUtils.foreach(listing.view(classOf[ApplicationInfoWrapper]).index("oldestAttempt"))
        // 删除逻辑与上面相同
        count -= deleteAttemptLogs(app, remaining, toDelete)
```

 

6、总结：SHS 与 Spark UI 整体执行流程如下图所示。

![SHS 与 Spark UI 整体执行流程](<./images/SHS 与 Spark UI 整体执行流程.png>)

- 如上图左侧所示，在 Spark 作业运行期间，Spark Driver 内部各模块会产生大量包含运行信息的 `SparkListenerEvent`，例如 `ApplicationStart`、`StageCompleted`、`MetricsUpdate` 等。所有的 `SparkListenerEvent` 都会被发送到 `LiveListenerBus` 中，然后在 `LiveListenerBus` 内部分发到各个子队列，由注册在子队列上的 `SparkListener` 进行处理。其中 `EventLoggingListener` 是专门用于生成事件日志的监听器。它会将事件序列化并写入到文件系统中（通常是分布式文件系统，如 HDFS）。事件的序列化格式以前是 JSON，现在可以配置为 Proto Buf 以提高性能和减小存储空间需求。每个应用程序的日志文件通常存储在一个配置的路径下。
- 如上图右侧表示的是 SHS，核心组件之一是 `FsHistoryProvider`。它负责定期扫描配置的事件日志存储路径，遍历其中的事件日志文件，并提取关键信息，如 `application_id`、`user`、`status`、`start_time`、`end_time` 和 `event_log_path`，并将这些信息维护在一个列表中。当用户通过 UI 访问时，`FsHistoryProvider` 会根据请求查询这个列表，找到相应的事件日志文件，然后进行完整的读取和解析。解析过程本质上是一个回放（replay）过程。事件日志文件中的每一行都是一个序列化的事件。系统将这些事件逐行反序列化，并通过 `ReplayListener` 将事件中的信息反馈到 KVStore 中，以还原应用程序的状态。在 Spark 中，KVStore 存储各种类实例，这些实例反映了任务和应用程序的状态。前端 UI 从 KVStore 查询所需的对象数据，实现页面的动态渲染和状态展示。

 

 

# 3. SHS Rest API

SHS 是基于内嵌的 jetty 来构建 HTTP 服务的，代码详见上一节。这里简单介绍一下 jetty 的架构，jetty 架构的核心是 Handler。一个请求过来时，会解析然后被封装成 Request，之后会交给 Server 对象中的 Handler 处理。Server 的 Handler 可以是各种类型的 Handler，因为 SHS 里面注入的是 ContextHandlerCollection，这里只介绍 ContextHandlerCollection。这个类也是 Handler 的一个实现类，可以理解为是 Handler 的集合，**持有一系列 Handler 对象，同时还能起到路由器的作用**。ContextHandlerCollection 基于 ArrayTernaryTrie 构造了一个字典树，用于快速匹配路径。当收到一个请求时，ContextHandlerCollection 根据 URL 找到对应的 Handler，然后把请求交给这个 Handler 去处理。Handler 里面封装了各种我们自己实现的 Servlet，最终请求就落到了具体的那个 Servlet 上执行了。

![SHS Rest API](<./images/SHS Rest API.png>)

SHS 在启动时，会往 ContextHandlerCollection 中加入一个 ServletContextHandler，这里放着 jersey 的 ServletContainer 类，用来提供 restful api。**jersey 会自动解析 org.apache.spark.status.api.v1 包下面的类，然后将对应的请求转发过去**。SHS 启动时还会注册其它 Handler，这里不多做介绍。

**任务的 applications 信息是长期驻留在内存并不断更新的**。当我们在页面点击查看某个任务的运行详情时，SHS 就会重新去解析对应 EventLog 日志文件，这时就是解析整个 EventLog 文件了，然后将构建好的详情信息保存到缓存中。它的缓存使用了 guava 的 LoadingCache，在将任务信息放入缓存的同时，SHS 还会提前构建好这个任务的各种状态的 SparkUI（也就是 web 界面)，并创建好 ServletContextHandler，然后放到 ContextHandlerCollection 中去。

 

 

# 4. 参考

1. [Spark Monitoring 官网](https://spark.apache.org/docs/3.1.3/monitoring.html)

2. [Spark History Server 和 Event Log 详解](https://blog.csdn.net/littlePYR/article/details/104621255)

3. [Spark History Server 架构原理介绍](https://blog.csdn.net/u013332124/article/details/88350345)

   