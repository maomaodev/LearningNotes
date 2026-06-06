说明：代码部分以 Kyuubi 1.9.0、Spark 3.4.2 为例讲解

# 1. Kyuubi 服务端与客户端

**首先区分 Kyuubi 服务端 Principal 和客户端 Principal，参考官方说明：**[**Kyuubi kerberos-authentication**](https://kyuubi.readthedocs.io/en/master/client/jdbc/kyuubi_jdbc.html#kerberos-authentication)。对于 Kerberos 认证，有两种方式：

- **使用 Principal 和 Keytab**，JDBC 连接串类似：`jdbc:kyuubi://host:port/schema;kyuubiClientPrincipal=<clientPrincipal>;kyuubiClientKeytab=<clientKeytab>;kyuubiServerPrincipal=<serverPrincipal>`，其中 kyuubiClientKeytab、kyuubiClientPrincipal分别为 Kyuubi 客户端 Keytab 和 Principal，kyuubiServerPrincipal 为 Kyuubi 服务端 Principal（自 1.7.0 版本起，kyuubiServerPrincipal 可作为 principal 别名使用，旧版本使用 principal）。
- **使用 Principal 和 TGT Cache**，JDBC 连接串类似：`jdbc:kyuubi://host:port/schema;kyuubiServerPrincipal=<serverPrincipal>;kyuubiClientTicketCache=<clientTicketCache>`，其中 kyuubiClientTicketCache 为 Kyuubi 客户端 TGT 缓存，需要先使用 kinit 生成 TGT 缓存。

在《Kyuubi 架构设计与源码剖析》介绍过，KinitAuxiliaryService 用于 Kerberos 认证，该类实现比较简单，只是在后台单线程周期性执行：`kinit -kt keytab principal`。**这里的 Keytab 和 Principal 指的就是 Kyuubi 服务端的 Keytab 和 Principal**，目的是防止 Kyuubi 服务端的认证过期。

 

# 2. Kyuubi 服务端与 Spark 引擎

上面的参数是 Kyuubi 客户端与 Kyuubi 服务端之间，Kyuubi 服务端与后端 Spark 引擎之间也有两种方式，参考官方说明：[Kyuubi hadoop_credentials_manager](https://kyuubi.readthedocs.io/en/master/security/hadoop_credentials_manager.html)。

- **使用当前 Kerberos 用户，并附加参数 --proxy-user 提交**
- **指定参数 spark.kerberos.principal 和 spark.kerberos.keytab 提交**

**如果引擎提交时指定了 --proxy-user，则其 Hadoop 集群服务的 Delegation Token 由当前 Kerberos 用户获取，且无法由引擎自身更新/续期。因此，引擎的生命周期受 Delegation Token 有效期的限制。为消除该限制，kyuubi 在 Hadoop Credentials Manager 中的服务器端更新委托令牌。使用 Keytab 和 Principal 提交的引擎可以自行更新 Delegation Token（参考：《Spark Kerberos》），但为了简化实现，kyuubi 服务端也会为其更新。**

```scala
class SparkProcessBuilder(...) extends ProcBuilder with Logging {
  
  protected def setupKerberos(buffer: mutable.Buffer[String]): Unit = {
    // 如果指定了spark.kerberos.keytab、spark.kerberos.principal，就不支持PROXY_USER
    tryKeytab() match {
      // doAsEnabled来自参数kyuubi.engine.doAs.enabled，表示在启动引擎时，是否启用用户代理模式，默认为true
      // 当启用此时，对于支持用户代理的引擎（如SPARK），根据kyuubi.engine.share.level的配置，将使用不同的用户来启动引擎
      // 否则，将始终使用Kyuubi服务器的用户来启动引擎
      case None if doAsEnabled =>
        setSparkUserName(proxyUser, buffer)
        buffer += PROXY_USER
        buffer += proxyUser
      case None =>
        // 关闭用户代理模式
        setSparkUserName(Utils.currentUser, buffer)
      case Some(name) =>
        // 指定了spark.kerberos.keytab、spark.kerberos.principal
        setSparkUserName(name, buffer)
    }
  }
  
  // ...
}
```

 

# 3. Kyuubi DT 自动更新

1、当第一次建立 KyuubiServer Session 时，KyuubiSessionImpl 将调用 HadoopCredentialsManager 类 renewCredentials 方法获取 DT，获取的 DT 将保存在 userCredentialsRefMap 中，以便下次直接从内存中获取。接着，KyuubiSessionImpl 将获取的 DT 作为请求参数之一，发送给 SparkSQLEngine，也就是说，**SparkSQLEngine 在第一次启动时，可以看到 spark-submit 设置了如下参数：**`--conf spark.kyuubi.engine.credentials=xxx --conf spark.kyuubi.session.user.credentials=xxx`。

```scala
KyuubiSessionImpl
  // engineCredentials、sessionUserCredentials初始化：均调用HadoopCredentialsManager类renewCredentials方法
  private lazy val engineCredentials = renewEngineCredentials()
    sessionManager.credentialsManager.renewCredentials(engine.appUser)
      getOrCreateUserCredentialsRef(appUser, true)
        // userCredentialsRefMap是一个保存用户DT的ConcurrentHashMap
        userCredentialsRefMap.computeIfAbsent(appUser, ...)
          scheduleRenewal(ref, 0, waitUntilCredentialsReady)
            updateCredentials(userRef)
              // 参数：kyuubi.credentials.{serviceName}.enabled，控制是否开启获取DT，默认开启（serviceName分别为hadoopfs、hive）
              providers.values.foreach(_.obtainDelegationTokens(userRef.getAppUser, creds))
                // 继承关系：HadoopFsDelegationTokenProvider -> HadoopDelegationTokenProvider
                doAsProxyUser(owner) { ... fs.addDelegationTokens(renewer, creds) ... }
                // 继承关系：HiveDelegationTokenProvider -> HadoopDelegationTokenProvider
                client.foreach { ... client.getDelegationToken(owner, principal) ... }
  private lazy val sessionUserCredentials = renewSessionUserCredentials()
    // 调用过程同上
    sessionManager.credentialsManager.renewCredentials(user)
  openEngineSession
    // engineCredentials不为空时，spark-submit启动SparkSQLEngine设置参数kyuubi.engine.credentials
    if (engineCredentials.nonEmpty)
      sessionConf.set(KYUUBI_ENGINE_CREDENTIALS_KEY, engineCredentials)
      Map(KYUUBI_ENGINE_CREDENTIALS_KEY -> engineCredentials)
    // sessionUserCredentials不为空时，spark-submit启动SparkSQLEngine设置参数kyuubi.session.user.credentials
    if (sessionUserCredentials.nonEmpty)
      sessionConf.set(KYUUBI_SESSION_USER_CREDENTIALS_KEY, sessionUserCredentials)
      Map(KYUUBI_SESSION_USER_CREDENTIALS_KEY -> sessionUserCredentials)
```

 

2、当 SparkSQLEngine 第一次启动时，将首先通过 Spark API 创建 SparkSession 对象，**如果 Kyuubi 使用代理用户的方式提交任务，SparkSession 会更新一次 DT，并直接忽略 DT 下次更新的时间，即 Spark 此时不会自行更新 DT**。接着，SparkSQLEngine 比较 `kyuubi.engine.credentials` 与当前用户的 Credentials 的时间，由于 SparkSession 启动时又更新了 DT，所以 KyuubiSessionImpl 传递过来的 DT 一般会被忽略。

```scala
SparkSQLEngine
  main(args: Array[String])
    spark = createSpark()
      // 通过Spark API创建SparkSession对象，后续SQL真正执行都会交由其去执行
      val session = SparkSession.builder.config(_sparkConf).getOrCreate
        // 以下为Spark源码
        _taskScheduler.start()
          // 继承关系：YarnSchedulerBackend -> CoarseGrainedSchedulerBackend -> SchedulerBackend，
          // 实际执行CoarseGrainedSchedulerBackend.start()
          backend.start()
            // 创建Delegation Token管理器，YarnSchedulerBackend复写了父类CoarseGrainedSchedulerBackend的createTokenManager()方法
            delegationTokenManager = createTokenManager()
              new HadoopDelegationTokenManager(sc.conf, sc.hadoopConfiguration, driverEndpoint)
            // 参数spark.kerberos.renewal.credentials，可选值为keytab（默认）、ccache
            // 参见renewalEnabled定义，当Kyuubi指定参数spark.kerberos.principal和spark.kerberos.keytab提交任务时，
            // Spark将启动Delegation Token管理器，定期更新所需的新DT，后续流程参考【Spark Kerberos】专题介绍
            if (dtm.renewalEnabled) { dtm.start() }
            // 当Kyuubi使用代理用户的方式提交任务时，Spark将为指定服务获取DT，但不会自行更新DT
            else dtm.obtainDelegationTokens(creds)
              // DT下次更新的时间直接被忽略
              val (newTokens, _) = obtainDelegationTokens()
                // 当前支持：Hadoop、Hive、Hbase、Kafka
                provider.obtainDelegationTokens(hadoopConf, sparkConf, creds)
      // 更新DT，credentials为参数kyuubi.engine.credentials，spark-submit提交时设置了该参数
      SparkTBinaryFrontendService.renewDelegationToken(session.sparkContext, credentials)
        // newCreds为参数kyuubi.engine.credentials，oldCreds为当前用户的Credentials
        val newCreds = KyuubiHadoopUtils.decodeCredentials(delegationToken)
        val oldCreds = UserGroupInformation.getCurrentUser.getCredentials
        // 比较oldCreds与newToken的IssueDate，若newToken较新才update，否则忽略
        addOtherTokens(otherTokens, oldCreds, updateCreds)
          if (compareIssueDate(newToken, oldToken) > 0)
            updateCreds.addToken(alias, newToken)
          else
            // 由于SparkSession启动时又更新了DT，所以KyuubiSessionImpl传递过来的DT一般会被忽略
            warn(s"Ignore token with earlier issue date: $newToken")
        if (updateCreds.numberOfTokens() > 0)
          info("Update delegation tokens. " + s"...")
          SparkContextHelper.updateDelegationTokens(sc, updateCreds)
            // 向Spark Driver发送一条UpdateDelegationTokens消息
            backend.driverEndpoint.send(UpdateDelegationTokens(bytes))
```

 

3、当 Kyuubi Server 启动时，将初始化并启动 HadoopCredentialsManager Service，它将初始化两个线程池。**其中 renewalExecutor 线程池用于更新 DT，不过当前尚未调度任务，直到调用 getOrCreateUserCredentialsRef 方法**：①当 KyuubiServer Session 建立时，KyuubiSessionImpl 将调用 renewCredentials 方法 ② 当 KyuubiServer SQL 执行时，ExecuteStatement 将调用 sendCredentialsIfNeeded 方法。两者都会调用 getOrCreateUserCredentialsRef 方法，若 userCredentialsRefMap 存在用户 Credentials，则直接获取； 否则使用 renewalExecutor 后台线程更新 DT，然后添加到 userCredentialsRefMap 中。**另一个 credentialsTimeoutChecker 线程池则在后台定期检查 DT 空闲时间是否超过** `kyuubi.credentials.idle.timeout`**，若超过，则从 userCredentialsRefMap 中移除**。

```scala
HadoopCredentialsManager
  start()
    // 初始化后台单线程renewalExecutor，用于更新Delegation Token，当前尚未调度任务，直到调用getOrCreateUserCredentialsRef方法
    // ①当KyuubiServer Session建立时，KyuubiSessionImpl将调用renewCredentials方法
    // ②当KyuubiServer SQL执行时，ExecuteStatement将调用sendCredentialsIfNeeded方法
    // 两者都会调用getOrCreateUserCredentialsRef方法，若userCredentialsRefMap存在用户Credentials，则直接获取；
    // 否则使用renewalExecutor后台线程更新Delegation Token，然后添加到userCredentialsRefMap中
    renewalExecutor = Some(ThreadUtils.newDaemonSingleThreadScheduledExecutor("Delegation Token Renewal Thread"))
    // 初始化后台单线程credentialsTimeoutChecker，用于周期性检查用户Credentials是否超时。若超时，
    // 则从userCredentialsRefMap中移除，下次调用getOrCreateUserCredentialsRef方法重新添加
    credentialsTimeoutChecker = Some(ThreadUtils.newDaemonSingleThreadScheduledExecutor("User Credentials Timeout Checker"))
    // 调用startTimeoutChecker方法启动
    startTimeoutChecker()
      credentialsTimeoutChecker.foreach { ... checkTask ... }
        for ((user, userCred) <- userCredentialsRefMap.asScala)
          // 参数kyuubi.credentials.idle.timeout，默认为6小时
          if (userCred.getNoOperationTime >= credentialsTimeout)
            userCredentialsRefMap.remove(user)
```

 

# 4. 参考

1. [Kyuubi 官网](https://kyuubi.readthedocs.io/en/master/security/hadoop_credentials_manager.html)。

2. 《Kyuubi 架构设计与源码剖析》

3. 《Spark Kerberos》

   

 
