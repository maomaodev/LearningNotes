## 1. String IOC

### 1.1 IOC 容器

在 Spring 中把每一个需要管理的对象称为 Spring Bean（简称 Bean），而 **Spring IOC 容器（简称 IOC 容器）则是一个管理 Bean 的容器**。所有的 IOC 容器都需要实现接口 `BeanFactory`，它是一个顶级容器接口，其源码如下：

```java
public interface BeanFactory {
    // 前缀
    String FACTORY_BEAN_PREFIX = "&";

    // 多个getBean方法，可以按照“名称”或“类型”来获取Bean
    Object getBean(String var1) throws BeansException;

    <T> T getBean(String var1, @Nullable Class<T> var2) throws BeansException;

    Object getBean(String var1, Object... var2) throws BeansException;

    <T> T getBean(Class<T> var1) throws BeansException;

    <T> T getBean(Class<T> var1, Object... var2) throws BeansException;

    // 是否包含Bean
    boolean containsBean(String var1);

    // Bean是否单例，默认单例，即返回同一个对象
    boolean isSingleton(String var1) throws NoSuchBeanDefinitionException;

    // Bean是否原型
    boolean isPrototype(String var1) throws NoSuchBeanDefinitionException;

    // 是否类型匹配
    boolean isTypeMatch(String var1, ResolvableType var2) throws NoSuchBeanDefinitionException;

    boolean isTypeMatch(String var1, @Nullable Class<?> var2) throws NoSuchBeanDefinitionException;

    // 获取Bean的类型
    @Nullable
    Class<?> getType(String var1) throws NoSuchBeanDefinitionException;

    // 获取Bean的别名
    String[] getAliases(String var1);
}
```

由于 `BeanFactory` 的功能还不够强大，因此设计了一个更为高级的接口 `ApplicationContext`，它是 `BeanFactory` 的子接口之一，两者都作为核心容器，其区别是：

- `ApplicationContext`：它在构建核心容器时，创建对象采取的策略是**立即加载**。也就是说，只要一读取完配置文件马上就创建配置文件中配置的对象。因此它适用于**单例对象**，且实际开发使用更多
- `BeanFactory`：它在构建核心容器时，创建对象采取的策略是**延迟加载**。也就是说，什么时候根据 id 获取对象了，什么时候才真正的创建对象。因此它适用于**多例对象**

`ApplicationContext` 的常用实现类有 3 个：

* `ClassPathXmlApplicationContext`：它可以加载类路径下的配置文件，要求配置文件必须在类路径下
* `FileSystemXmlApplicationContext`：它可以加载磁盘任意路径下的配置文件，但必须有访问权限
* `AnnotationConfigApplicationContext`：它可以读取注解创建容器



### 1.2 Bean

1. **Bean 的生命周期**

   * 单例对象：（出生）当容器创建时对象出生；（活着）只要容器还在，对象一直活着；（死亡）容器销毁，对象消亡；（总结）单例对象的生命周期和容器相同
   * 多例对象：（出生）当我们使用对象时 Spring 框架为我们创建；（活着）对象只要是在使用过程中就一直活着；（死亡）当对象长时间不用，且没有别的对象引用时，由 Java 的垃圾回收器回收

2. **Bean 的作用范围**

   |  作用域类型   |     使用范围     |   作用域描述   |
   | :-----------: | :--------------: | :------------: |
   |   singleton   | 所有 Spring 应用 |  默认值，单例  |
   |   prototype   | 所有 Spring 应用 |      多例      |
   |    session    | Spring web 应用  |   HTTP 会话    |
   |    request    | Spring web 应用  |    单次请求    |
   | globalSession | Spring web 应用  | 集群环境的会话 |

   

3. **依赖注入**

   * IOC 的作用是降低程序间的耦合（依赖关系），从而将依赖关系的管理交由 Spring 来维护。Bean 之间依赖关系的维护称为依赖注入（Dependency Injection，DI）。



### 1.3 IOC 注解

