# 1. Prometheus

## 1.1 Prometheus 入门

### 1.1.1 简介

Prometheus（普罗米修斯） 受启发于 Google 的 Brogmon 监控系统，它基于 Golang 编写，**是一个开源的完整监控解决方案**，其对传统监控系统的测试和告警模型进行了彻底的颠覆，形成了基于中央化的规则计算、统一分析和告警的新模型。 相比于传统监控系统，Prometheus 具有以下优点：

* **易于管理**：Prometheus 核心部分只有一个单独的二进制文件，不存在任何的第三方依赖。唯一需要的就是本地磁盘，因此不会有潜在级联故障的风险。**Prometheus 基于 Pull 模型**的架构方式，可以在任何地方搭建我们的监控系统。对于一些复杂的情况，还可以使用 Prometheus 服务发现（Service Discovery）的能力动态管理监控目标。
* **监控服务内部运行状态**：基于 Prometheus 丰富的 Client 库，用户可以轻松的在应用程序中添加对Prometheus 的支持，从而让用户可以获取服务和应用内部真正的运行状态。
* **强大的数据模型**：所有采集的监控数据均以指标（metric）的形式保存在内置的时序数据库当中（TSDB）。所有的样本除了基本的指标名称以外，还包含一组用于描述该样本特征的标签，基于这些标签我们可以方便地对监控数据进行聚合、过滤、裁剪。
* **强大的查询语言 PromQL**：Prometheus 内置了一个强大的数据查询语言 PromQL，通过 PromQL 可以实现对监控数据的查询、聚合，同时 PromQL 也被应用于数据可视化（如 Grafana）以及告警当中。
* **高效**：对于监控系统而言，大量的监控任务必然导致大量数据产生。而 Prometheus 可以高效地处理这些数据，对于单一 Prometheus Server 实例，它可以处理数以百万的监控指标，每秒可以处理数十万的数据点。
* **可扩展**：Prometheus 对于联邦集群的支持，可以让多个 Prometheus 实例产生一个逻辑集群，当单实例 Prometheus Server 处理的任务量过大时，通过使用功能分区（sharding）+ 联邦集群（federation）可以对其进行扩展。
* **易于集成**：使用 Prometheus 可以快速搭建监控服务，并且可以非常方便地在应用程序中进行集成。目前支持  Java、JMX、Python、Go、Ruby 等语言的客户端 SDK，基于这些 SDK 可以快速让应用程序纳入到 Prometheus 的监控当中，或者开发自己的监控数据收集程序。同时 Prometheus 还支持与其他的监控系统进行集成：Graphite、Statsd、Collected、Nagios 等。
* **可视化**：Prometheus Server 自带了一个 Prometheus UI，可以方便地对数据进行查询，并且支持以图形化的形式展示数据。同时 Prometheus 还提供了一个独立的 Dashboard 解决方案 Promdash。最新的 Grafana 可视化工具也提供了完整的 Prometheus 支持，可以创建更加精美的监控图标。基于 Prometheus 提供的 API 还可以实现自己的监控可视化 UI。



### 1.1.2 架构



![Prometheus架构](./images/Prometheus/Prometheus架构.png)

1. **Prometheus Server 是 Prometheus 组件中的核心部分，负责实现对监控数据的获取，存储以及查询**。 Prometheus Server 可以通过静态配置管理监控目标，也可以配合使用 Service Discovery 的方式动态管理监控目标，并从这些监控目标中获取数据。其次 Prometheus Server 需要对采集到的监控数据进行存储，Prometheus Server 本身就是一个时序数据库，将采集到的监控数据按照时间序列的方式存储在本地磁盘当中。最后 Prometheus Server 对外提供了自定义的 PromQL 语言，实现对数据的查询以及分析。

   Prometheus Server 内置的 Express Browser UI，通过这个 UI 可以直接通过 PromQL 实现数据的查询以及可视化。Prometheus Server 的联邦集群能力可以使其从其他的 Prometheus Server 实例中获取数据，因此在大规模监控的情况下，可以通过联邦集群以及功能分区的方式对 Prometheus Server 进行扩展。

2. **Exporter 将监控数据采集的端点通过 HTTP 服务的形式暴露给 Prometheus Server**，Prometheus Server 通过访问该 Exporter 提供的 Endpoint 端点，即可获取到需要采集的监控数据。一般可将 Exporter 分为 2 类：

   * 直接采集：这一类 Exporter 直接内置了对 Prometheus 监控的支持，比如 cAdvisor、Kubernetes、Etcd、Gokit 等，都直接内置了用于向 Prometheus 暴露监控数据的端点。
   * 间接采集：间接采集，原有监控目标并不直接支持 Prometheus，因此我们需要通过 Prometheus 提供的 Client Library 编写该监控目标的监控采集程序。例如：Mysql Exporter、JMX Exporter、Consul Exporter 等。

3. 在 Prometheus Server 中支持基于 PromQL 创建告警规则，如果满足 PromQL 定义的规则，则会产生一条告警，而**告警的后续处理流程则由 AlertManager 进行管理**。在 AlertManager 中我们可以与邮件，Slack 等等内置的通知方式进行集成，也可以通过 Webhook 自定义告警处理方式。AlertManager 即 Prometheus 体系中的告警处理中心。

4. 由于 Prometheus 数据采集基于 Pull 模型进行设计，因此在网络环境的配置上必须要让 Prometheus Server 能够直接与 Exporter 进行通信。 当这种网络需求无法直接满足时，就可以利用 PushGateway 来进行中转。**可以通过 PushGateway 将内部网络的监控数据主动 Push 到 Gateway 当中，而 Prometheus Server 则可以采用同样 Pull 的方式从 PushGateway 中获取到监控数据**。



### 1.1.3 安装

1. **安装 Prometheus Server**

   * 上传 Prometheus 安装包到 `/opt/software/` 目录下

   * 解压 Prometheus 到 `/opt/module/`目录，并重命名为 prometheus-2.41.0：`tar -xzvf prometheus-2.41.0.linux-amd64.tar.gz -C /opt/module/`

   * 修改配置文件：`vim prometheus.yml`

     ```yml
     scrape_configs:
       # The job name is added as a label `job=<job_name>` to any timeseries scraped from this config.
       - job_name: "prometheus"
     
         # metrics_path defaults to '/metrics'
         # scheme defaults to 'http'.
     
         static_configs:
           - targets: ["localhost:9090"]
     
       # 添加PushGateway监控配置
       - job_name: "pushgateway"
         static_configs:
           - targets: ["hadoop102:9091"]
             labels:
               instance: pushgateway
     
       # 添加Node Exporter监控配置，targets若有多个监控节点使用逗号分隔
       - job_name: "node exporter"
         static_configs:
           - targets: ["hadoop102:9100", "hadoop103:9100", "hadoop104:9100"]  
     ```

2. **安装 Pushgateway**

   * 上传 Pushgateway 安装包到 `/opt/software/` 目录下
   * 解压 Pushgateway 到 `/opt/module/`目录，并重命名为 pushgateway-1.5.1：`tar -xzvf pushgateway-1.5.1.linux-amd64.tar.gz -C /opt/module/`

3. **安装 Alertmanager（可选）**

   * 上传 Alertmanager 安装包到 `/opt/software/` 目录下
   * 解压 Alertmanager 到 `/opt/module/`目录，并重命名为 alertmanager-0.23.0：`tar -xzvf alertmanager-0.23.0.linux-amd64.tar.gz -C /opt/module/`

4. **安装 Node Exporter（可选）**

   * 上传 Node Exporter 安装包到 `/opt/software/` 目录下

   * 解压 Node Exporter 到 `/opt/module/`目录，并重命名为 node_exporter-1.2.2：`tar -xzvf node_exporter-1.2.2.linux-amd64 -C /opt/module/`

   * 启动 Node Exporter：`./node_exporter`

   * 浏览器访问：http://hadoop102:9100/metrics，可以看到 Node Exporter 获取到的当前主机的监控数据

   * 将解压后的目录分发到要监控的节点：`xsync node_exporter-1.2.2`

   * 创建 service 文件，配置开机自启动：`sudo vim /usr/lib/systemd/system/node_exporter.service`

     ```shell
     [Unit]
     Description=node_export
     Documentation=https://github.com/prometheus/node_exporter
     After=network.target
     
     [Service]
     Type=simple
     User=maomao
     ExecStart=/opt/module/node_exporter-1.2.2/node_exporter
     Restart=on-failure
     
     [Install]
     WantedBy=multi-user.target
     ```

   * 分发文件：`sudo /home/atguigu/bin/xsync /usr/lib/systemd/system/node_exporter.service`

   * 设为开机自启动（所有机器都执行）：`sudo systemctl enable node_exporter.service`

   * 启动服务（所有机器都执行）：`sudo systemctl start node_exporter.service`

5. **安装 Grafana（可选）**

   * 上传 Grafana 安装包到 `/opt/software/` 目录下
   * 解压 Grafana 到 `/opt/module/`目录，并重命名为 grafana-enterprise-9.3.2：`tar -xzvf grafana-enterprise-9.3.2.linux-amd64.tar.gz -C /opt/module/`

6. **启动并测试**

   * 启动 Prometheus Server，默认端口 9090：`nohup ./prometheus --config.file=prometheus.yml > ./prometheus.log 2>&1 &`
   * 启动 Pushgateway：`nohup ./pushgateway --web.listen-address :9091 > ./pushgateway.log 2>&1 &`
   * 启动 Grafana，默认端口 3000：`nohup bin/grafana-server web > ./grafana.log 2>&1 &`
   * 浏览器访问 Prometheus Server：http://hadoop102:9090/
   * 浏览器访问 Grafana，默认用户名和密码均为 admin：http://hadoop102:3000/



## 1.2 PromQL

### 1.2.1 时间序列

Prometheus 会将所有采集到的样本数据以时间序列（time-series）的方式保存在内存的 TSDB（时序数据库）中，并且定时保存到硬盘上。time-series 是按照时间戳和值的序列顺序存放的，我们称之为向量（vector）。在 time-series 中的每一个点称为一个样本（sample），样本由以下三部分组成：

- **指标（metric）**：指标名称（metrics name）和描述当前样本特征的一组标签集（labelset）
- **时间戳（timestamp）**：一个精确到毫秒的时间戳
- **样本值（value）**： 一个 float64 的浮点型数据表示当前样本的值

```
<--------------- metric ---------------------><-timestamp -><-value->
http_request_total{status="200", method="GET"}@1434417560938 => 94355
http_request_total{status="200", method="GET"}@1434417561287 => 94334
```

在形式上，所有的 Metric 都通过如下格式标示：

```
<metric name>{<label name>=<label value>, ...}
```

**指标的名称（metric name）可以反映被监控样本的含义**（比如 http_request_total 表示当前系统接收到的 HTTP 请求总量）指标名称只能由ASCII字符、数字、下划线以及冒号组成并必须符合正则表达式`[a-zA-Z_:][a-zA-Z0-9_:]*`。

**标签（label）反映了当前样本的特征维度，通过这些维度 Prometheus 可以对样本数据进行过滤，聚合等**。标签的名称只能由 ASCII 字符、数字以及下划线组成并满足正则表达式`[a-zA-Z_][a-zA-Z0-9_]*`。

