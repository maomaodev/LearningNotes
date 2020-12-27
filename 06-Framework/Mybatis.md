## 1. MyBatis 入门

### 1.1 简介

MyBatis 是一个优秀的基于 Java 的**持久层框架，它内部封装了 JDBC，使开发者只需要关注 SQL 语句本身**，而不需要花费精力去处理加载驱动、创建连接等繁杂的过程。MyBatis 的优势在于：

* **不屏蔽 SQL**，可以更为精确地定位 SQL 语句，对其进行优化和改造，提高系统性能；
* 提供强大、灵活的 **ORM 映射机制**，ORM 全称 Object Relational Mapping（对象关系映射），就是把数据库表和实体类对应起来，让我们可以通过操作实体类来操作数据库表；
* 提供**动态 SQL** 的功能，允许我们根据不同条件组装 SQL；
* 提供了使用 Mapper 的**接口编程**，只要一个接口和一个 XML 就能创建映射器，开发者能更集中于业务逻辑



### 1.2 快速开始

1. **创建数据库**

   ```sql
   -- 创建数据库
   CREATE DATABASE IF NOT EXISTS mybatis CHARACTER SET utf8;
   
   -- 创建数据表
   DROP TABLE IF EXISTS `user`;
   CREATE TABLE `user` (
       `user_id` int(11) NOT NULL auto_increment,
       `user_name` varchar(32) NOT NULL COMMENT '名称',
       `user_sex` char(1) default NULL COMMENT '性别',
       PRIMARY KEY (`user_id`)
   ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
   
   -- 添加记录
   insert into `user`(`user_id`, `user_name`, `user_sex`) values 
   (1,'张三','男'), (2,'李四','女'), (3,'王五','女'), (4,'赵六','男'), (5,'张三丰','男');
   ```

2. **添加依赖**

   ```xml
   <dependencies>
       <dependency>
           <groupId>org.mybatis</groupId>
           <artifactId>mybatis</artifactId>
           <version>3.4.5</version>
       </dependency>
       <dependency>
           <groupId>mysql</groupId>
           <artifactId>mysql-connector-java</artifactId>
           <version>5.1.6</version>
       </dependency>
       <dependency>
           <groupId>log4j</groupId>
           <artifactId>log4j</artifactId>
           <version>1.2.12</version>
       </dependency>
       <dependency>
           <groupId>junit</groupId>
           <artifactId>junit</artifactId>
           <version>4.10</version>
           <scope>test</scope>
       </dependency>
       <dependency>
           <groupId>org.projectlombok</groupId>
           <artifactId>lombok</artifactId>
           <version>1.18.10</version>
           <scope>provided</scope>
       </dependency>
   </dependencies>
   ```

3. **创建实体类 User**

   ```java
   @Data
   public class User implements Serializable {
       private Integer userId;
       private String userName;
       private String userSex;
   }
   ```

4. **创建持久层接口 IUserDao**

   注意，Mybatis 中持久层的操作接口和映射文件也叫做 Mapper，所以 **IUserDao 和 IUserMapper 是一样的**

   ```java
   public interface IUserDao {
       // 查询所有操作
       List<User> queryAll();
   }
   ```

5. **创建主配置文件 SqlMapConfig.xml**

   ```xml
   <?xml version="1.0" encoding="utf-8" ?>
   <!DOCTYPE configuration
           PUBLIC "-//mybatis.org//DTD config 3.0//EN"
           "http://mybatis.org/dtd/mybatis-3-config.dtd">
   
   <!-- mybatis主配置文件 -->
   <configuration>
       <!-- 配置环境 -->
       <environments default="mysql">
           <!-- 配置mysql环境 -->
           <environment id="mysql">
               <!-- 配置事务的类型 -->
               <transactionManager type="JDBC"/>
               <!-- 配置数据源（连接池） -->
               <dataSource type="POOLED">
                   <!-- 配置数据库的4个基本信息 -->
                   <property name="driver" value="com.mysql.jdbc.Driver"/>
                   <property name="url" value="jdbc:mysql://localhost:3306/mybatis?useUnicode=true&amp;characterEncoding=UTF-8"/>
                   <property name="username" value="root"/>
                   <property name="password" value="root"/>
               </dataSource>
           </environment>
       </environments>
   
       <!-- 指定映射配置文件的位置，映射配置文件指的是每个dao独立的配置文件 -->
       <mappers>
           <mapper resource="dao/IUserDao.xml"/>
       </mappers>
   </configuration>
   ```