1. **@Configuration**
   * 作用：指定当前类是一个配置类，Spring 容器会根据它来生成 IOC 容器去装配 Bean
   * 其它：当配置类作为AnnotationConfigApplicationContext 对象创建的参数时，该注解可以不写
2. **@Bean**
   * 作用：把**当前方法的返回值**作为 Bean 对象存入 IOC 容器中
   * 属性：name 用于指定 Bean 的 id，当不写时，默认值是当前方法的名称
   * 其它：当使用注解配置方法时，如果方法有参数，Spring 会去容器中查找有没有可用的 Bean 对象
3. **@Component**
   * 作用：把**当前的类对象**存入 IOC 容器中，相当于 XML 配置文件中的\<bean\>标签
   * 属性：value 用于指定 Bean 的 id，当不写时，默认值是当前类名，且首宇母改小写
   * 其它：**@Controller、@Service、@Repository**，以上三个注解的作用和属性与 @Component 是一样的，分别用于表现层、业务层和持久层，是 Spring 为我们提供明确的三层使用的注解，使我们的三层对象更加清晰
4. **@ComponentScan**
   - 作用：指定 Spring 在创建容器时要扫描的包
   - 属性：value 和 basePackages（别名）的作用是一样的，都是用于指定创建容器时要扫描的包，包名可以使用正则表达式。basePackageClasses 用于指定要扫描的类。includeFilters 和 excludeFilters 分别用于指定满足、排除过滤条件的 Bean，需要通过 @Filter 定义。lazyInit 用于指定是否延迟初始化。
   - 其它：
5. **@Autowired**
   - 作用：自动按照**属性的类型**找到对应的 Bean 进行注入。
   - 其它：首先它会根据类型找到对应的 Bean ，如果对应类型的 Bean 不是唯一的，那么它会根据其属性名称和 Bean 的名称进行匹配。如果匹配得上，就使用该 Bean，否则抛出异常。**当构造方法带有参数**，则可以使用该注解对构造方法的参数进行注入。
6. **@Qualifier**
   - 作用：与 @Autowired 组合使用，不能单独使用，按照**属性的类型和名称**找到对应的 Bean 进行注入。
   - 属性：value 用于指定 Bean 的 id
   - 其它：
7. **@Resource**
   - 作用：可以单独使用，直接按照**属性的名称**找到对应的 Bean 进行注入。
   - 属性：name 用于指定 Bean 的id
   - 其它：以上三个注入都只能注入其他 Bean 类型的数据，而基本类型和 String 类型无法使用上述注解实现。另外，集合类型的注入只能通过 XML 来实现。
8. **@Value**
   - 作用：用于注入**基本类型和 String 类型**的数据。
   - 属性：value 用于指定数据的值，它可以使用 Spring 中的 EL 表达式，SpEL 的写法： `${表达式}`
   - 其它：
9. **@Scope**
   - 作用：用于指定 Bean 的作用范围
   - 属性：value 指定范围的取值，常用取值：singleton（单例）、prototype（多例）
   - 其它：



## 2. Spring AOP

### 2.1 AOP 术语

1. 连接点（join point）：对应的是具体被拦截的对象，因为 Spring 只能支持方法，所以被拦截的对象往往就是指特定的方法
2. 切点（point cut）：有时候，我们的切面不单单应用于单个方法，也可能是多个类的不同方法，这时可以通过正则式和指示器的规则去定义，从而适配连接点。切点就是提供这样一个功能的概念
3. 通知（advice）：就是按照约定的流程下的方法，分为前置通知、后置通知、环绕通知、最终通知、异常通知，它会根据约定织入流程中
4. 目标对象（target）：即被代理的对象
5. 引入（introduction）：指引入新的类和其方法，增强现有 Bean 的功能
6. 织入（weaving）：它是一个通过动态代理技术，为原有服务对象生成代理对象，然后将与切点定义匹配的连接点拦截，并按约定将各类通知织入约定流程的过程
7. 切面（aspect）：是一个可以定义切点、各类通知和引入的内容，Spring AOP 将通过它的信息来增强 Bean 的功能或将对应的方法织入流程



