<title>一文理解Embedding</title>

<blockquote><ul><li>培训录播：<cite doc-id="EC7HdTuXxoAUSYxWhwrcQK3Rnom" file-type="docx" title="【LLM 系列培训】一文彻底理解 Embedding 2024年5月22日" type="doc"></cite></li><li>系列分享培训参考 <a href="https://bytedance.larkoffice.com/share/base/view/shrcnl6NlzrptN6RbHenfiABbqd">LLM  系列培训分享 - 排课表</a> 了解过往录屏及后续计划，有兴趣同学可加入<a href="https://applink.larkoffice.com/client/chat/chatter/add_by_link?link_token=b4dj1be3-4375-4371-82cf-0fb66ed8cca2">飞书群</a>参与。</li></ul></blockquote>

主要讲了一下Embedding是什么，为什么需要Embedding，以及如何生成Embedding。



# 背景简介

众所周知，**计算机无法读懂自然语言，只能处理数值**，但在现实中我们所看到的数据只有两种类型：**数值型、类别型**，以电影为例来说明，电影的风格、演员、导演、标签、分类等信息，这些无法用数字表示的信息全部都可以看作是类别、ID类数据；能用数字直接表示的数据就是数值型数据，类型包括用户的年龄、收入、视频播放时长、点击量、评论量等，那如何将类别型的数据转换成计算机可理解的数值型数据呢，这就需要用到One-Hot编码方式了。



# One-Hot编码介绍

One-Hot编码（又称独热编码）是一种简单而直观的文本表示方法。它的基本思想是将每个单词表示为一个二进制向量，其中向量的长度等于词汇表的大小，而向量中只有一个位置为1，其余位置为0，这个为1的位置对应着该单词在词汇表中的索引。

以星期为例进行说明，一个星期主要由周一、周二、周三、周四、周五、周六、周日组成，我们可以将这7天每一天看作一个类别，而这些类别又组成了一个词汇表，词汇表结构如下所示：

| 索引号 | 词汇 |
|-|-|
| 0 | 周一 |
| 1 | 周二 |
| 2 | 周三 |
| 3 | 周四 |
| 4 | 周五 |
| 5 | 周六 |
| 6 | 周日 |

One-Hot编码即是将上面的词汇表转换成下面这种样式：

| 周一 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
|-|-|-|-|-|-|-|-|
| 周二 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| ... | ... | ... | ... | ... | ... | ... | ... |
| 周六 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |
| 周日 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |

那么“周一”即可表示为向量[1,0,0,0,0,0,0]，依次类推“周日”可表示为向量[0,0,0,0,0,0,1]。



说白了就是，词汇表有多少种数据，那么就用多少位二进制表示，所以可以看到，这种编码方法只适用于可枚举完的特征，对于连续特征没法完全枚举的，这个时候需要灵活处理下，比如对某个范围内的数当成一个值。



One-Hot编码的优点是**简单易懂，易于实现**。然而，它也存在一些明显的缺点。首先，One-Hot编码产生的向量是**稀疏**的，即向量中大部分元素都是0，这会导致计算效率低下。其次，One-Hot编码**无法捕捉单词之间的语义关系**，即使两个单词在语义上非常相似，它们的One-Hot编码也是完全不相关的。





# 什么是Embedding

Embedding是一种将离散型变量（如单词）转化为连续型向量的方式。这种向量能够捕捉到**单词之间的语义关系**。Embedding 的过程，就是把数据集合映射到向量空间，进而把数据进行向量化的过程。Embedding 的目标，就是找到一组合适的向量，来刻画现有的数据集合，例如相似的单词会被映射到向量空间中的相近位置。



embedding样例：

```JSON
狗 [0.32, 0.54, 2.74, 4.76]
猫 [1.42, 2.47, 1.49, 2.11]
```



例如：给每一个单词一个N维编码向量（或者说将每个词投影到N维空间中），我们期望这种编码满足这样的特性：两个向量之间的”距离“越小，代表这两个单词含义越接近。比如利用 Word2vec 这个模型把单词映射到了高维空间中，从 king 到 queen 的向量和从 man 到 woman 的向量，无论从方向还是尺度来说它们都异常接近。

