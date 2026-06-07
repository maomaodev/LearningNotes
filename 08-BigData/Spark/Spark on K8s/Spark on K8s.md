说明：代码部分以 spark 3.4.2 为例讲解，辅以 spark 3.1.3。

# 1. 作业提交流程

1、命令行提交命令：与《Spark Core》类似。

2、从 SparkSubmit 类的 main() 方法开始。注意，在 Client 模式下，childMainClass = org.apache.spark.examples.SparkPi。而在 Cluster 模式下，childMainClass = org.apache.spark.deploy.k8s.submit.KubernetesClientApplication。下面先以 Cluster 模式为例，讲解后续流程。由于 SparkPi 任务运行后就立马结束了，没有足够的时间进入 Driver/Executor Pod 观察进程等情况，因此这里以 Kyuubi 提交 Spark 任务作为演示。

```scala
SparkSubmit
  main(args)
    doSubmit(args)
      // 解析参数，args是命令行参数
      parseArguments(args)
        // 例如，解析--master得到：maybeMaster=k8s://https://kubernetes.default.svc、解析--class得到：mainClass=org.apache.spark.examples.SparkPi
        parse(args.asJava)
        				
      submit()
        doRunMain()
          // 使用提交的参数运行子类的main方法
          runMain()
            // 【Cluster】childMainClass => org.apache.spark.deploy.k8s.submit.KubernetesClientApplication
            // 【Client】 childMainClass => org.apache.spark.examples.SparkPi
            (childArgs, childClasspath, sparkConf, childMainClass) = prepareSubmitEnvironment(args)
            // 通过反射获取Class类对象
            mainClass = Utils.classForName(childMainClass)
            // 判断条件：mainClass是否为SparkApplication实现类
            if (classOf[SparkApplication].isAssignableFrom(mainClass))
              // 【Cluster】通过反射调用KubernetesClientApplication构造方法，生成实例
              mainClass.getConstructor().newInstance().asInstanceOf[SparkApplication]
              // 【client】在本地通过反射执行main方法，即此时即生成了Driver
              new JavaMainApplication(mainClass)
            app.start(childArgs.toArray, sparkConf)
```

通过 Kyuubi 提交 Spark 任务后，新开一个窗口重新进入 Kyuubi Pod，查看 Pod 内执行的进程，如下图所示。Client 端确实启动了一个 Java 进程，且主方法是 org.apache.spark.deploy.SparkSubmit，即**进程名为 SparkSubmit**。

![Spark on K8s Client进程](<./images/Spark on K8s Client进程.png>)

3、从 KubernetesClientApplication 类的 start() 方法开始。这里大致的处理逻辑就是，Client 通过 K8s 的 API 来写 Driver YAML 文件，然后向 K8s 集群申请创建 Driver Pod，最后通过 K8s Watch 机制监控 Driver Pod 的状态，一直等待作业完成才会退出。