### 2.2 动态代理



### 2.3 AOP 注解

1. **@Aspect**

   - 作用：表示当前类是一个切面类
   - 其它：

2. **@Pointcut**

   - 作用：用来定义切点，它标注在方法 pointCut 上

   - 属性：value 指定切入点表达式，该表达式的含义指的是对业务层中哪些方法增强

   - 其它：切入点表达式的写法 `execution(访问修饰符 返回值 包名.包名.包名...类名.方法名(参数列表))`

     > 标准的表达式写法：public void com.service.impl.AccountServiceImpl.saveAccount()
     >
     > 访问修饰符可以省略：void com.service.impl.AccountServiceImpl.saveAccount()
     >
     > 返回值可以使用通配符，表示任意返回值：\* com.service.impl.AccountServiceImpl.saveAccount()
     >
     > 包名可以使用..表示当前包及其子包：\* \*..AccountServiceImpl.saveAccount()
     >
     > 包名可以使用通配符，表示任意包。但是有几级包，就需要写几个\*
     >
     > 类名和方法名都可以使用\*来实现通配：\* \*..\*.\*()
     >
     > 参数列表：基本类型直接写名称，引用类型写包名类名的方式，可以使用通配符表示任意类型，但是必须有参数，可以使用..表示有无参数均可，有参数可以是任意类型
     >
     > 全通配写法：\* *..*.\*(..)
     >
     > 实际开发中的通常写法：切到业务层实现类下的所有方法，即\* com.service.impl.*.*(..)

3. **@Before、@AfterReturning、@AfterThrowing、@AfterReturning、@Around**

   - 作用：前置通知、后置通知、异常通知、最终通知、环绕通知
   - 其它：spring 基于注解的后置通知和最终通知有顺序问题，此时可以使用环绕通知

4. **@DeclareParents**

   - 作用：用于引入新的类来增强服务
   - 属性：value 指定要增强功能的目标对象，defaultImpl 引入增强功能的类
   - 其它：

5. 





## 3. Bean 的生命周期

在传统的 Java 应用中，Bean 的生命周期很简单，使用 Java 关键字 new 进行 Bean 的实例化，然后该 Bean  就能够使用了。一旦 Bean 不再被使用，则由 Java 自动进行垃圾回收。相比之下，Spring 管理 Bean 的生命周期就复杂多了，正确理解 Bean 的生命周期非常重要，因为 Spring 对 Bean 的管理可扩展性非常强，下面展示了一个 Bean 的构造过程：

![Bean生命周期](./images/Spring/Bean生命周期.jpg)

1. Spring 启动，查找并加载需要被 Spring 管理的 Bean，进行 Bean 的实例化
2. Bean 实例化后对将 Bean 的引入和值注入到 Bean 的属性中
3. 如果 Bean 实现了 BeanNameAware 接口，Spring 将 Bean 的 Id 传递给 setBeanName() 方法
4. 如果 Bean 实现了BeanFactoryAware 接口，Spring 将调用 setBeanFactory() 方法，将 BeanFactory 容器实例传入
5. 如果Bean实现了 ApplicationContextAware 接口，Spring 将调用 Bean 的 setApplicationContext() 方法，将 bean 所在应用上下文引用传入进来。
6. 如果 Bean 实现了 BeanPostProcessor 接口，Spring 就将调用他们的 postProcessBeforeInitialization() 方法
7. 如果 Bean 实现了 InitializingBean 接口，Spring 将调用他们的 afterPropertiesSet() 方法。类似的，如果 Bean 使用 init-method 声明了初始化方法，该方法也会被调用
8. 如果 Bean 实现了 BeanPostProcessor 接口，Spring 就将调用他们的 postProcessAfterInitialization() 方法
9. 此时，Bean 已经准备就绪，可以被应用程序使用了。他们将一直驻留在应用上下文中，直到应用上下文被销毁
10. 如果 Bean 实现了 DisposableBean 接口，Spring 将调用它的 destory() 接口方法，同样，如果 Bean 使用了 destory-method 声明销毁方法，该方法也会被调用

