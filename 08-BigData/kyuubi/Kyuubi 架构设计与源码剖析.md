说明：代码部分以 Kyuubi 1.9.0、Spark 3.4.2 为例讲解

# 1. Spark Thrift Server

## 1.1 产生背景

在最初使用 Spark 时，只有理解了Spark RDD 模型和其提供的各种算子时，才能比较好地使用 Spark 进行数据处理和分析，显然由于向上层暴露了过多底层实现细节，Spark 有一定的高使用门槛，在易用性上对许多初入门用户来说并不太友好。

Spark SQL 的出现则较好地解决了这一问题，通过使用 Spark SQL 提供的简易 API，用户只需要有基本的编程基础并且会使用 SQL，就可以借助 Spark 强大的快速分布式计算能力来处理和分析他们的大规模数据集。

而 Spark Thrift Server 的出现使 Spark 的易用性又向前迈进了一步，通过提供标准的 JDBC 接口和命令行终端的方式，平台开发者可以基于其提供的服务来快速构建它们的数据分析应用，普通用户甚至不需要有编程基础即可借助其强大的能力来进行交互式数据分析。

 

## 1.2 核心设计

顾名思义，本质上 Spark Thrift Server 是一个基于 Apache Thrift 框架构建并且封装了 SparkContext 的 RPC 服务端，或者从 Spark 的层面来讲，我们也可以说，Spark Thrift Server 是一个提供了各种 RPC 服务的 Spark Driver。但不管从哪个角度去看 Spark Thrift Server，有一点可以肯定的是，它是一个 Server，是需要对外提供服务的，因此其是常驻的进程，并不会像一般我们构建的 Spark Application 在完成数据处理的工作逻辑后就退出。其整体架构图如下所示，参考 [kyuubi_vs_thriftserver](https://kyuubi.readthedocs.io/en/master/overview/kyuubi_vs_thriftserver.html)：

![Spark Thrift Server架构图](<./images/Spark Thrift Server架构图.png>)



Apache Thrift 是业界流行的 RPC 框架，通过其提供的接口描述语言（IDL），可以快速构建用于数据通信的并且语言无关的 RPC 客户端和服务端，在带来高性能的同时，大大降低了开发人员构建 RPC 服务的成本，因此在大数据生态其有较多的应用场景，比如我们熟知的 hiveserver2 即是基于 Apache Thrift 来构建其 RPC 服务。

当用户通过 JDBC 或 beeline 方式执行一条 SQL 语句时，TThreadPoolServer 会接收到该 SQL，通过一系列的 Session 和 Operation 的管理，最终会使用在启动 Spark Thrift Server 时已经构建好的 SparkContext 来执行该 SQL，并获取最后的结果集。从上面的基本分析中我们可以看到，在不考虑 Spark Thrfit Server 的底层 RPC 通信框架和业务细节时，其整体实现思路是比较清晰和简单的。

当然实际上要构建一个对外提供 SQL 能力的 RPC 服务时，是有许多细节需要考虑的，并且工作量也会非常巨大，Spark Thrift Server 在实现时实际上也没有自己重复造轮子，它复用了 hiveserver2 的许多组件和逻辑，并根据自身的业务需求来对其进行特定改造；同样的，后面当我们去看 Kyuubi 时，也会发现它复用了 hiveserver2 和 Spark Thrift Server 的一些组件和逻辑，并在此基础上创新性地设计自己的一套架构。

 

## 1.3 基本实现

前面提到的 TThreadPoolServer 是 Apache Thrift 提供的用于构建 RPC Server 的一个工作线程池类，在 Spark Thrift Server 的 Service 体系结构中，ThriftBinaryCLIService 正是使用 TThreadPoolServer 来构建 RPC 服务端并对外提供一系列 RPC 服务接口，如下图所示： 

![Spark Thrift Server Service 体系](<./images/Spark Thrift Server Service 体系.webp>)

```java
// org.apache.hive.service.cli.thrift.ThriftBinaryCLIService参考hiveserver2实现，Hive中有相同的类
// 继承关系：ThriftBinaryCLIService -> ThriftCLIService -> AbstractService（并实现接口 TCLIService.Iface、Runnable）
public class ThriftBinaryCLIService extends ThriftCLIService {
  @Override
  protected void initializeServer() {
    // ...
    // 基于TThreadPoolServer构建RPC服务端
    server = new TThreadPoolServer(sargs);
    server.setServerEventHandler(serverEventHandler);
  }
}
```

TCLIService.Iface 提供的 RPC 服务接口如下，可以看到相当一部分接口都是提供 SQL 服务时所必要的能力。当然，不管是使用标准的 JDBC 接口还是通过 beeline 的方式来访问 Spark Thrift Server，必然都是通过 Spark 基于 Apache Thrift 构建的 RPC 客户端来访问这些 RPC 服务接口的，因此我们去看 Spark Thrift Server 提供的 RPC 客户端，其提供的方法接口与 RPC 服务端提供的是对应的，可以参考 `org.apache.hive.service.rpc.thrift.TCLIService.Client`。

如果比较难以理解，建议可以先研究一下 RPC 框架的本质，然后再简单使用一下 Apache Thrift 来构建 RPC 服务端和客户端，这样就会有一个比较清晰的理解，这里不对其底层框架和原理做更多深入的分析。个人觉得，要理解 Spark Thrift Server，或是后面要介绍的 Kyuubi，本质上是理解其通信框架，也就是其是怎么使用 Apache Thrift 来进行通信的，因为其它的细节都是业务实现。

```java
// org.apache.hive.service.rpc.thrift.TCLIService.Iface
public interface Iface {
    TOpenSessionResp OpenSession(TOpenSessionReq var1) throws TException;

    TCloseSessionResp CloseSession(TCloseSessionReq var1) throws TException;

    TGetInfoResp GetInfo(TGetInfoReq var1) throws TException;

    TExecuteStatementResp ExecuteStatement(TExecuteStatementReq var1) throws TException;

    TGetTypeInfoResp GetTypeInfo(TGetTypeInfoReq var1) throws TException;

    TGetCatalogsResp GetCatalogs(TGetCatalogsReq var1) throws TException;

    TGetSchemasResp GetSchemas(TGetSchemasReq var1) throws TException;

    TGetTablesResp GetTables(TGetTablesReq var1) throws TException;

    TGetTableTypesResp GetTableTypes(TGetTableTypesReq var1) throws TException;

    TGetColumnsResp GetColumns(TGetColumnsReq var1) throws TException;

    TGetFunctionsResp GetFunctions(TGetFunctionsReq var1) throws TException;

    TGetPrimaryKeysResp GetPrimaryKeys(TGetPrimaryKeysReq var1) throws TException;

    TGetCrossReferenceResp GetCrossReference(TGetCrossReferenceReq var1) throws TException;

    TGetOperationStatusResp GetOperationStatus(TGetOperationStatusReq var1) throws TException;

    TCancelOperationResp CancelOperation(TCancelOperationReq var1) throws TException;

    TCloseOperationResp CloseOperation(TCloseOperationReq var1) throws TException;

    TGetResultSetMetadataResp GetResultSetMetadata(TGetResultSetMetadataReq var1) throws TException;

    TFetchResultsResp FetchResults(TFetchResultsReq var1) throws TException;

    TGetDelegationTokenResp GetDelegationToken(TGetDelegationTokenReq var1) throws TException;

    TCancelDelegationTokenResp CancelDelegationToken(TCancelDelegationTokenReq var1) throws TException;

    TRenewDelegationTokenResp RenewDelegationToken(TRenewDelegationTokenReq var1) throws TException;

    TGetQueryIdResp GetQueryId(TGetQueryIdReq var1) throws TException;

    TSetClientInfoResp SetClientInfo(TSetClientInfoReq var1) throws TException;
}
```

 

## 1.4 主要不足

Spark Thrift Server 在带来各种便利性的同时，其不足也是显而易见的。

首先，Spark Thrift Server 难以满足生产环境下多租户与资源隔离的场景需求。由于一个 Spark Thrift Server 全局只有一个 SparkContext，也即只有一个 Spark Application，其在启动时就确定了全局唯一的用户名，因此在 Spark Thrift Server 的维护人员看来，所有通过 Spark Thrift Server 下发的 SQL 都是来自同一用户（也就是启动时确定的全局唯一的用户名），尽管其背后实际上是由使用 Spark Thrift Server 服务的不同用户下发的，但所有背后的这些用户都共享使用了 Spark Thrift Server 的资源、权限和数据，因此我们难以单独对某个用户做资源和权限上的控制，操作审计和其它安全策略。在 Spark Thrift Server 执行的一条 SQL 实际上会被转换为一个 job 执行，如果用户 A 下发的 SQL 的 job 执行时间较长，必然也会阻塞后续用户 B 下发的 SQL 的执行。

其次，单个 Spark Thrift Server 也容易带来单点故障问题。从 Spark Thrift Server 接受的客户端请求和其与 Executor 的通信来考虑，Spark Thrift Server 本身的可靠性也难以满足生产环境下的需求。

因此，在将 Spark Thrift Server 应用于生产环境当中，上面提及的问题和局限性都会不可避免，那业界有没有比较好的解决方案呢？网易开源的 Spark Kyuubi 就给出了比较好的答案。

 

# 2. Kyuubi 架构设计

Kyuubi 的整体架构设计如下，**可以分为用户层、服务发现层、Kyuubi Server 层、Kyuubi Engine 层**，如下图所示：

![Kyuubi 架构](<./images/Kyuubi 架构.png>)



## 2.1 用户层

用户层就是指实际需要使用 Kyuubi 服务的用户，它们通过不同的用户名进行标识，以 JDBC 或 beeline 方式进行连接。比如我们可以在 beeline 中指定以不同用户名进行登录：`./beeline -u 'jdbc:hive2://10.2.10.1:10009' -n lifumao`。当然，这里的用户名或登录标识并不是可以随意指定或使用的，它应该根据实际使用场景由运维系统管理人员进行分配，并且其背后应当有一整套完整的认证、授权和审计机制，以确保整体系统的安全。

 

## 2.2 服务发现层

服务发现层主要是指 Zookeepr 服务，以及 Kyuubi Server 层的 KyuubiServer 实例和 Kyuubi Engine 层的 SparkSQLEngine 在上面注册的命名空间（即 node 节点），以提供负载均衡和高可用等特性，**因此它分为 Kyuubi Server 层的服务发现和 Kyuubi Engine 层的服务发现**。

Kyuubi Server 层的服务发现是需要用户感知的。**KyuubiServer 实例在启动之后都会向 Zookeeper 的 /kyuubi 节点下面创建关于自己实例信息的节点，主要是包含 KyuubiServer 实例监听的 host 和 port 这两个关键信息**，这样用户在连接 Kyuubi Server 时，只需要到 Zookeeper 的 /kyuubi 节点下面获取对应的服务信息即可，当有多个 KyuubiServer 实例时，选取哪一个实例进行登录，这个由用户自行决定，Kyuubi 本身并不会进行干预。在实际应用时也可以封装接口实现随机返回实例给用户，以避免直接暴露 Kyuubi 的底层实现给用户。

另外，KyuubiServer 实例是对所有用户共享，并不会存在特定 KyuubiServer 实例只对特定用户服务的问题。当然在实际应用时你也可以这么做，比如可以不对用户暴露服务发现，也就是不对用户暴露 Zookeeper，对于不同用户，直接告诉他们相应的 KyuubiServer 实例连接信息即可，不过这样一来，Kyuubi Server 层的高可用就难以保证了。

比如有多个在不同节点上启动的 KyuubiServer 实例，其在 Zookeeper 上面注册的信息如下：

```bash
[zk: 172.16.0.177:2181(CONNECTED) 0] ls /
[kyuubi, kyuubi_1.9.0_CONNECTION_SPARK_SQL, kyuubi_1.9.0_SERVER_SPARK_SQL, kyuubi_1.9.0_SERVER_SPARK_SQL_lock, kyuubi_1.9.0_USER_SPARK_SQL, kyuubi_1.9.0_USER_SPARK_SQL_lock]

[zk: 172.16.0.177:2181(CONNECTED) 1] ls /kyuubi
[serverUri=172.16.0.13:10009;version=1.9.0;sequence=0000000002, serverUri=172.16.0.164:10009;version=1.9.0;sequence=0000000001, serverUri=172.16.0.177:10009;version=1.9.0;sequence=0000000000, serverUri=172.16.0.195:10009;version=1.9.0;sequence=0000000004, serverUri=172.16.0.235:10009;version=1.9.0;sequence=0000000005, serverUri=172.16.0.3:10009;version=1.9.0;sequence=0000000003]

[zk: 172.16.0.177:2181(CONNECTED) 2] get -w /kyuubi/serverUri=172.16.0.13:10009;version=1.9.0;sequence=0000000002
172.16.0.13:10009
```

Kyuubi Engine 层的服务发现是不需要用户感知的，其属于 Kyuubi 内部不同组件之间的一种通信协作方式。**SparkSQLEngine 实例在启动之后都会向 Zookeeper 创建关于自己实例信息的节点，主要是包含该实例监听的 host 和 port 以及其所属 user 的相关信息，也就是说 SparkSQLEngine 实例并不是所有用户共享的，它是由用户独享的**。

比如 Kyuubi 系统中有多个不同用户使用了 Kyuubi 服务，启动了多个 SparkSQLEngine 实例，其在 Zookeeper 上面注册的信息如下：

```bash
[zk: 172.16.0.177:2181(CONNECTED) 0] ls /kyuubi_1.9.0_CONNECTION_SPARK_SQL
[hadoop, lifumao]
[zk: 172.16.0.177:2181(CONNECTED) 1] ls /kyuubi_1.9.0_CONNECTION_SPARK_SQL/hadoop/02995c75-8233-4190-b5cb-9e7cc06b74b7
[serverUri=172.16.0.177:42327;version=1.9.0;spark.driver.memory=4g;spark.executor.memory=4g;kyuubi.engine.id=application_1747756092437_0647;kyuubi.engine.url=172.16.0.177:40535;refId=02995c75-8233-4190-b5cb-9e7cc06b74b7;sequence=0000000000]
[zk: 172.16.0.177:2181(CONNECTED) 2] get -w /kyuubi_1.9.0_CONNECTION_SPARK_SQL/hadoop/02995c75-8233-4190-b5cb-9e7cc06b74b7/serverUri=172.16.0.177:42327;version=1.9.0;spark.driver.memory=4g;spark.executor.memory=4g;kyuubi.engine.id=application_1747756092437_0647;kyuubi.engine.url=172.16.0.177:40535;refId=02995c75-8233-4190-b5cb-9e7cc06b74b7;sequence=0000000000
172.16.0.177:42327

[zk: 172.16.0.177:2181(CONNECTED) 3] ls /kyuubi_1.9.0_SERVER_SPARK_SQL 
[hadoop]
[zk: 172.16.0.177:2181(CONNECTED) 4] ls /kyuubi_1.9.0_SERVER_SPARK_SQL/hadoop/default
[serverUri=172.16.0.177:46871;version=1.9.0;spark.driver.memory=4g;spark.executor.memory=4g;kyuubi.engine.id=application_1747756092437_0645;kyuubi.engine.url=172.16.0.177:34835;refId=9f982374-699c-4779-9ac7-2e41875a728b;sequence=0000000000]
[zk: 172.16.0.177:2181(CONNECTED) 5] get -w /kyuubi_1.9.0_SERVER_SPARK_SQL/hadoop/default/serverUri=172.16.0.177:46871;version=1.9.0;spark.driver.memory=4g;spark.executor.memory=4g;kyuubi.engine.id=application_1747756092437_0645;kyuubi.engine.url=172.16.0.177:34835;refId=9f982374-699c-4779-9ac7-2e41875a728b;sequence=0000000000
172.16.0.177:46871
[zk: 172.16.0.177:2181(CONNECTED) 6] ls /kyuubi_1.9.0_SERVER_SPARK_SQL_lock/hadoop/default
[leases, locks]

[zk: 172.16.0.177:2181(CONNECTED) 7] ls /kyuubi_1.9.0_USER_SPARK_SQL
[hadoop, lifumao]
[zk: 172.16.0.177:2181(CONNECTED) 8] ls /kyuubi_1.9.0_USER_SPARK_SQL/hadoop/default
[serverUri=172.16.0.177:42457;version=1.9.0;spark.driver.memory=4g;spark.executor.memory=4g;kyuubi.engine.id=application_1747756092437_0646;kyuubi.engine.url=172.16.0.177:33475;refId=d7b6862f-a212-4ad8-a19e-77798cdade5b;sequence=0000000000]
[zk: 172.16.0.177:2181(CONNECTED) 9] get -w /kyuubi_1.9.0_USER_SPARK_SQL/hadoop/default/serverUri=172.16.0.177:42457;version=1.9.0;spark.driver.memory=4g;spark.executor.memory=4g;kyuubi.engine.id=application_1747756092437_0646;kyuubi.engine.url=172.16.0.177:33475;refId=d7b6862f-a212-4ad8-a19e-77798cdade5b;sequence=0000000000
172.16.0.177:42457
[zk: 172.16.0.177:2181(CONNECTED) 10] ls /kyuubi_1.9.0_USER_SPARK_SQL_lock/hadoop/default
[leases, locks]
```

 

## 2.3 Kyuubi Server 层

**Kyuubi Server 层由多个不同的 KyuubiServer 实例组成，每个 KyuubiServer 实例本质上为基于 Apache Thrift 实现的 RPC 服务端，其接收来自用户的请求，但并不会真正执行该请求的相关 SQL 操作，只会作为代理转发该请求到 Kyuubi Engine 层用户所属的 SparkSQLEngine 实例上**。

整个 Kyuubi 系统中需要存在多少个 KyuubiServer 实例是由 Kyuubi 系统管理员决定的，根据实际使用 Kyuubi 服务的用户数和并发数，可以部署一个或多个 KyuubiServer 实例，以满足 SLA 要求。当然后续发现 KyuubiServer 实例不够时，可以横向动态扩容，只需要在 Kyuubi 中系统配置好 host 和 port，启动新的 KyuubiServer 实例即可。

 

## 2.4 Kyuubi Engine 层

**Kyuubi Engine 层由多个不同的 SparkSQLEngine 实例组成，每个 SparkSQLEngine 实例本质上为基于 Apache Thrift 实现的并且持有一个 SparkSession 实例的 RPC 服务端，其接收来自 KyuubiServer 实例的请求，并通过 SparkSession 实例来执行。在 Kyuubi 的 USER 共享层级上，每个 SparkSQLEngine 实例都是用户级别的，即不同的用户其会持有不同的 SparkSQLEngine 实例，以实现用户级别的资源隔离和控制**。

SparkSQLEngine 实例是针对不同的用户按需启动的。在 Kyuubi 整体系统启动之后，如果没有用户访问 Kyuubi 服务，实际上在整个系统中只有一个或多个 KyuubiServer 实例，当有用户通过 JDBC 或 beeline 的方式连接 KyuubiServer 实例时，其会在 Zookeeper 上去查找是否存在用户所属的 SparkSQLEngine 实例，如果没有，则通过 spark-submit 提交一个 Spark 应用，而这个 Spark 应用本身就是 SparkSQLEngine，启动后，基于其内部构建的 SparkSession 实例，即可为特定用户执行相关 SQL 操作。

 

## 2.5 整体协作流程

通过前面对各层的介绍，结合 Kyubbi Server 架构图，以用户 lifumao 访问 Kyuubi 服务为例来描述整个流程。

1. Kyuubi 系统管理员在大数据集群中启动了 3 个 KyuubiServer 实例和 1 个 Zookeeper 集群，其中 3 个 KyuubiServer 实例的连接信息分别为 10.2.10.1:10009（KyuubiServer_instance1）、10.2.10.1:10010（KyuubiServer_instance2） 和 10.2.10.2:1009（KyuubiServer_instance3）；
2. 用户 lifumao 通过 beeline 终端的方式连接了其中一个 KyuubiServer 实例：`./beeline -u 'jdbc:hive2://10.2.10.1:10009' -n lifumao`;
3. KyuubiServer_instance1 接收到 lifumao 的连接请求，会为该用户创建 Session 会话，同时会去 Zookeeper 上检查是否已经存在 lifumao 所属的 SparkSQLEngine 实例。如果已经存在，则获取其连接信息；如果不存在，则通过 spark-submit 的方式提交一个 Spark 应用，启动一个 SparkSQLEngine 实例；
4. KyuubiServer_instance1 在 Zookeeper 上没有找到 lifumao 所属的 SparkSQLEngine 实例信息，其通过 spark-submit 的方式启动了一个 SparkSQLEngine 实例；
5. 属于 lifumao 用户的新的 SparkSQLEngine_instance1 实例在 10.2.10.1 节点上进行启动，并且随机监听某个端口，启动后，其向 Zookeeper 注册自己的连接信息；
6. KyuubiServer_instance1 在检测到 SparkSQLEngine_instance1 启动成功后，会向其发送创建 Session 会话的连接请求；
7. SparkSQLEngine_instance1 收到 KyuubiServer_instance1 创建 session 会话的连接请求，则创建一个新的 Session 会话；
8. 用户启动 beeleine 完成并成功创建会话，接着用户执行 SQL 查询；
9. KyuubiServer_instance1 接收到 lifumao 的执行 SQL 查询的请求，会先检查是否存在 lifumao 所属的 SparkSQLEngine 实例；
10. KyuubiServer_instance1 找到 lifumao 所属的 SparkSQLEngine_instance1 实例，接着会为这次执行 SQL 的操作创建一个 Operation；
11. KyuubiServer_instance1 根据连接信息创建了一个 RPC Client，并且构建 SQL 执行的 RPC 请求，发到对应的 SparkSQLEngine_instance1 实例上；
12. SparkSQLEngine_instance1 接收到该请求后，会创建一个该 SQL 操作的 Operation，并且使用其内部的 SparkSession 实例来执行，最后将执行结果返回给KyuubiServer_instance1；
13. KyuubiServer_instance1 接收到 SparkSQLEngine_instance1 的执行结果，返回给用户，这样一次 SQL 查询操作就完成了。

Kyuubi 在整体 Server 端、Client 端以及其实现功能的设计上，是十分清晰的。透过整体协作流程我们可以看到：

- **站在用户层视角来看，其为 RPC 客户端，而为其提供 RPC 服务的是 Kyuubi Server 层，在这里，Kyuubi Server 是 RPC 服务端。**
- **站在 Kyuubi Server 层视角来看，其既是为用户层提供 RPC 服务的 RPC 服务端，同时也是使用 Kyuubi Engine 层 RPC 服务的 RPC 客户端。**
- **站在 Kyuubi Engine 层视角来看，其为 RPC 服务端，其为 Kyuubi Server 层提供 RPC 服务。**

 

# 3. Kyuubi 源码剖析

## 3.1 RPC 与 Apache Thrift 基本概述

RPC（Remote Procedure Call）即远程过程调用，如果按照百度百科的解释会非常羞涩难懂，但实际上我们就可以简单地把它理解为，一个进程调用另外一个进程的服务即可，不管是通过 Socket、内存共享或是网络的方式，只要其调用的服务的具体实现不是在调用方的进程内完成的就可以，目前我们见得比较多的是通过网络通信调用服务的方式。

在 Java 语言层面上比较普遍的 RPC 实现方式是，反射+网络通信+动态代理的方式来实现 RPC，而网络通信由于需要考虑各种性能指标，主要用的 Netty 或者原生的 NIO 比较多，Socket 一般比较少用，比如可以看一下阿里 Doubbo 的实现。

Apache Thrift 是业界流行的 RPC 框架，通过其提供的接口描述语言（IDL），可以快速构建用于数据通信的并且语言无关的 RPC 客户端和服务端，在带来高性能的同时，大大降低了开发人员构建 RPC 服务的成本，因此在大数据生态其有较多的应用场景，比如我们熟知的 hiveserver2 即是基于 Apache Thrift 来构建其 RPC 服务。

 

## 3.2 Kyuubi Service 体系与组合关系

在看 Kyuubi 源码时，我们可以把较多精力放在某几种较重要的类和其体系上，这样有助于我们抓住重点，理解 Kyuubi 最核心的部分。仅考虑 Kyuubi 整体的架构设计和实现，比较重要的是 Service、Session 和 Operation 等相关的类和体系。

### 3.2.1 Service 体系

Service 顾名思义就是服务，在 Kyuubi 中，各种不同核心功能的提供都是通过其 Service 体系下各个实现类来进行提供的。我们前面提到的服务发现层、Kyuubi Server 层和 Kyuubi Engine 层，在代码实现上绝大部分核心功能都是由 Kyuubi 源码项目的 Server 类体系来完成的，可以这么说，理解了 Service 体系涉及类的相关功能，就基本上从源码级别上理解了整个 Kyuubi 的体系架构设计和实现。当然这些 Service 的实现类并不一定使用 Service 结尾，比如 SessionManager、OperationManager 等，但基本上从名字我们就能对其功能窥探一二。其完整的继承关系如下：

![Kyuubi Service 体系](<./images/Kyuubi Service 体系.webp>)



基于 Kyuubi 提供的核心功能，我们可以大致按 Kyuubi Server 层和 Kyuubi Engine 层来将整个体系中的 Service 类进行一个划分：

**1、Kyuubi Server 层**

- **功能入口：KyuubiServer 提供 main 方法，是 Kyuubi Server 层 KyuubiServer 实例初始化和启动的入口；**
- **服务发现：KyuubiServiceDiscovery 封装了zkClient，用来与 Zookeeper 服务进行交互；**
- **核心功能：KyuubiTBinaryFrontendService 封装了 Apache Thrift 的 TThreadPoolServer，在 Kyuubi Server 层，其主要用于向用户层提供 RPC 服务；KyuubiBackendService 封装了来自用户层不同 RPC 请求的处理逻辑，比如 executeStatement、fetchResults 等；**
- **Session 管理：KyuubiSessionManager 提供对用户层的请求会话（session）管理；**
- **Operation 管理：KyuubiOperationManager 提供对用户层的请求操作（operation）管理；**

**2、Kyuubi Engine 层**

- **功能入口：SparkSQLEngine 提供 main 方法，是 Kyuubi Engine 层 SparkSQLEngine 实例初始化和启动的入口；**
- **服务发现：EngineServiceDiscovery：封装了 zkClient，用来与 Zookeeper 服务进行交互；**
- **核心功能：SparkTBinaryFrontendService 封装了 Apache Thrift 的 TThreadPoolServer，在 Kyuubi Engine 层，其主要用于向 Kyuubi Server 层提供 RPC 服务；SparkSQLBackendService 封装了来自 Kyuubi Server 层不同 RPC 请求的处理逻辑，比如 executeStatement、fetchResults 等；**
- **Session 管理：SparkSQLSessionManager 提供对 Kyuubi Server 层的请求会话（session）管理；**
- **Operation 管理：SparkSQLOperationManager 提供对 Kyuubi Server 层的请求操作（operation）管理；**

这里我们只对具体实现类进行归类，因为中间抽象类只是提取多个子类的公共方法，不影响我们对其体系功能的说明和讲解，而**以 Noop 开头的实际上是 Kyuubi 的测试实现类，KinitAuxiliaryService 是 Kyuubi 中用于认证的类**。通过对 Service 体系各个具体实现类的介绍，再回顾前面对 Kyuubi 整体架构和协作流程的介绍，其抽象的功能在源码实现类上面就有了一个相对比较清晰的体现，并且基本上也是可以一一对应上的。

 

### 3.2.2 Service 组合关系

为了理解 Kyuubi 在源码层面上是如何进行整体协作的，除了前面介绍的 Service 体系外，我们还有必要理清其各个 Service 之间的组合关系。在整个 Service 体系中，CompositeService 这个中间抽象类在设计上是需要额外关注的，它表示的是在它之下的实现类都至少有一个成员为其它 Service 服务类对象，比如对于 KyuubiServer，它的成员则包含有 KyuubiBackendService、KyuubiServiceDiscovery 等多个 Service 实现类，SparkSQLEngine 也是如此。我们将一些关键的 Service 类及其组合关系梳理如下，这对后面我们分析关键场景的代码执行流程时会提供很清晰的思路参考：

![Kyuubi Service 组合关系](<./images/Kyuubi Service 组合关系.png>)



**1、Session 与 SessionHandle**

- **Session**：当我们使用通过 JDBC 或 beeline 连接 Kyuubi 时，实际上在 Kyuubi 内部就为我们创建了一个 Session，用以标识本次会话的所有相关信息，后续的所有操作都是基于这次会话来完成的，我们可以在一次会话下执行多个操作（比如多次执行某次 SQL，我们只需要建立一次会话连接即可）。**Session 在 Kyuubi 中又分为 Kyuubi Server 层的 Session 和 Kyuubi Engine 层的 Session，前者实现类为 KyuubiSessionImpl，用来标识来自用户层的会话连接信息；后者实现类为 SparkSessionImpl，用来标识来自 Kyuubi Server 层的会话连接信息**。两个 Session 实现类都有一个共同的抽象父类 AbstractSession，用于 Session 操作的主要功能逻辑都是在该类实现的。
- **SessionHandle**：Session 对象的存储实际上由 SessionManager 来完成，在 SessionManager 内部其通过一个 Map 来存储 Session 的详细信息，其中 key 为 SessionHandle，value 为 Session 对象本身。**SessionHandle 可以理解为就是封装了一个唯一标识一个用户会话的字符串，这样用户在会话建立后进行通信时只需要携带该字符串标识即可，并不需要传输完整的会话信息，以避免网络传输带来的开销**。

**2、Operation 与 OperationHandle**

- **Operation**：用户在建立会话后执行的相关语句在 Kyuubi 内部都会抽象为一个个的 Operation，比如执行一条 SQL 语句对应的 Operation 实现类为 ExecuteStatement。不过需要注意，**Operation 又分为 Kyuubi Server 层的 KyuubiOperation 和 Kyuubi Engine 层的 SparkOperation，Kyuubi Server 层的 Operation 并不会执行真正的操作，它只是一个代理，会通过 RPC Client 请求 Kyuubi Engine 层来执行该 Operation，因此所有 Operation 的真正执行都是在 Kyuubi Engine 层来完成的**。由于 Operation 都是建立在 Session 之下的，所以从组合关系中可以看到，用于管理 Operation 的 OperationManager 为 SessionManager 的成员属性。
- **OperationHandle**：Operation 对象的存储实际上由 OprationManager 来完成，在 OprationManager 内部其通过一个 Map 来存储 Opration 的详细信息，其中 key 为 OperationHandle，value 为 Operation 对象本身。**OperationHandle 可以理解为就是封装了一个唯一标识一个用户操作的字符串，这样用户基于会话的操作时只需要携带该字符串标识即可，并不需要传输完整的操作信息，以避免网络传输带来的开销。第一次提交 Operation 时还是需要完整信息，后续只需要提供 OperationHandle 即可，实际上 SQL 语句的执行在 Kyuubi 内部是异步执行的，用户端在提交 Opeation 后即可获得 OperationHandle，后续只需要持着该 OperationHandle 去获取结果即可**，我们在分析 SQL 执行的代码时就可以看到这一点。

 

## 3.3 Kyuubi 启动流程

Kyuubi 的启动实际上包含两部分，分别是 KyuubiServer 的启动和 SparkSQLEngine 的启动。KyuubiServer 实例的启动发生在系统管理员根据实际业务需要启动 KyuubiServer 实例，这个是手动操作完成的；而 SparkSQLEngine 实例的启动则是在为用户建立会话时为由 KyuubiServer 实例通过 spark-submit 的方式去提交一个 Spark 应用来完成的。

### 3.3.1 KyuubiServer 启动流程

1、当我们在 Kyuubi 目录下执行 `bin/kyuubi start` 命令去启动 KyuubiServer 时，就会去执行 KyuubiServer 的 main 方法。在加载完配置信息后，就通过调用 `startServer(conf)` 方法，开始 KyuubiServer 的启动流程，KyuubiServer 的启动包括两部分：初始化和启动。我们前面提到，**KyuubiServer 为 Service 体系下的一个 CompositeService（参考前面给出的组合关系图），它本身又包含了多个 Service 对象，这些对象都保存在 serviceList 这个成员属性中，因此初始化和启动 KyuubiServer 实际上就是初始化和启动 serviceList 中所包含的各个 Service 对象。而这些 Service 对象本身又可能是 CompositeService，因此 KyuubiServer 的初始化和启动实际上就是一个递归初始化和启动的过程**。

```scala
// 继承关系：KyuubiServer -> Serverable -> CompositeService -> AbstractService -> Service
KyuubiServer
  main(args: Array[String])
    // 读取kyuubi-defaults.conf配置文件，并加载至内存
    val conf = new KyuubiConf().loadFileDefaults()
    // 启动KyuubiServer，包括两部分：初始化和启动
    startServer(conf)
      // 递归初始化Service
      server.initialize(conf)
        // 【1】KinitAuxiliaryService
        addService(kinit)
          // Service对象都保存在CompositeService类的serviceList这个成员属性中
          serviceList += service
        // 【2】PeriodicGCService
        addService(periodicGCService)
        // 【3】MetricsSystem，参数kyuubi.metrics.enabled，默认true
        addService(new MetricsSystem)
          // 继承关系：MetricsSystem -> CompositeService，其本身也是一个CompositeService，initialize方法中继续调用addService，
          // 参数kyuubi.metrics.reporters，默认PROMETHEUS
          initialize(conf: KyuubiConf)
            // 【3.1】JsonReporterService
            addService(new JsonReporterService(registry))
            // 【3.2】Slf4jReporterService
            addService(new Slf4jReporterService(registry))
            // 【3.3】ConsoleReporterService
            addService(new ConsoleReporterService(registry))
            // 【3.4】JMXReporterService
            addService(new JMXReporterService(registry))
            // 【3.5】PrometheusReporterService
            addService(new PrometheusReporterService(registry))
        // 【4】KyuubiBatchService，参数kyuubi.batch.submitter.enabled，默认false
        addService(new KyuubiBatchService(...))
        // 【5】KyuubiVirtualClusterManagerService，虚拟集群开发，参数kyuubi.vc.manager.enable，默认false
        addService(new KyuubiVirtualClusterManagerService(this))
        // 调用父类Serverable初始化
        super.initialize(conf)
          // 【6】KyuubiBackendService，KyuubiServer重写了父类Serverable backendService属性
          addService(backendService)
            // 继承关系：KyuubiBackendService -> AbstractBackendService -> CompositeService，其本身也是一个CompositeService，
            // 父类AbstractBackendService initialize方法中继续调用addService
            initialize(conf: KyuubiConf)
              // 【6.1】KyuubiSessionManager
              addService(sessionManager)
                // 继承关系：KyuubiSessionManager -> SessionManager -> CompositeService，其本身也是一个CompositeService，
                // initialize方法中继续调用addService
                initialize(conf: KyuubiConf)
                  // 【6.1.1】KyuubiApplicationManager
                  addService(applicationManager)
                  // 【6.1.2】 HadoopCredentialsManager
                  addService(credentialsManager)
                  // 【6.1.3】 MetadataManager
                  metadataManager.foreach(addService)
                    // 调用父类SessionManager初始化
                    super.initialize(conf)
                      // 【6.1.4】 KyuubiOperationManager
                      addService(operationManager)
          // 【7】KyuubiTBinaryFrontendService、【8】KyuubiRestFrontendService，参数kyuubi.frontend.protocols，
          // 默认Seq(THRIFT_BINARY、REST），KyuubiServer重写了父类Serverable frontendServices属性
          frontendServices.foreach(addService)
            // 继承关系：KyuubiTBinaryFrontendService -> TBinaryFrontendService -> TFrontendService -> AbstractFrontendService
            // -> CompositeService，其本身也是一个CompositeService，父类AbstractFrontendService initialize方法中继续调用addService
            initialize(conf: KyuubiConf)
              // 【7.1】KyuubiServiceDiscovery，KyuubiTBinaryFrontendService重写了父类AbstractFrontendService discoveryService属性
              discoveryService.foreach(addService)
          // 调用父类CompositeService初始化
          super.initialize(conf)
            // [重要] 递归初始化serviceList下的各个Service，这些Service可能复写initialize方法，并在initialize方法中继续调用addService
            serviceList.foreach(_.initialize(conf))
            // 调用父类AbstractService初始化
            super.initialize(conf)
              // 关键日志，未复写时调用父类方法；复写时最后super.initialize调用父类方法
              info(s"Service[$serviceName] is initialized.")

      // 递归启动Service
      server.start()
        // 调用父类Serverable启动
        super.start()
           // 调用父类CompositeService启动
          super.start()
            // 递归启动serviceList下的各个Service，这些Service可能复写start方法，且启动顺序与初始化相同
            serviceList.zipWithIndex.foreach { case (service, idx) => service.start() ... }
            // 调用父类AbstractService启动
            super.start()
              // 关键日志，未复写时调用父类方法；复写时最后super.start调用父类方法
              info(s"Service[$serviceName] is started.")
```

 

2、这样一来，整个 KyuubiServer 的启动流程就比较清晰了，这也是我们在最开始就列出其 Service 体系和组合关系的原因。由于整体的启动流程和细节所包含的代码比较多，这里先把整个初始化和启动流程步骤的流程图梳理了出来，待会再对其中一些需要重点关注的点进行说明。**根据 Kyuubi 启动日志，图中 Service 初始化和启动顺序依次为：KinitAuxiliaryService → PeriodicGCService → PrometheusReporterService → MetricsSystem → KyuubiApplicationManager → HadoopCredentialsManager → MetadataManager → KyuubiOperationManager → KyuubiSessionManager → KyuubiBackendService → KyuubiServiceDiscovery → KyuubiTBinaryFrontendService → KyuubiRestFrontendService → KyuubiServer**。

![KyuubiServer 启动流程](<./images/KyuubiServer 启动流程.png>) 



3、KinitAuxiliaryService 用于 Kerberos 认证，该类实现比较简单，只是在后台单线程周期性执行：`kinit -kt keytab principal`。

```scala
KinitAuxiliaryService
  initialize(conf: KyuubiConf)
    // 参数：kyuubi.kinit.keytab
    val keytab = conf.get(KyuubiConf.SERVER_KEYTAB)
    // 参数：kyuubi.kinit.principal
    val principal = conf.get(KyuubiConf.SERVER_PRINCIPAL)
    // 参数：kyuubi.kinit.interval，默认PT1H，即1小时
    kinitInterval = conf.get(KyuubiConf.KINIT_INTERVAL)
    // Kerberos认证登陆
    UserGroupInformation.loginUserFromKeytab(principal.get, keytab.get)
    // 后台单线程周期性执行：kinit -kt keytab principal
    val commands = Seq("kinit", "-kt", keytab.get, principal.get)
    val kinitProc = new ProcessBuilder(commands: _*).inheritIO()
    kinitTask = new Runnable { ... }
      val process = kinitProc.start()
      if (process.waitFor() == 0)
        info(s"Successfully ${commands.mkString(" ")}")
        executor.schedule(this, kinitInterval, TimeUnit.MILLISECONDS)
  start()
    executor.submit(kinitTask)
```

 

4、PeriodicGCService 用于 GC，该类实现比较简单，只是在后台单线程周期性执行：`System.gc()`。

```scala
PeriodicGCService
  start()
    startGcTrigger()
      // 参数：kyuubi.server.periodicGC.interval，默认PT30M，即30分钟
      val interval = conf.get(KyuubiConf.SERVER_PERIODIC_GC_INTERVAL)
      // 后台单线程周期性执行：System.gc()
      scheduleTolerableRunnableWithFixedDelay(gcTrigger, () => System.gc(), interval, interval, TimeUnit.MILLISECONDS)
```

 

5、MetricsSystem 用于指标监控，该类本身也是一个 CompositeService，包括 JSON、SLF4J、CONSOLE、JMX、PROMETHEUS 五种指标上报 Service。

```scala
MetricsSystem
  initialize(conf: KyuubiConf)
    // 使用MetricRegistry注册各类指标，包括：jvm、gc、memory_usage、buffer_pool、thread_state、class_loading
    registry.registerAll(...)
    // 参数：kyuubi.metrics.reporters，默认PROMETHEUS
    conf.get(METRICS_REPORTERS).map(ReporterType.withName).foreach
      case JSON => addService(new JsonReporterService(registry))
      case SLF4J => addService(new Slf4jReporterService(registry))
      case CONSOLE => addService(new ConsoleReporterService(registry))
      case JMX => addService(new JMXReporterService(registry))
      case PROMETHEUS => addService(new PrometheusReporterService(registry))
        initialize(conf: KyuubiConf)
          // 参数：kyuubi.metrics.prometheus.port，默认10019
          val port = conf.get(MetricsConf.METRICS_PROMETHEUS_PORT)
          // 初始化Jetty Server
          httpServer = new Server(port)
          httpServer.setHandler(context)
        start()
          // 启动Prometheus metrics HTTP server
          httpServer.start()
```

 

6、**KyuubiSessionManager 用于管理 Kyuubi Session 会话，该类会在后台周期性检查 Session 是否超时，若超时则 closeSession；同时会在后台周期性检查 Engine 是否存活，若探测失败（失败次数超过阈值），则 closeSession。KyuubiSessionManager 本身也是一个 CompositeService，其中 KyuubiApplicationManager 用于管理 Application，主要分为 Yarn 和 K8s 两种情况；HadoopCredentialsManager 用于更新 Delegation Token；MetadataManager 用于管理元数据，即插入/更新/删除 MySQL 的 metadata 表；KyuubiOperationManager 用于管理生命周期中的所有操作。**

```scala
KyuubiBackendService
  // 父类AbstractBackendService initialize方法
  initialize(conf: KyuubiConf)
    // KyuubiBackendService复写sessionManager，即为KyuubiSessionManager
    addService(sessionManager)
      initialize(conf: KyuubiConf)
        // 【1】KyuubiApplicationManager
        addService(applicationManager)
          initialize(conf: KyuubiConf)
            // 继承关系：YarnApplicationOperation、KubernetesApplicationOperation -> ApplicationOperation
            op.initialize(conf)
              // YarnApplicationOperation
              // 参数：kyuubi.yarn.user.strategy，默认NONE
              YarnUserStrategy.withName(conf.get(KyuubiConf.YARN_USER_STRATEGY)) match
                // 使用当前用户创建yarn客户端
                case NONE => createYarnClientWithCurrentUser()
                // 参数：kyuubi.yarn.user.admin，默认yarn
                case ADMIN if conf.get(KyuubiConf.YARN_USER_ADMIN) == Utils.currentUser => createYarnClientWithCurrentUser()
                // 使用代理用户kyuubi.yarn.user.admin创建yarn客户端
                case ADMIN => createYarnClientWithProxyUser(conf.get(KyuubiConf.YARN_USER_ADMIN))
                case OWNER => info("Skip initializing admin YARN client")
              // KubernetesApplicationOperation
              // Kyuubi Server使用guava cache作为基于时间的驱逐清理触发器，但在发生任何get/put操作之前，驱逐不会发生
              cleanupTerminatedAppInfoTrigger = CacheBuilder.newBuilder()....build()
              // 定期调度一个后台线程以定期清理缓存
              expireCleanUpTriggerCacheExecutor = ThreadUtils.newDaemonSingleThreadScheduledExecutor("pod-cleanup-trigger-thread")
              // 执行get操作，触发缓存驱逐
              ThreadUtils.scheduleTolerableRunnableWithFixedDelay(expireCleanUpTriggerCacheExecutor,
                () => { ... cleanupTerminatedAppInfoTrigger.getIfPresent(key) }, ...)

        // 【2】HadoopCredentialsManager
        addService(credentialsManager)
          initialize(conf: KyuubiConf)
            // 继承关系：HadoopFsDelegationTokenProvider、HiveDelegationTokenProvider -> HadoopDelegationTokenProvider
            // 参数：kyuubi.credentials.{serviceName}.enabled，控制是否开启获取DT，默认开启（serviceName分别为hadoopfs、hive）
            // 获取DT前的初始化工作，如hadoopfs初始化hadoopConf、fsUris等，hive初始化principal、client等
            provider.initialize(hadoopConf, conf)
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

        // 【3】MetadataManager
        metadataManager.foreach(addService)
          initialize(conf: KyuubiConf)
            // 实例化JDBCMetadataStore，继承关系：JDBCMetadataStore -> MetadataStore
            _metadataStore = MetadataManager.getOrCreateMetadataStore(conf)
              // 参数kyuubi.metadata.store.class，默认为org.apache.kyuubi.server.metadata.jdbc.JDBCMetadataStore
              val className = conf.get(KyuubiConf.METADATA_STORE_CLASS)
              ClassUtils.createInstance(className, classOf[MetadataStore], conf)
          start()
            // 在元数据请求失败时重试异步操作，参数kyuubi.metadata.request.async.retry.enabled，默认为true
            startMetadataRequestsAsyncRetryTrigger()
              // 后台单线程（线程名metadata-cleaner)周期性执行
              scheduleTolerableRunnableWithFixedDelay(requestsAsyncRetryTrigger, triggerTask, ...)
                // 执行insertMetadata（INSERT INTO $METADATA_TABLE ...）或updateMetadata（UPDATE $METADATA_TABLE ...）
                requestsAsyncRetryExecutor.submit(retryTask)
            // 定期清理元数据，参数kyuubi.metadata.cleaner.enabled，默认为true
            startMetadataCleaner()
              // 后台单线程（线程名metadata-requests-async-retry-trigger)周期性执行
              scheduleTolerableRunnableWithFixedDelay(metadataCleaner, cleanerTask, ...)
                // 执行：DELETE FROM $METADATA_TABLE WHERE state IN ($terminalStates) AND end_time < ?
                _metadataStore.cleanupMetadataByAge(stateMaxAge)

        // 初始化限制Kyuubi Server用户/IP的连接数，参数：kyuubi.server.limit.xxx，默认为空
        initSessionLimiter(conf)
        // 初始化Kyuubi Server最大Engine启动的并发数，防止负载过高，参数：kyuubi.server.limit.engine.startup，默认为空
        initEngineStartupProcessSemaphore(conf)
        // 父类SessionManager initialize方法
        super.initialize(conf)
          // 【4】KyuubiOperationManager
          addService(operationManager)
            initialize(conf: KyuubiConf)
              // 参数kyuubi.operation.query.timeout，默认为空
              queryTimeout = conf.get(OPERATION_QUERY_TIMEOUT)
            start()
              // 上报OPERATION_OPEN指标，值为handleToOperation集合的大小
              _.registerGauge(OPERATION_OPEN, getOperationCount, 0)
          // 初始化Kyuubi Server线程池，参数kyuubi.backend.server.exec.pool.size，默认100
          execPool = ThreadUtils.newDaemonQueuedThreadPool(...)

      start()
        // 上报指标，包括：CONN_OPEN、EXEC_POOL_ALIVE、EXEC_POOL_ACTIVE、EXEC_POOL_WORK_QUEUE_SIZE
        ms.registerGauge(...)
        super.start()
          // 后台单线程周期性检查Session是否超时，若超时则closeSession
          startTimeoutChecker()
            // timeoutChecker = ThreadUtils.newDaemonSingleThreadScheduledExecutor(s"$name-timeout-checker")
            scheduleTolerableRunnableWithFixedDelay(timeoutChecker, checkTask, interval, ...)
              val checkTask = new Runnable { ... }
                // handleToSession定义为ConcurrentHashMap[SessionHandle, Session]
                for (session <- handleToSession.values().asScala) { ... }
                  if (session.lastAccessTime + session.sessionIdleTimeoutThreshold <= current &&
                    session.getNoOperationTime > session.sessionIdleTimeoutThreshold)
                    closeSession(session.handle)
        // 后台单线程周期性检查Engine是否存活，若探测失败（失败次数超过阈值），则closeSession
        startEngineAliveChecker()
          // engineConnectionAliveChecker = ThreadUtils.newDaemonSingleThreadScheduledExecutor(s"$name-engine-alive-checker")
          scheduleTolerableRunnableWithFixedDelay(engineConnectionAliveChecker, checkTask, interval, ...)
            val checkTask: Runnable = () => { ... }
              // allSessions = handleToSession.values().asScala
              allSessions().foreach { ... }
                // 检查Engine是否存活，参数：kyuubi.session.engine.alive.probe.enabled，默认false，即默认未开启
                if (!session.checkEngineConnectionAlive())
                  closeSession(session.handle)
```

 

7、**KyuubiTBinaryFrontendService 用于构建对用户提供 RPC 服务的 KyuubiService 实例，该类在初始化时主要是设置 TThreadPoolServer 的相关参数（TThreadPoolServer 是 Apache Thrift 提供的用于构建 RPC 服务的一个工作线程池类），这些参数都是可配置的，详细可参考 KyuubiConf 类；启动则比较简单，主要是调用 TThreadPoolServer  的 serve() 方法来完成。KyuubiTBinaryFrontendService 本身也是一个 CompositeService，初始化时也会实例化 KyuubiServiceDiscovery，该类初始化时主要是创建一个用于后续连接 ZooKeeper 的 zkClient，启动则通过 zkClient 构建服务发现所需要的 KyuubiServer 实例信息，此时就会在 Zookeeper 的 /kyuubi 节点下面创建一个类似名为** `serverUri=xxx;version=xxx;xxx=xxx;sequence=xxx` **的临时顺序节点，表示当前的 KyuubiServer 实例。**

```scala
KyuubiTBinaryFrontendService
  initialize(conf: KyuubiConf)
    // 调用父类TBinaryFrontendService的方法，继承关系：KyuubiTBinaryFrontendService -> TBinaryFrontendService -> TFrontendService
    super.initialize(conf)
      // 实例化thrift frontend service线程池，参数：kyuubi.frontend.thrift.min.worker.threads（默认为9）、
      // kyuubi.frontend.thrift.max.worker.threads（默认为999）、kyuubi.frontend.thrift.worker.keepalive.time（默认为60秒）
      val executor = new ThreadPoolExecutor(minThreads, maxThreads, keepAliveTime, ...)
      // TThreadPoolServer是Apache Thrift提供的用于构建RPC服务的一个工作线程池类
      server = Some(new TThreadPoolServer(args))
      info(s"Initializing $name on ${serverAddr.getHostName}:${_actualPort} with" +
        s" [$minThreads, $maxThreads] worker threads")
      super.initialize(conf)

        // KyuubiTBinaryFrontendService复写该属性，参数kyuubi.ha.addresses不为空时，实例化KyuubiServiceDiscovery
        discoveryService.foreach(addService)
          // 调用父类ServiceDiscovery的方法，继承关系：KyuubiServiceDiscovery -> ServiceDiscovery
          initialize(conf: KyuubiConf)
            // 参数kyuubi.ha.namespace，默认为kyuubi
            _namespace = conf.get(HA_NAMESPACE)
            // 创建DiscoveryClient，继承关系：ZookeeperDiscoveryClient、EtcdDiscoveryClient -> DiscoveryClient
            _discoveryClient = DiscoveryClientProvider.createDiscoveryClient(conf)
              // 参数kyuubi.ha.client.class，默认为org.apache.kyuubi.ha.client.zookeeper.ZookeeperDiscoveryClient
              val className = conf.get(HighAvailabilityConf.HA_CLIENT_CLASS)
              ClassUtils.createInstance(className, classOf[DiscoveryClient], conf)
            // 以ZookeeperDiscoveryClient为例，启动zkClient
            discoveryClient.createClient()
              zkClient.start()
          start()
            // 以ZookeeperDiscoveryClient为例
            discoveryClient.registerService(conf, namespace, this)
              // instance即为持久节点的具体内容，其值为ip:port，参考TFrontendService类connectionUrl方法
              // 其中port值为portNum属性，子类TBinaryFrontendService复写了该属性，默认为参数kyuubi.frontend.thrift.binary.bind.port，即10009
              // 注意子类SparkSQLEngine在启动时，重新将该参数设置为0，即使用系统随机分配的端口，因此只有子类KyuubiTBinaryFrontendService使用10009端口
              val instance = serviceDiscovery.fe.connectionUrl
              serviceNode = createPersistentNode(...)
                // 通过zkClient创建名为kyuubi的持久节点
                zkClient.create().creatingParentsIfNeeded().withMode(PERSISTENT).forPath(ns)
                // 通过zkClient创建类似名为serverUri=xxx;version=xxx;sequence=xxx的临时顺序节点
                val pathPrefix = ZKPaths.makePath(namespace, s"serverUri=$instance;version=${version.getOrElse(KYUUBI_VERSION)}" +
                  s"${extraInfo.stripSuffix(";")};${session}sequence=")
                // createMode默认为EPHEMERAL_SEQUENTIAL
                localServiceNode = new PersistentNode(zkClient, createMode, false, pathPrefix, znodeData...)
                // instance即为持久节点的具体内容
                val znodeData = ... instance
                localServiceNode.start()
                info(s"Created a ${localServiceNode.getActualPath} on ZooKeeper for KyuubiServer uri: $instance")
            info(s"Registered $name in namespace ${_namespace}.")

  // 调用父类TFrontendService的方法
  start()
    serverThread.start()
      // TBinaryFrontendService with Runnable，因此调用run()方法启动TThreadPoolServer
      server.foreach(_.serve())
```

 

8、KyuubiRestFrontendService 是基于 HTTP 协议的 RESTful API 前端服务，该类实现比较简单，只是基于 Jetty 初始化并启动 Server。

```scala
KyuubiRestFrontendService
  initialize(conf: KyuubiConf)
    // 初始化JettyServer
    server = JettyServer(...)
  start()
    // 启动JettyServer
    server.start()
```

 

### 3.3.2 SparkSQLEngine 启动流程

在 KyuubiServer 为用户建立会话时，会通过服务发现层去 Zookeeper 查找该用户是否存在对应的 SparkSQLEngine 实例，如果没有则通过 spark-submit 启动一个属于该用户的 SparkSQLEngine 实例，即 KyuubiServer 是通过调用外部进程命令来提交一个 Spark 应用（后面介绍），为了方便分析 SparkSQLEngine 的启动流程，这里先将其大致的命令贴出来。

```bash
/usr/local/service/spark/bin/spark-submit \
        --class org.apache.kyuubi.engine.spark.SparkSQLEngine \
        --conf spark.hive.server2.thrift.resultset.default.fetch.size=1000 \
        --conf spark.kyuubi.client.ipAddress=172.16.0.177 \
        --conf spark.kyuubi.client.version=1.9.0 \
        --conf spark.kyuubi.engine.credentials=xxx \
        --conf spark.kyuubi.engine.engineLog.path=/usr/local/service/kyuubi/work/hadoop/kyuubi-spark-sql-engine.log.3 \
        --conf spark.kyuubi.engine.security.enabled=true \
        --conf spark.kyuubi.engine.security.secret.provider=simple \
        --conf spark.kyuubi.engine.security.secret.provider.simple.secret=kyuubi_secret \
        --conf spark.kyuubi.engine.share.level=CONNECTION \
        --conf spark.kyuubi.engine.submit.time=1748953396117 \
        --conf spark.kyuubi.engine.type=SPARK_SQL \
        --conf spark.kyuubi.frontend.protocols=THRIFT_BINARY,REST \
        --conf spark.kyuubi.ha.engine.ref.id=02995c75-8233-4190-b5cb-9e7cc06b74b7 \
        --conf spark.kyuubi.ha.namespace=/kyuubi_1.9.0_CONNECTION_SPARK_SQL/hadoop/02995c75-8233-4190-b5cb-9e7cc06b74b7 \
        --conf spark.kyuubi.ha.zookeeper.acl.enabled=false \
        --conf spark.kyuubi.ha.zookeeper.quorum=172.16.0.177:2181,172.16.0.13:2181,172.16.0.164:2181 \
        --conf spark.kyuubi.metadata.cleaner.interval=PT30M \
        --conf spark.kyuubi.metadata.max.age=P30D \
        --conf spark.kyuubi.metrics.enabled=true \
        --conf spark.kyuubi.metrics.json.interval=PT5S \
        --conf spark.kyuubi.metrics.json.location=metrics \
        --conf spark.kyuubi.metrics.prometheus.path=/metrics \
        --conf spark.kyuubi.metrics.prometheus.port=10019 \
        --conf spark.kyuubi.metrics.reporters=JSON,JMX,PROMETHEUS \
        --conf spark.kyuubi.server.ipAddress=172.16.0.177 \
        --conf spark.kyuubi.session.connection.url=172.16.0.177:10009 \
        --conf spark.kyuubi.session.engine.trino.kerberos.principal=hadoop/172.16.0.177@xxxx-G0MBTH0Y \
        --conf spark.kyuubi.session.real.user=hadoop \
        --conf spark.kyuubi.session.user.credentials=xxx \
        --conf spark.app.name=kyuubi_CONNECTION_SPARK_SQL_hadoop_02995c75-8233-4190-b5cb-9e7cc06b74b7 \
        --conf spark.master=yarn \
        --conf spark.yarn.maxAppAttempts=1 \
        --conf spark.yarn.tags=KYUUBI,02995c75-8233-4190-b5cb-9e7cc06b74b7 \
        --proxy-user hadoop /usr/local/service/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine_2.12-1.9.0.jar
```

1、kyuubi-spark-sql-engine_2.12-1.9.0.jar 是 Kyuubi 发布版本中的一个 jar 包，里面包含了 SparkSQLEngine 这个类，通过参数可知，实际上就是运行 SparkSQLEngine 的 main 方法，由此开启了 SparkSQLEngine 的启动流程。需要说明的是，提交 Sparkk App 的这些参数在 SparkSQLEngine 启动之前都会被设置到 SparkSQLEngine 的成员变量 kyuubiConf 当中，获取方法比较简单，通过 scala 提供的 sys.props 就可以获取，这些参数在 SparkSQLEngine 的初始化和启动中都会起到十分关键的作用。比如，**与 KyuubiTBinaryFrontendService 默认使用 10009 端口不同，SparkSQLEngine 在启动 RPC 服务时，将参数 kyuubi.frontend.thrift.binary.bind.port（默认 10009）设置为 0，表示系统随机分配端口**，这也就是为什么在启动 SparkSQLEngine 之后，看到其监听的端口都是随机端口的原因。**与 KyuubiServer 类似，SparkSQLEngine 本身也是一个 CompositeService，其初始化和启动也是一个递归的过程**。

```scala
// 继承关系：SparkSQLEngine -> Serverable -> CompositeService
SparkSQLEngine
  // 实例化时即设置SparkConf、KyuubiConf
  setupConf()
    // 注意，与KyuubiTBinaryFrontendService默认使用10009端口不同，SparkSQLEngine在启动RPC服务时，
    // 将参数kyuubi.frontend.thrift.binary.bind.port（默认10009）设置为0，表示系统随机分配端口
    kyuubiConf.setIfMissing(FRONTEND_THRIFT_BINARY_BIND_PORT, 0)
  main(args: Array[String])
    spark = createSpark()
      // 通过Spark API创建SparkSession对象，后续SQL真正执行都会交由其去执行
      val session = SparkSession.builder.config(_sparkConf).getOrCreate
      // 更新DelegationToken，credentials为参数kyuubi.engine.credentials，spark-submit提交时设置了该参数
      SparkTBinaryFrontendService.renewDelegationToken(session.sparkContext, credentials)
        // 比较oldCreds与newToken的IssueDate，若newToken较新才update，否则忽略
        val oldCreds = UserGroupInformation.getCurrentUser.getCredentials
        addHiveToken(sc, hiveTokens, oldCreds, updateCreds)
        addOtherTokens(otherTokens, oldCreds, updateCreds)
        info("Update delegation tokens. " + s"...")
        SparkContextHelper.updateDelegationTokens(sc, updateCreds)
          // 向Spark Driver发送一条UpdateDelegationTokens消息
          backend.driverEndpoint.send(UpdateDelegationTokens(bytes))
      // Spark Engine的初始化sql，参数kyuubi.engine.spark.initialize.sql，默认为SHOW DATABASES
      // Spark session的初始化sql，参数kyuubi.session.engine.spark.initialize.sql，默认为空
      KyuubiSparkUtil.initializeSparkSession(...)
        spark.sql(sql).isEmpty

    startEngine(spark)
      // 与KyuubiServer类似，递归初始化
      engine.initialize(kyuubiConf)
        super.initialize(conf)
          // 【1】SparkSQLBackendService，SparkSQLEngine重写了父类Serverable backendService属性
          addService(backendService)
            // 继承关系：SparkSQLBackendService -> AbstractBackendService -> CompositeService，其本身也是一个CompositeService，
            // 父类AbstractBackendService initialize方法中继续调用addService
            initialize(conf: KyuubiConf)
              // 【1.1】SparkSQLSessionManager，SparkSQLBackendService重写了父类AbstractBackendService sessionManager属性
              addService(sessionManager)
                // 继承关系：SparkSQLSessionManager -> SessionManager -> CompositeService，其本身也是一个CompositeService，
                // 父类SessionManager initialize方法中继续调用addService
                initialize(conf: KyuubiConf)
                  // 【1.1.1】SparkSQLOperationManager，SparkSQLSessionManager重写了父类SessionManager operationManager属性
                  addService(operationManager)
          // 【2】SparkTBinaryFrontendService，SparkSQLEngine重写了父类Serverable frontendServices属性
          frontendServices.foreach(addService)
            // 继承关系：SparkTBinaryFrontendService -> TBinaryFrontendService -> TFrontendService -> AbstractFrontendService
            // -> CompositeService，其本身也是一个CompositeService，父类AbstractFrontendService initialize方法中继续调用addService
            initialize(conf: KyuubiConf)
              // 【2.1】EngineServiceDiscovery，SparkTBinaryFrontendService重写了父类AbstractFrontendService discoveryService属性
              discoveryService.foreach(addService)
      // 与KyuubiServer类似，递归启动
      engine.start()
        super.start()
        // 在所有Service准备就绪后，启动Engine自终止检查器
        backendService.sessionManager.startTerminatingChecker(() => { ... currentEngine.get.stop() })
          // 后台单线程周期性检查Engine是否超时，当在指定的时间内未被访问，且handleToSession大小为0时，Engine将自行终止，及时释放资源
          // 参数kyuubi.session.engine.idle.timeout，默认为30分钟
          // handleToSession定义为ConcurrentHashMap[SessionHandle, Session]
          scheduleTolerableRunnableWithFixedDelay(timeoutChecker, checkTask, ...)
        // 后台单线程周期性检查Engine是否达到最大生命周期，当达到最大生命周期时，Engine将自行终止
        startLifetimeTerminatingChecker(() => { ... currentEngine.get.stop() })
          // 参数kyuubi.session.engine.spark.max.lifetime，默认为0，即没有最大生命周期
          if (maxLifetime > 0)
            scheduleTolerableRunnableWithFixedDelay(lifetimeTerminatingChecker.get, checkTask, ...)
        // Engine快速失败检查，如果在指定时间内未建立初始连接，Engine将自行终止，仅适用于CONNECTION级别
        // 参数kyuubi.session.engine.spark.max.initial.wait，默认为60秒
        if (conf.get(ENGINE_SHARE_LEVEL) == ShareLevel.CONNECTION.toString && maxInitTimeout > 0)
          startFastFailChecker(maxInitTimeout)
```

2、同样的，这里先把整个初始化和启动流程步骤的流程图梳理了出来，待会再对其中一些需要重点关注的点进行说明。**根据 Kyuubi 启动日志，图中 Service 初始化和启动顺序依次为：SparkSQLOperationManager → SparkSQLSessionManager → SparkSQLBackendService → EngineServiceDiscovery → SparkTBinaryFrontendService → SparkSQLEngine**。

![SparkSQLEngine 启动流程](<./images/SparkSQLEngine 启动流程.png>)



3、**SparkSQLSessionManager 用于管理 Spark SQL Session 会话，SparkSQLEngine 在所有 Service 准备就绪后，调用 startTerminatingChecker 方法，后台单线程周期性检查 Engine 是否超时，当在指定的时间内未被访问，且 handleToSession 大小为 0 时，Engine 将自行终止，及时释放资源。SparkSQLSessionManager 本身也是一个 CompositeService，其中 SparkSQLOperationManager 用于管理生命周期中的所有操作**。

```scala
SparkSQLBackendService
  // SparkSQLBackendService调用父类AbstractBackendService的方法
  initialize(conf: KyuubiConf)
    // SparkSQLSessionManager，SparkSQLBackendService重写了父类AbstractBackendService sessionManager属性
    addService(sessionManager)
      // SparkSQLSessionManager调用父类SessionManager的方法
      initialize(conf: KyuubiConf)
        // SparkSQLOperationManager，SparkSQLSessionManager重写了父类SessionManager operationManager属性
        addService(operationManager)
        // 初始化SQL Engine线程池，参数kyuubi.backend.engine.exec.pool.size，默认100
        execPool = ThreadUtils.newDaemonQueuedThreadPool(...)
      start()
        // 后台单线程周期性检查userIsolatedCache（key为用户名，value为SparkSession），当用户连接数为0，且闲置超时，
        // 则从userIsolatedCache中移除该条记录，参数kyuubi.engine.user.isolated.spark.session，默认true，即默认不检查
        startUserIsolatedCacheChecker()
          if (!userIsolatedSparkSession)
            scheduleTolerableRunnableWithFixedDelay(thread, ...)
        super.start()
          // 后台单线程周期性检查Session是否超时，若超时则closeSession
          startTimeoutChecker()
            // timeoutChecker = ThreadUtils.newDaemonSingleThreadScheduledExecutor(s"$name-timeout-checker")
            scheduleTolerableRunnableWithFixedDelay(timeoutChecker, checkTask, interval, ...)
```

 

4、**SparkTBinaryFrontendService 用于构建对 Kyuubi Server 提供 RPC 服务的 SparkEngine 实例，其调用流程与 KyuubiTBinaryFrontendService 基本相同，主要差别在于 spark-submit 提交任务时，显式设置了** `--conf spark.kyuubi.ha.namespace=/kyuubi_1.9.0_CONNECTION_SPARK_SQL/hadoop/02995c75-8233-4190-b5cb-9e7cc06b74b7`**，因此 EngineServiceDiscovery 会在该节点下面创建一个类似名为** `serverUri=xxx;version=xxx;xxx=xxx;sequence=xxx` **的临时顺序节点，表示当前的 SparkEngine 实例，而 KyuubiServiceDiscovery 是在默认的 /kyuubi 节点下面创建。**

```scala
// 继承关系：SparkTBinaryFrontendService -> TBinaryFrontendService -> TFrontendService -> AbstractFrontendService -> CompositeService
SparkTBinaryFrontendService
  // 调用父类TBinaryFrontendService的方法，后续调用流程与KyuubiTBinaryFrontendService基本相同
  initialize(conf: KyuubiConf)
  // 调用父类TFrontendService的方法，后续调用流程与KyuubiTBinaryFrontendService基本相同
  start()
```

 

## 3.4 Kyuubi Session 建立过程

Kyuubi Session 的建立实际上包含两部分，分别是 KyuubiServer Session 建立和 SparkSQLEngine Session 建立，这两个过程不是独立进行的，KyuubiServer Session 的建立伴随着 SparkSQLEngine Session 的建立，这样才完整构成了 Kyuubi 中可用于执行特定 Operation 操作的 Session。

### 3.4.1 KyuubiServer Session 建立过程

1、当用户通过 JDBC 或 beeline 的方式连接 Kyuubi 时，实际上就开启了 KyuubiServer Session 的一个建立过程，此时 KyuubiTBinaryFrontendService 的 OpenSession 方法就会被执行，并最终调用到 KyuubiSessionImpl 的 open 方法，这是整个 KyuubiServer Session 建立最复杂也是最关键的一个过程，为此我们单独介绍其流程。**KyuubiServer 在 Session 建立完成后，会给客户端返回一个 SessionHandle，后续客户端再与 KyuubiServer 进行通信时都会携带该 SessionHandle，以标识其用于会话的窗口**。

```scala
// 继承关系：KyuubiTBinaryFrontendService -> TBinaryFrontendService -> TFrontendService
// -> AbstractFrontendService -> CompositeService -> AbstractService -> Service
KyuubiTBinaryFrontendService
  OpenSession
    val sessionHandle = getSessionHandle(req, resp)
      val sessionHandle = be.openSession(...)
        sessionManager.openSession(protocol, user, password, ipAddr, configs)
          // 子类KyuubiSessionManager调用父类SessionManager方法
          super.openSession(protocol, username, password, ipAddress, conf)
            info(s"Opening session for $user@$ipAddress")
            // 实际创建的是KyuubiSessionImpl，继承关系：KyuubiSessionImpl -> KyuubiSession -> AbstractSession -> Session
            val session = createSession(protocol, user, password, ipAddress, conf)
              new KyuubiSessionImpl(...)
            // 直接调用父类AbstractSession方法，UUID随机生成：new SessionHandle(UUID.randomUUID())
            val handle = session.handle
            // 调用KyuubiSessionImpl方法（后面介绍）
            session.open()
            // 保存KyuubiServer SessionHandle与Session的映射关系
            setSession(handle, session)
              // handleToSession定义为ConcurrentHashMap[SessionHandle, Session]
              handleToSession.put(sessionHandle, session)
            // SessionHandle返回给客户端
            handle
```

2、**第一次建立 KyuubiServer Session 时，在 ZK 的命名空间下是没有相关节点信息的，因此会触发 KyuubiServer 调用外部命令来启动一个 SparkSQLEngine 实例，而调用的外部命令实际上就是我们在前面介绍【SparkSQLEngine 启动流程】中提到的 spark-submit 命令，之后就是 SparkSQLEngine 实例的启动过程，其启动完成之后，就会在 ZK 上注册自己的节点信息。在不超时的情况下，循环会一直执行，直到获取到 SparkSQLEngine 实例信息，进入下面跟 SparkSQLEngine 实例建立会话的过程。**

**SparkSQLEngine 本质上也是一个 RPC 服务端，为了与其进行通信以建立会话，就需要构建 RPC 客户端，这里 KyuubiSessionImpl 构建 RPC 客户端的方法主要是 Apache Thrift 的一些模板代码。在发送请求给 SparkSQLEngine 时，又会触发 SparkSQLEngine Session 建立的过程（后面介绍），在跟其建立完 Session 之后，会获取 SparkSQLEngine 返回的 SessionHandle，后续 KyuubiServer 再与 SparkSQLEngine 进行通信时都会携带该 SessionHandle，以标识其用于会话的窗口。**

```scala
KyuubiSessionImpl
  open()
    // 创建Operation日志根目录，JVM退出时删除该目录，根目录默认为：$KYUUBI_HOME/work/server_operation_logs/sessionHandle_UUID
    // 参数kyuubi.operation.log.dir.root，默认为server_operation_logs
    super.open()
      OperationLog.createOperationLogRootDirectory(this)
    // launchEngineOp实际是LaunchEngine，继承关系：LaunchEngine -> KyuubiApplicationOperation
    // -> KyuubiOperation -> AbstractOperation -> Operation
    runOperation(launchEngineOp)
      super.runOperation(operation)
        operation.run()
          // LaunchEngine复写该方法
          runInternal()
            session.openEngineSession(getOperationLog)
              // 在调用函数f之前创建一个ZK客户端，并在调用函数f之后关闭
              withDiscoveryClient(sessionConf) { ... }
                discoveryClient.createClient()
              // engineCredentials不为空时，spark-submit启动SparkSQLEngine设置参数kyuubi.engine.credentials
              if (engineCredentials.nonEmpty)
                sessionConf.set(KYUUBI_ENGINE_CREDENTIALS_KEY, engineCredentials)
                Map(KYUUBI_ENGINE_CREDENTIALS_KEY -> engineCredentials)
              // sessionUserCredentials不为空时，spark-submit启动SparkSQLEngine设置参数kyuubi.session.user.credentials
              // engineCredentials、sessionUserCredentials初始化：均调用HadoopCredentialsManager类renewCredentials方法
              if (sessionUserCredentials.nonEmpty)
                sessionConf.set(KYUUBI_SESSION_USER_CREDENTIALS_KEY, sessionUserCredentials)
                Map(KYUUBI_SESSION_USER_CREDENTIALS_KEY -> sessionUserCredentials)

              // 尝试与SparkSQLEngine建立连接，参数kyuubi.session.engine.open.max.attempts，默认为9
              while (attempt <= maxAttempts && shouldRetry)
                // 获取或创建SparkSQLEngine，先尝试从ZK中获取，获取不到再创建SparkSQLEngine
                val (host, port) = engine.getOrCreate(discoveryClient, extraEngineLog)
                  // 先尝试从ZK中获取，ZK namespace如下，参考变量engineSpace定义：
                  // serverSpace即参数kyuubi.ha.namespace，subdomain即参数kyuubi.engine.share.level.subdomain
                  // 1.CONNECTION级别：/serverSpace_version_CONNECTION_engineType/user/engineRefId
                  // 2.USER级别： /serverSpace_version_USER_engineType/user[/subdomain]
                  // 3.GROUP级别：/serverSpace_version_GROUP_engineType/primary group name[/subdomain]
                  // 4.SERVER级别：/serverSpace_version_SERVER_engineType/kyuubi server user[/subdomain]
                  discoveryClient.getServerHost(engineSpace).getOrElse { create(discoveryClient, extraEngineLog) }
                    // 这里再次尝试从ZK中获取，因为存在并发问题（注意create方法加锁了），如果另一个进程成功，则提前获取
                    var engineRef = discoveryClient.getServerHost(engineSpace)
                    if (engineRef.nonEmpty) return engineRef.get
                    // 支持：SPARK_SQL、FLINK_SQL、TRINO、HIVE_SQL、JDBC、CHAT，这里以SPARK_SQL为例
                    builder = engineType match
                      // SparkProcessBuilder继承ProcBuilder，重写了父类属性commands，该属性组装了spark-submit提交命令
                      case SPARK_SQL => ... new SparkProcessBuilder(...)
                    // 即输出spark-submit提交命令
                    info(s"Launching engine:\n$redactedCmd")
                    // 调用Java原生API（java.lang.ProcessBuilder）启动进程，参考变量processBuilder定义
                    // 进程会将标准及错误输出重定向到${spark.kyuubi.engine.engineLog.path}文件，默认位于kyuubi work目录下
                    val process = builder.start
                      // 启动后台线程，逐行读取${spark.kyuubi.engine.engineLog.path}文件，若解析到关键字Exception，
                      // 则初始化变量error，类型为KyuubiSQLException异常，后面抛出（调用builder.getError获取）
                      PROC_BUILD_LOGGER.newThread(redirect)
                    // 循环从ZK中获取SparkSQLEngine节点信息，直到获取成功或超时失败
                    while (engineRef.isEmpty)
                      // 超时失败，参数kyuubi.session.engine.initialize.timeout，默认180秒
                      if (started + timeout <= System.currentTimeMillis())
                        throw KyuubiSQLException(...)
                // 创建连接SparkSQLEngine的Thrift客户端
                _client = KyuubiSyncThriftClient.createClient(...)
                  // 继承关系：KyuubiSyncThriftClient -> TCLIService.Client
                  new KyuubiSyncThriftClient(...)
                // 与SparkSQLEngine建立RPC会话
                _engineSessionHandle = _client.openSession(...)
                  // 调用Thrift API与SparkSQLEngine建立RPC会话
                  val resp = withLockAcquired(OpenSession(req))
                  // 获取SparkSQLEngine RPC服务端返回的SessionHandle
                  _remoteSessionHandle = resp.getSessionHandle
                  SessionHandle(_remoteSessionHandle)
                logSessionInfo(s"Connected to engine [$host:$port]/[${client.engineId.getOrElse("")}]" +
                  s" with ${_engineSessionHandle}]")
```

 

### 3.4.2 SparkSQLEngine Session 建立过程

1、当 SparkSQLEngine 接收到来自 KyuubiServer 建立会话的 RPC 请求后，SparkTBinaryFrontendService 的 OpenSession 方法就会被执行，其整体流程与 KyuubiServer Session 的建立过程类似，并最终调用到 SparkSessionImpl 的 open 方法，同样后面我们单独介绍其流程。**SparkSQLEngine 在 Session 建立完成后，会给 KyuubiServer 返回一个 SessionHandle，后续 KyuubiServer 在与 SparkSQLEngine 进行通信时都会携带该 SessionHandle，以标识其用于会话的窗口**。

```scala
// 继承关系：SparkTBinaryFrontendService -> TBinaryFrontendService -> TFrontendService
// -> AbstractFrontendService -> CompositeService -> AbstractService -> Service
SparkTBinaryFrontendService
  OpenSession
    info("Client protocol version: " + req.getClient_protocol)
    val sessionHandle = getSessionHandle(req, resp)
      // 获取真实用户和会话用户：真实用户是用于会话认证的用户；若提供了代理用户，则会话用户为代理用户，否则为真实用户
      val (realUser, sessionUser) = getRealUserAndSessionUser(req)
      // 这里调用流程与KyuubiServer类似
      val sessionHandle = be.openSession(...)
        // 调用父类SessionManager方法
        sessionManager.openSession(protocol, user, password, ipAddr, configs)
          info(s"Opening session for $user@$ipAddress")
          // 实际创建的是SparkSessionImpl，继承关系：SparkSessionImpl -> AbstractSession -> Session
          val session = createSession(protocol, user, password, ipAddress, conf)
            new SparkSessionImpl(...)
          // SparkSessionImpl复写，先尝试从conf中取kyuubi.session.handle（KyuubiServer RPC请求时可能设置），否则UUID随机生成
          val handle = session.handle
            conf.get(KYUUBI_SESSION_HANDLE_KEY).map(SessionHandle.fromUUID).getOrElse(SessionHandle())
          // 调用SparkSessionImpl方法（后面介绍）
          session.open()
          // 保存SparkSQLEngine SessionHandle与Session的映射关系
          setSession(handle, session)
            // handleToSession定义为ConcurrentHashMap[SessionHandle, Session]
            handleToSession.put(sessionHandle, session)
          // SessionHandle返回给KyuubiServer
          handle
    // SessionHandle返回给KyuubiServer
    resp.setSessionHandle(sessionHandle.toTSessionHandle)
    resp
```

2、实际上，SparkSessionImpl 的 open 方法实现比较简单，只是设置了 Spark Session 的 Catalog、Database 和其他参数，然后注册 Kyuubi 自定义函数，最后创建 SparkSQLEngine Operation 日志根目录，该目录将在 JVM 退出时被自动删除，**根目录默认位于** `$KYUUBI_HOME/work/engine_operation_logs/sessionHandle_UUID`**。相应的，KyuubiServer Operation 根目录默认位于** `$KYUUBI_HOME/work/server_operation_logs/sessionHandle_UUID`**，可以此确认 KyuubiServer、SparkSQLEngine 分别位于哪个节点**。

```scala
SparkSessionImpl
  open()
    // 设置Spark Session Catalog
    SparkCatalogUtils.setCurrentCatalog(spark, catalog)
    // 设置Spark Session Database
    spark.sessionState.catalogManager.setCurrentNamespace(Array(database))
    // 设置Spark Session其他参数
    setModifiableConfig(key, value)
    // 注册Kyuubi自定义函数，包括：kyuubi_version、engine_name、engine_id、system_user、session_user、engine_url
    KDFRegistry.registerAll(spark)
    // 创建Operation日志根目录，JVM退出时删除该目录，根目录默认为：$KYUUBI_HOME/work/engine_operation_logs/sessionHandle_UUID
    // 参数kyuubi.engine.operation.log.dir.root，默认为engine_operation_logs
    super.open()
      OperationLog.createOperationLogRootDirectory(this)
```

 

## 3.5 Kyuubi SQL 执行流程

Kyuubi SQL 的执行流程实际上包含两部分，分别是 KyuubiServer SQL 执行流程和 SparkSQLEngine SQL 执行流程，其结合起来才是一个完整的 SQL 执行流程，KyuubiServer 只是一个代理，真正的 SQL 执行是在 SparkSQLEngine 中完成。**另外由于在 Kyuubi 中，SQL 的执行是异步的，即可以先提交一个 SQL 让其去执行，后续再通过其返回的 operationHandle 去获取结果，所以在 KyuubiServer 和 SparkSQLEngine 内部，SQL 的执行流程又可以再细分为提交 Statement 和 FetchResults 两个过程**，在分别分析 KyuubiServer SQL 执行流程和 SparkSQLEngine SQL 执行流程时，我们就是对提交 Statment 和 FetchResults 这两个过程来展开详细的分析，整体会有些繁多，但并不复杂。

### 3.5.1 KyuubiServer SQL 执行流程

1、当用户通过 JDBC 或 beeline 的方式执行一条 SQL 语句时，就开启了 SQL 语句在 Kyuubi 中的执行流程，此时 KyuubiTBinaryFrontendService 的 ExecuteStatement 方法就会被执行，并最终调用到 KyuubiSessionImpl 的 executeStatement 方法，这是整个 KyuubiServer SQL 执行最复杂也是最关键的一个过程，为此我们单独介绍其流程。**KyuubiServer 在提交完 Statement 后，客户端会将 OperationHandle 返回给用户端，用于后续获取执行结果（FetchResults）**。

```scala
// 继承关系：KyuubiTBinaryFrontendService -> TBinaryFrontendService -> TFrontendService
// -> AbstractFrontendService -> CompositeService -> AbstractService -> Service
KyuubiTBinaryFrontendService
  // 未复写，实际调用父类TFrontendService方法
  ExecuteStatement
    // 客户端传递的SessionHandle，用于获取KyuubiServer对应的Session
    val sessionHandle = SessionHandle(req.getSessionHandle)
    // 客户端要执行的SQL语句
    val statement = req.getStatement
    // 客户端是否要异步执行SQL，默认为true
    val runAsync = req.isRunAsync
    // 调用AbstractFrontendService方法
    val operationHandle = be.executeStatement(...)
       // 调用KyuubiSessionImpl方法（后面介绍）
      sessionManager.getSession(sessionHandle).executeStatement(...)
    // OperationHandle返回给客户端，用于后续FetchResults
    val tOperationHandle = operationHandle.toTOperationHandle
    resp.setOperationHandle(tOperationHandle)
```

2、**KyuubiSessionImpl 首先通过 KyuubiOperationManager 创建一个表示执行 SQL 的 ExecuteStatement，注意这里 ExecuteStatement 是 KyuubiServer 体系下的，其类全路径为** `org.apache.kyuubi.operation.ExecuteStatement`**，因为后面在分析 SparkSQLEngine SQL 执行流程时，在 SparkSQLEngine 体系下也有一个 ExecuteStatement，但其类全路径为** `org.apache.kyuubi.engine.spark.operation.ExecuteStatement`**。**

**然后调用** `client.executeStatement` **向 SparkSQLEngine 发送执行 SQL 语句的 RPC 请求，这里的 client 实际上就是前面 KyuubiServer Session 建立过程中创建的用于与 SparkSQLEngine 通信的 RPC 客户端** `KyuubiSyncThriftClient`**，其底层调用的仍然是 Thrift API，这样就会触发 SparkSQLEngine SQL 执行流程（后面介绍）。请求成功后，KyuubiServer 会将 SparkSQLEngine 返回的 OperationHandle 记录下来，赋值给成员变量 _remoteOpHandle，后续用于查询 Statement 在 SparkSQLEngine 实例中的执行状态和 FetchResults。**

最后 KyuubiSessionImpl 通过线程池提交一个任务 waitStatementComplete，该任务主要用于异步查询 SparkSQLEngine 实例中 Operation 的执行状态，这里提交一个线程后的返回结果 _backgroundHandle 实际上是一个 Future 对象，后续 FetchResults 过程中通过该对象就可以知道 Operation 在 SparkSQLEngine 实例中的执行状态。

```scala
// 继承关系：KyuubiSessionImpl -> KyuubiSession -> AbstractSession -> Session
KyuubiSessionImpl
  executeStatement(...)
    // Kyuubi引入基于Antlr4的解析器模块，可用于提供SQL转换，参考：https://github.com/apache/kyuubi/issues/3926
    // 例如当这里kyuubiNode类型为org.apache.kyuubi.sql.plan.command.RunnableCommand，则特殊处理，这里先不细讨论
    val kyuubiNode = parser.parsePlan(statement)
    // 调用父类AbstractSession方法
    super.executeStatement(statement, confOverlay, runAsync, queryTimeout)
      // 调用KyuubiOperationManager方法，创建一个表示执行SQL的ExecuteStatement
      val operation = sessionManager.operationManager.newExecuteStatementOperation(...)
        // 继承关系：ExecuteStatement -> KyuubiOperation -> AbstractOperation -> Operation
        // 这里ExecuteStatement是KyuubiServer体系下的，其类全路径为org.apache.kyuubi.operation.ExecuteStatement
        // SparkSQLEngine体系下也有ExecuteStatement，其类全路径为org.apache.kyuubi.engine.spark.operation.ExecuteStatement
        val operation = new ExecuteStatement(...)
        // 保存KyuubiServer OperationHandle与Operation的映射关系
        addOperation(operation)
          // handleToOperation定义为HashMap[OperationHandle, Operation]
          handleToOperation.put(operation.getHandle, operation)
      runOperation(operation)
        operation.run()
          // ExecuteStatement复写该方法
          runInternal()
            executeStatement()
              // 这里的client即前面KyuubiServer Session建立过程中创建的用于与SparkSQLEngine通信的RPC客户端KyuubiSyncThriftClient，
              // 这里statement实际上就是要执行的SQL语句。需要避免在同步（sync）模式下执行查询，因为Thrift协议中没有心跳机制，
              // 在sync模式下，我们无法区分长运行查询和在socket读取超时之前没有响应的引擎崩溃
              _remoteOpHandle = client.executeStatement(statement, ..., true, queryTimeout)
                // 底层调用Thrift API，即父类TServiceClient的ExecuteStatement方法，向SparkSQLEngine发送ExecuteStatement RPC请求
                val resp = withLockAcquiredAsyncRequest(ExecuteStatement(req))
                // 获取SparkSQLEngine返回的OperationHandle，后续用于查询Statement在SparkSQLEngine实例中的执行状态和FetchResults
                resp.getOperationHandle
            // 线程池submit异步执行，查询SparkSQLEngine实例中Operation的执行状态
            // 返回对象类型为Future，后续FetchResults过程中通过该对象就可以知道Operation在SparkSQLEngine实例中的执行状态
            val opHandle = sessionManager.submitBackgroundOperation(asyncOperation)
              val asyncOperation: Runnable = () => waitStatementComplete()
                // 通过OperationHandle查询SparkSQLEngine实例中Operation的执行状态，直到任务完成或终止
                while (!isComplete && !isTerminalState(state))
                  statusResp = client.getOperationStatus(_remoteOpHandle)
            // 设置_backgroundHandle，opHandle类型为Future
            setBackgroundHandle(opHandle)
            // 如果客户端选择同步执行，调用Future.get()等待任务执行完成
            if (!shouldRunAsync) getBackgroundHandle.get()
```

3、**提交完 Statement 后，用户层的 RPC 客户端就会去获取结果，此时 KyuubiTBinaryFrontendService 的 FetchResults 方法就会被执行。在获取真正执行结果之前，会有多次获取操作日志的请求，也就是** `req.getFetchType == 1` **的情况，这里主要关注** `fetchLog = false` **的情况。获取执行结果的过程比较简单，主要是调用 RPC 客户端的 FetchResults 方法，其底层调用的仍然是 Thrift API，这样就会触发 SparkSQLEngine FetchResults 的一个过程（后面介绍），不过在获取执行结果前会检查其执行状态，前面在分析在提交 Statement 时，异步线程 waitStatementComplete 就会请求 SparkSQLEngine 更新其状态为 FINISHED，因此这里可以正常获取执行结果。**

```scala
KyuubiTBinaryFrontendService
  // 未复写，实际调用父类TFrontendService方法
  FetchResults
    // 客户端传递的OperationHandle，用于获取KyuubiServer对应的Operation
    val operationHandle = OperationHandle(req.getOperationHandle)
    // 1表示获取日志，在获取真正执行结果之前，会有多次获取操作日志的请求，这里主要关注fetchLog=false的情况
    val fetchLog = req.getFetchType == 1
    // 调用AbstractBackendService方法
    be.fetchResults(operationHandle, orientation, maxRows, fetchLog)
      // 根据OperationHandle获取KyuubiServer对应的Operation
      sessionManager.operationManager.getOperation(operationHandle).getSession.fetchResults(...)
        // 这里关注fetchLog=false，若fetchLog=true，调用sessionManager.operationManager.getOperationLogRowSet(...)
        sessionManager.operationManager.getOperationNextRowSet(operationHandle, orientation, maxRows)
          getOperation(opHandle).getNextRowSet(order, maxRows)
            // KyuubiOperation复写父类AbstractOperation方法
            getNextRowSetInternal(order, rowSetSize)
              // 这里的client即前面KyuubiServer Session建立过程中创建的用于与SparkSQLEngine通信的RPC客户端KyuubiSyncThriftClient
              // 这里的_remoteOpHandle即前面KyuubiServer向SparkSQLEngine发送ExecuteStatement RPC请求后，返回的OperationHandle
              val rowset = client.fetchResults(_remoteOpHandle, order, rowSetSize, fetchLog = false)
                // 底层调用Thrift API，即父类TServiceClient的FetchResults方法，向SparkSQLEngine发送FetchResults RPC请求
                val resp = withLockAcquiredAsyncRequest(FetchResults(req))
```

 

### 3.5.2 SparkSQLEngine SQL 执行流程

1、当 SparkSQLEngine 接收到来自 KyuubiServer ExecuteStatement 的 RPC 请求后，SparkTBinaryFrontendService 的 ExecuteStatement 方法就会被执行，其整体流程与 KyuubiServer SQL 执行流程类似，并最终调用到 SparkSessionImpl 的 open 方法，同样后面我们单独介绍其流程。**SparkSQLEngine 在提交完 Statement 后，会给 KyuubiServer 返回一个 OperationHandle，用于后续获取执行结果（FetchResults）。**

```scala
// 继承关系：SparkTBinaryFrontendService -> TBinaryFrontendService -> TFrontendService
// -> AbstractFrontendService -> CompositeService -> AbstractService -> Service
SparkTBinaryFrontendService
  // 未复写，实际调用父类TFrontendService方法，整体流程与KyuubiServer SQL执行流程类似
  ExecuteStatement
    // KyuubiServer传递的SessionHandle，用于SparkSQLEngine获取对应的Session
    val sessionHandle = SessionHandle(req.getSessionHandle)
    // KyuubiServer要执行的SQL语句
    val statement = req.getStatement
    // KyuubiServer是否要异步执行SQL，默认为true
    val runAsync = req.isRunAsync
    // 调用AbstractFrontendService方法
    val operationHandle = be.executeStatement(...)
       // 调用SparkSessionImpl方法（后面介绍）
      sessionManager.getSession(sessionHandle).executeStatement(...)
    // OperationHandle返回KyuubiServer，用于后续FetchResults
    val tOperationHandle = operationHandle.toTOperationHandle
    resp.setOperationHandle(tOperationHandle)
```

2、**SparkSessionImpl 首先通过 SparkSQLOperationManager 创建一个表示执行 SQL 的 ExecuteStatement，注意这里 ExecuteStatement 是 SparkSQLEngine 体系下的，其类全路径为** `org.apache.kyuubi.engine.spark.operation.ExecuteStatement`**。然后通过线程池异步调用 executeStatement 方法，实际上其底层直接调用 SparkSession 的 sql 方法来执行 SQL 语句，并将结果保存到迭代器 iter 中，后续用于 FetchResults。**

```scala
// 继承关系：SparkSessionImpl -> AbstractSession -> Session
SparkSessionImpl
  // 未复写，实际调用父类AbstractSession方法
  executeStatement(...)
    val operation = sessionManager.operationManager.newExecuteStatementOperation(...)
      // 参数kyuubi.operation.language，默认为OperationLanguages.SQL，支持SQL、SCALA、PYTHON三种
      val lang = OperationLanguages(...OPERATION_LANGUAGE.key...)
      lang match
        // 继承关系：ExecuteStatement -> SparkOperation -> AbstractOperation -> Operation
        // 这里ExecuteStatement是SparkSQLEngine体系下的，其类全路径为org.apache.kyuubi.engine.spark.operation.ExecuteStatement
        case OperationLanguages.SQL => ... new ExecuteStatement(...)
        case OperationLanguages.SCALA => ... new ExecuteScala(...)
        case OperationLanguages.PYTHON => ... new ExecutePython(...)
      // 保存SparkSQLEngine OperationHandle与Operation的映射关系
      addOperation(operation)
        // handleToOperation定义为HashMap[OperationHandle, Operation]
        handleToOperation.put(operation.getHandle, operation)
    // SparkSessionImpl复写
    runOperation(operation)
      super.runOperation(operation)
        operation.run()
          // ExecuteStatement复写该方法
          runInternal()
            // 若shouldRunAsync=false，则直接调用executeStatement()，而不会通过线程池提交，异步执行
            val backgroundHandle = sparkSQLSessionManager.submitBackgroundOperation(asyncOperation)
              val asyncOperation = new Runnable { ... executeStatement() }
                // 底层直接调用SparkSession的sql方法来执行SQL语句
                result = spark.sql(statement)
                // 将结果保存到父类SparkOperation迭代器iter
                iter = collectAsIterator(result)
                // 执行Operation状态为完成
                setState(OperationState.FINISHED)
```

3、**当 SparkSQLEngine 接收到来自 KyuubiServer FetchResults 的 RPC 请求后，SparkTBinaryFrontendService 的 FetchResults 方法就会被执行，其整体流程与 KyuubiServer FetchResults 流程类似，整个过程比较简单，就是将前面 iter 的结果转换为 TRowSet 对象格式，最后返回给 KyuubiServer。**

```scala
SparkTBinaryFrontendService
  // 未复写，实际调用父类TFrontendService方法，整体流程与KyuubiServer SQL执行流程类似
  FetchResults
    // KyuubiServer传递的OperationHandle，用于获取SparkSQLEngine对应的Operation
    val operationHandle = OperationHandle(req.getOperationHandle)
    // 1表示获取日志，在获取真正执行结果之前，会有多次获取操作日志的请求，这里主要关注fetchLog=false的情况
    val fetchLog = req.getFetchType == 1
    // 调用AbstractBackendService方法
    be.fetchResults(operationHandle, orientation, maxRows, fetchLog)
      // 根据OperationHandle获取SparkSQLEngine对应的Operation
      sessionManager.operationManager.getOperation(operationHandle).getSession.fetchResults(...)
        // 这里关注fetchLog=false，若fetchLog=true，调用sessionManager.operationManager.getOperationLogRowSet(...)
        sessionManager.operationManager.getOperationNextRowSet(operationHandle, orientation, maxRows)
          getOperation(opHandle).getNextRowSet(order, maxRows)
            // SparkOperation复写父类AbstractOperation方法
            getNextRowSetInternal(order, rowSetSize)
              // 将前面iter的结果转换为TRowSet对象格式，最后返回给KyuubiServer。
              val taken = iter.next().asInstanceOf[Array[Byte]]
```

 

# 4. 参考

1. [Kyuubi 官网](https://kyuubi.readthedocs.io/en/master/)
2. [网易 Spark Kyuubi 核心架构设计与源码实现剖析](https://blog.51cto.com/xpleaf/2780248)
3. [既然有 HTTP 协议，为什么还要有 RPC](https://juejin.cn/post/7121882245605883934)