```scala
KubernetesClientApplication
  start(args, conf)
    // 解析参数
    ClientArguments.fromCommandLineArgs(args)
    run(parsedArguments, conf)
      // 生成spark.app.id，以”spark-{UUID}”为模板。之所以重新生成而不直接使用提交的作业name，是因为pod需要打上label——spark-app-selector:{appId}，label的值有长度限制
      KubernetesConf.getKubernetesAppId()
      KubernetesConf.createDriverConf()
      // 启动Pod时，会给Pod添加一个watcher：LoggingPodStatusWatcher用来监听Pod事件，当Pod状态到达完成状态时，触发当前进程退出
      new LoggingPodStatusWatcherImpl(kubernetesConf)
      SparkKubernetesClientFactory.createKubernetesClient()
      new Client().run()
        // KubernetesDriverBuilder构建driver pod，与之类似，KubernetesExecutorBuilder构建executor pod
        resolvedDriverSpec = builder.buildFromFeatures(conf, kubernetesClient)
          // spark.kubernetes.driver.podTemplateFile参数配置driver pod模版文件
          initialPod = conf.get(Config.KUBERNETES_DRIVER_PODTEMPLATE_FILE)
          // features包含了多个FeatureStep，它们都实现了KubernetesFeatureConfigStep特质，可以理解为通过K8s的API来写YAML文件。KubernetesFeatureConfigStep特质定义了4个抽象方法：
          // ①configurePod：根据当前特性对给定的Pod进行修改，包括附加卷、添加环境变量、标签、注解 ②getAdditionalPodSystemProperties：返回根据当前特性在JVM上设置的任何系统属性
          // ③getAdditionalPreKubernetesResources：返回应添加的额外K8s资源，资源将在Pod创建之前进行设置/刷新 ④getAdditionalKubernetesResources：同上，不过资源将在Pod创建后进行设置/刷新。
          features = Seq(new BasicDriverFeatureStep(conf)...) ++ userFeatures
            // 基础设置：设置driver容器名称、镜像、拉取策略、三个端口（driver-rpc-port、blockmanager、spark-ui，仅提供声明）、部分环境变量、资源（CPU、内存）
            // 以及driver pod元数据（名称、标签、注解）、描述（重启策略、节点选择器、镜像拉取密码）
            new BasicDriverFeatureStep(conf)
            // K8s安全认证设置：必要时设置driver容器及driver pod卷，卷的类型为Secret，保存K8s安全相关的文件
            new DriverKubernetesCredentialsFeatureStep(conf)
            // service设置：service名为”{作业名前缀}-driver-svc”，暴露上面提到的driver-rpc-port、blockmanager、spark-ui三个端口，用于executor连接driver进行通信
            new DriverServiceFeatureStep(conf)
            // 挂载Secrets设置：解析参数--conf spark.kubernetes.driver.secrets.[SecretName]，将名为SecretName的Secret添加到driver pod指定路径上
            new MountSecretsFeatureStep(conf)
            // Secrets环境变量设置：解析参数--conf spark.kubernetes.driver.secretKeyRef.[EnvName]，在driver容器中添加名为EnvName（区分大小写）的环境变量
            new EnvSecretsFeatureStep(conf)
            // 挂载Volumes设置：解析参数--conf spark.kubernetes.driver.volumes.[VolumeType].[VolumeName].xxx，处理挂载路径/子路径、是否只读、卷选项、卷名称、卷类型（支持：HostPath、PVC、EmptyDir、NFS）
            new MountVolumesFeatureStep(conf)
            // Driver命令设置：创建drive运行命令，并传播所需的配置，driver容器参数依次为：driver --proxy-user xxx --properties-file xxx --class xxx {resource} {appArgs}
            new DriverCommandFeatureStep(conf)
            // Hadoop配置设置：以ConfigMap形式挂载hadoop配置，如core-site.xml、hdfs-site.xml
            // 若设置了HADOOP_CONF_DIR环境变量，则从指定的路径获取文件并挂载，否则使用参数spark.kubernetes.hadoop.configMapName指定的已存在的configmap
            new HadoopConfDriverFeatureStep(conf)
            // Kerberos配置设置：以ConfigMap形式挂载krb5.conf，若设置了spark.kubernetes.kerberos.krb5.configMapName，则直接使用已存在的configmap，否则创建名为“krb5-file”的configmap，挂载路径为“/etc/krb5.conf”
            // 以Secret形式挂载keytab（token），挂载卷名称为“hadoop-secret”，默认挂载路径为“/mnt/secrets/hadoop-credentials”，其中token secret名为“{作业名前缀}-delegation-tokens”
            new KerberosConfDriverFeatureStep(conf)
            // Pod模版设置：解析参数：--conf spark.kubernetes.executor.podTemplateFile，以ConfigMap形式挂载executor pod模版
            new PodTemplateConfigMapStep(conf)
            // LocalDirs设置：以EmptyDir形式挂载临时数据（shuffle数据、广播变量等）存储目录，卷名称为“spark-local-dir-${index}”，默认挂载路径为“/var/data/spark-{UUID}”
            new LocalDirsFeatureStep(conf)
          features.foldLeft(spec) { case (spec, feature) => val configuredPod = feature.configurePod(spec.pod) ...}
        
        // driver configmap名称为“spark-drv-{UUID}-conf-map”，executor configmap名称为“spark-exec-{UUID}-conf-map”
        KubernetesClientUtils.configMapNameDriver
        // 构建以key为文件名、value为文件内容的映射，其中包含了在SPARK_CONF_DIR中选择的所有文件
        // ConfigMap不支持存储二进制内容，因此排除jar、tar、gzip、zip等文件；同时排除所有模板文件和用户提供的Spark配置或属性，Spark属性将在不同的步骤中解析
        KubernetesClientUtils.buildSparkConfDirFilesMap()
        // 构建ConfigMap，保存上面SPARK_CONF_DIR中文件的内容
        KubernetesClientUtils.buildConfigMap()
        // 构建driver容器，新增一个环境变量SPARK_CONF_DIR=/opt/spark/conf；新增一个挂载卷，名为spark-conf-volume-driver，挂载路径为/opt/spark/conf
        val resolvedDriverContainer = new ContainerBuilder(resolvedDriverSpec.pod.container)....build()
        // 构建driver pod，新增上面构建的driver容器；新增一个名为spark-conf-volume-driver的卷，卷的类型为configmap
        // configmap名仍为“spark-drv-{UUID}-conf-map”，每个item的key与path保持一致，mode为420（420是十进制表示的八进制字面量0644）
        val resolvedDriverPod = new PodBuilder(resolvedDriverSpec.pod.pod)....build()
        
        // 在创建driver pod之前设置资源
        kubernetesClient.resourceList(preKubernetesResources: _*).createOrReplace()
        // 创建driver pod
        createdDriverPod = kubernetesClient.pods().inNamespace(conf.namespace).resource(resolvedDriverPod).create()
        // 刷新所有预先资源的所有者引用。创建的额外resource（如configmap/service/secret）通过k8s的OwnerReference关联到driver pod，以便于driver pod删除时这些资源一起回收掉
        addOwnerReference(createdDriverPod, preKubernetesResources)
        // 在创建driver pod之后设置资源，并刷新所有资源的所有者引用
        addOwnerReference(createdDriverPod, otherKubernetesResources)
        kubernetesClient.resourceList(otherKubernetesResources: _*).createOrReplace()

        // 如果spark.kubernetes.submission.waitAppCompletion没有设置成false（默认true），SparkSubmit进程会一直等待作业完成才会退出
        if (conf.get(WAIT_FOR_APP_COMPLETION))
          // 这里的watcher即之前创建的LoggingPodStatusWatcherImpl，可以实时监视driver pod的状态变化
          podWithName.watch(watcher)
          // watchOrStop在synchronized代码块中，循环判断podCompleted状态变量，直到pod完成，并返回podCompleted
          if (watcher.watchOrStop(sId))
            // 新增功能，当spark.kubernetes.delete.driver.after.complete设置为true时（默认false），将睡眠30s（spark.kubernetes.delete.driver.pod.delay）后，删除driver pod
            if (conf.get(KUBERNETES_SHOULD_DELETE_AFTER_DRIVER_COMPLETE))
              kubernetesClient.pods().withName(driverPodName).delete()
```

通过 Kyuubi 提交 Spark 任务，执行 `kubectl get pods -n  1-xxxx-2jaylvrp kyuubi-kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-4c6b364a-cf5e-4bd0-878e-5784b7b31836-driver  -o yaml` 导出的 driver yaml 文件示例如下。