6. **创建映射配置文件 IUserDao.xml**

   注意，**映射配置文件的位置建议和 dao 接口的包结构相同**，由于 IUserDao 位于 dao 包下，所以我们首先在 resources 下新建一个 dao 目录，然后在 dao 目录下新建该映射配置文件

   ```xml
   <?xml version="1.0" encoding="utf-8" ?>
   <!DOCTYPE mapper
           PUBLIC "-//mybatis.org//DTD config 3.0//EN"
           "http://mybatis.org/dtd/mybatis-3-mapper.dtd">
   
   <!-- 映射配置文件mapper标签的namespace属性的取值必须是dao接口的全限定类名 -->
   <mapper namespace="dao.IUserDao">
   
       <!-- 配置实体类的属性名与数据库的列名的对应关系，type的取值必须是实体类的全限定类名 -->
       <resultMap id="userMap" type="domain.User">
           <!-- 主键字段的对应，使用id标签-->
           <id property="userId" column="user_id"/>
           <!-- 非主键字段的对应，使用result标签 -->
           <result property="userName" column="user_name"/>
           <result property="userSex" column="user_sex"/>
       </resultMap>
   
       <!-- 映射配置文件的操作配置select标签的id属性的取值必须是dao接口的方法名 -->
       <!-- 查询时结果需要封装成对象，所以需要将对象的属性与数据库的列名对应，有3种方法 -->
       <!-- 方式2指定：resultType="domain.User"  方式3指定：resultMap="userMap"-->
       <select id="queryAll" resultType="domain.User">
           <!--方法1：实体类属性名与数据库列名保持一致，效率高，但违背数据库或Java的命名规范-->
           <!--方法2：查询数据库时取别名的方式，效率高，但是开发慢（sql语句变复杂）-->
           <!-- select user_id as userId, user_name as userName, user_sex as userSex from user -->
           <!-- 方法3：配置实体类属性名与数据库列名的对应关系，效率低（多解析一个XML），但是开发快-->
           select * from user;
       </select>
   </mapper>
   ```

7. **测试**

   ```java
   public class QueryTest {
       private InputStream in;
       private SqlSession sqlSession;
       private IUserDao userDao;
   
       @Before // 在测试方法之前执行
       public void init() throws Exception {
           // 1.读取配置文件
           // 使用相对路径（src目录运行时可能删除）、绝对路径（可能没有D盘）都不常用
           // 第一个：使用类加载器，它只能读取类路径的配置文件
           // 第二个：使用ServletContext对象的getRealPath()
           in = Resources.getResourceAsStream("SqlMapConfig.xml");
   
           // 2.创建SqlSessionFactory工厂
           // 创建工厂使用了构建者模式：把对象的创建细节隐藏，使用者直接调用方法即可拿到对象
           SqlSessionFactoryBuilder builder = new SqlSessionFactoryBuilder();
           SqlSessionFactory factory = builder.build(in);
   
           // 3.使用工厂创建SqlSession对象
           // 生产SqISession使用了工厂模式：解耦，降低类之间的依赖关系
           sqlSession = factory.openSession();
           // 如果设置参数，则可以自动提交事务，无须手动调用sqlSession.commit()
   		// sqlSession = factory.openSession(true);
   
           // 4.使用SqlSession创建Dao接口的代理对象
           // 创建dao接口实现类使用了代理模式：不修改源码的基础上对已有方法增强
           userDao = sqlSession.getMapper(IUserDao.class);
       }
   
       @After  // 在测试方法之后执行
       public void destroy() throws Exception {
           // 6.释放资源
           sqlSession.close();
           in.close();
       }
   
       @Test
       public void queryAllTest() {
           // 5.使用代理对象执行方法
           List<User> users = userDao.queryAll();
           for (User user : users) {
               System.out.println(user);
           }
       }
   }
   ```



### 1.3 核心组件

MyBatis 核心组件分为 4 个部分：

* `SqlSessionFactoryBuilder`：构造器，它会根据配置或者代码来生成 `SqlSessionFactory`，采用的是分步构建的 Builder 模式
* `SqlSessionFactory`：工厂接口，使用工厂模式来生成 `SqlSession`
* `SqlSession`：会话，一个既可以发送 SQL 执行返回结果，也可以使用代理模式获取 `Mapper` 接口的实现类
* `SQL Mapper`：映射器，它由一个 java 接口和 XML 文件（或注解）组成，需要给出对应的 SQL 和映射规则，负责发送 SQL 去执行，并返回结果



## 2. CRUD操作

### 2.1 插入操作

1. **修改持久层接口 IUserDao**

   ```java
   public interface IUserDao {
       // 插入操作
       void insertUser(User user);
   }
   ```

2. **修改映射配置文件 IUserDao.xml**

   ```xml
   <!-- 插入用户 -->
   <insert id="insertUser" parameterType="domain.User">
       <!-- 配置插入操作后，获取插入数据的id -->
       <selectKey keyProperty="userId" keyColumn="user_id" resultType="int" order="AFTER">
           select last_insert_id()
       </selectKey>
       insert into user(user_name, user_sex) values(#{userName}, #{userSex});
   </insert>
   ```

3. **测试**

   ```java
   @Test
   public void insertUserTest() {
       User user = new User();
       user.setUserName("张三");
       user.setUserSex("男");
       // 插入操作前：User(userId=null, userName=张三, userSex=男)
       System.out.println("插入操作前：" + user); 
   
       // 5.执行插入方法，并提交事务
       userDao.insertUser(user);
       sqlSession.commit();
       // 插入操作后：User(userId=6, userName=张三, userSex=男)
       System.out.println("插入操作后：" + user);
   }
   ```