其中以 __ 作为前缀的标签，是系统保留的关键字，只能在系统内部使用。标签的值则可以包含任何 Unicode 编码的字符。在 Prometheus 的底层实现中指标名称实际上是以 `__name__=<metric name>` 的形式保存在数据库中的，因此以下两种方式均表示的同一条 time-series：

```
api_http_requests_total{method="POST", handler="/messages"}

{__name__="api_http_requests_total"，method="POST", handler="/messages"}
```



### 1.2.2 Metrics 类型

Prometheus 定义了 4 种不同的指标类型（metric type）：Counter（计数器）、Gauge（仪表盘）、Histogram（直方图）、Summary（摘要）。

1. **Counter：只增不减的计算器**

   Counter 类型的指标和计数器一样，只增不减（除非系统发生重置），一般在定义时推荐使用 _total 作为名称后缀，常见的指标如 http_requests_total（系统接收到的 HTTP 请求总量）。可以在应用中使用 Counter 记录某些事件发生的次数，通过以时序的形式存储这些数据，同时 PromQL 内置的聚合操作和函数可以让用户对这些数据进行进一步的分析。

   ```
   # 通过rate()函数获取HTTP请求量的增长率
   rate(http_requests_total[5m])
   
   # 查询当前系统中，访问量前10的HTTP地址
   topk(10, http_requests_total)
   ```

2. **Gauge：可增可减的仪表盘**

   与 Counter 不同，Gauge 类型的指标侧重于反应系统的当前状态，因此这类指标的样本数据可增可减，常见指标如 node_memory_MemAvailable（可用内存大小）。

   ```
   # 通过delta()函数可以获取样本在一段时间返回内的变化情况,如计算CPU温度在两个小时内的差异
   delta(cpu_temp_celsius{host="zeus"}[2h])
   ```

3. **使用 Histogram 和 Summary 分析数据分布情况**

   在大多数情况下人们都倾向于使用某些量化指标的平均值，如页面的平均响应时间。这种方式的问题很明显，以系统 API 调用的平均响应时间为例：如果大多数 API 请求都维持在 100ms 的响应时间范围内，而个别请求的响应时间需要 5s，那么就会导致某些页面的响应时间落到中位数的情况，而这种现象被称为**长尾问题**。

   为了区分是平均的慢还是长尾的慢，最简单的方式就是按照请求延迟的范围进行分组。例如，统计延迟在 0~10ms 之间的请求数有多少，而 10~20ms 之间的请求数又有多少。通过这种方式可以快速分析系统慢的原因。Histogram 和 Summary 都是为了能够解决这样问题的存在，通过 Histogram 和 Summary 类型的监控指标，我们可以快速了解监控样本的分布情况。

   例如，指标 prometheus_tsdb_wal_fsync_duration_seconds 的指标类型为 Summary。 它记录了Prometheus Server 中 wal_fsync 的处理时间，通过访问 Prometheus Server 的 /metrics 地址，可以获取到以下监控样本数据：

   ```
   # HELP prometheus_tsdb_wal_fsync_duration_seconds Duration of WAL fsync.
   # TYPE prometheus_tsdb_wal_fsync_duration_seconds summary
   prometheus_tsdb_wal_fsync_duration_seconds{quantile="0.5"} 0.012352463
   prometheus_tsdb_wal_fsync_duration_seconds{quantile="0.9"} 0.014458005
   prometheus_tsdb_wal_fsync_duration_seconds{quantile="0.99"} 0.017316173
   prometheus_tsdb_wal_fsync_duration_seconds_sum 2.888716127000002
   prometheus_tsdb_wal_fsync_duration_seconds_count 216
   ```

   从上面的样本中可以得知当前 Prometheus Server 进行 wal_fsync 操作的总次数为 216 次，耗时 2.888716127000002s。其中中位数（quantile=0.5）的耗时为 0.012352463，9分位数（quantile=0.9）的耗时为 0.014458005s。

   在 Prometheus Server 自身返回的样本数据中，我们还能找到类型为 Histogram 的监控指标：

   ```
   # HELP prometheus_tsdb_compaction_chunk_range Final time range of chunks on their first compaction
   # TYPE prometheus_tsdb_compaction_chunk_range histogram
   prometheus_tsdb_compaction_chunk_range_bucket{le="100"} 0
   prometheus_tsdb_compaction_chunk_range_bucket{le="400"} 0
   prometheus_tsdb_compaction_chunk_range_bucket{le="1600"} 0
   prometheus_tsdb_compaction_chunk_range_bucket{le="6400"} 0
   prometheus_tsdb_compaction_chunk_range_bucket{le="25600"} 0
   prometheus_tsdb_compaction_chunk_range_bucket{le="102400"} 0
   prometheus_tsdb_compaction_chunk_range_bucket{le="409600"} 0
   prometheus_tsdb_compaction_chunk_range_bucket{le="1.6384e+06"} 260
   prometheus_tsdb_compaction_chunk_range_bucket{le="6.5536e+06"} 780
   prometheus_tsdb_compaction_chunk_range_bucket{le="2.62144e+07"} 780
   prometheus_tsdb_compaction_chunk_range_bucket{le="+Inf"} 780
   prometheus_tsdb_compaction_chunk_range_sum 1.1540798e+09
   prometheus_tsdb_compaction_chunk_range_count 780
   ```

   与 Summary 类型的指标相似之处在于 Histogram 类型的样本同样会反应当前指标的记录的总数（以 \_count 作为后缀）以及其值的总量（以 _sum 作为后缀）。不同在于 Histogram 指标直接反应了在不同区间内样本的个数，区间通过标签 le 进行定义。

   同时对于 Histogram 的指标，我们还可以通过 histogram_quantile() 函数计算出其值的分位数。不同在于 Histogram 通过 histogram_quantile 函数是在服务器端计算的分位数；而 Sumamry 的分位数则是直接在客户端计算完成。因此对于分位数的计算而言，Summary 在通过 PromQL 进行查询时有更好的性能表现，而 Histogram 则会消耗更多的资源，反之对于客户端而言 Histogram 消耗的资源更少。在选择这两种方式时用户应该按照自己的实际场景进行选择。



### 1.2.3 初识 PromQL

1. **查询时间序列**

   当我们直接使用监控**指标名称**查询时，可以查询该指标下的所有时间序列。

   ```
   # 两者等价，表达式会返回指标名称为http_requests_total的所有时间序列
   http_requests_total
   http_requests_total{}
   ```

   ```
   http_requests_total{code="200",handler="alerts",instance="localhost:9090",job="prometheus",method="get"}=(20889@1518096812.326)
   http_requests_total{code="200",handler="graph",instance="localhost:9090",job="prometheus",method="get"}=(21287@1518096812.326)
   ```

   PromQL 还支持用户根据时间序列的**标签匹配模式**来对时间序列进行过滤，目前主要支持两种匹配模式：**完全匹配和正则匹配**。PromQL 支持使用 = 和 != 两种完全匹配模式：

   - 通过使用 `label=value` 可以选择那些标签满足表达式定义的时间序列
   - 反之使用 `label!=value` 则可以根据标签匹配排除时间序列

   ```
   # 查询所有http_requests_total时间序列中满足（排除）标签instance为localhost:9090的时间序列
   http_requests_total{instance="localhost:9090"}
   http_requests_total{instance!="localhost:9090"}
   ```

   除了使用完全匹配的方式对时间序列进行过滤以外，PromQL 还可以支持使用正则表达式作为匹配条件，多个表达式之间使用 | 进行分离：

   - 使用 `label=~regx` 表示选择那些标签符合正则表达式定义的时间序列
   - 反之使用 `label!~regx` 进行排除

   ```
   # 查询多个环节下的时间序列序列
   http_requests_total{environment=~"staging|testing|development",method!="GET"}
   ```

2. **范围查询**

   直接通过类似于 PromQL 表达式 http_requests_total 查询时间序列时，返回值中只会包含该时间序列中的最新的一个样本值，这样的返回结果我们称之为**瞬时向量**，相应的这样的表达式称之为**瞬时向量表达式**。

   而如果我们想过去一段时间范围内的样本数据时，则需要使用**区间向量表达式**，通过区间向量表达式查询到的结果我们称为**区间向量**。区间向量表达式和瞬时向量表达式之间的差异在于在**区间向量表达式需要定义时间选择的范围，时间范围通过时间范围选择器 [] 进行定义**。

   ```
   # 选择最近5分钟内的所有样本数据，表达式将会返回查询到的时间序列中最近5分钟的所有样本数据
   # 时间单位：s（秒）、m（分钟）、h（小时）、d（天）、w（周）、y（年）
   http_requests_total{}[5m]
   ```

   ```
   http_requests_total{code="200",handler="alerts",instance="localhost:9090",job="prometheus",method="get"}=[
       1@1518096812.326
       1@1518096817.326
       1@1518096822.326
       1@1518096827.326
       1@1518096832.326
       1@1518096837.325
   ]
   http_requests_total{code="200",handler="graph",instance="localhost:9090",job="prometheus",method="get"}=[
       4@1518096812.326
       4@1518096817.326
       4@1518096822.326
       4@1518096827.326
       4@1518096832.326
       4@1518096837.325
   ]
   ```

3. **时间位移操作**

   在瞬时向量表达式或者区间向量表达式中，都是以当前时间为基准：

   ```
   http_request_total{} # 瞬时向量表达式，选择当前最新的数据
   http_request_total{}[5m] # 区间向量表达式，选择以当前时间为基准，5分钟内的数据
   ```

   而如果我们想查询，5 分钟前的瞬时样本数据，或昨天一天的区间内的样本数据呢? 这时我们就可以使用位移操作，位移操作的关键字为 **offset**。

   ```
   http_request_total{} offset 5m
   http_request_total{}[1d] offset 1d
   ```

4. **聚合操作**

   一般来说，如果描述样本特征的标签在并非唯一的情况下，通过 PromQL 查询数据，会返回多条满足这些特征维度的时间序列。而 PromQL 提供的聚合操作可以对这些时间序列进行处理，形成一条新的时间序列。

   ```
   # 查询系统所有http请求的总量
   sum(http_request_total)
   
   # 按照mode计算主机CPU的平均使用时间
   avg(node_cpu) by (mode)
   
   # 按照主机查询各个主机的CPU使用率
   sum(sum(irate(node_cpu{mode!='idle'}[5m]))  / sum(irate(node_cpu[5m]))) by (instance)
   ```

5. **标量和字符串**

   除了使用瞬时向量表达式和区间向量表达式外，PromQL 还支持用户使用标量和字符串。需要注意的是，当使用表达式 count(http_requests_total)，返回的数据类型依然是瞬时向量，可以通过**内置函数 scalar() 将单个瞬时向量转换为标量**。

   * **标量（Scalar）：一个浮点型的数字值，没有时序**
   * **字符串（String）：一个简单的字符串值**

6. **合法的 PromQL 表达式**

   所有的 PromQL 表达式都必须**至少包含一个指标名称**（如 http_request_total），或者**一个不会匹配到空字符串的标签过滤器**（如 {code="200"}）。

   ```
   http_request_total # 合法
   http_request_total{} # 合法
   {__name__=~"http_request_total"} # 合法
   
   {method="get"} # 合法
   {job=~".*"} # 不合法，匹配空字符串的标签过滤器
   ```



### 1.2.4 PromQL 操作符