```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    emr.tencentyun.com/appId: "1"
    emr.tencentyun.com/emr-instance: xxxx-2jaylvrp
    emr.tencentyun.com/emr-trade: "true"
    emr.tencentyun.com/uin: "909619400"
    ipip.ipv4.network.infra.tce.io/address: 10.0.2.67
    ipip.ipv4.network.infra.tce.io/attributes: "null"
    network.infra.tce.io/ipam-allocation-error: ""
    network.infra.tce.io/ipv4: 10.0.2.67
    network.infra.tce.io/type: ipip
    resource.emr.tencent.com/k8sCluster: global
    resource.emr.tencent.com/platForm: eks
    v1.multus-cni.io/default-network: ipip
  creationTimestamp: "2024-01-18T02:07:05Z"
  labels:
    kyuubi-unique-tag: 4c6b364a-cf5e-4bd0-878e-5784b7b31836
    spark-app-name: kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784
    spark-app-selector: spark-c3bfa25751d24f5abe6193f0ff1d12f2
    spark-role: driver
    spark-version: 3.4.2-xxxx-5.3.1_2023p4-SNAPSHOT
  name: kyuubi-kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-4c6b364a-cf5e-4bd0-878e-5784b7b31836-driver
  namespace: 1-xxxx-2jaylvrp
  resourceVersion: "22169640"
  selfLink: /api/v1/namespaces/1-xxxx-2jaylvrp/pods/kyuubi-kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-4c6b364a-cf5e-4bd0-878e-5784b7b31836-driver
  uid: 55285a1e-ef0a-431e-9379-1cfaf48262cc
spec:
  containers:
  - args:
    - driver
    - --proxy-user
    - hadoop
    - --properties-file
    - /opt/spark/conf/spark.properties
    - --class
    - org.apache.kyuubi.engine.spark.SparkSQLEngine
    - spark-internal
    env:
    - name: SPARK_USER
      value: hadoop
    - name: SPARK_APPLICATION_ID
      value: spark-c3bfa25751d24f5abe6193f0ff1d12f2
    - name: LOG_PATH
      value: /xxxx-2jaylvrp/spark-logs
    - name: SPARK_USER_NAME
      value: hadoop
    - name: SPARK_DRIVER_BIND_ADDRESS
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: status.podIP
    - name: SPARK_DRIVER_POD_NAME
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: metadata.name
    - name: SPARK_NAMESPACE
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: metadata.namespace
    - name: HADOOP_CONF_DIR
      value: /opt/hadoop/conf
    - name: HADOOP_TOKEN_FILE_LOCATION
      value: /mnt/secrets/hadoop-credentials/hadoop-tokens
    - name: SPARK_LOCAL_DIRS
      value: /var/data/spark-cd11787d-09dd-4b8a-8fbb-82a40b852676
    - name: SPARK_CONF_DIR
      value: /opt/spark/conf
    image: registry.chongqing.standard.dev-self-test.fsphere.cn/library/spark-task:v1.8.0-5.3.1.1
    imagePullPolicy: Always
    name: spark-kubernetes-driver
    ports:
    - containerPort: 7078
      name: driver-rpc-port
      protocol: TCP
    - containerPort: 7079
      name: blockmanager
      protocol: TCP
    - containerPort: 4040
      name: spark-ui
      protocol: TCP
    resources:
      limits:
        cpu: "2"
        memory: 1408Mi
      requests:
        cpu: "1"
        memory: 1408Mi
    terminationMessagePath: /dev/termination-log
    terminationMessagePolicy: File
    volumeMounts:
    - mountPath: /opt/hadoop/conf
      name: hadoop-properties
    - mountPath: /etc/krb5.conf
      name: krb5-file
      subPath: krb5.conf
    - mountPath: /mnt/secrets/hadoop-credentials
      name: hadoop-secret
    - mountPath: /var/data/spark-cd11787d-09dd-4b8a-8fbb-82a40b852676
      name: spark-local-dir-1
    - mountPath: /opt/spark/conf
      name: spark-conf-volume-driver
    - mountPath: /var/run/secrets/kubernetes.io/serviceaccount
      name: sa-inner-serviceruntime-token-rswmr
      readOnly: true
  dnsPolicy: ClusterFirst
  enableServiceLinks: true
  nodeName: 172.16.0.37
  priority: 0
  restartPolicy: Never
  schedulerName: default-scheduler
  securityContext: {}
  serviceAccount: sa-inner-serviceruntime
  serviceAccountName: sa-inner-serviceruntime
  terminationGracePeriodSeconds: 30
  tolerations:
  - effect: NoExecute
    key: node.kubernetes.io/not-ready
    operator: Exists
    tolerationSeconds: 300
  - effect: NoExecute
    key: node.kubernetes.io/unreachable
    operator: Exists
    tolerationSeconds: 300
  volumes:
  - configMap:
      defaultMode: 420
      items:
      - key: core-site.xml
        path: core-site.xml
      - key: hdfs-site.xml
        path: hdfs-site.xml
      name: kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-bd310d8d1a525155-hadoop-config
    name: hadoop-properties
  - configMap:
      defaultMode: 420
      items:
      - key: krb5.conf
        path: krb5.conf
      name: kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-bd310d8d1a525155-krb5-file
    name: krb5-file
  - name: hadoop-secret
    secret:
      defaultMode: 420
      secretName: kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-bd310d8d1a525155-delegation-tokens
  - emptyDir: {}
    name: spark-local-dir-1
  - configMap:
      defaultMode: 420
      items:
      - key: hbase-site.xml
        mode: 420
        path: hbase-site.xml
      - key: ranger-spark-audit.xml
        mode: 420
        path: ranger-spark-audit.xml
      - key: ranger-spark-security.xml
        mode: 420
        path: ranger-spark-security.xml
      - key: spark.properties
        mode: 420
        path: spark.properties
      name: spark-drv-f49a1d8d1a526a04-conf-map
    name: spark-conf-volume-driver
  - name: sa-inner-serviceruntime-token-rswmr
    secret:
      defaultMode: 420
      secretName: sa-inner-serviceruntime-token-rswmr
status:
  conditions:
  - lastProbeTime: null
    lastTransitionTime: "2024-01-18T02:07:05Z"
    status: "True"
    type: Initialized
  - lastProbeTime: null
    lastTransitionTime: "2024-01-18T02:07:08Z"
    status: "True"
    type: Ready
  - lastProbeTime: null
    lastTransitionTime: "2024-01-18T02:07:08Z"
    status: "True"
    type: ContainersReady
  - lastProbeTime: null
    lastTransitionTime: "2024-01-18T02:07:05Z"
    status: "True"
    type: PodScheduled
  containerStatuses:
  - containerID: docker://6f163c85e2b940ded064d4df6e497fc6f7d3032e7de22ef1097020dee9e71096
    image: registry.chongqing.standard.dev-self-test.fsphere.cn/library/spark-task:v1.8.0-5.3.1.1
    imageID: docker-pullable://registry.chongqing.standard.dev-self-test.fsphere.cn/library/spark-task@sha256:29c39d29269a0689c37808c4e762ed2fcbafd31666c4e73e8b65d2518ffeef05
    lastState: {}
    name: spark-kubernetes-driver
    ready: true
    restartCount: 0
    started: true
    state:
      running:
        startedAt: "2024-01-18T02:07:07Z"
  hostIP: 172.16.0.37
  phase: Running
  podIP: 10.0.2.67
  podIPs:
  - ip: 10.0.2.67
  qosClass: Burstable
  startTime: "2024-01-18T02:07:05Z"
```



