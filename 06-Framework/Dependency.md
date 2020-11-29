## 1. Lombok

### 1.1 简介

Lombok 的最主要功能就是通过简单的注解的方式，来帮我们简化和消除一些必须但是又显得臃肿的 Java 样板代码，例如常见的 getter、setter，toString 等等。Lombok 依赖引入如下：

```xml
<!-- https://mvnrepository.com/artifact/org.projectlombok/lombok -->
<dependency>
    <groupId>org.projectlombok</groupId>
    <artifactId>lombok</artifactId>
    <version>1.18.10</version>
    <scope>provided</scope>
</dependency>
```

### 1.2 常见注解

1. **@Data**：作用于类，最常见的注解，等同于增加了 @Setter、@Getter、@EqualsAndHashCode、@ToString

   ![Lombok注解@Data](./images/Dependency/Lombok注解@Data.png)

2. **@Getter & @Setter**：作用于属性，会自动生成 getter 和 setter方法

   ```java
   @Getter @Setter 
   private boolean employed = true;
   
   @Setter(AccessLevel.PROTECTED) 
   private String name;
   
   // ---------------等价的java源码---------------
   private boolean employed = true;
   private String name;
    
   public boolean isEmployed() {
       return employed;
   }
    
   public void setEmployed(final boolean employed) {
       this.employed = employed;
   }
    
   protected void setName(final String name) {
       this.name = name;
   }
   ```

3. **@NonNull**：作用于属性，判断是否为空，如果为空，则抛出 java.lang.NullPointerException 异常

   ```java
   @Getter @Setter @NonNull
   private List<Person> members;
   
   // ---------------等价的java源码---------------
   @NonNull
   private List<Person> members;
    
   public Family(@NonNull final List<Person> members) {
       if (members == null) throw new java.lang.NullPointerException("members");
       this.members = members;
   }
    
   @NonNull
   public List<Person> getMembers() {
       return members;
   }
    
   public void setMembers(@NonNull final List<Person> members) {
       if (members == null) throw new java.lang.NullPointerException("members");
       this.members = members;
   }
   ```

4. **@ToString**：作用于类，默认为非静态字段生成 toString 方法，它有如下属性：

   * callSuper：是否输出父类的 toString 方法，默认为 false
   * includeFieldNames：是否包含字段名称，默认为 true
   * exclude：排除生成 tostring 的字段

   ```java
   @ToString(callSuper=true,exclude="someExcludedField")
   public class Foo extends Bar {
       private boolean someBoolean = true;
       private String someStringField;
       private float someExcludedField;
   }
   
   // ---------------等价的java源码---------------
   public class Foo extends Bar {
       private boolean someBoolean = true;
       private String someStringField;
       private float someExcludedField;
    
       @java.lang.Override
       public java.lang.String toString() {
           return "Foo(super=" + super.toString() +
               ", someBoolean=" + someBoolean +
               ", someStringField=" + someStringField + ")";
       }
   }
   ```

5. **@Synchronized**：作用于方法，该注解自动添加到同步机制，生成的代码并不是直接锁方法，而是锁代码块

   ```java
   private DateFormat format = new SimpleDateFormat("MM-dd-YYYY");
    
   @Synchronized
   public String synchronizedFormat(Date date) {
       return format.format(date);
   }
   
   // ---------------等价的java源码---------------
   private final java.lang.Object $lock = new java.lang.Object[0];
   private DateFormat format = new SimpleDateFormat("MM-dd-YYYY");
    
   public String synchronizedFormat(Date date) {
       synchronized ($lock) {
           return format.format(date);
       }
   }
   ```

6. **@Cleanup**：作用于属性，可用于确保已分配的资源被释放，如 IO 的连接关闭

   ```java
   public void testCleanUp() {
       try {
           @Cleanup
           ByteArrayOutputStream baos = new ByteArrayOutputStream();
           baos.write(new byte[] {'Y','e','s'});
           System.out.println(baos.toString());
       } catch (IOException e) {
           e.printStackTrace();
       }
   }
   
   // ---------------等价的java源码---------------
   public void testCleanUp() {
       try {
           ByteArrayOutputStream baos = new ByteArrayOutputStream();
           try {
               baos.write(new byte[]{'Y', 'e', 's'});
               System.out.println(baos.toString());
           } finally {
               baos.close();
           }
       } catch (IOException e) {
           e.printStackTrace();
       }
   }
   ```



