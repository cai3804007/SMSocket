//
//  SMSocket.m
//  XiaoHaIM
//
//  Created by xiaoha on 2018/9/17.
//  Copyright © 2018年 xuewei. All rights reserved.
//

#define SMSocketSyncQueue "SMSocketSyncQueue"
#define SMSocketReadQueue "SMSocketReadQueue"
#define SMSocketWriteQueue "SMSocketWriteQueue"
#define headerLength 4
#define SOCKET_NULL -1
#define Connect_Failed -1
#define PTHREAD_NULL -1
#define ConnectTimeOut 10

#define ProtoBt 4 //自定义协议，自己设置，比如此例子 4字节+ 4字节+ body

#import "SMSocket.h"

enum Net_Ipvtype {
    Net_IpvNull=1,
    Net_Ipv4,
    Net_Ipv6,
};


@interface ReadCacheBuffer()

@end

@implementation ReadCacheBuffer

- (instancetype)init {
    if (self = [super init]) {
        needReadSize = 1;
        tempBuffer = NULL;
        startBuffer = NULL;
        _readHeaderType = Read_TOP;
        cirleStop = NO;
        maxReadSize = 8*1024;
    }
    return self;
}

- (void)clearReadCahce{
    needReadSize = ProtoBt;
    tempBuffer = NULL;
    bodyLength = 0;
    _readHeaderType = Read_TOP;
    cirleStop = NO;
}

@end

@interface ReadPacket()
@end

@implementation ReadPacket

- (instancetype)initReadPacketData:(NSMutableData *)data Length:(NSUInteger)length type:(int)headtype{
    if(self = [super init])
    {
        type = headtype;
        bodyBuffer = [data mutableCopy];
        dataLength = length;
        isDone = NO;
    }
    return self;
}

@end

@interface SMSocket()
@property (nonatomic ,assign) int socketFD;
@property (nonatomic ,assign) int Net_IpvNull;
@property (nonatomic ,strong) NSString *host;
@property (nonatomic ,strong) NSString *port;
@property (nonatomic ,strong) ReadPacket *readPacketBuffer;
@property (nonatomic ,strong) dispatch_queue_t socketQueue;
@property (nonatomic ,strong) dispatch_queue_t readChanelQueue;
@property (nonatomic ,strong) dispatch_queue_t writeChanelQueue;
@property (nonatomic ,strong) NSMutableArray *readBufferQueue;
@property (nonatomic ,strong) NSMutableArray *writeBufferQueue;
@property (nonatomic ,strong) ReadCacheBuffer *readCacheBuffer;

@end

@implementation SMSocket {
    char *buffer;
    uint8_t *curReadoffer;
    uint8_t *startBufferPoint;
    NSUInteger readCount;
    size_t readMax;
    size_t writeMax;
    BOOL isTopRes;
    int _readLenght;
    int tryConnect;
    FILE *file;
}

- (instancetype)init {
    if (self = [super init]) {
        self.socketQueue = dispatch_queue_create("sm.Socket.Queue", DISPATCH_QUEUE_SERIAL);
#if OS_OBJECT_USE_OBJC
        dispatch_queue_set_specific(_socketQueue, SMSocketSyncQueue, (__bridge void *)self, NULL);
#endif
        //读队列
        self.readChanelQueue = dispatch_queue_create("sm.Read.Queue", DISPATCH_QUEUE_SERIAL);
#if OS_OBJECT_USE_OBJC
        dispatch_queue_set_specific(_readChanelQueue, SMSocketReadQueue, (__bridge void *)self, NULL);
#endif
        //写队列
        self.writeChanelQueue = dispatch_queue_create("sm.Write.Queue", DISPATCH_QUEUE_SERIAL);
#if OS_OBJECT_USE_OBJC
        dispatch_queue_set_specific(_writeChanelQueue, SMSocketWriteQueue, (__bridge void *)self, NULL);
#endif
        //读缓存窗口
        self.readCacheBuffer = [[ReadCacheBuffer alloc] init];
        readMax = 1024*8; //最大读缓存
        buffer = (char*)malloc(readMax);
        self.readBufferQueue = [[NSMutableArray alloc] init];
        self.writeBufferQueue = [[NSMutableArray alloc] init];
        isTopRes = YES;
        _readLenght =1;
    }
    return self;
}

//创建套接字和地址