1. **数学运算**

   PromQL 支持的数学运算包括：+（加）、-（减法）、*（乘）、/（除）、%（求余）、^（幂运算）。当**瞬时向量与标量之间进行数学运算**时，数学运算符会作用于瞬时向量中的每一个样本值，从而得到一组新的时间序列。而如果是**瞬时向量与瞬时向量之间进行数学运算**时，则会依次找到与左边向量元素匹配（标签完全一致）的右边向量元素进行运算，如果没找到匹配元素，则直接丢弃，同时新的时间序列将不会包含指标名称。

   ```
   # 获取当前主机可用的内存空间大小，单位为Bytes，转换为MB
   node_memory_free_bytes_total / (1024 * 1024)
   
   # 获取主机磁盘IO的总量
   node_disk_bytes_written + node_disk_bytes_read
   ```

2. **使用布尔运算过滤时间序列**

   PromQL 支持的布尔运算包括：==（相等）、!=（不相等）、>（大于）、<（小于）、>=（大于等于）、<=（小于等于）。当**瞬时向量与标量进行布尔运算**时，PromQL 依次比较向量中的所有时间序列样本的值，如果比较结果为 true 则保留，反之丢弃。而**瞬时向量与瞬时向量直接进行布尔运算**时，则同样遵循默认的匹配模式：依次找到与左边向量元素匹配（标签完全一致）向量元素进行相应的操作，如果没找到匹配元素，则直接丢弃。

   ```
   # 获取当前内存使用率超过95%的主机
   (node_memory_bytes_total - node_memory_free_bytes_total) / node_memory_bytes_total > 0.95
   ```

3. **使用 bool 修饰符改变布尔运算符的行为**

   布尔运算符的默认行为是对时序数据进行过滤，而在其它的情况下我们可能需要的是真正的布尔结果，这时可以使用 bool 修饰符改变布尔运算的默认行为。使用 bool 修改符后，**布尔运算不会对时间序列进行过滤，而是将瞬时向量中的各个样本数据与标量比较，结果为 0 或者 1**，从而形成一条新的时间序列。需要注意的是，如果是在两个标量之间使用布尔运算，则必须使用 bool 修饰符。

   ```
   # 获取当前模块的HTTP请求量是否>=1000，若大于等于1000则返回1（true），否则返回0（false）
   http_requests_total > bool 1000
   
   # 标量之间进行布尔运算，结果为1
   2 == bool 2
   ```

4. **集合运算符与操作符优先级**

   通过集合运算，可以在两个瞬时向量之间进行相应的集合操作，PromQL 支持的集合运算符包括：and（并且）、or（或者）、unless（排除）。在 PromQL 操作符中，优先级由高到低依次为：

   ```
   1. ^
   2. *, /, %
   3. +, -
   4. ==, !=, <=, <, >=, >
   5. and, unless
   6. or
   ```



### 1.2.5 PromQL 聚合操作

PromQL 提供的内置聚合操作包括：sum（求和）、min（最小值）、max（最大值）、avg（平均值）、stddev（标准差）、stdvar（标准方差）、count（计数）、count_values（对 value 进行计数）、bottomk（后 n 条时序）、topk（前 n 条时序）、quantile（分位数），这些操作符作用于瞬时向量，可以将瞬时表达式返回的样本数据进行聚合，形成一个新的时间序列。语法如下：

```
<aggr-op>([parameter,] <vector expression>) [without|by (<label list>)]
```

其中只有 count_values、quantile、topk、bottomk 支持参数 parameter。**without 用于从计算结果中移除列举的标签，而保留其它标签，by 则正好相反，结果向量中只保留列出的标签，其余标签则移除**。通

```
# 两者等价
sum(http_requests_total) without (instance)
sum(http_requests_total) by (code,handler,job,method)

# 计算整个应用的HTTP请求总量
sum(http_requests_total)

# count_values用于时间序列中每一个样本值出现的次数，它会为每一个唯一的样本值输出一个时间序列，并且每一个时间序列包含一个额外的标签
count_values("count", http_requests_total)

# 获取HTTP请求数前5位的时序样本数据
topk(5, http_requests_total)

# quantile用于计算当前样本数据值的分布情况quantile(φ, express)，其中0 ≤ φ ≤ 1，当φ为0.5时，即表示找到当前样本数据的中位数
quantile(0.5, http_requests_total)
```



### 1.2.6 PromQL 内置函数

1. **计算 Counter 指标增长率**

   Counter 类型的监控指标其特点是只增不减，在没有发生重置（如服务器重启，应用重启）的情况下其样本值应该是不断增大的。为了能够更直观的表示样本数据的变化剧烈情况，需要计算样本的增长速率。

   **increase(v range-vector) 函数获取区间向量中的第一个和最后一个样本并返回其增长量**，其中参数 v 是一个区间向量。除了使用 increase 函数外，PromQL 还直接内置了 **rate(v range-vector) 函数直接计算区间向量 v 在时间窗口内平均增长速率**。

   ```
   # 获取时间序列最近两分钟的平均增长率
   increase(node_cpu[2m]) / 120
   
   # 以下表达式可以得到与increase函数相同的结果
   rate(node_cpu[2m])
   ```

   需要注意的是，使用 rate 或 increase 函数计算样本的平均增长速率，容易陷入“长尾问题”当中，其无法反应在时间窗口内样本数据的突发变化。 例如，对于主机在 2 分钟的时间窗口内，可能在某一个由于访问量或其它问题导致 CPU 占用100%的情况，但是通过计算在时间窗口内的平均增长率却无法反应出该问题。

   为了解决该问题，PromQL 提供了另外一个灵敏度更高的函数 irate(v range-vector)。**irate 同样用于计算区间向量的计算率，但是其反应出的是瞬时增长率，它通过区间向量中最后两个样本数据来计算区间向量的增长速率**。这种方式可以避免在时间窗口范围内的“长尾问题”，并且体现出更好的灵敏度，绘制的图标能够更好的反应样本数据的瞬时变化状态。不过当需要分析长期趋势或者在告警规则中，irate 的这种灵敏度反而容易造成干扰，因此在长期趋势分析或者告警中更推荐使用 rate 函数。

   ```
   irate(node_cpu[2m])
   ```

2. **预测 Gauge 指标变化趋势**

   在一般情况下，系统管理员为了确保业务持续可用，会针对服务器的资源设置相应的告警阈值。如当磁盘空间只剩 512MB 时向相关人员发送告警通知，这种基于阈值的告警模式对于资源用量是平滑增长的情况是能有效工作的。 但是如果资源不是平滑变化，比如某些业务增长，存储空间的增长速率提升了好几倍，这时如果基于原有阈值去触发告警，当系统管理员收到告警后可能还没来得及处理，系统就已经不可用了。 因此阈值通常来说不是固定的，需要定期进行调整才能保证该告警阈值能够发挥去作用。那么还有更好的方法吗？

   PromQL 中内置的 predict_linear(v range-vector, t scalar) 函数可以帮助系统管理员更好的处理此类情况，**predict_linear 函数可以预测时间序列 v 在 t 秒后的值**，它基于简单线性回归的方式，对时间窗口内的样本数据进行统计，从而可以对时间序列的变化趋势做出预测。

   ```
   # 基于2小时的样本数据，预测主机可用磁盘空间的是否在4个小时候被占满
   predict_linear(node_filesystem_free{job="node"}[2h], 4 * 3600) < 0
   ```



### 1.2.7 HTTP API 使用 PromQL

Prometheus API 使用了 JSON 格式的响应内容。 当 API 调用成功后将会返回 2xx 的 HTTP 状态码，反之，当 API 调用失败时可能返回以下几种不同的 HTTP 状态码：

- 404 Bad Request：当参数错误或者缺失时。
- 422 Unprocessable Entity：当表达式无法执行时。
- 503 Service Unavailiable：当请求超时或者被中断时。

**瞬时数据查询**：**通过 `GET /api/v1/query` 可以查询 PromQL 在特定时间点下的计算结果**。URL 请求参数如下：

* query=：PromQL 表达式。
* time=：用于指定用于计算 PromQL 的时间戳。可选参数，默认情况下使用当前系统时间。
* timeout=：超时设置。可选参数，默认情况下使用 -query,timeout 的全局设置。

PromQL 表达式可能返回多种数据类型，在响应内容中使用 resultType 表示当前返回的数据类型，包括：vector（瞬时向量）、matrix（区间向量）、标量（scalar）、字符串（string）。

```json
# 查询表达式up在时间点2015-07-01T20:10:51.781Z的计算结果
$ curl 'http://localhost:9090/api/v1/query?query=up&time=2015-07-01T20:10:51.781Z'
{
   "status" : "success",
   "data" : {
      "resultType" : "vector",
      "result" : [
         {
            "metric" : {
               "__name__" : "up",
               "job" : "prometheus",
               "instance" : "localhost:9090"
            },
            "value": [ 1435781451.781, "1" ]
         },
         {
            "metric" : {
               "__name__" : "up",
               "job" : "node",
               "instance" : "localhost:9100"
            },
            "value" : [ 1435781451.781, "0" ]
         }
      ]
   }
}
```

**区间数据查询**：**通过 `GET /api/v1/query_range` 可以查询 PromQL 在一段时间内的计算结果**，且结果一定是一个区间向量。URL请求参数如下：

- query=: PromQL 表达式
- start=: 起始时间
- end=: 结束时间
- step=: 查询步长
- timeout=: 超时设置。可选参数，默认情况下使用 -query,timeout 的全局设置

```json
# 查询表达式up在30秒范围内以15秒为间隔计算PromQL表达式的结果
$ curl 'http://localhost:9090/api/v1/query_range?query=up&start=2015-07-01T20:10:30.781Z&end=2015-07-01T20:11:00.781Z&step=15s'
{
   "status" : "success",
   "data" : {
      "resultType" : "matrix",
      "result" : [
         {
            "metric" : {
               "__name__" : "up",
               "job" : "prometheus",
               "instance" : "localhost:9090"
            },
            "values" : [
               [ 1435781430.781, "1" ],
               [ 1435781445.781, "1" ],
               [ 1435781460.781, "1" ]
            ]
         },
         {
            "metric" : {
               "__name__" : "up",
               "job" : "node",
               "instance" : "localhost:9091"
            },
            "values" : [
               [ 1435781430.781, "0" ],
               [ 1435781445.781, "0" ],
               [ 1435781460.781, "1" ]
            ]
         }
      ]
   }
}
```



## 1.3 告警处理

### 1.3.1 告警简介

告警能力在 Prometheus 的架构中被划分成两个独立的部分，通过定义 AlertRule（告警规则），Prometheus 会**周期性的对告警规则进行计算，如果满足告警触发条件就会向 Alertmanager 发送告警信息**。一条告警规则主要由以下几部分组成：

- **告警名称**：用户需要为告警规则命名
- **告警规则**：告警规则实际上主要由 PromQL 进行定义，其意义是**当表达式查询结果持续多长时间（During）后出发告警**

在 Prometheus 中，还可以通过 Group（告警组）对一组相关的告警进行统一定义，这些定义都是通过 YAML 文件来统一管理的。Alertmanager 作为一个独立的组件，负责接收并处理来自 Prometheus Server（也可以是其它的客户端程序）的告警信息。Alertmanager 可以对这些告警信息进行进一步处理，如当接收到大量重复告警时能消除重复的告警信息，同时对告警信息进行分组并且路由到正确的通知方，Prometheus 内置了对邮件、Slack 等多种通知方式的支持，还支持与 Webhook 集成，以支持更多定制化的场景。例如，Alertmanager 不支持钉钉，那用户完全可以通过 Webhook 与钉钉机器人进行集成，从而通过钉钉接收告警信息。同时， AlertManager 还提供了静默（不发送告警通知）和告警抑制（当某一告警发出后，停止重复发送由此告警引发的其它告警）机制来对告警通知行为进行优化。



