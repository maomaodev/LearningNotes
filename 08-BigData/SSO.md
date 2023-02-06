# 1. CAS

## 1.1 CAS 简介

单点登录（Single Sign On，SSO）是一种身份验证方案，允许用户使用单个 ID 登录到多个相关但独立的软件系统中的任何一个。中央认证服务（Central Authentication Service，CAS） 是一种独立开放指令协议，它是耶鲁大学发起的一个开源项目，旨在为 Web 应用系统提供一种可靠的单点登录方法。

CAS 系统架构由服务端和客户端组成，它们通过各种协议进行通信。CAS Server 需要独立部署，主要负责对用户的认证工作，授予用户访问权限。CAS Client 负责处理对客户端受保护资源的访问请求，需要登录时重定向到 CAS Server。

![CAS架构](./images/SSO/CAS架构.png)

## 1.2 







# 2. Kerberos

## 2.1 Kerberos 基本原理

1. **Master Key 与 Session Key**

   Kerberos 是一种计算机网络授权协议，用于在非安全网络中，对个人通信以安全的手段进行身份认证。首先给出两个重要概念：

   * **Long-term Key/Master Key**：在安全领域中，有的 Key 可能长期内保持不变，这样的 Key 以及由此派生的 Key 被称为 Long-term Key。对于 Long-term Key 的使用有这样的原则：**被 Long-term Key 加密的数据不应该在网络上传输**，因为一旦这些被 Long-term Key 加密的数据包被恶意的网络监听者截获，在原则上，只要有充足的时间，就可以通过计算获得用于加密的 Long-term Key，任何加密算法都不可能做到绝对保密。

     在一般情况下，对一个 Account 来说，密码往往仅限于该 Account 的所有者知晓，甚至对于任何域的 Administrator，密码仍然应该是保密的。但是密码却又是证明身份的凭据，所以必须通过基于密码的派生信息来证明用户的真实身份。在这种情况下，一般将密码进行 Hash 运算得到一个 Hash code，一般将这样的 Hash Code 叫做 Master Key。由于 Hash Algorithm 是不可逆的，这样既保证了密码的保密性，同时保证 Master Key 和密码本身在证明身份时具有相同的效力。

   * **Short-term Key/Session Key**：由于被 Long-term Key 加密的数据包不能用于网络传送，所以我们**使用另一种 Short-term Key 来加密**。由于**这种 Key 只在一段时间内有效**，即使被加密的数据包被黑客截获，等把 Key 计算出来，这个 Key 早就已经过期了。

2. **Key Distribution Center（KDC）**

   为了让 Client 和 Server 获得 Short-term Key，需要引入另一个重要角色：Key Distribution Center（KDC）。KDC 是 Client 和 Server 共同信任的第三方，它**持有一个密钥数据库**，每个网络实体，无论是客户端还是服务器，共享一套只有他自己和 KDC 知道的密钥，密钥的内容用于证明实体的身份。也就是说，**KDC 知道每个 Account 的名称和派生于该 Account Password 的 Master Key，而用于 Client 和 Server 相互认证的 Short-term Key 就由 KDC 分发**。

   Client 和 Server 间的 Session Key 称为 S<sub>C-S</sub>，KDC 分发 S<sub>C-S</sub> 的简单过程如下：首先 Client 向 KDC 发送对 S<sub>C-S</sub> 的申请，该申请的内容可以简单概括为“我是某个Client，我需要一个 Session Key 用于访问某个 Server ”。KDC 在接收到这个请求时，生成一个 Session Key，**为了保证这个 Session Key 仅限于发送请求的 Client 和它希望访问的 Server 知晓，KDC 会为这个 Session Key 生成两个 Copy，分别被 Client 和 Server 使用**。然后从密钥数据库中提取 Client 和 Server 的 Master Key 分别对这两个 Copy 进行对称加密。对于后者，和 Session Key 一起被加密的还包含 Client 的一些信息。

   KDC 现在有了两个分别被 Client 和 Server 的 Master Key 加密过的 Session Key，这两个 Session Key 如何分别被 Client 和 Server 获得呢？也许你会说，KDC 直接将这两个加密过的包发送给 Client 和 Server 不就可以了吗，但是如果这样做，对于 Server 来说会出现下面 两个问题：

   * 由于一个 Server 会面对若干不同的 Client，而每个 Client 都具有一个不同的 Session Key。那么 Server 就会为所有的 Client 维护这样一个 Session Key 的列表，这样做对于 Server 来说是比较麻烦而低效的。
   * 由于网络传输的不确定性，可能出现这样一种情况：Client 很快获得 Session Key，并将这个 Session Key 作为 Credential 随同访问请求发送到 Server，但是用于 Server 的 Session Key 却还没有收到，并且有可能这个 Session Key 永远也到不了 Server 端，Client 将永远得不到认证。

   **为了解决这个问题，Kerberos 将这两个被加密的 Copy 一并发送给 Client，属于 Server 的那份由 Client 发送给 Server**。