## 2. Swagger

### 2.1 简介

Swagger 是一款让你更好的书写 API 文档的规范且完整框架，提供描述、生产、消费和可视化 RESTful Web Service。它的特点在于接口文档实时更新，可以在线测试，以及添加注释信息等。注意，在正式发布时，出于安全和节省运行内存的考虑，建议关闭 Swagger。Swagger 依赖引入如下：

```xml
<!-- https://mvnrepository.com/artifact/io.springfox/springfox-swagger2 -->
<dependency>
    <groupId>io.springfox</groupId>
    <artifactId>springfox-swagger2</artifactId>
    <version>2.9.2</version>
</dependency>

<!-- https://mvnrepository.com/artifact/io.springfox/springfox-swagger-ui -->
<dependency>
    <groupId>io.springfox</groupId>
    <artifactId>springfox-swagger-ui</artifactId>
    <version>2.9.2</version>
</dependency>
```

### 2.2 配置

```java
@Configuration
@EnableSwagger2		// 开启Swagger2
public class SwaggerConfig {
    /**
     * 1. apiInfo()：配置swagger基本信息
     * 2. enable()：配置是否开启swagger
     * 3. apis()：配置扫描接口的方式，包括扫描包、方法/类上的注解等，具体可查看源码
     * 4. paths()：配置过滤的路径
     * 5. groupName(): 配置组的名称，若要设置多个组，只要注入多个Docket实例即可
     */
    @Bean
    public Docket createRestApi() {
        return new Docket(DocumentationType.SWAGGER_2)
                .apiInfo(apiInfo())
                .select()
              .apis(RequestHandlerSelectors.basePackage("com.maomao.swagger.controller"))
//                .apis(RequestHandlerSelectors.withMethodAnnotation(ApiOperation.class))
                .paths(PathSelectors.any())
                .build();
    }

    private ApiInfo apiInfo() {
        return new ApiInfoBuilder()
                .title("Web接口文档")
                .description("简单优雅的restful风格")
                .license("Apache 2.0")
                .version("1.0")
                .build();
    }
}
```

**扩展**：如何在开发和测试环境下开启 Swagger，而在测试环境下不开启？

```java
	@Bean
    public Docket createRestApi(Environment environment) {
        // 设置要显示swagger的环境，并判断当前设定的环境是否符合
        Profiles profiles = Profiles.of("dev", "test");
        boolean b = environment.acceptsProfiles(profiles);

        return new Docket(DocumentationType.SWAGGER_2)
                .apiInfo(apiInfo())
                .enable(b);
    }
```

配置完成后，在浏览器中访问：http://localhost:8080/swagger-ui.html ，界面如下所示：

![swagger界面](./images/Dependency/swagger界面.png)

### 2.3 常见注解

1. **@Api**：作用于类，可以标记一个 Controller 类做为 swagger 文档资源

2. **@ApiOperation**：作用于方法，说明方法的作用，每一个 url 资源的定义

3. **@ApiParam**：作用于参数，说明参数的含义

   ```java
   @Api(value = "用户相关接口", tags = "用户相关接口")
   @RestController
   public class Controller {
       @GetMapping("/hello")
       public String get() {
           return "hello swagger";
       }
   
       @ApiOperation("提交用户")
       @PostMapping("/postUser")
       public String postUser(@ApiParam("用户") User user) {
           return user.getUsername();
       }
   }
   ```

4. **@ApiModel**：作用于类，表示一个 JavaBean 的信息

5. **@ApiModelProperty**：作用于属性，说明 JavaBean 属性的含义

   ```java
   @Data
   @ApiModel("用户实体类")
   public class User {
       @ApiModelProperty("用户名")
       private String username;
       @ApiModelProperty("密码")
       private String password;
   }
   ```



## 3. 



## 参考

1. [Maven 中央仓库](https://mvnrepository.com/)
2. [Lombok 官网](https://objectcomputing.com/resources/publications/sett/january-2010-reducing-boilerplate-code-with-project-lombok)