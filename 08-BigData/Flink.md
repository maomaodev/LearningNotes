# 1. Flink 入门

## 1.1 Flink 介绍

### 1.1.1 Flink 核心特性

Flink 是一个**框架和分布式处理引擎**，用于对无界和有界数据流进行有状态计算，它被设计在所有常见的集群环境中运行，以**内存执行速度和任意规模**来执行计算。Flink 区别于传统数据处理框架的特性如下：

* **高吞吐和低延迟**，每秒处理数百万个事件，毫秒级延迟。
* **结果的准确性**，Flink 提供了事件时间（event-time）和处理时间（processing-time） 语义，对于乱序事件流，事件时间语义仍然能提供一致且准确的结果。 
* **精确一次（exactly-once）**的状态一致性保证。 
* **可以连接到最常用的存储系统**，如 Kafka、Cassandra、Elasticsearch、 JDBC、Kinesis，以及分布式文件系统，如 HDFS 和 S3。 
* **高可用**，本身高可用的设置，加上与 K8s，YARN 和 Mesos 的紧密集成，再加上从故障中快速恢复和动态扩展任务的能力，Flink 能做到以极少的停机时间。 
* 能够更新应用程序代码并将作业（jobs）迁移到不同的 Flink 集群，而不会丢失应用程序的状态。

除了上述特性外，Flink 还拥有易于使用的**分层 API**。大多数应用直接针对核心 API 进行编程，如 **DataStream API（用于处理有界或无界流数据）**以及 DataSet API（用于处理有界数据集），这些 API 为数据处理提供了通用的构建模块，如由用户定义的多种形式的转换 （transformations）、连接（joins）、聚合（aggregations）、窗口（windows）操作等。由于新版本 Flink 已经完全实现了真正的流批一体，因此 DataSet API 已处于软弃用（soft deprecated）的状态。

![分层API](./images/Flink/分层API.png)



### 1.1.2 Flink 与 Spark

数据处理的基本方式，可以分为**批处理和流处理**两种。批处理针对的是有界数据集，非常适合**需要访问海量的全部数据**才能完成的计算工作，一 般用于**离线统计**；流处理主要针对的是数据流，特点是**无界、实时**, 对系统传输的每个数据依次执行操作， 一般用于**实时统计**。

**Spark 以批处理为根本，并尝试在批处理之上支持流计算**。在 Spark 中，万物皆批次，离线数据是一个大批次，而实时数据则是由一个一个无限的小批次组成的。所以对于流处理框架 Spark Streaming 而言，其实并不是真正意义上的“流”处理，而是“微批次”处理。而**在 Flink 中，万物皆流，流处理才是最基本的操作，批处理也可以统一为流处理**，实时数据是标准的、没有界限的流，而离线数据则是有界限的流。

![有界流与无界流](./images/Flink/有界流与无界流.png)

Spark 和 Flink 的区别还在于底层实现的数据模型不同。 **Spark 底层数据模型是弹性分布式数据集 RDD**，Spark Streaming 进行微批处理的底层接口 DStream，实际上是一组组小批数据 RDD 的集合，所以 Spark 更加适合批处理的场景。 而 **Flink 的基本数据模型是数据流（DataFlow），以及事件（Event）序列**，其基本上是完全按照 Google 的 DataFlow 模型实现的，所以 Flink 更加适合流处理的场景。



## 1.2 Flink 快速上手

### 1.2.1 批处理

```xml
<!-- 引入Flink相关依赖 -->
<dependency>
    <groupId>org.apache.flink</groupId>
    <artifactId>flink-java</artifactId>
    <version>1.13.0</version>
</dependency>
<!-- 此处Scala版本为2.12，Flink使用Akka实现底层的分布式通信，而Akka使用Scala开发 -->
<dependency>
    <groupId>org.apache.flink</groupId>
    <artifactId>flink-streaming-java_2.12</artifactId>
    <version>1.13.0</version>
</dependency>
<dependency>
    <groupId>org.apache.flink</groupId>
    <artifactId>flink-clients_2.12</artifactId>
    <version>1.13.0</version>
</dependency>
<!-- 引入日志管理相关依赖 -->
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>slf4j-api</artifactId>
    <version>1.7.30</version>
</dependency>
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>slf4j-log4j12</artifactId>
    <version>1.7.30</version>
</dependency>
<dependency>
    <groupId>org.apache.logging.log4j</groupId>
    <artifactId>log4j-to-slf4j</artifactId>
    <version>2.14.0</version>
</dependency>
```

```properties
log4j.rootLogger=error, stdout
log4j.appender.stdout=org.apache.log4j.ConsoleAppender
log4j.appender.stdout.layout=org.apache.log4j.PatternLayout
log4j.appender.stdout.layout.ConversionPattern=%-4r [%t] %-5p %c %x - %m%n
```

```java
// 基于DataSet API统计文本中单词出现的次数，从Flink 1.12开始，官方推荐直接使用DataStream API
// 在提交任务时将执行模式设为BATCH来进行批处理：$ bin/flink run -Dexecution.runtime-mode=BATCH BatchWordCount.jar
public class BatchWordCount {
    public static void main(String[] args) throws Exception {
        // 创建执行环境
        ExecutionEnvironment env = ExecutionEnvironment.getExecutionEnvironment();
        // 从文件读取数据，按行读取
        DataSource<String> lineDS = env.readTextFile("input/words.txt");
        // 转换数据格式
        FlatMapOperator<String, Tuple2<String, Long>> wordAndOne = lineDS
                .flatMap((String line, Collector<Tuple2<String, Long>> out) -> {
                    String[] words = line.split(" ");
                    for (String word : words) {
                        out.collect(Tuple2.of(word, 1L));
                    }
                })
            	// 当Lambda表达式使用Java泛型的时候, 由于泛型擦除的存在, 需要显示的声明类型信息
                .returns(Types.TUPLE(Types.STRING, Types.LONG)); 
        // 按照word进行分组，然后分组内聚合统计
        UnsortedGrouping<Tuple2<String, Long>> wordAndOneUG = wordAndOne.groupBy(0);
        AggregateOperator<Tuple2<String, Long>> sum = wordAndOneUG.sum(1);
        sum.print();
    }
}
```