### 2.2 更新操作

1. **修改持久层接口 IUserDao**

   ```java
   public interface IUserDao {
       // 更新操作
       void updateUser(User user);
   }
   ```

2. **修改映射配置文件 IUserDao.xml**

   ```xml
   <!-- 更新用户 -->
   <update id="updateUser" parameterType="domain.User">
       <!-- 因为接口方法的参数是User，所以userId必须是User类的属性名-->
       update user set user_name = #{userName} where user_id = #{userId}
   </update>
   ```

3. **测试**

   ```java
   @Test
   public void updateUserTest() {
       User user = new User();
       user.setUserId(6);
       user.setUserName("赵六");
   
       // 5.执行更新方法，并提交事务
       userDao.updateUser(user);
       sqlSession.commit();
   }
   ```



### 2.3 删除操作

1. **修改持久层接口 IUserDao**

   ```java
   public interface IUserDao {
       // 删除操作
       void deleteUser(int user_id);
   }
   ```

2. **修改映射配置文件 IUserDao.xml**

   ```xml
   <!-- 删除用户 -->
   <delete id="deleteUser" parameterType="int">
       <!-- 因为接口方法的参数只是一个int类型，所以可以不使用属性名userId，uid仅起到占位符的作用 -->
       delete from user where user_id = #{uid}
   </delete>
   ```

3. **测试**

   ```java
   @Test
   public void updateUserTest() {
       User user = new User();
       user.setUserId(6);
       user.setUserName("赵六");
   
       // 5.执行更新方法，并提交事务
       userDao.updateUser(user);
       sqlSession.commit();
   }
   ```

   

### 2.4 查询操作

1. **修改持久层接口 IUserDao**

   ```java
   public interface IUserDao {
       // 精确查询
       User queryUserById(Integer user_id);
   
       // 模糊查询
       List<User> queryUserByName(String user_name);
   
       // 使用聚集函数查询总用户数
       int queryTotalUser();
       
       // 根据QueryVo中的条件查询用户
       List<User> queryUserByVo(QueryVo queryVo);
   }
   ```

2. **创建查询条件封装类 QueryVo**

   ```java
   @Data
   public class QueryVo {
       private User user;
       // 如果还有其他的查询条件，可以一并封装进来
   }
   ```
   
3. **修改映射配置文件 IUserDao.xml**

   ```xml
   <!-- 精确查询用户 -->
   <select id="queryUserById" parameterType="Integer" resultMap="userMap">
       select * from user where user_id = #{uid}
   </select>
   
   <!-- 模糊查询用户 -->
   <select id="queryUserByName" parameterType="String" resultMap="userMap">
       select * from user where user_name like #{userName}
   </select>
   
   <!-- 使用聚集函数查询总用户数 -->
   <select id="queryTotalUser" resultType="int">
       select count(user_id) from user
   </select>
   
   <!-- 根据QueryVo中的条件查询用户 -->
   <select id="queryUserByVo" parameterType="domain.QueryVo" resultMap="userMap">
       <!-- user.userName中的user是QueryVo中的属性，而userName是User中的属性 -->
       select * from user where user_name like #{user.userName}
   </select>
   ```

4. **测试**

   ```java
   @Test
   public void queryUserByIdTest() {
       // 5.执行精确查询方法
       User user = userDao.queryUserById(1);
       System.out.println(user);
   }
   
   @Test
   public void queryUserByNameTest() {
       // 5.执行模糊查询方法
       userDao.queryUserByName("%三%").forEach(System.out::println);
   }
   
   @Test
   public void queryTotalUserTest() {
       // 5.执行统计用户方法
       int count = userDao.queryTotalUser();
       System.out.println(count);
   }
   
   @Test
   public void queryUserByVoTest() {
       // 5.执行查询方法
       QueryVo queryVo = new QueryVo();
       User user = new User();
       user.setUserName("%三%");
       queryVo.setUser(user);
   	queryUserByVo(queryVo).forEach(System.out::println);
   }
   ```



### 2.5 配置文件标签

1. **创建数据库连接配置文件 jdbcConfig.properties**

   ```properties
   driver = com.mysql.jdbc.Driver
   url = jdbc:mysql://localhost:3306/mybatis?useUnicode=true&characterEncoding=UTF-8
   username = root
   password = root
   ```

