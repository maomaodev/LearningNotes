# 1. Flume 入门

## 1.1 Flume 基础架构

Flume 是 Cloudera 提供的一个高可用的，高可靠的，分布式的**海量日志采集、聚合和传输的系统**，它最主要的作用是，**实时读取**服务器本地磁盘的数据，将数据写入到 HDFS。

* **Agent**：Agent 是一个 **JVM 进程**，它以事件的形式将数据从源头送至目的地，它主要由三个部分组成 Source、Channel、Sink。
* **Source**：Source 负责**接收数据**到 Flume Agent，它可以处理各种类型、各种格式的日志数据，包括 avro、thrift、exec、jms、spooling directory、netcat、taildir、sequence generator、syslog、http、legacy。
* **Sink**：Sink 不断**轮询 Channel 中的事件**，批量移除它们，并将这些事件批量写入存储或索引系统、或发送到另一个 Flume Agent，目的地包括 hdfs、logger、avro、thrift、ipc、file、HBase、solr、自定义。
* **Channel**：Channel 是**位于 Source 和 Sink 之间的缓冲区**，因此，它允许 Source 和 Sink 运作在不同的速率上。Channel 是**线程安全**的，可以同时处理几个 Source 的写入操作和几个 Sink 的读取操作。**Flume 自带两种 Channel：Memory Channel 和 File Channel**，Memory Channel 是内存中的队列，它在不需要关心数据丢失的情景下适用；File Channel 将所有事件写到磁盘。因此在程序关闭或机器宕机时不会丢失数据。
* **Event**：Flume 数据传输的基本单元，以 Event 的形式将数据从源头送至目的地。 **Event 由 Header 和 Body 两部分组成**，Header 用来存放该 Event 的一些属性，形式为 KV 结构， Body 用来存放该条数据，形式为字节数组。

![Flume架构](./images/Flume/Flume架构.png)



## 1.2 Flume 安装

1. **解压缩文件**

   * 上传 Flume 安装包到 hadoop102 的 `/opt/software/` 目录下
   * 解压 Flume 到 `/opt/module/`目录，并重命名为 flume：`tar -xzvf apache-flume-1.9.0-bin.tar.gz -C /opt/module/`

2. **配置相关环境**

   * 安装 Java 和 Hadoop，并配置相关环境变量

   * **删除 $FLUME_HOME/lib 目录下的 guava-11.0.2.jar 以兼容 Hadoop**，该 jar 包是由谷歌开发的工具包，由于 Flume 需要对接 Hadoop，若框架之间使用的版本不一致，则会导致兼容性问题，删除后自动通过环境变量使用 Hadoop 的 guava 包，同理，Hive 安装过程也需要删除该 jar 包：`rm lib/guava-11.0.2.jar`




## 1.3 Flume 案例

### 1.3.1 监控端口数据

```shell
# 需求：使用Flume监听一个端口，收集该端口数据，并打印到控制台
# 1.安装netcat工具
[maomao@hadoop102 flume]$ sudo yum -y install nc
# 2.创建job目录，并在该目录下创建Flume Agent配置文件，文件内容如下
[maomao@hadoop102 flume]$ mkdir job
[maomao@hadoop102 flume]$ vim job/netcat-flume-logger.conf
# 3.开启Flume监听端口
[maomao@hadoop102 flume]$ bin/flume-ng agent -n a1 -c conf/ -f job/netcat-flume-logger.conf  -Dflume.root.logger=INFO,console
# 4.新开一个SSH窗口，使用netcat工具向本机的44444端口发送内容
[maomao@hadoop102 flume]$ nc localhost 44444
maomao
# 5.在Flume监听页面观察接收数据情况
2022-09-17 23:50:06,720 (SinkRunner-PollingRunner-DefaultSinkProcessor) [INFO - org.apache.flume.sink.LoggerSink.process(LoggerSink.java:95)] Event: { headers:{} body: 6D 61 6F 6D 61 6F                               maomao }
```

```shell
# 命名Flume Agent组件：a1表示agent名称，r1表示source命令，k1表示sink名称，c1表示channel名称
# 复数表示可配置多个，单数表示只能配置一个，下同
a1.sources = r1
a1.sinks = k1
a1.channels = c1

# 配置source：type表示输入源类型，bind表示监听的主机，port表示监听的端口
a1.sources.r1.type = netcat
a1.sources.r1.bind = localhost
a1.sources.r1.port = 44444

# 配置sink：type表示输出类型
a1.sinks.k1.type = logger

# 配置channel：type表示channel类型，capacity表示事件event容量，transactionCapacity表示事务容量
a1.channels.c1.type = memory
a1.channels.c1.capacity = 1000
a1.channels.c1.transactionCapacity = 100

# 将source和sink绑定到channel
a1.sources.r1.channels = c1
a1.sinks.k1.channel = c1
```



### 1.3.2 监控单个追加文件

```shell

```



### 1.3.3 监控目录下多个新文件

```shell

```



### 1.3.4 监控目录下多个追加文件

```shell

```





# 2. Flume 进阶