### 1.3.2 自定义告警规则

在告警规则文件中，我们可以将一组相关的规则设置定义在一个 group 下，在每一个 group 中，我们可以定义多个告警规则（rule）。一条告警规则主要由以下几部分组成：

- **alert**：告警规则的名称
- **expr**：基于 PromQL 表达式告警触发条件，用于计算是否有时间序列满足该条件
- **for**：评估等待时间，可选参数。用于表示只有当触发条件持续一段时间后才发送告警。在等待期间新产生告警的状态为 pending
- **labels**：自定义标签，允许用户指定要附加到告警上的一组附加标签
- **annotations**：用于指定一组附加信息，比如用于描述告警详细信息的文字等，annotations 的内容在告警产生时会一同作为参数发送到 Alertmanager

```yaml
groups:
- name: example
  rules:
  - alert: HighErrorRate
    expr: job:request_latency_seconds:mean5m{job="myjob"} > 0.5
    for: 10m
    labels:
      severity: page
    annotations:
      summary: High request latency
      description: description info
```

为了让 Prometheus 启用定义的告警规则，需要在 Prometheus 全局配置文件中**通过 rule_files 指定一组告警规则文件的访问路径**，Prometheus 启动后会自动扫描这些路径下规则文件中定义的内容，并且根据这些规则计算是否向外部发送通知。

```yaml
rule_files:
  [ - <filepath_glob> ... ]
```

默认情况下 Prometheus 会每分钟对这些告警规则进行计算，如果用户想定义自己的告警计算周期，则可以通过evaluation_interval 来覆盖默认的计算周期。

```yaml
global:
  [ evaluation_interval: <duration> | default = 1m ]
```



### 1.3.3 Alertmanager 配置概述

Alertmanager 主要负责对 Prometheus 产生的告警进行统一处理，因此在 Alertmanager 配置中一般会包含以下几个主要部分：

- **全局配置（global）**：用于定义一些全局的公共参数，如全局的 SMTP 配置、Slack 配置等内容
- **模板（templates）**：用于定义告警通知时的模板，如 HTML 模板，邮件模板等
- **告警路由（route）**：根据标签匹配，确定当前告警应该如何处理
- **接收人（receivers）**：接收人是一个抽象的概念，它可以是一个邮箱也可以是微信、Slack 或 Webhook 等，接收人一般配合告警路由使用
- **抑制规则（inhibit_rules）**：合理设置抑制规则可以减少垃圾告警的产生

```yaml
global:
  [ resolve_timeout: <duration> | default = 5m ]
  [ smtp_from: <tmpl_string> ] 
  [ smtp_smarthost: <string> ] 
  [ smtp_hello: <string> | default = "localhost" ]
  [ smtp_auth_username: <string> ]
  [ smtp_auth_password: <secret> ]
  [ smtp_auth_identity: <string> ]
  [ smtp_auth_secret: <secret> ]
  [ smtp_require_tls: <bool> | default = true ]
  [ slack_api_url: <secret> ]
  [ victorops_api_key: <secret> ]
  [ victorops_api_url: <string> | default = "https://alert.victorops.com/integrations/generic/20131114/alert/" ]
  [ pagerduty_url: <string> | default = "https://events.pagerduty.com/v2/enqueue" ]
  [ opsgenie_api_key: <secret> ]
  [ opsgenie_api_url: <string> | default = "https://api.opsgenie.com/" ]
  [ hipchat_api_url: <string> | default = "https://api.hipchat.com/" ]
  [ hipchat_auth_token: <secret> ]
  [ wechat_api_url: <string> | default = "https://qyapi.weixin.qq.com/cgi-bin/" ]
  [ wechat_api_secret: <secret> ]
  [ wechat_api_corp_id: <string> ]
  [ http_config: <http_config> ]

templates:
  [ - <filepath> ... ]

route: <route>

receivers:
  - <receiver> ...

inhibit_rules:
  [ - <inhibit_rule> ... ]
```

完整配置格式如上。在全局配置中需要注意的是 resolve_timeout，该参数定义了当 Alertmanager 持续多长时间未接收到告警后标记告警状态为 resolved（已解决），该参数可能会影响到告警恢复通知的接收时间，读者可根据实际场景进行定义，其默认值为 5 分钟。



## 1.4 Exporter

### 1.4.1 Exporter 简介

1. **Exporter 来源**

   广义上讲，所有可以向 Prometheus 提供监控样本数据的程序都可以称为一个 Exporter，而 Exporter 的一个实例称为 target。从 Exporter 的来源上来讲，主要分为两类：**社区提供的、用户自定义的**。

   Prometheus 社区提供了丰富的 Exporter 实现，涵盖了从基础设施、中间件以及网络等各个方面的监控功能。这些 Exporter 可以实现大部分通用的监控需求，下表列举一些社区中常用的Exporter。

   | 范围     | 常用 Exporter                                                |
   | -------- | ------------------------------------------------------------ |
   | 数据库   | MySQL Exporter、Redis Exporte、MongoDB Exporter、MSSQL Exporter 等 |
   | 硬件     | Apcupsd Exporter、IoT Edison Exporter、IPMI Exporter、Node Exporter 等 |
   | 消息队列 | Beanstalkd Exporter、Kafka Exporter、NSQ Exporter、RabbitMQ Exporter 等 |
   | 存储     | Ceph Exporter、Gluster Exporter、HDFS Exporter、ScaleIO Exporter等 |
   | HTTP服务 | Apache Exporter、HAProxy Exporter、Nginx Exporter 等         |
   | API服务  | AWS ECS Exporter、Docker Cloud Exporter、Docker Hub Exporter、GitHub Exporter 等 |
   | 日志     | Fluentd Exporter、Grok Exporter 等                           |
   | 监控系统 | Collectd Exporter、Graphite Exporter、InfluxDB Exporter、Nagios Exporter 等 |
   | 其它     | Blockbox Exporter、JIRA Exporter、Jenkins Exporter、Confluence Exporter 等 |

   除了直接使用社区提供的 Exporter 程序外，用户还可以基于 Prometheus 提供的 Client Library 创建自己的 Exporter 程序，目前 Promthues 社区官方提供了对以下编程语言的支持：Go、Java/Scala、Python、Ruby。同时还有第三方实现的如：Bash、C++、Common Lisp、Erlang,、Haskeel、Lua、Node.js、PHP、Rust 等。

2. **Exporter 规范**

   所有的 Exporter 程序都需要按照 Prometheus 的规范，返回监控的样本数据。以 Node Exporter 为例，当访问 /metrics 地址时会返回以下内容：

   ```
   # HELP node_cpu Seconds the cpus spent in each mode.
   # TYPE node_cpu counter
   node_cpu{cpu="cpu0",mode="idle"} 362812.7890625
   # HELP node_load1 1m load average.
   # TYPE node_load1 gauge
   node_load1 3.0703125
   ```

   这是一种基于文本的格式规范，Exporter 返回的样本数据**主要由三个部分组成：样本的一般注释信息（HELP）、样本的类型注释信息（TYPE）和样本**。Prometheus 会对 Exporter 响应的内容逐行解析：

   * 如果**当前行以 # HELP 开始**，Prometheus 将会按照以下规则对内容进行解析，得到当前的指标名称以及相应的说明信息。

     ```
     # HELP <metrics_name> <doc_string>
     ```

   * 如果**当前行以 # TYPE 开始**，Prometheus 会按照以下规则对内容进行解析，得到当前的指标名称以及指标类型。TYPE 注释行必须出现在指标的第一个样本之前，如果没有明确的指标类型需返回 untyped。 

     ```
     # TYPE <metrics_name> <metrics_type>
     ```

   * **除了# 开头的所有行都会被视为监控样本数据**，每一行样本需要满足以下格式规范。其中 metric_name 和 label_name 必须遵循 PromQL 的格式规范；value 是一个 float 格式的数据；timestamp 的类型为 int64（从 1970-01-01 00:00:00 以来的毫秒数），可选默认为当前时间。具有相同 metric_name 的样本必须按照一个组的形式排列，并且每一行必须是唯一的指标名称和标签键值对组合。

     ```
     metric_name [
       "{" label_name "=" `"` label_value `"` { "," label_name "=" `"` label_value `"` } [ "," ] "}"
     ] value [ timestamp ]
     ```

   需要特别注意的是对于 histogram 和 summary 类型的样本，需要按照以下约定返回样本数据：

   - 类型为 summary 或 histogram 的指标 x，其所有样本的值的总和需要使用一个单独的 x_sum 指标表示。
   - 类型为 summary 或 histogram 的指标 x，其所有样本的总数需要使用一个单独的 x_count 指标表示。
   - 类型为 summary 的指标 x，其不同分位数 quantile 所代表的样本，需要使用单独的 x{quantile="y"} 表示。
   - 类型为 histogram 的指标 x，为了表示其样本的分布情况，每一个分布需要使用 x_bucket{le="y"} 表示，其中 y 为当前分布的上位数。同时必须包含一个样本 x_bucket{le="+Inf"}，并且其样本值必须和 x_count 相同。
   - 类型为 summary 和 histogram 的样本，必须按照分位数 quantile 和分布 le 的值递增排序。

   ```
   # A histogram, which has a pretty complex representation in the text format:
   # HELP http_request_duration_seconds A histogram of the request duration.
   # TYPE http_request_duration_seconds histogram
   http_request_duration_seconds_bucket{le="0.05"} 24054
   http_request_duration_seconds_bucket{le="0.1"} 33444
   http_request_duration_seconds_bucket{le="0.2"} 100392
   http_request_duration_seconds_bucket{le="+Inf"} 144320
   http_request_duration_seconds_sum 53423
   http_request_duration_seconds_count 144320
   
   # Finally a summary, which has a complex representation, too:
   # HELP rpc_duration_seconds A summary of the RPC duration in seconds.
   # TYPE rpc_duration_seconds summary
   rpc_duration_seconds{quantile="0.01"} 3102
   rpc_duration_seconds{quantile="0.05"} 3272
   rpc_duration_seconds{quantile="0.5"} 4773
   rpc_duration_seconds_sum 1.7560473e+07
   rpc_duration_seconds_count 2693
   ```



### 1.4.2 自定义 Exporter