# 2. Driver 启动

1、Driver Pod 被拉起后，将执行 Driver 容器的 ENTRYPOINT 入口点。将 args 参数传递给 spark-submit，然后**以 client 模式再次启动一个 SparkSubmit 进程**，参数 spark.driver.bindAddress 用于处理和查看作业运行过程中的 driver 日志（扩展功能）。这里也可以看出 cluster 模式与 client 模式的区别，**cluster 模式 driver 位于 K8s 集群内，而 client 模式 driver 位于 K8s 集群外**。

```scala
case "$1" in
  driver)
    mkdir -p /usr/local/service/hadoop/etc
    ln -sf /opt/hadoop/conf /usr/local/service/hadoop/etc/hadoop
    shift 1
    CMD=(
      "$SPARK_HOME/bin/spark-submit"
      --conf "spark.driver.bindAddress=$SPARK_DRIVER_BIND_ADDRESS"
      --deploy-mode client
      "$@"
    )
    ;;
  # ...
esac
```

执行 kubectl exec -it -n  1-xxxx-2jaylvrp kyuubi-kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-4c6b364a-cf5e-4bd0-878e-5784b7b31836-driver  -- bash 进入 Driver Pod，查看 Pod 内执行的进程，如下图所示。Driver 确实启动了一个 Java 进程，且主方法是 org.apache.spark.deploy.SparkSubmit，参数 deploy-mode 为 client，即**进程名为 SparkSubmit**。

![Spark on K8s Driver进程](<./images/Spark on K8s Driver进程.png>)

2、启动 SparkSubmit 的源码，和上文分析的一样，只不过这次是以 client 模式提交的，所以不会再调用到 org.apache.spark.deploy.k8s.submit.KubernetesClientApplication，而是直接调用到 --class 指定的作业类名的 main 方法，在当前例子中就是直接执行 org.apache.spark.examples.SparkPi 的 main 方法。按照规范，用户代码中需要先创建 SparkContext，因此接下来从 SparkContext 开始分析。