- (void)CreateSocketWithHost:(NSString *)host port:(NSString *)port {
    _host = host;
    _port = port;
    struct addrinfo hints, *res, *res0;
    
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = PF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    const char *serverPort = [port UTF8String];
    const char *serverHost = [host UTF8String];
    
    int gai_error = getaddrinfo(serverHost, serverPort, &hints, &res0); //获取网络地址
    
    if (gai_error) {
        [self.delegate didGetAddrInfoFailed:[self showErrMessage:@"getAddrInfoFaild"]];
    } else {
        self.socketFD = SOCKET_NULL;
        struct addrinfo* resultInfo = NULL;
        for (res = res0; res; res = res->ai_next) {
            if (res->ai_family == AF_INET) {
                
                int tempSocket = createIpv4Socket(res); //ipv4
                if (tempSocket != SOCKET_NULL) {
                    _socketFD = tempSocket;
                    resultInfo = res;
                    break;
                }
            }
            
            if (res->ai_family == AF_INET6) {  //ipv6
                int tempSocket = createIpv6Socket(res);
                if (tempSocket != SOCKET_NULL) {
                    _socketFD = tempSocket;
                    resultInfo = res;
                    break;
                }
            }
        }
        
        if (resultInfo) {
            tryConnect = 0;
            if (resultInfo->ai_addrlen >0) {
                NSData *addInfo = [NSData dataWithBytes:resultInfo->ai_addr length:resultInfo->ai_addrlen];
                [self createConnectPthread:addInfo]; //链接connect
            }
            freeaddrinfo(res0);
        } else {
            tryConnect ++;
            if (tryConnect == 3) {
                tryConnect = 0;
                freeaddrinfo(res0);
                return;
            }
            self.socketFD = SOCKET_NULL;
            freeaddrinfo(res0);
            [self.delegate didReadError:0];
            NSLog(@"Get AddInfo Faild");
        }
        if (_socketFD != SOCKET_NULL) {
            
        } else {
            perror("error");
        }
    }
}

//createIPV4
int createIpv4Socket(struct addrinfo* resultInfo) {
    int socketFD = socket(AF_INET, SOCK_STREAM, 0);
    if (socketFD == SOCKET_NULL) {
        return socketFD;
    }
    int one = 1;
    if (setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) < 0) { //端口复用
        close(socketFD);
        return SOCKET_NULL;
    }
    int nosigpipe = 1;
    setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, sizeof(nosigpipe)); //忽略sipiple信号
    return socketFD;
};

int createIpv6Socket(struct addrinfo* resultInfo) {
    int socketFD = socket(AF_INET6, SOCK_STREAM, 0);
    
    if (socketFD == SOCKET_NULL) {
        return socketFD;
    }
    
    struct sockaddr_in clientAddr;
    clientAddr.sin_family = AF_INET6;
    
    const struct sockaddr *interAddr = (const struct sockaddr *)resultInfo;
    int bindResult = bind(socketFD, interAddr, (socklen_t)interAddr->sa_len);
    
    if (bindResult != 0) {
        close(socketFD);
        return SOCKET_NULL;
    }
    
    int nosigpipe = 1;
    setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, sizeof(nosigpipe));
    return socketFD;
};

//超时处理

- (int)connectTimerOut:(NSData *)data {
    int selectVal;
    struct timeval tm;
    fd_set sockfd_set;
    int error = -1;
    int len;
    int ret = 0;
    
    //为设置超时时间，套接字阻塞->非阻塞
    if (fcntl(self->_socketFD, F_SETFL, fcntl(self->_socketFD, F_GETFL) | O_NONBLOCK)<0) {
        NSLog(@"FCNTL Error");
        return Connect_Failed;
    }
    
    //建立三路握手
    int connected = connect(self->_socketFD, (const struct sockaddr *)[data bytes], (socklen_t)[data length]);
    
    if (connected >=0) {
        fcntl(self->_socketFD, F_SETFL, fcntl(self->_socketFD, F_GETFL) &~ O_NONBLOCK);
        return 1;
    }
    
    if (errno != EINPROGRESS) {
        perror("connect Failed");
        fcntl(self->_socketFD, F_SETFL, fcntl(self->_socketFD, F_GETFL) &~ O_NONBLOCK);
        return Connect_Failed;
    }
    
    //设置connect阻塞时间
    tm.tv_sec = ConnectTimeOut;
    tm.tv_usec = 0;
    
    FD_ZERO(&sockfd_set);
    FD_SET(self->_socketFD,&sockfd_set);
    
    //select是阻塞式，阻塞时间内返回
    selectVal = select(self->_socketFD + 1, NULL, &sockfd_set, NULL, &tm);
    switch (selectVal) {
        case -1: {
            NSLog(@"Get Select Connect Failed");
            ret = Connect_Failed;
        }
        case 0: {
            ret = Connect_Failed;
            NSLog(@"Time Out To Connect Failed");
        }
            break;
        default: {
            if(FD_ISSET(self->_socketFD,&sockfd_set)) {
                if(getsockopt(self->_socketFD, SOL_SOCKET, SO_ERROR, &error, (socklen_t *)&len) < 0) {
                    ret = Connect_Failed;
                }
                NSLog(@"error=%d\n",error);
                if(error == 0) {
                    ret = 1;
                }
                else {
                    ret = 0;
                    errno = error;
                    NSLog(@"error=%d\n",error);
                }
            }
        }
            break;
    }
    //套接字非阻塞->阻塞
    fcntl(self->_socketFD, F_SETFL, fcntl(self->_socketFD,F_GETFL) &~ O_NONBLOCK);
    return ret;
}