3. **Authenticator**

   通过上面的过程，Client 实际上获得了两组信息：一个通过自己 Master Key 加密的 Session Key，另一个通过 Server 的 Master Key加密的数据包，包含 Session Key 和关于自己的一些确认信息。在网络的环境中，通过一个双方都知晓的 Key 对对方进行认证的做法仍然是有安全漏洞的，为此，**Client 需要提供更多的证明信息，这种证明信息称为 Authenticator，Kerberos 的 Authenticator 实际上就是关于 Client 的一些信息和当前时间的时间戳 Timestamp**。在此基础上，Server 对 Client 的认证过程如下：

   * Client 通过自己的 Master Key 对 KDC 加密的 Session Key 进行解密，从而获得 Session Key。随后创建 Authenticator（**Client Info + Timestamp**），用 Session Key 对其加密。最后连同从 KDC 获得的、被 Server 的 Master Key 加密过的数据包（**Client Info + Session Key**）一并发送到 Server 端，我们把通过 Server 的 Master Key 加密过的数据包称为 Session Ticket。
   * 当 Server 接收到这两组数据后，先使用自己的 Master Key 对 Session Ticket 进行解密，从而获得 Session Key。随后使用该 Session Key 解密 Authenticator，通过比较 Authenticator 中的 Client Info 和 Session Ticket 中的 Client Info，从而实现对 Client 的认证。

   假设 Client 向 Server发送的数据包被某个恶意网络监听者截获，该监听者随后将数据包作为自己的 Credential 冒充该 Client 对 Server 进行访问，在这种情况下，依然可以很顺利地获得 Server 的认证。为此，Client 在 Authenticator 中会加入当前时间戳 Timestamp。

   **在 Server 对 Authenticator 中的 Client Info 和 Session Ticket 中的 Client Info 进行比较之前，会先提取 Authenticator 中的 Timestamp，并同当前的时间进行比较，如果他们之间的偏差超出一个可以接受的时间范围，Server 会直接拒绝该 Client 的请求**。在这里需要知道的是，Server 维护着一个列表，这个列表记录着在这个可接受的时间范围内所有进行认证的 Client 和认证的时间。对于时间偏差在这个可接受的范围中的 Client，Server 会从这个这个列表中获得最近一个该Client的认证时间，只有当 Authenticator 中的 Timestamp 晚于通过 Client 的最近的认证时间的情况下，Server 才进行后续的认证流程。**上述基于时间戳的认证机制只有在 Client 和 Server 的时间保持同步才有意义**。

4. **双向认证 Mutual Authentication**

   Kerberos 的一个重要优势在于它能够提供双向认证：不但 Server 可以对 Client 进行认证，Client 也能对 Server 进行认证。具体过程如下：如果 Client 需要对它访问的 Server 进行认证，会在它向 Server 发送的 Credential 中设置一个是否需要认证的 Flag。Server 在对 Client 认证成功之后，会把 Authenticator 中的 Timestamp 提出来，通过 Session Key 进行加密。当 Client 接收到并使用 Session Key 进行解密之后，如果确认 Timestamp 和原来完全一致，那么就可以认定 Server 正是它试图访问的 Server。

   那么为什么 Server 不直接把通过 Session Key 进行加密的 Authenticator 原样发送给 Client，而要把 Timestamp 提取出来加密发送给 Client 呢？原因在于防止恶意的监听者通过获取 Client 发送的 Authenticator，冒充 Server 获得 Client 的认证。



## 2.2 Kerberos 认证流程

下面是对协议的一个简化描述，将使用以下缩写：

- KDC（Key Distribution Center）= 密钥分发中心
- AS（Authentication Server）= 认证服务器
- TGT（Ticket Granting Ticket）= 票据授权票据，票据的票据
- TGS（Ticket Granting Server）= 票据授权服务器
- SS（Service Server）= 特定服务提供端

用户输入用户 ID 和密码到客户端，客户端程序运行一个单向函数把密码转换成密钥，这个就是客户端（用户）的“用户密钥”。接下来 Kerberos 认证流程如下：

1. **客户端认证（Client 从 AS 获取 TGT）**
   * 客户端向 AS 发送 1 条明文消息，申请所应享有的服务（注意，用户不向 AS 发送“用户密钥 K<sub>C</sub>”，也不发送密码），AS 能从本地数据库中查询到该用户的密码，并通过相同途径转换成相同的“用户密钥 K<sub>C</sub>”。
   * AS 检查该用户 ID 是否在于本地数据库中，如果用户存在则返回 2 条消息：
     - 消息 A：**Client/TGS 会话密钥 K<sub>C-TGS</sub>（用于将来 Client 与 TGS 通信会话上），通过“用户密钥 K<sub>C</sub>”进行加密**
     - 消息 B：**TGT（包括：K<sub>C-TGS</sub>、用户ID、用户网址、TGT 有效期），通过“TGS密钥 K<sub>TGS</sub>”进行加密**
   * 客户端收到消息 A 和 B，首先尝试用自己的“用户密钥 K<sub>C</sub>”解密消息 A，如果用户输入的密码与 AS 数据库中的密码不符，则不能成功解密消息 A。输入正确的密码并通过随之生成的“用户密钥 K<sub>C</sub>”才能解密消息 A，从而得到“Client/TGS 会话密钥 K<sub>C-TGS</sub>”。（注意，**客户端不能解密消息 B**，因为 B 是用“TGS 密钥 K<sub>TGS</sub>”加密的）。