```scala
SparkContext
  // 1.创建spark执行环境
  _env = createSparkEnv(_conf, isLocal, listenerBus)
    SparkEnv.createDriverEnv()
      // 为driver或executor创建SparkEnv
      create()
        RpcEnv.create()
          new NettyRpcEnvFactory().create(config)
            nettyEnv = new NettyRpcEnv()
              // RpcAddress -> Outbox映射。当连接到远程的RpcAddress时，只需将消息放入其Outbox中，以实现非阻塞的send方法
              val outboxes = new ConcurrentHashMap[RpcAddress, Outbox]()
                // Outbox成员，链表结构存放消息，TransportClient可与TransportServer通信
                val messages = new java.util.LinkedList[OutboxMessage]
                var client: TransportClient = null
            Utils.startServiceOnPort()
              // startService是个函数参数，实际调用nettyEnv.startServer(）
              val (service, port) = startService(tryPort)
                // 创建一个服务器，尝试绑定到特定的主机和端口
                transportContext.createServer()
                  new TransportServer()
                    // hostToBind为driver启动参数--conf spark.driver.bindAddress指定的值，即pod ip；portToBind默认为7078。即在7078端口初始化driver rpc server，等待executor连接
                    init(hostToBind, portToBind)
                      // Netty API，其中ioMode = NIO/EPOLL，Linux不支持AIO，故采用EPOLL方式来模拟，默认使用NIO
                      new ServerBootstrap().group(bossGroup, workerGroup).channel(NettyUtils.getServerChannelClass(ioMode))...
  
  // 2.初始化心跳接收器，executor将向driver定时发送心跳
  _heartbeatReceiver = env.rpcEnv.setupEndpoint()
  // 3.创建TaskScheduler，负责Task级的调度
  val (sched, ts) = SparkContext.createTaskScheduler(this, master)
    // 返回类型ExternalClusterManager，其有3个子类：KubernetesClusterManager、MesosClusterManager、YarnClusterManager，后面调用的都是KubernetesClusterManager重写的方法
    case masterUrl => val cm = getClusterManager(masterUrl)
    // 返回TaskSchedulerImpl实例
    val scheduler = cm.createTaskScheduler(sc, masterUrl)
    // 返回KubernetesClusterSchedulerBackend实例，该类继承自CoarseGrainedSchedulerBackend
    val backend = cm.createSchedulerBackend(sc, masterUrl, scheduler)
    // 初始化backend，SchedulerBackend是TaskScheduler重要成员，用于和外部组件进行通信交互
    cm.initialize(scheduler, backend)
      // 这里还构建了任务调度池，分为FIFOSchedulableBuilder（默认）、FairSchedulableBuilder两种
      scheduler.asInstanceOf[TaskSchedulerImpl].initialize(backend)
  _schedulerBackend = sched
  _taskScheduler = ts
  // 4.创建DAGScheduler，负责Stage级的调度
  _dagScheduler = new DAGScheduler(this)
  
  _taskScheduler.start()
    // 实际执行KubernetesClusterSchedulerBackend类的start()方法
    backend.start()
      // 父类CoarseGrainedSchedulerBackend启动线程，定期获取并刷新token
      super.start()
      // AbstractPodsAllocator是一个分配不同类型Pod的抽象类，其有2个子类：StatefulSetPodsAllocator、ExecutorPodsAllocator（默认）
      podAllocator.start(applicationId(), this)
        // 启动executor之前，等待driver pod准备就绪，否则无法通过DNS解析headless service
        kubernetesClient.pods()....waitUntilReady()
        // ExecutorPodsSnapshotsStoreImpl控制executor pod状态传播给订阅者，以便对该状态做出反应。应用程序的所有executor pod的状态组合称为快照，大致遵循生产者-消费者模型：
        // 生产者以两种方式推送更新，通过updatePod()发送的增量更新表示单个executor pod的已知新状态；通过replaceSnapshot()发送的完整同步表示所有executor pod的最新状态
        // 订阅者注册希望了解executor pod的所有快照。每当存储库增量更新或完整同步替换其最新的快照时，更新后的最新快照将被发布到订阅者的缓冲区，订阅者按时间窗口分块接收生产者生成的快照
        snapshotsStore.addSubscriber(podAllocationDelay) { onNewSnapshots() }
          subscribersExecutor.scheduleWithFixedDelay(() => newSubscriber.processSnapshots(), ...)
            processSnapshotsInternal()
              // 从订阅者缓冲区获取快照，并回调处理，onNewSnapshots即回调函数
              onNewSnapshots(snapshots.asScala.toSeq)
                requestNewExecutors()
                  // executor pvc重用
                  val reusablePVCs = getReusablePVCs(applicationId, pvcsInUse)
                  // KubernetesDriverBuilder构建driver pod，与之类似，KubernetesExecutorBuilder构建executor pod
                  val resolvedExecutorSpec = executorBuilder.buildFromFeatures()
                    // spark.kubernetes.executor.podTemplateFile参数配置executor pod模版文件
                    initialPod = conf.get(Config.KUBERNETES_EXECUTOR_PODTEMPLATE_FILE)
                    // 与构建driver pod类似，features包含了多个FeatureStep，它们都实现了KubernetesFeatureConfigStep特质，可以理解为通过K8s的API来写YAML文件
                    features = Seq(new BasicExecutorFeatureStep(conf, secMgr, resourceProfile)...) ++ userFeatures
                      // 基础设置：设置executor容器名称、镜像、拉取策略、部分环境变量、资源（CPU、内存）、volume、PreStop钩子
                      // 以及executor pod元数据（名称、标签、注解、OwnerReference）、描述（主机名、重启策略、节点选择器、镜像拉取密码）、调度器
                      new BasicExecutorFeatureStep(conf, secMgr, resourceProfile)
                      // K8s安全认证设置：若未通过pod模板进行设置，则使用executor service account，若executor也未设置，则使用driver service account
                      new ExecutorKubernetesCredentialsFeatureStep(conf)
                      // 挂载Secrets设置（同driver）：解析参数--conf spark.kubernetes.executor.secrets.[SecretName]，将名为SecretName的Secret添加到executor pod指定路径上
                      new MountSecretsFeatureStep(conf)
                      // Secrets环境变量设置（同driver）：解析参数--conf spark.kubernetes.executor.secretKeyRef.[EnvName]，在executor容器中添加名为EnvName（区分大小写）的环境变量
                      new EnvSecretsFeatureStep(conf)
                      // 挂载Volumes设置（同driver）：解析参数--conf spark.kubernetes.executor.volumes.[VolumeType].[VolumeName].xxx，处理挂载路径/子路径、是否只读、卷选项、卷名称、卷类型（支持：HostPath、PVC、EmptyDir、NFS）
                      new MountVolumesFeatureStep(conf)
                      // LocalDirs设置（同driver）：以EmptyDir形式挂载临时数据（shuffle数据、广播变量等）存储目录，卷名称为“spark-local-dir-${index}”，默认挂载路径为“/var/data/spark-{UUID}”
                      new LocalDirsFeatureStep(conf)
                    features.foldLeft(spec) { case (spec, feature) => val configuredPod = feature.configurePod(spec.pod) ...}
                  // 创建executor pod
                  val createdExecutorPod = kubernetesClient.pods().inNamespace(namespace).resource(podWithAttachedContainer).create()
                  // 刷新资源的所有者引用。创建的额外resource（如configmap/secret）通过k8s的OwnerReference关联到executor pod，以便于executor pod删除时这些资源一起回收掉
                  addOwnerReference(createdExecutorPod, resources)
                  // pvc重用：pvc OwnerReference为driver，因此生命周期随driver释放，这样即使executor挂掉，新拉起的executor也会复用之前的pvc，避免了pvc申请的消耗，提高性能，同时丢失的shuffle数据会自动恢复
                  addOwnerReference(driverPod.get, Seq(resource))
                  kubernetesClient.persistentVolumeClaims().inNamespace(namespace).resource(pvc).create()
      // 若开启了动态分配，executor个数取spark.dynamicAllocation.minExecutors、spark.dynamicAllocation.initialExecutors、spark.executor.instances三者最大值，默认未开启为2个
      val initExecs = Map(defaultProfile -> initialExecutors)
      // ExecutorPodsLifecycleManager订阅executor pod快照，针对executor pod不同状态打印日志，必要时删除executor pod
      lifecycleEventHandler.start(this)
        snapshotsStore.addSubscriber(eventProcessingInterval) { onNewSnapshots(schedulerBackend, _) }
      // ExecutorPodsWatchSnapshotSource实时监视executor pod，通过updatePod()发送当前executor pod的新状态
      watchEvents.start(applicationId())
        kubernetesClient.pods()....watch(new ExecutorPodsWatcher())
      // 逻辑与driver类似，构建ConfigMap，保存SPARK_CONF_DIR中文件的内容，executor configmap名称为“spark-exec-{UUID}-conf-map”，所有executor共用该configmap
      setUpExecutorConfigMap(podAllocator.driverPod)
        val confFilesMap = KubernetesClientUtils.buildSparkConfDirFilesMap()
        val labels = Map(SPARK_APP_ID_LABEL -> applicationId(), SPARK_ROLE_LABEL -> SPARK_POD_EXECUTOR_ROLE)
        KubernetesClientUtils.buildConfigMap(configMapName, confFilesMap, labels)
        kubernetesClient.configMaps().inNamespace(namespace).resource(configMap).create()
```

