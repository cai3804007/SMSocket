//
//  SMSocket.h
//  XiaoHaIM
//
//  Created by xiaoha on 2018/9/17.
//  Copyright © 2018年 xuewei. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <time.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <stdio.h>
#include <arpa/inet.h>
#include <pthread.h>
#include<stdlib.h>
#include<fcntl.h>

@class GCDAsyncReadPacket;
enum Read_HeaderType
{
    Read_TOP=1,
    Read_Lenght,
    Read_Body,
};
//extern NSString *const soulSocketSyncQueue;
@interface ReadCacheBuffer :NSObject{
@public
    size_t needReadSize;
    char *tempBuffer;
    char *startBuffer;
    enum Read_HeaderType _readHeaderType;
    BOOL cirleStop;
    char *bodyBuffer;
    size_t bodyLength;
    int type;
    size_t totalSize;
    size_t maxReadSize;
}

@end

@interface ReadPacket :NSObject {
@public
    NSMutableData *bodyBuffer;
    NSUInteger dataLength;
    BOOL isDone;
    int type;
}

- (instancetype)initReadPacketData:(NSMutableData *)data Length:(NSUInteger)length type:(int)headtype;
@end



@protocol SMSocketDelegate <NSObject>
@optional
/*
 获取地址
 */
- (void)didGetAddrInfoFailed:(NSError *)error;

/*
 三路握手失败
 */
- (void)didConnectSocketFailed:(NSError *)error;

/*
 发送失败
 */
- (void)didSendMessageFailed:(int)code;

/*
 三路握手成功
 */
- (void)didConnectSocketSuccess:(int)socketFD;

/*
 接收数据代理
 */
- (void)didRecieveMessageData:(ReadPacket *)packet;

/*
 读报错
 */
- (void)didReadError:(NSInteger)errorCode;
@end

@interface SMSocket : NSObject
@property (nonatomic ,weak) id <SMSocketDelegate>delegate;

/*
 创建套接字并连接
 */
- (void)CreateSocketWithHost:(NSString *)host port:(NSString *)port;

/*
 发数据
 */
- (void)sendMessage:(char *)data lenght:(size_t)length;

- (void)closeSocket;

/*
 重连
 */
- (void)resetConnectSocket:(NSString *)host port:(NSString *)port;
@end

