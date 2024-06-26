# 1. Lombok

## 1.1 简介

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

参考：[Lombok 官网](https://objectcomputing.com/resources/publications/sett/january-2010-reducing-boilerplate-code-with-project-lombok)、[Maven 中央仓库](https://mvnrepository.com/)

## 1.2 常见注解

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



# 2. Swagger

## 2.1 简介

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

参考：[b站视频](https://www.bilibili.com/video/BV1Y441197Lw)

## 2.2 配置

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

## 2.3 常见注解

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



# 3. JWT

## 3.1 简介

JSON Web Token（JWT）是一个开放标准（RFC 7519），它定义了一种紧凑且自包含的方式，用于在各方之间以 JSON 对象安全地传输信息。由于此信息是经过数字签名的，因此可以被验证和信任。JWT 可以使用 HMAC 算法或使用 RSA 或 ECDSA 的公钥/私钥对进行签名，主要用于：

- **授权**：这是使用 JWT 的最常见方案。一旦用户登录，每个后续请求将包括 JWT，从而允许用户访问该令牌允许的路由、服务和资源。单点登录是当今广泛使用 JWT 的一项功能，因为它的开销很小并且可以在不同的域中轻松使用。
- **信息交换**：JWT 是在各方之间安全地传输信息的一种好方法。因为可以对 JWT 进行签名（例如，使用公钥/私钥对），所以可以确保发件人是他们所说的人。此外，由于签名是使用标头和有效负载计算的，因此还可以验证内容是否未被篡改。

```xml
<!-- https://mvnrepository.com/artifact/com.auth0/java-jwt -->
<dependency>
    <groupId>com.auth0</groupId>
    <artifactId>java-jwt</artifactId>
    <version>3.11.0</version>
</dependency>
```

参考：[JWT 官网](https://jwt.io/introduction/)、[b站视频](https://www.bilibili.com/video/BV1i54y1m7cP?p=1)、[彻底理解cookie，session，token的区别](https://blog.csdn.net/qq_31201781/article/details/94575507)、图解 HTTP

## 3.2 Session 与 Token

### 3.2.1  Session 认证

由于 HTTP 协议本身是一种**无状态的协议**，这意味着如果用户向我们的应用提供了用户名和密码来进行用户认证，那么下一次请求时，用户还要再一次进行用户认证才行。为了让应用能识别是哪个用户发出的请求，我们只能**在服务器存储一份用户登录的信息，这份登录信息会在响应时传递给浏览器，告诉其保存为 Cookie**，以便下次请求时发送给应用，这样应用就能识别请求来自哪个用户了，这就是传统的基于session认证。

![基于传统的Session认证](./images/dependency/基于传统的Session认证.png)

基于传统的 Session 认证流程如下：

- 步骤一：客户端把用户 ID 和密码等登录信息放入报文的实体部分，通常是以 POST 方法把请求发送给服务器。而这时，会使用 HTTPS 通信来进行 HTML 表单画面的显示和用户输入数据的发送。
- 步骤二：**服务器会发放用以识别用户的 Session ID**。通过验证从客户端发送过来的登录信息进行身份认证，然后**把用户的认证状态与 Session ID 绑定后记录在服务器端**。向客户端返回响应时，**会在首部字段 Set-Cookie 内写入 Session ID**（如 PHPSESSID=028a8c…）。
  你可以把 Session ID 想象成一种用以区分不同用户的等位号。然而，如果 Session ID 被第三方盗走，对方就可以伪装成你的身份进行恶意操作了。因此必须防止 Session ID 被盗，或被猜出。为了做到这点，Session ID 应使用难以推测的字符串，且服务器端也需要进行有效期的管理，保证其安全性。另外，为减轻跨站脚本攻击（XSS）造成的损失，建议事先在 Cookie 内加上 httponly 属性。
- 步骤三：**客户端接收到从服务器端发来的 Session ID 后，会将其作为 Cookie 保存在本地**。下次向服务器发送请求时，**浏览器会自动发送 Cookie**，所以 Session ID 也随之发送到服务器。服务器端可通过验证接收到的 Session ID 识别用户和其认证状态。

基于传统的 Session 认证暴露出如下问题：

* 每个用户经过我们的应用认证之后，我们的应用都要在服务端做一次记录，以方便用户下次请求的鉴别，通常而言 Session 都是保存在内存中，而**随着认证用户的增多，服务端的开销会明显增大**
* 用户认证之后，服务端做认证记录，如果认证的记录被保存在内存中的话，这意味着用户下次请求还必须要请求在这台服务器上，这样才能拿到授权的资源，这样在**分布式的应用上，相应的限制了负载均衡器的能力**，这也意味着限制了应用的扩展能力
* 因为是基于 Cookie 来进行用户识别的，Cookie 如果被截获，用户就会很**容易受到跨站请求伪造的攻击**
* Session ID 就是一个特征值，**表达的信息不够丰富**，不容易扩展。而且如果后端应用是多节点部署，那么就需要实现 Session共享机制，**不方便集群应用**

### 3.2.2 JWT 认证

JWT 由紧凑的三部分组成，这些部分由点（.）分隔，分别是：**标头（Header）、有效载荷（Payload）、签名（Signature）**，因此，JWT 通常的形式为：`Header.Payload.Signature`

![JWT组成](./images/dependency/JWT组成.png)

* Header 标头通常由两部分组成：令牌的类型（即 JWT）和所使用的签名算法，如 HMAC、SHA256 或 RSA。然后，此 JSON 被 **Base64Url** 编码以形成 JWT 的第一部分。

  ```json
  {
    "alg": "HS256",
    "typ": "JWT"
  }
  ```

- Payload 有效负载包含了声明，声明是有关实体（通常是用户）和其他数据的声明。同样的，它会使用 **Base64Url** 编码，以形成 JWT 的第二部分。注意，对于已签名的令牌，此信息尽管可以防止篡改，但任何人都可以读取（Base64Url 编码是可逆的）。除非将其加密，否则**请勿将机密信息放入 JWT 的有效载荷或报头元素中**。

  ```json
  {
    "sub": "1234567890",
    "name": "John Doe",
    "admin": true
  }
  ```

- 前面两部分都是使用 Base64Url 进行编码的，即前端可以解开知道里面的信息。Signature 需要使用编码后的 Header 和 Payload 以及我们提供的一个密钥，然后使用 Header 中指定的签名算法（HS256）进行签名。签名的作用是保证 JWT 没有被篡改过

  ```
  HMACSHA256(base64UrlEncode(header) + "." + base64UrlEncode(payload), secret)
  ```

![基于JWT认证](./images/dependency/基于JWT认证.png)

基于 JWT 认证的流程如下：

* 步骤一：前端通过 Web 表单将自己的用户名和密码发送到后端的接口。这一过程一般是一个 HTTP POST 请求，建议的方式是通过 SSL 加密的传输（https协议），从而避免敏感信息被嗅探。
* 步骤二：后端核对用户名和密码成功后，**将用户的 ID 等其他信息作为 JWT Payload（负载），将其与头部分别进行 Base64 编码拼接后签名，形成一个 JWT 字符串**，将其作为登录成功的返回结果返回给前端。前端可以将返回的结果保存在 localStorage 或 sessionStorage 上，退出登录时删除保存的 JWT 即可。
* 步骤三：**前端在每次请求时将 JWT 放入 HTTP Header 中的 Authorization 位**（解决 XSS 和 XSRF 问题）。 后端检查 JWT 的有效性，例如，检查签名是否正确、Token 是否过期等。验证通过后，后端可以使用 JWT 中包含的用户信息进行其他逻辑操作。

JWT 的优势在于：

* **简洁**，可以通过 URL，POST 参数或者在 HTTP header 发送，因为数据量小，传输速度也很快
* **自包含**，负载中包含了所有用户所需要的信息，避免了多次查询数据库
* 因为 Token 是以 JSON 加密的形式保存在客户端的，所以 JWT 是**跨语言**的，原则上任何 web 形式都支持
* **不需要在服务端保存会话信息**，特别适用于分布式微服务



## 3.3 工具类封装

```java
/**
 * JWT 工具类
 */
@Slf4j
public class JWTUtils {
    /**
     * 加密时的密钥，用于生成签名signature，不能泄漏
     */
    private static final String SECRET_KEY = "kew@06#khto&xuq3ou56fln4xw!klo9qpg=fb1ro";
    /**
     * JWT过期时间，单位毫秒，默认2h
     */
    private static final long EXPIRE_TIME_MILLIS = 1000 * 3600 * 2;

    /**
     * 生成JWT
     *
     * @param map 保存至有效载荷payload的信息
     * @return 返回JWT
     */
    public static String getJWT(Map<String, String> map) {
        JWTCreator.Builder builder = JWT.create();

        // 设置JWT的有效载荷payload，标头header使用默认设置
        map.forEach(builder::withClaim);
        // 设置JWT的过期时间
        long nowMillis = System.currentTimeMillis();
        builder.withExpiresAt(new Date(nowMillis + EXPIRE_TIME_MILLIS));

        // 使用HS256算法加密生成签名signature后返回JWT
        return builder.sign(Algorithm.HMAC256(SECRET_KEY));
    }

    /**
     * 验证JWT
     *
     * @param jwt JWT字符串
     * @return 验证通过返回有效载荷信息，可通过get("name").asString()获取具体的值；否则返回null
     */
    public static Map<String, Claim> verifyJWT(String jwt) {
        try {
            // 验证过程可能抛出异常：签名不一致异常、令牌过期异常、算法不匹配异常、失效的payload异常等
            DecodedJWT decodedJWT = JWT.require(Algorithm.HMAC256(SECRET_KEY)).build().verify(jwt);
            return decodedJWT.getClaims();
        } catch (TokenExpiredException e) {
            log.info("JWT已过期");
        } catch (SignatureVerificationException e) {
            log.info("签名不一致");
        } catch (AlgorithmMismatchException e) {
            log.info("加密算法不匹配");
        } catch (Exception e) {
            log.info("JWT无效");
        }
        return null;
    }
}
```



## 3.4 配置

```java
/**
 * JWT拦截器
 */
public class JWTInterceptor implements HandlerInterceptor {
    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        // 得到请求头authorization信息
        String token = request.getHeader("token");
        // 进行token验证
        Map<String, Claim> map = JWTUtils.verifyJWT(token);

        if (map == null) {
            Map<String, Object> res = new HashMap<>();
            res.put("state", "error");
            res.put("msg", "token无效或过期");

            String json = new ObjectMapper().writeValueAsString(res);
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().println(json);
            return false;
        } else {
            // token验证通过，进行正常的业务逻辑处理
            return true;
        }
    }
}
```

```java
@Configuration
public class InterceptorConfig implements WebMvcConfigurer {
    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(new JWTInterceptor())
                .addPathPatterns("/user/test")			// 其它请求需要首先验证token
                .excludePathPatterns("/user/login");	// 用户登录请求放行
    }
}
```



# 4. Json

## 4.1 简介

JSON（JavaScript Object Notation）是一种轻量级的数据交换格式，易于人阅读和编写，同时也易于机器解析和生成。 JSON建构于两种结构：名称/值对的集合（相当于 Java 中的 Map<String, Object>）、值的有序列表（相当于 Java 中的 List），并具有以下形式：

* 对象是一个无序的“名称/值对”集合。一个对象以 `{`左括号 开始， `}`右括号 结束，每个“名称”后跟一个 `:`冒号 ，“名称/值对”之间使用 `,`逗号 分隔
* 数组是值（value）的有序集合。一个数组以 `[`左中括号 开始， `]`右中括号 结束，值之间使用 `,`逗号 分隔
* 值（value）可以是双引号括起来的字符串、数值、`true`、`false`、 `null`、对象或数组，这些结构可以嵌套

参考：[json 中文官网](http://www.json.org/json-zh.html)

## 4.2 jakson

### 4.2.1 简介

Spring Boot 内置了 jackson 来完成 JSON 的序列化和反序列化操作，依赖由 `spring-boot-starter-web` 引入，因此在 Spring Boot 中不需要引入依赖。jackson 使用 `ObjectMapper` 类将  Java Bean 序列化成 JSON 字符串，或者将 JSON 字符串反序列化成  Java Bean。

参考：[默认转换工具Jackson](https://blog.csdn.net/u013089490/article/details/83585794)、[利用Jackson封装常用JsonUtil工具类](https://www.cnblogs.com/christopherchan/p/11071098.html)

### 4.2.2 常见注解

1. **@JsonProperty**：作用在属性上，用来为 JSON Key 指定一个别名

2. **@JsonIgnore**：作用在属性上，用来忽略此属性

3. **@JsonFormat**：作用在属性上，用于日期格式化

   ```java
   @JsonFormat(pattern = "yyyy-MM-dd HH-mm-ss")
   private Date date;
   ```

   

### 4.2.3 工具类封装

```java
/**
 * json 工具类
 */
@Slf4j
public class JsonUtils {
    private static ObjectMapper objectMapper = new ObjectMapper();
    private static final String STANDARD_FORMAT = "yyyy-MM-dd HH:mm:ss";

    static {
        // 对象的所有字段全部列入
        objectMapper.setSerializationInclusion(JsonInclude.Include.ALWAYS);
        // 取消默认转换timestamps形式
        objectMapper.configure(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS, false);
        // 所有的日期格式都统一为以下的样式，即yyyy-MM-dd HH:mm:ss
        objectMapper.setDateFormat(new SimpleDateFormat(STANDARD_FORMAT));
        // 忽略空Bean转json的错误
        objectMapper.configure(SerializationFeature.FAIL_ON_EMPTY_BEANS, false);
        // 忽略在json字符串中存在，但是在java对象中不存在对应属性的情况，防止错误
        objectMapper.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
    }

    /**
     * 对象转Json格式字符串
     *
     * @param obj 对象
     * @return Json格式字符串
     */
    public static <T> String obj2String(T obj) {
        if (obj == null) {
            return null;
        }
        try {
            return obj instanceof String ? (String) obj : objectMapper.writeValueAsString(obj);
        } catch (JsonProcessingException e) {
            log.warn("Parse Object to String Error : {}", e.getMessage());
            return null;
        }
    }

    /**
     * 对象转Json格式字符串(格式化的Json字符串)
     *
     * @param obj 对象
     * @return 美化的Json格式字符串
     */
    public static <T> String obj2StringPretty(T obj) {
        if (obj == null) {
            return null;
        }
        try {
            return obj instanceof String ? (String) obj : objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(obj);
        } catch (JsonProcessingException e) {
            log.warn("Parse Object to String Error : {}", e.getMessage());
            return null;
        }
    }

    /**
     * 字符串转换为自定义对象
     *
     * @param str   要转换的字符串
     * @param clazz 自定义对象的class对象
     * @return 自定义对象
     */
    public static <T> T string2Obj(String str, Class<T> clazz) {
        if (StringUtils.isEmpty(str) || clazz == null) {
            return null;
        }
        try {
            return clazz.equals(String.class) ? (T) str : objectMapper.readValue(str, clazz);
        } catch (Exception e) {
            log.warn("Parse String to Object Error : {}", e.getMessage());
            return null;
        }
    }

    /**
     * 字符串转换为集合对象
     *
     * @param str           要转换的字符串
     * @param typeReference 接收类型泛型
     * @return 集合对象
     */
    public static <T> T string2Obj(String str, TypeReference<T> typeReference) {
        if (StringUtils.isEmpty(str) || typeReference == null) {
            return null;
        }
        try {
            return (T) (typeReference.getType().equals(String.class) ? str : objectMapper.readValue(str, typeReference));
        } catch (IOException e) {
            log.warn("Parse String to Collection Object Error", e);
            return null;
        }
    }

    /**
     * 字符串转换为集合对象
     *
     * @param str             要转换的字符串
     * @param collectionClazz 集合的Class对象
     * @param elementClazzes  元素的Class对象
     * @return 集合对象
     */
    public static <T> T string2Obj(String str, Class<?> collectionClazz, Class<?>... elementClazzes) {
        if (StringUtils.isEmpty(str) || collectionClazz == null || elementClazzes == null) {
            return null;
        }
        JavaType javaType = objectMapper.getTypeFactory().constructParametricType(collectionClazz, elementClazzes);
        try {
            return objectMapper.readValue(str, javaType);
        } catch (IOException e) {
            log.warn("Parse String to Collection Object Error : {}" + e.getMessage());
            return null;
        }
    }
}
```



## 4.3 fastjson

### 4.3.1 简介

fastjson 是阿里巴巴的开源 JSON 解析库，它可以解析 JSON 格式的字符串，支持将 Java Bean 序列化为 JSON 字符串，也可以从 JSON 字符串反序列化到 JavaBean。fastjson 具有速度快、使用简单、功能完备等优点，依赖引入如下：

```xml
<dependency>
    <groupId>com.alibaba</groupId>
    <artifactId>fastjson</artifactId>
    <version>1.2.73</version>
</dependency>
```

参考：[github-fastjson](https://github.com/alibaba/fastjson)

### 4.3.2 常见 API

```java
// com.alibaba.fastjson.JSON 类的常用静态方法

// 将 JavaBean 序列化为 JSON 字符串（主要）
public static final String toJSONString(Object object);
// 将 JavaBean 序列化为带格式的 JSON 字符串 
public static final String toJSONString(Object object, boolean prettyFormat);
// 将 JavaBean 序列化为 JSONObject 或 JSONArray；JSONArray 相当于 List，JSONObject 相当于 Map
public static final Object toJSON(Object javaObject); 

// 把 JSON 字符串反序列化为JavaBean（主要）
public static final <T> T parseObject(String text, Class<T> clazz);
// 把 JSON 字符串反序列化为JavaBean 集合 
public static final <T> List<T> parseArray(String text, Class<T> clazz);

// 把 JSON 字符串反序列化为 JSONObject 或 JSONArray
public static final Object parse(String text);
// 把 JSON 字符串反序列化为 JSONObject（主要）
// 有时不方便定义JavaBean，可在获取JSONObject后，通过jsonObject.getString("属性名")获取对应属性值
public static final JSONObject parseObject(String text);
// 把 JSON 字符串反序列化为 JSONArray
public static final JSONArray parseArray(String text);
```



# 5. 日志

## 5.1 简介

![日志发展史](./images/dependency/日志发展史.png)

1. Log4j 最初由瑞士程序员 Ceki Gülcü 开发，出来时就得到了广泛的应用，是 Java 日志事实上的标准，后来成为 Apache 项目。
2. Apache 要求把 Log4j 并入 JDK，遭到 SUN 拒绝，后者在 JDK 1.4 版本增加了 JUL。由于 JDK 自带，因此也有很多人用，这时如果想换成日志组件，如 Log4j 换成 JUL，因为 API 完全不同，就需要改动代码。
3. Apache 见此，开发了 JCL，它只提供一套通用的日志接口 API，并不提供日志的实现，依赖抽象而非实现，这样应用程序可以在运行时选择自己想要的日志实现组件。
4. 但是 Log4j 的作者对 JCL 不满意，于是自己开发了 Slf4j，它跟 JCL 类似，本身不替供日志具体实现，只对外提供接口或门面，目的就是为了替代 JCL。同时还开发出 Logback，一个比 Log4j 拥有更高性能的组件，目的是为了替代 Log4j。
5. Apache 参考了 Logback，并做了一系列优化，推出了 Log4j2。

参考：[b 站视频](https://www.bilibili.com/video/BV13A41137Tc?p=1&vd_source=03ee00a529e3c4f9c2d8c6f412586123)、[JUL日志](https://bbs.huaweicloud.com/blogs/384489)、[slf4j源码解析-门面模式](https://blog.csdn.net/ym674745853/article/details/104715787/)、[深入掌握Java日志体系](https://www.modb.pro/db/221840)、[slf4j 官网](https://www.slf4j.org/manual.html)



## 5.2 JUL

JUL 是 java.util.logging 包的简称，不需要额外引入 jar 包，其日志按照等级**从低到高依次为：ALL < FINEST < FINER < FINE < CONFIG < INFO < WARNING < SEVERE < OFF**，默认级别为 INFO。日志实现框架的组成大多类似，主要包含如下四个主要的组件：

1. **Logger**：日志记录的核心类，关联着一组 Handler，负责收集处理日志记录。
2. **Handler**：对应 Log4j 中的 Appender，负责日志的输出，一个输出源就叫一个 Handler，其类别有：控制台、文件、套接字、内存等。
3. **Layout**：对应 Log4j 中的 Layout，负责转换和格式化日志。
4. **Filter**：负责根据规则过滤日志。

日志输出的大致流程如下：

1. 获取 Logger 实例，该实例初始化会**自动配置一个 RootLogger（即它的父 Logger）**。
2. 当使用 Logger 实例调用方法输出日志时，首先会**比对 Logger 本身的日志等级，以及使用 Filter 过滤日志**。
3. 获取 Logger 实例关联的 Handlers 集合，并依次调用集合中 Handler 的 publish() 方法来输出日志信息，**再此之前会比对 Handler 的日志等级，以及使用 Filter 过滤日志**。
4. 根据 Logger 实例的 useParentHandlers 布尔值判断**是否执行父 Logger 中的 Handlers**，操作同 3。

![日志组件](./images/dependency/日志组件.png)

```properties
# RootLogger顶级父元素指定的默认处理器 ConsoleHandler，可添加多个用,隔开
handlers = java.util.logging.ConsoleHandler
# RootLogger 顶级父元素默认的日志级别为INFO
.level = INFO

# 若是上面handlers中多加了一个FileHandler则配置生效
java.util.logging.FileHandler.pattern = %h/java%u.log
java.util.logging.FileHandler.limit = 50000
java.util.logging.FileHandler.count = 1
java.util.logging.FileHandler.formatter = java.util.logging.XMLFormatter

# 对应上面handlers中的ConsoleHandler进行配置
java.util.logging.ConsoleHandler.level = INFO
java.util.logging.ConsoleHandler.formatter = java.util.logging.SimpleFormatter

# 特殊logger日志的默认等级
com.example.maomao.level = WARNING
```

```java
import java.io.IOException;
import java.util.logging.*;

// JUL不需要额外引入jar包，默认配置文件位于$JAVA_HOME/jre/lib/logging.properties
public class JULDemo {
    static {
        LogManager logManager = LogManager.getLogManager();
        try {
            // 在Java安装目录jre/lib下提供了logging.properties配置文件样例，拷贝到类路径下
            logManager.readConfiguration(JULDemo.class.getClassLoader()
                    .getResourceAsStream("logging.properties"));
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    // JULDemo.class.getName()表示继承的父类，否则配置文件com.example.maomao.level属性无法生效
    private static final Logger LOGGER = Logger.getLogger(JULDemo.class.getName());

    public static void main(String[] args) {
      	// 日志级别：ALL < FINEST < FINER < FINE < CONFIG < INFO < WARNING < SEVERE < OFF
        // 若子Logger未显式设置日志级别，将继承父Logger日志级别，底层使用System.err输出，因此日志输出是洋红色
        // LOGGER.finest("finest level");
        LOGGER.log(Level.FINEST, "finest level");
        LOGGER.log(Level.FINER, "finer level");
        LOGGER.log(Level.FINE, "fine level");
        LOGGER.log(Level.CONFIG, "config level");
        LOGGER.log(Level.INFO, "info level");
        LOGGER.log(Level.WARNING, "warning level");
        LOGGER.log(Level.SEVERE, "severe level");

        Logger logger1 = Logger.getLogger("com");
        Logger logger2 = Logger.getLogger("com.example");
        // Logger中的父子关系通过名字当中的“.”来决定
        System.out.println(logger2.getParent() + " = " + logger2.getParent().getName());
        System.out.println(logger1 + " = " + logger1.getName());
        // 所有Logger的默认父级是java.util.logging.LogManager$RootLogger
        System.out.println(logger1.getParent() + " = " + logger1.getParent().getName());

        // 自定义RootLogger（即设置name=""）
				// Logger logger3 = Logger.getLogger("");
				// System.out.println(logger3 + " = " + logger3.getName());

	      // 设置自己的Handler
        logger2.addHandler(new ConsoleHandler());
        // 解决父子关系中日志重复输出的问题
        logger2.setUseParentHandlers(false);
        logger2.info("log replicate problem");
    }
}
```



## 5.3 Log4j

Log4j 是 Log for java 的简称，其日志按照等级**从低到高依次为：ALL < TRACE < DEBUG < INFO < WARN < ERROR < FATAL < OFF**，默认级别为 INFO。如果配置为 OFF 级别，表示关闭日志。Log4j 支持两种格式的配置文件：properties 和 xml，

```xml
<dependency>
    <groupId>log4j</groupId>
    <artifactId>log4j</artifactId>
    <version>1.2.17</version>
</dependency>
```

```properties
# INFO表示日志级别，stdout、a1、a2分别表示把Logger和具体的Appender关联起来
log4j.rootLogger = INFO,stdout,a1,a2

# 配置控制台的appender，其名字为stdout，可以随便起
log4j.appender.stdout = org.apache.log4j.ConsoleAppender
log4j.appender.stdout.Target = System.out
log4j.appender.stdout.Threshold = INFO
log4j.appender.stdout.layout = org.apache.log4j.PatternLayout
# %d表示日期，%-5p表示日志级别并对齐，%20c表示全类名，%L表示第几行，%m表示打印的消息，%n表示换行
log4j.appender.stdout.layout.ConversionPattern = %d{yyyy-MM-dd HH:mm:ss} %-5p %20c %L:%m %n

# 配置文件的appender，每天一个日志文件，且不会自动清除，需要另外配置Linux的定时任务crontab
log4j.appender.a1 = org.apache.log4j.DailyRollingFileAppender
# 日志文件的存放目录不需要提前创建
log4j.appender.a1.File = ${user.home}/log/server.log
log4j.appender.a1.Threshold = INFO
log4j.appender.a1.layout = org.apache.log4j.PatternLayout
log4j.appender.a1.layout.ConversionPattern = %d{yyyy-MM-dd HH:mm:ss} %-5p %20c %L:%m %n

# 配置文件的appender，可以指定单个文件的最大大小，以及保留多少个日志文件
log4j.appender.a2 = org.apache.log4j.RollingFileAppender
# 日志文件的存放目录不需要提前创建
log4j.appender.a2.File = ${user.home}/log/server2.log
log4j.appender.a2.MaxFileSize = 100MB
log4j.appender.a2.MaxBackupIndex = 7
log4j.appender.a2.Threshold = INFO
log4j.appender.a2.layout = org.apache.log4j.PatternLayout
log4j.appender.a2.layout.ConversionPattern = %d{yyyy-MM-dd HH:mm:ss} %-5p %20c %L:%m %n

# 可以指定具体的包（为避免重复输出，指定的Appender最好不要与父Logger重复）
#log4j.logger.com.example.maomao = ERROR,stdout,a1,a2
```

```java
import org.apache.log4j.Logger;

// Log4j需要引入jar包，且必须有Log4j配置文件log4j.properties，默认类路径下寻找
public class Log4jDemo {
    private static final Logger LOGGER = Logger.getLogger(Log4jDemo.class);

    public static void main(String[] args) {
        LOGGER.trace("trace");
        LOGGER.debug("debug");
        LOGGER.info("info");
        LOGGER.warn("warn");
        LOGGER.error("error");
        LOGGER.fatal("fatal");
    }
}
```



## 5.4 Log4j2

Log4j2 日志按照等级**从低到高依次为：ALL < TRACE < DEBUG < INFO < WARN < ERROR < FATAL < OFF**，默认级别为 INFO。它支持四种格式的配置文件：properties、xml、yaml、json。

```xml
 <dependency>
    <groupId>org.apache.logging.log4j</groupId>
    <artifactId>log4j-core</artifactId>
    <version>2.17.2</version>
</dependency>
```

```properties
rootLogger.level = info
rootLogger.appenderRef.stdout.ref = STDOUT
# 配置控制台的appender
appender.console.type = Console
appender.console.name = STDOUT
appender.console.layout.type = PatternLayout
appender.console.layout.pattern = %d{yyyy-MM-dd HH:mm:ss} %-5p %20c %L:%m %n
appender.console.filter.threshold.type = ThresholdFilter
appender.console.filter.threshold.level = info
```

```java
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

// Log4j2需要引入jar包，且必须有Log4j2配置文件log4j2.properties，默认类路径下寻找
public class Log4j2Demo {
    private static final Logger LOGGER = LogManager.getLogger(Log4j2Demo.class);

    public static void main(String[] args) {
        LOGGER.trace("trace");
        LOGGER.debug("debug");
        LOGGER.info("info");
        LOGGER.warn("warn");
        LOGGER.error("error");
        LOGGER.fatal("fatal");
    }
}
```



## 5.5 JCL

JCL 是 Jakarta Commons Logging 的简称，称作"门面日志"，即它**不负责写日志，而是提供用一个统一的接口**，通过 jar 来决定使用的日志框架，这样就不要在更换框架时修改代码了。JCL 日志按照等级从低到高依次为：ALL < TRACE < DEBUG < INFO < WARN < ERROR < FATAL < OFF，默认级别为 INFO。**JCL 默认使用 JUL 进行日志输出，若要使用 Log4j 进行日志输出，需要引入 Log4j 的 jar 包，并配置 log4j.properties 文件**。注意，JCL 已停止维护，最近一次更新是 2014 年，且包含多个漏洞，由于 Spring 4 使用的是原生 JCL，因此不建议使用；Spring 5 使用的是 spring-jcl，是经过改造的 JCL。

```xml
<!--JCL默认使用JUL进行日志输出-->
<dependency>
    <groupId>commons-logging</groupId>
    <artifactId>commons-logging</artifactId>
    <version>1.2</version>
</dependency>
<!--若要使用Log4j进行日志输出，需要引入Log4j，并配置log4j.properties文件-->
<!--
<dependency>
    <groupId>log4j</groupId>
    <artifactId>log4j</artifactId>
    <version>1.2.17</version>
</dependency>
-->
```

```java
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

// JCL需要引入jar包，且默认使用JUL进行日志输出
public class JCLDemo {
    private static final Log LOG = LogFactory.getLog(JCLDemo.class);

    public static void main(String[] args) {
        LOG.trace("trace");
        LOG.debug("debug");
        LOG.info("info");
        LOG.warn("warn");
        LOG.error("error");
        LOG.fatal("fatal");
    }
}
```



## 5.6 Slf4j

Slf4j 是 Simple Logging Facade For Java 的简称，与 JCL 类似，它也是一种"门面日志"，日志按照等级从低到高依次为：TRACE < DEBUG < INFO < WARN < ERROR，默认级别为 INFO。**Slf4j + Logback 是目前最流行的组合，若要使用 Slf4j + log4j，则需要引入相关 jar 包，并配置 log4j.properties 文件（不能用 logback.xml）**。

### 5.6.1 Slf4j + Logback

```xml
<!-- slf4j+logback -->
<!-- 由于logback-classic依赖前两个，因此其实只需引入logback-classic -->
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>slf4j-api</artifactId>
    <version>1.7.32</version>
</dependency>
<dependency>
    <groupId>ch.qos.logback</groupId>
    <artifactId>logback-core</artifactId>
    <version>1.2.10</version>
</dependency>
<dependency>
    <groupId>ch.qos.logback</groupId>
    <artifactId>logback-classic</artifactId>
    <version>1.2.10</version>
</dependency>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <!-- 定义变量，文件后面可以使用，此处定义日志文件的存储地址 -->
    <property name="LOG_HOME" value="${user.home}/log" />
    <property name="APP_NAME" value="slf4j-demo"/>
    <!-- 格式化输出：%d表示日期，%thread表示线程名，%-5level表示级别从左显示5个字符宽度，%line表示第几行，%msg表示日志消息，%n表示换行符 -->
    <property name="LOG_PATTERN" value="%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{50} %line: %msg%n" />

    <!-- 控制台输出 -->
    <appender name="console" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>${LOG_PATTERN}</pattern>
            <charset>UTF-8</charset>
        </encoder>
    </appender>
    <!-- 输出到日志文件 -->
    <appender name="file"  class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>${LOG_HOME}/${APP_NAME}.log</file>
        <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
            <!--日志文件输出的文件名-->
            <FileNamePattern>${LOG_HOME}/${APP_NAME}-%d{yyyy-MM-dd}-%i.log</FileNamePattern>
            <MaxHistory>7</MaxHistory>
            <MaxFileSize>50MB</MaxFileSize>
            <totalSizeCap>1GB</totalSizeCap>
        </rollingPolicy>
        <encoder>
            <pattern>${LOG_PATTERN}</pattern>
            <charset>UTF-8</charset>
        </encoder>
    </appender>

    <!-- 自定义logger，additivity="false"表示不重复输出 -->
    <logger name="com.example.maomao" level="debug" additivity="false">
        <appender-ref ref="console" />
        <appender-ref ref="file" />
    </logger>

    <root level="info" additivity="false">
        <appender-ref ref="console" />
        <appender-ref ref="file" />
    </root>
</configuration>
```

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

// Slf4j需要引入jar包，且默认会去类路径下找名为logback.xml配置文件
public class Slf4jDemo {
    private static final Logger LOGGER = LoggerFactory.getLogger(Slf4jDemo.class);

    public static void main(String[] args) {
        LOGGER.trace("trace");
        LOGGER.debug("debug");
        LOGGER.info("info");
        LOGGER.warn("warn");
        LOGGER.error("error");
    }
}
```



### 5.6.2 Slf4j + Log4j

```xml
<!-- slf4j+log4j -->
<!-- 由于slf4j-log4j12依赖前两个，因此其实只需引入slf4j-log4j12 -->
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>slf4j-api</artifactId>
    <version>1.7.32</version>
</dependency>
<dependency>
    <groupId>log4j</groupId>
    <artifactId>log4j</artifactId>
    <version>1.2.17</version>
</dependency>
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>slf4j-log4j12</artifactId>
    <version>1.7.32</version>
</dependency>
```

```properties
# INFO表示日志级别，stdout、a1、a2分别表示把Logger和具体的Appender关联起来
log4j.rootLogger = TRACE,stdout

# 配置控制台的appender，其名字为stdout，可以随便起
log4j.appender.stdout = org.apache.log4j.ConsoleAppender
log4j.appender.stdout.Target = System.out
log4j.appender.stdout.Threshold = TRACE
log4j.appender.stdout.layout = org.apache.log4j.PatternLayout
# %d表示日期，%-5p表示日志级别并对齐，%20c表示全类名，%L表示第几行，%m表示打印的消息，%n表示换行
log4j.appender.stdout.layout.ConversionPattern = %d{yyyy-MM-dd HH:mm:ss} %-5p %20c %L:%m %n
```

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class Slf4jLog4jDemo {
    private static final Logger LOGGER = Logger.getLogger(Slf4jLog4jDemo.class);

    public static void main(String[] args) {
        LOGGER.trace("trace");
        LOGGER.debug("debug");
        LOGGER.info("info");
        LOGGER.warn("warn");
        LOGGER.error("error");
        LOGGER.fatal("fatal");
    }
}
```



### 5.6.3 适配器模式

适配器模式用一句话总结，即**用一个包装来包装不兼容的接口对象**，其适用场景是：已经存在的类的接口不符合需求，**解决正在服役的项目问题**。模式角色共 3 个：Adaptee 被适配者（org.apache.log4j）、Target 目标接口（org.slf4j.Logger）、Adapter 适配器（org.slf4j.impl.Log4jLoggerAdapter）。

Slf4j 提供了统一的 Logger API ，每个日志框架（适配器）都会实现该API。在调用 Logger 时，Slf4j 会根据 ClassLoader 加载各框架的 StaticLoggerBinder，然后根据 StaticLoggerBinder 获取对应的 LoggerFactory 对象，再根据 LoggerFactory 创建 Logger 对象，所以调用 Logger 方法时，实际是调用各个框架 Logger 方法，这实际也是门面模式的一种实现。这就解释了为什么 SLf4j 能整合不同日志框架，实际 Slf4j 只是提供了一个接口规范，具体实现交给对应的日志框架实现。

![适配器模式调用流程及类图](./images/dependency/适配器模式调用流程及类图.png)

![Log4jLoggerAdapter源码](./images/dependency/Log4jLoggerAdapter源码.png)



### 5.6.4 日志切换

假设自己的应用使用了 Slf4j + Logback，但依赖的第三方 jar 使用的是 Log4j，此时如何桥接到 Slf4j 并进行统一管理呢？**首先需要排除 Log4j 对应的日志实现，然后引入对应的桥接器，其它类型的第三方 jar 处理与之类似**。

![日志切换](./images/dependency/日志切换.png)

```xml
<!-- 这里假设org.example.log4j-other是需要引入的第三方jar，内容与5.3节类似，但是没有配置文件 -->
<dependency>
    <groupId>org.example</groupId>
    <artifactId>log4j-other</artifactId>
    <version>1.0-SNAPSHOT</version>
    <exclusions>
        <exclusion>
            <artifactId>log4j</artifactId>
            <groupId>log4j</groupId>
        </exclusion>
    </exclusions>
</dependency>
<!-- 引入桥接器，注意桥接器优先级一定要高于Log4j（即引入的桥接器依赖位于第三方依赖前面，或排除第三方依赖），且第三方包不应该有日志配置文件 -->
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>log4j-over-slf4j</artifactId>
    <version>1.7.32</version>
</dependency>
```

```java
// Slf4j需要引入jar包，且默认会去类路径下找名为logback.xml配置文件
public class Slf4jDemo {
    private static final Logger LOGGER = LoggerFactory.getLogger(Slf4jDemo.class);

    public static void main(String[] args) {
        LOGGER.trace("trace");
        LOGGER.debug("debug");
        LOGGER.info("info");
        LOGGER.warn("warn");
        LOGGER.error("error");

        Log4jOther.test();
    }
}
```



### 5.6.5 桥接器原理

以 Log4j-over-slf4j 桥接器为例，它实际定义了一套和 Log4j 一样的 API（**包名、类名、方法定义相同**，这也是为什么需要在 POM 文件中排除原有依赖的原因），在这套 API 中调用 Slf4j 的 API，从而实现偷天换日的效果，即披着 Log4j 的外衣，做着 Slf4j 的事情。

![桥接器原理1](./images/dependency/桥接器原理1.png)

![桥接器原理2](./images/dependency/桥接器原理2.png)



# 6. picocli

## 6.1 简介

picocli 是一个单文件命令行解析框架，几乎不需要任何代码即可创建命令行应用程序，它支持多种命令行语法风格，包括 POSIX、GNU、MS-DOS 等。

```xml
<dependency>
    <groupId>info.picocli</groupId>
    <artifactId>picocli</artifactId>
    <version>4.6.3</version>
</dependency>
```

参考：[官网](https://picocli.info/)、[picocli-入门](https://blog.csdn.net/it_freshman/article/details/125458116)



## 6.2 常见注解

命令行参数可以分为选项（options）和位置参数（positional parameters），选项有一个名称，位置参数通常是选项后面的值，但它们可能是混合的。

![选项和参数](./images/dependency/选项和参数.png)

1. **@CommandLine.Option**：选项，一个选项必须有一个或多个 names，默认情况下，选项名称区分大小写
2. **@CommandLine.Parameters**：位置参数，任何不是子命令或选项的命令行参数都被解释为位置参数，位置参数通常跟在选项后面。使用 index 属性来准确指定要捕获的参数（从零开始），数组或集合字段可以捕获多个值。
3. **@CommandLine.ArgGroup**：一组相互排斥的选项和位置参数，



## 6.3 Demo

```java
@CommandLine.Command(name = "rename", mixinStandardHelpOptions = true,
        version = "1.0", description = "rename directory or file")
public class RenameCommand implements Callable<Integer> {
		// 一组相互排斥的选项和位置参数，multiplicity = "1"表示该组必须出现一次，默认"0..1"
    @CommandLine.ArgGroup(multiplicity = "1")
    private FileOrDirectoryExclusiveOption fileOrDirectoryExclusiveOption;

  	// 布尔选项，usageHelp = true显示使用帮助消息
    @CommandLine.Option(names = {"--help"}, usageHelp = true, description = "show help message and exit")
    public static Boolean help = false;

    // 布尔选项，hidden = true设置选项不显示到help信息中
    @CommandLine.Option(names = {"-e", "--exec"}, hidden = true, description = {"perform the update operation instead of checking"})
    public static Boolean exec = false;

  	// 位置参数，使用index属性来准确指定要捕获的参数
    @CommandLine.Parameters(index = "0...*", description = "src & dst file relative path if single operation, otherwise, local file absolute path")
    private static List<String> params;

    static class FileOrDirectoryExclusiveOption {
        @CommandLine.Option(names = {"-f", "--file"}, description = {"rename file"})
        public static Boolean file = false;

        @CommandLine.Option(names = {"-d", "--directory"}, description = {"rename directory"})
        public static Boolean directory = false;
    }

    @Override
    public Integer call() throws Exception {
				// 业务逻辑...
        return 1;
    }
  
  	public static void main(String[] args) {
      	int exitCode = new CommandLine(new RenameCommand()).execute(args);
      	System.exit(exitCode);
    }
}
```