通过 Kyuubi 提交 Spark 任务，执行 `kubectl get pods -n  1-xxxx-2jaylvrp kyuubi-kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-4c6b364a-cf5e-4bd0-878e-5784b7b31836-exec-1  -o yaml` 导出的 executor yaml 文件示例如下。

```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    emr.tencentyun.com/appId: "1"
    emr.tencentyun.com/emr-instance: xxxx-2jaylvrp
    emr.tencentyun.com/emr-trade: "true"
    emr.tencentyun.com/uin: "909619400"
    ipip.ipv4.network.infra.tce.io/address: 10.0.2.73
    ipip.ipv4.network.infra.tce.io/attributes: "null"
    network.infra.tce.io/ipam-allocation-error: ""
    network.infra.tce.io/ipv4: 10.0.2.73
    network.infra.tce.io/type: ipip
    resource.emr.tencent.com/k8sCluster: global
    resource.emr.tencent.com/platForm: eks
    v1.multus-cni.io/default-network: ipip
  creationTimestamp: "2024-01-18T02:07:19Z"
  labels:
    spark-app-name: kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784
    spark-app-selector: spark-c3bfa25751d24f5abe6193f0ff1d12f2
    spark-exec-id: "1"
    spark-exec-resourceprofile-id: "0"
    spark-role: executor
    spark-version: 3.4.2-xxxx-5.3.1_2023p4-SNAPSHOT
    tcs_region: chongqing
    tcs_zone: cq1
  name: kyuubi-kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-4c6b364a-cf5e-4bd0-878e-5784b7b31836-exec-1
  namespace: 1-xxxx-2jaylvrp
  ownerReferences:
  - apiVersion: v1
    controller: true
    kind: Pod
    name: kyuubi-kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-4c6b364a-cf5e-4bd0-878e-5784b7b31836-driver
    uid: 55285a1e-ef0a-431e-9379-1cfaf48262cc
  resourceVersion: "22170123"
  selfLink: /api/v1/namespaces/1-xxxx-2jaylvrp/pods/kyuubi-kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-4c6b364a-cf5e-4bd0-878e-5784b7b31836-exec-1
  uid: b2797f98-7a9a-411e-befe-d86c1f415263
spec:
  containers:
  - args:
    - executor
    env:
    - name: SPARK_USER
      value: hadoop
    - name: SPARK_DRIVER_URL
      value: spark://CoarseGrainedScheduler@spark-4764e08d1a5257e9-driver-svc.1-xxxx-2jaylvrp.svc:7078
    - name: SPARK_EXECUTOR_CORES
      value: "1"
    - name: SPARK_EXECUTOR_MEMORY
      value: 1024m
    - name: SPARK_APPLICATION_ID
      value: spark-c3bfa25751d24f5abe6193f0ff1d12f2
    - name: SPARK_CONF_DIR
      value: /opt/spark/conf
    - name: SPARK_EXECUTOR_ID
      value: "1"
    - name: SPARK_RESOURCE_PROFILE_ID
      value: "0"
    - name: SPARK_USER_NAME
      value: hadoop
    - name: LOG_PATH
      value: /xxxx-2jaylvrp/spark-logs
    - name: SPARK_CLASSPATH
      value: /usr/local/service/spark/kyuubi-spark-authz/*
    - name: SPARK_JAVA_OPT_0
      value: -Djava.net.preferIPv6Addresses=false
    - name: SPARK_JAVA_OPT_6
      value: --add-opens=java.base/java.net=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_13
      value: --add-opens=java.base/sun.nio.cs=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_4
      value: --add-opens=java.base/java.lang.reflect=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_18
      value: -Dspark.driver.port=7078
    - name: SPARK_JAVA_OPT_1
      value: -XX:+IgnoreUnrecognizedVMOptions
    - name: SPARK_JAVA_OPT_10
      value: --add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_9
      value: --add-opens=java.base/java.util.concurrent=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_7
      value: --add-opens=java.base/java.nio=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_17
      value: -Djdk.reflect.useDirectMethodHandle=false
    - name: SPARK_JAVA_OPT_11
      value: --add-opens=java.base/jdk.internal.ref=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_2
      value: --add-opens=java.base/java.lang=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_16
      value: --add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_8
      value: --add-opens=java.base/java.util=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_12
      value: --add-opens=java.base/sun.nio.ch=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_15
      value: --add-opens=java.base/sun.util.calendar=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_3
      value: --add-opens=java.base/java.lang.invoke=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_19
      value: -Dspark.driver.blockManager.port=7079
    - name: SPARK_JAVA_OPT_14
      value: --add-opens=java.base/sun.security.action=ALL-UNNAMED
    - name: SPARK_JAVA_OPT_5
      value: --add-opens=java.base/java.io=ALL-UNNAMED
    - name: SPARK_EXECUTOR_POD_IP
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: status.podIP
    - name: SPARK_EXECUTOR_POD_NAME
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: metadata.name
    - name: SPARK_NAMESPACE
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: metadata.namespace
    - name: SPARK_LOCAL_DIRS
      value: /var/data/spark-cd11787d-09dd-4b8a-8fbb-82a40b852676
    image: registry.chongqing.standard.dev-self-test.fsphere.cn/library/spark-task:v1.8.0-5.3.1.1
    imagePullPolicy: Always
    name: spark-kubernetes-executor
    ports:
    - containerPort: 7079
      name: blockmanager
      protocol: TCP
    resources:
      limits:
        cpu: "2"
        memory: 1408Mi
      requests:
        cpu: "1"
        memory: 1408Mi
    terminationMessagePath: /dev/termination-log
    terminationMessagePolicy: File
    volumeMounts:
    - mountPath: /opt/spark/conf
      name: spark-conf-volume-exec
    - mountPath: /var/data/spark-cd11787d-09dd-4b8a-8fbb-82a40b852676
      name: spark-local-dir-1
    - mountPath: /var/run/secrets/kubernetes.io/serviceaccount
      name: sa-inner-serviceruntime-token-rswmr
      readOnly: true
  dnsPolicy: ClusterFirst
  enableServiceLinks: true
  hostname: 0-878e-5784b7b31836-4c6b364a-cf5e-4bd0-878e-5784b7b31836-exec-1
  nodeName: 172.16.0.37
  priority: 0
  restartPolicy: Never
  schedulerName: default-scheduler
  securityContext: {}
  serviceAccount: sa-inner-serviceruntime
  serviceAccountName: sa-inner-serviceruntime
  terminationGracePeriodSeconds: 30
  tolerations:
  - effect: NoExecute
    key: node.kubernetes.io/not-ready
    operator: Exists
    tolerationSeconds: 300
  - effect: NoExecute
    key: node.kubernetes.io/unreachable
    operator: Exists
    tolerationSeconds: 300
  volumes:
  - configMap:
      defaultMode: 420
      items:
      - key: hbase-site.xml
        mode: 420
        path: hbase-site.xml
      - key: ranger-spark-audit.xml
        mode: 420
        path: ranger-spark-audit.xml
      - key: ranger-spark-security.xml
        mode: 420
        path: ranger-spark-security.xml
      name: spark-exec-aba9028d1a529f87-conf-map
    name: spark-conf-volume-exec
  - emptyDir: {}
    name: spark-local-dir-1
  - name: sa-inner-serviceruntime-token-rswmr
    secret:
      defaultMode: 420
      secretName: sa-inner-serviceruntime-token-rswmr
status:
  conditions:
  - lastProbeTime: null
    lastTransitionTime: "2024-01-18T02:07:19Z"
    status: "True"
    type: Initialized
  - lastProbeTime: null
    lastTransitionTime: "2024-01-18T02:07:21Z"
    status: "True"
    type: Ready
  - lastProbeTime: null
    lastTransitionTime: "2024-01-18T02:07:21Z"
    status: "True"
    type: ContainersReady
  - lastProbeTime: null
    lastTransitionTime: "2024-01-18T02:07:19Z"
    status: "True"
    type: PodScheduled
  containerStatuses:
  - containerID: docker://52afa43413ba8f40905cd5e3d02e0a886713db90308c0e91cdf3492569ab3b7a
    image: registry.chongqing.standard.dev-self-test.fsphere.cn/library/spark-task:v1.8.0-5.3.1.1
    imageID: docker-pullable://registry.chongqing.standard.dev-self-test.fsphere.cn/library/spark-task@sha256:29c39d29269a0689c37808c4e762ed2fcbafd31666c4e73e8b65d2518ffeef05
    lastState: {}
    name: spark-kubernetes-executor
    ready: true
    restartCount: 0
    started: true
    state:
      running:
        startedAt: "2024-01-18T02:07:21Z"
  hostIP: 172.16.0.37
  phase: Running
  podIP: 10.0.2.73
  podIPs:
  - ip: 10.0.2.73
  qosClass: Burstable
  startTime: "2024-01-18T02:07:19Z"
```