2. **修改主配置文件 SqlMapConfig.xml**

   ```xml
   <?xml version="1.0" encoding="utf-8" ?>
   <!DOCTYPE configuration
           PUBLIC "-//mybatis.org//DTD config 3.0//EN"
           "http://mybatis.org/dtd/mybatis-3-config.dtd">
   
   <configuration>
       <!-- 可以在properties标签内部配置连接数据库的信息，也可以通过属性引用外部配置文件信息，
       resource属性用于指定配置文件的位置，是按照类路径的写法来写，并且必须存在于类路径下 -->
       <properties resource="jdbcConfig.properties"/>
   
       <!-- 使用typeAliases配置别名，它只能配置domain中类的别名 -->
   	<typeAliases>
           <!-- type属性指定实体类的全限定类名，alias属性指定别名，别名不再区分大小写 -->
           <!-- <typeAlias type="domain.User" alias="user"/> -->
           
           <!-- 用于指定要配置别名的包，该包下的实体类都会注册别名，且类名就是别名，不再区分大小写 -->
           <package name="domain"/>
       </typeAliases>
   
   
       <!-- 配置环境 -->
       <environments default="mysql">
           <environment id="mysql">
               <transactionManager type="JDBC"/>
               <dataSource type="POOLED">
                   <!-- 通过属性引用外部配置文件信息 -->
                   <property name="driver" value="${driver}"/>
                   <property name="url" value="${url}"/>
                   <property name="username" value="${username}"/>
                   <property name="password" value="${password}"/>
               </dataSource>
           </environment>
       </environments>
   
       <!-- 指定映射配置文件的位置，映射配置文件指的是每个dao独立的配置文件 -->
       <mappers>
           <!-- 1.XML方式 -->
   		<!-- <mapper resource="dao/IUserDao.xml"/> -->
           <!-- 2.注解方式 -->
   		<!-- <mapper class="dao.IUserDao"/>-->
           <!-- 3.package用于指定dao接口所在的包，指定后就不需要再写mapper了 -->
           <package name="dao"/>
       </mappers>
   </configuration>
   ```

   注：之前在编写映射配置文件时， resultType 这个属性可以写 int、INT 等，就是因为 Mybatis 给这些类型起了别名，Mybatis 内置的别名如下所示：

   | 别名       | Java 类型  | 别名       | Java 类型  |
   | ---------- | ---------- | ---------- | ---------- |
   | _byte      | byte       | byte       | Byte       |
   | _long      | long       | long       | Long       |
   | _short     | short      | short      | Short      |
   | _int       | int        | int        | Integer    |
   | _integer   | int        | integer    | Integer    |
   | _double    | double     | double     | Double     |
   | _float     | float      | float      | Float      |
   | _boolean   | boolean    | boolean    | Boolean    |
   | string     | String     | map        | Map        |
   | date       | Date       | hashmap    | HashMap    |
   | decimal    | BigDecimal | list       | List       |
   | bigdecimal | BigDecimal | arraylist  | ArrayList  |
   | object     | Object     | collection | Collection |
   |            |            | iterator   | Iterator   |



## 3. MyBatis 高级

### 3.1 连接池

**线程池就是一个用于存储连接的容器，容器其实是一个集合对象**，该集合必须是线程安全的，不能多个线程拿到同一个连接，同时该集合必须实现队列的特性，即先进先出。在实际开发中都会使用线程池，因为它可以减少获取连接所消耗的时间。在 Mybatis 中，提供了三种方式的配置：

* **POOLED **：采用传统的 javax.sql.DataSource 规范中的连接池，Mybatis 中有针对规范的实现
* **UNPOOLED**：采用传统的获取连接的方式，虽然也实现了 javax.sql.DataSource 接口，但是并没有使用池的思想
* **JNDI** ： 采用服务器提供的 JNDI 技术实现，来获取 DataSource 对象，不同的服务器所能拿到的 DataSource 是不一样的，比如 Tomcat 服务器，采用的连接池就是 dbcp 连接池。注意，如果不是 Web 或 Maven 的 war 工程，是不能使用 JNDI 的



### 3.2 动态 SQL

#### 3.2.1 if 标签

1. **修改持久层接口 IUserDao**

   ```java
   public interface IUserDao {
       // 根据不同的条件进行查询，条件可能只有用户名或性别，也可能都有
       List<User> queryUserByCondition(User user);
   }
   ```

2. **修改映射配置文件 IUserDao.xml**

   ```xml
   <!-- 以下映射配置二选一即可 -->
   <select id="queryUserByCondition" parameterType="domain.User" resultMap="userMap">
       <!-- 恒等条件1 = 1必须加上，否则拼接的字符串不符合SQL语法 -->
       select * from user where 1 = 1
       <!-- test属性用于判断条件，如果有多个条件，必须使用and连接，而不能是&& -->
       <if test="userName != null and userName != ''">
           and user_name = #{userName}
       </if>
       <if test="userSex != null and userName != ''">
           and user_sex = #{userSex}
       </if>
   </select>
   
   <select id="queryUserByCondition" parameterType="domain.User" resultMap="userMap">
       select * from user
       <!-- where标签可以动态添加where关键字，并且剔除SQL语句中多余的and或or -->
       <!-- 为了避免在动态拼接SQL语句时发生错误，建议在编写SQL语句时不要添加分号; -->
       <where>
           <if test="userName != null">
               and user_name = #{userName}
           </if>
           <if test="userSex != null">
               and user_sex = #{userSex}
           </if>
       </where>
   </select>
   ```

3. **测试**

   ```java
   @Test
   public void queryUserByConditionTest() {
       // 5.执行查询方法
       User user = new User();
       user.setUserName("张三");
   	userDao.queryUserByCondition(user).forEach(System.out::println);
   }
   ```

   