![图片展示了Word2vec模型将单词映射到高维空间中的示例。左侧“Male-Female”图中，king、man、queen、woman的向量位置接近，且有虚线箭头表示从king到queen、从man到woman的向量方向和尺度相似。右侧“Verb tense”图中，walked、walking、swam、swimming的向量位置也相近，有虚线箭头表示从walked到swam、从walking到swimming的向量方向和尺度相似。这些示例直观呈现了利用Word2vec模型将单词映射到高维空间后，相关单词向量在空间中的分布情况。](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=ZWY2MTM4M2I2YzFhYjJkNTRjODhhODY5MmU0ZjE3Y2NfNGRjNmY0MGQzZGIwZWM1OTE4NTNhMDI5MGNjMGNkMzZfSUQ6NzM2ODM2NzE2MTcyNjc2MzAxMV8xNzg1MTMzOTI1OjE3ODUxMzc1MjVfVjM)







# 如何生成Embedding

生成Embeding的方式有很多：

- Word2Vec
- Glove
- FastText
- Bert

主要讲解一下最经典的Word2Vec，它是由Google的研究员开发的，主要目的是捕捉词汇之间的语义和语法关系。涉及到的模型主要有：连续词袋模型（CBOW）和Skip-gram模型。



**什么是Word2Vec?**

word2vec是词向量化技术的一种，通过神经网络来实现。其在表面上看起来是一种无监督学习技术，但本质上仍然是有监督学习。利用文本的上下文信息构造有监督数据集，通过这一数据集来训练神经网络，最后取训练好的神经网络两个网络层之间的权重矩阵更新后的词向量表（每个单词对应词汇表中的一行数据）。



**Word2Vec模型有哪些？**

连续词袋模型（CBOW）和Skip-gram模型。

- 连续词袋模型（CBOW）：在CBOW模型中，我们尝试预测目标词汇（中心词）基于其上下文（周围的词）。换句话说，我们的模型应该能够根据“我吃了一个\_\_苹果”中的“我，吃，了，一个，苹果”来预测填空处的词是“大”。

<readonly-block type="diagram"></readonly-block>

- Skip-gram模型：Skip-gram模型是CBOW模型的反向。在这个模型中，我们尝试预测上下文（周围的词）基于目标词汇（中心词）。换句话说，我们的模型应该能够从“大”这个词预测出“我，吃，了，一个，苹果”。

<readonly-block type="diagram"></readonly-block>



## CBOW训练数据集

我们通过找常出现在每个单词附近的词，就能获得它们的映射关系。机制如下：

- 先是获取大量文本数据
- 后我们建立一个可以沿文本滑动的窗口(例如一个窗口里包含三个单词)
- 利用这样的滑动窗口就能为训练模型生成大量样本数据。

当这个窗口沿着文本滑动时，我们就能(真实地)生成一套用于模型训练的数据集。为了明确理解这个过程，我们看下滑动窗口是如何处理这个句子的，我们把前两个单词单做特征，第三个单词单做标签:

<readonly-block type="diagram"></readonly-block>

在生成训练数据集时，我们不仅要考虑前两个单词，还需要考虑后两个单词，窗口不断滑动，最终得到的结果是：

| input1 | input2 | input3 | input4 | output |
|-|-|-|-|-|
| - | - | eat | a | I |
| - | I | a | big | eat |
| I | eat | big | apple | a |
| eat | a | apple | every | big |
| a | big | every | day | apple |
| big | apple | day | - | every |
| apple | every | - | - | day |





## Skip-gram训练数据集

Skip-gram不同的是，它不根据上下文(前后单词)来猜测目标单词，而是推测当前单词可能的上下文单词。还是以上面的句子为例进行说明。

<readonly-block type="diagram"></readonly-block>

通过这种方式我们就得到了Skip-gram模型训练数据集。





## Word2Vec训练过程

### 创建词汇表

在训练过程开始之前，我们预先处理我们正在训练模型的文本。在这一步中，我们确定一下词汇表的大小（vocab_size，比如说10,000）以及哪些词被它包含在内。

我们创建两个矩阵——Embedding矩阵和Context矩阵。这两个矩阵在我们的词汇表中嵌入了每个单词（所以vocab_size是他们的维度之一）。第二个维度是我们希望每次嵌入的长度（embedding_size，可以是定义成50或200，取决于最终的训练效果）。