# 3. Executor 启动

1、Executor Pod 被拉起后，将执行 Executor 容器的 ENTRYPOINT 入口点，启动的主类是 org.apache.spark.executor.CoarseGrainedExecutorBackend（和 standalone/yarn 模式一样）。

```shell
case "$1" in
  # ...
  executor)
    shift 1
    CMD=(
      ${JAVA_HOME}/bin/java
      "${SPARK_EXECUTOR_JAVA_OPTS[@]}"
      -Xms$SPARK_EXECUTOR_MEMORY
      -Xmx$SPARK_EXECUTOR_MEMORY
      -cp "$SPARK_CLASSPATH:$SPARK_DIST_CLASSPATH"
      org.apache.spark.executor.CoarseGrainedExecutorBackend
      --driver-url $SPARK_DRIVER_URL
      --executor-id $SPARK_EXECUTOR_ID
      --cores $SPARK_EXECUTOR_CORES
      --app-id $SPARK_APPLICATION_ID
      --hostname $SPARK_EXECUTOR_POD_IP
      --resourceProfileId $SPARK_RESOURCE_PROFILE_ID
    )
    ;;
esac
```

2、与《Spark Core》类似，这里直接复制过来稍加修改，从 CoarseGrainedExecutorBackend 类的 main() 方法开始。注意，CoarseGrainedExecutorBackend 间接继承 RpcEndpoint，**其生命周期为：constructor -> onStart -> receive\* -> onStop**。在构造过程中，它将通过 RPC 协议向 Driver 注册 Executor，一旦收到 Driver 注册成功的消息，就向自己发送一条消息，生成 Executor 计算对象。因此，**粗看 Executor 等同 CoarseGrainedExecutorBackend 通信后台，是个进程；细看 Executor 其实是个计算对象，里面有个线程池处理 Task**。