#### 3.2.2 foreach 标签

1. **修改查询条件封装类 QueryVo**

   ```java
   @Data
   public class QueryVo {
       private User user;
       private List<Integer> ids;
       // 如果还有其他的查询条件，可以一并封装进来
   }
   ```

2. **修改持久层接口 IUserDao**

   ```java
   public interface IUserDao {
       // 根据queryVo提供的ID集合，同时进行查询
       List<User> queryUserByIds(QueryVo queryVo);
   }
   ```

3. **修改映射配置文件 IUserDao.xml**

   ```xml
   <select id="queryUserByIds" parameterType="domain.QueryVo" resultMap="userMap">
       select * from user
       <where>
           <if test="ids != null and ids.size() > 0">
               <!-- foreach标签用于遍历集合。其中collection表示遍历的集合或数组，值ids对应封装类的属性名；open表示语句的开始部分，close表示语句的结束部分；item表示遍历集合时的每个元素，相当于临时变量；index表示当前元素在集合的位置下标；separator表示分隔符 -->
               <foreach collection="ids" open="and user_id in (" close=")" item="uid" separator=",">
                   #{uid}
               </foreach>
           </if>
       </where>
   </select>
   ```

4. **测试**

   ```java
   @Test
   public void queryUserByIdsTest() {
       // 5.执行查询方法
       QueryVo queryVo = new QueryVo();
       queryVo.setIds(Arrays.asList(1, 8, 3));
       userDao.queryUserByIds(queryVo).forEach(System.out::println);
   }
   ```
   
   

### 3.3 多表查询

#### 3.3.1 一对一