1. **自定义 Collector**

   client_java 是 Prometheus 针对 JVM 类开发语言的 client library 库，在 client_java 的 simpleclient 模块中提供了自定义监控指标的核心接口。当无法直接修改监控目标时，可以通过自定义 Collector 的方式，实现对监控样本收集，该收集器需要实现 collect() 方法并返回一组监控样本。

   ```xml
   <dependency>
       <groupId>io.prometheus</groupId>
       <artifactId>simpleclient</artifactId>
       <version>0.16.0</version>
   </dependency>
   ```

   ```java
   public class YourCustomCollector extends Collector {
       public List<MetricFamilySamples> collect() {
           List<MetricFamilySamples> mfs = new ArrayList<>();
   				// 定义一个名为my_guage_1的监控指标
           String metricName = "my_guage_1";
   
           // Your code to get metrics
   
         	// 所有样本数据均转换为一个MetricFamilySamples.Sample实例，该实例中包含了样本的指标名称、标签名数组、标签值数组以及样本数据的值
           MetricFamilySamples.Sample sample = new MetricFamilySamples.Sample(metricName, Arrays.asList("l1"), Arrays.asList("v1"), 4);
           MetricFamilySamples.Sample sample2 = new MetricFamilySamples.Sample(metricName, Arrays.asList("l1", "l2"), Arrays.asList("v1", "v2"), 3);
   
         	// 监控指标my_guage_1的所有样本值，需要持久化到MetricFamilySamples实例中，它指定了当前监控指标的名称、类型、注释信息等。注意MetricFamilySamples中所有样本的名称必须保持一致，否则生成的数据将无法符合Prometheus规范
           MetricFamilySamples samples = new MetricFamilySamples(metricName, Type.GAUGE, "help", Arrays.asList(sample, sample2));
   
           mfs.add(samples);
           return mfs;
       }
   }
   ```

   直接使用 MetricFamilySamples.Sample 和 MetricFamilySamples 的方式适用于当某监控指标的样本之间的标签可能不一致的情况。而如果所有样本的是一致的情况下，我们还可以使用 client_java 针对不同指标类型的实现 GaugeMetricFamily，CounterMetricFamily，SummaryMetricFamily 等。

   ```java
   public class YourCustomCollector2 extends Collector {
       public List<MetricFamilySamples> collect() {
           List<MetricFamilySamples> mfs = new ArrayList<>();
   
           // With no labels.
           mfs.add(new GaugeMetricFamily("my_gauge_2", "help", 42));
   
           // With labels
           GaugeMetricFamily labeledGauge = new GaugeMetricFamily("my_other_gauge", "help", Arrays.asList("labelname"));
           labeledGauge.addMetric(Arrays.asList("foo"), 4);
           labeledGauge.addMetric(Arrays.asList("bar"), 5);
           mfs.add(labeledGauge);
   
           return mfs;
       }
   }
   ```

2. **使用 HTTP Server 暴露样本数据**

   client_java 下的 simpleclient_httpserver 模块实现了一个简单的 HTTP 服务器，当向该服务器发送获取样本数据的请求后，它会自动调用所有 Collector 的 collect() 方法，并将所有样本数据转换为 Prometheus 要求的数据输出格式规范。

   ```xml
   <dependency>
       <groupId>io.prometheus</groupId>
       <artifactId>simpleclient_httpserver</artifactId>
       <version>0.16.0</version>
   </dependency>
   ```

   ```java
   public class CustomExporter {
       public static void main(String[] args) throws IOException {
           new YourCustomCollector().register();
           new YourCustomCollector2().register();
         	// 内置的Collector
           // DefaultExports.initialize();
   
           new HTTPServer(1234);
       }
   }
   ```

   运行 CustomExporter 并访问 http://127.0.0.1:1234/metrics，即可获取到以下数据。其原理是：当调用 Collector 实例 register() 方法时，会将该实例保存到 CollectorRegistry 当中，CollectorRegistry 负责维护当前系统中所有的 Collector 实例。 HTTPServer 在接收到HTTP请求之后，会从 CollectorRegistry 中拿到所有的 Collector 实例，并调用其 collect() 方法获取所有样本，最后格式化为 Prometheus 的标准输出。

   ```
   $ curl http://127.0.0.1:1234/metrics
   # HELP my_gauge help
   # TYPE my_gauge gauge
   my_gauge 42.0
   # HELP my_other_gauge help
   # TYPE my_other_gauge gauge
   my_other_gauge{labelname="foo",} 4.0
   my_other_gauge{labelname="bar",} 5.0
   # HELP my_guage help
   # TYPE my_guage gauge
   my_guage{l1="v1",} 4.0
   my_guage{l1="v1",l2="v2",} 3.0
   ```

3. **使用内置的 Collector**

   除了提供接口规范外，client_java 还提供了多个内置的 Collector 模块，以 simpleclient_hotspot 为例，该模块中内置了对 JVM 虚拟机运行状态（GC，内存池，JMX，类加载，线程池等）数据的 Collector 实现。

   ```xml
   <dependency>
       <groupId>io.prometheus</groupId>
       <artifactId>simpleclient_hotspot</artifactId>
       <version>0.16.0</version>
   </dependency>
   ```

   ```java
   // 通过调用DefaultExport的initialize方法注册该模块中所有的Collector实例
   DefaultExports.initialize();
   ```

   重新运行 CustomExporter，除了之前自定义的监控指标外，响应内容中还包括当前 JVM 的运行状态数据。

   ```
   # HELP jvm_buffer_pool_used_bytes Used bytes of a given JVM buffer pool.
   # TYPE jvm_buffer_pool_used_bytes gauge
   jvm_buffer_pool_used_bytes{pool="direct",} 8192.0
   jvm_buffer_pool_used_bytes{pool="mapped",} 0.0
   ```

4. **简单类型 Gauge 和 Counter**

   在 client_java 中除了使用 Collector 直接采集样本数据以外，还直接提供了对 Prometheus 中 4 种监控类型的实现，分别是：Counter、Gauge、Summary 和。Histogram。 基于这些实现，开发人员可以非常方便的在应用程序的业务流程中进行监控埋点。以 Gauge 为例，监控某个业务当前正在处理的请求数量。

   ```java
   public class YourClass {
     	// Gauge继承自Collector，registoer()方法会将该Gauge实例注册到CollectorRegistry中。这里创建了一个名为inprogress_requests的监控指标，其注释信息为"Inprogress requests"，标签名为"method"
       static final Gauge inprogressRequests = Gauge.build()
               .name("inprogress_requests")
               .labelNames("method")
               .help("Inprogress requests.").register();
   
       void processRequest() {
         	// Gauge对象主要包含两个方法inc()和dec()，分别用于计数器+1和-1
           inprogressRequests.labels("get").inc();
           // Your code here.
           inprogressRequests.labels("get").dec();
       }
   }
   ```

5. **复杂类型 Summary 和 Histogram**

   Summary 和 Histogram 用于统计和分析样本的分布情况。如下所示，通过 Summary 可以将 HTTP 请求的字节数以及请求处理时间作为统计样本，直接统计其样本的分布情况。

   ```java
   public class SummaryDemo {
       static final Summary receivedBytes = Summary.build()
               .name("requests_size_bytes").help("Request size in bytes.").register();
       static final Summary requestLatency = Summary.build()
               .name("requests_latency_seconds").help("Request latency in seconds.").register();
   
       void processRequest(Request req) {
         	// 使用Timer进行计时
           Summary.Timer requestTimer = requestLatency.startTimer();
           try {
               // Your code here.
           } finally {
               receivedBytes.observe(req.size());
               requestTimer.observeDuration();
           }
       }
     
     	// 使用time()方法可以对线程或Lamda表达式运行时间进行统计
     	void processRequest2(Request req) {
           requestLatency.time(() -> {
               // Your code here.
           });
       }
   }
   ```

   Summary 和 Histogram 的用法基本保持一致，区别在于 Summary 可以指定在客户端统计的分位数。

   ```
   static final Summary requestLatency = Summary.build()
       .quantile(0.5, 0.05)   // 其中0.05为误差
       .quantile(0.9, 0.01)   // 其中0.01为误差
       .name("requests_latency_seconds").help("Request latency in seconds.").register();
   ```

   对于 Histogram 而言，默认的分布桶为 [.005, .01, .025, .05, .075, .1, .25, .5, .75, 1, 2.5, 5, 7.5, 10]，如果需要指定自定义的桶分布，可以使用 buckets() 方法指定，如下所示：

   ```java
    static final Histogram requestLatency = Histogram.build()
               .name("requests_latency_seconds").help("Request latency in seconds.")
               .buckets(0.1, 0.2, 0.4, 0.8)
               .register();
   ```

6. **与 PushGateway 集成**

   ```xml
   <dependency>
       <groupId>io.prometheus</groupId>
       <artifactId>simpleclient_pushgateway</artifactId>
       <version>0.16.0</version>
   </dependency>
   ```

   ```java
   public class PushGatewayIntegration {
       public void push() throws IOException {
         	// 从所有注册到defaultRegistry的Collector实例中获取样本数据，并直接推送到外部部署的PushGateway服务中
           CollectorRegistry registry = CollectorRegistry.defaultRegistry;
           PushGateway pg = new PushGateway("127.0.0.1:9091");
           pg.pushAdd(registry, "my_batch_job");
       }
   }
   ```



### 1.4.3 Exporter Demo

```java
@Component
public class PrometheusCollector {
    private static final Logger LOG = LoggerFactory.getLogger(PrometheusCollector.class);
    private static final String APPLICATION = "application";
    private static final String CUSTOM_APPLICATION = "custom-application";
    private static final String HOST = "host";
    private static final String TYPE = "type";
    private static final String QUEUE = "queue";
    private static final String MAP = "map";

    private static final int threadPoolSize = 2;

    private ConcurrentHashMap<String, Gauge> queueGaugeMap;
    private ConcurrentHashMap<String, Gauge> mapGaugeMap;

    private String host = "127.0.0.1";
    private PushGateway pushGateway;
    
    @Autowired
    private InitConfiguration initConfiguration;

    @PostConstruct
    public void init() {
        LOG.info("PrometheusCollector init");
        queueGaugeMap = new ConcurrentHashMap<>();
        mapGaugeMap = new ConcurrentHashMap<>();
        
        ScheduledExecutorService executorService = Executors.newScheduledThreadPool(threadPoolSize,
                (r) -> {
                    final Thread thread = new Thread(r);
                    thread.setDaemon(true);
                    thread.setName("custom application repoter");
                    return thread;
                });

        try {
            // 获取运行的服务器IP地址
            host = GetLocalHostUtils.getHostName();
        } catch (UnknownHostException e) {
            LOG.error("get host error", e);
        }

        // 获取自定义配置信息：prometheus IP、端口等
        String prometheusServerIp = initConfiguration.getPrometheusServerIp();
        Integer prometheusPort = initConfiguration.getPrometheusPort();
        Integer prometheusInitialDelay = initConfiguration.getPrometheusInitialDelay();
        Integer prometheusPeriod = initConfiguration.getPrometheusPeriod();
        String prometheusAddress = String.format("%s:%s", prometheusServerIp, prometheusPort);
        LOG.info("prometheus address is {}, prometheusInitialDelay = {}, prometheusPeriod = {}", prometheusAddress, prometheusInitialDelay, prometheusPeriod);
        pushGateway = new PushGateway(prometheusAddress);

        // 开启两个定时任务，定期向prometheus推送指标信息
        executorService.scheduleAtFixedRate(this::pushQueue, prometheusInitialDelay, prometheusPeriod, TimeUnit.SECONDS);
        executorService.scheduleAtFixedRate(this::pushMap, prometheusInitialDelay, prometheusPeriod, TimeUnit.SECONDS);
    }

    private void pushQueue() {
        // Statistic是一个自定义类，主要包括指标名、描述信息、指标的大小
        QueueLens.simple().forEach(statistic -> {
            Gauge gauge = queueGaugeMap.get(statistic.getIdentify());
            if (Objects.isNull(gauge)) {
                gauge = Gauge.build(statistic.getIdentify(), statistic.getDesc())
                        .labelNames(APPLICATION, HOST, TYPE).register();
                queueGaugeMap.put(statistic.getIdentify(), gauge);
            }
            gauge.labels(CUSTOM_APPLICATION, host, QUEUE).set(statistic.getSize());

            try {
                pushGateway.push(gauge, statistic.getIdentify());
            } catch (IOException e) {
                LOG.error("push queue {} to prometheus pushgateway error", statistic, e);
            }
        });
    }

    private void pushMap() {
        MapLens.simple().forEach(statistic -> {
            Gauge gauge = mapGaugeMap.get(statistic.getIdentify());
            if (Objects.isNull(gauge)) {
                gauge = Gauge.build(statistic.getIdentify(), statistic.getDesc())
                        .labelNames(APPLICATION, HOST, TYPE).register();
                mapGaugeMap.put(statistic.getIdentify(), gauge);
            }
            gauge.labels(CUSTOM_APPLICATION, host, MAP).set(statistic.getSize());

            try {
                pushGateway.push(gauge, statistic.getIdentify());
            } catch (IOException e) {
                LOG.error("push map {} to prometheus pushgateway error", statistic, e);
            }
        });
    }
}
```