2. **服务授权（Client 从 TGS 获取票据 client-to-server ticket）**
   * 当客户端需要申请特定服务时，向 TGS 发送以下 2 条消息：
     - 消息 C：**消息 B 的内容（即使用“TGS 密钥 K<sub>TGS</sub>”加密的 TGT）和想获取的服务的服务 ID**
     - 消息 D：**认证符 Authenticator（Authenticator 包括：用户ID、时间戳），通过“Client/TGS 会话密钥 K<sub>C-TGS</sub>”进行加密**
   * TGS 收到消息 C 和 D 后，首先检查 KDC 数据库中是否存在所需的服务，找到之后，TGS 用自己的“TGS 密钥 K<sub>TGS</sub>”解密消息 C 中的消息 B（即 TGT），从而得到之前生成的“Client/TGS 会话密钥 K<sub>C-TGS</sub>”。TGS再用这个会话密钥解密消息 D，得到包含用户 ID 和时间戳的 Authenticator，并对 TGT 和 Authenticator进行验证，验证通过之后返回 2 条消息：
     - 消息 E：**客户端-服务器票据 client-to-server ticket（包括：“Client/SS 会话密钥 K<sub>C-S</sub>”、用户ID、用户网址、有效期），通过提供该服务的“服务器密钥 K<sub>S</sub>”进行加密**
     - 消息 F：**Client/SS 会话密钥 K<sub>C-S</sub>（该会话密钥用在将来客户端与SS的通信（会话）上），通过“Client/TGS 会话密钥 K<sub>C-TGS</sub>”进行加密**
   * 客户端收到这些消息后，用“Client/TGS 会话密钥 K<sub>C-TGS</sub>”解密消息 F，得到“Client/SS会话密钥 K<sub>C-S</sub>”。（注意，**客户端不能解密消息 E**，因为 E 是用“服务器密钥 K<sub>S</sub>”加密的）。
3. **服务请求（Client 从 SS 获取服务）**
   * 获得“Client/SS 会话密钥 K<sub>C-S</sub>”后，客户端就能使用服务器提供的服务了，向指定 SS 发出 2 条消息：
     - 消息 E：**即上一步中的消息E“客户端-服务器票据”，已通过“服务器密钥 K<sub>S</sub>”进行加密**
     - 消息 G：**新的 Authenticator（包括用户ID、时间戳），通过“Client/SS 会话密钥 K<sub>C-S</sub>”进行加密**
   * SS 用自己的“服务器密钥 K<sub>S</sub>”解密消息 E，从而得到 TGS 提供的“Client/SS 会话密钥 K<sub>C-S</sub>”。再用这个会话密钥解密消息 G，得到 Authenticator，对票据和 Authenticator 进行验证，验证通过则返回 1 条消息：
     - 消息 H：**新时间戳（客户端发送的时间戳加1，v5 已取消这一做法），通过“Client/SS 会话密钥 K<sub>C-S</sub>”进行加密**
   * 客户端通过“Client/SS 会话密钥 K<sub>C-S</sub>”解密消息 H，得到新时间戳并验证其是否正确。验证通过的话则客户端可以信赖 SS，并向 SS 发送服务请求。
   * SS 向客户端提供相应的服务。

![Kerberos协议流程](./images/SSO/Kerberos协议流程.png)

1. Kerberos 优点：
   * 较高的性能：虽然 Kerberos 涉及到三方的认证过程，但是一旦 Client 获得用于访问某个 Server 的 Ticket，该 Server 就能根据这个 Ticket 实现对 Client 的验证，而无须 KDC 的再次参与。
   * 实现双向验证：Client 在访问 Server 的资源之前，可以要求对 Server 的身份执行认证。

2. Kerberos 缺点：
   * 单点故障：它需要中心服务器的持续响应。当 Kerberos 服务宕机时，没有人可以连接到服务器，这个缺陷可以通过使用复合 Kerberos 服务器和缺陷认证机制弥补。
   * Kerberos 要求参与通信的主机的时钟同步。票据具有一定有效期，因此，如果主机的时钟与 Kerberos 服务器的时钟不同步，认证会失败。默认设置要求时钟的时间相差不超过 10 分钟。在实践中，通常用网络时间协议后台程序来保持主机时钟同步。
   * 管理协议并没有标准化，在服务器实现工具中有一些差别。
   * 因为所有用户使用的密钥都存储于中心服务器中，危及服务器的安全的行为将危及所有用户的密钥。
   * 一个危险客户机将危及用户密码。



## 2.3 Hadoop Kerberos 认证







# 参考

1. [kerberos-维基百科](https://zh.wikipedia.org/wiki/Kerberos)
2. [kerberos-博客](https://www.cnblogs.com/artech/archive/2007/07/05/807492.html)