//连接

- (void)createConnectPthread:(NSData *)data {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool{
            NSLog(@"GETGETconnect success");
            int ret = [self connectTimerOut:data];
            if(ret < 1) {
                close(self->_socketFD);
                self->_socketFD = SOCKET_NULL;
                [self.delegate didConnectSocketFailed:[self showErrMessage:@"Connect Server Faild"]];
                return;
            }
            
            self->file = fdopen (self->_socketFD, "w+");
            NSLog(@"connect success");
            [self.delegate didConnectSocketSuccess:self->_socketFD];
            
            [self.readCacheBuffer clearReadCahce];
            memset(self->buffer, 0, self->readMax);
            self.readCacheBuffer->tempBuffer = self->buffer;
            self.readCacheBuffer->startBuffer = self->buffer;
            while(1) {
                int cnt = (int) read(self->_socketFD, self.readCacheBuffer->tempBuffer,self.readCacheBuffer->needReadSize);
                if(cnt >0) {
                    switch (self.readCacheBuffer->_readHeaderType) {
                        case Read_TOP: {
                            char s[5];
                            memset(s, 0, 5);
                            sprintf(s, "%d", self.readCacheBuffer->tempBuffer[1]);
                            int byte = s[0]-48;
                            self.readCacheBuffer->type = byte; //类型
                            self.readCacheBuffer->totalSize += ProtoBt; //以下读缓存指针偏移
                            self.readCacheBuffer->tempBuffer += ProtoBt;
                            self.readCacheBuffer->startBuffer += ProtoBt;
                            if (byte == 0) {
                                //pingpong 类型
                                self.readCacheBuffer->_readHeaderType = Read_TOP;
                                self.readCacheBuffer->tempBuffer += ProtoBt;
                                self.readCacheBuffer->startBuffer += ProtoBt;
                                NSMutableData *bufferData = [NSMutableData dataWithBytes:self.readCacheBuffer->tempBuffer length:ProtoBt];
                                ReadPacket *packet = [[ReadPacket alloc] initReadPacketData:bufferData Length:ProtoBt type:0];
                                self.readCacheBuffer->type = 999;
                                [self reciveMessage:packet];
                                continue;
                            } else if (byte == ProtoBt){
                                self.readCacheBuffer->_readHeaderType = Read_Lenght;
                            }
                        }
                            break;
                        case Read_Lenght: {
                            unsigned int byte = ((short)(self.readCacheBuffer->tempBuffer[0] & 0x000000ff) << 8) + (self.readCacheBuffer->tempBuffer[1] & 0x000000ff);
                            self.readCacheBuffer->totalSize += ProtoBt; //以下读缓存指针偏移
                            self.readCacheBuffer->tempBuffer += ProtoBt;
                            self.readCacheBuffer->startBuffer += ProtoBt;
                            self.readCacheBuffer->needReadSize = byte;  //算出bodylength大小
                            if ((self->readMax -self.readCacheBuffer->totalSize) < byte) { //读缓存空间不够，扩大缓存
                                NSLog(@"rellloc Memory XXX");
                                [self reallocReadBufferMemory:byte];
                            }
                            self.readCacheBuffer->bodyLength = byte;
                            self.readCacheBuffer->_readHeaderType = Read_Body;
                        }
                            break;
                        case Read_Body: {
                            if (cnt < self.readCacheBuffer->needReadSize) { //读缓冲区空间不够，一次返回不完，循环读取
                                self.readCacheBuffer->needReadSize -=cnt;
                                self.readCacheBuffer->tempBuffer +=cnt;
                                self.readCacheBuffer->_readHeaderType = Read_Body;
                                continue;
                            }
                            self.readCacheBuffer->_readHeaderType = Read_TOP;
                            NSMutableData *bufferData = [NSMutableData dataWithBytes:self.readCacheBuffer->startBuffer length:self.readCacheBuffer->bodyLength];
                            //封装body
                            ReadPacket *packet = [[ReadPacket alloc] initReadPacketData:bufferData Length:self.readCacheBuffer->bodyLength type:self.readCacheBuffer->type];
                            self.readCacheBuffer->type = 999;
                            
                            [self reciveMessage:packet]; //读到的数据包传输出去
                            self.readCacheBuffer->totalSize +=cnt;
                            self.readCacheBuffer->tempBuffer +=cnt;
                            self.readCacheBuffer->startBuffer = self.readCacheBuffer->tempBuffer;
                            self.readCacheBuffer->needReadSize = ProtoBt;
                            
                            if (self.readCacheBuffer->cirleStop == YES) {
                                [self clearReadMemory];
                            }
                        }
                            break;
                        default:
                            break;
                    }
                    //正常处理数据
                } else if (cnt ==0) { //对端关闭socket
                    close(self->_socketFD);
                    self->_socketFD = SOCKET_NULL;
                    [self.delegate didReadError:0];
                    NSLog(@"close close close");
                    break;
                } else {
                    if((cnt<0) &&(errno == EAGAIN||errno == EWOULDBLOCK||errno == EINTR)) {
                        continue;
                    }
                    NSLog(@" -1 -1 -1close close close");
                    //close(self->_socketFD);
                    //self->_socketFD = SOCKET_NULL;
                    //  [self.delegate didReadError:-1];
                    break;
                }
            }
        }
    });
};