# 2. Micrometer

Micrometer 为 Java 平台上的性能数据收集提供了一个通用的 API，**它提供了多种度量指标类型，同时支持接入不同的监控系统**，例如 Influxdb、Graphite、Prometheus 等。我们可以通过 Micrometer 收集 Java 性能数据，配合 Prometheus 监控系统实时获取数据，并最终在 Grafana 上展示出来，从而很容易实现应用的监控。

```xml
<!-- 核心依赖，包括核心的注册表，监控指标，默认提供的绑定配置（不确定接入哪种监控系统时使用） -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-core</artifactId>
    <version>1.10.2</version>
</dependency>

<!-- 适配第三方监控（prometheus）的依赖：用于将指标适配到第三方监控系统（包括了上述依赖） -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
    <version>1.10.2</version>
</dependency>
```



## 2.1 MeterRegistry

Meter 是指一组用于收集应用中度量数据的接口，具体类型包括：Timer、Counter、Gauge、TimeGauge、DistributionSummary、LongTaskTimer、FunctionCounter 和 FunctionTimer。**一个 Meter 具体类型需要通过名字和 Tag 作为它的唯一标识**，这样做的好处是可以使用名字进行标记，通过不同的 Tag 去区分多种维度进行数据统计。

Meter 由 MeterRegistry 创建和保存的，可以理解 MeterRegistry 是 Meter 的工厂和缓存中心，一般而言每个 JVM 应用在使用 Micrometer 的时候必须创建一个 MeterRegistry 的具体实现。MeterRegistry 在 Micrometer 是一个抽象类，主要实现包括：

- **SimpleMeterRegistry**：每个 Meter 的最新数据可以收集到 SimpleMeterRegistry 实例中，但是这些数据不会发布到其他系统，也就是**数据是位于应用的内存中的**。
- **CompositeMeterRegistry**：**多个 MeterRegistry 聚合**，内部维护了一个 MeterRegistry 列表。
- **全局的 MeterRegistry**：工厂类 io.micrometer.core.instrument.Metrics 中持有一个静态 final 的CompositeMeterRegistry 实例 globalRegistry。

当然，使用者也可以继承 MeterRegistry 去实现自定义的 MeterRegistry。SimpleMeterRegistry 适合做调试的时候使用，它的简单使用方式如下：

```java
MeterRegistry registry = new SimpleMeterRegistry();
Counter counter = registry.counter("counter");
counter.increment();
```

CompositeMeterRegistry 实例初始化时，内部持有的 MeterRegistry 列表是空的，如果此时用它新增一个 Meter 实例，Meter 实例的操作是无效的：

```java
CompositeMeterRegistry composite = new CompositeMeterRegistry();

Counter compositeCounter = composite.counter("counter");
compositeCounter.increment(); // 实际上这一步操作是无效的,但是不会报错

SimpleMeterRegistry simple = new SimpleMeterRegistry();
composite.add(simple);  // 向CompositeMeterRegistry实例中添加SimpleMeterRegistry实例

compositeCounter.increment();  // 计数成功
```

全局的 MeterRegistry 的使用方式更加简单便捷，因为一切只需要操作工厂类 Metrics 的静态方法：

```java
Metrics.addRegistry(new SimpleMeterRegistry());
Counter counter = Metrics.counter("counter", "tag-1", "tag-2");
counter.increment();
```



## 2.2 Meter 命名与 Tag

不同的监控系统对命名的规约可能并不相同，如果命名规约不一致，在做监控系统迁移或者切换的时候，可能会对新的系统造成破坏。**Micrometer 使用英文逗号分隔单词**，再通过底层的命名转换接口 NamingConvention 进行转换，最终可以适配不同的监控系统，同时可以消除监控系统不允许的特殊字符的名称和标记等。开发者也可以覆盖 NamingConvention 实现自定义的命名转换规则。

在 Micrometer 中，NamingConvention 已经提供了 5 种默认的转换规则：dot、snakeCase、camelCase、upperCamelCase 和 slashes，对一些主流的监控系统或存储系统的命名规则提供了默认的转换方式，例如当我们使用下面的命名时候：

```java
MeterRegistry registry = ...
registry.timer("http.server.requests");
```

对于不同的监控系统或者存储系统，命名会自动转换如下：

- Prometheus - http_server_requests_duration_seconds
- Atlas - httpServerRequests
- Graphite - http.server.requests
- InfluxDB - http_server_requests

另外，**Tag（标签）是 Micrometer 的一个重要的功能**，严格来说，一个度量框架只有实现了标签的功能，才能真正地多维度进行度量数据收集。Tag 的命名一般需要是有意义的，所谓有意义就是可以根据 Tag 的命名推断出它指向的数据到底代表什么维度或者什么类型的度量指标。假设我们需要监控数据库的调用和 Http 请求调用统计，一般推荐的做法是：

```java
MeterRegistry registry = ...
registry.counter("database.calls", "db", "users")
registry.counter("http.requests", "uri", "/api/users")
```

这样，当我们选择命名为"database.calls"的计数器，我们可以进一步选择分组"db"或者"users"分别统计不同分组对总调用数的贡献或者组成。可以定义全局的 Tag，也就是**全局的 Tag 定义之后，会附加到所有的使用到的 Meter 上（只要是使用同一个 MeterRegistry）**，全局的 Tag 可以这样定义：

```java
MeterRegistry registry = ...
registry.config().commonTags("stack", "prod", "region", "us-east-1");
// 和上面的意义是一样的
registry.config().commonTags(Arrays.asList(Tag.of("stack", "prod"), Tag.of("region", "us-east-1"))); 
```

像上面这样使用，就能通过主机，实例，区域，堆栈等操作环境进行多维度深入分析。还有两点需要注意：

- **Tag 的值必须不为 NULL**。
- **Tag 必须成对出现，实际它们以 Key=Value 的形式存在**，详见 io.micrometer.core.instrument.Tag 接口

当然，有时我们需要过滤一些必要的标签或名称进行统计，或者为 Meter 的名称添加白名单，此时可以使用 MeterFilter，它本身提供了一系列的静态方法，多个 MeterFilter 可以叠加或组成链实现用户最终的过滤策略。

```java
MeterRegistry registry = ...
// 表示忽略"http"标签，拒绝名称以"jvm"字符串开头的Meter，更多用法详见MeterFilter类
registry.config()
    .meterFilter(MeterFilter.ignoreTags("http"))
    .meterFilter(MeterFilter.denyNameStartsWith("jvm"));
```

Meter 的命名和 Meter 的 Tag 相互结合，以命名为轴心，以 Tag 为多维度要素，可以使度量数据的维度更加丰富，便于统计和分析。



## 2.3 Meters

1. **Counter（计数器）**：计数器记录单一计数指标，该 Counter 接口允许按固定数量递增，该数量必须为正数，可以用来统计无上限的数据。
2. **FunctionTimer（函数计时器）**：在函数编程中可以传递一个函数，在需要时调用函数进行获取数据。
3. **Timer（计时器）**：用于测量短时延迟和此类事件的频率。
4. **FunctionCounter（函数计数器）**：在函数编程中可以传递一个函数，在需要时调用函数进行获取数据。
5. **LongTaskTimer（长任务计时器）**：长任务计时器是一种特殊类型的计时器，可让您在正在测量的事件仍在运行时测量时间。一个普通的 Timer 只记录任务完成后的持续时间。
6. **Gauge（仪表盘）**：一般用来统计有上限可增可减的数据，仪表是获取当前值的句柄。仪表的典型示例是集合或映射的大小或处于运行状态的线程数。
7. **TimeGauge（跟踪时间值的专用量规）**：TimeGauge 是一个跟踪时间值的专用量规，可缩放到每个注册表实现所期望的基本时间单位。
8. **DistributionSummary（分布摘要跟踪事件的分布）**：它在结构上类似于定时器，但记录的是不代表时间单位的值。例如，您可以使用分布摘要来衡量到达服务器的请求的负载大小。

### 2.3.1 Counter

Counter 是一种比较简单的 Meter，它是一种单值的度量类型。Counter 接口允许使用者使用一个固定值（必须为正数）进行计数，准确来说，**Counter 就是一个增量为正数的单值计数器**。

```java
MeterRegistry meterRegistry = new SimpleMeterRegistry();
Counter counter = meterRegistry.counter("http.request", "createOrder", "/order/create");
counter.increment();
System.out.println(counter.measure()); // [Measurement{statistic='COUNT', value=1.0}]
```

使用场景：Counter 的作用是记录总量或者计数值，适用于一些增长类型的统计，例如下单、支付次数、HTTP 请求总量记录等等，通过 Tag 可以区分不同的场景，对于下单，可以使用不同的 Tag 标记不同的业务来源或者是按日期划分。

```java
@Data
class Order {
    private String orderId;
    private Integer amount;
    private String channel;
    private LocalDateTime createTime;
}


public class CounterMain {
    private static final DateTimeFormatter FORMATTER = DateTimeFormatter.ofPattern("yyyy-MM-dd");

    static {
        Metrics.addRegistry(new SimpleMeterRegistry());
    }

    public static void main(String[] args) throws Exception {
        Order order1 = new Order();
        order1.setOrderId("ORDER_ID_1");
        order1.setAmount(100);
        order1.setChannel("CHANNEL_A");
        order1.setCreateTime(LocalDateTime.now());
        createOrder(order1);
      
        Order order2 = new Order();
        order2.setOrderId("ORDER_ID_2");order2.setAmount(200);
        order2.setChannel("CHANNEL_B");
        order2.setCreateTime(LocalDateTime.now());
        createOrder(order2);
      
        Search.in(Metrics.globalRegistry).meters().forEach(each -> {
            StringBuilder builder = new StringBuilder();
            builder.append("name:")
                    .append(each.getId().getName())
                    .append(",tags:")
                    .append(each.getId().getTags())
                    .append(",type:").append(each.getId().getType())
                    .append(",value:").append(each.measure());
            System.out.println(builder.toString());
        });
    }

    private static void createOrder(Order order) {
        Metrics.counter("order.create",
                "channel", order.getChannel(),
                "createTime", FORMATTER.format(order.getCreateTime())).increment();
    }
}
```

```java
name:order.create,tags:[tag(channel=CHANNEL_A), tag(createTime=2018-11-10)],type:COUNTER,value:[Measurement{statistic='COUNT', value=1.0}]
name:order.create,tags:[tag(channel=CHANNEL_B), tag(createTime=2018-11-10)],type:COUNTER,value:[Measurement{statistic='COUNT', value=1.0}]
```