<readonly-block type="diagram"></readonly-block>





### 构造神经网络

由于我们的训练数据集特征数量为4，定义我们的输入层有4个输入单元，输出结果为预测一个单词，定义输出层神经元的个数为7（输出7个单词的概率，取概率最大的一个，假设共有7个词汇），假如我们想要每个单词为一个五维的向量表示，那么我们的隐藏层则为五个神经元。由此，我们可以构建一个输入层为4，隐藏层为5，输出层为7的全连接神经网络，如下图所示：

<readonly-block type="diagram"></readonly-block>





### one-hot编码

假设我们的词汇表中只有上面几个单词，则每个单词对应的one-hot编码如下：

| 单词 | one-hot编码 |
|-|-|
| I | [1, 0, 0, 0, 0, 0, 0] |
| eat | [0, 1, 0, 0, 0, 0, 0] |
| a | [0, 0, 1, 0, 0, 0, 0] |
| ... | ... |
| day | [0, 0, 0, 0, 0, 0, 1] |

通过one-hot编码的结果，就可以直接在词汇表中定位到对应的单词是哪个



### 训练过程

在训练过程开始时，我们随机值初始化这些embedding和context矩阵。然后我们开始训练过程。在每个训练步骤中，我们采取一个相邻的例子及其相关的非相邻例子。

比如想要预测的结果为apple，上下文单词为a、big、every、day，那输入的训练集如下表所示：

| 期望结果 | 上下文 | target |
|-|-|-|
| apple | big | 1 |
| apple | I | 0 |
| apple | eat | 0 |
| ... |  |  |

通过单词one-hot向量可以在Embedding词汇表中找到"apple"对应的初始化向量，"big"、"I"、"eat"通过同样的方式可以在Context词汇表中找到对应的初始化向量，整体流程如下所示：

<readonly-block type="diagram"></readonly-block>

然后，我们计算期望结果的embedding与每个上下文embedding的点积。在每种情况下，结果都将是表示期望结果和上下文嵌入的相似性的数字。

| 期望结果 | 上下文 | 目标 | 点积结果 |
|-|-|-|-|
| apple embedding | I embedding | 0 | -0.22 |
| apple embedding | eat embedding | 0 | 0.34 |
| apple embedding | big embedding | 1 | 0.77 |

现在我们需要一种方法将这些分数转化为看起来像概率的东西——我们需要它们都是正值，并且 处于0到1之间。sigmoid这一逻辑函数转换正适合用来做这样的事情。

| 期望结果 | 上下文 | 目标 | 点积结果 | sigmod() |
|-|-|-|-|-|
| apple embedding | I embedding | 0 | -0.22 | 0.14 |
| apple embedding | eat embedding | 0 | 0.34 | 0.26 |
| apple embedding | big embedding | 1 | 0.77 | 0.65 |

现在我们可以将sigmoid操作的输出视为这些示例的模型输出。可以看到"big"得分最高，"I"最低，无论是sigmoid操作之前还是之后。

既然未经训练的模型已做出预测，而且我们确实拥有真实目标标签来作对比，那么接下来我们就可以通过模型计算预测结果与真实结果的差异。为此我们只需从目标结果减去sigmoid后结果。

| 期望结果 | 上下文 | 目标 | 点积结果 | sigmod() | error |
|-|-|-|-|-|-|
| apple embedding | I embedding | 0 | -0.22 | 0.14 | -0.14 |
| apple embedding | eat embedding | 0 | 0.34 | 0.26 | -0.26 |
| apple embedding | big embedding | 1 | 0.77 | 0.65 | 0.35 |

现在，我们可以利用这个误差来调整big、 I、eat和apple的embedding向量，使我们下一次做出这一计算时，结果会更接近目标分数，我们只需要不断的重复这个过程，不断的通过反向传播更新权重值、通过权重值更新embedding向量，当训练轮次达到最大轮次限制（自己设置的）时，就可以停止训练，丢弃Context矩阵，保留Embedding矩阵，训练出来的Embedding矩阵就可以作为下一项任务的输入来使用了。



### 基于神经网络的训练