//重新申请内存
- (void)reallocReadBufferMemory:(unsigned int) bytes {
    NSLog(@"realloc IM Memory");
    size_t freeSize =  readMax - self.readCacheBuffer->totalSize;
    size_t needSize = bytes - freeSize +100;
    self.readCacheBuffer->cirleStop = YES;
    self.readCacheBuffer->maxReadSize = readMax +needSize;
    char *newSizeBuffer = realloc(self->buffer,readMax +needSize);
    if (newSizeBuffer) {}else {
        NSLog(@"realloc IM Memory Failed");
    }
    self->buffer = newSizeBuffer;
    self.readCacheBuffer->tempBuffer = (self->buffer +self.readCacheBuffer->totalSize);
    self.readCacheBuffer->startBuffer = self.readCacheBuffer->tempBuffer;
}

//清缓存
- (void)clearReadMemory {
    NSLog(@"clearReadMemory MM");
    memset(self->buffer, 0, self.readCacheBuffer->maxReadSize);
    char *newSizeBuffer = realloc(self->buffer,readMax);
    if (!newSizeBuffer) {
        self.readCacheBuffer->tempBuffer = self->buffer;
        self.readCacheBuffer->startBuffer = self->buffer;
        self.readCacheBuffer->totalSize = 0;
    } else {
        self->buffer = newSizeBuffer;
        self.readCacheBuffer->tempBuffer = self->buffer;
        self.readCacheBuffer->startBuffer = self->buffer;
        self.readCacheBuffer->totalSize = 0;
        self.readCacheBuffer->cirleStop = NO;
    }
    self.readCacheBuffer->_readHeaderType = Read_TOP;
    self.readCacheBuffer->needReadSize = ProtoBt;
    self.readCacheBuffer->bodyLength = 0;
}

- (void)checkBufferAvalableMemory {
    if (self.readCacheBuffer->totalSize  > 1024*5) {
        memset(self->buffer, 0, 8*1024);
        self.readCacheBuffer->tempBuffer = self->buffer;
    }
}

#pragma --send--recieve--

- (void)reciveMessage:(ReadPacket *)packet {
    if (dispatch_get_specific(SMSocketReadQueue)) {
        [self.delegate didRecieveMessageData:packet];
    }
    else {
        dispatch_sync(_readChanelQueue, ^{
            [self.delegate didRecieveMessageData:packet];
        });
    }
}

- (void)sendMessage:(char *)data lenght:(size_t)length {
    if (dispatch_get_specific(SMSocketWriteQueue)) {
        [self writeSocketData:data size:length];
    }
    else {
        dispatch_async(_writeChanelQueue, ^{
            [self writeSocketData:data size:length];
        });
    }
}

- (void)writeSocketData:(char *)data size:(size_t)size {
    int cnt = (int)write(self->_socketFD, data, size);
    fflush(self->file);
    if (cnt < 0) {
        int code = errno;
        [self.delegate didSendMessageFailed:code];
    }
}

#pragma --reconnect--

- (void)resetConnectSocket:(NSString *)host port:(NSString *)port {
    if (_socketFD != SOCKET_NULL) {
        close(_socketFD);
        self.socketFD = SOCKET_NULL;
        [self clearReadMemory];
        [self.readCacheBuffer clearReadCahce];
        [self CreateSocketWithHost:host port:port];
    }
}

- (void)closeSocket {
    if (self.socketFD != SOCKET_NULL) {
        close(self.socketFD);
        self.socketFD = SOCKET_NULL;
        [self clearReadMemory];
        [self.readCacheBuffer clearReadCahce];
    }
}

- (NSError *)showErrMessage:(NSString *)string {
    NSError *error = [NSError errorWithDomain:string code:-1 userInfo:nil];
    return error;
}

@end