上面的例子是使用全局静态方法工厂类 Metrics 去构造 Counter 实例，实际上，Counter 接口提供了一个内部建造器类 Counter.Builder 去实例化 Counter ，使用方式如下：

```java
Counter counter = Counter.builder("name")  // 名称
    .baseUnit("unit") // 基础单位
    .description("desc") // 描述
    .tag("tagKey", "tagValue")  // 标签
    .register(new SimpleMeterRegistry());	// 绑定的MeterRegistry
counter.increment();
```



### 2.3.2 FunctionCounter

FunctionCounter 是 Counter 的特化类型，**它把计数器数值增加的动作抽象成接口类型 ToDoubleFunction**，这个接口是 JDK1.8 中 Function 的特化类型接口。FunctionCounter 的使用场景和 Counter 是一致的，这里介绍一下它的用法。

```java
public class FunctionCounterMain {
    public static void main(String[] args) throws Exception {
        MeterRegistry registry = new SimpleMeterRegistry();
        AtomicInteger n = new AtomicInteger(0);
        // 这里ToDoubleFunction匿名实现其实可以使用Lambda表达式简化为AtomicInteger::get
        FunctionCounter.builder("functionCounter", n, new ToDoubleFunction<AtomicInteger>() {
                    @Override
                    public double applyAsDouble(AtomicInteger value) {
                        return value.get();
                    }
                }).baseUnit("function")
                .description("functionCounter")
                .tag("createOrder", "CHANNEL-A")
                .register(registry);
        // 模拟三次计数		
        n.incrementAndGet();
        n.incrementAndGet();
        n.incrementAndGet();
    }
}
```

FunctionCounter 使用的一个明显的好处是，我们不需要感知 FunctionCounter 实例的存在，实际上我们只需要操作 FunctionCounter 实例构建元素之一的 AtomicInteger 实例即可，这种接口的设计方式在很多主流框架里面可以看到。



### 2.3.3 Timer

**Timer（计时器）适用于记录耗时比较短的事件的执行时间，通过时间分布展示事件的序列和发生频率**。所有的Timer 的实现至少记录了发生事件的数量和这些事件的总耗时，从而生成一个时间序列。Timer 的基本单位基于服务端的指标而定，但实际上我们不需要过于关注 Timer 的基本单位，因为 Micrometer 在存储生成的时间序列的时候会自动选择适当的基本单位。

```java
// 比较常用和方便的方法是几个函数式接口入参的方法
Timer timer = ...
timer.record(() -> dontCareAboutReturnValue());
timer.recordCallable(() -> returnValue());

Runnable r = timer.wrap(() -> dontCareAboutReturnValue());
Callable c = timer.wrap(() -> returnValue());
```

使用场景：**记录指定方法的执行时间用于展示，或记录一些任务的执行时间，从而确定某些数据来源的速率**，例如消息队列消息的消费速率等。这里用下单方法做例子，记录该方法的执行时间：

```java
public class TimerMain {
    private static final Random R = new Random();

    static {
        Metrics.addRegistry(new SimpleMeterRegistry());
    }

    public static void main(String[] args) throws Exception {
        Order order1 = new Order();
        order1.setOrderId("ORDER_ID_1");
        order1.setAmount(100);
        order1.setChannel("CHANNEL_A");
        order1.setCreateTime(LocalDateTime.now());
        Timer timer = Metrics.timer("timer", "createOrder", "cost");
        timer.record(() -> createOrder(order1));
    }

    private static void createOrder(Order order) {
        try {
            TimeUnit.SECONDS.sleep(R.nextInt(5)); // 模拟方法耗时
        } catch (InterruptedException e) {
            // no-op
        }
    }
}
```

在实际生产环境中，可以通过 spring-aop 把记录方法耗时的逻辑抽象到一个切面中，这样就能减少不必要的冗余的模板代码。上面的例子是通过 Mertics 构造 Timer 实例，实际上也可以使用 Builder 构造：

```java
MeterRegistry registry = ...
Timer timer = Timer
    .builder("my.timer")
    .description("a description of what this timer does") // 可选
    .tags("region", "test") // 可选
    .register(registry);
```

另外，Timer 的使用还可以基于它的内部类 Timer.Sample，通过 start 和 stop 两个方法记录两者之间的逻辑的执行耗时。例如：

```java
Timer.Sample sample = Timer.start(registry);

// 这里做业务逻辑
Response response = ...

sample.stop(registry.timer("my.timer", "response", response.status()));
```



### 2.3.4 FunctionTimer

FunctionTimer 是 Timer 的特化类型，它主要提供两个单调递增的函数（其实并不是单调递增，只是在使用中一般需要随着时间最少保持不变或者说不减少）：**一个用于计数的函数和一个用于记录总调用耗时的函数**，它的建造器的入参如下：

```java
public interface FunctionTimer extends Meter {
    static <T> Builder<T> builder(String name, T obj, ToLongFunction<T> countFunction,
                                  ToDoubleFunction<T> totalTimeFunction,
                                  TimeUnit totalTimeFunctionUnit) {
        return new Builder<>(name, obj, countFunction, totalTimeFunction, totalTimeFunctionUnit);
    }
	...
}	
```

其中，countFunction 用于统计事件个数，totalTimeFunction 用于记录执行总时间，实际上两个函数都只是 Function 函数的变体，还有一个比较重要的是总时间的单位 totalTimeFunctionUnit。简单使用方式如下：

```java
public class FunctionTimerMain {
    public static void main(String[] args) throws Exception {
        // 这个是为了满足参数,暂时不需要理会
        Object holder = new Object();
        AtomicLong totalTimeNanos = new AtomicLong(0);
        AtomicLong totalCount = new AtomicLong(0);
        FunctionTimer.builder("functionTimer", holder, p -> totalCount.get(),
                        p -> totalTimeNanos.get(), TimeUnit.NANOSECONDS)
                .register(new SimpleMeterRegistry());
        totalTimeNanos.addAndGet(10000000);
        totalCount.incrementAndGet();
    }
}
```



### 2.3.5 LongTaskTimer

LongTaskTimer 是 Timer 的特化类型，**主要用于记录长时间执行的任务的持续时间**，在任务完成之前，被监测的事件或者任务仍然处于运行状态，任务完成时，任务执行的总耗时才会被记录下来，例如相对耗时的定时任务。在 SpringBoot 应用中，可以简单地使用 @Scheduled和 @Timed 注解，基于 spring-aop 完成定时调度任务的总耗时记录：

```java
@Timed(value = "aws.scrape", longTask = true)
@Scheduled(fixedDelay = 360000)
void scrapeResources() {
    // 这里做相对耗时的业务逻辑
}
```

当然，在非 Spring 体系中也能方便地使用 LongTaskTimer。

```java
public class LongTaskTimerMain {
    public static void main(String[] args) throws Exception{
        MeterRegistry meterRegistry = new SimpleMeterRegistry();
        LongTaskTimer longTaskTimer = meterRegistry.more().longTaskTimer("longTaskTimer");
        longTaskTimer.record(() -> {
             // 这里编写Task的逻辑
        });
        // 或者这样
        Metrics.more().longTaskTimer("longTaskTimer").record(()-> {
             // 这里编写Task的逻辑
        });
    }
}
```



### 2.3.6 Guage

Gauge 的典型使用场景是**用于测量集合/映射的大小或运行状态中的线程数**。一般情况下，Gauge 适合用于监测有自然上界的事件或者任务，而 Counter 一般使用于无自然上界的事件或者任务的监测，所以像 HTTP 请求总量计数应该使用 Counter 而非 Gauge。MeterRegistry 中提供了一些便于构建用于观察数值、函数、集合和映射的 Gauge 相关的方法：

```java
List<String> list = registry.gauge("listGauge", Collections.emptyList(), new ArrayList<>(), List::size); 
List<String> list2 = registry.gaugeCollectionSize("listSize2", Tags.empty(), new ArrayList<>()); 
Map<String, Integer> map = registry.gaugeMapSize("mapGauge", Tags.empty(), new HashMap<>());
```

上面的三个方法通过 MeterRegistry 构建 Gauge 并且返回了集合或者映射实例，**使用这些集合或者映射实例就能在其 size 变化过程中记录这个变更值**。更重要的是，我们不需要感知 Gauge 接口的存在，只需要像平时一样使用集合或映射实例。此外，Gauge 还支持 java.lang.Number 的子类，java.util.concurrent.atomic 包中的 AtomicInteger 和 AtomicLong，还有 Guava 提供的 AtomicDouble：

```java
AtomicInteger n = registry.gauge("numberGauge", new AtomicInteger(0));
n.set(1);
n.set(2);
```

除了使用 MeterRegistry 创建 Gauge 之外，还可以使用建造器流式创建：

```java
// 一般我们不需要操作Gauge实例
Gauge gauge = Gauge
    .builder("gauge", myObj, myObj::gaugeValue)
    .description("a description of what this gauge does") // 可选
    .tags("region", "test") // 可选
    .register(registry);
```



### 2.3.7 TimeGuage

TimeGauge 是 Gauge 的特化类型，相比 Gauge，它的构建器中多了一个 TimeUnit 类型参数，用于指定ToDoubleFunction 入参的基础时间单位。

```java
public class TimeGaugeMain {
    private static final SimpleMeterRegistry R = new SimpleMeterRegistry();

    public static void main(String[] args) throws Exception {
        AtomicInteger count = new AtomicInteger();
        TimeGauge.Builder<AtomicInteger> timeGauge = TimeGauge.builder("timeGauge", count,
                TimeUnit.SECONDS, AtomicInteger::get);
        timeGauge.register(R);
        count.addAndGet(10086);
        print();
        count.set(1);
        print();
    }

    private static void print() throws Exception {
        Search.in(R).meters().forEach(each -> {
            StringBuilder builder = new StringBuilder();
            builder.append("name:")
                    .append(each.getId().getName())
                    .append(",tags:")
                    .append(each.getId().getTags())
                    .append(",type:").append(each.getId().getType())
                    .append(",value:").append(each.measure());
            System.out.println(builder.toString());
        });
    }
}
```

```
name:timeGauge,tags:[],type:GAUGE,value:[Measurement{statistic='VALUE', value=10086.0}]
name:timeGauge,tags:[],type:GAUGE,value:[Measurement{statistic='VALUE', value=1.0}]
```



### 2.3.8 DistributionSummary

Summary 主要用于跟踪事件的分布，在 Micrometer 中，对应的类是 DistributionSummary。它的使用方式和 Timer 十分相似，但是它的记录值并不依赖于时间单位。常见的使用场景：测量命中服务器请求的有效负载大小。

```java
// 使用MeterRegistry创建DistributionSummary实例
DistributionSummary summary = registry.summary("response.size");

// 通过建造器流式创建如下
DistributionSummary summary = DistributionSummary
    .builder("response.size")
    .description("a description of what this summary does") // 可选
    .baseUnit("bytes") // 可选
    .tags("region", "test") // 可选
    .scale(100) // 可选
    .register(registry);
```