整体的训练过程可总结成如下的流程，输入层 -> 隐藏层 -> 输出层 -> 计算概率 -> 计算与真实的差异 -> 反向传播 -> 更新词汇表，不断重复这个过程直至达到最大训练轮次。

![图片展示了基于神经网络的Word2Vec训练过程。输入层为上下文，包含“you say goodbye and i hello”等词汇，对应权重矩阵W_in（7×3）。中间层 addCriterion<qa:image></qa addCriterion addCriterion<qa:image></qa>](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=MDQ2YWE4ZTcwNTA1Y2M1NjFiYTU3MDcxZmI2ZDBmYmVfMGU4NDdmODhkYzQwMTBlY2FiMTAzNjg2NTZkZGYyMTBfSUQ6NzM2ODQ1ODU1NDc4MzEyMTQxMV8xNzg1MTMzOTI1OjE3ODUxMzc1MjVfVjM)



## 思考题

1. 上面仅是CBOW的实现原理，可以思考一下Skip-gram的实现原理，以及两者之间的异同点是什么？
2. 两个不同模型（模型不具有相似性、训练数据集也存在差异）训练出来的embedding可以进行相似度计算吗？

<poll name="可以进行相似度计算吗？"></poll>



# Embedding在大模型上的应用

**Tokenization**

也称作分词，是把一段文本切分成模型能够处理的token或子词的过程，将token或子词映射到多维空间中的向量表示，用以捕捉语义含义。通过和Embedding结合，这些连续的向量使模型能够在神经网络中处理离散的token，从而使其学习单词之间的复杂关系。

```Python
from transformers import AutoTokenizer

tokenizer = AutoTokenizer.from_pretrained("bert-base-uncased")

inputs = tokenizer("This is the first sentence.", "This is the second one.")

print(inputs)
```

```JSON
{ 
  'input_ids': [101, 2023, 2003, 1996, 2034, 6251, 1012, 102, 2023, 2003, 1996, 2117, 2028, 1012, 102],
  'token_type_ids': [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1],
  'attention_mask': [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
}
```

重点关注一下input_ids字段，该字段中的值即表示分割之后的单词或字符在embedding词汇表中的索引。





**外挂知识库**

大模型功能虽然已经非常强大，但依然存在以下几点不足：

1. 知识不足或信息丢失
2. 训练数据是基于某个时间之前的数据，缺少最新的数据
3. 无法访问私有的文档
4. 基于历史会话中获取信息
5. 对输入的内容长度有限制



基于 Embedding 搜索 + 问答的模式，即RAG，把知识通过 Embedding 后存储到向量数据库，作为长期记忆。提问时首先在向量数据库中搜索相关知识，然后把返回的结果提供给大模型作为输入。进一步也可以针对问题和检索得到的 embedding 做一些提示工程，来优化 ChatGPT 的回答。





**大模型多模态**

思考：文本可以使用embedding表示，图片也可以使用embedding表示，视频同样也可以使用embedding表示，那三者之间是不是可以去求解向量的相似度呢？

虽然他们都可以通过embedding表示，但这并不意味着它们可以直接结合使用。问题在于，这三种模态的向量是在不同的向量空间中学习并训练得到的，它们各自对事物的理解存在差异，例如，在图像中“小狗”的Embedding和文本中“小狗”的Embedding在两种模态中的表示可能截然不同。这就引出了一个重要的概念——**模态对齐**。

![照片 @@@@ 图片展示了一只白色的狗躺在草地上，旁边有一个红色飞盘。图片左侧文字为“A dog lying on the grass next to a frisbee”。右侧为从图片到语言的模型结构示意，包括语言模型、连接模块和视觉编码器。](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=MjY3NGNmNTcxY2Y2NzE1ODhiYzM0NmIyZjI5ZmM4ZjFfNzE1ZGZiMDg3MmYzNDU0ZGY0Y2QzMTEyNGZjMDBhMzZfSUQ6NzM2ODY4MDIyODg0MzkxMzIxOV8xNzg1MTMzOTI1OjE3ODUxMzc1MjVfVjM)





# 练习题

https://colab.research.google.com/drive/1N7HELWImK9xCYheyozVP3C_McbiRo1nb#scrollTo=knWTPeFGvCVr
