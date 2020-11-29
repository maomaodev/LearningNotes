## 1. 并发 List

### 1.1 CopyOnWriteArrayList

### 1.1.1 简介

并发包中的并发 List 只有 `CopyOnWriteArrayList`，它是一个**线程安全的 `ArrayList`**。所谓 `CopyOnWrite` 就是说：在计算机，如果你想要对一块内存进行修改时，我们不在原有内存块中进行写操作，而是将内存拷贝一份，在新的内存中进行写操作，写完之后呢，就将指向原来内存指针指向新的内存，原来的内存就可以被回收掉了。

```java
public class CopyOnWriteArrayList<E>
    implements List<E>, RandomAccess, Cloneable, java.io.Serializable  {
    // 独占锁，用来保证同时只有一个线程对array进行修改
    final transient ReentrantLock lock = new ReentrantLock();

    // 存放具体元素的数组，只能通过getArray、setArray方法访问
    private transient volatile Object[] array;
    
    // 无参构造函数，默认创建一个大小为0的Object数组
    public CopyOnWriteArrayList() {
        setArray(new Object[0]);
    }
}
```



### 1.1.2 源码解析

1. **add 操作**

   ```java
   	public boolean add(E e) {
       	// 1.获取独占锁
           final ReentrantLock lock = this.lock;
           lock.lock();
           try {
               // 2.获取array数组
               Object[] elements = getArray();
               // 3.复制array到新数组，添加新元素到新数组（长度加1，无界list）
               int len = elements.length;
               Object[] newElements = Arrays.copyOf(elements, len + 1);
               newElements[len] = e;
               // 4.使用新数组替换原来的数组
               setArray(newElements);
               return true;
           } finally {
               // 5.释放独占锁
               lock.unlock();
           }
       }
   ```

   `CopyOnWriteArrayList` 的添加、修改、删除元素的原理是类似的，都是通过创建底层数组的新副本来实现的。首先获取独占锁以保证其它线程不能对 array 进行修改，然后对原有数组进行一次复制，将修改的内容写入副本，之后再将修改完的副本替换原来的数组。

2. **get 操作**

   ```java
   	public E get(int index) {
           return get(getArray(), index);
       }
   
   	// 步骤1
   	final Object[] getArray() {
           return array;
       }
   
   	// 步骤2
   	private E get(Object[] a, int index) {
           return (E) a[index];
       }
   ```

   由于步骤 1 和步骤 2 没有加锁，这就可能导致在线程 X 执行完步骤 1 后执行步骤 2 前，另外一个线程 Y 进行了 remove 操作，该操作最后会将 array 指向复制后的新数组，这时线程 X 开始执行步骤 2，但是此时操作的数组仍然是线程 Y 删除元素之前的老数组。这就是写时**复制策略**产生的弱一致性问题。

3. **迭代器**

   ```java
   	public Iterator<E> iterator() {
           return new COWIterator<E>(getArray(), 0);
       }
   
   	static final class COWIterator<E> implements ListIterator<E> {
           // array的快照版本
           private final Object[] snapshot;
           // 遍历时的数组下标
           private int cursor;
   
           private COWIterator(Object[] elements, int initialCursor) {
               cursor = initialCursor;
               snapshot = elements;
           }
   
           public boolean hasNext() {
               return cursor < snapshot.length;
           }
   
           @SuppressWarnings("unchecked")
           public E next() {
               if (! hasNext())
                   throw new NoSuchElementException();
               return (E) snapshot[cursor++];
           }
       }
   ```

   为什么说 snapshot 是 list 的快照呢？明明是指针传递的引用，而不是副本。这其实和 get 操作是类似的，因为**增删改后 list 里面的数组被新数组替换了，这时候老数组被 snapshot 引用**。因此，使用该迭代器元素时，其它线程对 list 的修改是不可见的，因为它们操作的是两个不同的数组，这就是弱一致性。



### 1.1.3 总结

`CopyOnWriteArrayList` 使用**写时复制**的策略来保证 list 的一致性，即对其进行的**增、删、改操作都是在底层的一个复制的数组（快照）上进行的**，由于获取-修改-写入三步操作并不是原子性的，所以使用了独占锁来保证某个时刻只有一个线程能对 list 数组进行修改。

`CopyOnWriteArrayList` 的**读取操作没有进行加锁同步**，且写入也不会阻塞读取操作，这样读操作的性能就得到了大幅度提升，但会存在弱一致性问题。`CopyOnWriteArrayList` 还提供了**弱一致性的迭代器**，从而保证在获取迭代器后，其它线程对 list 的修改是不可见的，迭代器遍历的数组是一个快照。另外，`CopyOnWriteArraySet` 的底层是使用 `CopyOnWriteArrayList` 实现的。



## 2. 并发 Queue

### 2.1 ConcurrentLinkedQueue



### 2.2 LinkedBlockingQueue



### 2.3 ArrayBlockingQueue



### 2.4 PriorityBlockingQueue



### 2.5 DelayQueue





## 3. 并发 Map

### 3.1 ConcurrentHashMap