```java
public class DistributionSummaryMain {
    private static final DistributionSummary DS = DistributionSummary.builder("cacheHitPercent").register(new SimpleMeterRegistry());

    private static final LoadingCache<String, String> CACHE = CacheBuilder.newBuilder()
            .maximumSize(1000)
            .recordStats()
            .expireAfterWrite(60, TimeUnit.SECONDS)
            .build(new CacheLoader<String, String>() {
                @Override
                public String load(String s) throws Exception {
                     return selectFromDatabase();
                }
            });

    public static void main(String[] args) throws Exception {
        String key = "doge";
        String value = CACHE.get(key);
        record();
    }

    private static void record() throws Exception {
        CacheStats stats = CACHE.stats();
        BigDecimal hitCount = new BigDecimal(stats.hitCount());
        BigDecimal requestCount = new BigDecimal(stats.requestCount());
        DS.record(hitCount.divide(requestCount, 2, BigDecimal.ROUND_HALF_DOWN).doubleValue());
    }
}
```



# 3. OGNL

OGNL 是 Object-Graph Navigation Language（对象导航图语言）的缩写，它是一种功能强大的表达式语言，通过它简单一致的表达式语法，可以存取对象的任意属性，调用对象的方法，遍历整个对象的结构图，实现字段类型转化等功能。它使用相同的表达式去存取对象的属性，这样可以更好的取得数据。**通过 OGNL 可以比较方便地获取指标数据，避免在业务代码中埋点**。

```xml
<dependency>
    <groupId>ognl</groupId>
    <artifactId>ognl</artifactId>
    <version>3.1.19</version>
</dependency>
```



## 3.1 三要素

1. **表达式（Expression）**：表达式是整个 OGNL 的核心内容，所有的 OGNL 操作都是针对表达式解析后进行的。通过表达式来告诉 OGNL 操作到底要干些什么。因此，表达式其实是一个带有语法含义的字符串，整个字符串将规定操作的类型和内容。OGNL 表达式支持大量的表达式，如“链式访问对象”、表达式计算、甚至还支持 Lambda 表达式。
2. **Root 对象**：OGNL 的 Root 对象可以理解为 OGNL 的操作对象。当我们指定了一个表达式的时候，我们需要指定这个表达式针对的是哪个具体的对象。而这个具体的对象就是 Root 对象，这就意味着，如果有一个 OGNL 表达式，那么我们需要针对 Root 对象来进行 OGNL 表达式的计算并且返回结果。
3. **上下文环境**：有个 Root 对象和表达式，我们就可以使用 OGNL 进行简单的操作了，如对 Root 对象的赋值与取值操作。但是，实际上在 OGNL 的内部，所有的操作都会在一个特定的数据环境中运行。这个数据环境就是上下文环境（Context）。**OGNL 的上下文环境是一个 Map 结构，称之为 OgnlContext**，它实现了 java.utils.Map 的接口，Root 对象也会被添加到上下文环境当中去。



## 3.2 基本语法

```java
@Data
public class Address {
    private String port;
    private String address;
	
    public Address(String port, String address) {
        this.port = port;
        this.address = address;
    }
}
```

```java
@Data
public class User {
    private String name;
    private int age;
    private Address address;

    public User() {
    }

    public User(String name, int age) {
        this.name = name;
        this.age = age;
    }
}
```



### 3.2.1 访问 Root 对象

OGNL 使用的是一种链式的风格进行对象的访问。

```java
@Test
public void test1() throws OgnlException {
    User user = new User("test", 23);
    Address address = new Address("330108", "杭州市滨江区");
    user.setAddress(address);
    System.out.println(Ognl.getValue("name", user));	// test
    System.out.println(Ognl.getValue("name.length", user));	// 4
    System.out.println(Ognl.getValue("address", user));	// Address(port=330108, address=杭州市滨江区)
    System.out.println(Ognl.getValue("address.port", user));	// 330108
}
```



### 3.2.2 访问上下文对象

使用 OGNL 时如果不设置上下文对象，系统会自动创建一个上下文对象，如果传入的参数当中包含了上下文对象则会使用传入的上下文对象。**当访问上下文环境中的参数时，需要在表达式前面加上 '#' ，表示了与访问 Root 对象的区别**。

```java
@Test
public void test2() throws OgnlException {
    User user = new User("test", 23);
    Address address = new Address("330108", "杭州市");
    user.setAddress(address);
    Map<String, Object> context = new HashMap<>();
    context.put("init", "hello");
    context.put("user", user);
    System.out.println(Ognl.getValue("#init", context, user));    // hello
    System.out.println(Ognl.getValue("#user.name", context, user));    // test
    System.out.println(Ognl.getValue("name", context, user));    // test
}
```



### 3.2.3 访问静态变量

在 OGNL 表达式当中也可以访问静态变量或者调用静态方法，格式如 **@[class]@[field/method ()]**。

```java
public static String ONE = "one";

public static String demo() {
    return "abc";
}

@Test
public void test3() throws OgnlException {
    Object object1 = Ognl.getValue("@com.example.maomao.OgnlTest@ONE", null);
    Object object2 = Ognl.getValue("@com.example.maomao.OgnlTest@demo()", null);
    System.out.println(object1);    // one
    System.out.println(object2);    // abc
}
```



### 3.2.4 调用方法

如果需要调用 Root 对象或上下文对象当中的方法，可以**使用 .+ 方法的方式**，甚至可以传入参数。赋值的时候可以选择上下文当中的元素给 Root 对象的属性赋值。

```java
@Test
public void test4() throws OgnlException {
    User user = new User();
    Map<String, Object> context = new HashMap<>();
    context.put("name", "maomao");
    context.put("password", "password");
    System.out.println(Ognl.getValue("getName()", context, user));    // null
    Ognl.getValue("setName(#name)", context, user);
    System.out.println(Ognl.getValue("getName()", context, user));    // maomao
}
```



### 3.2.5 访问数组和集合

OGNL 支持对数组按照数组下标的顺序进行访问。此方式也适用于对集合的访问，对于 Map 支持使用键进行访问。

```java
@Test
public void test5() throws OgnlException {
    User user = new User();
    Map<String, Object> context = new HashMap<>();

    String[] strings = {"aa", "bb"};
    List<String> list = new ArrayList<>();
    list.add("aa");
    list.add("bb");
    Map<String, String> map = new HashMap<>();
    map.put("key1", "value1");
    map.put("key2", "value2");

    context.put("list", list);
    context.put("strings", strings);
    context.put("map", map);

    System.out.println(Ognl.getValue("#strings[0]", context, user));	// aa
    System.out.println(Ognl.getValue("#list[0]", context, user));			// aa
    System.out.println(Ognl.getValue("#list[0 + 1]", context, user));    // bb
    System.out.println(Ognl.getValue("#map['key1']", context, user));    // value1
    System.out.println(Ognl.getValue("#map['key' + '2']", context, user));    // value2
}
```



### 3.2.6 投影与选择

* **投影**：选出集合当中的相同属性组合成一个新的集合。**语法为 collection.{XXX}，XXX 就是集合中每个元素的公共属性**。
* **选择**：选择就是选择出集合当中符合条件的元素组合成新的集合。**语法为 collection.{Y XXX}，其中 Y 是一个选择操作符，XXX 是选择用的逻辑表达式**。选择操作符如下有 3 种：
  * ? ：选择满足条件的所有元素
  * ^：选择满足条件的第一个元素
  * $：选择满足条件的最后一个元素

```java
@Test
public void test6() throws OgnlException {
    User p1 = new User("name1", 11);
    User p2 = new User("name2", 22);
    User p3 = new User("name3", 33);
    User p4 = new User("name4", 44);
    Map<String, Object> context = new HashMap<String, Object>();
    ArrayList<User> list = new ArrayList<User>();
    list.add(p1);
    list.add(p2);
    list.add(p3);
    list.add(p4);
    context.put("list", list);
    System.out.println(Ognl.getValue("#list.{age}", context, list));    // [11, 22, 33, 44]
    System.out.println(Ognl.getValue("#list.{age + '-' + name}", context, list));   // [11-name1, 22-name2, 33-name3, 44-name4]
    System.out.println(Ognl.getValue("#list.{? #this.age > 22}", context, list));   // [User(name=name3, age=33, address=null), User(name=name4, age=44, address=null)]
    System.out.println(Ognl.getValue("#list.{^ #this.age > 22}", context, list));   // [User(name=name3, age=33, address=null)]
    System.out.println(Ognl.getValue("#list.{$ #this.age > 22}", context, list));   // [User(name=name4, age=44, address=null)]
}
```



### 3.2.7 创建对象

OGNL 支持直接使用表达式来创建对象。主要有三种情况：

- **构造 List 对象**：使用 {}, 中间使用 ',' 进行分割如 {"aa", "bb", "cc"}
- **构造 Map 对象**：使用 #{}，中间使用 ', 进行分割键值对，键值对使用 ':' 区分，如 #{"key1" : "value1", "key2" : "value2"}
- **构造任意对象**：直接使用已知的对象的构造方法进行构造。可以使用链式语句给对象属性进行赋值，定义规则如下：**圆括号包裹起来，中间用逗号分隔，依次执行，最后一个为需要返回的目标**，即`(step1, step2,..., result)`

```java
@Test
public void test7() throws OgnlException {
    System.out.println(Ognl.getValue("{'key1','value1'}", null));    // [key1, value1]
    System.out.println(Ognl.getValue("#{'key1':'value1'}", null));    // {key1=value1}
    System.out.println(Ognl.getValue("new com.example.maomao.User()", null));  // User(name=null, age=0, address=null)
    System.out.println(Ognl.getValue("(#demo=new com.example.maomao.User(), #demo.setName(\"maomao\"), #demo.setAge(18), #demo)", null));   // User(name=maomao, age=18, address=null)
}
```



## 3.3 Ognl Demo

对于 Ognl 的使用，关键的地方在于获取 OgnlContext，在这个上下文中保存一些实例用来支撑 ognl 的语法。所以一般使用 ognl 的先前操作就是创建 OgnlContext，然后将我们的实例扔到上下文中，接收 ognl 表达式，最后执行并获取结果。

```java
// 构建一个OgnlContext对象，true表示可访问Private、Protected、PackageProtected，详见源码
OgnlContext context = (OgnlContext) Ognl.createDefaultContext(this, 
        new DefaultClassResolver(), 
        new DefaultTypeConverter(),
        new DefaultMemberAccess(true));


// 设置根节点，以及初始化一些实例对象
context.setRoot(this);
context.put("实例名", obj);
...


// ognl表达式执行
Object expression = Ognl.parseExpression("#a.name")
Object result = Ognl.getValue(expression, context, context.getRoot());
```





# 参考

1. [prometheus-book](https://yunlzheng.gitbook.io/prometheus-book/)
2. [Micrometer官方文档](https://micrometer.io/docs)
3. [3W字干货深入分析基于Micrometer和Prometheus实现度量和监控的方案](https://www.cnblogs.com/throwable/p/13257557.html)
3. [b站 - Prometheus+Grafana+睿象云的监控告警系统](https://www.bilibili.com/video/BV1HT4y1Z7vR/?vd_source=03ee00a529e3c4f9c2d8c6f412586123)
3. [OGNL 官网](https://commons.apache.org/proper/commons-ognl/language-guide.html)
3. [Ognl 表达式的基本使用方法](https://jueee.github.io/2020/08/2020-08-15-Ognl%E8%A1%A8%E8%BE%BE%E5%BC%8F%E7%9A%84%E5%9F%BA%E6%9C%AC%E4%BD%BF%E7%94%A8%E6%96%B9%E6%B3%95/)
3. [Ognl 使用实例手册](https://juejin.cn/post/6844904013859651597)