### 1.2.2 流处理

```java
public class StreamWordCount {
    public static void main(String[] args) throws Exception {
        // 创建流式执行环境
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        // 读取文本流，使用netcat工具产生流式数据，启动命令为：nc -lk 7777
        DataStreamSource<String> lineDSS = env.socketTextStream("hadoop102", 7777);
        // 转换数据格式
        SingleOutputStreamOperator<Tuple2<String, Long>> wordAndOne = lineDSS
                .flatMap((String line, Collector<String> words) -> {
                    Arrays.stream(line.split(" ")).forEach(words::collect);
                })
                .returns(Types.STRING)
                .map(word -> Tuple2.of(word, 1L))
                .returns(Types.TUPLE(Types.STRING, Types.LONG));
        // 分组后求和
        KeyedStream<Tuple2<String, Long>, String> wordAndOneKS = wordAndOne
                .keyBy(t -> t.f0);
        SingleOutputStreamOperator<Tuple2<String, Long>> result = wordAndOneKS
                .sum(1);
        
        result.print();
        env.execute();
    }
}
```



## 1.3 Flink 安装部署

Flink 有几个关键组件：**客户端（Client）、作业管理器（JobManager）和任务管理器（TaskManager）**。我们的代码实际上由客户端获取并做转换，之后提交给 JobManger，所以 JobManager 就是 Flink 集群里的“管事人”，对作业进行中央调度管理， 而它获取到要执行的作业后，会进一步处理转换，然后分发任务给众多的 TaskManager。

### 1.3.1 Fink 部署模式

Flink 为各种场景提供了不同的部署模式，主要有： 会话模式（Session Mode）、 单作业模式（Per-Job Mode） 、应用模式（Application Mode），它们的主要**区别在于：集群的生命周期和资源的分配方式，以及应用的 main 方法到底在客户端 Client 还是 JobManager 执行**。

1. **会话模式**：会话模式**需要先启动一个集群**，保持一个会话，在这个会话中通过客户端提交作业。集群启动时所有资源就都已经确定，所以提交的作业会竞争集群中的资源。这种方式的优点是**集群的生命周期超越于作业之上**，作业结束了就释放资源，集群依然正常运行；缺点是**资源是共享的**，一旦资源不足，提交新的作业就会失败，另外，同一个 TaskManager 上可能运行了很多作业，如果其中一个发生故障导致 TaskManager 宕机，那么所有作业都会受到影响。会话模式比较适合于单个规模小、执行时间短的大量作业。

   ![会话模式](./images/Flink/会话模式.png)

2. **单作业模式**：**为每个提交的作业启动一个集群**，由客户端运行应用程序，然后启动集群，作业被提交给 JobManager，进而分发给 TaskManager 执行，作业完成后，集群就会关闭，所有资源也会释放。每个作业都有它自己的 JobManager 管理，**独占资源**，即使发生故障，它的 TaskManager 宕机也不会影响其他作业。 因此单作业模式运行更加稳定，也是**实际应用的首选模式**。 注意，Flink 单作业模式一般需要借助一些资源管理框架来启动集群，如 YARN、K8s。

   ![单作业模式](./images/Flink/单作业模式.png)

3. **应用模式**：前面两种模式，应用代码都是在客户端上执行，然后由客户端提交给 JobManager 的，这种方式客户端需要占用大量网络带宽。**应用模式不需要客户端，直接把应用提交到 JobManger 上运行**，这个 JobManager 只为执行这一个应用而存在，执行结束之后 JobManager 也就关闭了。

   ![应用模式](./images/Flink/应用模式.png)

总结：在会话模式下，集群的生命周期独立于作业的生命周期，且提交的作业共享资源。而单作业模式为每个提交的作业创建一个集群，带来更好的资源隔离，这时集群的生命周期与作业的生命周期绑定。最后，应用模式为每个应用程序创建一个会话集群，在 JobManager 上直接调用应用程序的 main()方法。



### 1.3.2 Standalone 模式

1. **解压缩文件**

   * 上传 Flink 安装包到 hadoop102 的 `/opt/software/` 目录下
   * 解压 Flink 到 `/opt/module/`目录：`tar -xzvf flink-1.15.2-bin-scala_2.12.tgz -C /opt/module/`

2. **配置集群**

   * 集群部署规划：

     |      | hadoop102  | hadoop103   | hadoop104   |
     | ---- | ---------- | ----------- | ----------- |
     | 角色 | JobManager | TaskManager | TaskManager |

   * 修改核心配置文件：`cd /opt/module/hadoop-3.2.3/etc/hadoop`、

3. 





### 1.3.3 Yarn 模式





## 1.4 Flink 运行时架构

### 1.4.1 系统架构



### 1.4.2 作业提交流程



### 1.4.3 重要概念





# 2. DataStream API

## 2.1 执行环境



## 2.2 源算子



## 2.3 转换算子



## 2.4 输出算子





# 3. Flink 时间和窗口











# 参考

1. [Flink 官网](https://flink.apache.org/)
2. 