```scala
// 直接继承IsolatedRpcEndpoint，间接继承RpcEndpoint，endpoint生命周期为：constructor -> onStart -> receive* -> onStop
CoarseGrainedExecutorBackend
  main(args)
    // parseArguments解析参数，即上面通过java命令启动CoarseGrainedExecutorBackend时传递的参数，如--driver-url、--executor-id
    run(parseArguments(args, ...), createFn)
      // driver是一个指向driver-url地址的RpcEndpointRef，用于向driver发送同步消息，临时获取配置（包括token）信息后关闭
      val cfg = driver.askSync[SparkAppConfig](RetrieveSparkAppConfig(arguments.resourceProfileId))
      val env = SparkEnv.createExecutorEnv
        // 为driver或executor创建SparkEnv（与上面driver创建SparkEnv类似）
        create()
          RpcEnv.create()
            new NettyRpcEnvFactory().create(config)
              nettyEnv = new NettyRpcEnv()
                outboxes = new ConcurrentHashMap[RpcAddress, Outbox]
                  // Outbox成员，链表结构存放消息，TransportClient可与TransportServer通信
                  val messages = new java.util.LinkedList[OutboxMessage]
                  val client: TransportClient
              Utils.startServiceOnPort()
                // startService是个函数参数，实际调用nettyEnv.startServer(）
                val (service, port) = startService(tryPort)
                  // 创建一个服务器，尝试绑定到特定的主机和端口
                  transportContext.createServer()
                    new TransportServer()
                      init(hostToBind, portToBind)
                        // Netty API，其中ioMode = NIO/EPOLL，Linux不支持AIO，故采用EPOLL方式来模拟，默认使用NIO
                        new ServerBootstrap().group(bossGroup, workerGroup).channel(NettyUtils.getServerChannelClass(ioMode))...
                          
      // 使用指定名称注册一个RpcEndpoint，并返回其RpcEndpointRef。env.rpcEnv实际获取的是前面创建的NettyRpcEnv，它是RpcEnv的子类
      env.rpcEnv.setupEndpoint("Executor", backend)
        // Dispatcher是一个消息分发器，负责将RPC消息路由到适当的Endpoint
        dispatcher.registerRpcEndpoint(name, endpoint)
          // 创建一个指向driver地址的RpcEndpointRef，用于向driver发送消息
          val endpointRef = new NettyRpcEndpointRef()
          // 专用于单个RPC Endpoint的消息循环
          new DedicatedMessageLoop()
            inbox = new Inbox(name, endpoint)
              messages = new java.util.LinkedList[InboxMessage]()
              // OnStart是要处理的第一条消息
              messages.add(OnStart)
            // 在线程池中运行消息循环任务
            threadpool.execute(receiveLoopRunnable)
              receiveLoop()
                while (true) { inbox.process(dispatcher) }
                  // process()循环处理消息，取出刚刚存放的OnStart消息
                  message = messages.poll()
                  // 调用CoarseGrainedExecutorBackend类的onStart()处理
                  case OnStart => endpoint.onStart()
                    // 向driver注册executor，发送RegisterExecutor消息
                    ref.ask[Boolean](RegisterExecutor()）
                    // 如果注册成功，向自己发送一条消息。self是父类RpcEndpoint的属性，类型是RpcEndpointRef
                    case Success(_) => self.send(RegisteredExecutor)
                      // 根据endpoint生命周期，后续CoarseGrainedExecutorBackend类的receive()处理接收的消息，这里生成Executor计算对象
                      // 粗看Executor等同CoarseGrainedExecutorBackend通信后台，是个进程；细看Executor其实是个计算对象，里面有个线程池处理Task
                      case RegisteredExecutor => executor = new Executor()
                      // 处理Task，先调用TaskDescription.decode()反序列化
                      case LaunchTask(data) => executor.launchTask()
                        val tr = createTaskRunner(context, taskDescription)
                        // 计算对象Executor内部线程池处理Task
                        threadPool.execute(tr)
                          run()
                            task.run()
                              // Task类定义的抽象方法，由子类ShuffleMapTask、ResultTask实现
                              runTask()
      
      // Executor的主线程会一直等待，直到Driver发来StopExecutor消息才会退出。一般来说，StopExecutor会在Driver退出或SparkContext关闭时触发
      env.rpcEnv.awaitTermination()
        dispatcher.awaitTermination()
          shutdownLatch.await()
```

执行 `kubectl exec -it -n  1-xxxx-2jaylvrp kyuubi-kyuubi-connection-spark-sql-hadoop-4c6b364a-cf5e-4bd0-878e-5784b7b31836-4c6b364a-cf5e-4bd0-878e-5784b7b31836-exec-1 -- bash` 进入 Executor Pod，查看 Pod 内执行的进程，如下图所示。Executor 确实启动了一个 Java 进程，且主方法是 org.apache.spark.executor.CoarseGrainedExecutorBackend，即**进程名为 CoarseGrainedExecutorBackend**。同时，我们使用 netstat 命令查看 Executor Pod 中的网络情况，图中 7078 是 Driver rpc 端口，7079 是 Driver blockmanager 端口，Executor Server 由于没有指定端口，分配到了 41415。

![Spark on K8s Executor进程](<./images/Spark on K8s Executor进程.png>)



# 4. 总结

Spark on K8s Cluster 模式提交流程图如下图所示。

1、Client 提交任务后，**在本地启动一个名为 SparkSubmit 的进程，该进程通过 K8s 的 API 来编写 Driver YAML 文件**，然后向 K8s 集群申请创建 Driver Pod，最后通过 K8s Watch 机制监控 Driver Pod 的状态，一直等待作业完成才会退出。
2、K8s 拉起 Driver Pod 后，将执行 Driver 容器的 ENTRYPOINT 入口点，**它以 Client 模式在 Driver 容器中再次启动一个名为 SparkSubmit 进程**。
3、**SparkSubmit 进程将从用户提交的作业类名的 main 方法开始执行**，依次完成：创建Spark 执行环境、初始化心跳接收器、创建TaskScheduler（负责Task级的调度）、创建DAGScheduler（负责Stage级的调度）、启动 TaskScheduler（**通过 K8s 的 API 来编写 Executor YAML 文件，然后向 K8s 集群申请创建 Executor Pod**）等。
4、K8s 拉起 Executor Pod 后，将执行 Executor 容器的 ENTRYPOINT 入口点，**它在 Executor 容器中启动一个名为 CoarseGrainedExecutorBackend 进程**。
5、CoarseGrainedExecutorBackend 进程通过 RPC 协议向 Driver 注册 Executor，一旦收到 Driver 注册成功的消息，就向自己发送一条消息，生成 Executor 计算对象。
6、之后 Driver 与 Executor 通过 inbox、outbox 进行收发消息，执行任务。

![Spark On K8s Cluster模式流程图](<./images/Spark On K8s Cluster模式流程图.png>)



# 5. 参考

1、[Running Spark on Kubernetes 官网](https://spark.apache.org/docs/3.4.2/running-on-kubernetes.html)

2、[Spark on Kubernetes 作业执行流程](https://fanyilun.me/2021/08/22/Spark on Kubernetes作业执行流程/)

3、[Spark Kubernetes 的源码分析系列 - features](https://cloud.tencent.com/developer/article/1674888)

4、[Spark on K8s日志改造](https://iwiki.woa.com/p/4009413423)