1. **创建数据库**

   ```sql
   -- 创建账户表，外键为user_id，关联用户表的user_id
   DROP TABLE IF EXISTS `account`;
   CREATE TABLE `account` (
       `account_id` int(11) NOT NULL COMMENT '账户编号',
       `user_id` int(11) default NULL COMMENT '用户编号',
       `account_money` double default NULL COMMENT '账户金额',
       PRIMARY KEY  (`account_id`),
       KEY `FK_Reference_8` (`user_id`),
       CONSTRAINT `FK_Reference_8` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`)
   ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
   
   -- 导入账户数据
   insert into `account`(`account_id`, `user_id`, `account_money`) values 
   (1, 2, 1000), (2, 1, 1000), (3, 2, 2000);
   ```

2. **创建实体类 Account**

   ```java
   @Data
   public class Account implements Serializable {
       private Integer accountId;
       private Integer userId;
       private double accountMoney;
   
       // 一对一关系映射：一个账户只能有一个用户，从表实体包含一个主表实体的对象引用
       private User user;
   }
   ```

3. **创建持久层接口 IAccountDao**

   ```java
   public interface IAccountDao {
       // 查询所有账户，同时包含用户信息
       List<Account> queryAll();
   }
   ```

4. **创建映射配置文件 IAccountDao.xml**

   ```xml
   <mapper namespace="dao.IAccountDao">
       <resultMap id="accountUserMap" type="account">
           <id property="accountId" column="account_id"/>
           <result property="userId" column="user_id"/>
           <result property="accountMoney" column="account_money"/>
   
           <!-- association标签配置一对一的关系映射：配置封装user的内容 -->
           <!-- property表示关联的属性，javaType表示关联的实体类的全限定类名，这里配置了别名 -->
           <association property="user" column="user_id" javaType="user">
               <id property="userId" column="user_id"/>
               <result property="userName" column="user_name"/>
               <result property="userSex" column="user_sex"/>
           </association>
       </resultMap>
   
       <!-- 配置查询所有账户，同时包含用户信息 -->
       <select id="queryAll" resultMap="accountUserMap">
           select u.*, a.* from account a, user u where a.user_id = u.user_id;
       </select>
   </mapper>
   ```

5. **测试**

   ```java
   @Test
   public void queryAllTest() {
       // 5.使用代理对象执行方法（省略accountDao的创建过程）
       accountDao.queryAll().forEach(System.out::println);
   }
   ```

   

#### 3.3.2 一对多

1. **修改实体类 User**

   ```java
   @Data
   public class User implements Serializable {
       private int userId;
       private String userName;
       private String userSex;
       // 一对多关系映射：一个用户可以有多个账户，主表实体应该包含从表实体的集合引用
       private List<Account> accounts;
   }
   ```

3. **修改持久层接口 IUserDao**

   ```java
   public interface IUserDao {
       // 查询所有用户，同时包含账户信息
       List<User> queryAll();
   }
   ```

4. **修改映射配置文件 IUserDao.xml**

   ```xml
   <mapper namespace="dao.IUserDao">
       <resultMap id="userAccountMap" type="user">
           <id property="userId" column="user_id"/>
           <result property="userName" column="user_name"/>
           <result property="userSex" column="user_sex"/>
   
           <!-- collection标签配置一对多关系映射：配置user对象中accounts集合的映射 -->
           <!-- property表示要关联的集合属性，ofType表示集合元素（实体类）的全限定类名 -->
           <collection property="accounts" ofType="account">
               <id property="accountId" column="account_id"/>
               <result property="userId" column="user_id"/>
               <result property="accountMoney" column="account_money"/>
           </collection>
       </resultMap>
   
       <!-- 配置查询所有用户，同时包含账户信息 -->
       <select id="queryAll" resultMap="userAccountMap">
           select * from user u left outer join account a on a.user_id = u.user_id;
       </select>
   </mapper>
   ```
   
5. **测试**

   ```java
   @Test
   public void queryAllTest() {
       // 5.使用代理对象执行方法
       userDao.queryAll().forEach(System.out::println);
   }
   ```

   

#### 3.3.3 多对多

1. **创建数据库**

   ```sql
   -- 创建角色表
   DROP TABLE IF EXISTS `role`;
   CREATE TABLE `role` (
       `role_id` int(11) NOT NULL COMMENT '角色编号',
       `role_name` varchar(30) default NULL COMMENT '角色名称',
       `role_desc` varchar(60) default NULL COMMENT '角色描述',
       PRIMARY KEY  (`role_id`)
   ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
   
   -- 添加角色数据
   insert into `role`(`role_id`, `role_name`, `role_desc`) values 
   (1,'院长','管理学院'), (2,'总裁','管理公司'), (3,'校长','管理学校');
   
   -- 创建用户角色表，也就是中间表，uid 和 rid是复合主键，同时也是外键
   DROP TABLE IF EXISTS `user_role`;
   CREATE TABLE `user_role` (
       `user_id` int(11) NOT NULL COMMENT '用户编号',
       `role_id` int(11) NOT NULL COMMENT '角色编号',
       PRIMARY KEY  (`user_id`,`role_id`),
       KEY `FK_Reference_10` (`role_id`),
       CONSTRAINT `FK_Reference_9` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`),
       CONSTRAINT `FK_Reference_10` FOREIGN KEY (`role_id`) REFERENCES `role` (`role_id`)
   ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
   
   -- 添加用户角色数据
   insert into `user_role`(`user_id`, `role_id`) values (3,1), (4,1), (3,2);
   ```

2. **创建实体类 Role，并修改实体类 User**

   ```java
   @Data
   public class Role implements Serializable {
       private Integer roleId;
       private String roleName;
       private String roleDesc;
       // 多对多的关系映射：一个角色可以赋予多个用户，实体类包含对方实体的集合引用
       private List<User> users;
   }
   ```
   
   ```java
   @Data
   public class User implements Serializable {
       private int userId;
       private String userName;
       private String userSex;
       // 一对多关系映射：一个用户可以有多个账户，主表实体应该包含从表实体的集合引用
       private List<Account> accounts;
       // 多对多关系映射：一个用户可以具备多个角色，实体类包含对方实体的集合引用
       private List<Role> roles;
   }
   ```

3. **创建持久层接口 IRoleDao，并修改持久层接口 IUserDao**

   ```java
   public interface IRoleDao {
       // 查询所有角色，包含用户信息
       List<Role> queryAll();
   }
   ```

   ```java
   public interface IUserDao {
       // 查询所有用户，同时包含角色信息
       List<User> queryAll2();
   }
   ```

4. **创建映射配置文件 IRoleDao.xml，并修改映射配置文件 IUserDao.xml**

   ```xml
   <mapper namespace="dao.IRoleDao">
       <resultMap id="roleUserMap" type="role">
           <id property="roleId" column="role_id"/>
           <result property="roleName" column="role_name"/>
           <result property="roleDesc" column="role_desc"/>
   
           <!-- 多对多关系映射：配置role对象中users集合的映射（可以看作一对多关系映射） -->
           <collection property="users" ofType="user">
               <id property="userId" column="user_id"/>
               <result property="userName" column="user_name"/>
               <result property="userSex" column="user_sex"/>
           </collection>
       </resultMap>
   
       <!-- 配置查询所有角色 -->
       <select id="queryAll" resultMap="roleUserMap">
           select r.*, u.* from role r
           left outer join user_role ur on r.role_id = ur.role_id
           left outer join user u on u.user_id = ur.user_id
       </select>
   </mapper>
   ```

   ```xml
   <mapper namespace="dao.IUserDao">
       <resultMap id="userAccountMap" type="user">
           <id property="userId" column="user_id"/>
           <result property="userName" column="user_name"/>
           <result property="userSex" column="user_sex"/>
   
           <!-- 多对多关系映射：配置user对象中roles集合的映射（可以看作一对多关系映射） -->
           <collection property="roles" ofType="role">
               <id property="roleId" column="role_id"/>
               <result property="roleName" column="role_name"/>
               <result property="roleDesc" column="role_desc"/>
           </collection>
       </resultMap>
   
       <!-- 配置查询所有用户，同时包含角色信息 -->
       <select id="queryAll2" resultMap="userAccountMap">
           select r.*, u.* from user u
           left outer join user_role ur on u.user_id = ur.user_id
           left outer join role r on r.role_id = ur.role_id;
       </select>
   </mapper>
   ```

5. **测试**

   ```java
   @Test
   public void queryRoleTest() {
       // 5.使用代理对象执行方法（省略roleDao的创建过程）
       roleDao.queryAll().forEach(System.out::println);
   }
   
   @Test
   public void queryAll2Test() {
       // 5.使用代理对象执行方法
       userDao.queryAll2().forEach(System.out::println);
   }
   ```



### 3.4 延迟加载

在查询用户的时候，用户所拥有的账户信息应该是**需要使用的时候才去查询**，不然每次查询该用户的时候，都要查询他拥有的账户，那么开销无疑是比较大的；而在查询账户的时候，由于每个账户对应一个用户，所以应该让用户信息**随账户信息一并查询出来**，否则别人不知道该账户属于谁。

- **延迟加载**也称懒加载，就是在**需要用到数据时才进行加载，不需要用到数据时就不加载数据**，通常用于**一对多**或**多对多**的表关系中。
- **立即加载**就是不管是否需要数据，只要**一进行查询，就会把相关联的数据一并查询出来**，通常用于**多对一**或**一对一**的表关系中。

下面仅演示一对多关系映射实现延迟加载，一对一关系映射实现延迟加载与之类似：

1. **修改主配置文件 SqlMapConfig.xml**

   ```xml
   <configuration>
       <settings>
           <!-- 开启mybatis延迟加载 -->
           <setting name="lazyLoadingEnabled" value="true"/>
           <setting name="aggressiveLazyLoading" value="false"/>
       </settings>
   </configuration>
   ```

2. **修改映射配置文件 IUserDao.xml**

   ```xml
   <mapper namespace="dao.IUserDao">
       <resultMap id="userAccountMap" type="user">
           <result property="userName" column="user_name"/>
           <result property="userSex" column="user_sex"/>
   
           <!-- 一对多关系映射实现延迟加载，延迟加载都是在需要的时候再调用对方的方法来进行加载。select表示我们要调用的映射语句ID，它会从column属性指定的列中检索数据，作为参数传递给目标select语句 -->
   		<!-- 一对一关系映射实现延迟加载类似，只不过使用association标签 -->
           <collection property="accounts" column="user_id" ofType="account" select="dao.IAccountDao.queryAccountByUserId"/>
       </resultMap>
   
       <!-- 查询所有用户，延迟加载账户信息 -->
       <select id="queryUser" resultMap="userAccountMap">
           select * from user
       </select>
   </mapper>
   ```

3. **修改持久层接口 IAccountDao 和映射配置文件 IAccountDao.xml**

   ```java
   public interface IAccountDao {
       // 根据用户ID查询账户
       List<Account> queryAccountByUserId(Integer user_id);
   }
   ```

   ```xml
   <mapper namespace="dao.IAccountDao">
       <resultMap id="accountUserMap" type="account">
           <id property="accountId" column="account_id"/>
           <result property="userId" column="user_id"/>
           <result property="accountMoney" column="account_money"/>
       </resultMap>
   
       <!-- 根据用户ID查询账户 -->
       <select id="queryAccountByUserId" parameterType="integer" resultMap="accountUserMap">
           select * from account where user_id = #{uid};
       </select>
   </mapper>
   ```

4. **测试**

   ```java
   @Test
   public void queryUserTest() {
       // 5.使用代理对象执行方法
       List<User> users = userDao.queryUser();
       for (User user : users){
           System.out.println(user);
           // 如果注释掉下面的语句，则不会将账户信息查询出来
           System.out.println(user.getAccounts());
       }
   }
   ```

   

### 3.5 缓存

缓存就是存在于**内存中的临时数据**，它可以减少和数据库的交互次数，提高执行效率。缓存适用于：**经常查询且不经常改变的数据，且数据的正确与否对最终结果影响不大**。如商品的库存、银行的汇率等，由于缓存与数据库不一致可能产生较大影响，因此不适用使用缓存。

#### 3.5.1 一级缓存

一级缓存是 **SqlSession 级别的缓存**，默认情况下，也就是没有任何配置的情况下，MyBatis 系统会开启一级缓存。当调用 SqlSession 的插入、更新删除、commit()、close()、clearCache() 等方法时，就会清空一级缓存。

1. **测试**

   ```java
   @Test
   public void firstLevelCacheTest() {
       User user = userDao.queryUserById(1);
       // 调用sqlSession的clearCache()方法会清除缓存，结果为false
   //        sqlSession.clearCache();
       // 调用更新方法也会清除缓存，结果为false
   //        userDao.updateUser(user);
       User user2 = userDao.queryUserById(1);
       // 默认结果为true
       System.out.println(user == user2);
   }
   ```

   

#### 3.5.2 二级缓存

二级缓存是 **SqlSessionFactory 级别的缓存**，由同一个 SqlSessionFactory 对象创建的  SqlSession 共享其缓存。二级缓存中**存放的是对象数据，而非对象本身**，它需要一个**序列化和反序列化**的过程，因此所缓存的类必须实现 `java.io.Serializable` 接口。

1. **修改主配置文件 SqlMapConfig.xml**

   ```xml
   <configuration>
       <settings>
           <!-- 开启mybatis二级缓存，其实可以省略，因为默认也是开启的 -->
           <setting name="cacheEnabled" value="true"/>
       </settings>
   </configuration>
   ```

2. **修改映射配置文件 IUserDao.xml**

   ```xml
   <mapper namespace="dao.IUserDao">
       <!-- 开启user支持二级缓存 -->
       <cache/>
       
       <!-- 根据ID查询用户，使用useCache="true"开启二级缓存 -->
       <select id="queryUserById" parameterType="Integer" resultMap="userAccountMap" useCache="true">
           select * from user where user_id = #{uid}
       </select>
   </mapper>
   ```

3. **测试**

   ```java
   @Test
   public void secondLevelCacheTest() {
       SqlSession sqlSession1 = factory.openSession();
       IUserDao userDao1 = sqlSession1.getMapper(IUserDao.class);
       User user1 = userDao1.queryUserById(1);
   
       SqlSession sqlSession2 = factory.openSession();
       IUserDao userDao2 = sqlSession2.getMapper(IUserDao.class);
       User user2 = userDao2.queryUserById(1);
   
       // 开启二级缓存仍然是false，原因是二级缓存中存放的是对象数据，而非对象本身，但只会发起一次查询
       System.out.println(user1 == user2);
   }
   ```



## 4. 注解开发

在 Mybatis 的注解开发中，常用的注解如下表所示：

| 注解     | 作用 | 注解            | 作用                     |
| :------- | ---- | --------------- | ------------------------ |
| @Intsert | 插入 | @Results        | 结果集封装               |
| @Update  | 更新 | @ResultMap      | 引用 @Results 定义的封装 |
| @Delete  | 删除 | @One            | 一对一结果集封装         |
| @Select  | 查询 | @Many           | 一对多结果集封装         |
|          |      | @SelectProvider | 动态 SQL 映射            |
|          |      | @CacheNamespace | 二级缓存                 |

注：注解开发仅用于替换映射配置文件，主配置文件还是必须存在的

1. **修改持久层接口 IUserDao**

   ```java
   public interface IUserDao {
       // 查询所有用户，包括对应的账户信息（一对多）
       @Select("select * from user")
       // @Results注解用于定义映射结果集，id为唯一标识，value用于接收@Result[]注解类型的数组
       // @Result注解用于定义映射关系，id指定主键，property指定实体类属性名，column指定表中对应的列
       // @Many注解用于一对多的多表查询，select指定用于查询的接口方法，fetchType用于指定立即加载或延迟加载，分别对应 FetchType.EAGER 和 FetchType.LAZY
       @Results(id = "userMap", value = {
               @Result(id = true, column = "user_id", property = "userId"),
               @Result(column = "user_name", property = "userName"),
               @Result(column = "user_sex", property = "userSex"),
               @Result(column = "user_id", property = "accounts",
                       many = @Many(select = "dao.IAccountDao.queryAccountByUserId",
                               fetchType = FetchType.LAZY))
       })
       List<User> queryAll();
   
       // 查询所有用户
       @Select("select * from user")
       @ResultMap(value = {"userMap"})
       List<User> queryUser();
   
       // 插入用户
       @Insert("insert into user(user_name, user_sex) values(#{userName}, #{userSex})")
       void insertUser(User user);
   
       // 更新用户
       @Update("update user set user_name = #{userName}, user_sex = #{userSex} where user_id = #{userId}")
       void updateUser(User user);
   
       // 删除用户
       @Delete("delete from user where user_id = #{userId}")
       void deleteUser(Integer userId);
   
       // 根据id查找用户
       @Select("select * from user where user_id = #{userId}")
       @ResultMap("userMap")
       User queryUserById(Integer userId);
   }
   ```

2. **修改持久层接口 IAccountDao**

   ```java
   // 使用@CacheNamespace开启二级缓存
   @CacheNamespace(blocking = true)
   public interface IAccountDao {
       // 查询所有账户，包括对应的用户信息（一对一）
       @Select("select * from account")
       @Results(id = "accountUserMap", value = {
               @Result(id = true, column = "account_id", property = "accountId"),
               @Result(column = "user_id", property = "userId"),
               @Result(column = "account_money", property = "accountMoney"),
               @Result(column = "user_id", property = "user",
                       one = @One(select = "dao.IUserDao.queryUserById", fetchType = FetchType.EAGER))
       })
       List<Account> queryAll();
   
       // 根据用户id查询所有账户
       @Select("select * from account where user_id = #{userId}")
       @ResultMap("accountUserMap")
       List<Account> queryAccountByUserId(Integer userId);
   }
   ```

   





## 参考

1. [官方文档](https://mybatis.org/mybatis-3/zh/index.html)
2. [b站视频](https://www.bilibili.com/video/BV1Db411s7F5?from=search&seid=4040748663948841523)