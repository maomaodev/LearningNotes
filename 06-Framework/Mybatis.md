## 1. MyBatis 核心组件

MyBatis 核心组件分为 4 个部分：

* `SqlSessionFactoryBuilder`：构造器，它会根据配置或者代码来生成 `SqlSessionFactory`，采用的是分步构建的 Builder 模式
* `SqlSessionFactory`：工厂接口，使用工厂模式来生成 `SqlSession`
* `SqlSession`：会话，一个既可以发送 SQL 执行返回结果，也可以获取 `Mapper` 的接口
* `SQL Mapper`：映射器，它由一个 java 接口和 XML 文件（或注解）组成，需要给出对应的 SQL 和映射规则，负责发送 SQL 去执行，并返回结果



