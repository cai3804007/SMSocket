# SMSocket
轻量级IM网络框架，基于BSD Socket，适用于自定义IM网络协议开发

IM业务一般分为网络层 网络和业务交合的协议层 和业务层，协议层各个公司自己定义，业务层每个人有自己写法，建议MVVM
网络层没有使用著名的GCGSyncsocket，
1此库强大但臃肿，大部分功能我们用不到
2自定义协议程度较高，需要与之适配的网络层写法
3三方网络库有问题不好定位
因此需要自己写网络层

比如收到一段字节流，可以判断前n个字节判断消息类型，再n个字节判断消息body长度，然后读取body长度的消息体去解析，如Read_HeaderType

整体架构图如图：![image](https://github.com/SoulApp/SMSocket/blob/master/SMSocket/tttttt.png)