```java
public class Book implements BeanNameAware, BeanFactoryAware,
        ApplicationContextAware, InitializingBean, DisposableBean {
    private String bookName;
            
    public String getBookName() {
        return bookName;
    }       

    public Book(){
        System.out.println("Bean实例化");
    }

    public void setBookName(String bookName) {
        this.bookName = bookName;
        System.out.println("Bean属性注入");
    }

    @Override
    public void setBeanName(String name) {
        System.out.println("调用BeanNameAware的setBeanName()方法");
    }

    @Override
    public void setBeanFactory(BeanFactory beanFactory) throws BeansException {
        System.out.println("调用BeanFactoryAware的setBeanFactory()方法");
    }

    @Override
    public void setApplicationContext(ApplicationContext applicationContext) throws BeansException {
        System.out.println("调用ApplicationContextAware的setApplicationContext()方法");
    }

    @Override
    public void afterPropertiesSet() {
        System.out.println("调用InitializingBean的afterPropertiesSet()方法");
    }

    public void myPostConstruct(){
        System.out.println("调用自定义初始化方法");
    }

    @Override
    public void destroy() {
        System.out.println("调用DisposableBean的destroy()方法");
    }

    public void myPreDestroy(){
        System.out.println("调用自定义销毁方法");
    }
}
```

自定义实现 BeanPostProcessor 的 MyBeanPostProcessor：

```java
public class MyBeanPostProcessor implements BeanPostProcessor {
    @Override
    public Object postProcessBeforeInitialization(Object bean, String beanName) throws BeansException {
        if(bean instanceof Book){
            System.out.println("调用BeanPostProcessor的预初始化方法");
        }
        return bean;
    }

    @Override
    public Object postProcessAfterInitialization(Object bean, String beanName) throws BeansException {
        if(bean instanceof Book){
            System.out.println("调用BeanPostProcessor的初始化后方法");
        }
        return bean;
    }
}
```

做一个启动测试类，新建 SpringBeanLifecycleApplication：

```java
public class SpringBeanLifecycleApplication {
    public static void main(String[] args) throws InterruptedException {
        ClassPathXmlApplicationContext context = new ClassPathXmlApplicationContext("Bean-Lifecycle.xml");
        Book book = (Book)context.getBean("book");
        System.out.println("Bean可以使用了，book = " + book.getBookName());
        context.destroy();
    }
}
```

在 resources 目录下新建 Bean-Lifecycle.xml：

```xml
<beans xmlns="http://www.springframework.org/schema/beans"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xmlns:context="http://www.springframework.org/schema/context"
       xsi:schemaLocation="http://www.springframework.org/schema/beans
http://www.springframework.org/schema/beans/spring-beans-2.5.xsd http://www.springframework.org/schema/context http://www.springframework.org/schema/context/spring-context.xsd">

    <!-- 扫描bean -->
    <context:component-scan base-package="com.bean.lifecycle"/>

    <!-- 实现了用户自定义初始化和销毁方法 -->
    <bean id="book" class="com.bean.lifecycle.Book" init-method="myPostConstruct" destroy-method="myPreDestroy">
        <!-- 注入bean 属性名称 -->
        <property name="bookName" value="thinking in java" />
    </bean>

    <!-- 引入自定义的BeanPostProcessor -->
    <bean class="com.bean.lifecycle.MyBeanPostProcessor"/>
</beans>
```

结果输出如下：

```
Bean实例化
Bean属性注入
调用BeanNameAware的setBeanName()方法
调用BeanFactoryAware的setBeanFactory()方法
调用ApplicationContextAware的setApplicationContext()方法
调用BeanPostProcessor的预初始化方法
调用InitializingBean的afterPropertiesSet()方法
调用自定义初始化方法
调用BeanPostProcessor的初始化后方法
Bean可以使用了，book = thinking in java
调用DisposableBean的destroy()方法
调用自定义销毁方法
```

参考：[深究Spring中Bean的生命周期](https://www.cnblogs.com/javazhiyin/p/10905294.html)